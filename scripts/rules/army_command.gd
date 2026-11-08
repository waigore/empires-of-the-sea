class_name ArmyCommand
extends RefCounted
## Command helpers for a battle side: which army is primary, which general
## medals apply, and stable id minting for recovered garrisons
## (wiki: military-armies § Combat and province loss, military-generals § Medals).
## Split from ArmyCombat so the battle chain stays inside the P3 size bar.


## Primary army for a side: most regiments, ties by lowest army id.
static func primary(side: Array[ArmyState]) -> ArmyState:
	var best: ArmyState = null
	for army: ArmyState in side:
		if army == null:
			continue
		if best == null or army.count() > best.count():
			best = army
		elif army.count() == best.count() and army.id < best.id:
			best = army
	return best


## Medals the side fights under: its primary army's bound general, else the
## leader-multiplier fallback (wiki: military-generals § Assignment).
static func medals(side: Array[ArmyState], context: Dictionary) -> int:
	var lead: ArmyState = primary(side)
	if lead == null:
		return 0
	var snapshot: Dictionary = context.get("army_medals", {}) as Dictionary
	if snapshot.has(lead.id):
		return int(snapshot[lead.id])
	var bindings: Dictionary = context.get("army_general", {}) as Dictionary
	var general_id: String = String(bindings.get(lead.id, ""))
	if not general_id.is_empty():
		var roster: GeneralRoster = context.get("roster") as GeneralRoster
		if roster != null:
			return roster.medals(lead.owner, general_id)
	var leaders: Dictionary = context.get("leaders", {}) as Dictionary
	return ArmyModifiers.fallback_medals(String(leaders.get(lead.owner, "")))


## Credits the winning side's primary general with one medal; returns its id
## only when a medal was actually gained (a four-medal general gains nothing).
static func award(context: Dictionary, side: Array[ArmyState], owner: int) -> String:
	var lead: ArmyState = primary(side)
	if lead == null:
		return ""
	var bindings: Dictionary = context.get("army_general", {}) as Dictionary
	var general_id: String = String(bindings.get(lead.id, ""))
	if general_id.is_empty():
		return ""
	var roster: GeneralRoster = context.get("roster") as GeneralRoster
	if roster == null:
		return ""
	var before: int = roster.medals(owner, general_id)
	if roster.award(owner, general_id) <= before:
		return ""
	return general_id


static func next_army_id(armies: Array[ArmyState]) -> int:
	var best: int = 0
	for army: ArmyState in armies:
		if army != null:
			best = maxi(best, army.id)
	return best + 1


static func next_unit_number(armies: Array[ArmyState]) -> int:
	var best: int = 0
	for army: ArmyState in armies:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			if regiment_id.begins_with("unit_"):
				best = maxi(best, int(regiment_id.trim_prefix("unit_")))
	return best + 1
