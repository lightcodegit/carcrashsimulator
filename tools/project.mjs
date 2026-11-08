#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { cp, mkdir, mkdtemp, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { availableParallelism, tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripVTControlCharacters } from 'node:util';

export const ROOT = fileURLToPath(new URL('../', import.meta.url));
const GODOT_VERSION = '4.7.2';
const COMMANDS = ['import', 'test', 'build', 'run'];
// Тесты, утверждающие бюджет в миллисекундах (сборка карты, пересборка вмятин):
// соседние Godot-инстансы делят ядра и раздувют замер до ложного FAIL. Они идут
// первыми строго по одному, весь остальной набор — пулом (см. ветку test).
const SERIAL_TESTS = ['d_bigcity_density', 'h_crash', 'h_dents'];
const EXCLUSIONS = {
  h_embed_guard: 'Requires a live editor-owned host window and --wid; headless cannot test embedding.',
  h_fullscreen: 'Requires a live window to verify fullscreen transitions and restored geometry.',
  h_pixelscale: 'Requires a live window to measure the physical screen pixel grid.',
  h_picture: 'Requires GPU-rendered frames to measure brightness; no rendering in headless.',
};

export function parseArgs(argv, env = process.env) {
  const result = { command: null, godot: env.GODOT || 'godot', tests: [], help: false, list: false, failOnSkip: false };
  const positional = [];
  const used = new Set();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith('-')) { positional.push(arg); continue; }
    used.add(arg);
    if (arg === '--help' || arg === '-h') result.help = true;
    else if (arg === '--list') result.list = true;
    else if (arg === '--fail-on-skip') result.failOnSkip = true;
    else if (['--godot', '--test', '--timeout', '--jobs'].includes(arg)) {
      const value = argv[++i];
      if (!value?.trim() || value.startsWith('-')) throw new Error(`${arg} requires a value.`);
      if (arg === '--godot') result.godot = value;
      if (arg === '--test') result.tests.push(value);
      if (arg === '--jobs') {
        const workers = Number(value);
        if (!Number.isInteger(workers) || workers < 1 || workers > 32) {
          throw new Error('--jobs must be an integer 1–32.');
        }
        result.jobs = workers;
      }
      if (arg === '--timeout') {
        const seconds = Number(value);
        if (!Number.isFinite(seconds) || seconds < 0.001 || seconds * 1000 > 2147483647) {
          throw new Error('--timeout must be positive seconds (0.001–2147483.647).');
        }
        result.timeoutMs = Math.ceil(seconds * 1000);
      }
    } else throw new Error(`Unknown option: ${arg}`);
  }
  if (positional[0] === 'help') { positional.shift(); result.help = true; }
  result.command = positional.shift() || null;
  if (result.command && !COMMANDS.includes(result.command)) throw new Error(`Unknown command: ${result.command}`);
  if (!result.command) {
    if ([...used].some(x => !['--help', '-h'].includes(x))) throw new Error('A command is required.');
    result.help = true;
  }
  if (result.command === 'build') {
    result.platform = positional.shift();
    if ((!result.platform && !result.help) || (result.platform && !['windows', 'linux'].includes(result.platform))) {
      throw new Error('build requires a platform: windows or linux.');
    }
  }
  if (positional.length) throw new Error(`Unexpected argument: ${positional[0]}`);
  if (result.command !== 'test' && (result.list || result.failOnSkip || result.tests.length || used.has('--jobs'))) {
    throw new Error('--test, --list, --jobs and --fail-on-skip are test-only options.');
  }
  result.timeoutMs ??= result.command === 'run' ? 3600000 : result.command === 'test' ? 120000 : 300000;
  return result;
}

