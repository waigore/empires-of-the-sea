class_name HospitalRules
extends RefCounted
## Hospitals: the province building that sets an army's recovery tempo and
## blunts the wear a defeat leaves behind (wiki: combat § Regiment condition;
## DR-20261111-12). A province stores only `hospital_level`; the rest share,
## the triage scale and the build gates are derived here, so the turn tick,
## combat and the dossier read one table (REQ-P3-03).

const MAX_LEVEL: int = 2

## Level 0 is a bare field. `rest_bonus` adds to RegimentCondition.REST_SHARE;
## `triage` is the share of battle wear the province's owner still takes.
const LEVELS: Array[Dictionary] = [
	{},
	{
		"name": "Field hospital",
		"rest_bonus": 0.15,
		"triage": 0.20,
		"turns": 1,
		"tech": "organised_regiments",
		"cost": {"lumber": 3, "fabric": 2},
	},
	{
		"name": "General hospital",
		"rest_bonus": 0.30,
		"triage": 0.35,
		"turns": 2,
		"tech": "modern_military_funding",
		"cost": {"lumber": 4, "fabric": 3, "steel": 2},
	},
]


static func clamp_level(level: int) -> int:
	return clampi(level, 0, MAX_LEVEL)


static func level_name(level: int) -> String:
	return String(_entry(level).get("name", "None"))


## Share of a regiment's pool restored at turn start in this province.
static func rest_share(level: int) -> float:
	return RegimentCondition.REST_SHARE + float(_entry(level).get("rest_bonus", 0.0))


## Multiplier on the battle wear the province's owner takes (1.0 = no relief).
static func triage_scale(level: int) -> float:
	return 1.0 - float(_entry(level).get("triage", 0.0))


static func turns(level: int) -> int:
	return int(_entry(level).get("turns", 1))


static func cost(level: int) -> Dictionary:
	return (_entry(level).get("cost", {}) as Dictionary).duplicate()


## Owned tech id required to raise the province to `level`, or "" when free.
static func tech_gate(level: int) -> String:
	return String(_entry(level).get("tech", ""))


static func next_level(current: int) -> int:
	return mini(clamp_level(current) + 1, MAX_LEVEL)


static func level_at(model: MapModel, province: int) -> int:
	if model == null:
		return 0
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return 0
	return clamp_level(data.hospital_level)


## The tile a hospital is raised on: the province's town, like a fort
## (wiki: siege-mechanics § Fort Levels). -1 on legacy maps with no seat.
static func site_tile(model: MapModel, province: int) -> Vector2i:
	return FortRules.site_tile(model, province)


static func rest_share_at(model: MapModel, province: int) -> float:
	return rest_share(level_at(model, province))


static func triage_scale_at(model: MapModel, province: int) -> float:
	return triage_scale(level_at(model, province))


## Applies a finished build: the province reaches the level that project was
## raised for, and a later completion can never leap a level.
static func apply_build(data: ProvinceState, ordered: int) -> void:
	if data == null:
		return
	var target: int = ordered if ordered > 0 else next_level(data.hospital_level)
	data.hospital_level = clampi(maxi(data.hospital_level, target), 0, MAX_LEVEL)


## Dossier wording, e.g. "Field hospital · rest 40% · wear 80%".
static func describe(level: int) -> String:
	if level <= 0:
		return "No hospital"
	return "%s · rest %d%% · wear %d%%" % [
		level_name(level),
		roundi(rest_share(level) * 100.0),
		roundi(triage_scale(level) * 100.0),
	]


static func _entry(level: int) -> Dictionary:
	return LEVELS[clamp_level(level)]


## Validation for the Engineer's `build_hospital` order. Returns `{"ok": true}`
## (with the level to raise in `details`) or a refusal shaped like
## CivilianWork's `_no`.
static func work_check(
	model: MapModel,
	unit: CivilianState,
	tile: Vector2i,
	province: int,
	tech_unlocked: Dictionary
) -> Dictionary:
	if model.owner_at(tile.x, tile.y) != unit.owner:
		return _refuse("This land is not held by your crown.")
	if level_at(model, province) >= MAX_LEVEL:
		return _refuse("This province already holds a general hospital.")
	var next: int = next_level(level_at(model, province))
	var gate: String = tech_gate(next)
	if not gate.is_empty() and not bool(tech_unlocked.get(gate, false)):
		return _refuse(
			"A %s needs %s." % [level_name(next), TechCatalog.display_name(gate)]
		)
	return {"ok": true, "details": {"hospital_level": next}}


## The work detail a hospital order records, for CivilianWork.assign.
static func work_details(check: Dictionary) -> Dictionary:
	return (check.get("details", {}) as Dictionary).duplicate()


## Applies a finished hospital order and reports the painted tile.
static func work_complete(
	model: MapModel, province: int, unit: CivilianState, tile: Vector2i
) -> Array:
	apply_build(model.province_data(province), unit.work_detail("hospital_level"))
	return [model.index_of(tile.x, tile.y)]


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": {}, "duration": 0}