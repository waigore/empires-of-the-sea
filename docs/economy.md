# Economy: stockpile, production and riches

One stockpile per Great Power; raw → manufactures.
**Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases, then research and prices:

1. **Extraction** — connected estates yield ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds, spices clear at base price.
3. **Consumption** — army, navy, workers, hospitals eat; unfed men strike, wards idle.
4. **Production** — recipes spend inputs and idle labour; a hire labours next
   turn (`workers-and-population` § Phase).

Projections never mutate.

## Production recipes

Catalogue `ProductionRecipes`; phase `ProductionPhase`:

| Output | Inputs | Labour |
|--------|--------|--------|
| lumber | timber ×2 | 2 |
| fabric | wool ×2 or cotton ×2 | 2 |
| cast iron | iron ×2 | 2 |
| refined sugar | sugar cane ×2 | 2 |
| cigars | tobacco ×2 | 2 · apprentice · 2t |
| fur hats | furs ×2 | 2 · journeyman · 2t |
| steel | iron ×1 + coal ×1 | 2 |
| paper | timber ×2 | 2 |
| bronze | copper ×1 + tin ×1 | 3 |

`fabric_from_cotton` needs Cotton Weaving; a Labour hand is a `min_tier`
gate. Runs are whole; short rows skip.

Steel, bronze, cigars and fur hats take two turns (DR-20261114-10). Inputs
pay first; the batch
lands **one unit a phase**, WIP in the save (DR-20261112-11/13-02).

A slow bench holds three (`QUEUE_CAP`); a fourth waits
(DR-20261114-12).

## Town manufacturing bonus

Town level 2 or 4 turns raw into ×1/×2 manufactures:
`floor(input / 4) × multiplier`, no inputs or labour. A colony pays on
landed tons; a Minor/Tribe town offers; a deed lifts it (`min(4, 1+deeds)`).

## World-market auction

One book: `MarketClearing` matches staged orders and Minor/Tribe offers.
Tiebreaks: priority, pact, colony favour, Consulate, relation
(`MarketFavoured`). A boycott bars the pair; first right pays a tile's owner a
relation share and an embassy cut.
Unfilled orders carry while capacity (holds − colonial tons) covers
them; offers cap post-production. Bids spend `treasury − waiting build orders`
(`MarketBudget`).

## Trade terms

Prices publish once; pact, boycott, subsidy settle ([`diplomacy.md`](diplomacy.md)).

## UI

`PRODUCTION`: stockpile by group in columns (three desktop, two phone, Riches
strip); steppers capped by labour/inputs (`allowance`), a run names its
output (`made 3`), court runs gold and `▸`-marked
(`MapPlayProductionPick`, DR-20261121-07; DR-20261122-10).
`MARKET`: staged orders, Minor/Tribe/world rows, bid budget, `CROSSING`
line (`CargoRead`), court trade gold and `▸` (`MapPlayMarketPick`,
DR-20261121-09; DR-20261122-08),
a **batch press** (`MarketBatch`), a dead `Bid` (`MarketRules.bid_block`,
DR-20261118-15), a barred colony row (`MinorMarket.sealed_line`), share
fills (`share_rows`).
`WORKERS`: tier medallions, `RECRUIT`, `DISBAND`, a **batch press**
(`recruit_affordable`; `UNDER ORDERS` folds it), a `LARDER` block
(`LarderRead`): next store, every appetite, the striking tier; court recruits
gold, `▸`-marked (DR-20261122-01, DR-20261123-08). Tier rows print
their deal (`LedgerWorkersText.recruit_line`): price, gate or ration
(DR-20261118-03).

## Deferred (REQ-P2-02)

Live: workshop/riches landing (`ground_appetite`, DR-19-05/21); [`deferred.md`](deferred.md).

## Architecture

`player_economy`, `economy_turn`, `economy_consumption`, `larder_read`,
`cargo_read`, `production_recipes`/`production_phase`,
`commodity_catalog`, `world_market`, `market_*`, `first_right`,
`market_favoured`, `town_industry`, `minor_market`, `ui/ledger_*`,
`economy/economy_controller`, `economy/ledger_readings`,
`economy/ledger_orders`, `map/map_play_market`, `map/map_play_production_pick`.

## Tests

`test_market_economy_rules`, `test_economy_screen`, `test_a_ai_rules`.
