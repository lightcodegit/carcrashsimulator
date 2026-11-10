<p align="center">
  <img src="docs/images/crumple.jpg" alt="Car Crash Simulator — deformed car body at the impact point, telemetry on the left, photo mode bar at the bottom" width="100%">
</p>

<h1 align="center">Car Crash Simulator</h1>

<p align="center">
  <b>A 3D crash sandbox for Godot 4.7</b><br>
  Speed up, crash, and watch the body crumple right where it hits.
</p>

<p align="center">
  <a href="https://github.com/lightcodegit/carcrashsimulator/actions/workflows/ci.yml"><img src="https://github.com/lightcodegit/carcrashsimulator/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/license-MIT-F0795A" alt="License: MIT">
  <a href="https://godotengine.org/download/archive/"><img src="https://img.shields.io/badge/Godot-4.7.2%20stable-F0795A" alt="Godot 4.7.2"></a>
  <img src="https://img.shields.io/badge/renderer-GL%20Compatibility-F0795A" alt="Renderer: GL Compatibility">
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20Linux-F0795A" alt="Platform: Windows | Linux">
</p>

<p align="center">
  <a href="#what-is-in-the-game"><b>Features</b></a> ·
  <a href="#controls"><b>Controls</b></a> ·
  <a href="#download"><b>Download</b></a> ·
  <a href="#building-from-source"><b>Build</b></a> ·
  <a href="#tests"><b>Tests</b></a> ·
  <a href="CONTRIBUTING.md"><b>Contributing</b></a>
</p>

<p align="center">🌐 <b>English</b> · <a href="README.ru.md">Русский</a></p>

---

**Car Crash Simulator** is a free, open-source (MIT) 3D crash sandbox with real-time body deformation, in-run telemetry, a replay of the last ten seconds, photo mode with a free camera, and a garage for tuning and paint. Built with **Godot 4.7.2** and **CC0** assets.

## What is in the game

Everything listed below ships in the current release.

| Feature | Details |
|:--:|---|
| **Deformation** | Body vertices shift along the velocity-loss vector: head-on, side, and rear impacts crumple their own panel. Dents accumulate and are cleared on restart. |
| **5 cars** | From a heavy pickup to the *Endless* car with no speed cap. Each car has its own top speed, mass, acceleration, and nitro with a tank and exhaust flame. |
| **6 maps** | Test arena, town with parked cars, drag strip with a finish wall, kilometre race loop, endless tile strip, and a big city with districts. |
| **Replay & photo mode** | Replay the last 10 seconds with stepping and playback speed. Free camera with zoom and PNG screenshots. |
| **Garage** | Suspension stiffness, dampers, thrust, brakes, grip, nitro tank, and body paint in any color. Profiles are stored per car. |
| **Sound & vibration** | Engine, tire squeal, impact, and nitro are synthesized by a DSP mixer. Gamepads vibrate on impacts and slides. |
| **Settings & i18n** | Image presets plus individual graphics options, slow-mo, and camera settings. English/Russian UI, switchable on the fly. Every action is rebindable (key/button/axis) — keyboard and gamepad stored separately, modifiers are part of the binding. |

<table>
  <tr>
    <td width="50%" align="center">
      <img src="docs/images/garage.jpg" alt="Garage: a green sedan in a live world and the tuning panel with paint"><br>
      <sub><b>Garage</b> — live preview, tuning, and custom paint</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/images/skid.jpg" alt="A slide on the arena: a tire mark stays on the asphalt"><br>
      <sub><b>Driving feel</b> — slides, grip, and persistent skid marks</sub>
    </td>
  </tr>
</table>

## Performance

Simulation costs ≈**1 ms** per physics tick (6–7% of the 16.67 ms step budget) — the frame is bounded by rendering. That is why the renderer is **GL Compatibility** and image presets are priced from measured frame costs.

Measured by `tools/project.mjs test` (`p_perf`, live rendering) on **Intel HD 630** at **1600×900**:

| Frame configuration (Compatibility) | Frame cost |
| --- | ---: |
| Geometry only, no shadows or post effects, 70% scale | **6.7 ms** |
| Haze and glow, shadows 120 m *(default)* | **13.7 ms** |
| Everything on: SSAO/SSIL, MSAA 4×, shadows 260 m | 29.4 ms |
| Soft shadows 420 m, bloom, exposure 1.15 *(film)* | 29.2 ms |

> **Tip:** The default preset fits a 60 Hz refresh on integrated graphics; **HIGH** and **FILM** presets are intended for discrete GPUs.

## Download

