# Economy: stockpile, production and riches

One stockpile per Great Power, the end-of-turn pipeline, raw →
manufactured recipes. **Pillars:** P2, P3, P5.

**Wiki:** [stockpiles-and-production](https://github.com/waigore/empires-of-the-sea/wiki/stockpiles-and-production),
[production-recipes](https://github.com/waigore/empires-of-the-sea/wiki/production-recipes),
[commodity-catalog](https://github.com/waigore/empires-of-the-sea/wiki/commodity-catalog).

## Pipeline

`EconomyTurn` runs four phases, then research and prices:

1. **Extraction** — connected estates add yields ([improvements.md](improvements.md)).
2. **Riches-to-treasury** — gold, silver, gems, diamonds, spices clear at base price.
3. **Consumption** — army, navy, workers, hospitals eat; unfed men strike, wards idle.
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
| cigars | tobacco ×2 | 2 · apprentice · 2t |
| fur hats | furs ×2 | 2 · journeyman · 2t |
| steel | iron ×1 + coal ×1 | 2 |
| paper | timber ×2 | 2 |
| bronze | copper ×1 + tin ×1 | 3 |

`fabric_from_cotton` needs Cotton Weaving; a hand in the Labour column is a
`min_tier` gate, inert until trained. Runs are whole; short rows skip.

Steel, bronze, cigars and fur hats take **two turns** (`turns`); the alloys
combine two inputs (DR-20261114-10). Inputs and labour are paid up front and the
batch lands **one unit a phase**, WIP riding the save (DR-20261112-11/13-02). A
row left set starts a batch a phase.

A slow row's bench holds **three pieces** (`QUEUE_CAP`): a fourth run waits for
a landing (DR-20261114-12). The room is read after the phase's landings, so a
landing frees its place; a paid batch keeps its. A full bench reads `3/3→2t`.

## Town manufacturing bonus

Town development 2 or 4 turns connected raw into ×1/×2 manufactures:
`floor(input / 4) × multiplier`, no inputs, labour or cargo. A colony pays on
landed tons; rivals upgrade towns; a Minor/Tribe town auto-offers them; estates
sell in full; a deed lifts it (`min(4, 1+deeds)`).

## World-market auction

One book: `Bid`/`Offer` stages; turn-end `MarketClearing` matches court orders
plus Minor/Tribe auto-offers.
Tiebreaks: priority, pact, colony favour, Consulate, relation; a colony's
suzerain clears (`MarketFavoured`, R7.1). First right pays
a purchased tile's owner, plus relation share and embassy cut.
Unfilled orders carry while holds cover; offers cap at post-production.

## Trade terms

Prices publish once; pact, boycott, subsidy apply at settlement
([`diplomacy.md`](diplomacy.md)).

## UI

Ledger `PRODUCTION`: stockpile by catalogue group, holdings; steppers capped by
labour/inputs (`allowance`), a worked row naming its output (`made 3`).
`MARKET`: staged orders and Minor/Tribe/world rows. `WORKERS`: tier medallions,
`RECRUIT`, `DISBAND`, a **batch press** (`recruit_affordable`; `UNDER ORDERS`
folds a batch), a `LARDER` block
forecasting the next Consumption (`LarderRead`).


## Deferred (REQ-P2-02)

Building gates; rows past the four; rival bench room
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
