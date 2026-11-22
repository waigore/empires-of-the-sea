# Espionage

Spies observe rival Great Powers, lift research and screen the home provinces
(wiki: [civilian-units § Spy](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[research-state § Spy RP boost](https://github.com/waigore/empires-of-the-sea/wiki/research-state)).

**Pillars:** P2 rules fidelity, P3 pure/testable rules, P4 no per-frame work,
P5 hidden spies leave no trace.

## Implemented

- **Roster:** 2,000 ducats + 4 paper at the capital; any land province, rivals,
  Minors and Tribes included.
- **Presence reveal** (`SpyNetworks`, `CivilianMovement`): a spy on non-owner
  ground holds its tiles visible; it shows no terrain or minerals, and the
  province fogs at once when the last spy leaves (no grace; wiki:
  fog-and-exploration § Fog Decay, civilian-units § Spy, DR-20261110-03).
- **Invisibility:** rival spies are never drawn, hovered or selectable
  (`CivilianLayer.viewer_faction`); the AI never sees human spies.
- **Counter-espionage** (`counter_spy`): an ongoing order on an owned province.
  One screen gives +5% kill chance in every owned province, survivors roll 10%
  defection, and a turned spy changes crown where it stands.
- **Spy death:** relations −8, and the turn's one interaction (wiki: diplomacy).
- **Research boost:** each observed rival adds +15% RP to slots studying a tech
  it knows (funding ≥ Low), stacking before one floor; spies killed that turn
  do not count.
- **Court reports:** one digest per observed rival after resolution — message,
  battles, provinces, finished technologies; never its agenda (`play.court_reports`,
  eight lines at most).
- **Persistence:** spies ride the civilian and save tables; the screen rebuilds
  from `counter_spy` orders.

## The crown's eyes

`SpyLedger` + `SpyLedgerPanel` (DR-20261115-10): the court ledger's **EYES ›**
door (or `I`) opens one sheet — every spy with the duty its posting earns
(`shadow`, `watch`, `screen`, `idle`, `aboard`), every Great Power shadowed or
unobserved, and the screen's state. Visit opens the spy; the sheet moves nothing.

One gold line above the network names the spies the court would book this turn
(DR-20261121-11) — `The court would walk its Spy toward Genoa.` — three named,
the rest counted. Each spy the court would *order* — a walk or a screen — leads
its row with `▸` (DR-20261122-18); a kept spy carries none: keeping is no order.
No spy, no planner, no line; nothing is ordered.

## AI use

`AiSpyPlanner` keeps a spy posted abroad, walks idle spies toward the nearest
unobserved rival Great Power province (one spy per rival first), and raises a
counter-espionage screen at home while at war. Rivals open with a spy and train
more after their builder/engineer/explorer base. AI spies earn the same +15%
boost.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/spy_networks.gd` | presence hosts, qualifying rivals, RP boost |
| `scripts/rules/spy_rules.gd` | screen, dice, kills, defections |
| `scripts/rules/spy_ledger.gd` | the crown's eyes: duties, courts, screen |
| `scripts/rules/civilian_movement.gd`, `civilian_work.gd` | entry and order |
| `scripts/ai/ai_spy_planner.gd` | rival work and march policy |
| `scripts/map/map_play_spies.gd` | resolution and court digest |
| `scripts/map/map_play_spy_pick.gd` | the spies the court would book |
| `scripts/map/map_play_espionage.gd`, `map_play_spy_ai.gd` | player/AI boost wiring |
| `scripts/map/civilian_layer.gd` | invisibility on the map |

## Tests

`test_diplomacy_rules`, `test_ledgers`, `test_panel_parts_rules`, `test_ai_rules`,
`test_research_rules`.

```bash
gd-tools test --coverage --min 80
```
