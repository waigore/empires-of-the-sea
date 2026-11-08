# Test speed playbook

Tactics that paid off for Empires of the Sea. Prefer reuse over new harnesses.

## gd-tools quirks

- Each test method runs on a **new suite instance**. Instance fields set in `before_each` do not persist across tests.
- `before_all` runs on the suite context; the runner copies **non-underscore** script vars onto each test instance. Names like `_world` are **not** copied — use `world` / `model` (or a `static` cache on a fixture script).
- Default per-test timeout comes from `gd-tools.toml` (`timeout_seconds`). Suite hook budget is the max of declared test timeouts.
- Coverage instrumentation makes map generation ~10× slower. Profile with `--coverage`, not bare `gd-tools test`.

## Highest-ROI fixes

1. **Shared world fixture** — `tests/map_fixture.gd` caches one small `WorldMap` / region per Godot worker. MapScreen suites call `Fixture.attach_screen(self)` so `_ready` uses `preset_world` instead of `generate_world`.
2. **`before_all` for generator suites** — build once into a public `world` / `model`; only re-generate in determinism tests that must compare two seeds.
3. **Smaller maps in tests/smoke** — integration sizes (e.g. 64×42 world, 48×32 region) beat playable 128×84. Keep playable defaults for real play.
4. **Pure fixtures first** — `civilian_fixture.gd` / `naval_fixture.gd` for rules; reserve MapScreen for UI/wiring.
5. **Tear down hard** — `free()` MapScreens in `after_each` (not only `queue_free`) so prior screens do not keep processing under coverage.
6. **CI parallel** — `gd-tools test --coverage --min 80 --parallel 4 --timeout 240`. Job `timeout-minutes: 5` for `tests`, `2` for `e2e-smoke`.

## E2E smoke

- Budget ≤ 2 min wall; prefer ≪ 30s.
- Set `main.map_width` / `map_height` before `add_child` (see `tools/e2e_smoke.gd`).
- Few `await process_frame`; no `sleep`, no full campaigns, no second suite.
- Deep rules belong in `tests/`, not smoke.

## What not to do

- Raise CI timeouts to hide slowness.
- Lower `--min 80` or delete asserts to go green faster.
- Regenerate full worlds inside every `before_each`.
- Add sleeps “for stability.”
- Invent a second e2e runner.

## Prove it

```bash
gd-tools test --coverage --min 80 --parallel 4 --timeout 240 --durations 15
/usr/bin/time -p godot --headless --path . --script res://tools/e2e_smoke.gd
```

Cite before/after wall times in the PR.
