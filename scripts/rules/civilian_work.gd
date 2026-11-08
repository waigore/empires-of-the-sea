class_name CivilianWork
extends RefCounted
## Civilian work orders: validation, assignment, multi-turn progress and the
## completion effects (wiki: civilian-units § Work Order Summary and
## § Work Types, extraction-and-improvements § Improvement / Road / Port costs).
##
## Materials are paid when the work is assigned and are not refunded on cancel
## (wiki: § Relations). Terrain, visibility and tile effects are only applied
## when a work order completes during the Build/Work pass.

const MAX_IMPROVEMENT: int = LandWorks.MAX_IMPROVEMENT
const IMPROVEMENT_COSTS: Array[Dictionary] = [
	{},
	{"lumber": 1, "castIron": 1},
	{"lumber": 4, "castIron": 4},
	{"lumber": 8, "castIron": 8},
	{"lumber": 16, "castIron": 16},
]
const ROAD_COST: Dictionary = {"lumber": 1, "castIron": 1}
const PORT_COST: Dictionary = {"lumber": 5, "castIron": 5}
const ROAD_TURNS: int = 1
const PORT_TURNS: int = 2
const PROSPECT_TURNS: int = 1
const EXPLORE_MAX_TURNS: int = 3
## Iron, coal and gold are the map's prospect-required minerals
## (wiki: fog-and-exploration § Prospect-Required Resources).
const MINERAL_RESOURCES: Array[int] = [1, 2, 3]

const LABELS: Dictionary = {
	"explore": "Explore province",
	"prospect": "Prospect minerals",
	"build_improvement": "Build improvement",
	"build_road": "Build road",
	"build_port": "Build port",
}

const COMMODITY_NAMES: Dictionary = {
	"lumber": "lumber",
	"castIron": "cast iron",
	"steel": "steel",
	"bronze": "bronze",
	"paper": "paper",
}


static func label(action: String) -> String:
	return String(LABELS.get(action, action.capitalize()))


static func cost_for(action: String, level: int = 1) -> Dictionary:
	match action:
		"build_improvement":
			return (IMPROVEMENT_COSTS[clampi(level, 1, MAX_IMPROVEMENT)] as Dictionary).duplicate()
		"build_road":
			return ROAD_COST.duplicate()
		"build_port":
			return PORT_COST.duplicate()
	return {}


static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: PackedStringArray = PackedStringArray()
	for commodity: Variant in cost.keys():
		var id: String = String(commodity)
		parts.append("%d %s" % [int(cost[commodity]), String(COMMODITY_NAMES.get(id, id))])
	return " + ".join(parts)


## Wiki exploration time: ceil(3 × tiles / largest province), capped at 3.
static func explore_turns(model: MapModel, province_id: int) -> int:
	var tiles: int = model.province_tiles(province_id).size()
	if tiles <= 0:
		return 1
	var largest: int = 1
	for province: Dictionary in model.provinces:
		largest = maxi(largest, int((province.get("tiles", []) as Array).size()))
	var turns: int = int(ceil(3.0 * float(tiles) / float(largest)))
	return clampi(turns, 1, EXPLORE_MAX_TURNS)


static func duration_for(
	model: MapModel, action: String, tile: Vector2i, works: LandWorks
) -> int:
	match action:
		"explore":
			return explore_turns(model, model.province_at(tile.x, tile.y))
		"prospect":
			return PROSPECT_TURNS
		"build_improvement":
			return clampi(works.improvement_at(model, tile) + 1, 1, MAX_IMPROVEMENT)
		"build_road":
			return ROAD_TURNS
		"build_port":
			return PORT_TURNS
	return 1


