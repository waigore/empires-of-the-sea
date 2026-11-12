# Economy: stockpile, production and riches

One stockpile per Great Power, the end-of-turn pipeline and raw →
manufactured recipes. **Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases, then research and prices:

1. **Extraction** — connected estates add yields
   ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds, spices clear at base
   price.
3. **Consumption** — army, navy, workers, then hospital staffs eat; unfed men
   strike, unfed wards lose their staff.
4. **Production** — recipes spend post-consumption inputs and idle labour.

Projections never mutate state.

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
whole times, bounded by inputs and labour; incomplete rows are skipped.
`PRODUCTION` sets desired outputs.

Steel and bronze take **two turns** (`turns` per run): inputs and labour are paid
at the start, the output lands when the turns are served, and the batch rides the
save (`PlayerEconomy.production_wip`, DR-20261112-11).

## Town manufacturing bonus

Town development 2 or 4 turns town-connected raw into ×1/×2 manufactures:
`floor(delivered town-connected input / 4) × multiplier`, no inputs, labour or
cargo. A colony pays on landed tons. Rivals upgrade towns
([improvements.md](improvements.md)). A Minor/Tribe town publishes them as market auto-offers at the province town;
estates still sell in full. A deed lifts that town (`min(4, 1+deeds)`).

## World-market auction

One global order book: `Bid`/`Offer` stages; turn-end `MarketClearing` matches
court orders plus Minor/Tribe per-tile auto-offers at the published price.
Tiebreaks: integer priority, pact, colony favour, Consulate, relation — a
colony's suzerain clears first inside a tier (`MarketFavoured`, wiki R7.1).
First right of refusal fills a purchased tile's owner first and pays its relation
share plus embassy kickbacks. Unfilled orders carry when holds/stock cover them;
prices move from fills, and a world counterparty fills the rest.

An offer is capped by stock left after production; the `Offer` chip names the
claim. Fills and lapses show in the toast.

## Trade terms

Prices are published once; each crown's diplomacy rate applies at settlement
([`diplomacy.md`](diplomacy.md) § Trade terms). `buy_price`, `sell_price` and
the Minor/Tribe ask carry it.

## UI

`ECONOMY` shows treasury, stockpile, trade, projection. `MARKET` lists
staged orders, Minor/Tribe harvest and world rows as intents, each good under
its medallion (`REQ-P1-02`, `REQ-P2-03`).
`WORKERS`: `RECRUIT` per tier; trained tiers get `DISBAND` (no refund).
Thumb-sized on a phone.

## Architecture

`player_economy`, `economy_turn`, `economy_consumption`, `production_recipes`,
`commodity_catalog`, `world_market`, `market_{order,book,rules,matcher,orders,clearing}`,
`first_right`, `market_favoured`, `town_industry`, `minor_market`,
`ui/{commodity_icons,ledger_{production,market}}`, and `economy/economy_controller` plus
`map/map_play_market`.

## Tests

`test_economy_rules`, `test_economy_screen`, `test_ai_economy_rules`,
`test_catalogs`.
