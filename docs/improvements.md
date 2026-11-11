# Improvements and estates

Per-tile improvements, town development and the estates ledger.
**Pillars:** P1, P2, P3, P5.

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Setup post-pass

`WorldBootstrap` seeds capital ports and harbour roads, a town (level ≥1) per
province, Great Powers at level 4 and four L1 plains grain farms at the seat.

## Implemented

- **Named improvements** follow the resource: Timber → Lumber camp,
  Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** A Builder raises a tile one level for 1/4/8/16 lumber + cast
  iron over target-level turns. Needs a crowned resource; minerals need
  prospecting; orders above a cap are refused.
- **Terrain caps:** scrub caps timber at 1; hardwood follows tech.
- **Path transport:** bottleneck of the best road/rail/port route to the
  capital; beside-network tiles take it; several routes use the highest.
- **Init town roads:** setup roads every owned Old World town to its crown;
  New World towns wait for built roads.
- **Town rule:** estates 4-adjacent to a province town extract; capital
  provinces cap at town development; a non-capital port town caps tiles that
  reach the crown through it. An estate on (or beside) a crown road ignores the
  town cap.
- **Town development 1–4** via Builder `upgrade_town` (National Bureaucracy).
  Level 2 or 4 adds town manufacturing ([economy.md](economy.md)).
- **Cross-map assign.** A Builder may target another owned tile; materials paid
  at assign.
- **Extraction** after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`. Only
  connected, prospected improvements yield; purchased enclaves pay their buyer.
- **Survey lens** (`LENS`, **L**): slip per charted province; seals show each
  resource tile, worked badge, bar, link row. Yields take Extraction's caps
  (terrain, path transport, town cap), never promising more.
  Draws roads — solid when linked, dashed when cut. Unknown ground is
  never surveyed.
- **Crown-road lens** (`R`): gold where the crown road reaches, amber where
  only the province town does, crimson where nothing does; a cut province shows
  the road tiles still to lay, their count and the route.
- **Estates ledger** (`ESTATES`): realm totals, filters, blockers, Build /
  Cancel / Map, caps, nearest Builder; cut-off estates name the gap.
- **Province dossier**: town level, live crown link; Upgrade Town waits for tech.

## Deferred (REQ-P2-02)

Minor/Tribe towns stay level 1, so manufacture offers rarely fire. See
[`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/world_bootstrap.gd` | ports, roads, farms, baseline towns |
| `scripts/rules/improvement_catalog.gd` | names, commodities, yield |
| `scripts/rules/terrain_caps.gd` | terrain hard caps |
| `scripts/rules/land_connectivity.gd` | road/town rules, path transport |
| `scripts/rules/town_industry.gd` | town manufacturing |
| `scripts/rules/improvement_*.gd` | ledger, dispatch, connectivity wrapper |
| `scripts/rules/resource_survey.gd`, `resource_routes.gd`, `scripts/map/resource_lens.gd` | survey, roads, plaques |
| `scripts/rules/crown_road_survey.gd`, `scripts/map/crown_road_lens.gd` | crown-road reading and route |
| `scripts/ui/lens_legend.gd` | lens keys |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_*.gd`, `province_*.gd` | ledger shell, rows, dossier |

Rules stay node-free (`REQ-P3-03`); panels read ledger rows and emit intents.

## Tests

`test_world_bootstrap`, `test_civilian_field_rules`, `test_economy_rules`,
`test_map_generator`, `test_save_world`, `test_map_screen_crown_orders`,
`test_resource_survey`, `test_resource_lens`, `test_crown_road_survey`,
`test_crown_road_lens`, `test_province_panel`.
