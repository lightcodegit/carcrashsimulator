# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [semantic versioning](https://semver.org/). The version number
lives in `project.godot` (`application/config/version`), and the release
workflow refuses to publish a tag that does not match it.

## [Unreleased]

### Added

- Lifetime statistics on a new STATISTICS section in the main menu: runs,
  impacts, best impact, top speed, distance, time in runs and photos taken.
  The numbers accumulate live during every run and are stored in
  `user://stats_v1.json` with the same atomic write as the garage file, so
  they survive restarts.
- A GALLERY section in the main menu: photo-mode and replay snapshots as a
  thumbnail grid (newest first) with delete and open-folder actions — no more
  digging for PNGs in the file manager to see what you shot.
- Accessibility settings on the GENERAL tab of the settings screen. FLASH
  REDUCTION extinguishes the sudden bright bursts (impact and wall-scrape
  sparks) while non-flashing effects like dust and smoke stay on. LARGER
  INTERFACE grows the UI by one whole step (never a fractional scale — the
  engine renders those blurry); it applies when a screen is built: in the menu
  at once, in a run after returning to the menu, which the label says plainly.

## [v0.1.3] - 2026-11-11

### Fixed

- Replay tape parsing is hardened to the same standard as the settings and
  garage files: a 16 MB file size cap, finite numbers everywhere (NaN passed
  the `is float` check and then broke the frame-time binary search in
  `index_at`), dents validated by type and value (a foreign `lp` type was a
  script error inside the typed `apply_impact_local` mid-replay), and frame
  and dent count caps enforced in `adopt_tape` too.
- The nitro gauge on a replay burns from the recorded boost flag
  (`CarRig.replay_hot`, filled by the player) instead of the tank level: by
  the end of a run the tank is almost never empty, so the ring glowed for the
  whole replay as if the boost was active, which the recording never had.
- Factory gamepad bindings answer any pad (`device = -1`) instead of only the
  first one. Godot's event default `device` is 0, so with two gamepads the
  second one could not drive the car on factory bindings while vibration
  still reached it through `pad_index()`.
- A key assignment that conflicts with another action's binding now ends the
  capture cell instead of leaving it in "press a key" mode, where the next
  press silently rebound the action again. Mouse events are no longer
  swallowed by the interceptor: clicking another cell retargets the capture.
- Photo mode numbers a new snapshot after the highest existing `photo_NNNN`
  file instead of the file count, so deleting a middle snapshot no longer
  makes the next shot silently overwrite a newer one (replay snapshots
  already counted this way).
- The pause run summary repaints on a live language switch: it is a composed
  string, not a bound label, and settings — where the language lives — can be
  opened from the pause.

---

## [v0.1.2] - 2026-11-10

### Added

- New **Void** map: an infinite flat plane in all directions with no walls or objects; the floor follows the car on both axes.


### Changed

- The endless strip keeps 6 km of road in play (was 1.8 km): the ribbon- Heavy scenes render more efficiently: endless-strip barriers, lights, and billboards use visibility ranges, and small static city props (benches, bins, picnic tables, fountains, planters) are culled at distance with shadows disabled where appropriate.

  stretches 5.9 km ahead of the car, so the horizon reads as an endless road
  even at 671 km/h — 31 seconds of road ahead. Billboards and light poles
  now line the whole first stretch. The simulation cost stays at 1.4 ms per
  tick and the node count is flat.
- Billboards are now a clean, blank white board: the Kenney "TankCo" road
  advertisement and the game-logo overlay were both removed. `MapKit.kit`
  overrides the panel surface with a plain white material for every billboard
  model on every map, before the per-map material pass so it is not re-tuned.

### Fixed

- The endless grass floor follows the car (issue #5): driving off the strip
  onto the grass no longer reaches the edge of the 40 km slab, where the road
  strip hung over the void and the car fell through. The world boundary grew
  to 400 km to match.
- A replay snapshot taken from the replay bar no longer fails on a fresh
  profile where photo mode was never opened: the `user://photos` folder is
  created before the write (Godot's `save_png` does not create parent dirs).
- A saved replay tape whose frames omit the `nitro`/`hot` keys is now rejected
  by validation instead of crashing the player mid-replay when it reads those
  keys. The frame validator required those keys to be well-formed but not to
  be present at all.
- `ReplayRecorder.frame_at()` on an empty ring returns an empty frame instead
  of indexing `frames[0]` and raising a runtime out-of-bounds error.
- Loading an older, shorter tape from the replay bar no longer leaves the
  near-prop cache stale: `adopt_tape` resets it, so the first frames after
  resuming record the props actually around the car, not the previous
  surroundings (the refresh gate compares against the rewound time).
- Nitro no longer keeps pushing after the tank runs out. While the player held
  the nitro key with the throttle open, an empty tank recharged a hair every
  frame and immediately re-lit the boost (a limit cycle), so the car kept
  accelerating "as if with nitro" forever. The tank now recharges only when the
  boost is not being demanded (key released or off the throttle).
- The speedometer and nitro gauge labels ("KM/H", "NITRO") now translate. They
  were drawn straight onto the gauge with a raw Russian literal, so the language
  switch never repainted them and they stayed Cyrillic in English mode. `h_i18n`
  gains a source scan so custom-drawn UI text cannot bypass the catalog again.

---

## [v0.1.1] - 2026-11-09

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
- Landings and light scrapes no longer count as impacts. The detector is
  two-tier now: 20 km/h of dead HORIZONTAL speed (a wall, a barrier, a real
  scrape) or 54 km/h of dead VERTICAL speed (a suspension-bottoming slam from
  15 m/s and harder — the kind the impact replay exists for). Ordinary
  touchdowns at 7–12 m/s of vertical, which the suspension absorbs, no longer
  dent the car; the player log showed phantom impacts at 97–238 km/h.
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

---

## [v0.1.0] - 2026-11-08

### Added

- The first public release of the crash sandbox: a car body that crumples with
  dents at the point of impact, five cars from a heavy pickup to the Endless
  car with no speed cap, and seven maps from a test arena to a big city.
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