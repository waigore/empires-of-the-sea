# AI objective ledger

Issue [#491](https://github.com/waigore/empires-of-the-sea/issues/491). Rules
stay in the wiki; this page is the shipped slice and its migration steps.

## Shape

| Piece | Role |
|-------|------|
| `AiObjective` | id, domain, utility 0–100, cost, claim, status, children |
| `AiUtility` | one currency: `scale`/`ratio`/`modified`, cost and shortfall text |
| `AiObjectiveLedger` | rank pass + allocate pass over per-turn pools |
| `AiObjectivesPlan` | pure emitter: readings in, objectives out |
| `MapPlayObjectivesAi` | per-court adapter; stamps the ledger into the turn trace |

## Turn

`MapPlayObjectivesAi.run` prices every planning court before the expedition
pass: readings (footing, desire, muster, hulls, purse, research) become
objectives, which are ranked (utility down, id breaks ties) and allocated over
the pools `treasury, hull, civilian, regiment, labour, orders`. Each aim ends
`funded`, `deferred` with its shortfall (`hull 0/1`), or `blocked` with a
reason. `AiState.note_objectives` keeps the turn's row and the save carries it.

## Migration

| Step | Issue | State |
|------|-------|-------|
| T1 skeleton, trace-only | #496 | shipped |
| T2 expedition package | #497 | pending |
| T3 reservations become claims | #498 | pending |
| T4 posture modifier + weights | #499 | pending |
| T5 naval build policy | #500 | pending |
| T6 ai-bench funded share | #501 | pending |
