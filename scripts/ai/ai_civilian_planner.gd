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
const KIND_MOVE: String = "move"


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
	train_context["merchant_targets"] = AiMerchantWork.buyable_tiles(
		model, config.faction, works, context
	).size()
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


## Next civilian to train: builders first, then one engineer and one explorer;
## at war a court wants a spy screen before another explorer, and a court with a
## Minor or Tribe deed it could sign trains a merchant (wiki:
## civilian-build-planner, civilian-units § Merchant).
static func training_order(
	config: AiConfig, units: Array, context: Dictionary
) -> Dictionary:
	if config == null or int(context.get("capital_province", -1)) < 0:
		return {}
	var own: Array[CivilianState] = _owned_units(units, config.faction)
	if own.size() >= config.parameter("civilian.max_civilians"):
		return {}
	var type_id: String = _preferred_type(
		own,
		bool(context.get("at_war", false)),
		int(context.get("merchant_targets", 0)),
		context.get("tech_unlocked", {}),
		int(context.get("treasury", 0)),
		int(context.get("paper", 0))
	)
	if not CivilianCatalog.is_implemented(type_id):
		return {}
	var tech: Dictionary = context.get("tech_unlocked", {})
	if not CivilianCatalog.is_unlocked(type_id, tech):
		return {}
	if not CivilianCatalog.can_afford(
		type_id, int(context.get("treasury", 0)), int(context.get("paper", 0))
	):
		return {}
	return {"ok": true, "type_id": type_id}


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


static func _best_builder(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary,
	town_raw: Dictionary = {}, estates: Array = []
) -> Dictionary:
	return AiBuilderWork.best_candidate(
		config, model, unit, works, units, stockpile, tech_caps, tech_unlocked,
		context, reserved, town_raw, estates
	)


## Movement fallback: an idle Explorer walks one legal tile toward the nearest
## unprospected mineral on its own land or the nearest unexplored chart; a
## Merchant walks toward the nearest deed it could sign; an idle Spy is handled
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


## A court wants two builders, then an engineer, a spy screen at war, an
## explorer, a counter-spy, and — once Merchant Companies is researched and a
## Minor or Tribe deed it can close is on offer — a merchant.
static func _preferred_type(
	roster: Array[CivilianState],
	at_war: bool = false,
	merchant_targets: int = 0,
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
	if builders < 2:
		return "builder"
	if engineers < 1:
		return "engineer"
	if at_war and spies < 1:
		return "spy"
	if explorers < 1:
		return "explorer"
	if spies < 1:
		return "spy"
	if merchants < 1 and merchant_targets > 0 and (
		CivilianCatalog.is_unlocked("merchant", tech_unlocked)
		and CivilianCatalog.can_afford("merchant", treasury, paper)
	):
		return "merchant"
	return "builder"


## Higher score wins; row-major tile order and action name break ties so the
## same state always produces the same order.
static func _better(best: Dictionary, candidate: Dictionary) -> Dictionary:
	if candidate.is_empty():
		return best
	if best.is_empty():
		return candidate
	if int(candidate["score"]) != int(best["score"]):
		return candidate if int(candidate["score"]) > int(best["score"]) else best
	var left: Vector2i = candidate["tile"]
	var right: Vector2i = best["tile"]
	if left.y != right.y:
		return candidate if left.y < right.y else best
	if left.x != right.x:
		return candidate if left.x < right.x else best
	return candidate if String(candidate["action"]) < String(best["action"]) else best
