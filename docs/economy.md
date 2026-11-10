# Economy: stockpile, production and riches

One stockpile per Great Power, the end-of-turn pipeline and the raw →
manufactured recipes. **Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases in wiki order, then research and world-market
price discovery:

1. **Extraction** — connected estates add yields
   ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds and spices clear at
   base price (`CommodityCatalog.treasury_ids()`).
3. **Consumption** — navy, army and workers eat; unfed workers strike.
4. **Production** — whole recipe runs spend post-consumption inputs and idle
   labour.

Projections copy the economy and never mutate live state.

## Production recipes

`ProductionRecipes` holds the published recipes:

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

`fabric_from_cotton` needs Cotton Weaving; other rows always run. A recipe runs
whole times, bounded by inputs and idle labour; a row that cannot complete once
skips without consuming. The `PRODUCTION` tab sets desired outputs.

## Town manufacturing bonus

Town development 2 or 4 turns town-connected raw into ×1/×2 bonus manufactures:
`floor(least delivered input / 4) × multiplier`, no inputs or labour.
Great Powers credit the stockpile; overseas town manufacturing stays deferred;
rivals trade the same market. Connectivity: [improvements.md](improvements.md).

## Minor and Tribe offers

`MinorMarket` publishes each Minor Nation's and Tribe's harvest every turn: one
row per tradeable commodity its estates yield, at 75% of the world price
(`DR-20261110-08`). Riches and the capital grain ration never appear, and a court
sells only in a region where the crown holds land. Buying pays the seller
(treasury sink), fills stock, spends a cargo hold, and books the import for
price discovery and naval interception. Rows expire each turn change; the book
is saved, and a crown's trade terms also move the ask.

## Trade terms

Prices are published once, but each crown pays and receives its own rate after
trade diplomacy ([`diplomacy.md`](diplomacy.md) § Trade terms). The market holds
`{"buy": {id|"*": multiplier}, "sell": {...}}` per faction; `buy_price`,
`sell_price` and the direct offer ask apply it, while price discovery still
reads the published price. The ledger prints the rate and adjusted rows; rivals
trade on the same terms.

## UI

`ECONOMY` shows treasury, stockpile, trade and the projection. The `MARKET` tab
leads with the cargo and trade-terms banners and the offers (seller, good, units
left, ask), then the world rows. Tab presses are intents; rules stay in the
rules modules (`REQ-P2-03`).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/player_economy.gd` | stockpile, treasury, workers, assignments |
| `scripts/rules/economy_turn.gd` | phase order and projection |
| `scripts/rules/economy_consumption.gd` | food, luxuries, strikes |
| `scripts/rules/production_recipes.gd` | recipe catalog and whole-run planner |
| `scripts/rules/commodity_catalog.gd` | ids, categories, prices, treasury rows |
| `scripts/rules/world_market.gd` | global price book and per-crown trade terms |
| `scripts/rules/town_industry.gd` | town manufacturing bonus |
| `scripts/rules/minor_market.gd` | Minor Nation / Tribe offers and direct purchase |
| `scripts/ui/ledger_production.gd` | production tab rows |
| `scripts/economy/economy_controller.gd` | panel wiring and turn resolution |

## Tests

`test_economy_rules`, `test_economy_screen`, `test_catalogs`.
