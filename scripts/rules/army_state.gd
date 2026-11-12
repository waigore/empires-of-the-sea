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
## Per-instance condition (wiki: combat § Strength): each `unit_<n>`'s remaining
## health pool and its 0-4 chevrons; keyed like `regiment_types`, saved with them.
var regiment_health: Dictionary = {}
var regiment_medals: Dictionary = {}
## Each instance's title, record and battle honours (DR-20261111-18,
## DR-20261112-02). Honours are province ids, newest first.
var regiment_names: Dictionary = {}
var regiment_engagements: Dictionary = {}
var regiment_wins: Dictionary = {}
var regiment_honours: Dictionary = {}
## Fleet instance id carrying this army, or -1 (wiki: ships-and-naval § Naval
## transport; DR-20261109-08). An embarked army has no province and never
## fights on land.
var embarked_fleet: int = -1


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
	## Condition and identity ride along; new instances enter at full strength.
	var kept_health: Dictionary = regiment_health.duplicate()
	var kept_medals: Dictionary = regiment_medals.duplicate()
	var kept_names: Dictionary = regiment_names.duplicate()
	var kept_engagements: Dictionary = regiment_engagements.duplicate()
	var kept_wins: Dictionary = regiment_wins.duplicate()
	var kept_honours: Dictionary = regiment_honours.duplicate()
	regiments = p_regiments.duplicate()
	regiment_types = {}
	regiment_health = {}
	regiment_medals = {}
	regiment_names = {}
	regiment_engagements = {}
	regiment_wins = {}
	regiment_honours = {}
	for regiment_id: String in regiments:
		var type_id: String = RegimentCatalog.normalize(
			String(p_types.get(regiment_id, RegimentCatalog.DEFAULT_TYPE))
		)
		regiment_types[regiment_id] = type_id
		var top: int = RegimentCatalog.max_health(type_id)
		regiment_health[regiment_id] = clampi(
			int(kept_health.get(regiment_id, top)), 1, top
		)
		regiment_medals[regiment_id] = clampi(
			int(kept_medals.get(regiment_id, 0)), 0, RegimentCatalog.MAX_MEDALS
		)
		regiment_names[regiment_id] = String(kept_names.get(regiment_id, ""))
		regiment_engagements[regiment_id] = int(kept_engagements.get(regiment_id, 0))
		regiment_wins[regiment_id] = int(kept_wins.get(regiment_id, 0))
		regiment_honours[regiment_id] = kept_honours.get(regiment_id, [])
	RegimentNames.fill(self)


func count() -> int:
	return regiments.size()


func is_empty() -> bool:
	return regiments.is_empty()


func is_home_army() -> bool:
	return home


func is_embarked() -> bool:
	return embarked_fleet >= 0


## Join Empire: an absorbed crown's regiments pass to the winner, its Home Army
## becoming a field army so the winner keeps exactly one (wiki: diplomacy §
## GP–Minor Rules, military-armies § Home Army). A terminal fall passes
## `MapModel.NO_ID` and the armies leave (capital-and-connectivity § Capital loss).
static func hand_over(groups: Array, from_id: int, to_id: int) -> void:
	for index in range(groups.size() - 1, -1, -1):
		var army: ArmyState = groups[index]
		if army == null or army.owner != from_id:
			continue
		if to_id == MapModel.NO_ID:
			groups.remove_at(index)
			continue
		army.owner = to_id
		army.home = false


func type_of(regiment_id: String) -> String:
	return RegimentCatalog.normalize(
		String(regiment_types.get(regiment_id, RegimentCatalog.DEFAULT_TYPE))
	)


func add_regiment(regiment_id: String, type_id: String = RegimentCatalog.DEFAULT_TYPE) -> void:
	if regiments.has(regiment_id):
		return
	regiments.append(regiment_id)
	var normalized: String = RegimentCatalog.normalize(type_id)
	regiment_types[regiment_id] = normalized
	regiment_health[regiment_id] = RegimentCatalog.max_health(normalized)
	regiment_medals[regiment_id] = 0
	RegimentRecord.start(self, regiment_id)


