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
## civilian to train — the published hire order plus the one crew the court's
## archetype keeps beyond the region's asks (AiStaffTaste). Every candidate is
## checked by CivilianWork before it is emitted, so the planner cannot invent an
## outcome or spend a commodity twice (REQ-P2-03, REQ-P3-03). Modules are
## preloaded by path, so routing never depends on the engine's global class
## cache.
## Pure rules: state in, orders out; the map adapter applies them.

const AiBuilderWork = preload("res://scripts/ai/ai_builder_work.gd")
const AiEngineerWork = preload("res://scripts/ai/ai_engineer_work.gd")
const AiExplorerWork = preload("res://scripts/ai/ai_explorer_work.gd")
const AiMerchantWork = preload("res://scripts/ai/ai_merchant_work.gd")
const AiSpyPlanner = preload("res://scripts/ai/ai_spy_planner.gd")

const KIND_WORK: String = "work"
## Why a court at war hires no expansion crew, printed by the economy trace so
## the closed hire is never silent (REQ-P5-05; DR-20261116-15).
const REASON_CREWS: String = "at war: no new crew"
## The two crews that serve the expansion doors the footing can shut.
const EXPANSION_CREWS: Array[String] = ["explorer", "merchant"]


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
	# The merchant follows the door, not just the deed: one Merchant while a
	# priced deed is openable — the embassy waits on the merchant, so the hire
	# cannot wait on the embassy, and a deed the purse cannot cover this turn is
	# still the deed the merchant will walk to (issue #724, #841; wiki:
	# civilian-units § Merchant).
	train_context["merchant_targets"] = (
		deed_tiles if deed_tiles > 0
		else (
			1 if not AiMerchantWork.openable_deed(
				model, config.faction, context
			).is_empty() else 0
		)
	)
	# The region's asks, and the court's own crew on top (AiStaffTaste).
	var own_targets: Dictionary = region_targets(
		config, model, works, units, stockpile, tech_caps, train_context
	)
	train_context["own_targets"] = own_targets
	train_context["staff_targets"] = AiStaffTaste.raises(config, own_targets)
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
## civilian-build-planner; DR staff lever). The exception is the crew the court's
## own archetype keeps beyond the region's asks: that target is one higher, so a
## court at the map's own target still hires in character (AiStaffTaste).
##
## A court at war hires no **expansion** crew: the Explorer and the Merchant
## serve the voyage and the Tribe chain the same footing holds shut, so the hire
## order stops at them and the yard keeps its coin for the muster
## (DR-20261116-15). Builders, Engineers and Spies are the front's own staff and
## stay open. A caller that passes no footing (`phase` absent) hires exactly as
## published.
static func training_order(
	config: AiConfig, units: Array, context: Dictionary
) -> Dictionary:
	if config == null or int(context.get("capital_province", -1)) < 0:
		return {}
	var own: Array[CivilianState] = _owned_units(units, config.faction)
	var targets: Dictionary = context.get("staff_targets", {})
	# The region's own asks, so the order can name a hire the taste alone wanted.
	var region: Dictionary = context.get("own_targets", {})
	if targets.is_empty():
		region = region_targets(config, null, null, units, {}, {}, context)
		targets = AiStaffTaste.raises(config, region)
	# Discretionary hires (spy, merchant) spend the standing reserve. Extraction
	# staff — builders, engineers, explorers — may draw on the works purse while
	# the court is on `earn`, so a war chest does not freeze the mines that refill
	# it (issue #489 / #603 income lever).
	var hire_purse: int = int(context.get("hire_treasury", context.get("treasury", 0)))
	var works_purse: int = hire_purse
	if bool(context.get("earn", false)):
		works_purse = maxi(hire_purse, int(context.get("treasury", 0)))
	var queue: Array[String] = _hire_queue(
		own,
		targets,
		bool(context.get("at_war", false)),
		context.get("tech_unlocked", {}),
		hire_purse,
		int(context.get("paper", 0))
	)
	# The court's own crew leads once the region can spare it — a taste, never a
	# legality. A shut footing is not its to walk through: an expansion crew it
	# names falls back to the published order's own report.
	var type_id: String = AiStaffTaste.lead(config, queue, own)
	if not crews_open(context) and is_expansion_crew(type_id):
		type_id = ""
	if type_id.is_empty() and not queue.is_empty():
		type_id = queue[0]
	if type_id.is_empty() or not CivilianCatalog.is_implemented(type_id):
		return {}
	# The footing's own reading, never a legality gate: the hire is the court's
	# choice, and a crew it does hire still passes the same catalog gate
	# (DR-20261116-15).
	if not crews_open(context) and is_expansion_crew(type_id):
		return {"ok": false, "reason": REASON_CREWS}
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
	return {
		"ok": true,
		"type_id": type_id,
		"taste": AiStaffTaste.drives(config, type_id, targets, region, own),
	}


