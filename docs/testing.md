# Testing

Unit/integration tests and the headless e2e smoke. Two CI tiers; budgets are hard gates.

## Tiers

| Tier | When | Command / gate | Budget |
|------|------|----------------|--------|
| **1 (PR)** | Code/test path PRs | Impacted suites via [`tests/impact_map.toml`](../tests/impact_map.toml) + `tools/select_impacted_tests.py`; **80% patch coverage** on changed executable lines; e2e smoke | tests **≤ 5 min**; smoke **≤ 2 min** |
| **2 (trunk)** | Every **8 hours** on `main` (+ manual) | Full suite as **4 shards** (`--shard K/4`, one matrix job each); merged shard coverage, then `gd-tools coverage show --min 80` | shard **≤ 20 min**; gate **≤ 10 min** |

Tier 1 is the merge gate (`tests` / `e2e-smoke`). Tier 2 does not block PRs; failures open a sticky `ci-tier2` issue the **fix-tests** agent closes.

Tier 2 shards because `gd-tools` boots one Godot process **per suite**; shards run on separate runners and `coverage-gate` merges their coverage so the 80% gate spans the project.

Strict map: unmapped in-scope paths fail. `full = true` runs every suite. Keep the map complete (`python tools/select_impacted_tests.py --check-complete`).

Patch coverage uses gd-tools’ plan (test dirs are not instrumented). Empty patches pass.

## E2E smoke (tier 1)

Smoke boots the title, starts a game, opens the menu, saves, plays **one turn** (civilians / navy / army), loads, returns to title. Deep rules stay in `tests/`.

## Speed rules

- Prefer pure fixtures (`civilian_fixture`, `naval_fixture`) over map screens.
- One cached small world per worker via `MapScreen.preset_world` /
  `Main.preset_world`; snapshot/restore when a case mutates the chart.
- Smallest world that validates a `SaveCodec` slot and seats the turn-100
  civilians, passing fair split on the **first** attempt.
- Terrain wash (`MapWash.baked`) and fog coast tables (`VisibilityModel`) build
  once per map state — many mounts repaint nothing.
- Chart layers bake on change (`CountryBorders.signature`, `MapLens.source_key`):
  a re-seat of the same chart redraws nothing; `sync_visibility` raises
  `fog_changed` only when a tile moved.
- A mount paints chips, minimap and readings once (`load_region`); `build_hud`
  adds turn, economy, income and dossier.
- Cache shared maps in `before_all` on **non-underscore** vars, attached lazily
  (`_attach()`) so rule-only cases never paint; region-only suites too.
- **One mount per suite**: `MapFixture.suite_capture` / `suite_reset` re-seat a
  case on a pristine save (~0.15 s) instead of remounting (~0.5 s), dropping
  selection, sheets, lenses and news; a suite that swaps screens frees its own.
  `SaveCodec.restore` is the in-place path; reuse a preset only when sizes match.
- **One resolved turn per suite**: resolve once in `before_all`, capture the
  session and `ai_turns`, then re-seat each case (~0.2 s vs ~1.5–2 s). Mode
  cases start at turn 1. `test_ai_observer` is the reference.
- **Generate only what a case reads**: one-region rules call `generate_region`,
  not `generate_world` (builds and discards the other region).
- One Godot boot per theme (merged pure suites) — coverage ~6 s a boot: fold
  leftovers in; delete suites already covered elsewhere. `gd-tools.toml` keeps
  `parallel = 4`; profile with `--durations 20`. Smoke: short boot, no sleeps.

## Local


