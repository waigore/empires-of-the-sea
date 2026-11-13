class_name AiObjective
extends RefCounted
## One objective in a rival court's turn ledger (docs/ai.md; issue #491 T1).
##
## A planner emits an objective instead of spending directly: `utility` is the
## shared 0–100 currency (AiUtility), `cost` names the resources it would claim,
## and `children` decompose a composite aim — the expedition is a parent whose
## children are the hull, the Explorer and the peace window (issue #491 T2).
## The ledger ranks and allocates the tree; this type only carries it, so it
## stays pure data (REQ-P2-02, REQ-P2-03).

## The four states a ranked objective can hold. `ranked` is the state an
## emitter hands over; the allocate pass writes the other three.
const STATUS_RANKED: String = "ranked"
const STATUS_FUNDED: String = "funded"
const STATUS_DEFERRED: String = "deferred"
const STATUS_BLOCKED: String = "blocked"

var id: String = ""
var domain: String = ""
var utility: int = 0
var cost: Dictionary = {}
var claim: Dictionary = {}
var status: String = STATUS_RANKED
var blocked: String = ""
var children: Array[AiObjective] = []


static func create(
	objective_id: String,
	objective_domain: String,
	value: int,
	objective_cost: Dictionary = {}
) -> AiObjective:
	var objective := AiObjective.new()
	objective.id = objective_id
	objective.domain = objective_domain
	objective.utility = AiUtility.clamp_utility(value)
	objective.cost = AiUtility.clean_cost(objective_cost)
	return objective


## Chainable child, so a parent reads as one expression.
func with_child(child: AiObjective) -> AiObjective:
	if child != null:
		children.append(child)
	return self


## The value the rank pass sorts on. T1 ranks by utility alone; T4 applies the
## posture modifier vector (#499).
func rank() -> int:
	return utility


func is_funded() -> bool:
	return status == STATUS_FUNDED


## A blocked objective claims nothing and says why: no harbour, no target.
func block(reason: String) -> AiObjective:
	status = STATUS_BLOCKED
	blocked = reason
	return self


func shortfall() -> Dictionary:
	return AiUtility.shortfall(cost, claim)


## One trace row: every reading the ledger made, so a starved objective explains
## itself instead of vanishing (issue #491 T1 acceptance).
func to_dict() -> Dictionary:
	var row: Dictionary = {
		"id": id,
		"domain": domain,
		"utility": utility,
		"cost": cost,
		"claim": claim,
		"status": status,
	}
	if not blocked.is_empty():
		row["blocked"] = blocked
	var short: Dictionary = shortfall()
	if not short.is_empty():
		row["shortfall"] = short
	if not children.is_empty():
		var kids: Array[Dictionary] = []
		for child: AiObjective in children:
			kids.append(child.to_dict())
		row["children"] = kids
	return row


## "colonise.new_world u50 hull 1/1, civilian 0/1 deferred" — the trace line.
func line() -> String:
	var text: String = "%s u%d" % [id, utility]
	var claims: String = AiUtility.claim_text(cost, claim)
	if not claims.is_empty():
		text += " %s" % claims
	text += " %s" % status
	if status == STATUS_BLOCKED and not blocked.is_empty():
		text += " (%s)" % blocked
	return text
