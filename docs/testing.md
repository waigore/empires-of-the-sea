# Testing

Unit/integration tests and the headless e2e smoke. Two CI tiers; budgets are hard gates.

## Tiers

| Tier | When | Command / gate | Budget |
|------|------|----------------|--------|
| **1 (PR)** | Code/test path PRs | Impacted suites via [`tests/impact_map.toml`](../tests/impact_map.toml) + `tools/select_impacted_tests.py`; **80% patch coverage** on changed executable lines; e2e smoke | tests **≤ 5 min**; smoke **≤ 2 min** |
| **2 (trunk)** | Every **8 hours** on `main` (+ manual) | Full suite as **4 shards** (`--shard K/4`, one matrix job each); merged shard coverage, then `gd-tools coverage show --min 80` | shard **≤ 20 min**; gate **≤ 10 min** |

Tier 1 is the merge gate (`tests` / `e2e-smoke` in CI). Tier 2 does **not** block PRs; failures open one sticky `ci-tier2` issue the **fix-tests** agent fixes, PRs, babysits, and closes.

Tier 2 shards because `gd-tools` boots one Godot process **per suite** and coverage instrumentation costs ~35 s before the first test, so one job is bounded by its suites. Shards run on separate runners; `coverage-gate` merges their coverage so the 80% gate spans the project.

Strict map: unmapped in-scope paths fail selection. `full = true` rules run every suite. Keep the map complete (`python tools/select_impacted_tests.py --check-complete`).

Patch coverage uses gd-tools’ plan (test dirs are not instrumented); changed test files are gated by running their suites. Empty patches pass.

## E2E smoke (tier 1)

Smoke boots the title, starts a new game, opens the in-game menu, saves, completes **one player turn** (civilians / navy / army actions), loads the save, returns to title. Deep rules stay in `tests/`.

## Speed rules

- Prefer pure fixtures (`civilian_fixture`, `naval_fixture`) over full map screens.
- MapScreen and app-shell suites reuse one cached small world per worker via
  `MapScreen.preset_world` / `Main.preset_world` (capital-choice, observer, load).
  Snapshot/restore when a case seats or mutates the chart.
- That world is the smallest that validates a `SaveCodec` slot and seats the
  turn-100 civilian tier; it must pass fair split on the **first** attempt
  (else `generate_world` rebuilds). Screen and campaign-plate suites share it.
- Terrain wash (`MapWash.baked`) and fog coast tables (`VisibilityModel`) build
  once per map state — mounting many screens or six courts' charts repaints nothing.
- Cache shared maps in `before_all` on **non-underscore** vars; attach lazily
  (`_attach()`) so rule-only cases never paint. Region-only suites use
  `generate_region` and cache twin / New World charts in `before_all`.
- Saving/loading: reuse a preset, snapshot owners/deeds (`MapFixture.snapshot`/
  `restore`), prefer `SaveCodec.restore` over remounting. `test_save_codec`
  keeps one MapScreen and resets via a pristine save (rebind layers; no remount).
- One Godot boot per theme (merged pure suites) — coverage costs ~12 s per boot;
  fold leftovers into a theme suite (`test_naval_rules`, `test_campaign_rules`,
  `test_gazette`, `test_defence_lens`, `test_quick_battle_overlay`,
  `test_audio_rules`). Prefer one mount per case. Profile with
  `gd-tools test --durations 20`. Smoke: short boot, few `await process_frame`,
  no sleeps / full campaigns.

## Local

```bash
# Tier 1-shaped (changed files vs HEAD / base)
python tools/select_impacted_tests.py --base origin/main --print-command
gd-tools test --coverage --timeout 240 --parallel 4 $(python tools/select_impacted_tests.py --base origin/main | grep -v '^ALL$' | grep -v '^NONE$')
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80

# Tier 2-shaped (one shard; CI runs all four, then merges coverage and gates 80%)
gd-tools test --coverage --shard 1/4 --parallel 4
godot --headless --path . --script res://tools/e2e_smoke.gd

# Free-playtest drives (opt-in, not a CI gate). Every one launches the real flow
# through `tests/playtest_launch.gd` (title -> setup -> capital chart -> crown's
# charge -> map), so a flow change that strands a drive fails loudly instead of
# printing one line.

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

# Rival espionage — the other half: plays real turns from a turn-100 advanced
# start and prints the spies rival courts walk onto crown land (invisible by
# rule), the screen the crown keeps at home, every line the court is told when
# an agent is caught or turns coat (with the relations it cost), and the share a
# rival's spy earns from the crown's own studies.
godot --headless --path . --script res://tests/playtest_ai_spycraft.gd

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

# Persistence — opens a turn-100 advanced start, sets the crown's battle plan and
# issues orders, saves and loads through the pause menu's own browsers, then
# walks the endings a save must carry (decided, defeated, halted) and the slots
# that cannot be read (a newer format, a corrupt file).
godot --headless --path . --script res://tests/playtest_persistence.gd

# Persistence, advanced — closes turns, starts a study from the college's own
# row and raises an estate, then saves and loads and compares the two snapshots
# field by field plus the college, estate, purse and plan reads a player makes.
godot --headless --path . --script res://tests/playtest_persistence_advanced.gd

# Naval squadron — reads the crown's squadrons and their named hulls, boards a
# field army and sorties, lands it on a crown coast, takes a blockade off a rival
# shore, resolves a sea battle (printing the despatch against the hulls actually
# lost), and sorts a rival squadron out of a captured port.
godot --headless --path . --script res://tests/playtest_naval.gd

# Beachhead — boards a field army and marks a landing site on a hostile coast,
# reads the same-turn refusal, lands on the ready turn into the land battle, and
# watches the site's three deaths: sailed away, left unused, and peace made.
godot --headless --path . --script res://tests/playtest_beachhead.gd

# Treasury — opens a turn-100 advanced start and reads the purse the player sees
# (the chip, the ledger's summary and "Next turn" promise, the market's own rows,
# the college's funding), stages a sale and a study on those buttons, closes real
# turns, and prints each promise against the ducats the turn actually paid.
godot --headless --path . --script res://tests/playtest_treasury.gd

# Workshop — opens a turn-100 advanced start and presses the PRODUCTION tab's own
# buttons: orders three steel and reads the price the promise charges, clears the
# order and watches the paid batch land one unit a phase, contrasts a one-turn
# row, lets two alloy batches serve at once (the note must name the two units the
# promise names), and saves and loads a batch off the anvil.
godot --headless --path . --script res://tests/playtest_workshop.gd

# Capital loss — storms the crown's seat while it still holds another province
# (the court moves, the home squadron re-moors, the Gazette names the province
# lost), then strips the crown to its seat and storms that (the defeat plate, the
# sealed turn, and the save that restores the defeated campaign).
godot --headless --path . --script res://tests/playtest_capital_move.gd

# Field hospital train — pitches the army's own tents from the dossier (reading
# the caption, the receipt and the strength line), mauls two hosts on bare ground
# to read 40% against 25% over a real turn, seats a General hospital to read the
# better-of rule and an unfed ward, then splits, boards, combines and saves.
godot --headless --path . --script res://tests/playtest_field_train.gd

# Court proposals — plays England (not the catalog's player slot) and answers a
# rival's white peace, alliance, trade pact and non-aggression offer on the
# consent banner's own buttons, reading the banner, the despatch and the court
# chronicle in between; then saves with an offer still waiting, reloads and
# answers it, and reads the call to arms the restored ledger still raises for an
# ally.
godot --headless --path . --script res://tests/playtest_court_proposal.gd
```

See [`pull-requests.md`](pull-requests.md) for required checks.
