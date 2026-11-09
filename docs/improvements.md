# Improvements and estates

Per-tile extraction improvements, town development and the estates ledger.
**Pillars:** P1, P2 (rules), P3 (rules/view), P5 (agency).

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Setup post-pass

`WorldBootstrap` turns capital ports and harbour roads into real `LandWorks`
entries, gives every province a town tile and at least town level 1, and gives
Great Powers level 4 plus four guaranteed L1 grain farms wired to the seat.

## Implemented

- **Named improvements** derive from the resource: Timber → Lumber camp,
  Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** A Builder raises a tile one level for 1/4/8/16 lumber + cast
  iron over its target-level turns. Tiles need a crowned resource; minerals need
  prospecting. Orders above the tech or terrain cap are refused.
- **Terrain caps:** scrub forest hard-caps timber at level 1; hardwood follows
  the tech cap.
- **Path transport:** a tile's cap is the bottleneck of its best road/rail/port
  route to the capital. Tiles beside the network take the adjacent path's cap;
  several routes use the highest cap.
- **Town rule:** each province town is 4-adjacent to its extracting tiles.
  Capital provinces cap yield at town development; a connected non-capital port
  town caps its town-connected tiles. Road-connected non-capital tiles ignore
  the town cap.
- **Town development 1–4** comes from a Builder `upgrade_town` order (National
  Bureaucracy; improvement material table, interim). Level 2 or 4 adds town
  manufacturing ([economy.md](economy.md)).
- **Assignment can cross the map.** A Builder may target another owned tile,
  including an enclave, and returns on cancel. Materials are paid at assign.
- **Extraction** runs after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`. Only
  connected, prospected improvements yield; purchased enclaves pay their buyer.
- **Survey lens** (`LENS`, **L**): a parchment slip per charted province; seals
  show each resource tile (ring = status, pips = level), plus a worked badge and
  bar. Unknown ground is never surveyed; units ghost back.
- **Estates ledger** (`ESTATES`, or **Build Improvement**): realm totals,
  province groups, filters, blockers, Build / Cancel / Map, caps and nearest
  idle Builder.

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

Rules stay node-free (`REQ-P3-03`); panels read ledger rows and emit intents.

## Tests

`test_world_bootstrap`, `test_civilian_field_rules`, `test_economy_rules`,
`test_map_generator`, `test_save_world`, `test_map_screen_crown_orders`,
`test_resource_survey`, `test_resource_lens`.