Ready builds are published on the [**Releases**](https://github.com/lightcodegit/carcrashsimulator/releases) page. The `Release` workflow assembles them automatically on a `v*` tag and checks the tag number against the version in `project.godot` and the `CHANGELOG.md` entry.

If a build for your platform or version is not available there, you can [build from source](#building-from-source) or grab CI artifacts from the [Actions](https://github.com/lightcodegit/carcrashsimulator/actions) tab.

| Platform | File | Requirements |
| --- | --- | --- |
| Windows x86_64 | `Car Crash Simulator.exe` | Windows 10/11, GPU with OpenGL 3.3 |
| Linux x86_64 | `Car Crash Simulator.x86_64` | glibc distribution, X11 or Wayland |

> Each build is a single file: game data (`.pck`) is embedded into the executable, so there is nothing to keep next to it.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle / Brake | `W` / `S` | `RT` / `LT` |
| Steering | `A` `D`, `←` `→` | Left stick |
| Handbrake / Parking brake | `Space` | `A` (Cross) **or** `L1` |
| Nitro (hold) | `Shift` | `R1` |
| Slow-mo (hold) | `Ctrl` | `B` |
| Camera (chase → hood → orbit) | `C` | `X` |
| Restart | `R` | `Y` |
| Pause | `Esc` | `Start` |

> **Default layout shown above.** Everything can be rebound in **SETTINGS → CONTROLS** (from the main menu or pause): to a key, button, or gamepad axis. `Ctrl+F` and `F` are treated as different bindings, and modifiers are stored in the settings file.

## Building from source

**Requirements:** [Godot 4.7.2 stable](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) *(not .NET)* and **Node.js >= 22** *(no npm dependencies)*.

For exporting, install the **4.7.2.stable** export templates via **Editor → Manage Export Templates** or from the official release. CI downloads the same editor/templates and verifies SHA-256.

```sh
git clone https://github.com/lightcodegit/carcrashsimulator.git
cd carcrashsimulator

# import resources and classes
node tools/project.mjs import

# run the game from source
node tools/project.mjs run

# export release builds
node tools/project.mjs build windows   # -> artifacts/build/windows/
node tools/project.mjs build linux     # -> artifacts/build/linux/
```

- Godot is resolved as `godot` from `PATH`; set `GODOT` or pass `--godot "C:/path with spaces/Godot.exe"` to any command.
- `help <command>` and `<command> --help` describe available options.
- `import`, `test`, and `build` run headless (no windows). `run` launches the game GUI.
- Alternatively, open `project.godot` in the editor and press **F5**.

## Tests

```sh
# tests of the runner itself (no Godot needed)
node --test tools/project.test.mjs

# import resources and classes first
node tools/project.mjs import

# discover / run tests
node tools/project.mjs test --list
node tools/project.mjs test --test d_assets --test h_crash --timeout 180
node tools/project.mjs test                # whole set, in parallel (--jobs N)
node tools/project.mjs test --fail-on-skip # strict mode: partial/skip is an error too
```

**How the test runner works:**
- Discovers `tests/**/d_*.gd` and `tests/**/h_*.tscn`; `--test` takes exact names from `--list`.
- Runs each test with isolated `APPDATA`/`HOME`/`XDG_*` directories in the system temp — player settings and other tests' results never leak into defaults.
- Success requires an `ALL PASS` line, exit code `0`, and no `SCRIPT ERROR`/`FAIL`. `PARTIAL`/`SKIP` are counted separately and **do not** count as a pass.
- Tests that need a live GPU, window, or gamepad honestly report `PARTIAL` in headless or are marked skipped. Full coverage for them requires a manual `p_live_probe` run with a live window (audio, smoke, paint, replay, and photo mode — measured in pixels and with real audio output).
- CI runs on both OSes and **always launches the exported build** headless for a few frames: *"it exported" without "it runs" does not count as a build*.

## Contributing

The process and queues are described in [**CONTRIBUTING.md**](CONTRIBUTING.md).

> **Language policy:** English is the language of the repository — new issues, commits, and pull requests are written in English. If the work is done by an AI agent, see the *"If you are an agent"* section in the contributing guide.

## License

- **Code, scenes, and tests:** [MIT](LICENSE)
- **Assets:** not ours — `assets/` contains CC0 **Kenney Car Kit** and **Racing Kit**. Their license texts are included next to the files and shipped in builds; `d_assets` tracks them.
- *"Godot"* and *"Kenney"* are trademarks of their respective owners, mentioned only to explain what this project is built with.

If you reuse the project: MIT requires keeping the copyright notice; CC0 requires nothing, but crediting the kit authors is appreciated.

## Credits

**Author:** [crystaldev](https://github.com/lightcodegit) ([@lightcodegit](https://github.com/lightcodegit))

**Contributors:** tracked in the GitHub [contributors graph](https://github.com/lightcodegit/carcrashsimulator/graphs/contributors).
