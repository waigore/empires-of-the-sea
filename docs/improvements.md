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

- **Named improvements** follow the resource: Timber → Lumber camp,
  Iron/Coal/Gold/Tin → Mine, Grain → Farm, Wool → Pasture, Meat/Horses → Ranch.
- **Levels 1–4.** A Builder raises a tile for 1/4/8/16 lumber + cast iron over
  target-level turns. A mineral must be uncovered by that crown's Explorer
  first; orders above a cap are refused.
- **Survey (DR-20261111-26).** `Prospect this tile` reads one charted
  swamp/hills/mountain/desert tile a turn. Until that survey lands no icon,
  estate row, lens row or AI plan names the mineral; empty ground may be read
  to find nothing. The find is toasted; a Builder may mine at once.
- **Terrain caps:** scrub caps timber at 1; hardwood follows tech. **Path
  transport** is the bottleneck of the best road/rail/port route to the capital.
- **Town rule:** estates 4-adjacent to a town extract; capital provinces cap at
  town development; a non-capital port town caps tiles reaching the crown
  through it. An estate on a crown road ignores the cap. Setup roads every
  owned Old World town to its crown; New World towns wait for built roads.
- **Town development 1–4** via `upgrade_town` (National Bureaucracy); level 2 or
  4 adds manufacturing ([economy.md](economy.md)).
- **Cross-map assign.** A Builder may target another owned tile; materials paid
  at assign, lost on cancel.
- **Extraction** after Build/Work:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`; only
  connected, prospected improvements yield; purchased enclaves pay their buyer.
- **Survey lens** (`LENS`, **L**): a slip per charted province with its known
  estates, worked badge, link row, a dotted ring where ground is still to read,
  and built roads. Unknown ground is never surveyed.
- **Crown-road lens** (`R`): gold where the crown road reaches, amber where only
  the province town does, crimson where nothing does; a cut province names the
  road tiles still to lay.
- **Estates ledger** (`ESTATES`): realm totals, filters, Build / Cancel / Map,
  caps and the nearest idle Builder. The **province dossier** adds town level,
  crown link, estates and unsurveyed ground.

## Deferred (REQ-P2-02)

Minor/Tribe towns stay level 1, so manufacture offers rarely fire
([`deferred.md`](deferred.md)).

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