```bash
# Tier 1-shaped (changed files vs HEAD / base)
python tools/select_impacted_tests.py --base origin/main --print-command
gd-tools test --coverage --timeout 240 --parallel 4 $(python tools/select_impacted_tests.py --base origin/main | grep -v '^ALL$' | grep -v '^NONE$')
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80

# Tier 2-shaped (one shard; CI runs all four, then merges coverage and gates 80%)
gd-tools test --coverage --shard 1/4 --parallel 4
godot --headless --path . --script res://tools/e2e_smoke.gd

# Free-playtest drives live under playtests/ (opt-in, not a CI gate). Every one
# launches the real flow through playtests/playtest_launch.gd (title -> setup ->
# capital chart -> crown's charge -> map), so a flow change that strands a drive
# fails loudly instead of printing one line.

# New World exploration loop — boards an Explorer, takes the Passage, lands,
# charts and prospects, printing one line per step.
godot --headless --path . --script res://playtests/playtest_new_world.gd

# Quick Battle — declares war, resolves an attacking field battle, a siege and a
# defending battle through the play helpers, printing every despatch line the
# plate shows.
godot --headless --path . --script res://playtests/playtest_quick_battle.gd

# Battle Simulator — a visual sandbox over the live Quick Battle resolver:
# ground, fort, gates, regiments and a step-by-step plate (battle-sim.md).
tools/run.sh scenes/battle_sim.tscn

# Land combat — a multi-attacker chain, an unopposed capture, a peaceful third
# army blocking one, the player defending a fort through a whole AI turn, and two
# crowns falling on one province in a single turn (plates, standards, court news).
godot --headless --path . --script res://playtests/playtest_combat_chain.gd

# Espionage — opens a turn-100 advanced start, despatches a spy across a border,
# ends a real turn and prints the dossier, the presence reveal, the despatch the
# court keeps, the research share it earns, and the counter-espionage screen.
godot --headless --path . --script res://playtests/playtest_espionage.gd

# Rival espionage — plays real turns from a turn-100 advanced start and prints
# the spies rivals walk onto crown land, the screen kept at home, the lines a
# catch or a turncoat earns, and the share a rival's spy takes from our studies.
godot --headless --path . --script res://playtests/playtest_ai_spycraft.gd

# Province development — raises an estate from the estates ledger, walks the
# Engineer tile by tile to the capital, prospects and mines a mineral, upgrades
# a town, and asserts each linked estate's commodity reaches the stockpile.
godot --headless --path . --script res://playtests/playtest_province_dev.gd

# Allied defence — signs a formal alliance at court, lets a rival declare on the
# ally, reads the call-to-arms banner, joins, and fights the battle the court did
# not start; then two declarations in one turn (one call at a time, a refusal's
# price).
godot --headless --path . --script res://playtests/playtest_allied_defence.gd

# Persistence — opens a turn-100 advanced start, sets the crown's battle plan and
# issues orders, saves and loads through the pause menu's own browsers, then
# walks the endings a save must carry (decided, defeated, halted) and the slots
# that cannot be read (a newer format, a corrupt file).
godot --headless --path . --script res://playtests/playtest_persistence.gd

# Persistence, advanced — closes turns, then saves and compares the college,
# estate, purse and plan reads a player makes.
godot --headless --path . --script res://playtests/playtest_persistence_advanced.gd

# Naval squadron — boards a field army and sorties, lands it, blockades a rival
# shore, resolves a sea battle (the despatch against the hulls actually lost),
# and sorts a rival squadron out of a captured port.
godot --headless --path . --script res://playtests/playtest_naval.gd

# Beachhead — boards a field army and marks a landing site on a hostile coast,
# reads the same-turn refusal, lands on the ready turn into the land battle, and
# watches the site's three deaths: sailed away, left unused, and peace made.
godot --headless --path . --script res://playtests/playtest_beachhead.gd

# Rival overseas invasion — plays an all-AI campaign and reads every expedition
# (boarding, Passage, beachhead, landing) beside the landing gate's own verdict,
# so a stalled expedition names the gate that refused it.
godot --headless --path . --script res://playtests/playtest_overseas_invasion.gd

# Sighted strength — sights a hostile squadron and reads the marker's `*`, the
# dossier's `???` and the zone that takes no verdict; closes a turn to read the
# watch's news, then checks the read survives another chart and a save.
godot --headless --path . --script res://playtests/playtest_naval_intel.gd

# Treasury — reads the purse the player sees (chip, ledger summary and "Next
# turn" promise, market rows, college funding), stages a sale and a study on
# those buttons, closes real turns, and prints each promise against the ducats.
godot --headless --path . --script res://playtests/playtest_treasury.gd

# Workshop — presses the PRODUCTION tab's own buttons: orders three steel, reads
# the price the promise charges, watches the paid batch land a unit a phase, lets
# two alloy batches serve at once, and saves and loads a batch off the anvil.
godot --headless --path . --script res://playtests/playtest_workshop.gd

# Capital loss — storms the crown's seat while it still holds another province
# (the court moves, the home squadron re-moors, the Gazette names the province
# lost), then strips the crown to its seat and storms that (the defeat plate, the
# sealed turn, and the save that restores the defeated campaign).
godot --headless --path . --script res://playtests/playtest_capital_move.gd

# Field hospital train — pitches the army's own tents from the dossier (reading
# the caption, the receipt and the strength line), mauls two hosts on bare ground
# to read 40% against 25% over a real turn, seats a General hospital to read the
# better-of rule and an unfed ward, then splits, boards, combines and saves.
godot --headless --path . --script res://playtests/playtest_field_train.gd

# Court proposals — plays England (not the catalog's player slot) and answers a
# rival's white peace, alliance, trade pact and non-aggression offer on the
# consent banner's own buttons, reading the banner, the despatch and the court
# chronicle in between; then saves with an offer still waiting, reloads and
# answers it, and reads the call to arms the restored ledger still raises for an
# ally.
godot --headless --path . --script res://playtests/playtest_court_proposal.gd

# War toasts (#426) — ends turns with spies abroad and diffs HUD war lines against
# warDeclared / At War (duplicate AI + spy + intervention announce).
godot --headless --path . --script res://playtests/playtest_war_toasts.gd

# College debt — books every slot at Maximum from the college's own buttons on a
# turn-0 crown that may not borrow and walks real turns until a study starves,
# then seats a Money Lending crown at the -500 floor's edge and reads the phase's
# last payment, the floor it will not pass, and every line the court is told.
godot --headless --path . --script res://playtests/playtest_college_debt.gd

# Trade terms — walks the colony chain, bids the colony's own good (the Deal Book
# must name the favoured fill), boycotts a rival and reads that crown's taxed
# sale receipt against the rate its page prints.
godot --headless --path . --script res://playtests/playtest_trade_terms.gd

# Market receipt — signs a favoured trading pact, buys five tons at its rate and
# reads the Deal Book line against the ducats the clearing charged, then claims a
# good with production runs and reads the row's sellable cap.
godot --headless --path . --script res://playtests/playtest_market_receipt.gd

# Sieges — raises a wall from the Engineer's own order (caption, receipt,
# despatch, province sheet, military lens), storms rival walls at wood and modern
# levels with guns and reads the plate's wall block, the battery, the lanes, the
# gates and the level the fort is left at, then mans the crown's own frontier wall
# and reads the defending plate.
godot --headless --path . --script res://playtests/playtest_siege.gd

# Colony chain — opens the turn-100 advanced start (the New World charted, so a
# Tribe is in contact) and walks the four overture stages on the court sheet's own
# buttons, reading the sheet, the despatch and the chronicle at each step; then
# founds the colony, reads what the crown now holds (status, survey, chronicle,
# envoy), checks the court will not sell the same colony twice, and issues the
# boycott the colony unlocks against a rival crown.
godot --headless --path . --script res://playtests/playtest_colony.gd

# Campaign end — the hardest state in the game to reach (the calendar cap is turn
# 201 and the bar is 31 Old World provinces). Seats the turn number and the
# holdings, then closes real turns: reads the Gazette's age tab and the sheet's
# foot, the three-province warning, the campaign-complete plate and the seal at
# the cap, the halted save reloaded, an Endless campaign sailing past the cap,
# and a rival on the bar taking the military plate — then reads the deciding
# turn's own sheet once the plate steps aside.
godot --headless --path . --script res://playtests/playtest_campaign_end.gd
```

See [`pull-requests.md`](pull-requests.md) for required checks.
