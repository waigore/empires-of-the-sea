# Improvements and estates

Per-tile extraction improvements, town development and the estates ledger.
**Pillars:** P1, P2 (rules), P3 (rules/view), P5 (agency).

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Setup post-pass

`WorldBootstrap` turns capital ports and harbour roads into `LandWorks`
entries, gives every province a town (level ≥1) and Great Powers level 4, plus
four L1 grain farms wired to the seat.

## Implemented

- **Named improvements** derive from the resource: Timber → Lumber camp,
  Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** A Builder raises a tile one level for 1/4/8/16 lumber + cast
  iron over its level's turns. Tiles need a crowned resource; minerals need
  prospecting. Orders above a cap are refused; scrub forest hard-caps timber at
  level 1.
- **Path transport:** a tile's cap is the bottleneck of its best road/rail/port
  route to the capital; tiles beside the network take that path's cap, and
  several routes use the highest.
- **Init town roads:** setup roads every owned Old World town to its crown;
  New World towns wait for built roads (wiki § Init town roads).
- **Town rule:** estates beside a province town extract; a capital province caps
  yield at town development; a port town caps only tiles reaching the crown
  through it; a road-side estate ignores the cap.
- **Town development 1–4** comes from a Builder `upgrade_town` order (National
  Bureaucracy; interim material table). Level 2 or 4 adds town
  manufacturing ([economy.md](economy.md)).
- **Assignment can cross the map.** A Builder may target another owned tile,
  including an enclave; cancel returns it. Materials are paid at assign.
- **Extraction** runs after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`; only
  connected, prospected improvements yield, and purchased enclaves pay.
- **Survey lens** (`LENS`, **L**): a parchment slip per charted province; seals
  show each tile (ring = status, pips = level) and a worked badge. Unknown
  ground is never surveyed.
- **Estates ledger** (`ESTATES`, or **Build Improvement**): realm totals,
  province groups, filters, blockers, Build / Cancel / Map, caps and nearest
  idle Builder. A disconnected estate says how many owned tiles still separate
  it from the crown.
- **Province dossier**: town level and the live crown link (road/port tiles and
  whether its town reaches the capital), repainted when a work completes.

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
| `scripts/rules/resource_survey.gd`, `scripts/map/resource_lens.gd` | survey projection and plaques |
| `scripts/ui/lens_legend.gd` | survey key |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_*.gd` | ledger shell and rows |

Rules stay node-free (`REQ-P3-03`); panels read rows and emit intents.

## Tests

`test_world_bootstrap`, `test_civilian_field_rules`, `test_economy_rules`,
`test_map_generator`, `test_save_world`, `test_map_screen_crown_orders`,
`test_resource_survey`, `test_resource_lens`.
