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
	"build_fort": "Build fort",
	"build_rail": "Lay railroad",
	"purchase_land": "Purchase land",
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
	if CivilianTransport.knows(action):
		return CivilianTransport.cost(action)
	if action == "build_fort":
		return FortRules.cost(clampi(level, 1, FortRules.MAX_LEVEL))
	if action == "build_improvement":
		return (IMPROVEMENT_COSTS[clampi(level, 1, MAX_IMPROVEMENT)] as Dictionary).duplicate()
	return {}


## Fort the engineer would raise in this province next: level + 1, capped.
static func fort_target(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return FortRules.next_level(0)
	return FortRules.next_level(
		FortRules.level_at(model, model.province_at(tile.x, tile.y))
	)


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
	for province: ProvinceState in model.provinces:
		largest = maxi(largest, int((province.tiles as Array).size()))
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
		"build_fort":
			return FortRules.turns(fort_target(model, tile))
	if CivilianTransport.knows(action):
		return CivilianTransport.turns(action)
	return 1


## Every action the unit could consider, with the reason it cannot start now.
static func options(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {}
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if unit == null:
		return result
	for action: String in CivilianCatalog.works(unit.type_id):
		var check: Dictionary = validate(
			model, unit, action, works, units, stockpile, visibility, CivilianState.NO_TILE,
			tech_caps, tech_unlocked, context
		)
		var cost: Dictionary = cost_for(
			action,
			fort_target(model, unit.tile) if action == "build_fort"
			else works.improvement_at(model, unit.tile) + 1
		)
		var price_text: String = cost_text(cost)
		if action == LandPurchase.ACTION:
			price_text = String(
				check.get("cost_text", LandPurchase.cost_text(model, unit.tile))
			)
		result.append({
			"action": action,
			"label": label(action),
			"ok": bool(check.get("ok", false)),
			"reason": String(check.get("reason", "")),
			"cost": cost,
			"cost_text": price_text,
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
	visibility: VisibilityModel = null,
	target_tile: Vector2i = CivilianState.NO_TILE,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {}
) -> Dictionary:
	if model == null or unit == null:
		return _no("No civilian selected")
	if not CivilianCatalog.works(unit.type_id).has(action):
		return _no(
			"The %s cannot %s." % [unit.display_name(), label(action).to_lower()]
		)
	if unit.is_working():
		return _no("The %s is already working." % unit.display_name())
	var tile: Vector2i = unit.tile if target_tile.x < 0 else target_tile
	if not model.is_land(tile.x, tile.y):
		return _no("Civilian work happens on land.")
	var province: int = model.province_at(tile.x, tile.y)
	if province == MapModel.NO_ID:
		return _no("This tile belongs to no province.")
	var check: Dictionary = _check_action(
		model, unit, action, tile, province, works, units, visibility, tech_caps,
		tech_unlocked, context
	)
	if not bool(check.get("ok", false)):
		return check
	if action == LandPurchase.ACTION:
		check["tile"] = tile
		check["province"] = province
		return check
	var cost: Dictionary = cost_for(
		action,
		fort_target(model, tile) if action == "build_fort"
		else works.improvement_at(model, tile) + 1
	)
	var short: Dictionary = ImprovementSystem.short_inputs(cost, stockpile)
	if not short.is_empty():
		return _no("Stores are short of %s." % cost_text(short))
	check["cost"] = cost
	check["duration"] = duration_for(model, action, tile, works)
	check["tile"] = tile
	check["province"] = province
	return check


## Validates, charges materials and puts the unit to work. `target_tile` lets a
## Builder take an estate away from its current tile (wiki: § Work Types and
## Multi-Turn Builds); cancel returns it to the origin tile.
static func assign(
	model: MapModel,
	unit: CivilianState,
	action: String,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null,
	target_tile: Vector2i = CivilianState.NO_TILE,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {}
) -> Dictionary:
	var check: Dictionary = validate(
		model, unit, action, works, units, stockpile, visibility, target_tile, tech_caps,
		tech_unlocked, context
	)
	if not bool(check.get("ok", false)):
		return check
	_pay(stockpile, check.get("cost", {}))
	var details: Dictionary = {}
	if action == "build_fort":
		details["fort_level"] = fort_target(model, Vector2i(check["tile"]))
	elif action == LandPurchase.ACTION:
		details["treasury_cost"] = int(check.get("treasury_cost", 0))
	unit.start_work(action, Vector2i(check["tile"]), int(check["duration"]), unit.tile, details)
	check["label"] = label(action)
	return check


## Build/Work pass: advance every working unit and apply completions.
## Returns one report per working unit; `completed` marks the finished ones.
static func resolve_turn(
	model: MapModel, units: Array[CivilianState], works: LandWorks,
	visibility: VisibilityModel = null, economy: PlayerEconomy = null
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
			report["changed"] = _apply(model, unit, action, tile, works, visibility, economy)
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
	visibility: VisibilityModel,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {}
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
			var owned: Dictionary = _owned_land(model, unit, tile)
			if not bool(owned["ok"]):
				return owned
			var resource: int = model.resource_at(tile.x, tile.y)
			if resource == MapModel.NO_ID:
				return _no("Improvements need a tile with a resource.")
			if works.improvement_at(model, tile) >= MAX_IMPROVEMENT:
				return _no("This tile is already fully improved.")
			if (
				ImprovementCatalog.needs_prospecting(resource)
				and not works.is_prospected(unit.owner, model, tile)
			):
				return _no("An Explorer must prospect this tile before a mine can rise.")
			var commodity: String = ImprovementCatalog.commodity(resource)
			var tech_cap: int = ImprovementCatalog.tech_cap_for(commodity, tech_caps)
			if works.improvement_at(model, tile) + 1 > tech_cap:
				return _no(
					"Requires %s extraction tech (cap %d) to raise this estate."
					% [ImprovementCatalog.commodity_label(commodity), tech_cap]
				)
			return CivilianTransport.exclusive(units, unit, tile)
		"build_fort":
			var held: Dictionary = _owned_land(model, unit, tile)
			if not bool(held["ok"]):
				return held
			if FortRules.level_at(model, province) >= FortRules.MAX_LEVEL:
				return _no("This province already holds a modern fort.")
			var next_fort: int = fort_target(model, tile)
			var gate: String = FortRules.tech_gate(next_fort)
			if not gate.is_empty() and not bool(tech_unlocked.get(gate, false)):
				return _no(
					"A %s fort needs %s."
					% [FortRules.level_name(next_fort), TechCatalog.display_name(gate)]
				)
			return CivilianTransport.exclusive(units, unit, tile)
		"build_road", "build_port", "build_rail":
			return CivilianTransport.check(
				model, unit, action, tile, works, units, tech_unlocked
			)
		"purchase_land":
			return LandPurchase.check(model, unit, tile, works, units, context)
	return _no("The %s has no such work order." % unit.display_name())


static func _owned_land(model: MapModel, unit: CivilianState, tile: Vector2i) -> Dictionary:
	if model.owner_at(tile.x, tile.y) != unit.owner:
		return _no("This land is not held by your crown.")
	return {"ok": true}


# --- completion effects -----------------------------------------------------


static func _apply(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	works: LandWorks,
	visibility: VisibilityModel,
	economy: PlayerEconomy = null
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
		"build_fort":
			FortRules.apply_build(
				model.province_data(province), unit.work_detail("fort_level")
			)
			return [model.index_of(tile.x, tile.y)]
		"purchase_land":
			if LandPurchase.complete(model, tile, unit.owner, economy):
				return [model.index_of(tile.x, tile.y)]
			return []
	if CivilianTransport.knows(action):
		return CivilianTransport.apply(model, action, tile, works)
	return []


# --- stockpile helpers ------------------------------------------------------


static func _pay(stockpile: Dictionary, cost: Dictionary) -> void:
	for commodity: Variant in cost.keys():
		var id: String = String(commodity)
		stockpile[id] = int(stockpile.get(id, 0)) - int(cost[commodity])


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": {}, "duration": 0}
