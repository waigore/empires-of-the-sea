class_name ArmyState
extends RefCounted
## One land army: a persistent container of regiment instances (wiki:
## military-armies). Pure data — no nodes, so movement and combat resolve
## headless (REQ-P3-03).
##
## Regiments are stable instance ids (`unit_<n>`); `regiment_types` maps each
## instance to its catalog type. Every regiment belongs to exactly one army,
## and the Home Army is never deleted even when it has no regiments.


var id: int = -1
var owner: int = -1
var province: int = MapModel.NO_ID
var home: bool = false
var moved: bool = false
var regiments: Array[String] = []
var regiment_types: Dictionary = {}


static func create(
	p_id: int,
	p_owner: int,
	p_province: int,
	p_home: bool,
	p_regiments: Array[String] = [],
	p_types: Dictionary = {}
) -> ArmyState:
	var army := ArmyState.new()
	army.id = p_id
	army.owner = p_owner
	army.province = p_province
	army.home = p_home
	army.set_regiments(p_regiments, p_types)
	return army


## Builds a roster from catalog types, minting `unit_<n>` ids in sequence.
## `first_unit` is the first free instance number; the caller advances its
## counter by `types.size()`.
static func muster(
	p_id: int,
	p_owner: int,
	p_province: int,
	p_home: bool,
	types: Array[String],
	first_unit: int = 1
) -> ArmyState:
	var ids: Array[String] = []
	var mapping: Dictionary = {}
	var next_unit: int = first_unit
	for type_id: String in types:
		var unit_id: String = "unit_%d" % next_unit
		next_unit += 1
		ids.append(unit_id)
		mapping[unit_id] = RegimentCatalog.normalize(type_id)
	return create(p_id, p_owner, p_province, p_home, ids, mapping)


func set_regiments(p_regiments: Array[String], p_types: Dictionary = {}) -> void:
	regiments = p_regiments.duplicate()
	regiment_types = {}
	for regiment_id: String in regiments:
		regiment_types[regiment_id] = RegimentCatalog.normalize(
			String(p_types.get(regiment_id, RegimentCatalog.DEFAULT_TYPE))
		)


func count() -> int:
	return regiments.size()


func is_empty() -> bool:
	return regiments.is_empty()


func is_home_army() -> bool:
	return home


func type_of(regiment_id: String) -> String:
	return RegimentCatalog.normalize(
		String(regiment_types.get(regiment_id, RegimentCatalog.DEFAULT_TYPE))
	)


func add_regiment(regiment_id: String, type_id: String = RegimentCatalog.DEFAULT_TYPE) -> void:
	if regiments.has(regiment_id):
		return
	regiments.append(regiment_id)
	regiment_types[regiment_id] = RegimentCatalog.normalize(type_id)


func remove_regiment(regiment_id: String) -> bool:
	var index: int = regiments.find(regiment_id)
	if index < 0:
		return false
	regiments.remove_at(index)
	regiment_types.erase(regiment_id)
	return true


func count_of_type(type_id: String) -> int:
	var wanted: String = RegimentCatalog.normalize(type_id)
	var total: int = 0
	for regiment_id: String in regiments:
		if type_of(regiment_id) == wanted:
			total += 1
	return total


## Auto-resolve strength basis: Σ (FPN + FPM), medals multiplied by the caller
## (wiki: combat § Strength).
func strength() -> float:
	var total: float = 0.0
	for regiment_id: String in regiments:
		total += float(RegimentCatalog.strength(type_of(regiment_id)))
	return total


## Cavalry share of the army, used for initiative ordering (wiki: combat).
func cavalry_share() -> float:
	if regiments.is_empty():
		return 0.0
	var riders: int = 0
	for regiment_id: String in regiments:
		if RegimentCatalog.is_cavalry(type_of(regiment_id)):
			riders += 1
	return float(riders) / float(regiments.size())


## "2 Peasant Levies · Pikemen" for the army dossier.
func composition_text() -> String:
	if regiments.is_empty():
		return "No regiments"
	var parts: PackedStringArray = PackedStringArray()
	for type_id: String in RegimentCatalog.ids():
		var count: int = count_of_type(type_id)
		if count <= 0:
			continue
		if count == 1:
			parts.append(RegimentCatalog.display_name(type_id))
		else:
			parts.append("%d %s" % [count, RegimentCatalog.display_name(type_id)])
	return " · ".join(parts)


## Splits the named regiment instances into a new field army in the same
## province. The source keeps its Home Army flag (and is never deleted, even
## when emptied); the caller owns the army list and receives the new army.
static func split(
	armies: Array[ArmyState],
	source: ArmyState,
	regiment_ids: Array[String],
	new_id: int
) -> Dictionary:
	if source == null or not armies.has(source):
		return _deny("There is no army to split.")
	if regiment_ids.is_empty():
		return _deny("Choose at least one regiment to detach.")
	var types: Dictionary = {}
	for regiment_id: String in regiment_ids:
		if not source.regiments.has(regiment_id):
			return _deny("That regiment is not in this army.")
		if types.has(regiment_id):
			return _deny("A regiment can only be detached once.")
		types[regiment_id] = source.type_of(regiment_id)
	var detached := ArmyState.create(
		new_id, source.owner, source.province, false, regiment_ids, types
	)
	detached.moved = source.moved
	for regiment_id: String in regiment_ids:
		source.remove_regiment(regiment_id)
	armies.append(detached)
	if not source.home and source.is_empty():
		armies.erase(source)
	return {"ok": true, "reason": "", "army": detached}


## Combines same-owner armies sharing a province. The Home Army is always the
## merge target when present; otherwise the first army in panel order wins
## (wiki: military-armies § Split and combine).
static func combine(armies: Array[ArmyState], selected: Array[ArmyState]) -> Dictionary:
	if selected.size() < 2:
		return _deny("Select two armies in the same province to combine.")
	var province: int = selected[0].province
	var owner: int = selected[0].owner
	var target: ArmyState = selected[0]
	var any_moved: bool = false
	for army: ArmyState in selected:
		if army == null or not armies.has(army):
			return _deny("That army is no longer on the map.")
		if army.owner != owner or army.province != province:
			return _deny("Armies must share a province and an owner to combine.")
		any_moved = any_moved or army.moved
		if army.home:
			target = army
	for army: ArmyState in selected:
		if army == target:
			continue
		for regiment_id: String in army.regiments:
			target.add_regiment(regiment_id, army.type_of(regiment_id))
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


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "army": null}
