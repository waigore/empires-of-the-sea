class_name ArmyRoster
extends RefCounted
## Multi-army list surgery over [ArmyState]: split, combine, prune, hand-over,
## and faction-wide roster counts (wiki: military-armies § Split and combine,
## § Home Army; diplomacy § GP–Minor Rules; capital-and-connectivity § Capital
## loss; combat § Feeding). Pure rules, no nodes (REQ-P3-03). Split from
## [ArmyState] so the container stays a single-army bag inside the P3 size bar
## (REQ-P3-01); the layer, combat pass and AI all take the same list ops here.


## Join Empire and a terminal fall, in place: an absorbed crown's land regiments
## change colours and its Home Army becomes a field army (diplomacy § GP–Minor
## Rules, military-armies § Home Army); `to_id == MapModel.NO_ID` retires its
## armies (capital-and-connectivity § Capital loss). The owner stores again.
static func hand_over(armies: Array[ArmyState], from_id: int, to_id: int) -> void:
	for index in range(armies.size() - 1, -1, -1):
		var army: ArmyState = armies[index]
		if army == null or army.owner != from_id:
			continue
		if to_id == MapModel.NO_ID:
			armies.remove_at(index)
			continue
		army.owner = to_id
		army.home = false


## Splits the named instances into a new field army in the same province; the
## source keeps its Home Army flag (never deleted) and the caller owns the list.
static func split(
	armies: Array[ArmyState],
	source: ArmyState,
	regiment_ids: Array[String],
	new_id: int
) -> Dictionary:
	if source == null or not armies.has(source):
		return _deny("There is no army to split.")
	if source.is_embarked():
		return _deny("Land the army before detaching; a squadron carries it as one.")
	if regiment_ids.is_empty():
		return _deny("Choose at least one regiment to detach.")
	var types: Dictionary = {}
	## Its condition, title, record and honours travel with it: a veteran stays one.
	var condition: Dictionary = {}
	for regiment_id: String in regiment_ids:
		if not source.regiments.has(regiment_id):
			return _deny("That regiment is not in this army.")
		if types.has(regiment_id):
			return _deny("A regiment can only be detached once.")
		types[regiment_id] = source.type_of(regiment_id)
		condition[regiment_id] = source.condition_of(regiment_id)
	var detached := ArmyState.create(
		new_id, source.owner, source.province, false, regiment_ids, types
	)
	for regiment_id: String in regiment_ids:
		var data: Dictionary = condition[regiment_id]
		detached.regiment_health[regiment_id] = int(data["hp"])
		detached.regiment_medals[regiment_id] = int(data["medals"])
	RegimentRecord.take(source, detached, regiment_ids)
	detached.moved = source.moved
	for regiment_id: String in regiment_ids:
		source.remove_regiment(regiment_id)
	armies.append(detached)
	if not source.home and source.is_empty():
		HospitalTrain.split_carry(source, detached)
		armies.erase(source)
	return {"ok": true, "reason": "", "army": detached}


## Combines same-owner armies sharing a province: the Home Army is always the
## merge target, else the first in panel order (military-armies § Split and combine).
static func combine(armies: Array[ArmyState], selected: Array[ArmyState]) -> Dictionary:
	if selected.size() < 2 or selected[0] == null:
		return _deny("Select two armies in the same province to combine.")
	var province: int = selected[0].province
	var owner: int = selected[0].owner
	var target: ArmyState = selected[0]
	var any_moved: bool = false
	for army: ArmyState in selected:
		if army == null or not armies.has(army):
			return _deny("That army is no longer on the map.")
		if army.is_embarked():
			return _deny("Land the armies before combining; a squadron carries one army.")
		if army.owner != owner or army.province != province:
			return _deny("Armies must share a province and an owner to combine.")
		any_moved = any_moved or army.moved
		if army.home:
			target = army
	for army: ArmyState in selected:
		if army == target:
			continue
		HospitalTrain.combine_carry(target, army)
		for regiment_id: String in army.regiments:
			var data: Dictionary = army.condition_of(regiment_id)
			target.add_regiment(regiment_id, army.type_of(regiment_id))
			target.regiment_health[regiment_id] = int(data["hp"])
			target.regiment_medals[regiment_id] = int(data["medals"])
		## Title and record travel with the instance, as a hull's name does.
		RegimentRecord.carry(army, target)
		armies.erase(army)
	if any_moved:
		target.moved = true
	return {"ok": true, "reason": "", "army": target}


## Drops empty field armies; the Home Army persists at zero regiments.
static func prune(armies: Array[ArmyState]) -> void:
	var index: int = armies.size() - 1
	while index >= 0:
		var army: ArmyState = armies[index]
		if army != null and army.is_empty() and not army.home:
			armies.remove_at(index)
		index -= 1


## Regiments owned by one faction in a roster (null entries skipped).
static func count_of(armies: Array[ArmyState], owner: int) -> int:
	var total: int = 0
	for army: ArmyState in armies:
		if army != null and army.owner == owner:
			total += army.count()
	return total


## Grain a faction's regiments eat every turn (wiki: combat § Feeding); a train's
## nurses eat inside the same line (DR-20261112-07).
static func food_upkeep_of(armies: Array[ArmyState], owner: int) -> int:
	var total: int = 0
	for army: ArmyState in armies:
		if army == null or army.owner != owner:
			continue
		if army.field_hospital:
			total += HospitalTrain.food()
		for regiment_id: String in army.regiments:
			total += RegimentCatalog.food_upkeep(army.type_of(regiment_id))
	return total


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "army": null}
