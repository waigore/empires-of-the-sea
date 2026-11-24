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
## court, a per-tile reservation so two crews never claim one tile, and the
## scored candidates. The standing staffing question it asks each turn has two
## halves: the region's asks (`ai_civilian_targets.gd`, AiCivilianTargets) and
## the published hire order with the next civilian to train
## (`ai_civilian_hire.gd`, AiCivilianHire). Every candidate is checked
## by CivilianWork before it is emitted, so the planner cannot invent an outcome
## or spend a commodity twice (REQ-P2-03, REQ-P3-03). Modules are preloaded by
## path, so routing never depends on the engine's global class cache.
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
	var roster: Array[CivilianState] = AiCivilianHire.owned_units(units, config.faction)
	var screened: bool = SpyRules.has_counter_spy(units, config.faction)
	var town_raw: Dictionary = AiBuilderWork.town_raw(
		model, config.faction, works, tech_caps, tech_unlocked, context
	)
	# One estate-ledger read per region per court, and only when a Builder is
	# idle: the same rows the player's ESTATES ledger renders, so a Builder
	# prices the yield the crown can gather.
	var estates: Array[Dictionary] = []
	var estates_ready: bool = false
	var train_context: Dictionary = AiCivilianTargets.training_context(
		config, model, works, units, stockpile, tech_caps, context
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
		"training": AiCivilianHire.training_order(config, units, train_context),
		# The crew the hire order would take if the purse allowed: the market
		# keeps its price back from this turn's bids (issue #894).
		"next_crew": AiCivilianHire.next_crew(config, units, train_context),
	}


# --- candidate scoring -------------------------------------------------------


static func _best_work(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary,
	screened: bool = false, town_raw: Dictionary = {}, estates: Array = []
) -> Dictionary:
	var query: AiWorkQuery = AiWorkQuery.make(
		config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
		context, reserved
	)
	match unit.type_id:
		"builder":
			return AiBuilderWork.best_candidate(query, town_raw, estates)
		"engineer", "rail_builder":
			return AiEngineerWork.best_candidate(query)
		"explorer":
			return AiExplorerWork.best_candidate(query)
		"spy":
			return AiSpyPlanner.best_work(query, screened)
		"merchant":
			return AiMerchantWork.best_candidate(query)
	return {}


## Movement fallback: an idle Explorer walks one legal tile toward the nearest
## unsurveyed prospectable tile on its own land or the nearest unexplored chart;
## a Merchant walks toward the nearest deed it could sign; a Builder or an
## Engineer the next voyage waits for walks to the harbour that boards it; a Spy
## is handled by AiSpyPlanner.
static func _best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, units: Array,
	context: Dictionary = {}, screened: bool = false
) -> Dictionary:
	if unit.type_id == "spy":
		return AiSpyPlanner.best_move(model, unit, units, context, screened)
	if unit.type_id == "merchant":
		return AiMerchantWork.best_move(model, unit, works, context)
	if unit.type_id == "engineer":
		return AiEngineerWork.best_move(model, unit, context)
	if unit.type_id == "builder":
		return AiBuilderWork.best_move(model, unit, context)
	if unit.type_id != "explorer":
		return {}
	return AiExplorerWork.best_move(model, unit, works, context)
