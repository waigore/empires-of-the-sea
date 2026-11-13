class_name AiObjectiveLedger
extends RefCounted
## Rank and allocate passes over a court's objectives (T1, trace-only).
##
## `rank` orders objectives by utility, highest first, with the objective id as
## the deterministic tie-break. `allocate` walks that order and grants each
## objective its whole cost from the court's pools; an objective that cannot be
## paid in full is `deferred` with the shortfall recorded, and a blocked
## objective is skipped. Nothing is spent: the pools are a read model, so the
## ledger changes no rules state (REQ-P2-03, REQ-P4-03).


## Ranked copy, highest utility first, ties broken by id so the same state
## always yields the same order.
static func rank(objectives: Array[AiObjective]) -> Array[AiObjective]:
	var ranked: Array[AiObjective] = []
	ranked.assign(objectives)
	ranked.sort_custom(func(a: AiObjective, b: AiObjective) -> bool:
		if a.utility != b.utility:
			return a.utility > b.utility
		return a.id < b.id
	)
	for index in ranked.size():
		ranked[index].rank = index + 1
	return ranked


## Grants each ranked objective its cost from `pools` until a pool empties.
## Returns the same array with `claim`, `status` and `shortfall` stamped.
static func allocate(
	objectives: Array[AiObjective], pools: Dictionary
) -> Array[AiObjective]:
	var remaining: Dictionary = {}
	for resource: String in AiObjective.RESOURCES:
		remaining[resource] = maxi(int(pools.get(resource, 0)), 0)
	for objective: AiObjective in objectives:
		if objective.is_blocked():
			objective.status = AiObjective.STATUS_BLOCKED
			continue
		var missing: Dictionary = {}
		for resource: String in objective.cost.keys():
			var need: int = int(objective.cost[resource])
			var have: int = int(remaining.get(resource, 0))
			if need > have:
				missing[resource] = need - have
		if missing.is_empty():
			for resource: String in objective.cost.keys():
				remaining[resource] = (
					int(remaining.get(resource, 0)) - int(objective.cost[resource])
				)
			objective.claim = objective.cost.duplicate()
			objective.status = AiObjective.STATUS_FUNDED
			objective.shortfall = {}
		else:
			objective.claim = {}
			objective.status = AiObjective.STATUS_DEFERRED
			objective.shortfall = missing
	return objectives


## The claims a court carries into the next turn, for `AiState` persistence.
static func claims_of(objectives: Array[AiObjective]) -> Array[Dictionary]:
	var claims: Array[Dictionary] = []
	for objective: AiObjective in objectives:
		if objective.status != AiObjective.STATUS_FUNDED:
			continue
		claims.append({
			"id": objective.id,
			"domain": objective.domain,
			"claim": objective.claim.duplicate(),
		})
	return claims


## One line per objective for the turn trace: utility, cost, claim and the
## blocked/deferred reason (wiki: turn-trace-interpretation).
static func trace_lines(objectives: Array[AiObjective]) -> Array[String]:
	var lines: Array[String] = []
	for objective: AiObjective in objectives:
		lines.append(_line(objective))
	return lines


static func _line(objective: AiObjective) -> String:
	var head: String = "#%d %s u%d" % [objective.rank, objective.id, objective.utility]
	var cost: String = _pairs(objective.cost)
	if not cost.is_empty():
		head += " cost " + cost
	match objective.status:
		AiObjective.STATUS_FUNDED:
			return head + " funded " + _pairs(objective.claim)
		AiObjective.STATUS_DEFERRED:
			return head + " deferred, short " + _pairs(objective.shortfall)
		AiObjective.STATUS_BLOCKED:
			return head + " blocked: " + objective.blocked
	return head + " ranked"


static func _pairs(raw: Dictionary) -> String:
	var parts: PackedStringArray = []
	for resource: String in AiObjective.RESOURCES:
		if raw.has(resource):
			parts.append("%s %d" % [resource, int(raw[resource])])
	return ", ".join(parts)