function help(command) {
  const common = '\nOptions: --godot PATH (or GODOT environment variable), --timeout SECONDS, --help\nNode >=22; Godot 4.7.2 standard editor (not .NET). Logs: artifacts/logs/.\n';
  const details = {
    import: 'import  Import resources headlessly and exit. Default wall timeout: 300 seconds.',
    test: 'test [--test EXACT_NAME ...] [--jobs N] [--list] [--fail-on-skip]\nRuns discovered d_*.gd / h_*.tscn headlessly at fixed 60 FPS, each with fresh user storage.\nTests run in parallel: default is half the CPU cores capped at 4; --jobs 1 restores serial order.\nWall-clock budget tests (d_bigcity_density, h_crash, h_dents) always run strictly one at a time, first.\nDefault wall timeout: 120 seconds per test. Import first.\nNOTE is informational; PARTIAL/SKIP means partial coverage; unsupported tests are skipped with reasons.\n--fail-on-skip rejects skipped AND partial results. --list does not launch Godot.',
    build: 'build windows|linux  Import and release-export a temporary staging project.\nRequires matching 4.7.2.stable export templates. Default timeout: 300 seconds per process.\nUses tools/export_presets.cfg, never your local preset. Output: artifacts/build/<platform>/.',
    run: 'run  Launch the game GUI using your normal player settings.\nOnly this command opens a window. Default wall timeout: 3600 seconds; close normally to exit.',
  };
  return `Usage: node tools/project.mjs ${command ? details[command] : '<import|test|build|run> [options]\n       node tools/project.mjs help <command>'}\n${common}`;
}

export function classifyTest(result) {
  const text = stripVTControlCharacters(`${result.stdout}\n${result.stderr}`);
  const reasons = [];
  if (result.error) reasons.push(`Process error: ${result.error}`);
  if (result.timedOut) reasons.push('Wall-clock timeout exceeded.');
  if (result.exitCode !== 0 || result.signal) reasons.push(`Exit: ${result.exitCode}, signal: ${result.signal || 'none'}`);
  if (/\bSCRIPT ERROR\b|\bFAIL(?:S|ED|URE)?\b/.test(text)) reasons.push('SCRIPT ERROR or FAIL detected.');
  if (!/^ALL PASS\r?$/m.test(text)) reasons.push('Missing standalone ALL PASS completion marker.');
  const notes = text.match(/^\s*(?:PARTIAL|SKIP)\b[^\r\n]*/gm)?.map(x => x.trim()) || [];
  return { status: reasons.length ? 'failed' : notes.length ? 'partial' : 'passed', reasons: [...reasons, ...notes] };
}

export function summarize(entries, failOnSkip = false) {
  const counts = { passed: 0, partial: 0, skipped: 0, failed: 0 };
  for (const entry of entries) counts[entry.status]++;
  return { ...counts, exitCode: !entries.length || counts.failed || (failOnSkip && (counts.skipped || counts.partial)) ? 1 : 0 };
}

export async function discoverTests(directory = path.join(ROOT, 'tests')) {
  const found = [];
  async function visit(dir, prefix = '') {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const relative = `${prefix}${entry.name}`;
      if (entry.isDirectory() && !entry.name.startsWith('.') && !['out', 'tmpappdata'].includes(entry.name)) {
        await visit(path.join(dir, entry.name), `${relative}/`);
      } else if (entry.isFile() && /^(d_.*\.gd|h_.*\.tscn)$/.test(entry.name)) {
        const name = relative.replace(/\.(gd|tscn)$/, '');
        found.push({ name, file: relative, skipReason: EXCLUSIONS[name] });
      }
    }
  }
  await visit(directory);
  return found.sort((a, b) => a.name.localeCompare(b.name, 'en'));
}

export function selectTests(entries, names) {
  for (const name of names) {
    if (!entries.some(x => x.name === name)) throw new Error(`Unknown test: ${name}. Use test --list (exact names, without extension).`);
  }
  return names.length ? entries.filter(x => names.includes(x.name)) : entries;
}

export function isolatedEnvironment(directory, parent = process.env, platform = process.platform) {
  const p = platform === 'win32' ? path.win32 : path.posix;
  const replacements = {
    HOME: directory, USERPROFILE: directory,
    APPDATA: p.join(directory, 'AppData', 'Roaming'), LOCALAPPDATA: p.join(directory, 'AppData', 'Local'),
    XDG_DATA_HOME: p.join(directory, '.local', 'share'), XDG_CONFIG_HOME: p.join(directory, '.config'),
    XDG_CACHE_HOME: p.join(directory, '.cache'), XDG_STATE_HOME: p.join(directory, '.local', 'state'),
    XDG_RUNTIME_DIR: p.join(directory, 'runtime'),
    TMPDIR: p.join(directory, 'tmp'), TMP: p.join(directory, 'tmp'), TEMP: p.join(directory, 'tmp'),
  };
  if (platform === 'win32') {
    replacements.HOMEDRIVE = p.parse(directory).root.replace(/[\\/]$/, '');
    replacements.HOMEPATH = directory.slice(replacements.HOMEDRIVE.length);
  }
  const env = Object.fromEntries(Object.entries(parent).filter(([key]) => !(key.toUpperCase() in replacements)));
  return { ...env, ...replacements };
}

