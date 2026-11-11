# Improvements and estates

Per-tile improvements, town development and estates.
**Pillars:** P1, P2 (rules), P3 (rules/view), P5 (agency).

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Setup post-pass

`WorldBootstrap` seeds capital ports and harbour roads, a town (level ≥1) per
province, Great Powers at level 4 and four L1 grain farms wired to the seat.

## Implemented

- **Named improvements** follow the resource: Timber → Lumber camp,
  Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** A Builder raises a tile one level for 1/4/8/16 lumber + cast
  iron over its target-level turns. Tiles need a crowned resource; minerals need
  prospecting; orders above a cap are refused.
- **Terrain caps:** scrub caps timber at 1; hardwood follows tech.
- **Path transport:** a tile's cap is the bottleneck of its best road/rail/port
  route to the capital; tiles beside the network take it, and several routes use
  the highest.
- **Init town roads:** setup roads every owned Old World town to its crown;
  New World towns wait for built roads (wiki: capital-and-connectivity).
- **Town rule:** estates 4-adjacent to a province town extract; capital
  provinces cap yield at town development, and a non-capital port town caps the
  tiles that reach the crown through it. An estate on (or beside) a crown road
  ignores the town cap.
- **Town development 1–4** comes from a Builder `upgrade_town` order (National
  Bureaucracy). Level 2 or 4 adds town manufacturing ([economy.md](economy.md)).
- **Assignment can cross the map.** A Builder may target another owned tile;
  materials are paid at assign and refunded on cancel.
- **Extraction** runs after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`. Only
  connected, prospected improvements yield; purchased enclaves pay their buyer.
- **Survey lens** (`LENS`, **L**): a slip per charted province; seals
  show each resource tile (ring = status, pips = level), plus a worked badge,
  bar and a link row (developed estates linked). It draws the built roads and
  railroads — solid when linked, dashed when cut — so the chart shows no roads.
  Unknown ground is never surveyed.
- **Estates ledger** (`ESTATES`, or **Build Improvement**): realm totals,
  province groups, filters, blockers, Build / Cancel / Map, caps and nearest
  idle Builder; a cut-off estate names its gap to the crown.
- **Province dossier**: town level and live crown link (repainted on work);
  Upgrade Town waits for tech.

## Deferred (REQ-P2-02)

- Forts and rival/AI builders.
- Minor/Tribe town manufacturing offers; overseas town manufacturing.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/world_bootstrap.gd` | ports, roads, farms, baseline towns |
| `scripts/rules/improvement_catalog.gd` | names, commodities, yield |
| `scripts/rules/terrain_caps.gd` | terrain hard caps |
| `scripts/rules/land_connectivity.gd` | road/town rules, path transport |
| `scripts/rules/town_industry.gd` | town manufacturing |
| `scripts/rules/improvement_*.gd` | ledger, dispatch, connectivity wrapper |
| `scripts/rules/resource_survey.gd`, `scripts/rules/resource_routes.gd` | survey, roads, plaques |
| `scripts/ui/lens_legend.gd` | survey key |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_*.gd`, `province_*.gd` | ledger shell, rows, province dossier |


## Tests

`test_world_bootstrap`, `test_civilian_field_rules`, `test_economy_rules`,
`test_map_generator`, `test_save_world`, `test_map_screen_crown_orders`,
`test_resource_survey`, `test_resource_lens`, `test_province_panel`.
