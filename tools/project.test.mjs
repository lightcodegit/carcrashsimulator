import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm, stat, copyFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  ROOT, parseArgs, classifyTest, summarize, discoverTests, selectTests,
  isolatedEnvironment, withIsolation, runProcess, stageProject,
} from './project.mjs';

const ok = { stdout: 'ALL PASS\n', stderr: '', exitCode: 0, signal: null, error: null, timedOut: false };

test('only a complete marker and clean zero exit pass', () => {
  for (const stdout of ['ALL PASS\n', 'Godot banner\r\nALL PASS\r\n', '\u001b[32mALL PASS\u001b[0m\n']) {
    assert.equal(classifyTest({ ...ok, stdout }).status, 'passed');
  }
  for (const change of [
    { stdout: '' }, { stdout: 'not ALL PASS\n' }, { stdout: 'ALL PASS soon\n' },
    { stdout: 'NOTE: nothing ran\n' }, { exitCode: 1 }, { exitCode: null },
    { timedOut: true }, { signal: 'SIGKILL' }, { error: 'ENOENT' },
    { stderr: 'SCRIPT ERROR: assertion failed\n' }, { stderr: 'FAIL: broken\n' },
    { stdout: 'FAILS 1\nALL PASS\n' }, { stdout: 'ALL PASS\nFAIL: late failure\n' },
  ]) assert.equal(classifyTest({ ...ok, ...change }).status, 'failed', JSON.stringify(change));
});

test('informational notes do not reduce coverage', () => {
  const notes = ['NOTE: на town горок нет — проверять нечего',
    'NOTE: endless — те же горки, что на кольце; лента плит двигается, см. h_newmaps'];
  const result = classifyTest({ ...ok, stdout: `${notes.join('\n')}\nALL PASS\n` });
  assert.equal(result.status, 'passed');
  assert.deepEqual(result.reasons, []);
});

test('explicit coverage gaps mean partial coverage, not full passes or hidden failures', () => {
  for (const note of [
    'PARTIAL: кадров не рисовалось (headless) — дрожание не мерилось',
    'PARTIAL: геймпад не подключён — проверялась только клавиатура',
    'SKIP (headless): unavailable subcheck',
  ]) {
    const result = classifyTest({ ...ok, stdout: `${note}\nALL PASS\n` });
    assert.equal(result.status, 'partial');
    assert.deepEqual(result.reasons, [note]);
    assert.equal(classifyTest({ ...ok, stdout: note }).status, 'failed');
    const mixed = { ...ok, stdout: `NOTE: informational\n${note}\nALL PASS\n` };
    assert.deepEqual(classifyTest(mixed), { status: 'partial', reasons: [note] });
    for (const change of [
      { exitCode: 1 }, { timedOut: true }, { signal: 'SIGKILL' }, { error: 'ENOENT' },
      { stderr: 'SCRIPT ERROR: assertion failed\n' }, { stderr: 'FAIL: broken\n' },
      { stdout: `${mixed.stdout}FAILS 1\n` },
    ]) assert.equal(classifyTest({ ...mixed, ...change }).status, 'failed', JSON.stringify(change));
  }
  assert.equal(classifyTest({ ...ok, stdout: 'NOTEBOOK\nALL PASS\n' }).status, 'passed');
});

test('suite policy counts skipped and partial separately and can reject either', () => {
  const entries = ['passed', 'partial', 'skipped'].map(status => ({ status }));
  assert.deepEqual(summarize(entries), { passed: 1, partial: 1, skipped: 1, failed: 0, exitCode: 0 });
  assert.equal(summarize(entries, true).exitCode, 1);
  assert.equal(summarize([{ status: 'failed' }]).exitCode, 1);
  assert.equal(summarize([]).exitCode, 1);
});

test('CLI supports command help, exact selectors and explicit Godot override', () => {
  assert.equal(parseArgs([]).help, true);
  assert.equal(parseArgs(['--help']).help, true);
  for (const command of ['import', 'test', 'build', 'run']) {
    assert.equal(parseArgs(['help', command]).command, command);
    assert.equal(parseArgs([command, '--help']).help, true);
  }
  const parsed = parseArgs(['--godot', 'C:/Program Files/Godot.exe', 'test', '--test', 'd_assets', '--test', 'h_actions', '--timeout', '12.5', '--fail-on-skip']);
  assert.equal(parsed.godot, 'C:/Program Files/Godot.exe');
  assert.equal(parsed.timeoutMs, 12500);
  assert.deepEqual(parsed.tests, ['d_assets', 'h_actions']);
  assert.equal(parsed.failOnSkip, true);
  assert.equal(parseArgs(['build', 'linux']).platform, 'linux');
  assert.equal(parseArgs(['test', '--list']).list, true);
  assert.equal(parseArgs(['import'], { GODOT: 'engine' }).godot, 'engine');
  assert.equal(parseArgs(['import', '--godot', 'explicit'], { GODOT: 'engine' }).godot, 'explicit');
});

