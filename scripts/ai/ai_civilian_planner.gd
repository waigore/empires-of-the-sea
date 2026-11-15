class_name AiCivilianPlanner
extends RefCounted
## Rival civilian work pass (wiki: civilian-work-planner, growth-stage-planner).
##
## This planner is the dispatcher, not the policy. Each civilian kind hands off
## to its own work module, so a new kind or a difficulty adds one branch here or
## rewrites one module, never the pass itself:
## - Builders (`ai_builder_work.gd`) raise the estate the stores are shortest of
##   or finish a town that pays a manufacturing bonus.
## - Engineers and Rail Builders (`ai_engineer_work.gd`) extend the transport
##   network, raise a port, hospitals, and at war the court's fort.
## - Explorers (`ai_explorer_work.gd`) survey, prospect and march toward the fog.
## - Merchants (`ai_merchant_work.gd`) buy Minor and Tribe land the court closes.
## - Spies (`ai_spy_planner.gd`) observe rival Great Powers or keep a screen.
##
## The pass itself owns what is genuinely per-run: one estate-ledger read per
## court, a per-tile reservation so two crews never claim one tile, and the next
## civilian to train. Every candidate is checked by CivilianWork before it is
## emitted, so the planner cannot invent an outcome or spend a commodity twice
## (REQ-P2-03, REQ-P3-03). Modules are preloaded by path, so routing never
## depends on the engine's global class cache.
## Pure rules: state in, orders out; the map adapter applies them.

const AiBuilderWork = preload("res://scripts/ai/ai_builder_work.gd")
const AiEngineerWork = preload("res://scripts/ai/ai_engineer_work.gd")
const AiExplorerWork = preload("res://scripts/ai/ai_explorer_work.gd")
const AiMerchantWork = preload("res://scripts/ai/ai_merchant_work.gd")
const AiSpyPlanner = preload("res://scripts/ai/ai_spy_planner.gd")

const KIND_WORK: String = "work"


## Work and movement orders for one court in one region, plus the scored
## candidates and the optional next civilian to train.
static func plan(
	config: AiConfig,
	model: MapModel,
	units: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {}
) -> Dictionary:
	var orders: Array[Dictionary] = []
	var moves: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or model == null or works == null:
		return {"orders": orders, "moves": moves, "candidates": candidates, "training": {}}
	var reserved: Dictionary = {}
	var roster: Array[CivilianState] = _owned_units(units, config.faction)
	var screened: bool = SpyRules.has_counter_spy(units, config.faction)
	var town_raw: Dictionary = AiBuilderWork.town_raw(
		model, config.faction, works, tech_caps, tech_unlocked, context
	)
	# One estate-ledger read per region per court, and only when a Builder is
	# idle: the same rows the player's ESTATES ledger renders, so a Builder
	# prices the yield the crown can gather.
	var estates: Array[Dictionary] = []
	var estates_ready: bool = false
	var train_context: Dictionary = context.duplicate()
	var deed_tiles: int = AiMerchantWork.buyable_tiles(
		model, config.faction, works, context
	).size()
	# The merchant follows the door, not just the deed: one Merchant while an
	# envoy chain toward a priced deed is openable — the embassy waits on the
	# merchant, so the hire cannot wait on the embassy (issue #724; wiki:
	# civilian-units § Merchant).
	train_context["merchant_targets"] = (
		deed_tiles if deed_tiles > 0
		else (1 if AiMerchantWork.chain_openable(model, config.faction, context) else 0)
	)
	train_context["staff_targets"] = staff_targets(
		config, model, works, units, stockpile, tech_caps, train_context
	)
	for unit: CivilianState in roster:
		if unit.is_working():
			continue
		if unit.type_id == "builder" and not estates_ready:
			estates = AiBuilderWork.estate_rows(
				model, works, units, stockpile, config.faction, tech_caps, context
			)
			estates_ready = true
		var best: Dictionary = _best_work(
			config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
			context, reserved, screened, town_raw, estates
		)
		if best.is_empty():
			var move: Dictionary = _best_move(model, unit, works, units, context, screened)
			if not move.is_empty():
				moves.append(move)
			continue
		var tile: Vector2i = best["tile"]
		reserved[tile] = true
		if String(best["action"]) == SpyRules.WORK_COUNTER:
			screened = true
		candidates.append(best)
		orders.append({
			"kind": KIND_WORK,
			"unit_id": unit.id,
			"action": String(best["action"]),
			"tile": tile,
			"score": int(best["score"]),
		})
	return {
		"orders": orders,
		"moves": moves,
		"candidates": candidates,
		"training": training_order(config, units, train_context),
	}


