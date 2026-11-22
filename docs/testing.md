# Testing

Unit/integration tests and headless e2e smoke; two CI tiers, hard budgets.

## Tiers

| Tier | When | Command / gate | Budget |
|------|------|----------------|--------|
| **1 (PR)** | Code/test path PRs | Impacted suites via [`tests/impact_map.toml`](../tests/impact_map.toml) + `tools/select_impacted_tests.py`; **80% patch coverage** on changed executable lines; e2e smoke + auto | tests **≤ 5 min**; e2e **≤ 5 min** |
| **2 (trunk)** | Every **8 hours** on `main` (+ manual) | Full suite as **4 shards** (`--shard K/4`, one matrix job each); merged shard coverage, then `gd-tools coverage show --min 80` | shard **≤ 20 min**; gate **≤ 10 min** |

Tier 1 is the merge gate; tier 2 failures open a sticky `ci-tier2` issue for
**fix-tests**. Tier 2 shards (`gd-tools` boots one process **per suite**);
the gate merges them for the 80% gate.

Strict map: unmapped paths fail; `full = true` runs every suite
(`select_impacted_tests.py --check-complete`). Empty patches pass.

## E2E (tier 1)

Job `e2e-smoke` (≤5 min): **smoke** (title → one turn → save/load) then
**auto** (Small, five Auto turns, dump asserts). Deep rules in `tests/`.

## Speed rules

- Prefer pure fixtures (`civilian_fixture`, `naval_fixture`) to map screens.
- One cached small world per worker via `MapScreen.preset_world` /
  `Main.preset_world`; snapshot/restore when a case mutates the chart.
- Smallest world that validates a `SaveCodec` slot and seats turn-100 civilians,
  passing fair split on the **first** attempt.
- Terrain wash, fog and chart layers build once per map state; a re-seat
  redraws nothing; `fog_changed` rises on a moved tile.
- Cache shared maps in `before_all` on **non-underscore** vars, attached lazily
  (`_attach()`) so rule-only cases never paint. Chart caches must be `static`
  (gd-tools clones each case). Prefer a pocket chart; one Standard census seed.
- **One mount per suite**: `suite_capture` / `suite_reset` (~0.15 s vs ~0.5 s
  remount); advanced-start live cases share **one mount per tier**. Pure cases
  skip re-seat / shell (lazy `_screen` / `main` / menu-flow `chart`); hospitals
  ride that chart; opening plates use short `hold_max` / `fade_seconds`. Free a
  swapped screen. Far-chart fog / off-screen naval: `world.region` /
  `regions.set_region` — no `_cycle_region`.
- **Tiny fixture first**: names and sea zones use `naval_fixture.build()` (7×3),
  not the 48×32 chart (~9 s covered).
- **One resolved turn per suite**: resolve once in `before_all`, capture the
  session (and `ai_turns` / Auto fields), re-seat lazily (~0.2 s vs ~1.5–2 s).
  Mode cases start at turn 1; shared-pass spy readings stay one `end_turn`.
- **Generate only what a case reads**: one-region rules call `generate_region`,
  never `generate_world`. College rules keep state/purse in `before_each`; bind
  pocket chart and `ResearchPanel` only when read.
- **Heaviest suite sorts first**: name order, four wide — `test_a_map_screen`
  leads so one chart suite does not drain alone.
- One Godot boot per theme — coverage ~15 s; 24 suites; `parallel = 4`.
  Diplomacy/battle court-words book at rules; suspending closes /
  campaign-end use `AiControl.NOOP`; counsel only when court open; plate
  saves reload in-place.
- Smoke/auto: short boot, no sleeps/fades; auto sets `view_live=false`.

## Local


