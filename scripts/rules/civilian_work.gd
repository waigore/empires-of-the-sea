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
## The Builder's town order needs National Bureaucracy (wiki:
## tech-tree-diplomacy-civilian).
const TOWN_TECH: String = "national_bureaucracy"

const LABELS: Dictionary = {
	"explore": "Explore province",
	"prospect": "Prospect minerals",
	"build_improvement": "Build improvement",
	"upgrade_town": "Upgrade town",
	"build_road": "Build road",
	"build_port": "Build port",
	"build_fort": "Build fort",
	"build_rail": "Lay railroad",
	"purchase_land": "Purchase land",
	"counter_spy": "Counter-espionage",
}


static func label(action: String) -> String:
	return String(LABELS.get(action, action.capitalize()))


static func cost_for(action: String, level: int = 1) -> Dictionary:
	return CivilianWorkPlan.cost_for(action, level)


static func cost_text(cost: Dictionary) -> String:
	return CivilianWorkPlan.cost_text(cost)


static func explore_turns(model: MapModel, province_id: int) -> int:
	return CivilianWorkPlan.explore_turns(model, province_id)


static func cost_level(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks
) -> int:
	return CivilianWorkPlan.cost_level(action, model, tile, works)


static func duration_for(
	model: MapModel, action: String, tile: Vector2i, works: LandWorks
) -> int:
	return CivilianWorkPlan.duration_for(model, action, tile, works)



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
			action, cost_level(action, model, unit.tile, works)
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
	## A fort is raised on the province's town tile, wherever the engineer stands
	## (wiki: siege-mechanics § Fort Levels; DR-20261110-24).
	if action == "build_fort":
		var site: Vector2i = FortRules.site_tile(model, province)
		if site.x >= 0:
			tile = site
			province = model.province_at(tile.x, tile.y)
	var cost: Dictionary = cost_for(action, cost_level(action, model, tile, works))
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
		details["fort_level"] = CivilianWorkPlan.fort_target(model, Vector2i(check["tile"]))
	elif action == "upgrade_town":
		details["town_level"] = CivilianWorkPlan.town_upgrade_level(
			model, Vector2i(check["tile"])
		)
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
		# Counter-espionage is ongoing: it never advances or completes, and the
		# spy keeps its screen until the player cancels (wiki: civilian-units).
		if action == SpyRules.WORK_COUNTER:
			continue
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
			var explore_gate: String = CivilianExplorerGates.refusal(
				"explore", model, unit.owner, tile, province, visibility, context
			)
			if not explore_gate.is_empty():
				return _no(explore_gate)
			if visibility != null and visibility.is_province_fully_visible(province):
				return _no("%s is already charted." % model.province_name(province))
			return {"ok": true}
		"prospect":
			var prospect_gate: String = CivilianExplorerGates.refusal(
				"prospect", model, unit.owner, tile, province, visibility, context
			)
			if not prospect_gate.is_empty():
				return _no(prospect_gate)
			var resource: int = model.resource_at(tile.x, tile.y)
			if not ImprovementCatalog.needs_prospecting(resource):
				return _no("Only iron, coal, gold and tin tiles can be prospected.")
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
			var terrain_cap: int = TerrainCaps.hard_cap(
				model.terrain_at(tile.x, tile.y), commodity
			)
			if works.improvement_at(model, tile) + 1 > terrain_cap:
				return _no(
					"Terrain caps %s extraction at level %d here."
					% [ImprovementCatalog.commodity_label(commodity), terrain_cap]
				)
			return CivilianTransport.exclusive(units, unit, tile)
		"upgrade_town":
			var held_town: Dictionary = _owned_land(model, unit, tile)
			if not bool(held_town["ok"]):
				return held_town
			var town_data: ProvinceState = model.province_data(province)
			if town_data == null or not town_data.is_town_tile(tile):
				return _no("Towns are upgraded on the province's town tile.")
			if town_data.town_level() >= CivilianWorkPlan.MAX_TOWN:
				return _no("This town is already fully developed.")
			if not bool(tech_unlocked.get(TOWN_TECH, false)):
				return _no("Requires National Bureaucracy to upgrade a town.")
			return CivilianTransport.exclusive(units, unit, tile)
		"build_fort":
			var held: Dictionary = _owned_land(model, unit, tile)
			if not bool(held["ok"]):
				return held
			if FortRules.level_at(model, province) >= FortRules.MAX_LEVEL:
				return _no("This province already holds a modern fort.")
			var next_fort: int = CivilianWorkPlan.fort_target(model, tile)
			var gate: String = FortRules.tech_gate(next_fort)
			if not gate.is_empty() and not bool(tech_unlocked.get(gate, false)):
				return _no(
					"A %s fort needs %s."
					% [FortRules.level_name(next_fort), TechCatalog.display_name(gate)]
				)
			# Two projects in one province may run; the later completion cannot
			# leap a level (wiki: siege-mechanics § Fort Levels), so the town
			# tile is not exclusive the way an estate tile is.
			return {"ok": true}
		"build_road", "build_port", "build_rail":
			return CivilianTransport.check(
				model, unit, action, tile, works, units, tech_unlocked
			)
		"purchase_land":
			return LandPurchase.check(model, unit, tile, works, units, context)
		"counter_spy":
			# Empire-wide screen: the target is any owned province, and one spy
			# anywhere covers every province (wiki: civilian-units § Spy).
			if model.province_owner(province) != unit.owner:
				return _no("Counter-espionage is kept in your own provinces.")
			return {"ok": true}
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
		"upgrade_town":
			var town_data: ProvinceState = model.province_data(province)
			if town_data != null:
				town_data.town_development = clampi(
					int(unit.work_detail("town_level")), 1, CivilianWorkPlan.MAX_TOWN
				)
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
