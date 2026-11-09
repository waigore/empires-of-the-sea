# Improvements and estates

Per-tile extraction improvements, setup works that make them pay, and the
estates ledger. **Pillars:** P1, P2 (rules), P3 (rules/view), P4.

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap),
[civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units).

## Setup post-pass

`WorldBootstrap` runs once per region before civilians muster:

- Capital ports and harbour roads become real `LandWorks` entries, so
  connectivity sees them instead of only drawing them.
- Great Power capitals get town development 4 and **four grain farms** (L1,
  nearest plains, road to the seat), so the ledger opens producing.

## Implemented

- **Named improvements** derive from the tile resource: Timber → Lumber camp,
  Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** A completed Builder order raises one level; costs match the
  wiki (1/4/8/16 lumber + cast iron), one turn per target level. Improvements
  need a crowned resource tile (province or deed); iron, coal, gold and tin
  also need an Explorer to prospect first. Orders above the tech cap are refused.
- **Assignment can cross the map.** A Builder may target another owned tile,
  including enclaves; the unit relocates and returns on cancel. Materials are
  paid on assignment and not refunded.
- **Extraction** runs at end of turn after Build/Work:
  `min(improvement, tech cap, transport, town development)`. Only connected,
  prospected improvements yield; commodities flow through Consumption and
  Production. Enclaves yield for their buyer.
- **Connectivity:** capital, ports and roads form the network; tiles on or
  beside it extract. A port seeds its province and four neighbours.
- **Map feedback:** improvements draw a category glyph plus one gold pip per
  level.
- **Survey lens** (`LENS`, **L**): a parchment slip per charted province; each
  seal is a resource tile (ring = estate status, pips = level), with a worked
  badge and bar. Unknown ground is never surveyed; units ghost back.
- **Estates ledger** (`ESTATES`, or **Build Improvement** in a province):
  realm totals, province groups, filters, status and blockers, Build / Cancel /
  Map actions, cost, turns, level pips, connectivity, tech cap and nearest idle
  Builder.

## Tech cap

Extraction caps come from researched techs ([technology.md](technology.md)):
`min(improvement, tech cap, transport, town development)`. L1 yields at once;
higher levels need the resource's advance (Saw Mill, Land Enclosure, …); orders
above it are refused.

## Deferred (REQ-P2-02)

- Terrain hard caps; path transport caps (per-tile transport only).
- `upgrade_town` / town development, forts, rival/AI builders.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/world_bootstrap.gd` | ports, harbour roads, grain farms |
| `scripts/rules/improvement_catalog.gd` | names, commodities, effective yield |
| `scripts/rules/improvement_system.gd` | connectivity |
| `scripts/rules/improvement_ledger.gd` | estate rows, statuses, totals |
| `scripts/rules/resource_survey.gd`, `scripts/map/resource_lens.gd` | survey projection and map plaques |
| `scripts/ui/lens_legend.gd` | survey key |
| `scripts/rules/improvement_orders.gd` | nearest-Builder dispatch, cancel |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_panel.gd` | ledger shell, summary, filters |
| `scripts/ui/improvement_row.gd` | estate row and actions |

Rules stay node-free (`REQ-P3-03`); the panel reads ledger rows and emits
intents applied by MapScreen through `ImprovementOrders`.

## Tests

`test_world_bootstrap`, `test_improvement_system`, `test_civilian_work`,
`test_extraction`, `test_map_screen_crown_orders`, `test_economy_screen`,
`test_resource_survey`, `test_resource_lens`.

```bash
gd-tools test --coverage --min 80
```
