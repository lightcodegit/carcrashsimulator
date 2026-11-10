# Security

> 🌐 This page in other languages: **English** · [Русский](SECURITY.ru.md)

## The threat model in two paragraphs

The game runs offline: there is no networking, accounts, servers or telemetry
in it. So a remote attack is only possible through data the player brought into
their own profile, or through a build the player downloaded. Problems in the
game's code are fixed by the project; the security of third-party builds
depends on their source.

The player profile lives in `user://` (`settings.cfg`, `garage_v1.json`, photo
mode shots in `photos/`). All of it is read from GDScript and never reaches
SQL, shell or eval; paths in the code are constant, and no external input is
concatenated into paths. So the real defect class here is not an "exploit" but
state corruption: a hang on load, lost settings, NaN in physics, a black body.
We fix those and count them as bugs, not vulnerabilities.

## What is covered, and how it is verified

- **Hostile profile files.** Broken JSON, an array instead of a dictionary, a
  key from a foreign version, a file over 1 MiB, non-numeric and infinite
  tuning values, foreign fields, a missing car — all of it rolls back to
  factory settings while the rest of the file keeps loading. Verified by the
  `d_garage_profiles`, `h_settings_robust` and `h_wrap` tests.
- **Atomic writes.** The garage is written through a `.tmp` file and a rename:
  a crash mid-write leaves no half-file. Verified (`failed save preserves old
  file`).
- **Key bindings.** Tokens from `settings.cfg` are checked for format and
  bounds (`k70+CS`, `b3@1`, `a0_50`): a garbage number does not become an
  unpressable binding and does not displace a real one. Verified in
  `h_settings_robust`.
- **CI and the supply chain.** The official Godot and export templates are
  downloaded by name and verified by SHA-256 **before** unpacking; actions are
  pinned by commits, not tags; the default workflow has
  `permissions: contents: read`, `persist-credentials: false`, no
  `pull_request_target` and no `github.event.*` interpolation into shell
  commands. Only the release workflow has write permissions, and it runs on a
  tag from this repository, not from a foreign PR.

## What is not a vulnerability

- A malicious `.pck` or a foreign build: the engine executes package code under
  its own trust model. Trust the source of the build — official ones live in
  Releases.
- A player corrupting their own profile: the files are theirs, they may break
  them.
- Destructive performance actions (stalling the fps with a huge number of
  props) — that is a balance bug if it makes the game unplayable; open an issue.

## How to report

If the repository's **Security** tab has a **Report a vulnerability** button,
send the report through it. If there is no button, use the contact details
published by the project owner on their
[GitHub profile](https://github.com/lightcodegit) and ask for a private channel
to hand over the details. Do not open a public issue describing a
vulnerability.

Useful things to include: the version (`v*` or `git describe --tags`), the OS
and GPU, minimal reproduction steps, the contents of the offending profile file
(if it goes through one), and what exactly broke — a crash, data corruption or
a leak.

The project is maintained by one person, so the terms are honest:
confirmation within ~7 days, a fix as time allows, no guarantees. There is no
public bounty. Reports in the "what is covered" classes above already have
tests — if you found a way around them, that is exactly what is interesting.
