class_name AiObjectiveLedger
extends RefCounted
## The rank pass and the allocate pass of a rival court's objective ledger
## (docs/ai.md; issue #491 T1).
##
## `rank` sorts the tree into one order — parents before their children, each
## level by utility with the id breaking ties — so the same state always funds
## the same objective first. `allocate` walks that order top-down: each
## objective claims its cost from the pools, a pool never goes below zero, and
## an objective the pools cannot cover is marked `deferred` with the shortfall
## the trace prints. A blocked objective claims nothing and passes its reason
## up the tree (issue #491 T2).
##
## Pure: state in (objectives + pools), decisions out. No order is issued here,
## so T1's ledger cannot move the rules (REQ-P2-03, REQ-P4-03).


## Rank the tree in place: parents and their children by utility, id breaks the
## tie. Deterministic, so a replay never funds a different objective first.
static func rank(
	objectives: Array[AiObjective], modifiers: Dictionary = {}
) -> Array[AiObjective]:
	var sorted: Array[AiObjective] = []
	sorted.assign(objectives)
	sorted.sort_custom(
		func(a: AiObjective, b: AiObjective) -> bool: return _before(a, b, modifiers)
	)
	for objective: AiObjective in sorted:
		objective.children = rank(objective.children, modifiers)
	return sorted


## Walk the ranked tree top-down: each objective claims its cost from the pools
## in the currency's reading order, and one the pools cannot cover is deferred
## with its shortfall. Returns the report the turn trace keeps.
static func allocate(
	objectives: Array[AiObjective], pools: Dictionary = {}
) -> Dictionary:
	# Every aim claims its own cost first, in rank order; a parent's state is
	# settled after its children, so a composite aim is only as funded as they
	# are (issue #491 T4).
	for objective: AiObjective in walk(objectives):
		if objective.status == AiObjective.STATUS_BLOCKED:
			continue
		objective.claim = _grant(objective.cost, pools)
		if objective.shortfall().is_empty():
			objective.status = AiObjective.STATUS_FUNDED
		else:
			objective.status = AiObjective.STATUS_DEFERRED
	_resolve_parents(objectives)
	var statuses: Dictionary = {}
	for objective: AiObjective in walk(objectives):
		statuses[objective.id] = objective.status
	_resolve_requires(objectives, statuses)
	var ranked: int = 0
	var funded: int = 0
	var blocked: int = 0
	var lines: Array[String] = []
	for objective: AiObjective in walk(objectives):
		lines.append(objective.line())
		if objective.status == AiObjective.STATUS_BLOCKED:
			blocked += 1
			continue
		ranked += 1
		if objective.status == AiObjective.STATUS_FUNDED:
			funded += 1
	return {
		"ranked": ranked,
		"funded": funded,
		"blocked": blocked,
		"pools": pools,
		"lines": lines,
		"objectives": to_dict(objectives),
	}


## Settle every parent bottom-up: funded only when each child funded, else
## deferred with the first child that starved it named.
static func _resolve_parents(objectives: Array[AiObjective]) -> void:
	for objective: AiObjective in objectives:
		if objective.children.is_empty():
			continue
		_resolve_parents(objective.children)
		if objective.status == AiObjective.STATUS_BLOCKED:
			continue
		if _children_funded(objective):
			objective.status = AiObjective.STATUS_FUNDED
			continue
		objective.status = AiObjective.STATUS_DEFERRED
		objective.blocked = _starved_child(objective)


## Rank then allocate in one call: the shape the turn adapter and the tests use.
static func run(
	objectives: Array[AiObjective],
	pools: Dictionary = {},
	modifiers: Dictionary = {}
) -> Dictionary:
	var report: Dictionary = allocate(rank(objectives, modifiers), pools)
	report["modifiers"] = modifiers
	return report


## Every objective in rank order, parent before child.
static func walk(objectives: Array[AiObjective]) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	for objective: AiObjective in objectives:
		out.append(objective)
		out.append_array(walk(objective.children))
	return out


## Trace rows for the turn log, without mutating the tree.
static func to_dict(objectives: Array[AiObjective]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for objective: AiObjective in objectives:
		rows.append(objective.to_dict())
	return rows


## A parent whose required aim was deferred is deferred too, naming it: the
## expedition waits on the peace window it cannot claim twice.
static func _resolve_requires(
	objectives: Array[AiObjective], statuses: Dictionary
) -> void:
	for objective: AiObjective in objectives:
		for required_id: String in objective.requires:
			if String(statuses.get(required_id, AiObjective.STATUS_DEFERRED)) == (
				AiObjective.STATUS_FUNDED
			):
				continue
			if objective.status == AiObjective.STATUS_BLOCKED:
				continue
			objective.status = AiObjective.STATUS_DEFERRED
			if objective.blocked.is_empty():
				objective.blocked = required_id
		_resolve_requires(objective.children, statuses)


## True when every child of this objective ended funded (or it has none).
static func _children_funded(objective: AiObjective) -> bool:
	for child: AiObjective in objective.children:
		if child.status != AiObjective.STATUS_FUNDED:
			return false
	return true


## The first child that did not fund, named with its shortfall, e.g.
## "expedition.peace (orders 0/1)" — the reason a composite aim waited.
static func _starved_child(objective: AiObjective) -> String:
	for child: AiObjective in objective.children:
		if child.status == AiObjective.STATUS_FUNDED:
			continue
		var claims: String = AiUtility.claim_text(child.cost, child.claim)
		if claims.is_empty():
			return child.id
		return "%s (%s)" % [child.id, claims]
	return ""


## Grant as much of `cost` as the pools hold. Each resource draws on its own
## pool, in the currency's reading order so the trace is stable.
static func _grant(cost: Dictionary, pools: Dictionary) -> Dictionary:
	var claim: Dictionary = {}
	for key: String in AiUtility.ordered_keys(cost):
		var asked: int = int(cost.get(key, 0))
		if asked <= 0:
			continue
		var left: int = int(pools.get(key, AiUtility.UNBOUNDED))
		var granted: int = mini(asked, maxi(left, 0))
		claim[key] = granted
		if pools.has(key):
			pools[key] = maxi(left - granted, 0)
	return claim


static func _before(a: AiObjective, b: AiObjective, modifiers: Dictionary) -> bool:
	var left: int = AiUtility.modified(a.utility, int(modifiers.get(a.domain, 1000)))
	var right: int = AiUtility.modified(b.utility, int(modifiers.get(b.domain, 1000)))
	if left != right:
		return left > right
	if a.id != b.id:
		return a.id < b.id
	return a.domain < b.domain
