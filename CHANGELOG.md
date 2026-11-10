# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
versions follow [semantic versioning](https://semver.org/). The version number
lives in `project.godot` (`application/config/version`), and the release
workflow refuses to publish a tag that does not match it.

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
  gains a source scan so custom-drawn UI text cannot bypass the catalog.