func remove_regiment(regiment_id: String) -> bool:
	var index: int = regiments.find(regiment_id)
	if index < 0:
		return false
	regiments.remove_at(index)
	regiment_types.erase(regiment_id)
	regiment_health.erase(regiment_id)
	regiment_medals.erase(regiment_id)
	RegimentRecord.forget(self, regiment_id)
	return true


func count_of_type(type_id: String) -> int:
	var wanted: String = RegimentCatalog.normalize(type_id)
	var total: int = 0
	for regiment_id: String in regiments:
		if type_of(regiment_id) == wanted:
			total += 1
	return total


## Auto-resolve strength basis: Σ (FPN + FPM), each regiment scaled by its
## chevrons and its remaining health (wiki: combat § Strength).
func strength() -> float:
	var total: float = 0.0
	for regiment_id: String in regiments:
		var data: Dictionary = condition_of(regiment_id)
		total += (
			float(RegimentCatalog.strength(String(data["type"])))
			* RegimentCatalog.medal_multiplier(int(data["medals"]))
			* float(data["fraction"])
		)
	return total


## One regiment's condition: `type`, `hp`, `max`, `medals` and the health
## fraction its firepower is scaled by. Missing records read as a fresh
## regiment, so old saves and new instances behave alike. The name is a
## separate read (`name_of`) because the strength path must not pay for it.
func condition_of(regiment_id: String) -> Dictionary:
	var type_id: String = type_of(regiment_id)
	var top: int = RegimentCatalog.max_health(type_id)
	var hp: int = clampi(int(regiment_health.get(regiment_id, top)), 0, top)
	return {
		"id": regiment_id,
		"type": type_id,
		"hp": hp,
		"max": top,
		"medals": clampi(
			int(regiment_medals.get(regiment_id, 0)), 0, RegimentCatalog.MAX_MEDALS
		),
		"fraction": float(hp) / float(maxi(top, 1)),
	}


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


## Grain a faction's regiments eat every turn (wiki: combat § Feeding).
static func food_upkeep_of(armies: Array[ArmyState], owner: int) -> int:
	var total: int = 0
	for army: ArmyState in armies:
		if army == null or army.owner != owner:
			continue
		for regiment_id: String in army.regiments:
			total += RegimentCatalog.food_upkeep(army.type_of(regiment_id))
	return total


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "army": null}


## Plain data for local saves: location and every regiment instance.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"province": province,
		"home": home,
		"moved": moved,
		"regiments": regiments.duplicate(),
		"regiment_types": regiment_types.duplicate(),
		"regiment_health": regiment_health.duplicate(),
		"regiment_medals": regiment_medals.duplicate(),
		"regiment_names": regiment_names.duplicate(),
		"regiment_engagements": regiment_engagements.duplicate(),
		"regiment_wins": regiment_wins.duplicate(),
		"regiment_honours": regiment_honours.duplicate(),
		"embarked_fleet": embarked_fleet,
	}


static func from_dict(data: Dictionary) -> ArmyState:
	var army := ArmyState.new()
	army.id = int(data.get("id", -1))
	army.owner = int(data.get("owner", -1))
	army.province = int(data.get("province", MapModel.NO_ID))
	army.home = bool(data.get("home", false))
	army.moved = bool(data.get("moved", false))
	army.embarked_fleet = int(data.get("embarked_fleet", -1))
	var names: Array[String] = []
	for raw: Variant in data.get("regiments", []):
		names.append(String(raw))
	army.regiment_health = _condition_map(data.get("regiment_health", {}))
	army.regiment_medals = _condition_map(data.get("regiment_medals", {}))
	## A pre-record save restores empty maps; `set_regiments` christens it alike.
	army.regiment_names = NameRoster.map_from(data.get("regiment_names", {}))
	army.regiment_engagements = _condition_map(data.get("regiment_engagements", {}))
	army.regiment_wins = _condition_map(data.get("regiment_wins", {}))
	army.regiment_honours = RegimentRecord.honours_from(data.get("regiment_honours", {}))
	army.set_regiments(names, data.get("regiment_types", {}))
	return army


## JSON object with instance keys; keys arrive as strings from disk.
static func _condition_map(raw: Variant) -> Dictionary:
	var mapped: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			mapped[String(key)] = int((raw as Dictionary)[key])
	return mapped

