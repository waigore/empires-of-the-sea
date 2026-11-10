class_name AiCivilianPlanner
extends RefCounted
## Full-AI civilian work policy (wiki: civilian-work-planner, growth-stage-planner).
##
## One legal order per idle civilian: Builders raise the estate the stores are
## shortest of, Engineers extend the transport network and, at war, raise a
## fort, Explorers prospect their minerals, Rail Builders upgrade roads, and
## Spies observe rival Great Powers or keep a counter-espionage screen. Every
## candidate is checked by CivilianWork before it is emitted, so the planner
## cannot invent an outcome or spend a commodity twice (REQ-P2-03, REQ-P3-03).
## Pure rules: state in, orders out; the map adapter applies them.

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
	for unit: CivilianState in roster:
		if unit.is_working():
			continue
		var best: Dictionary = _best_work(
			config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
			context, reserved, screened
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
		"training": training_order(config, units, context),
	}


## Next civilian to train: builders first, then one engineer and one explorer;
## at war a court wants a spy screen before another explorer (wiki:
## civilian-build-planner).
static func training_order(
	config: AiConfig, units: Array, context: Dictionary
) -> Dictionary:
	if config == null or int(context.get("capital_province", -1)) < 0:
		return {}
	var own: Array[CivilianState] = _owned_units(units, config.faction)
	if own.size() >= config.parameter("civilian.max_civilians"):
		return {}
	var type_id: String = _preferred_type(own, bool(context.get("at_war", false)))
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
	screened: bool = false
) -> Dictionary:
	match unit.type_id:
		"builder":
			return _best_builder(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, reserved
			)
		"engineer":
			return _best_engineer(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, reserved
			)
		"explorer":
			return _best_explorer(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, reserved
			)
		"rail_builder":
			return _best_rail(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, reserved
			)
		"spy":
			return AiSpyPlanner.best_work(
				config, model, unit, units, works, stockpile, tech_caps,
				tech_unlocked, context, screened
			)
	return {}


