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
