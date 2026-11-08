# How to help

The project is Godot 4.7.2 (standard, **not** .NET), GL Compatibility, GDScript.
The product and the game numbers are described in `README.md`, which is the
source of truth; this file is how work on the code is organized. The rules here
are enforced by CI and tests, not taken on faith.

## Language policy

**English is the language of the repository.** All new issues, pull requests,
commit messages, code comments and UI strings are written in English. Existing
Russian content (old commits, historical docs in `docs/superpowers/`, comments
in files you are not otherwise touching) stays as it is — history is not
rewritten for its own sake.

## Environment

1. Godot **4.7.2 stable** (standard build). In PATH as `godot`, or
   `export GODOT=<path>`, or `--godot <path>` on every command.
2. Node.js **>= 22**. There are no npm dependencies: `tools/project.mjs` runs
   without `npm install` and never creates `node_modules`.
3. For exporting — the **4.7.2.stable** templates (Editor → Manage Export
   Templates).

```sh
node tools/project.mjs --help
node tools/project.mjs import              # required after adding or renaming .gd/.tscn
node tools/project.mjs test --timeout 400  # the whole set
node tools/project.mjs test --test h_audio --test d_params
node tools/project.mjs build windows       # or linux
node tools/project.mjs run                 # opens a window
```

`import` is mandatory after new classes and scenes appear: without it the tests
do not see the file, and the failure looks like "this function does not exist".

## How the tests are organized

Harnesses live in `tests/` and are grouped by name prefix: `d_` is pure data on
`--script` (there are no autoloads there, touching `TimeScale` or
`ReplayRecorder` is not allowed), `h_` is node-level checks on scenes, `p_` is
manual diagnostics — measurements and screenshots. A run prints `ALL PASS` or
`FAILS <n>` and exits 0 or 1; `PARTIAL` is an honest admission that part of the
check did not run, `NOTE` is information.

Baseline: **66 checks → 54 pass / 8 partial / 4 skipped / 0 failed**. A
regression is any new `failed` or a smaller number of discovered checks.

The main rule: **a test must be able to fail.** Green output from a timeout, a
self-counting loop, an un-awaited `await` or the "nothing to check" shortcut is
a defect of the test, not success. Confirmability is proven by mutation: restore
the old behavior → get `FAIL` → roll back. Roll back by editing the text, not
by copying a file from an earlier stage of the work.

Second rule: `PARTIAL` is printed when a condition holds, not as a hedge. A
line like "sound cannot be checked in headless" lies when run in a live window:
GPU and WASAPI are there, and lying in the report is not allowed. Harnesses
with a joystick (`h_vibration`, `h_padflow`, `h_handbrake_devices`) are always
partial in headless — `Input.get_connected_joypads()` is empty even with a
gamepad connected, so hardware cannot be judged from a headless run.

### Headless traps, verified the hard way

- the viewport is `0×0` or square — take the actual size, not the 1600×900 from
  `project.godot`;
- synthetic mouse clicks are not routed to the GUI — press buttons via the
  `pressed` signal;
- `Performance` reports 0 for physics time;
- `AudioServer.get_driver_name() == "Dummy"`, and the audio generator is not
  created at all in that case;
- tests write to the **real** `user://`: the runner isolates it via `APPDATA`,
  and running `Godot.exe` manually without `APPDATA=<empty folder>` edits the
  saved player profile.

## Live verification

```sh
APPDATA=<empty folder> "$GODOT" --path . res://tests/p_live_probe.tscn --fixed-fps 60
```

Two to three minutes, opens a window. It covers what headless cannot: audio
output, a GPU frame, smoke and tire marks, the showcase paint measured in
pixels, a photo-mode shot, three re-assemblies of the run tree. Image or sound
changes without such a run do not count as verified — say in the PR what
exactly you saw with your eyes and ears.

## Code boundaries

- `scripts/maps/map_db.gd` is only a facade (`ids`/`build`/`recycle`/
  `debug_counts`); geometry lives in `map_kit`, `map_props`, `map_circuit`,
  `map_<map>`, numbers and palette in `map_defs`.