test('CLI rejects typos, wrong command options, missing values and unsafe timeouts', () => {
  for (const args of [
    ['unknown'], ['help', 'unknown'], ['build'], ['build', 'macos'], ['test', 'd_assets'],
    ['run', '--list'], ['import', '--test', 'd_assets'], ['build', 'linux', '--fail-on-skip'],
    ['test', '--godot'], ['test', '--godot', ''], ['test', '--test'], ['test', '--test', '--list'],
    ['test', '--godot', '-h'], ['test', '--test', '-h'],
    ['test', '--wat'], ['test', '--timeout', '0'], ['test', '--timeout', '-1'],
    ['test', '--timeout', 'NaN'], ['test', '--timeout', 'Infinity'], ['test', '--timeout', '2147484'],
    ['build', 'windows', 'linux'], ['help', 'test', 'extra'], ['--help', '--typo'],
  ]) assert.throws(() => parseArgs(args), undefined, args.join(' '));
});

async function temp(t) {
  const dir = await mkdtemp(path.join(tmpdir(), 'ccs-tool-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
}

test('discovery includes data scripts and harness scenes, not diagnostics or companion scripts', async t => {
  const dir = await temp(t);
  await mkdir(path.join(dir, 'nested'));
  for (const name of ['d_new.gd', 'h_new.tscn', 'h_new.gd', 'p_probe.tscn', 'd_new.gd.uid', 'nested/d_other.gd']) {
    await writeFile(path.join(dir, name), '');
  }
  const discovered = await discoverTests(dir);
  assert.deepEqual(discovered.map(x => x.name), ['d_new', 'h_new', 'nested/d_other']);
  assert.equal(selectTests(discovered, ['h_new'])[0].file, 'h_new.tscn');
  assert.throws(() => selectTests(discovered, ['h_ne']), /Unknown test/);
  assert.throws(() => selectTests(discovered, ['p_probe']), /Unknown test/);
  assert.equal(selectTests(discovered, ['h_new', 'h_new']).length, 1);
});

test('unsupported tests remain discoverable with explicit reasons', async () => {
  const entries = await discoverTests(path.join(ROOT, 'tests'));
  for (const name of ['h_embed_guard', 'h_fullscreen', 'h_picture', 'h_pixelscale']) {
    assert.ok(entries.find(x => x.name === name)?.skipReason, name);
  }
  assert.equal(entries.find(x => x.name === 'h_chase_shake').skipReason, undefined);
});

test('isolation overrides Windows case variants and all Linux user directories without mutating parent', () => {
  const parent = { AppData: 'real-user', HOME: '/real/home', XDG_DATA_HOME: '/real/data', Path: 'keep', OTHER: 'keep' };
  const env = isolatedEnvironment('C:\\temp\\ccs', parent, 'win32');
  assert.equal(env.APPDATA, 'C:\\temp\\ccs\\AppData\\Roaming');
  assert.equal(env.LOCALAPPDATA, 'C:\\temp\\ccs\\AppData\\Local');
  assert.equal(env.USERPROFILE, 'C:\\temp\\ccs');
  assert.equal(env.HOMEDRIVE, 'C:');
  assert.equal(env.HOMEPATH, '\\temp\\ccs');
  assert.equal(env.AppData, undefined);
  assert.equal(env.Path, 'keep');
  assert.equal(parent.AppData, 'real-user');
  const linux = isolatedEnvironment('/tmp/ccs', parent, 'linux');
  assert.equal(linux.HOME, '/tmp/ccs');
  assert.equal(linux.XDG_DATA_HOME, '/tmp/ccs/.local/share');
  assert.equal(linux.XDG_CONFIG_HOME, '/tmp/ccs/.config');
  assert.equal(linux.XDG_CACHE_HOME, '/tmp/ccs/.cache');
});

test('each invocation gets fresh user storage and cleans it even on failure', async () => {
  let first;
  await withIsolation(async env => {
    first = env.HOME;
    assert.ok(first.startsWith(tmpdir()));
    await writeFile(path.join(env.APPDATA, 'settings.cfg'), 'sentinel');
    await withIsolation(async other => {
      assert.notEqual(other.HOME, first);
      assert.deepEqual(await readdir(other.APPDATA), []);
    });
  });
  await assert.rejects(stat(first), { code: 'ENOENT' });
  let failed;
  await assert.rejects(withIsolation(async env => { failed = env.HOME; throw new Error('test failure'); }), /test failure/);
  await assert.rejects(stat(failed), { code: 'ENOENT' });
});

function fakeSpawn(action) {
  return (executable, args, options) => {
    assert.equal(options.shell, false);
    assert.equal(options.windowsHide, true);
    const child = new EventEmitter();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = signal => { queueMicrotask(() => child.emit('close', null, signal)); return true; };
    queueMicrotask(() => action(child, executable, args, options));
    return child;
  };
}

test('mock process timeout is failure even if ALL PASS was printed first', async () => {
  const result = await runProcess('engine', [], {
    timeoutMs: 20,
    spawnImpl: fakeSpawn(child => child.stdout.write('ALL PASS\n')),
  });
  assert.equal(result.timedOut, true);
  assert.equal(classifyTest(result).status, 'failed');
});

test('spawn errors are reported, not thrown away or treated as successful exit', async () => {
  for (const spawnImpl of [
    fakeSpawn(child => { child.emit('error', new Error('ENOENT')); child.emit('close', -2, null); }),
    () => { throw new Error('cannot spawn'); },
  ]) {
    const result = await runProcess('missing', [], { timeoutMs: 100, spawnImpl });
    assert.ok(result.error);
    assert.equal(classifyTest(result).status, 'failed');
  }
});

test('runner drains both streams until close and never fabricates a completion marker', async () => {
  const result = await runProcess('engine with spaces', ['--script', 'path with spaces'], {
    timeoutMs: 1000,
    spawnImpl: fakeSpawn((child, executable, args) => {
      assert.equal(executable, 'engine with spaces');
      assert.deepEqual(args, ['--script', 'path with spaces']);
      child.stdout.write('ALL ');
      child.emit('exit', 0, null);
      child.stdout.write('PASS\n');
      child.stderr.write('SCRIPT ERROR: late\n');
      child.emit('close', 0, null);
    }),
  });
  assert.equal(result.stdout, 'ALL PASS\n');
  assert.equal(classifyTest(result).status, 'failed');
  const noMarker = await runProcess('engine', [], {
    timeoutMs: 1000, spawnImpl: fakeSpawn(child => child.emit('close', 0, null)),
  });
  assert.equal(classifyTest(noMarker).status, 'failed');
});

test('real process failure and timeout work without a shell', async () => {
  const missing = await runProcess(path.join(tmpdir(), 'nonexistent-ccs-engine'), [], { timeoutMs: 1000 });
  assert.match(missing.error, /ENOENT/);
  const hang = await runProcess(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { timeoutMs: 100 });
  assert.equal(hang.timedOut, true);
  assert.equal(classifyTest(hang).status, 'failed');
});

test('CLI help and validation work from outside the repository without launching Godot', async () => {
  const cli = path.join(ROOT, 'tools', 'project.mjs');
  const help = await runProcess(process.execPath, [cli, 'test', '--help'], { cwd: tmpdir(), timeoutMs: 5000 });
  assert.equal(help.exitCode, 0);
  assert.match(help.stdout, /--fail-on-skip/);
  const bad = await runProcess(process.execPath, [cli, 'build', 'macos'], { cwd: tmpdir(), timeoutMs: 5000 });
  assert.equal(bad.exitCode, 2);
});

test('staging uses only runtime sources and portable presets; local config stays untouched', async t => {
  const source = await temp(t);
  const dest = path.join(await temp(t), 'stage');
  for (const dir of ['assets', 'scenes', 'scripts', 'tools', 'tests', 'docs']) await mkdir(path.join(source, dir));
  const config = '[rendering]\nrenderer/rendering_method="gl_compatibility"\n';
  await writeFile(path.join(source, 'project.godot'), config);
  await writeFile(path.join(source, 'export_presets.cfg'), 'LOCAL SIGNING SECRET');
  await writeFile(path.join(source, 'assets', 'dynamic.glb'), 'model');
  await writeFile(path.join(source, 'scripts', 'map.gd'), 'source');
  await writeFile(path.join(source, 'tests', 'h_test.tscn'), 'excluded');
  await copyFile(path.join(ROOT, 'tools', 'export_presets.cfg'), path.join(source, 'tools', 'export_presets.cfg'));
  await stageProject(source, dest);
  assert.deepEqual((await readdir(dest)).sort(), ['assets', 'export_presets.cfg', 'project.godot', 'scenes', 'scripts']);
  assert.equal(await readFile(path.join(dest, 'project.godot'), 'utf8'), config);
  assert.equal(await readFile(path.join(dest, 'assets', 'dynamic.glb'), 'utf8'), 'model');
  assert.equal(await readFile(path.join(source, 'export_presets.cfg'), 'utf8'), 'LOCAL SIGNING SECRET');
  assert.doesNotMatch(await readFile(path.join(dest, 'export_presets.cfg'), 'utf8'), /LOCAL SIGNING SECRET/);
});