## Every action the unit could consider, with the reason it cannot start now.
static func options(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if unit == null:
		return result
	for action: String in CivilianCatalog.works(unit.type_id):
		var check: Dictionary = validate(model, unit, action, works, units, stockpile, visibility)
		var cost: Dictionary = cost_for(action, works.improvement_at(model, unit.tile) + 1)
		result.append({
			"action": action,
			"label": label(action),
			"ok": bool(check.get("ok", false)),
			"reason": String(check.get("reason", "")),
			"cost": cost,
			"cost_text": cost_text(cost),
			"duration": int(check.get("duration", 1)),
		})
	return result


static func validate(
	model: MapModel,
	unit: CivilianState,
	action: String,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null
) -> Dictionary:
	if model == null or unit == null:
		return _no("No civilian selected")
	if not CivilianCatalog.works(unit.type_id).has(action):
		return _no(
			"The %s cannot %s." % [unit.display_name(), label(action).to_lower()]
		)
	if unit.is_working():
		return _no("The %s is already working." % unit.display_name())
	var tile: Vector2i = unit.tile
	if not model.is_land(tile.x, tile.y):
		return _no("Civilian work happens on land.")
	var province: int = model.province_at(tile.x, tile.y)
	if province == MapModel.NO_ID:
		return _no("This tile belongs to no province.")
	var check: Dictionary = _check_action(
		model, unit, action, tile, province, works, units, visibility
	)
	if not bool(check.get("ok", false)):
		return check
	var cost: Dictionary = cost_for(action, works.improvement_at(model, tile) + 1)
	var short: Dictionary = _short_inputs(cost, stockpile)
	if not short.is_empty():
		return _no(
			"Not enough %s in the stockpile." % _commodities_text(short.keys())
		)
	check["cost"] = cost
	check["duration"] = duration_for(model, action, tile, works)
	check["tile"] = tile
	check["province"] = province
	return check


## Validates, charges materials and puts the unit to work.
static func assign(
	model: MapModel,
	unit: CivilianState,
	action: String,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null
) -> Dictionary:
	var check: Dictionary = validate(
		model, unit, action, works, units, stockpile, visibility
	)
	if not bool(check.get("ok", false)):
		return check
	_pay(stockpile, check.get("cost", {}))
	unit.start_work(action, Vector2i(check["tile"]), int(check["duration"]))
	check["label"] = label(action)
	return check


## Build/Work pass: advance every working unit and apply completions.
## Returns one report per working unit; `completed` marks the finished ones.
static func resolve_turn(
	model: MapModel, units: Array[CivilianState], works: LandWorks,
	visibility: VisibilityModel = null
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for unit: CivilianState in units:
		if unit == null or not unit.is_working():
			continue
		var action: String = unit.work_action()
		var tile: Vector2i = unit.work_tile()
		var finished: bool = unit.advance_work()
		var report: Dictionary = {
			"unit": unit,
			"unit_id": unit.id,
			"owner": unit.owner,
			"type_id": unit.type_id,
			"action": action,
			"tile": tile,
			"province": model.province_at(tile.x, tile.y),
			"completed": finished,
			"remaining": unit.remaining_turns(),
			"changed": [],
		}
		if finished:
			report["changed"] = _apply(model, unit, action, tile, works, visibility)
			unit.clear_work()
		reports.append(report)
	return reports


# --- action checks ----------------------------------------------------------


static func _check_action(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	province: int,
	works: LandWorks,
	units: Array[CivilianState],
	visibility: VisibilityModel
) -> Dictionary:
	match action:
		"explore":
			if visibility != null and visibility.is_province_fully_visible(province):
				return _no("%s is already charted." % model.province_name(province))
			return {"ok": true}
		"prospect":
			var resource: int = model.resource_at(tile.x, tile.y)
			if not MINERAL_RESOURCES.has(resource):
				return _no("Only iron, coal and gold tiles can be prospected.")
			if works.is_prospected(unit.owner, model, tile):
				return _no("This tile has already been prospected.")
			return {"ok": true}
		"build_improvement":
			var owned: Dictionary = _owned_land(model, unit, province)
			if not bool(owned["ok"]):
				return owned
			if model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
				return _no("Improvements need a tile with a resource.")
			if works.improvement_at(model, tile) >= MAX_IMPROVEMENT:
				return _no("This tile is already fully improved.")
			return _exclusive(units, unit, tile)
		"build_road":
			var road_land: Dictionary = _owned_land(model, unit, province)
			if not bool(road_land["ok"]):
				return road_land
			if works.transport_at(model, tile) >= LandWorks.TRANSPORT_ROAD:
				return _no("This tile already has a road.")
			return _exclusive(units, unit, tile)
		"build_port":
			var port_land: Dictionary = _owned_land(model, unit, province)
			if not bool(port_land["ok"]):
				return port_land
			if not model.is_coastal_tile(tile.x, tile.y):
				return _no("Ports need a coastal tile.")
			if works.province_has_port(model, province):
				return _no("%s already has a port." % model.province_name(province))
			return _exclusive(units, unit, tile)
	return _no("The %s has no such work order." % unit.display_name())


static func _owned_land(model: MapModel, unit: CivilianState, province: int) -> Dictionary:
	if model.province_owner(province) != unit.owner:
		return _no("This land is not held by your crown.")
	return {"ok": true}


## One Builder/Engineer work order per player and tile (wiki: § Per-player tile
## exclusivity).
static func _exclusive(
	units: Array[CivilianState], unit: CivilianState, tile: Vector2i
) -> Dictionary:
	for other: CivilianState in units:
		if other == null or other == unit or other.owner != unit.owner:
			continue
		if other.is_working() and other.work_tile() == tile:
			return _no("Another crew is already working this tile.")
	return {"ok": true}


# --- completion effects -----------------------------------------------------


static func _apply(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	works: LandWorks,
	visibility: VisibilityModel
) -> Array:
	var province: int = model.province_at(tile.x, tile.y)
	match action:
		"explore":
			if visibility != null:
				return visibility.reveal_province(province)
			return []
		"prospect":
			works.set_prospected(unit.owner, model, tile)
			return [model.index_of(tile.x, tile.y)]
		"build_improvement":
			works.set_improvement(model, tile, works.improvement_at(model, tile) + 1)
			return [model.index_of(tile.x, tile.y)]
		"build_road":
			works.set_transport(model, tile, LandWorks.TRANSPORT_ROAD)
			return [model.index_of(tile.x, tile.y)]
		"build_port":
			works.add_port(model, tile)
			return [model.index_of(tile.x, tile.y)]
	return []


# --- stockpile helpers ------------------------------------------------------


static func _short_inputs(cost: Dictionary, stockpile: Dictionary) -> Dictionary:
	var short: Dictionary = {}
	for commodity: Variant in cost.keys():
		var need: int = int(cost[commodity])
		if int(stockpile.get(String(commodity), 0)) < need:
			short[String(commodity)] = need
	return short


static func _pay(stockpile: Dictionary, cost: Dictionary) -> void:
	for commodity: Variant in cost.keys():
		var id: String = String(commodity)
		stockpile[id] = int(stockpile.get(id, 0)) - int(cost[commodity])


static func _commodities_text(ids: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for raw: Variant in ids:
		var id: String = String(raw)
		parts.append(String(COMMODITY_NAMES.get(id, id)))
	return ", ".join(parts)


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": {}, "duration": 0}
