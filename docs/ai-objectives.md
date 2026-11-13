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

## The expedition

`colonise.new_world` is a parent with the children that make it sail: a hull off
the cargo routes (`expedition.hull`), the Explorer's train slot
(`expedition.explorer`), the peace window at war (`expedition.peace`, one
diplomatic order) and a protected `expedition.voyage` once afloat or landed. The
colony muster gate reads the funded hull claim (`MapPlayCivilianAi._hull_claimed`)
instead of looking for a squadron a second time, and a starved child prints its
shortfall (`expedition.hull hull 0/1 deferred`).

## Posture and weights

`AiPosture` turns the footing into a per-mille vector (`posture.war_boost`,
`posture.war_expansion`, `posture.fronts_expansion`) and multiplies it by the
leader's domain weights (`posture.weight_step`, floor `posture.floor`), so a
domain is scaled, never zeroed. Ranking is `utility × modifier / 1000`. A parent
with a starved child, or with a required aim that deferred (`requires`, e.g. the
expedition needs the court's one `peace.window`), is itself deferred and names
the aim it waited on. The voyage's footing is read from the ledger: a funded
`colonise.new_world` opens the muster even at war, because the peace window is
what bought it.

## The navy's build leg

`navy.build` is a funded aim at war when the court has no fighting hull or is
outmatched on its own coast (utility 90 / 70 against a sortie's 60). Its cost is
the cheapest warship the court's techs open (`treasury` price, one `hull` slip);
`MapPlayCargoAi` lays the hull down through `FleetYard` when the claim funds, and
the turn trace names it ("lays down a Sloop of War for the fleet"). A court at
peace prices no yard at all, so there is no idle churn.

A colonist already ashore is the voyage's progress, not a missing Explorer: the
parent keeps pricing `expedition.voyage` instead of reporting `no Explorer free`.

## Migration

| Step | Issue | State |
|------|-------|-------|
| T1 skeleton, trace-only | #496 | shipped |
| T2 expedition package | #497 | shipped |
| T3 reservations become claims | #498 | pending |
| T4 posture modifier + weights | #499 | shipped |
| T5 naval build policy | #500 | shipped |
| T6 ai-bench funded share | #501 | pending |