## Next civilian to train: the published hire order, each step against the
## region's staff targets. A court whose staff already meets every target trains
## nothing — there is no staff cap and no unconditional builder fill (wiki:
## civilian-build-planner; DR staff lever).
static func training_order(
	config: AiConfig, units: Array, context: Dictionary
) -> Dictionary:
	if config == null or int(context.get("capital_province", -1)) < 0:
		return {}
	var own: Array[CivilianState] = _owned_units(units, config.faction)
	var targets: Dictionary = context.get("staff_targets", {})
	if targets.is_empty():
		targets = staff_targets(config, null, null, units, {}, {}, context)
	# Discretionary hires (spy, merchant) spend the standing reserve. Extraction
	# staff — builders, engineers, explorers — may draw on the works purse while
	# the court is on `earn`, so a war chest does not freeze the mines that refill
	# it (issue #489 / #603 income lever).
	var hire_purse: int = int(context.get("hire_treasury", context.get("treasury", 0)))
	var works_purse: int = hire_purse
	if bool(context.get("earn", false)):
		works_purse = maxi(hire_purse, int(context.get("treasury", 0)))
	var type_id: String = _preferred_type(
		own,
		targets,
		bool(context.get("at_war", false)),
		context.get("tech_unlocked", {}),
		hire_purse,
		int(context.get("paper", 0))
	)
	if type_id.is_empty() or not CivilianCatalog.is_implemented(type_id):
		return {}
	var tech: Dictionary = context.get("tech_unlocked", {})
	if not CivilianCatalog.is_unlocked(type_id, tech):
		return {}
	var purse: int = hire_purse
	if type_id == "builder" or type_id == "engineer" or type_id == "explorer":
		purse = works_purse
	if not CivilianCatalog.can_afford(
		type_id, purse, int(context.get("paper", 0))
	):
		return {}
	return {"ok": true, "type_id": type_id}


## Per-type staff the college wants in this region: one base (or the published
## explorer/engineer floor) plus the region's own work queue / work_per_staff,
## and one Explorer kept free while a colonisation voyage is mustering.
static func staff_targets(
	config: AiConfig,
	model: MapModel,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	context: Dictionary
) -> Dictionary:
	var per: int = maxi(config.parameter("civilian.work_per_staff"), 1)
	var prospect_work: int = 0
	var uncharted: int = 0
	var provinces: int = 0
	var estate_work: int = 0
	var view: VisibilityModel = context.get("visibility", null)
	if model != null and works != null:
		for province: ProvinceState in model.provinces:
			if model.province_owner(province.id) != config.faction:
				continue
			provinces += 1
			if (
				view != null
				and view.is_province_known(province.id)
				and not view.is_province_fully_visible(province.id)
			):
				uncharted += 1
			prospect_work += MineralSurvey.unsurveyed_in_province(
				model, works, config.faction, province.id, view
			).size()
		for row: Dictionary in AiBuilderWork.estate_rows(
			model, works, units, stockpile, config.faction, tech_caps, context
		):
			if AiBuilderWork.paid_gain(row) > 0:
				estate_work += 1
	var explorers: int = maxi(
		config.parameter("civilian.explorer_target"),
		1 + (prospect_work + uncharted * 3) / per
	)
	var muster: Vector2i = context.get("muster_port", Vector2i(-1, -1))
	if muster.x >= 0:
		explorers += 1
	var merchants: int = 0
	if int(context.get("merchant_targets", 0)) > 0:
		merchants = 1
	return {
		"builder": maxi(2, 1 + estate_work / per),
		"engineer": maxi(
			config.parameter("civilian.engineer_target"),
			1 + provinces / per
		),
		"explorer": explorers,
		"spy": 1,
		"merchant": merchants,
	}


