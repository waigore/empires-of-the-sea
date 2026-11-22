class_name CivilianWork
extends RefCounted
## Civilian work orders: validation, assignment, multi-turn progress and the
## completion effects (wiki: civilian-units § Work Order Summary and
## § Work Types, extraction-and-improvements § Improvement / Road / Port costs).
##
## Materials are paid when the work is assigned and are not refunded on cancel
## (wiki: § Relations). Terrain, visibility and tile effects are only applied
## when a work order completes during the Build/Work pass. Per-action start
## gates live in CivilianWorkGates; completion writes in CivilianWorkEffects;
## cost and duration maths in CivilianWorkPlan (REQ-P3-01). The crew roster the
## estates, road and rail orders all pick from — the idle scan, the nearest hand
## and the crew already at a tile — also reads here.

const MAX_IMPROVEMENT: int = LandWorks.MAX_IMPROVEMENT
## The Builder's town order needs National Bureaucracy (wiki:
## tech-tree-diplomacy-civilian).
const TOWN_TECH: String = CivilianWorkPlan.TOWN_TECH

const LABELS: Dictionary = {
	"explore": "Explore province",
	"prospect": "Prospect this tile",
	"build_improvement": "Build improvement",
	"upgrade_town": "Upgrade town",
	"build_road": "Build road",
	"build_port": "Build port",
	"build_fort": "Build fort",
	"build_hospital": "Build hospital",
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


static func cost_level(action: String, model: MapModel, tile: Vector2i, works: LandWorks) -> int:
	return CivilianWorkPlan.cost_level(action, model, tile, works)


static func duration_for(model: MapModel, action: String, tile: Vector2i, works: LandWorks) -> int:
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
		var row: Dictionary = CivilianWorkRows.option_row(
			action, model, unit.tile, works, check, label(action),
			context.get("blockade", null) as Blockades
		)
		row["action"] = action
		row["ok"] = bool(check.get("ok", false))
		row["reason"] = String(check.get("reason", ""))
		row["duration"] = int(check.get("duration", 1))
		result.append(row)
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
		return _no("The %s cannot %s." % [unit.display_name(), label(action).to_lower()])
	if unit.is_working():
		return _no("The %s is already working." % unit.display_name())
	# A crew aboard a squadron is off the map (wiki: civilian-units § Overseas
	# deployment): no work order may be filed for it, whichever surface names the
	# ground. The crew's own sheet reads the same gate.
	if unit.is_embarked():
		return _no("The %s is aboard a squadron." % unit.display_name())
	var tile: Vector2i = unit.tile if target_tile.x < 0 else target_tile
	if not model.is_land(tile.x, tile.y):
		return _no("Civilian work happens on land.")
	var province: int = model.province_at(tile.x, tile.y)
	if province == MapModel.NO_ID:
		return _no("This tile belongs to no province.")
	var check: Dictionary = CivilianWorkGates.check_action(
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
	if action == "build_fort" or action == "build_hospital":
		var site: Vector2i = FortRules.site_tile(model, province)
		if site.x >= 0:
			tile = site
			province = model.province_at(tile.x, tile.y)
	## One crew a player owns builds the town's hospital (civilian-units § Per-player tile exclusivity).
	if action == "build_hospital":
		var free_site: Dictionary = CivilianTransport.exclusive(units, unit, tile)
		if not bool(free_site.get("ok", false)):
			return free_site
	var cost: Dictionary = cost_for(action, cost_level(action, model, tile, works))
	if action == "build_improvement":
		# The H8 bootstrap may waive the raise's inputs (#878).
		cost = CivilianWorkPlan.bootstrap_cost(
			model, tile, stockpile, cost_level(action, model, tile, works)
		)
	var stores_gate: String = CivilianWorkRefusals.stores(cost, stockpile)
	if not stores_gate.is_empty():
		return _no(stores_gate)
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
	details.merge(HospitalRules.work_details(check), true)
	if action == "build_fort":
		details["fort_level"] = CivilianWorkPlan.fort_target(model, Vector2i(check["tile"]))
	elif action == "upgrade_town":
		details["town_level"] = CivilianWorkPlan.town_upgrade_level(
			model, Vector2i(check["tile"])
		)
	elif action == LandPurchase.ACTION:
		details["treasury_cost"] = int(check.get("treasury_cost", 0))
	unit.start_work(action, Vector2i(check["tile"]), int(check["duration"]), unit.tile, details)
	check["label"] = CivilianWorkRows.order_label(action, model, Vector2i(check["tile"]), label(action))
	return check


# --- crew roster -------------------------------------------------------------


## Every idle crew of one trade, in roster order. The estates, road and rail
## orders all pick their Builder or Engineer the same way, so the scan lives
## here instead of in each order module (REQ-P3-01, REQ-P3-02).
## `type_id` empty asks for every free crew of the crown's, whatever its trade.
static func idle_crews(
	units: Array[CivilianState], owner: int, type_id: String
) -> Array[CivilianState]:
	var result: Array[CivilianState] = []
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner or not unit.is_idle():
			continue
		# A crew aboard a squadron is off the map: no ledger may hand it the
		# next estate, road or deed (wiki: civilian-units § Overseas deployment).
		if unit.is_embarked():
			continue
		if not type_id.is_empty() and unit.type_id != type_id:
			continue
		result.append(unit)
	return result


## Closest idle crew of one trade by Manhattan distance; ties break on unit id,
## so two orders on the same tile always send the same hand.
static func nearest_crew(
	units: Array[CivilianState], owner: int, tile: Vector2i, type_id: String
) -> CivilianState:
	var best: CivilianState = null
	var best_distance: int = 1 << 30
	for unit: CivilianState in idle_crews(units, owner, type_id):
		var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
		if distance < best_distance or (distance == best_distance and unit.id < best.id):
			best = unit
			best_distance = distance
	return best


## The crew of one trade already at work on a tile, or null. `action` narrows
## the test to one work order; empty matches any work the crew holds.
static func working_crew(
	units: Array[CivilianState],
	owner: int,
	tile: Vector2i,
	type_id: String,
	action: String = ""
) -> CivilianState:
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner or unit.type_id != type_id:
			continue
		if not unit.is_working() or unit.work_tile() != tile:
			continue
		if not action.is_empty() and unit.work_action() != action:
			continue
		return unit
	return null


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
			report["changed"] = CivilianWorkEffects.apply(
				model, unit, action, tile, works, visibility, economy, report
			)
			if action == "prospect":
				# The despatch names what the survey found (DR-20261111-26).
				report["find"] = MineralSurvey.find_of(model, tile)
			unit.clear_work()
		reports.append(report)
	return reports


# --- stockpile helpers ------------------------------------------------------


static func _pay(stockpile: Dictionary, cost: Dictionary) -> void:
	for commodity: Variant in cost.keys():
		var id: String = String(commodity)
		stockpile[id] = int(stockpile.get(id, 0)) - int(cost[commodity])


static func _no(reason: String) -> Dictionary:
	return CivilianWorkGates.deny(reason)
