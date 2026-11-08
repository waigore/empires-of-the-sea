# Improvements and estates

Per-tile extraction improvements built by **Builders**, plus the realm-wide
estates ledger. **Pillars:** P1 (map and ledger feedback), P2 (rules fidelity),
P3 (rules/view split), P4 (turn-based, no per-frame sim).

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units).

## Implemented

- **Named improvements** derive from the tile resource, never the level:
  Timber → Lumber camp, Iron/Coal/Gold/Salt → Mine, Grain → Farm, Wool →
  Pasture, Horses → Ranch. UI may append the level (`Farm (L2)`).
- **Levels 1–4** produce one unit of the tile commodity per level. Costs match
  the wiki: 1/4/8/16 lumber + cast iron; an order takes its target level in
  turns. Improvements need an owned resource tile; iron, coal and gold mines
  also need an Explorer to prospect the tile first.
- **Assignment can cross the map.** A Builder order may target another owned
  resource tile; the unit records `origin_tile` / `assigned_tile`, relocates for
  the works and returns on cancel. Materials are paid on assignment and are not
  refunded.
- **Extraction** runs at end of turn, after the Build/Work pass. Every connected,
  prospected improvement credits its commodity to the crown's stockpile.
- **Connectivity:** the capital tile, built ports and road tiles form the
  network; tiles on or beside it extract. A port seeds its province and its
  four neighbours. `townDevelopment` does not decide connectivity.
- **Map feedback:** improvements draw a category glyph (tree, diamond, stalk or
  coin) plus one gold pip per level.
- **Estates ledger** (`ESTATES` button, or **Build Improvement** in a province):
  whole-realm totals and projected yield, province groups, All/Producing/Works/
  Vacant/Issues filters, plain-text status and blocker reasons, and one-click
  Build, Cancel and Map actions. Each row shows cost, turns, level pips,
  connectivity and the nearest idle Builder.

## Milestone bridge

The Production phase and raw-stock recipes are not shipped yet. Until they
land, a Lumber camp credits **lumber** and an Iron Mine credits **cast iron**
directly instead of raw timber/iron. This keeps the build economy playable;
the raw → manufactured pipeline is a release-blocking follow-up.

## Deferred (REQ-P2-02)

- Path transport caps (`min(production, road level)`) — need the transport tech
  tree and improved roads/rail.
- Raw → manufactured recipes, labour and Consumption.
- Riches-to-treasury for gold; tech extraction caps and terrain hard caps.
- `upgrade_town` / town development, forts, and rival/AI builders.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/improvement_catalog.gd` | names, commodities, yield, prospect gate |
| `scripts/rules/improvement_system.gd` | connectivity, end-turn extraction |
| `scripts/rules/improvement_ledger.gd` | estate rows, statuses, totals |
| `scripts/rules/improvement_orders.gd` | nearest-Builder dispatch, cancel |
| `scripts/ui/improvement_panel.gd` | ledger shell, summary, filters |
| `scripts/ui/improvement_row.gd` | one estate row and its actions |
| `scripts/map/civilian_layer.gd` | map glyphs, relocation animation |

Rules stay node-free (`REQ-P3-03`); the panel reads ledger rows and emits
intents, and MapScreen applies them through `ImprovementOrders`.

## Tests

`test_improvement_system`, `test_civilian_work`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
