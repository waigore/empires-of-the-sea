# Testing

Unit/integration tests and the headless e2e smoke. Budgets are hard CI gates.

## Budgets

| Suite | Command | Budget |
|-------|---------|--------|
| Unit + coverage | `gd-tools test --coverage --min 80 --parallel 4` | **≤ 5 min** (CI job `tests`) |
| E2E smoke | `godot --headless --path . --script res://tools/e2e_smoke.gd` | **≤ 2 min** (CI job `e2e-smoke`) |

CI enforces these with job `timeout-minutes` (`5` / `2`) and a 240s gd-tools `--timeout`.

## E2E smoke hard gate

Smoke must complete **one player turn** on the live main scene without unexpected failures. In that turn it exercises player actions that touch each unit type: civilians (select, march, work, cancel, train), navy (select, sail/dock), and army (deferred recruit toast only until the military slice). Deep rules stay in `tests/`.

## Speed rules

- Prefer pure fixtures (`civilian_fixture`, `naval_fixture`) over full map screens.
- MapScreen suites use `tests/map_fixture.gd`: one cached small world per worker, injected via `MapScreen.preset_world`.
- Cache shared maps in `before_all` on **non-underscore** vars (gd-tools copies those onto each test instance; `_foo` is not copied).
- Do not regenerate large worlds in `before_each`. Profile with `gd-tools test --durations 20`.
- Smoke: short boot, few `await process_frame`, no sleeps / full campaigns.

## Local

```bash
gd-tools test --coverage --min 80 --parallel 4
godot --headless --path . --script res://tools/e2e_smoke.gd
```

Coverage gate remains **80%**. See [`pull-requests.md`](pull-requests.md) for required checks.
