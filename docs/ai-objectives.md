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
| `AiClaims` | the reservation primitive: commodity claims against the stockpile |
| `MapPlayObjectivesAi` | per-court adapter; stamps the ledger into the turn trace |

Costs name the six resources (`treasury, hull, civilian, regiment, labour,
orders`) plus any commodity a reservation claims; the trace prints the named
resources first, commodities sorted after them.

## Turn

`MapPlayObjectivesAi.run` prices every planning court: readings (footing,
desire, muster, hulls, purse, research) become objectives, ranked (utility ×
posture modifier, id breaks ties) and allocated over the pools. Each aim ends
`funded`, `deferred` with its shortfall (`hull 0/1`), or `blocked` with a
reason. `AiState.note_objectives` keeps the row and the ids by status, and the
save carries them.

## Posture and weights

`AiPosture` turns the footing into a per-mille vector (`posture.war_boost`,
`posture.war_expansion`, `posture.fronts_expansion`) multiplied by the leader's
domain weights (`posture.weight_step`, floor `posture.floor`), so a domain is
scaled, never zeroed. A parent with a starved child, or whose required aim
deferred (`requires`), is deferred and names what it waited on.

## The expedition

`colonise.new_world` parents `expedition.hull`, `expedition.explorer` and a
`requires` link to the court's one `peace.window` at war; a colonist already
ashore prices `expedition.voyage` instead of a missing Explorer. The colony
muster gate reads the funded hull claim (`MapPlayCivilianAi._hull_claimed`), so
a funded parent opens the voyage even at war, and a starved child prints
`expedition.hull hull 0/1 deferred`.

## The navy's build leg

`navy.build` is priced at war (90 with no fighting hull, 70 when outmatched,
against a sortie's 60) at the cheapest warship the court's techs open.
`MapPlayCargoAi` lays the hull down through `FleetYard` when the claim funds, and
the trace names it ("lays down a Sloop of War for the fleet").

## Reservations as claims

`AiClaims` ranks the ration the consumption phase eats, the next regiment's row,
the planned works and this turn's production against the stockpile; the market
reads their merged grant (the dictionary it always read, so the trade stays
behaviour-identical), the civilian purse is one treasury claim, and the turn
record keeps `claims` beside the ledger lines.

## Migration

| Step | Issue | State |
|------|-------|-------|
| T1 skeleton, trace-only | #496 | shipped |
| T2 expedition package | #497 | shipped |
| T3 reservations become claims | #498 | shipped |
| T4 posture modifier + weights | #499 | shipped |
| T5 naval build policy | #500 | shipped |
| T6 ai-bench funded share | #501 | pending |
