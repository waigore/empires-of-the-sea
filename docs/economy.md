# Economy: stockpile, production and riches

One stockpile per Great Power, the end-of-turn pipeline and raw →
manufactured recipes. **Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases, then research and prices:

1. **Extraction** — estates add yields ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds, spices clear at base price.
3. **Consumption** — army, navy, workers, hospitals eat; unfed men strike.
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
| cigars | tobacco ×2 | 2 · apprentice |
| fur hats | furs ×2 | 2 · journeyman |
| steel | iron ×1 + coal ×1 | 2 |
| paper | timber ×2 | 2 |
| bronze | copper ×1 + tin ×1 | 3 |

`fabric_from_cotton` needs Cotton Weaving. A hand in the Labour column is a
worker-tier gate (`min_tier`): inert until the court trains one.
Runs are whole, bounded by inputs and labour; short rows skip.

Steel and bronze take **two turns** (`turns`): inputs and labour paid
up front; the batch lands **one unit a phase** until spent, WIP riding the save
(`production_wip`, DR-20261112-11/13-02). A row left set starts a
batch a phase, so `5→1t` lands two (`next_landing`).

## Town manufacturing bonus

Town development 2 or 4 turns connected raw into ×1/×2 manufactures:
`floor(input / 4) × multiplier`, no inputs, labour or cargo. A colony pays on
landed tons; rivals upgrade towns.
Minor/Tribe towns auto-offer; estates sell in full, and a deed lifts a town
(`min(4, 1+deeds)`).

## World-market auction

One global book: `Bid`/`Offer` stages; turn-end `MarketClearing` matches
court orders plus Minor/Tribe auto-offers at the published price.
Tiebreaks: priority, pact, colony favour, Consulate, then relation; a colony's
suzerain clears first inside a tier (`MarketFavoured`, R7.1). First right fills
a purchased tile's owner first, paying relation share plus embassy kickback.
Unfilled orders carry while holds cover; fills move prices. Offers
cap at post-production stock.

## Trade terms

Prices publish once; pact, boycott, subsidy apply at settlement
([`diplomacy.md`](diplomacy.md)).

## UI

Ledger `PRODUCTION`: stockpile by catalogue group (`FOOD`, `RAW MATERIALS`,
`MANUFACTURED`, `RICHES`) with holdings and next figures; steppers capped by
labour/inputs (`ProductionRecipes.allowance`); a worked row names its output
(`made 3`). `MARKET`: staged orders and Minor/Tribe/world rows under medallions,
priced for the crown's terms and subsidy. `WORKERS`: tier medallions, `RECRUIT`,
trained `DISBAND` (no refund); a `LARDER` block forecasts the next Consumption —
store, every appetite (arriving recruits included) and the tier a shortfall
strikes first (`LarderRead`).


## Deferred (REQ-P2-02)

Building gates; further multi-turn rows; a queue cap
([`deferred.md`](deferred.md)).

## Architecture

`player_economy`, `economy_turn`, `economy_consumption`, `larder_read`,
`production_recipes`,
`commodity_catalog`, `world_market`, `market_*`, `first_right`,
`market_favoured`, `town_industry`, `minor_market`, `ui/ledger_*`,
`economy/economy_controller`, `economy/ledger_readings`,
`economy/ledger_orders`, `map/map_play_market`.

## Tests

`test_economy_rules`, `test_economy_screen`, `test_ai_economy_rules`,
`test_catalogs`.
