# Economy: stockpile, production and riches

One central stockpile per Great Power, the end-of-turn economy pipeline and the
raw → manufactured recipes. **Pillars:** P2 (rules), P3 (rules/view), P5
(agency).

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` resolves four phases in wiki order, then research and world-market
price discovery:

1. **Extraction** — connected estates add their yields
   ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds and spices clear from
   the stockpile at base price (`CommodityCatalog.treasury_ids()`).
3. **Consumption** — navy, army and workers eat from the stockpile; strike
   rules apply to unfed workers.
4. **Production** — whole recipe runs consume post-consumption inputs and idle
   labour, then add outputs.

The same pipeline powers the ledger's dry-run projection; the projection copies
the economy, so it never mutates the live treasury or stockpile.

## Production recipes

`ProductionRecipes` holds the ten published recipes:

| Output | Inputs | Labour |
|--------|--------|--------|
| lumber | timber ×2 | 2 |
| fabric | wool ×2 or cotton ×2 | 2 |
| cast iron | iron ×2 | 2 |
| refined sugar | sugar cane ×2 | 2 |
| cigars | tobacco ×2 | 2 |
| fur hats | furs ×2 | 2 |
| steel | iron ×1 + coal ×1 | 2 |
| paper | timber ×2 | 2 |
| bronze | copper ×1 + tin ×1 | 3 |

`fabric_from_cotton` needs Cotton Weaving; every other row is always available.
A recipe runs an integer number of times, bounded by inputs and idle labour; a
row that cannot complete once is skipped without consuming anything. The
`PRODUCTION` ledger tab sets desired output units per recipe; labour is not
removed from the worker pool.

## Town manufacturing bonus

A province at town development 2 or 4 turns **town-connected raw extracted that
turn** into bonus manufactures during Extraction: level 2 ×1, level 4 ×2,
levels 1 and 3 none. The bonus consumes no inputs, labour or cargo. Per recipe,
`floor(least delivered town-connected raw input / 4) × multiplier`.

Great Powers credit the output to the central stockpile; Minor and Tribe market
offers are deferred. Town connectivity is in [improvements.md](improvements.md).

## UI

`ECONOMY` shows treasury, stockpile, trade and the projection. The production
tab emits assignment intents; `EconomyController` applies them and refreshes the
panel. All validation stays in the rules modules (`REQ-P2-03`).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/player_economy.gd` | stockpile, treasury, workers, assignments |
| `scripts/rules/economy_turn.gd` | phase order and projection |
| `scripts/rules/economy_consumption.gd` | food, luxuries, strikes |
| `scripts/rules/production_recipes.gd` | recipe catalog and whole-run planner |
| `scripts/rules/commodity_catalog.gd` | ids, categories, prices, treasury rows |
| `scripts/rules/town_industry.gd` | town manufacturing bonus |
| `scripts/ui/ledger_production.gd` | production tab rows |
| `scripts/economy/economy_controller.gd` | panel wiring and turn resolution |

## Tests

`test_economy_rules` (pipeline, workers, recipes, riches, town bonus),
`test_economy_screen`, `test_catalogs`.
