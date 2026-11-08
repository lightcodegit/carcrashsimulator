# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [semantic versioning](https://semver.org/). The version number
lives in `project.godot` (`application/config/version`), and the release
workflow refuses to publish a tag that does not match it.

## [Unreleased]

## [v0.1.0] - 2026-11-08

### Added

- The first public release of the crash sandbox: a car body that crumples with
  dents at the point of impact, five cars from a heavy pickup to the Endless
  car with no speed cap, and six maps from a test arena to a big city.
- In-run telemetry HUD: speed, peak g-force, dent count and depth, the impact
  log and an on-screen fps counter.
- Impact replay of the last 10 seconds with stepping and playback speed;
  dents are rebuilt from the recorded events, not re-simulated.
- Photo mode: a free camera with zoom, PNG screenshots into `user://photos`.
- Garage: suspension stiffness, dampers, thrust, brakes, grip, the nitro tank
  and body paint; one saved profile per car, written atomically.
- Nitro with a tank, exhaust flame and a gauge ring on the speedometer.
- Sound and vibration: engine, tire squeal, nitro and impacts synthesized by a
  DSP mixer; gamepad rumble on impacts and slides.
- Manual slow-motion, three camera modes (chase, hood, orbit) with wall
  avoidance, tire marks that age on the asphalt.
- Settings: image presets, every graphics option individually, window and
  frame controls, rebinding every action to a key, button or axis with
  modifier support; the interface is English and Russian, switchable on the
  fly.
- Debug overlay (F2/F3) with frame, car, world and log sections.
- English and Russian localization with live switching.

### Changed

- Each build ships as one self-contained file: the `.pck` with all game data is
  embedded into the executable, so there is nothing to keep next to the binary.

### Known issues

- On Windows, closing the game window right after a run with sound can
  terminate the process with a SIGSEGV (~3 of 12 launches on Intel UHD 730).
  The crash happens after the game has already stopped rendering and saving:
  it is a shutdown race between OpenGL resources and the live audio stream in
  the graphics driver, not a defect in game logic. Player progress and
  settings are written before the crash window, so nothing is lost.