export async function withIsolation(callback) {
  const directory = await mkdtemp(path.join(tmpdir(), 'ccs-user-'));
  try {
    const env = isolatedEnvironment(directory);
    for (const key of ['APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'TMPDIR']) {
      await mkdir(env[key], { recursive: true, mode: 0o700 });
    }
    return await callback(env);
  } finally {
    await rm(directory, { recursive: true, force: true, maxRetries: 3 });
  }
}

// Исполняемый файл ищется в PATH, а не «где окажется». Это не косметика:
// spawn(..., {shell:false}) на Windows дополняет поиск текущим каталогом, и
// godot.exe, положенный в клон репозитория, запускался бы вместо редактора из
// PATH — а последующая проверка версии подделку пропускала бы.
export function resolveExecutable(nameOrPath, {
  env = process.env, cwd = ROOT, platform = process.platform, root = ROOT, exists = existsSync,
} = {}) {
  if (/[\\/]/.test(nameOrPath)) {
    const abs = path.isAbsolute(nameOrPath) ? nameOrPath : path.resolve(root, nameOrPath);
    if (!exists(abs)) {
      throw new Error(`Godot не найден по пути: ${abs}. Передайте --godot PATH.`);
    }
    return abs;
  }
  const exts = platform === 'win32'
    ? (env.PATHEXT || '.EXE;.CMD;.BAT;.COM').split(';').map(x => x.toLowerCase())
    : [''];
  const dirs = String(env.PATH || '').split(path.delimiter).filter(Boolean);
  for (const dir of dirs) {
    for (const ext of exts) {
      const candidate = path.join(dir, nameOrPath + ext);
      if (exists(candidate)) return candidate;
    }
  }
  throw new Error(
    `Godot (${nameOrPath}) не найден в PATH. Установите 4.7.2 stable и передайте --godot PATH или GODOT.`);
}

export function runProcess(executable, args, { cwd = ROOT, env = process.env, timeoutMs = 120000, spawnImpl = spawn, maxOutputBytes = 8 * 1024 * 1024 } = {}) {
  return new Promise(resolve => {
    const start = Date.now();
    const result = { stdout: '', stderr: '', exitCode: null, signal: null, timedOut: false, error: null, truncated: false };
    // Потолок на поток: зациклившийся тест не должен выедать память раннера и
    // раздувать лог. Факт усечения записывается, чтобы молчаливая потеря вывода
    // не выглядела как «такого просто не было».
    const collect = (stream, key) => {
      stream.setEncoding('utf8');
      stream.on('data', data => {
        if (result[key].length >= maxOutputBytes) { result.truncated = true; return; }
        result[key] += data;
        if (result[key].length > maxOutputBytes) {
          result[key] = result[key].slice(0, maxOutputBytes) + '\n… вывод обрезан по лимиту раннера …';
          result.truncated = true;
        }
      });
    };
    let timer;
    const finish = () => { clearTimeout(timer); resolve({ ...result, durationMs: Date.now() - start }); };
    let child;
    try {
      child = spawnImpl(executable, args, { cwd, env, shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (error) { result.error = error.message; finish(); return; }
    collect(child.stdout, 'stdout');
    collect(child.stderr, 'stderr');
    child.on('error', error => { result.error = error.message; });
    child.on('close', (code, signal) => { result.exitCode = code; result.signal = signal; finish(); });
    timer = setTimeout(() => {
      result.timedOut = true;
      child.kill('SIGKILL');
    }, timeoutMs);
  });
}

// Root files that are not Godot resources but must travel with the build: a
// player who unpacks only the .pck has to see the grant the code ships under.
const STAGE_ROOT_FILES = ['LICENSE'];

export async function stageProject(source, destination) {
  await mkdir(destination, { recursive: true });
  // Whitelist includes dynamically loaded assets, not just main-scene dependencies.
  for (const entry of ['project.godot', 'assets', 'scenes', 'scripts']) {
    await cp(path.join(source, entry), path.join(destination, entry), { recursive: true });
  }
  // Missing here means silently missing in every release, so an absent optional
  // file (a fork without LICENSE) is skipped rather than failing the build.
  for (const entry of STAGE_ROOT_FILES) {
    const from = path.join(source, entry);
    if (existsSync(from)) await cp(from, path.join(destination, entry));
  }
  await cp(path.join(source, 'tools', 'export_presets.cfg'), path.join(destination, 'export_presets.cfg'));
}

function requireSuccess(result, label) {
  const text = stripVTControlCharacters(`${result.stdout}\n${result.stderr}`);
  if (result.error || result.timedOut || result.exitCode !== 0 || result.signal || /^(?:SCRIPT )?ERROR:/m.test(text)) {
    throw new Error(`${label} failed: ${result.error || (result.timedOut ? 'wall-clock timeout' : `exit ${result.exitCode}; see log`)}.`);
  }
}

async function main() {
  let options;
  let selected;
  try {
    if (Number(process.versions.node.split('.')[0]) < 22) throw new Error('Node.js >=22 is required.');
    options = parseArgs(process.argv.slice(2));
    if (options.help) { console.log(help(options.command)); return 0; }
    if (options.command === 'test') {
      selected = selectTests(await discoverTests(), options.tests);
      if (!selected.length) throw new Error('No tests discovered.');
      if (options.list) {
        for (const entry of selected) console.log(`${entry.name}${entry.skipReason ? ` [SKIP: ${entry.skipReason}]` : ''}`);
        return 0;
      }
    }
  } catch (error) { console.error(error.message); return 2; }

  const logs = path.join(ROOT, 'artifacts', 'logs');
  await mkdir(logs, { recursive: true });
  const reportDir = await mkdtemp(path.join(logs, `${new Date().toISOString().replace(/[:.]/g, '-')}-${options.command}-`));
  const report = { command: options.command, platform: process.platform, target: options.platform, startedAt: new Date().toISOString(), processes: [], tests: [], exitCode: 1 };
  const executable = resolveExecutable(options.godot, { env: process.env, root: ROOT });
  // Номер лога выдаётся синхронно до первого await: при параллельном пуле
  // счётчик report.processes.length гонял бы два теста на одно имя файла.
  let logCounter = 0;
  async function execute(label, args, overrides = {}) {
    const log = `${String(logCounter++).padStart(3, '0')}-${label.replace(/[^a-zA-Z0-9_-]/g, '_')}.log`;
    const result = await runProcess(executable, args, { timeoutMs: options.timeoutMs, ...overrides });
    await writeFile(path.join(reportDir, log), `${JSON.stringify({ executable, args })}\n--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}\n`);
    const { stdout, stderr, ...metadata } = result;
    report.processes.push({ label, args, log, ...metadata });
    return result;
  }
  try {
    const version = await execute('version', ['--version']);
    requireSuccess(version, 'Godot version check (use --godot PATH or GODOT)');
    report.godotVersion = version.stdout.trim();
    if (!/^4\.7\.2\.stable(?:\.|$)/.test(report.godotVersion)) {
      throw new Error(`Expected Godot ${GODOT_VERSION}.stable; found ${report.godotVersion}. Install the matching standard editor and templates.`);
    }
    if (options.command === 'test') {
      // Пул воркеров: каждый тест уже изолирован своим temp-APPDATA и своим
      // процессом Godot, поэтому параллельность безопасна. Дефолт — половина
      // ядер, но не больше 4: headless-инстанс ест CPU, а не GPU, и чрезмерный
      // оверсабскрипт только замедляет замеры времени в p_*-тестах.
      const jobs = Math.max(1, Math.min(
        options.jobs ?? Math.max(1, Math.min(4, availableParallelism() >> 1)),
        selected.length));
      report.jobs = jobs;
      const results = new Array(selected.length);
      const slotOf = new Map(selected.map((entry, i) => [entry.name, i]));
      const runOne = async entry => {
        let outcome;
        if (entry.skipReason) outcome = { status: 'skipped', reasons: [entry.skipReason] };
        else {
          const args = ['--headless', '--path', ROOT, '--fixed-fps', '60'];
          if (entry.file.endsWith('.gd')) args.push('--script');
          args.push(`res://tests/${entry.file}`);
          outcome = await withIsolation(async env => classifyTest(await execute(entry.name, args, { env })));
        }
        results[slotOf.get(entry.name)] = { name: entry.name, ...outcome };
        console.log(`${outcome.status.toUpperCase()} ${entry.name}${outcome.reasons.length ? `: ${outcome.reasons.join(' | ')}` : ''}`);
      };
      // Сначала последовательная полоса тестов с бюджетами времени, затем пул.
      // Перед ней короткая пауза: прогон, стартующий сразу за предыдущим полным,
      // ловил раздутые замеры (1589 мс против заводских 604) на просевших
      // частотах — это шум среды, а не регресс, но лучше его не создавать вовсе.
      await new Promise(resolve => setTimeout(resolve, 2000));
      for (const entry of selected.filter(e => SERIAL_TESTS.includes(e.name))) await runOne(entry);
      const rest = selected.filter(e => !SERIAL_TESTS.includes(e.name));
      let next = 0;
      const worker = async () => {
        while (next < rest.length) {
          const i = next++;
          await runOne(rest[i]);
        }
      };
      await Promise.all(Array.from({ length: jobs }, worker));
      report.tests = results;
      report.summary = summarize(report.tests, options.failOnSkip);
      report.exitCode = report.summary.exitCode;
      console.log(JSON.stringify(report.summary));
    } else if (options.command === 'import') {
      requireSuccess(await withIsolation(env => execute('import', ['--headless', '--path', ROOT, '--import'], { env })), 'Import');
      report.exitCode = 0;
    } else if (options.command === 'run') {
      requireSuccess(await execute('run', ['--path', ROOT]), 'Game');
      report.exitCode = 0;
    } else {
      const temporary = await mkdtemp(path.join(tmpdir(), 'ccs-build-'));
      try {
        const stage = path.join(temporary, 'project');
        const output = path.join(temporary, 'output');
        await stageProject(ROOT, stage);
        await mkdir(output);
        requireSuccess(await execute('build-import', ['--headless', '--path', stage, '--import']), 'Staging import');
        const windows = options.platform === 'windows';
        const filename = windows ? 'Car Crash Simulator.exe' : 'Car Crash Simulator.x86_64';
        const result = await execute('export', ['--headless', '--path', stage, '--export-release', windows ? 'Windows Desktop' : 'Linux', path.join(output, filename)]);
        try { requireSuccess(result, 'Export'); }
        catch (error) {
          throw new Error(`${error.message} Install Godot ${GODOT_VERSION}.stable export templates via Editor > Manage Export Templates (or the official release .tpz). Local export_presets.cfg is not used.`);
        }
        for (const file of [filename, 'Car Crash Simulator.pck']) {
          const info = await stat(path.join(output, file));
          if (!info.isFile() || info.size === 0) throw new Error(`Export did not produce a nonempty ${file}.`);
        }
        const destination = path.join(ROOT, 'artifacts', 'build', options.platform);
        await rm(destination, { recursive: true, force: true });
        await cp(output, destination, { recursive: true });
        report.output = destination;
        report.exitCode = 0;
        console.log(`Built ${destination}`);
      } finally { await rm(temporary, { recursive: true, force: true, maxRetries: 3 }); }
    }
  } catch (error) {
    report.exitCode = 1;
    report.error = error.message;
    console.error(error.message);
  } finally {
    report.finishedAt = new Date().toISOString();
    await writeFile(path.join(reportDir, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
    console.log(`Report: ${path.join(reportDir, 'report.json')}`);
  }
  return report.exitCode;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().then(code => { process.exitCode = code; }).catch(error => { console.error(error.message); process.exitCode = 1; });
}
