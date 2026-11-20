# Modding

Car Crash Simulator v1 mods are **data-only car packs**. A pack picks a shipped
car as its base and overrides whitelisted physics numbers and the menu/HUD accent
color. Custom models, textures, maps, and scripts are not supported yet: a
`mod.json` cannot point the game at another resource or execute code.

## Install a pack

1. Open **MODS** in the main menu and press **OPEN MODS FOLDER**. On Windows this
   is `%APPDATA%\Godot\app_userdata\Car Crash Simulator\mods`.
2. Create one folder per pack, for example `mods/midnight_tuning/`.
3. Put a file named exactly `mod.json` inside that folder.
4. Press **RELOAD** in the MODS section, or restart the game. The car appears in
   **CARS** and works in the garage, records, and replay export like a shipped
   car.

The MODS section lists every loaded pack and every rejected file with the reason.
A broken pack never stops the other packs or the shipped cars from loading.

If you start the game through the bundled launcher, its **MODS** button opens the
same folder: the launcher computes the game's user-data path directly, so both
entries point at one `mods` directory.

## Minimal pack

```json
{
  "name": "Midnight Tuning",
  "version": "1.0",
  "author": "your name",
  "cars": [
    {
      "id": "night_sedan",
      "name": "Night Sedan",
      "description": "A stiff, fast sedan.",
      "base": "sedan",
      "color": [0.2, 0.8, 1.0],
      "params": {
        "mass": 1420,
        "accel_max": 9.0,
        "vmax_kmh": 230,
        "grip": 9.0,
        "nitro_capacity": 140
      }
    }
  ]
}
```

## Pack fields

| Field | Required | Meaning |
|---|---|---|
| `name` | no | Pack name in the MODS panel. Defaults to the folder name; at most 64 characters. |
| `version` | no | Free-form string shown next to the name; at most 16 characters. |
| `author` | no | Shown in the MODS panel; at most 64 characters. |
| `cars` | yes | Non-empty array of car entries. At most 8 cars per pack. |

Unknown pack-level fields are ignored.

## Car fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique car id, 2–32 characters of `a-z`, `0-9`, `_`, starting with a letter. It must not match a shipped car or another mod car. |
| `base` | yes | Shipped car to inherit from: `sedan`, `pickup`, `limousine`, `infinity`, or `sport`. |
| `name` | no | Display name, at most 64 characters. Defaults to the id; an explicitly empty name is rejected. |
| `description` | no | Card text under the name, at most 240 characters. |
| `color` | no | `[r, g, b]` with numbers from 0 to 1. Sets the menu card and HUD gauge accent, not the body paint. Overrides the base accent when valid. |
| `params` | no | Object of physics overrides. Unknown keys are reported and ignored. |

The base car supplies the model, body paint, wheel placement, and every value you
do not override. `width` and `body_stretch` are applied before length, height,
and wheel radius are measured, so a scaled body keeps a correct collider.

## Physics parameters

Numbers are clamped to the range below instead of being rejected, so a typo
cannot feed a NaN or a negative mass to the simulation.

| Key | Range | Meaning |
|---|---|---|
| `mass` | 400–4000 | Body mass, kg. |
| `accel_max` | 1–60 | Engine thrust, m/s². |
| `vmax_kmh` | 40–1000 | Speed ceiling, km/h. The `infinity` base has no ceiling unless you set one. |
| `brake_decel` | 4–20 | Braking deceleration, m/s². The tire model still caps the real value. |
| `steer_rate_deg` | 120–600 | Steering angle rate, °/s. |
| `grip` | 2–20 | Tire grip multiplier. |
| `suspension_stiffness` | 40–260 | Suspension spring stiffness. |
| `damping_compression` | 2–16 | Compression damping. |
| `damping_relaxation` | 2–20 | Rebound damping. |
| `width` | 1.2–2.6 | Target body width in metres; scales the whole model uniformly. |
| `body_stretch` | 0.8–2.0 | Extra stretch along the car's length; wheels stay round. |
| `nitro_capacity` | 0–400 | Nitro tank size. `0` disables nitro. |
| `nitro_drain` | 0–200 | Tank units per second while boosting. |
| `nitro_refill` | 0–100 | Tank units per second while off boost. |
| `nitro_accel` | 0–30 | Extra acceleration while boosting, m/s². |
| `nitro_vmax` | 1–3 | Multiplier applied to the speed ceiling during boost. |

Other `VehicleParams` fields are not moddable through `mod.json`. Body paint is
set in the garage, not by a pack.

## Limits and validation

- At most 32 pack folders, 8 cars per pack, and 32 mod cars in total.
- `mod.json` must be valid JSON and no larger than 64 KB.
- A folder without `mod.json`, an empty `cars` array, an unknown `base`, a
  built-in id collision, or a duplicate id across packs is reported and skipped.
- Car ids are sorted by pack folder; if two packs claim the same id, the first
  folder keeps it and the second is reported.
- Non-numeric parameter values are reported and leave the base value in place.
  Unknown parameter names are reported and ignored.
- Malformed `color` values are reported; the car still loads with the base
  accent color.

Mod cars keep their own records bucket in STATS, keyed by their mod id. Removing
a pack hides its car but leaves existing records on disk.

## Troubleshooting

- **The pack does not appear in MODS.** Check that the folder contains a file
  named exactly `mod.json` (lowercase). Folders without `mod.json` are ignored
  silently. Press **RELOAD** after adding the file.
- **"rejected: unknown base"** — the `base` field must be one of `sedan`,
  `pickup`, `limousine`, `infinity`, or `sport`. Check spelling and case.
- **"rejected: id collision"** — another pack or a shipped car already uses
  that id. Rename the car's `id` to something unique.
- **"rejected: invalid json"** — the file is not valid JSON. Common causes:
  trailing commas, single quotes instead of double quotes, or a BOM at the
  start. Validate with any JSON linter.
- **"rejected: file too large"** — `mod.json` must be under 64 KB. Remove
  unused fields or shorten descriptions.
- **The car appears but drives wrong.** Numbers are clamped to the ranges in
  the table above. A value outside the range is silently clamped, not rejected.
  Check the clamped value in the MODS panel tooltip.
- **The car's accent color did not change.** The `color` field sets the menu
  card and HUD gauge accent, not the body paint. Body paint is changed in the
  garage. Also, a malformed `color` array is reported and the base accent is
  kept.
- **Mod cars do not appear after a game update.** The `base` car name may have
  changed. Check the MODS panel for the rejection reason and update the
  `base` field in `mod.json`.

## Using the launcher

If you start the game through the bundled **Car Crash Launcher**, its **MODS**
button opens the same folder: the launcher computes the game's user-data path
directly, so both entries point at one `mods` directory. Installed game
versions (managed by the launcher) share the same mods folder, so a pack
installed once works in every version.

## What is not moddable (v1)

- Custom 3D models, textures, or sounds.
- New maps or tracks.
- Scripts or executable code of any kind.
- Body paint colors (set in the garage per car).
- `VehicleParams` fields not listed in the table above (engine curves,
  aero, tire model internals, etc.).
