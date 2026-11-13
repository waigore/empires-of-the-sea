# Economy: stockpile, production and riches

One stockpile per Great Power, the end-of-turn pipeline and raw →
manufactured recipes. **Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases, then research and prices:

1. **Extraction** — connected estates add yields ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds, spices clear at base price.
3. **Consumption** — army, navy, workers, hospitals eat; unfed men strike, unfed
   wards idle.
4. **Production** — recipes spend post-consumption inputs and idle labour.

Projections never mutate.

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

`fabric_from_cotton` needs Cotton Weaving; others always run. Runs are whole,
bounded by inputs and labour; incomplete rows skip. `PRODUCTION` sets desired
outputs.

Steel and bronze take **two turns** (`turns` per run): inputs and labour paid
up front; the batch lands **one unit a phase** until spent, WIP riding the save
(`PlayerEconomy.production_wip`, DR-20261112-11/13-02). Three steel begun in
turn 1 end in turn 4. A row left set starts a batch a phase, so `5→1t` lands
two (`ProductionRecipes.next_landing`).

## Town manufacturing bonus

Town development 2 or 4 turns town-connected raw into ×1/×2 manufactures:
`floor(input / 4) × multiplier`, no inputs, labour or cargo. A colony pays on
landed tons; rivals upgrade towns ([improvements.md](improvements.md)). A
Minor/Tribe town auto-offers them at its province town; estates still sell in
full, and a deed lifts that town (`min(4, 1+deeds)`).

## World-market auction

One global book: `Bid`/`Offer` stages; turn-end `MarketClearing` matches
court orders plus Minor/Tribe per-tile auto-offers at the published price.
Tiebreaks: integer priority, pact, colony favour, Consulate, relation; a
colony's suzerain clears first inside a tier (`MarketFavoured`, R7.1).
First right of refusal fills a purchased tile's owner first and pays its relation
share plus embassy kickback. Unfilled orders carry while holds cover them;
prices move from fills; a counterparty fills the rest.
An offer is capped by post-production stock (`Offer` chip); fills/lapses toast.

## Trade terms

Prices are published once; each crown's diplomacy rate applies at settlement
([`diplomacy.md`](diplomacy.md) § Trade terms). `buy_price`, `sell_price` and
the Minor ask carry it.

## UI

`ECONOMY` shows treasury, stockpile, trade, projection. `MARKET` lists staged
orders, Minor/Tribe harvest and world rows as intents under their medallions
(`REQ-P1-02`, `REQ-P2-03`). `WORKERS`: `RECRUIT` per tier; trained tiers get
`DISBAND` (no refund). Thumb-sized on a phone.

## Deferred (REQ-P2-02)

Building/tier gates; further multi-turn rows; a queue cap
([`deferred.md`](deferred.md)).

## Architecture

`player_economy`, `economy_turn`, `economy_consumption`, `production_recipes`,
`commodity_catalog`, `world_market`, `market_*`, `first_right`,
`market_favoured`, `town_industry`, `minor_market`, `ui/ledger_*`,
`economy/economy_controller`, `map/map_play_market`.

## Tests

`test_economy_rules`, `test_economy_screen`, `test_ai_economy_rules`,
`test_catalogs`.
