# Testing

Unit/integration tests and the headless e2e smoke. Two CI tiers; budgets are hard gates.

## Tiers

| Tier | When | Command / gate | Budget |
|------|------|----------------|--------|
| **1 (PR)** | Code/test path PRs | Impacted suites via [`tests/impact_map.toml`](../tests/impact_map.toml) + `tools/select_impacted_tests.py`; **80% patch coverage** on changed executable lines; e2e smoke | tests **≤ 5 min**; smoke **≤ 2 min** |
| **2 (trunk)** | Every **8 hours** on `main` (+ manual) | Full `gd-tools test --coverage --min 80 --parallel 4` | job **≤ 15 min** |

Tier 1 is the merge gate (`tests` / `e2e-smoke` in CI). Tier 2 does **not** block PRs. Failures open/update one sticky GitHub issue labeled `ci-tier2`; the **fix-tests** agent (hourly, gated on that label) fixes, PRs, babysits, and closes it.

Strict map: unmapped in-scope paths fail selection. `full = true` rules run every suite. Keep the map complete (`python tools/select_impacted_tests.py --check-complete`).

Patch coverage uses gd-tools’ plan (test dirs are not instrumented); changed test files are gated by running their suites. Empty patches pass.

## E2E smoke (tier 1)

Smoke boots the title, starts a new game, opens the in-game menu, saves, completes **one player turn** (civilians / navy / army actions), loads the save, returns to title. Deep rules stay in `tests/`.

## Speed rules

- Prefer pure fixtures (`civilian_fixture`, `naval_fixture`) over full map screens.
- MapScreen suites use `tests/map_fixture.gd`: one cached small world per worker via `MapScreen.preset_world`.
- Cache shared maps in `before_all` on **non-underscore** vars.
- Do not regenerate large worlds in `before_each`. Profile with `gd-tools test --durations 20`.
- Saving and loading is the hottest integration path: a preset world is reused by
  `SaveCodec.restore` instead of regenerating, and suites that rewrite owners or
  buy deeds snapshot it (`MapFixture.snapshot` / `restore`) rather than build a world.
- One Godot boot per theme; keep suite count low under coverage.
- Smoke: short boot, few `await process_frame`, no sleeps / full campaigns.

## Local

```bash
# Tier 1-shaped (changed files vs HEAD / base)
python tools/select_impacted_tests.py --base origin/main --print-command
gd-tools test --coverage --parallel 4 $(python tools/select_impacted_tests.py --base origin/main | grep -v '^ALL$' | grep -v '^NONE$')
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80

# Tier 2-shaped
gd-tools test --coverage --min 80 --parallel 4
godot --headless --path . --script res://tools/e2e_smoke.gd

# Free-playtest drive (opt-in, not a CI gate): New World exploration loop —
# boards an Explorer, takes the Passage, lands, charts and prospects, printing
# one line per step.
godot --headless --path . --script res://tests/playtest_new_world.gd
```

See [`pull-requests.md`](pull-requests.md) for required checks.
