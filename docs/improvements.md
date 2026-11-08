# Improvements and estates

Per-tile extraction improvements built by **Builders**, plus the realm-wide
estates ledger. **Pillars:** P1 (map and ledger feedback), P2 (rules fidelity),
P3 (rules/view split), P4 (turn-based, no per-frame sim).

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap),
[civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units).

## Implemented

- **Named improvements** derive from the tile resource, never the level:
  Timber → Lumber camp, Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool →
  Pasture, Meat/Horses → Ranch. UI may append the level (`Farm (L2)`).
- **Levels 1–4.** A completed Builder order raises the tile one level. Costs
  match the wiki (1/4/8/16 lumber + cast iron) and the order takes its target
  level in turns. Improvements need an owned resource tile; iron, coal, gold
  and tin also need an Explorer to prospect the tile first. Levels above the
  owner's extraction tech cap are refused.
- **Assignment can cross the map.** A Builder order may target another owned
  resource tile; the unit records `origin_tile` / `assigned_tile`, relocates for
  the works and returns on cancel. Materials are paid on assignment and are not
  refunded.
- **Extraction** runs at end of turn after the Build/Work pass. The published
  formula is `min(improvement, tech cap, transport, town development)`. Only
  connected, prospected improvements yield; raw commodities then flow through
  Consumption and Production into lumber, cast iron and the rest of the economy.
- **Connectivity:** the capital tile, built ports and road tiles form the
  network; tiles on or beside it extract. A port seeds its province and its
  four neighbours. `townDevelopment` does not decide connectivity.
- **Map feedback:** improvements draw a category glyph (tree, diamond, stalk or
  coin) plus one gold pip per level.
- **Estates ledger** (`ESTATES` button, or **Build Improvement** in a province):
  whole-realm totals and projected yield, province groups, All/Producing/Works/
  Vacant/Issues filters, plain-text status and blocker reasons, and one-click
  Build, Cancel and Map actions. Each row shows cost, turns, level pips,
  connectivity, tech cap and the nearest idle Builder.

## Tech cap in this slice

No gathering tech tree ships yet, so the wiki default extraction cap **1**
applies: a newly built L1 estate yields its raw commodity, while L2–L4 show
`Needs Tech` until the tech tree lands. Transport path caps are also
tile-level for now.

## Deferred (REQ-P2-02)

- Gathering tech tree (unlocks L2–L4 yields), terrain hard caps.
- Path transport caps, improved roads and rail.
- `upgrade_town` / town development, forts, rival/AI builders.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/improvement_catalog.gd` | names, raw commodities, effective yield |
| `scripts/rules/improvement_system.gd` | connectivity |
| `scripts/rules/improvement_ledger.gd` | estate rows, statuses, totals |
| `scripts/rules/improvement_orders.gd` | nearest-Builder dispatch, cancel |
| `scripts/rules/extraction.gd` | end-turn extraction from improved tiles |
| `scripts/ui/improvement_panel.gd` | ledger shell, summary, filters |
| `scripts/ui/improvement_row.gd` | one estate row and its actions |
| `scripts/map/civilian_layer.gd` | map glyphs, relocation animation |

Rules stay node-free (`REQ-P3-03`); the panel reads ledger rows and emits
intents, and MapScreen applies them through `ImprovementOrders`.
`EconomyController` passes `LandWorks` and the capital tile into extraction.

## Tests

`test_improvement_system`, `test_civilian_work`, `test_extraction`,
`test_map_screen`, `test_economy_screen`.

```bash
gd-tools test --coverage --min 80
```
