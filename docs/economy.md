# Economy: stockpile, production and riches

One stockpile per Great Power; pipeline, raw → manufactures.
**Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases, then research and prices:

1. **Extraction** — connected estates add yields ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds, spices clear at base price.
3. **Consumption** — army, navy, workers, hospitals eat; unfed men strike, wards idle.
4. **Production** — recipes spend inputs and idle labour; a hire labours **next**
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

`fabric_from_cotton` needs Cotton Weaving; a Labour-column hand is a
`min_tier` gate. Runs are whole; short rows skip.

Steel, bronze, cigars and fur hats take **two turns** (`turns`); alloys
combine two inputs (DR-20261114-10). Inputs and labour pay up front; the batch
lands **one unit a phase**, WIP riding the save (DR-20261112-11/13-02).

A slow row's bench holds **three pieces** (`QUEUE_CAP`): a fourth run waits for
a landing (DR-20261114-12).

## Town manufacturing bonus

Town development 2 or 4 turns connected raw into ×1/×2 manufactures:
`floor(input / 4) × multiplier`, no inputs or labour. A colony pays on
landed tons; rivals upgrade towns; a Minor/Tribe town offers; a deed lifts
it (`min(4, 1+deeds)`).

## World-market auction

One book: `Bid`/`Offer` stages; turn-end `MarketClearing` matches orders and
Minor/Tribe offers.
Tiebreaks: priority, pact, colony favour, Consulate, relation; a suzerain
clears its colony (`MarketFavoured`). A boycott bars the pair; first right pays
a tile's owner, relation share and embassy cut.
Unfilled orders carry while holds cover; offers cap post-production. Bids
spend `treasury − waiting build orders` (`MarketBudget`).

## Trade terms

Prices publish once; pact, boycott, subsidy settle
([`diplomacy.md`](diplomacy.md)).

## UI

`PRODUCTION`: stockpile by group; steppers capped by labour/inputs
(`allowance`), a worked row names its output (`made 3`), **batch press**
(`ProductionBatch`; its line priced, DR-20261118-24).
`MARKET`: staged orders, Minor/Tribe/world rows, the bid budget, a `CROSSING`
line (`CargoRead`), a **batch press** (`MarketBatch`), and a dead
`Bid` naming its rule (`MarketRules.bid_block`, DR-20261118-15).
`WORKERS`: tier medallions, `RECRUIT`, `DISBAND`, a **batch press**
(`recruit_affordable`; `UNDER ORDERS` folds a batch), a `LARDER` block
(`LarderRead`): next Consumption's store, every appetite, the striking tier.
Tier rows print their deal (`LedgerWorkersText.recruit_line`): price, gate or
ration, never a hover (DR-20261118-03).

## Deferred (REQ-P2-02)

Live: workshop landing (`ground_appetite`, DR-19-05); see
[`deferred.md`](deferred.md).

## Architecture

`player_economy`, `economy_turn`, `economy_consumption`, `larder_read`,
`cargo_read`, `production_recipes`/`production_phase`,
`commodity_catalog`, `world_market`, `market_*`, `first_right`,
`market_favoured`, `town_industry`, `minor_market`, `ui/ledger_*`,
`economy/economy_controller`, `economy/ledger_readings`,
`economy/ledger_orders`, `map/map_play_market`.

## Tests

`test_market_economy_rules`, `test_economy_screen`, `test_ai_rules`.
