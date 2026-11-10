# Improvements and estates

Per-tile improvements, town development and the estates ledger.
**Pillars:** P1, P2, P3, P5.

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Setup post-pass

`WorldBootstrap` turns capital ports and harbour roads into `LandWorks`, gives
every province a town (Great Powers 4) and four L1 grain farms at the seat.

## Implemented

- **Named improvements** follow the resource: Timber → Lumber camp,
  Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** A Builder raises a tile one level for 1/4/8/16 lumber + cast
  iron. Tiles need a crowned resource; minerals need prospecting; a cap refuses.
- **Terrain caps:** scrub forest caps timber at 1; hardwood follows tech.
- **Path transport:** a tile's cap is the bottleneck of its best road/rail/port
  route to the capital; tiles beside the network take it, several routes the
  highest.
- **Init town roads:** setup roads every owned Old World town to its crown;
  New World towns wait for built roads.
- **Town rule:** estates 4-adjacent to a town extract; a capital province caps
  at town development, and a non-capital port town caps the tiles that reach the
  crown only through it. An estate on (or beside) a crown road ignores the cap.
- **Town development 1–4** comes from a Builder `upgrade_town` order (National
  Bureaucracy). Level 2 or 4 adds town manufacturing ([economy.md](economy.md)).
- **Assignment can cross the map.** A Builder may target another owned tile and
  returns on cancel; materials are paid at assign.
- **Extraction** runs after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`. Only
  connected, prospected improvements yield; bought enclaves pay their buyer.
- **Survey lens** (`L`, `LENS`): a slip per charted province; seals show each
  resource tile (ring = status, pips = level) with a worked badge and bar.
- **Crown-road lens** (`R`): own land washed gold where the crown road reaches
  it, amber where only the province town does (town development caps that yield),
  crimson where nothing does; a cut province shows the road tiles still to lay,
  their count and the route.
- **Estates ledger** (`ESTATES`): realm totals, filters, blockers, Build /
  Cancel / Map, caps and the nearest idle Builder.
- **Province dossier**: town level, live crown link, Upgrade Town gate.

## Deferred (REQ-P2-02)

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
| `scripts/rules/resource_survey.gd`, `scripts/map/resource_lens.gd` | survey projection and plaques |
| `scripts/rules/crown_road_survey.gd`, `scripts/map/crown_road_lens.gd` | crown-road reading and route |
| `scripts/ui/lens_legend.gd` | lens keys |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_*.gd`, `province_*.gd` | ledger shell, rows, province dossier |

Rules stay node-free (`REQ-P3-03`); panels read ledger rows and emit intents.

## Tests

`test_world_bootstrap`, `test_civilian_field_rules`, `test_economy_rules`,
`test_map_generator`, `test_save_world`, `test_map_screen_crown_orders`,
`test_resource_survey`, `test_resource_lens`, `test_crown_road_survey`,
`test_crown_road_lens`, `test_province_panel`.
