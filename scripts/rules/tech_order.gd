class_name TechOrder
extends RefCounted
## Goal-first ordering for the research ledger (wiki: tech-tree § Research Model
## — the goal slot sorts the display and spends nothing). Pure queries over the
## catalog, so the panel keeps no ordering rules of its own (REQ-P3-03).

## Rank given to a tech that is not on the goal's prerequisite path.
const OFF_PATH: int = 1 << 20


## The goal an order, a snapshot or the ledger may carry: a catalog tech id, or
## "" when it is absent or this build does not know it — the queue then keeps
## catalog order (wiki: tech-tree § Goal slot; DR-20261111-21).
static func normalize(goal_id: String) -> String:
	if TechCatalog.known(goal_id):
		return goal_id
	return ""


## Depth from `goal_id` back along prerequisite edges: 0 is the goal itself, 1
## its direct prerequisites, 2 theirs, and so on; -1 when the tech is off that
## path (or the goal is unknown).
static func chain_depth(tech_id: String, goal_id: String) -> int:
	if goal_id.is_empty() or tech_id.is_empty():
		return -1
	if not TechCatalog.known(goal_id) or not TechCatalog.known(tech_id):
		return -1
	var frontier: Array[String] = [goal_id]
	var seen: Dictionary = {goal_id: true}
	var depth: int = 0
	while not frontier.is_empty():
		var next: Array[String] = []
		for node: String in frontier:
			if node == tech_id:
				return depth
			for prereq: String in TechCatalog.prerequisites(node):
				if seen.has(prereq):
					continue
				seen[prereq] = true
				next.append(prereq)
		frontier = next
		depth += 1
	return -1


## The goal itself first, then its prerequisites nearest-first, then everything
## else in catalog order (category, era, name).
static func sorted(techs: Array[String], goal_id: String = "") -> Array[String]:
	var out: Array[String] = techs.duplicate()
	if goal_id.is_empty():
		out.sort_custom(before)
		return out
	var rank: Dictionary = {}
	for tech_id: String in out:
		var depth: int = chain_depth(tech_id, goal_id)
		rank[tech_id] = depth if depth >= 0 else OFF_PATH
	out.sort_custom(func(a: String, b: String) -> bool:
		if int(rank[a]) != int(rank[b]):
			return int(rank[a]) < int(rank[b])
		return before(a, b)
	)
	return out


## Catalog order: category (catalog order), then era, then display name.
static func before(a: String, b: String) -> bool:
	var ca: int = TechCatalog.CATEGORIES.find(TechCatalog.category(a))
	var cb: int = TechCatalog.CATEGORIES.find(TechCatalog.category(b))
	if ca != cb:
		return ca < cb
	if TechCatalog.era(a) != TechCatalog.era(b):
		return TechCatalog.era(a) < TechCatalog.era(b)
	return TechCatalog.display_name(a) < TechCatalog.display_name(b)
