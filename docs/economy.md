# Economy: stockpile, production and riches

One stockpile per Great Power, the end-of-turn pipeline and the raw →
manufactured recipes. **Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases, then research and price discovery:

1. **Extraction** — connected estates add yields
   ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds, spices clear at base
   price.
3. **Consumption** — navy, army, workers eat; unfed strike.
4. **Production** — recipes spend post-consumption inputs and idle labour.

Projections never mutate live state.

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

`fabric_from_cotton` needs Cotton Weaving; other rows always run. Recipes run
whole times, bounded by inputs and idle labour; an incomplete row is skipped.
`PRODUCTION` sets desired outputs.

## Town manufacturing bonus

Town development 2 or 4 turns town-connected raw into ×1/×2 manufactures:
`floor(delivered town-connected input / 4) × multiplier`, no inputs, labour or
cargo. A colony pays after the crossing, on landed tons (level 4 town first,
then most tons, then province id). Rivals upgrade towns too; works:
[improvements.md](improvements.md). A Minor or Tribe province with such a town
publishes its manufactures as market auto-offers under its own name, sourced at
the province town; its estates still sell in full.

## World-market auction

The market is one global order book. `Bid`/`Offer` stages an order;
turn-end `MarketClearing` matches every court's orders plus each Minor and
Tribe's per-tile auto-offers at the old published price. Integer priority,
pact, Consulate and relation tiebreaks order the book. First right of refusal
fills a purchased tile's owner first and pays its relation share plus embassy
kickbacks; subsidies adjust the settled deal. Unfilled orders carry when
holds/stock cover them; prices move from filled bids and submitted offers. A
standing world counterparty fills the remainder.

An offer is capped by stock left after production; the `Offer` chip names that
claim. Staged and carried orders show in the ledger; fills, cuts and lapses
appear in the turn toast. Orders travel in the save.

## Trade terms

Prices are published once; each crown's diplomacy rate applies at settlement
([`diplomacy.md`](diplomacy.md) § Trade terms). `buy_price`, `sell_price` and
the Minor/Tribe ask carry it; price discovery reads the published price.


## UI

`ECONOMY` shows treasury, stockpile, trade and projection. The `MARKET` tab
lists staged orders, the Minor/Tribe harvest and world rows; presses are
intents (`REQ-P2-03`). The `WORKERS` tab holds the tier roster: `RECRUIT` per
tier and, for trained tiers, `DISBAND` — one worker back to the fields at once,
no refund, inert when the tier is empty. Rows are thumb-sized on a phone.

## Architecture

`player_economy`, `economy_turn`, `economy_consumption`, `production_recipes`,
`commodity_catalog`, `world_market`, `market_{order,book,rules,matcher,orders,clearing}`,
`first_right`, `town_industry`, `minor_market`, `ui/ledger_{production,market}`,
and `economy/economy_controller` plus `map/map_play_market`.

## Tests

`test_market_engine`, `test_economy_rules`, `test_economy_screen`,
`test_ai_market`, `test_catalogs`.

