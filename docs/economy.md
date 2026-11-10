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
`floor(delivered town-connected input / 4) × multiplier`, no inputs, labour or
cargo. A colony pays after the crossing, on landed tons only (level 4 town
first, then most tons, then province id). Rivals upgrade towns too; works:
[improvements.md](improvements.md).

## Minor and Tribe offers

`MinorMarket` publishes each Minor Nation's and Tribe's harvest every turn: one
row per tradeable commodity its estates yield, at 75% of the world price
(`DR-20261110-08`). Riches and capital grain never appear; a court sells only
where the crown holds land. Buying pays the seller, fills stock, spends a hold
and books the import. Rows expire each turn; the book is saved, and trade terms
move the ask.

## Trade terms

Prices are published once, but each crown pays and receives its own rate after
trade diplomacy ([`diplomacy.md`](diplomacy.md) § Trade terms). The market holds
`{"buy": {id|"*": multiplier}, "sell": {...}}` per faction; `buy_price`,
`sell_price` and the direct ask apply it. Price discovery still reads the
published price; the ledger prints the rate and adjusted rows.

## UI

`ECONOMY` shows treasury, stockpile, trade and the projection. The `MARKET` tab
leads with the cargo and trade-terms banners and the offers (seller, good, units
left, ask), then the world rows. Tab presses are intents; rules stay in the
rules modules (`REQ-P2-03`).

## Architecture

`player_economy` (stockpile, treasury, workers), `economy_turn` (phase order,
projection), `economy_consumption`, `production_recipes`, `commodity_catalog`,
`world_market` (price book, trade terms), `town_industry`, `minor_market`
(offers, direct purchase), `ui/ledger_{production,market}`, and
`economy/economy_controller` (wiring, turn resolution).

## Tests

`test_economy_rules`, `test_economy_screen`, `test_catalogs`.
