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

# Free-playtest drives (opt-in, not a CI gate). Every one launches the real flow
# through `tests/playtest_launch.gd` (title -> setup -> capital chart -> map), so
# a flow change that strands a drive fails loudly instead of printing one line.

# New World exploration loop — boards an Explorer, takes the Passage, lands,
# charts and prospects, printing one line per step.
godot --headless --path . --script res://tests/playtest_new_world.gd

# Quick Battle — declares war, resolves an attacking field battle, a siege and a
# defending battle through the play helpers, printing every despatch line the
# plate shows.
godot --headless --path . --script res://tests/playtest_quick_battle.gd

# Battle Simulator — a visual sandbox over the live Quick Battle resolver:
# ground, fort, gates, regiments and a step-by-step plate (battle-sim.md).
tools/run.sh scenes/battle_sim.tscn

# Land combat — a multi-attacker chain, an unopposed capture, a peaceful third
# army blocking one, the player defending a fort through a whole AI turn, and two
# crowns falling on one province in a single turn (plates, standards, court news).
godot --headless --path . --script res://tests/playtest_combat_chain.gd

# Espionage — opens a turn-100 advanced start, despatches a spy across a border,
# ends a real turn and prints the dossier, the presence reveal, the despatch the
# court keeps, the research share it earns, and the counter-espionage screen.
godot --headless --path . --script res://tests/playtest_espionage.gd

# Province development — opens a turn-100 advanced start, raises an estate over
# several turns from the estates ledger, walks the Engineer tile by tile laying
# the road to the capital, prospects and mines a mineral and upgrades a town,
# asserting that each linked estate's commodity reaches the stockpile.
godot --headless --path . --script res://tests/playtest_province_dev.gd

# Allied defence — signs a formal alliance at court, lets a rival declare on the
# ally, reads the call-to-arms banner, joins, and fights the battle the court did
# not start; then two declarations in one turn (one call at a time, a refusal's
# price).
godot --headless --path . --script res://tests/playtest_allied_defence.gd
```

See [`pull-requests.md`](pull-requests.md) for required checks.
