# Improvements and estates

Per-tile improvements, towns and the estates ledger.
**Pillars:** P1, P2, P3, P5.

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Setup post-pass

`WorldBootstrap` seeds capital ports, harbour roads, a town per province,
level-4 Great Power towns and four L1 grain farms.

## Implemented

- **Named improvements** follow the resource: Timber → Lumber camp, minerals →
  Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** Builder raises one level for 1/4/8/16 lumber + cast iron over
  target-level turns. Minerals need Prospect first (DR-20261111-26); above-cap
  orders refused.
- **Survey (DR-20261111-26).** One charted swamp/hills/mountain/desert tile per
  turn. Until surveyed, no icon, estate, lens row or AI plan names the mineral;
  empty ground may find nothing. Toast the find; a Builder may mine at once.
- **Terrain caps:** scrub timber at 1; hardwood follows tech.
- **Path transport:** bottleneck of the best road/rail/port route to the
  capital; beside-network tiles take it; several routes use the highest.
- **Init town roads:** every owned Old World town to its crown; New World towns
  wait for built roads.
- **Town rule:** estates 4-adjacent to a province town extract; capital
  provinces cap at town development; a non-capital port town caps tiles that
  reach the crown through it. An estate on (or beside) a crown road ignores the
  town cap.
- **Town development 1–4** via Builder `upgrade_town` (National Bureaucracy).
  Level 2 or 4 adds town manufacturing ([economy.md](economy.md)).
- **Cross-map assign.** Builder may target another owned tile; materials paid
  at assign, lost on cancel.
- **Extraction** after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`; only
  connected, prospected improvements yield; purchased enclaves pay their buyer.
- **Survey lens** (`LENS`, **L**): charted provinces; seals for known resources
  (minerals after Prospect), worked badge, bar, link row, dotted ring on
  unsurveyed ground; roads/rail solid when linked, dashed when cut. Yields use
  Extraction's caps (terrain, path, town).
- **Crown-road lens** (`R`): gold / amber / crimson for crown, town-only, or
  cut; cut provinces show the road tiles still to lay, count and route.
- **Estates ledger** (`ESTATES`): totals, filters, blockers, Build / Cancel /
  Map, caps, nearest idle Builder; cut-off estates name the crown gap.
- **Province dossier**: town level, crown link, estates, unsurveyed ground;
  Upgrade Town waits for tech.

## Deferred (REQ-P2-02)

None. A deed raises a Minor/Tribe town (`MinorTownGrowth`, DR-20261112-01);
ranked gaps: [`deferred.md`](deferred.md).

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
| `scripts/rules/resource_survey.gd`, `resource_routes.gd`, `scripts/map/resource_lens.gd` | survey, roads, plaques |
| `scripts/rules/crown_road_survey.gd`, `scripts/map/crown_road_lens.gd` | crown-road reading |
| `scripts/ui/lens_legend.gd` | lens keys |
| `scripts/rules/extraction.gd` | end-turn extraction |
| `scripts/ui/improvement_*.gd`, `province_*.gd` | ledger, rows, dossier |

Rules stay node-free (`REQ-P3-03`); panels read rows and emit intents.

## Tests

`test_civilian_field_rules`, `test_economy_rules`, `test_resource_survey`,
`test_resource_lens`, `test_crown_road_survey`, `test_province_panel`.
