# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [semantic versioning](https://semver.org/). The version number
lives in `project.godot` (`application/config/version`), and the release
workflow refuses to publish a tag that does not match it.

## [Unreleased]

### Added

- Loading screen with the animated game emblem on scene switches: starting a
  run and returning to the menu show it until the target scene is ready.
- The chosen car and map persist across returning to the menu and quitting
  the game; the menu restores the card highlight from the last choice.

### Changed

- The language setting now lives in its own GENERAL section on the sound tab
  instead of sitting inside the SOUND section.
- The default frame cap is 60 (was uncapped). On 120–144 Hz monitors the GPU
  no longer renders every refresh, which removes the progressive slowdown
  from thermal throttling on weaker machines. Uncapped is still available in
  the settings.

### Fixed

- Ramp rear walls render double-sided: from behind, ramps looked transparent
  even though the collider stopped the car.
- The Endless map keeps billboards and light poles moving with the road strip,
  so the roadside has scenery along the whole ribbon instead of only the first
  few hundred metres.
- Falls no longer descend like a parachute. The hydro-stop now engages only
  when waiting longer would outrun its braking power (the braking distance to
  the soft-touch speed grew up to the ground clearance); until that moment
  every fall is free fall, and the arrest happens in the last decimetres —
  ramp jumps at any speed and drops off ledges land like real cars.
- Landings and light scrapes no longer count as impacts: the detector now
  measures the death of speed in the DRIVING plane. A touchdown — even a hard
  one that bottoms the suspension — kills only the vertical component, and
  the horizontal speed the crash detector watches survives it; a wall kills
  the horizontal speed outright. Player log showed phantom impacts at
  97–238 km/h.
- The Endless asphalt no longer flickers: the giant floor's visual top sits
  6 cm below the road plane (the physics drive surface is untouched — flat
  road tiles have no colliders of their own and ride on the floor).
- The endless spawn moved off a tile seam, so rays and wheels at the start
  find the road and not the gap between two colliders.
- F2/F3 yield to the player's own bindings: a key assigned to a game action
  no longer toggles the debug overlay or flips its sections. Each handler
  excludes its own action, otherwise the "owner" is always found and the
  key is dead.
- In photo mode the car is fully frozen: its rig inherited always-process
  from the manager and woke up on pause, so the camera keys (W/A/S/D) turned
  the wheels of the frozen world.
- The photo and replay bars fit their buttons: both panels were shorter than
  the button rows and the buttons hung out of the panel.

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
