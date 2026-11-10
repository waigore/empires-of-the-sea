# Test speed playbook

Prefer reuse over new harnesses. See [`docs/testing.md`](../../../../docs/testing.md).

## gd-tools quirks

- Each test method runs on a **new suite instance**. Instance fields set in `before_each` do not persist across tests.
- `before_all` runs on the suite context; the runner copies **non-underscore** script vars onto each test instance. Underscore-prefixed names are **not** copied.
- Default per-test timeout comes from `gd-tools.toml`. Suite hook budget is the max of declared test timeouts.
- Coverage instrumentation multiplies setup cost. Profile with `--coverage`, not bare `gd-tools test`.

## Highest-ROI fixes

1. **Shared fixtures** — cache expensive worlds/setups once per worker; attach rather than regenerate.
2. **`before_all` for generator suites** — build once into a public var; only re-generate when determinism requires two seeds.
3. **Smaller maps in tests/smoke** — keep playable defaults for real play; shrink fixtures for CI.
4. **Pure fixtures first** — reserve full screen suites for UI/wiring.
5. **Tear down hard** — free screens in `after_each` so prior instances do not keep processing under coverage.
6. **CI parallel** — `gd-tools test --coverage --min 80 --parallel 4 --timeout 240`.

## E2E smoke

- Budget ≤ 2 min wall; prefer much less.
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