# --- candidate scoring -------------------------------------------------------


static func _best_work(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary,
	screened: bool = false, town_raw: Dictionary = {}, estates: Array = []
) -> Dictionary:
	match unit.type_id:
		"builder":
			return AiBuilderWork.best_candidate(
				config, model, unit, works, units, stockpile, tech_caps,
				tech_unlocked, context, reserved, town_raw, estates
			)
		"engineer", "rail_builder":
			return AiEngineerWork.best_candidate(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, reserved
			)
		"explorer":
			return AiExplorerWork.best_candidate(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, reserved
			)
		"spy":
			return AiSpyPlanner.best_work(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, screened
			)
		"merchant":
			return AiMerchantWork.best_candidate(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, reserved
			)
	return {}


## Movement fallback: an idle Explorer walks one legal tile toward the nearest
## unsurveyed prospectable tile on its own land or the nearest unexplored chart;
## a Merchant walks toward the nearest deed it could sign; an idle Spy is handled
## by AiSpyPlanner.
static func _best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, units: Array,
	context: Dictionary = {}, screened: bool = false
) -> Dictionary:
	if unit.type_id == "spy":
		return AiSpyPlanner.best_move(model, unit, units, context, screened)
	if unit.type_id == "merchant":
		return AiMerchantWork.best_move(model, unit, works, context)
	if unit.type_id != "explorer":
		return {}
	return AiExplorerWork.best_move(model, unit, works, context)


# --- shared helpers ----------------------------------------------------------


static func _owned_units(units: Array, owner: int) -> Array[CivilianState]:
	var roster: Array[CivilianState] = []
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner:
			roster.append(unit)
	roster.sort_custom(func(a: CivilianState, b: CivilianState) -> bool: return a.id < b.id)
	return roster


## Hire order against the region's targets: builders, engineers, a war spy
## screen before another explorer, then the peace spy, then a merchant when a
## deed is on offer or an envoy chain toward one is openable. Empty when every
## target is already met.
static func _preferred_type(
	roster: Array[CivilianState],
	targets: Dictionary,
	at_war: bool = false,
	tech_unlocked: Dictionary = {},
	treasury: int = 0,
	paper: int = 0
) -> String:
	var builders: int = 0
	var engineers: int = 0
	var explorers: int = 0
	var spies: int = 0
	var merchants: int = 0
	for unit: CivilianState in roster:
		if unit.type_id == "builder":
			builders += 1
		elif unit.type_id == "engineer":
			engineers += 1
		elif unit.type_id == "explorer":
			explorers += 1
		elif unit.type_id == "spy":
			spies += 1
		elif unit.type_id == "merchant":
			merchants += 1
	if builders < int(targets.get("builder", 0)):
		return "builder"
	if engineers < int(targets.get("engineer", 0)):
		return "engineer"
	if at_war and spies < int(targets.get("spy", 0)):
		return "spy"
	if explorers < int(targets.get("explorer", 0)):
		return "explorer"
	if spies < int(targets.get("spy", 0)):
		return "spy"
	if merchants < int(targets.get("merchant", 0)) and (
		CivilianCatalog.is_unlocked("merchant", tech_unlocked)
		and CivilianCatalog.can_afford("merchant", treasury, paper)
	):
		return "merchant"
	return ""
