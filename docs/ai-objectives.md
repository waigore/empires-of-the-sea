# AI objective ledger

Issue [#491](https://github.com/waigore/empires-of-the-sea/issues/491). Rules
stay in the wiki; this page is the shipped slice and its migration steps.

## Shape

| Piece | Role |
|-------|------|
| `AiObjective` | id, domain, utility 0–100, cost, claim, status, children, requires |
| `AiUtility` | one currency: `scale`/`ratio`/`modified`, cost and shortfall text |
| `AiObjectiveLedger` | rank pass + allocate pass over per-turn pools |
| `AiObjectivesPlan` | pure emitter: readings in, objectives out |
| `AiClaims` | reservation primitive: commodity claims against the stockpile |
| `MapPlayObjectivesAi` | per-court adapter; stamps the ledger into the turn trace |

Costs name six resources (`treasury, hull, civilian, regiment, labour, orders`)
plus any commodity a reservation claims; named resources print first.

## Turn

`MapPlayObjectivesAi.run` prices every planning court before the expedition
pass: readings (footing, desire, muster, hulls, purse, research, tribe) become
objectives, ranked (`utility × modifier / 1000`, id breaks ties) and allocated
over the pools. Each aim ends `funded`, `deferred` with shortfall
(`hull 0/1`), or `blocked`. `AiState.note_objectives` keeps the row and ids by
status; the save carries them.

## The expedition

`colonise.new_world` parents `expedition.hull` (hull off cargo routes),
`expedition.explorer` (Explorer train slot) and a `requires` link to
`peace.window` at war; afloat or landed it adds `expedition.voyage`. The
colony muster gate reads the funded hull claim
(`MapPlayCivilianAi._hull_claimed`); a starved child prints
`expedition.hull hull 0/1 deferred`. Ashore, the parent prices
`expedition.voyage`, not `no Explorer free`.

## Posture and weights

`AiPosture` turns footing into a per-mille vector (`posture.war_boost`,
`posture.war_expansion`, `posture.fronts_expansion`) × leader domain weights
(`posture.weight_step`, floor `posture.floor`) — scaled, never zeroed. A parent
with a starved child, or whose required aim deferred (`requires`), is deferred
and names what it waited on. A funded `colonise.new_world` opens the muster even
at war: the peace window bought it.

## The navy's build leg

`navy.build` funds at war with no fighting hull or an outmatched coast (utility
90 / 70 vs a sortie's 60) at the cheapest open warship (`treasury` + one `hull`
slip). `MapPlayCargoAi` lays it via `FleetYard` when funded ("lays down a Sloop
of War for the fleet"); peace prices no yard.

## Reservations as claims

`AiClaims` ranks the ration consumption eats, the next regiment, planned works
and this turn's production against the stockpile; the market reads their merged
grant (same dictionary, trade behaviour-identical), the civilian purse is one
treasury claim, and the turn record keeps `claims` beside ledger lines.

## The colony

`colonise.tribe_chain` prices the next envoy step toward a charted Tribe the
court can still buy (stage cost, one order); the diplomacy planner reads the
same ambition and never declares on it (DR-20261114-02).

## Migration

| Step | Issue | State |
|------|-------|-------|
| T1 skeleton, trace-only | #496 | shipped |
| T2 expedition package | #497 | shipped |
| T3 reservations become claims | #498 | shipped |
| T4 posture modifier + weights | #499 | shipped |
| T5 naval build policy | #500 | shipped |
| T6 ai-bench funded share | #501 | pending |