- Particles are `CPUParticles3D` only (headless must count the same as a
  window), smoke emitters are attached to `EffectsDirector`, not to
  `VehicleWheel3D`: the wheel is freed together with the car, and an active
  emitter on that free used to kill the process.
- Audio: one output per process, do not add a second player to the scene, do
  not free the host in someone else's `_exit_tree`.
- The replay plays back what was recorded, it does not re-simulate: the world
  is paused, pose and speed come from the ring, dents are rebuilt from events
  in the mesh's local coordinates.
- Garage: `brake_decel` is clamped by physics (`CarRig.BRAKE_MAX_G`), only
  `accel_max` scales from `LIMITS`; paint touches exactly the body cell of the
  atlas; `user://garage_v1.json` is versioned and written atomically.
- A binding is a key together with its modifiers; keys outside `InputMap` are
  allowed only as service keys and only yieldingly (`PhotoMode` asks
  `InputRouter.find_owner`).
- UI: sizes via `UiTheme.fx()`/`px()`/`step()`, active states via
  `UiTheme.nav_mark_active`. Do not add pixel constants to UI code — stepped
  scaling breaks them.

## Style

Commit messages follow conventional prefixes (`fix(ui): …`, `test: …`,
`docs: …`) and the body explains **why**, not what.

Mixed alphabets are a real defect class in this repository: a stray CJK glyph,
or a Latin word glued into a Cyrillic phrase without a space (and vice versa —
this file used to be written in Russian, and leftover glue still hides in old
code comments). Before committing:

```sh
grep -rnIP "[\x{4E00}-\x{9FFF}\x{3040}-\x{30FF}]" --include="*.gd" --include="*.tscn" --include="*.md" --include="*.mjs" --include="*.yml" scripts tests tools docs README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md .github
```

The `-I` flag is mandatory: without it the scan drowns in binary caches from
`tests/tmpappdata/` and screenshots in `tests/out/` and reports hundreds of
false positives.

## What must not be in a diff

`artifacts/`, `tests/out/`, `tests/tmpappdata/`, `*.tpz`, the root
`export_presets.cfg` (it is local and ignored; the portable presets live in
`tools/export_presets.cfg`), personal paths like `C:/Users/…` in code,
documentation and workflows. The logic of a change must not leave one-off
scripts in the repository.

## What to ask about first

Changing public contracts (`user://` formats, `InputMap` action names, the
export scheme), engine boundaries (moving to Forward+, another renderer) and
the v1 boundary (AI traffic, networking, parts falling off, photorealism) —
in an issue, before the code. This is not bureaucracy: each of these points
already has tests and documentation that get rewritten together with it.

## If you are an agent

The rules below come from the practice of public repositories with AI
contributors (for example, `horizon-rust/horizon`) and are adapted to our size.

- **Mark that an agent writes.** The PR body starts with a line like
  `> 🤖 Opened by <login>'s AI agent (<tool, model>), not by <login> personally.`
  (`<login>` is the account that opened the PR, `gh api user --jq .login`); in
  issues — "Filed by …", in reviews — "Review by …", every comment starts with
  `🤖 Agent:`. The commit carries `Co-Authored-By:` for the agent that wrote
  it. Write only on behalf of the person you are working for.
- **Check what is already being done.** Before starting:
  `gh pr list --state open --search <area>` and open issues; do not duplicate
  someone else's work. A taken task is one assigned to someone or marked as in
  progress.
- **Small PRs.** The guideline is up to ~500 lines of diff: one defect or one
  feature. Bigger changes are discussed in an issue first, not shipped as a
  ready-made train.
- **Do not touch the release.** Release labels and tags are the owner's call;
  an agent does not push `v*` tags and does not change repository visibility.
- **Isolation is mandatory.** Every launch of the game or a harness uses a
  fresh empty `APPDATA` (Windows) or `XDG_DATA_HOME`/`XDG_CONFIG_HOME` (Linux):
  tests write to the real `user://`, and without isolation you are editing a
  live player's profile.
- **The repository map** is in `README.md`; this file describes the
  contribution process.
