# Improvements and estates

Per-tile improvements, towns, the estates ledger.
**Pillars:** P1, P2, P3, P5.

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Setup post-pass

`WorldBootstrap` seeds capital ports, harbour roads, a town per province,
level-4 Great Power towns, four grain farms.

## Implemented

- **Named improvements**: Timber → Lumber camp, minerals →
  Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch, crops → Plantation,
  Furs → Fur post, each with its own pictogram (DR-20261119-06).
- **Levels 1–4.** A Builder raises one level for 1/4/8/16 lumber + cast iron
  over target-level turns; minerals need Prospect first (DR-20261111-26),
  above-cap orders refused.
- **Survey (DR-20261111-26).** One charted swamp/hills/mountain/desert tile a
  turn; until surveyed nothing names it; a Builder may mine it.
- **Terrain caps:** scrub timber 1, hardwood follows tech.
- **Path transport:** the best road/rail/port bottleneck; beside-network
  tiles take it, several routes the highest.
- **Init town roads:** every owned Old World town to its crown; New World towns
  wait.
- **Town rule:** estates 4-adjacent to a province town extract; capital
  provinces cap at town development; a non-capital port town caps tiles
  reaching the crown; a crown-road estate ignores the cap.
- **Town development 1–4** via Builder `upgrade_town` (National Bureaucracy);
  level 2 or 4 adds manufactures ([economy.md](economy.md)).
- **Cross-map assign.** Builder may target another owned tile; materials paid
  at assign, lost on cancel.
- **Extraction** after Build/Work:
  `min(improvement, tech cap, terrain cap, transport, town cap)`; only
  connected, prospected estates yield; purchased enclaves pay their buyer.
  Grain and meat pay double per level; the cap line reads the per-level yield
  (DR-20261116-10).
- **Lenses.** Survey (lens seal): a column per resource, emblem and
  `built/linked/held` badge, the Explorer's mark, prospectable tiles; roads
  solid when linked, dashed cut (#698). Crown road (`R`): gold / amber /
  crimson for crown, town-only or cut; cut provinces show the tiles to lay.
- **Estates ledger**: totals, filters, blockers, Build / Cancel / Map, caps,
  a free Builder; cut estates name the gap.
- **One press** (DR-20261116-06): `Raise all ready (n)` files every `READY`
  estate the view prints, in order, stopping at the first refusal with one
  receipt; the line under it prices the walk and its wait (DR-20261118-12).
- **Province dossier**: town level, crown link, estates, unsurveyed ground;
  a cut-off estate carries **Build road**.

## Deferred (REQ-P2-02)

None. A deed raises a Minor/Tribe town (`MinorTownGrowth`, DR-20261112-01).
Gaps: [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/world_bootstrap.gd` | ports, roads, farms, towns |
| `scripts/rules/improvement_catalog.gd` | names, commodities, yield |
| `scripts/rules/mineral_survey.gd` | known-resource predicate, survey |
| `scripts/rules/terrain_caps.gd` | terrain hard caps |
| `scripts/rules/land_connectivity.gd` | roads, town rules, transport |
| `scripts/rules/town_industry.gd` | town manufacturing |
| `scripts/rules/improvement_*.gd` | ledger, dispatch, link |
| `scripts/rules/resource_survey.gd`, `resource_types.gd`, `resource_routes.gd`, `scripts/map/resource_lens.gd` | survey, types, roads |
| `scripts/rules/crown_road_survey.gd`, `scripts/map/crown_road_lens.gd` | crown-road reading |
| `scripts/ui/lens_legend.gd` | lens keys |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_*.gd`, `province_*.gd` | ledger, rows, dossier |

Rules stay node-free (`REQ-P3-03`); panels read rows, emit intents.

## Tests

`test_civilian_turn_rules`, `test_economy_rules`, `test_a_map_screen`,
`test_map_view_rules`, `test_panel_parts_rules`, `test_ledgers`.
