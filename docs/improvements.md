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
  iron over its target-level turns. Tiles need a crowned resource; minerals need
  prospecting. Orders above a cap are refused.
- **Terrain caps:** scrub forest caps timber at 1; hardwood follows tech.
- **Path transport:** a tile's cap is the bottleneck of its best road/rail/port
  route to the capital; tiles beside the network take that cap, and several
  routes use the highest.
- **Init town roads:** setup roads every owned Old World town to its crown;
  New World towns wait for built roads (wiki: capital-and-connectivity).
- **Town rule:** estates 4-adjacent to a province town extract; capital
  provinces cap yield at town development, and a non-capital port town caps the
  tiles that reach the crown only through it. An estate on (or beside) a road to
  the crown ignores the town cap.
- **Town development 1–4** comes from a Builder `upgrade_town` order (National
  Bureaucracy). Level 2 or 4 adds town manufacturing ([economy.md](economy.md)).
- **Assignment can cross the map.** A Builder may target another owned tile
  and returns on cancel. Materials are paid at assign.
- **Extraction** runs after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`. Only
  connected, prospected improvements yield; purchased enclaves pay their buyer.
- **Survey lens** (`LENS`, **L**): a parchment slip per charted province; seals
  show each resource tile (ring = status, pips = level), plus a worked badge and
  bar. Unknown ground is never surveyed.
- **Estates ledger** (`ESTATES`, or **Build Improvement**): realm totals,
  province groups, filters, blockers, Build / Cancel / Map, caps and nearest
  idle Builder. A cut-off estate names its gap to the crown.
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
| `scripts/rules/resource_survey.gd`, `scripts/map/resource_lens.gd` | survey projection and plaques |
| `scripts/ui/lens_legend.gd` | survey key |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_*.gd`, `province_*.gd` | ledger shell, rows, province dossier |

Rules stay node-free (`REQ-P3-03`); panels read ledger rows and emit intents.

## Tests

`test_world_bootstrap`, `test_civilian_field_rules`, `test_economy_rules`,
`test_map_generator`, `test_save_world`, `test_map_screen_crown_orders`,
`test_resource_survey`, `test_resource_lens`, `test_province_panel`.
