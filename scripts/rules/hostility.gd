class_name Hostility
extends RefCounted
## The war query every naval rule and rival planner reads. A caller may pass a
## `hostile(a, b)` callable (a court's chart, a fixture); an unset callable keeps
## the legacy every-faction-hostile behaviour, so an isolated test still fights
## (wiki: diplomacy § War required for hostile actions; REQ-P3-03).
##
## One module owns the predicate and the membership set, so the rules and the AI
## can never drift on what "at war" means.


## Whether two factions may fight. A faction is never hostile to itself; an unset
## callable means every other faction is hostile.
static func between(hostile: Callable, a: int, b: int) -> bool:
	if a == b:
		return false
	if not hostile.is_valid():
		return true
	return bool(hostile.call(a, b))


## Every faction at war with `owner`, as a membership set. No court means no
## known wars, so an isolated caller reads an empty set.
static func owners(state: DiplomacyState, owner: int) -> Dictionary:
	var hostile: Dictionary = {}
	if state == null:
		return hostile
	for record: DiplomacyRelation in state.relations_of(owner):
		if record.at_war:
			hostile[record.other(owner)] = true
	return hostile