static func _best_builder(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	var target: int = config.parameter("civilian.need_target")
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if reserved.has(tile):
			continue
		var resource: int = model.resource_at(tile.x, tile.y)
		if resource == MapModel.NO_ID:
			continue
		var level: int = works.improvement_at(model, tile)
		if level >= LandWorks.MAX_IMPROVEMENT:
			continue
		var crop: String = ImprovementCatalog.commodity(resource)
		var score: int = config.parameter("civilian.improvement_weight")
		score += _need(crop, stockpile, target) * 10
		if level <= 0:
			score += 10
		var candidate: Dictionary = AiCivilianCandidate.make(
			model, unit, "build_improvement", tile, works, units, stockpile,
			tech_caps, tech_unlocked, context, score
		)
		best = _better(best, candidate)
	return best


static func _best_engineer(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	var target: int = config.parameter("civilian.need_target")
	var seat: Vector2i = context.get("capital_tile", Vector2i(-1, -1))
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		model, works, unit.owner, seat
	)
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if reserved.has(tile) or model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
			continue
		if works.transport_at(model, tile) >= LandWorks.TRANSPORT_ROAD:
			continue
		var crop: String = ImprovementCatalog.commodity(model.resource_at(tile.x, tile.y))
		var score: int = config.parameter("civilian.road_weight")
		score += _need(crop, stockpile, target) * 4
		if works.improvement_at(model, tile) > 0:
			score += 15
		if _touches_connected(model, tile, connected):
			score += 30
		var road: Dictionary = AiCivilianCandidate.make(
			model, unit, "build_road", tile, works, units, stockpile, tech_caps,
			tech_unlocked, context, score
		)
		best = _better(best, road)
	var port: Dictionary = _port_candidate(
		config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
		context, reserved
	)
	best = _better(best, port)
	if bool(context.get("at_war", false)):
		var fort: Dictionary = _fort_candidate(
			config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
			context
		)
		best = _better(best, fort)
	# A province's town only connects its estates when the town itself reaches
	# the capital, so a town link outranks incidental works — but not the
	# court's own fort when it is invaded (wiki: ai-architecture
	# § Town-per-province roads; capital-and-connectivity § Town rule).
	var town_road: Dictionary = AiTownRoads.best_candidate(
		config, model, unit, works, units, stockpile, tech_caps, tech_unlocked,
		context, connected, reserved
	)
	if not town_road.is_empty() and String(best.get("action", "")) != "build_fort":
		best = town_road
	return best


static func _best_explorer(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> Dictionary:
	if reserved.has(unit.tile) or model.owner_at(unit.tile.x, unit.tile.y) != unit.owner:
		return {}
	var resource: int = model.resource_at(unit.tile.x, unit.tile.y)
	if not ImprovementCatalog.needs_prospecting(resource):
		return {}
	var score: int = config.parameter("civilian.prospect_weight")
	score += _need(
		ImprovementCatalog.commodity(resource), stockpile,
		config.parameter("civilian.need_target")
	) * 10
	return AiCivilianCandidate.make(
		model, unit, "prospect", unit.tile, works, units, stockpile, tech_caps,
		tech_unlocked, context, score
	)


static func _best_rail(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if reserved.has(tile) or works.transport_at(model, tile) < LandWorks.TRANSPORT_ROAD:
			continue
		var score: int = 20 + _need(
			ImprovementCatalog.commodity(model.resource_at(tile.x, tile.y)),
			stockpile, config.parameter("civilian.need_target")
		) * 4
		var candidate: Dictionary = AiCivilianCandidate.make(
			model, unit, "build_rail", tile, works, units, stockpile, tech_caps,
			tech_unlocked, context, score
		)
		best = _better(best, candidate)
	return best


static func _port_candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> Dictionary:
	for province: ProvinceState in model.provinces:
		if province.owner != unit.owner or works.province_has_port(model, province.id):
			continue
		for tile: Vector2i in province.tiles:
			if reserved.has(tile) or not MapGeo.is_coastal_tile(model, tile.x, tile.y):
				continue
			return AiCivilianCandidate.make(
				model, unit, "build_port", tile, works, units, stockpile, tech_caps,
				tech_unlocked, context, config.parameter("civilian.port_weight")
			)
	return {}


static func _fort_candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary
) -> Dictionary:
	var province: int = int(context.get("capital_province", -1))
	if province < 0:
		return {}
	var tile: Vector2i = model.capital_tile_of(province)
	if tile.x < 0:
		return {}
	var score: int = config.parameter("civilian.fort_weight") + 50
	return AiCivilianCandidate.make(
		model, unit, "build_fort", tile, works, units, stockpile, tech_caps,
		tech_unlocked, context, score
	)


## Movement fallback: an idle Explorer walks one legal tile toward the nearest
## unprospected mineral on its own land; an idle Spy is handled by AiSpyPlanner.
static func _best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, units: Array,
	context: Dictionary = {}, screened: bool = false
) -> Dictionary:
	if unit.type_id == "spy":
		return AiSpyPlanner.best_move(model, unit, units, context, screened)
	if unit.type_id != "explorer":
		return {}
	var goal: Vector2i = _nearest_mineral(model, unit, works)
	if goal.x < 0:
		return {}
	var best: Dictionary = {}
	for tile: Vector2i in CivilianMovement.valid_tiles(model, unit):
		var distance: int = absi(tile.x - goal.x) + absi(tile.y - goal.y)
		if best.is_empty() or distance < int(best["distance"]):
			best = {"kind": KIND_MOVE, "unit_id": unit.id, "tile": tile, "distance": distance}
		elif distance == int(best["distance"]) and tile < Vector2i(best["tile"]):
			best = {"kind": KIND_MOVE, "unit_id": unit.id, "tile": tile, "distance": distance}
	return best


static func _nearest_mineral(model: MapModel, unit: CivilianState, works: LandWorks) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = 1 << 30
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if not ImprovementCatalog.needs_prospecting(model.resource_at(tile.x, tile.y)):
			continue
		if works.is_prospected(unit.owner, model, tile):
			continue
		var distance: int = absi(tile.x - unit.tile.x) + absi(tile.y - unit.tile.y)
		if distance < best_distance or (distance == best_distance and tile < best):
			best = tile
			best_distance = distance
	return best


# --- shared helpers ----------------------------------------------------------


static func _owned_units(units: Array, owner: int) -> Array[CivilianState]:
	var roster: Array[CivilianState] = []
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner:
			roster.append(unit)
	roster.sort_custom(func(a: CivilianState, b: CivilianState) -> bool: return a.id < b.id)
	return roster


static func _preferred_type(
	roster: Array[CivilianState], at_war: bool = false
) -> String:
	var builders: int = 0
	var engineers: int = 0
	var explorers: int = 0
	var spies: int = 0
	for unit: CivilianState in roster:
		if unit.type_id == "builder":
			builders += 1
		elif unit.type_id == "engineer":
			engineers += 1
		elif unit.type_id == "explorer":
			explorers += 1
		elif unit.type_id == "spy":
			spies += 1
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
	return "builder"


static func _need(commodity: String, stockpile: Dictionary, target: int) -> int:
	if commodity.is_empty():
		return 0
	return clampi(target - int(stockpile.get(commodity, 0)), 0, target)


static func _touches_connected(model: MapModel, tile: Vector2i, connected: Dictionary) -> bool:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var next: Vector2i = tile + offset
		if model.in_bounds(next.x, next.y) and connected.has(model.index_of(next.x, next.y)):
			return true
	return false


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