```bash
# Tier 1-shaped (changed files vs HEAD / base)
python tools/select_impacted_tests.py --base origin/main --print-command
gd-tools test --coverage --timeout 240 --parallel 4 $(python tools/select_impacted_tests.py --base origin/main | grep -v '^ALL$' | grep -v '^NONE$')
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80

# Tier 2-shaped (one shard; CI runs all four, then merges coverage and gates 80%)
gd-tools test --coverage --shard 1/4 --parallel 4
godot --headless --path . --script res://tools/e2e_smoke.gd
godot --headless --path . --script res://tools/e2e_auto.gd

# Free-playtest drives live under playtests/ (opt-in, not a CI gate). Every one
# launches the real flow through playtests/playtest_launch.gd (title -> setup ->
# capital chart -> crown's charge -> map), so a flow change that strands a drive
# fails loudly instead of printing one line.

# New World exploration loop — boards an Explorer, takes the Passage, lands,
# charts and prospects, printing one line per step.
godot --headless --path . --script res://playtests/playtest_new_world.gd

# The voyage's landing lines — opens a turn-100 squadron's passenger block and
# presses its own rows: one line per crew kind per coast, the grounds each line
# opens (with what the chart reads of the tile), the crew and the tile the press
# carries, the coast-only caller, and the chart a landing makes.
godot --headless --path . --script res://playtests/playtest_voyage_grounds.gd

# Quick Battle — declares war, resolves an attacking field battle, a battle of
# horse and foot (the wings each line stands in, the flank a blow falls on and
# the break it makes), a siege and a defending battle through the play helpers,
# printing every despatch line the plate shows.
godot --headless --path . --script res://playtests/playtest_quick_battle.gd

# Battle Simulator — mounts the sandbox scene, presses its own rail (ground,
# fort, men, plans, Fight, Next round, Reset) and reads the header, the
# despatch and the plate against the record the live resolver returned; it
# fails loudly when the rail's army, the step walk or the aftermath sheet stops
# matching the game's plate.
godot --headless --path . --script res://playtests/playtest_battle_sim.gd

# Battle Simulator — a visual sandbox over the live Quick Battle resolver:
# ground, fort, gates, regiments and a step-by-step plate (battle-sim.md).
tools/run.sh scenes/battle_sim.tscn

# Land combat — a multi-attacker chain, an unopposed capture, a peaceful third
# army blocking one, the player defending a fort through a whole AI turn, and two
# crowns falling on one province in a single turn (plates, standards, court news).
godot --headless --path . --script res://playtests/playtest_combat_chain.gd

# Routed host — a beaten attacker that keeps men stands on the enemy's ground:
# the despatch, the place line and hint a crown reads there, the tap list that
# holds no own province, the refusal a home march hears, and the walk home one
# province at a time beside the one-march road a bordered host has.
godot --headless --path . --script res://playtests/playtest_routed_host.gd

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

# Civilian pick — opens the turn-100 advanced start as England and reads the
# court's pick on every waiting crew's sheet against the rules, the chart ring
# and the sheet's own presses; raises the picked estate from the estates ledger
# and checks a crew with no order it can take says so.
godot --headless --path . --script res://playtests/playtest_civilian_pick.gd

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

# Station prices — sorties the home squadron, takes a patrol and declares war,
# then reads the dossier's two prices (the catch and the prize) against the pass
# that rolls them: the printed chance and hulls, the fog clause, a Defend
# station, a second station in the group, a blockade's own coast, and the turn's
# battle record.
godot --headless --path . --script res://playtests/playtest_station_prices.gd

# Split / combine — folds the opening's single-hull commands into one squadron,
# reads the troops that hold a split back, detaches a named hull into a command
# of her own, folds her back, and follows the army a combine carries from the
# dossier to the muster roll (the row's place and its own Visit press).
godot --headless --path . --script res://playtests/playtest_fleet_split_combine.gd

# The court's pick — reads the gold line the fleet dossier prints under its
# station in the states a player reaches (in port, at sea at peace, at war, a
# rival in the next water, the holds ashore again) and holds every word to the
# planner's own record: the kind, the water and the harbour, the sheet's print,
# and a roster that did not move.
godot --headless --path . --script res://playtests/playtest_fleet_pick.gd

# Beachhead — boards a field army and marks a landing site on a hostile coast,
# reads the same-turn refusal, lands on the ready turn into the land battle, and
# watches the site's three deaths: sailed away, left unused, and peace made.
godot --headless --path . --script res://playtests/playtest_beachhead.gd

# Shipyard batch — opens the capital slip as a player does and presses its one
# Launch all ready (n) twice: the arm's face, the receipt, the rows it redraws,
# the arm a redraw must forget, and the slip with no squadron afloat (breaking
# up the last hull) where a launch once left the panel promising hulls the
# recruit queue already held.
godot --headless --path . --script res://playtests/playtest_fleet_yard_batch.gd

# The realm's three views on a live chart (the seat's town and defence figure),
# the province dossier's one Upgrade Town press filing a real Builder's order,
# and the estates card's line held against what its two taps actually raised.
godot --headless --path . --script res://playtests/playtest_raise_line.gd

# Rival overseas invasion — plays an all-AI campaign and reads every expedition
# (boarding, Passage, beachhead, landing) beside the landing gate's own verdict,
# so a stalled expedition names the gate that refused it.
godot --headless --path . --script res://playtests/playtest_overseas_invasion.gd

# New World land war — reaches the crown's land on the New World chart (the
# turn-100 start leaves three colonies there), declares war on the Tribe beside
# it and storms a province, reading every surface the court meets there: the
# despatches, the army dossier and its counsel, the province sheet and the realm
# reading. A third pass queues a hire, a muster and a launch at the seat, flips
# the chart to the colony and closes the turn, so a seat-scoped order that lands
# on the chart on screen (or is lost there) reads in one line. A fourth pass
# leaves a host cut off on ground with no crown land beside it and reads the
# walk-home words: on a chart that holds no seat, the rule names the sea.
godot --headless --path . --script res://playtests/playtest_new_world_war.gd

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

# Join Empire — seats the last rung's chain with a Great Power, a Minor and a
# Tribe, then holds the row's words to the rule's two roads (nearly defeated, or
# our power twice its own), the warmth gate at 50 and 51 against the herald's
# word, the press a standing crown answers, and the provinces, regiments and
# hulls that change flags on an absorption.
godot --headless --path . --script res://playtests/playtest_join_empire.gd

# War toasts (#426) — ends turns with spies abroad and diffs HUD war lines against
# warDeclared / At War (duplicate AI + spy + intervention announce).
godot --headless --path . --script res://playtests/playtest_war_toasts.gd

# College debt — books every slot at Maximum from the college's own buttons on a
# turn-0 crown that may not borrow and walks real turns until a study starves,
# then seats a Money Lending crown at the -500 floor's edge and a Money Lending
# and Banking crown at the -1,000 floor, reading the phase's last payment, the
# floor it will not pass, every line the court is told, and the MARKET tab's bid
# budget and dead Bid presses with the purse in debt.
godot --headless --path . --script res://playtests/playtest_college_debt.gd

# College batch — the college's one press (DR-20261118-26): books two studies from
# the college's own buttons, steps the press to High, presses it and reads the
# receipt, then closes a real turn so the phase pays what the line promised; then
# a thin purse (three studies at Maximum, 1,000 ducats) so the line and the
# receipt must name the studies that wait; then the whole college stood down to
# None; then the same sheet on a 720x360 handset, reading the press, its line and
# the room the two lists keep under it.
godot --headless --path . --script res://playtests/playtest_college_batch.gd

# Trade terms — walks the colony chain, bids the colony's own good (the Deal Book
# must name the favoured fill), boycotts a rival and reads that crown's taxed
# sale receipt against the rate its page prints.
godot --headless --path . --script res://playtests/playtest_trade_terms.gd

# Deed share — a deed's first right of refusal as a rival's fill pays it: reads the
# crew's Deed row on the turn-100 start, stages a rival's bid on the crown's sold
# ground and closes a real turn, then reads the LAST CLEARING (the total and the
# fills under it), the despatch and the purse; then bids on its own deed's units
# and reads the row that names the first refusal.
godot --headless --path . --script res://playtests/playtest_deed_share.gd

# Market receipt — signs a favoured trading pact, buys five tons at its rate and
# reads the Deal Book line against the ducats the clearing charged, then claims a
# good with production runs and reads the row's sellable cap.
godot --headless --path . --script res://playtests/playtest_market_receipt.gd

# Market batch — reads every whole-order press on the MARKET tab (label, caption,
# single press) and presses them past their own cap: a production claim, a staged
# offer, a bid that empties the holds, and a Minor row whose ask carries a
# subsidy step against a purse that binds at the ask.
godot --headless --path . --script res://playtests/playtest_market_batch.gd

# Sieges — raises a wall from the Engineer's own order (caption, receipt,
# despatch, province sheet, military lens), storms rival walls at wood and modern
# levels with guns and reads the plate's wall block, the battery, the lanes, the
# gates and the level the fort is left at, then mans the crown's own frontier wall
# and reads the defending plate.
godot --headless --path . --script res://playtests/playtest_siege.gd

# Workers — reads the WORKERS tab as a player does (a row's price and ration, the
# larder's store, appetites and shortfall, the batch press and the queue), presses
# its own peasant press and the batch under it, then closes real turns so the
# phase pays the fabric and feeds the hands; then the trained tiers on the turn-100
# advanced start (disband, a train, a muster and the peasant reservation); then a
# starved larder, holding the tab's forecast to the phase's own report; then a
# second press after the queue has promised the store.
godot --headless --path . --script res://playtests/playtest_workers.gd

# The crown's command — reads the opening pool and the ledger's own lines (count,
# cap road, each commander, the medal note and the fallback), then the turn-100
# advanced start where the cap-raising studies have landed, then fights a real
# land battle and holds the despatch's medal credit to the roster and to the
# ledger's row afterwards, and finally runs one phase of four attacks and a
# defence against a pool of three — the distinct binds, the army left on the
# leader's fallback medals, and each despatch line's own medal count.
godot --headless --path . --script res://playtests/playtest_command.gd

# Observer siege — seats a wall, its garrison and a besieging train between two
# rival crowns in the full-AI observer, then reads the panel's orders feed, the
# cards, the merged turn record and the province the rules actually left.
godot --headless --path . --script res://playtests/playtest_observer_siege.gd

# Observer feed — plays a real all-AI campaign forward and, after every turn,
# reads the panel's "Recent orders" feed against the merged record the same turn
# wrote: how many rows exist, how many the feed prints, which rows a busy turn
# loses, and the plate's geometry (the feed's window, the crowns' room, whether
# the plate scrolls) on the engine's own and on a 720x360 handset viewport.
godot --headless --path . --script res://playtests/playtest_observer_feed.gd

# The ground a province shows — opens every province on the real chart, reads
# the dossier's Terrain row against the ground the Combat phase fights on
# (`ArmyModifiers.terrain_for`), and pins every terrain to the published display
# name; the charts whose tiles tie are generated and read too.
godot --headless --path . --script res://playtests/playtest_terrain_ground.gd

# Colony chain — opens the turn-100 advanced start (the New World charted, so a
# Tribe is in contact) and walks the four overture stages on the court sheet's own
# buttons, reading the sheet, the despatch and the chronicle at each step; then
# founds the colony, reads what the crown now holds (status, survey, chronicle,
# envoy), checks the court will not sell the same colony twice, and issues the
# boycott the colony unlocks against a rival crown.
godot --headless --path . --script res://playtests/playtest_colony.gd

# Colony counsel — the gold line THE COLONIES prints under its chips, held to the
# crown's own press: a pact with a court too cold for the Join Empire, the same
# court warmed, a chain already visited this turn, and the study that holds an
# Embassy, then the honest link; then a fifth chain read on both sheets at once,
# where the colony line may promise the link only when the court's one envoy order
# takes it (DR-20261121-18). Every reading prints the envoy's one order beside it.
godot --headless --path . --script res://playtests/playtest_colony_counsel.gd

# Campaign end — the hardest state in the game to reach (the calendar cap is turn
# 201 and the bar is 31 Old World provinces). Seats the turn number and the
# holdings, then closes real turns: reads the Gazette's age tab and the sheet's
# foot, the three-province warning, the campaign-complete plate and the seal at
# the cap, the halted save reloaded, an Endless campaign sailing past the cap,
# and a rival on the bar taking the military plate — then reads the deciding
# turn's own sheet once the plate steps aside.
godot --headless --path . --script res://playtests/playtest_campaign_end.gd

# Boycott blocked deal — seats the two records no session waits for (a rival
# holding a Tribe as its colony, that rival boycotting the crown), then reads
# what each court is told: the court sheet's trade block and the colony's page
# (where Grant Aid and every subsidy are refused), the market page's offers with
# the bar printed under each shut row and its words in the terms banner, the bid
# pressed from the colony's own row, and the turn close (despatch, LAST
# CLEARING, notes, carry) two turns running.
godot --headless --path . --script res://playtests/playtest_boycott_block.gd

# Defeat — the crown's own end, which no play reaches by hand (terminal fall:
# the capital lost with nothing left in its region). Strips the crown to its
# seat, lets a rival host at war take it in a real Combat phase, then reads the
# battle despatch, the defeat plate, the seal and the turn's sheet in the
# archive; saves and reloads the fallen campaign; presses the seal again; and
# seats a rival on the bar in the same turn to read that the fall, not a
# military victory, decides it.
godot --headless --path . --script res://playtests/playtest_defeat.gd

# The Gazette — the crown's news sheet at the turn's open, its watchlist, its
# archive and the tiers of knowledge it may print. Opens the sheet at turn 1
# (no press has run), plays five turns of a campaign and audits each filed
# sheet (class order, another court's line never counts losses, no item
# without a line, the map agreeing with every capture), queues a worker, a
# crew, a regiment and a hull and reads their delivery lines, fights a real
# battle for the crown and for a watched court (charted, then a chart that
# reaches nothing), strikes a court off against a new war of its own, walks the
# archive's chips and its `<n> of <m>` pages, and saves and reloads the
# campaign to read the watchlist and the sheets back.
godot --headless --path . --script res://playtests/playtest_gazette.gd

# Home fleet at the opening — the one command every Great Power moors at its own
# seat (#1043): reads both charts' rosters for a stray hull id or a second
# command in port, the marker's badge, the fleet dossier, the navy sheet's count
# line and hull rows, the holds the market may spend and the food the navy eats,
# then puts the home squadron to sea and moors her back (one command, holds
# restored), lays a hull down at the seat, and lays one down again with her away
# to read the slip founded there and the merge that follows her home. PT_ADVANCED
# opens a preset start, so the turn-100 galleons read the same way.
godot --headless --path . --script res://playtests/playtest_home_fleet.gd

# Fleets in one station (DR-20261119-08) — the chart's row only appears when
# several of the crown's squadrons hold one water, so the drive reaches it the
# way a player does: a turn-100 home squadron sorties, then detaches hulls until
# four commands stand in the sea zone. It reads the plan (who takes a row step,
# who is covered, where each hull is drawn), taps every drawn point and a covered
# one, hears the words of all of them, seats a rival in the same water (the stack,
# the pennant and `observe only`), and hides her to read the fog: no hull, no
# pennant, no place in the count.
godot --headless --path . --script res://playtests/playtest_station_fan.gd

# A whole standard campaign — plays a new Standard game (seed 1500, Spain) through
# the real flow, closes one turn from the crown's own seal and hands the seat to
# Auto for the rest, printing each close's bar, undelivered news, purse, regiments,
# hulls, crews and holdings beside what the rules paid, auditing every panel family
# (capital, people, muster, realm, eyes, colonies, command, navy, army, ledger,
# college, court) every ten turns, and checking the standing invariants after every
# turn, so a curve that stops moving, a purse that stops paying or an age that ends
# early names itself. `--turns`, `--seed`, `--size`, `--faction`, `--advanced`,
# `--audit-every` and `--auto=0` (the crown keeps its own seat).
godot --headless --path . --script res://playtests/playtest_standard_campaign.gd
```

See [`pull-requests.md`](pull-requests.md) for required checks.