## True when the court's footing leaves the expansion-crew slot open. A caller
## that passes no `phase` (fixtures, the mainline planners) reads the published
## behaviour: every crew is open.
static func crews_open(context: Dictionary) -> bool:
	return AiPhasePlanner.opens(
		String(context.get("phase", AiPhasePlanner.PHASE_UNKNOWN)),
		AiPhasePlanner.SLOT_CREWS
	)


## True for the crews the voyage and the Tribe chain need: Explorer, Merchant.
static func is_expansion_crew(type_id: String) -> bool:
	return EXPANSION_CREWS.has(type_id)


## The staff the court wants in this region: the region's owns plus its taste.
static func staff_targets(
	config: AiConfig,
	model: MapModel,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	context: Dictionary
) -> Dictionary:
	return AiStaffTaste.raises(
		config,
		region_targets(config, model, works, units, stockpile, tech_caps, context)
	)


## Per-type staff the region's own work asks for (the court's taste is the extra
## crew [method staff_targets] adds): one base — or the published explorer and
## engineer floor — plus the region's own work queue / work_per_staff, and one
## Explorer kept free while a colonisation voyage is mustering.
static func region_targets(
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


## The crews the court may hire this turn, in the published order: builders,
## engineers, the deed partner once the first two crews stand, a war spy screen
## before another explorer, then the peace spy, then a merchant when a deed is
## on offer or an envoy chain toward one is openable. Empty when every target is
## already met; which of them is taken is the caller's (AiStaffTaste.lead).
static func _hire_queue(
	roster: Array[CivilianState],
	targets: Dictionary,
	at_war: bool = false,
	tech_unlocked: Dictionary = {},
	treasury: int = 0,
	paper: int = 0
) -> Array[String]:
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
	var queue: Array[String] = []
	if builders < int(targets.get("builder", 0)):
		queue.append("builder")
	if engineers < int(targets.get("engineer", 0)):
		queue.append("engineer")
	# The deed partner waits on the crew, not on the estate queue: with the first
	# Builder and Engineer standing, one Merchant is taken ahead of the second
	# Builder and the survey queue — a hire parked behind an unbounded target is
	# a deed never signed (issue #841; wiki: civilian-units § Merchant).
	var deeds: bool = merchants < int(targets.get("merchant", 0))
	var merchant_ready: bool = CivilianCatalog.is_unlocked("merchant", tech_unlocked) and (
		CivilianCatalog.can_afford("merchant", treasury, paper)
	)
	if deeds and merchant_ready and builders >= 1 and engineers >= 1:
		queue.append("merchant")
	if at_war and spies < int(targets.get("spy", 0)):
		queue.append("spy")
	if explorers < int(targets.get("explorer", 0)):
		queue.append("explorer")
	if spies < int(targets.get("spy", 0)) and not queue.has("spy"):
		queue.append("spy")
	if deeds and merchant_ready and not queue.has("merchant"):
		queue.append("merchant")
	return queue
