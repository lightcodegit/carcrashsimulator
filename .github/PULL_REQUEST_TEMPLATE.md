# What and why

<!-- 1–2 paragraphs: which defect or feature, and why the solution is this one.
Link the issue if there is one: fixes #N. A PR without an issue — explain why
in the body. -->

## How it was verified

```sh
node tools/project.mjs import
node tools/project.mjs test --timeout 400
node --test tools/project.test.mjs
```

<!-- If verification needs a live window (GPU, audio output, gamepad) — say so
directly and describe what you saw: `node tools/project.mjs run` or
`p_live_probe`. -->

## Self-check

- [ ] A new check **can fail**: restored the old behavior → got `FAIL` → rolled back. A green `ALL PASS` from a timeout, an un-awaited `await` or "nothing to check" is a defect, not success.
- [ ] The full headless set did not regress: 68 checks → 56 pass / 8 partial / 4 skipped / 0 failed. `PARTIAL` is printed only when a part is genuinely not verified.
- [ ] Commit message and code comments in **English**, conventional prefix (`fix(ui): …`, `test: …`), the body explains **why**.
- [ ] Mixed-alphabet check passes: `grep -rnIP "[\x{4E00}-\x{9FFF}\x{3040}-\x{30FF}]" --include="*.gd" --include="*.tscn" --include="*.md" --include="*.mjs" scripts tests tools README.md` is empty.
- [ ] No local junk in the diff: `artifacts/`, `tests/out/`, `tests/tmpappdata/`, `*.tpz`, the root `export_presets.cfg`.
- [ ] Commands and paths are portable: no `C:/Users/…` in code, docs and workflows.
- [ ] If player-visible behavior changed — `README.md` and `CHANGELOG.md` updated.
- [ ] Code boundaries respected: `map_db.gd` stays a facade, particles are `CPUParticles3D`, the replay plays back what was recorded and does not re-simulate physics, audio output is one per process.
