class_name ArmyState
extends RefCounted
## One land army: a persistent container of regiment instances (wiki:
## military-armies). Pure data — no nodes, so movement and combat resolve
## headless (REQ-P3-03). Multi-army list surgery (split, combine, prune,
## hand-over, faction counts) lives on [ArmyRoster] so this bag stays one domain
## inside the P3 size bar (REQ-P3-01).
##
## Regiments are stable instance ids (`unit_<n>`); `regiment_types` maps each
## instance to its catalog type. Every regiment belongs to exactly one army,
## and the Home Army is never deleted even when it has no regiments.
## `RegimentRecord` owns each instance's store below: christened on entry,
## re-equipped in place, released on the way out.


var id: int = -1
var owner: int = -1
var province: int = MapModel.NO_ID
var home: bool = false
var moved: bool = false
var regiments: Array[String] = []
var regiment_types: Dictionary = {}
## Per-instance condition (wiki: combat § Strength): health pool and chevrons.
var regiment_health: Dictionary = {}
var regiment_medals: Dictionary = {}
## Each instance's title, record and honours (DR-20261111-18, DR-20261112-02),
## plus the despatch fields and citations it holds (DR-20261112-10).
var regiment_names: Dictionary = {}
var regiment_engagements: Dictionary = {}
var regiment_wins: Dictionary = {}
var regiment_honours: Dictionary = {}
var regiment_history: Dictionary = {}
## Fleet instance id carrying this army, or -1 (wiki: ships-and-naval § Naval
## transport; DR-20261109-08). An embarked army has no province.
var embarked_fleet: int = -1
## Tents that march with the standard (DR-20261112-07); its nurses eat with the
## men and the province record never knows it.
var field_hospital: bool = false


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


## Builds a roster from catalog types, minting `unit_<n>` ids from `first_unit`.
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
	var kept_history: Dictionary = regiment_history.duplicate()
	regiments = p_regiments.duplicate()
	regiment_types = {}
	regiment_health = {}
	regiment_medals = {}
	regiment_names = {}
	regiment_engagements = {}
	regiment_wins = {}
	regiment_honours = {}
	regiment_history = {}
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
		regiment_history[regiment_id] = kept_history.get(regiment_id, {})
	RegimentNames.fill(self)


func count() -> int:
	return regiments.size()


func is_empty() -> bool:
	return regiments.is_empty()


func is_home_army() -> bool:
	return home


func is_embarked() -> bool:
	return embarked_fleet >= 0


func type_of(regiment_id: String) -> String:
	return RegimentCatalog.normalize(
		String(regiment_types.get(regiment_id, RegimentCatalog.DEFAULT_TYPE))
	)


func add_regiment(regiment_id: String, type_id: String = RegimentCatalog.DEFAULT_TYPE) -> void:
	if regiments.has(regiment_id):
		return
	regiments.append(regiment_id)
	regiment_types[regiment_id] = RegimentCatalog.normalize(type_id)
	RegimentRecord.start(self, regiment_id)


## Re-equips one instance (see `RegimentRecord.retype`); the one re-equip path.
func set_type(regiment_id: String, type_id: String) -> void:
	RegimentRecord.retype(self, regiment_id, type_id)


func remove_regiment(regiment_id: String) -> bool:
	var index: int = regiments.find(regiment_id)
	if index < 0:
		return false
	regiments.remove_at(index)
	RegimentRecord.forget(self, regiment_id)
	return true


func count_of_type(type_id: String) -> int:
	var wanted: String = RegimentCatalog.normalize(type_id)
	var total: int = 0
	for regiment_id: String in regiments:
		if type_of(regiment_id) == wanted:
			total += 1
	return total


## Auto-resolve strength basis: Σ (FPN + FPM) × chevrons × health (wiki: combat).
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
## fraction its firepower is scaled by; missing records read as a fresh regiment.
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
		"regiment_history": regiment_history.duplicate(),
		"embarked_fleet": embarked_fleet,
		"field_hospital": field_hospital,
	}


static func from_dict(data: Dictionary) -> ArmyState:
	var army := ArmyState.new()
	army.id = int(data.get("id", -1))
	army.owner = int(data.get("owner", -1))
	army.province = int(data.get("province", MapModel.NO_ID))
	army.home = bool(data.get("home", false))
	army.moved = bool(data.get("moved", false))
	army.embarked_fleet = int(data.get("embarked_fleet", -1))
	army.field_hospital = bool(data.get("field_hospital", false))
	var names: Array[String] = []
	names.assign(data.get("regiments", []))
	army.regiment_health = NameRoster.numbers_from(data.get("regiment_health", {}))
	army.regiment_medals = NameRoster.numbers_from(data.get("regiment_medals", {}))
	## A pre-record save restores empty maps; `set_regiments` christens it alike.
	army.regiment_names = NameRoster.map_from(data.get("regiment_names", {}))
	army.regiment_engagements = NameRoster.numbers_from(data.get("regiment_engagements", {}))
	army.regiment_wins = NameRoster.numbers_from(data.get("regiment_wins", {}))
	army.regiment_honours = RegimentRecord.honours_from(data.get("regiment_honours", {}))
	army.regiment_history = RegimentDecorations.history_from(data.get("regiment_history", {}))
	army.set_regiments(names, data.get("regiment_types", {}))
	return army
