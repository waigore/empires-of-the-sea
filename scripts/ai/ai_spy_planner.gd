class_name AiSpyPlanner
extends RefCounted
## Rival spy policy (wiki: civilian-units § Spy, research-state § Spy RP boost).
##
## A spy in a rival Great Power's province holds station: presence reveal, the
## +15% research boost and the court report all need it there. At war one spy
## keeps the empire-wide counter-espionage screen at home, and the rest walk
## toward the nearest unobserved rival province. Pure rules: state in, orders
## out; the map adapter applies them (REQ-P2-03, REQ-P3-03).

const KIND_MOVE: String = "move"


## Work the spy should take this turn, or {} to move/stay. `counter_spy` is the
## only spy order; it is raised when the court is at war and has no screen.
static func best_work(
	config: AiConfig,
	model: MapModel,
	unit: CivilianState,
	units: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	screen_up: bool = false
) -> Dictionary:
	if SpyRules.is_foreign(model, unit):
		return {}
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	if province == MapModel.NO_ID or model.province_owner(province) != unit.owner:
		return {}
	var at_war: bool = bool(context.get("at_war", false))
	if at_war and not screen_up:
		return _counter(config, model, unit, units, works, stockpile, tech_caps,
			tech_unlocked, context)
	if target_province(model, units, unit) < 0:
		return _counter(config, model, unit, units, works, stockpile, tech_caps,
			tech_unlocked, context)
	return {}


## One legal step toward the chosen rival province, or {} to stay put. At war a
## spy abroad is recalled home when no counter-espionage screen is up.
static func best_move(
	model: MapModel, unit: CivilianState, units: Array,
	context: Dictionary = {}, screen_up: bool = false
) -> Dictionary:
	if SpyRules.is_foreign(model, unit):
		if not bool(context.get("at_war", false)) or screen_up:
			return {}
		var home: int = _home_province(model, unit.owner)
		if home < 0:
			return {}
		return _step_to_province(model, unit, home)
	var province: int = target_province(model, units, unit)
	if province < 0:
		return {}
	return _step_to_province(model, unit, province)


static func _step_to_province(
	model: MapModel, unit: CivilianState, province: int
) -> Dictionary:
	var distance: Dictionary = _distance_field(model, model.province_tiles(province))
	var best: Dictionary = {}
	for tile: Vector2i in CivilianMovement.valid_tiles(model, unit):
		var step: int = int(distance.get(tile, 1 << 30))
		if step >= 1 << 30:
			continue
		if best.is_empty() or step < int(best["distance"]):
			best = {"kind": KIND_MOVE, "unit_id": unit.id, "tile": tile, "distance": step}
		elif step == int(best["distance"]) and tile < Vector2i(best["tile"]):
			best = {"kind": KIND_MOVE, "unit_id": unit.id, "tile": tile, "distance": step}
	return best


## Nearest own province, used as the recall destination at war.
static func _home_province(model: MapModel, owner: int) -> int:
	var best: int = -1
	for province: ProvinceState in model.provinces:
		if province.owner == owner and (best < 0 or province.id < best):
			best = province.id
	return best


## Rival Great Power province this spy should observe, or -1 when no rival is
## reachable by land. Provinces already watched by another spy of the same crown
## are skipped first so each observer earns its own +15% (wiki: research-state).
static func target_province(
	model: MapModel, units: Array, unit: CivilianState
) -> int:
	var watched: Dictionary = {}
	for raw: Variant in units:
		var other: CivilianState = raw as CivilianState
		if other == null or other.owner != unit.owner or other == unit:
			continue
		if not SpyRules.is_foreign(model, other):
			continue
		watched[model.province_at(other.tile.x, other.tile.y)] = true
	var field: Dictionary = _distance_field(model, [unit.tile])
	var best: int = -1
	var best_distance: int = 1 << 30
	var fallback: int = -1
	var fallback_distance: int = 1 << 30
	for province: ProvinceState in model.provinces:
		if province.owner == unit.owner:
			continue
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		var distance: int = _province_distance(field, model, province)
		if watched.has(province.id):
			if distance < fallback_distance:
				fallback = province.id
				fallback_distance = distance
			continue
		if distance < best_distance or (distance == best_distance and province.id < best):
			best = province.id
			best_distance = distance
	if best >= 0 and best_distance < 1 << 30:
		return best
	if fallback >= 0 and fallback_distance < 1 << 30:
		return fallback
	return -1


# --- internals ---------------------------------------------------------------


static func _counter(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary
) -> Dictionary:
	var score: int = config.parameter("civilian.spy_weight") + 40
	return AiCivilianCandidate.make(
		model, unit, SpyRules.WORK_COUNTER, unit.tile, works, units, stockpile,
		tech_caps, tech_unlocked, context, score
	)


## Nearest distance from the field to any tile of the province.
static func _province_distance(
	field: Dictionary, model: MapModel, province: ProvinceState
) -> int:
	var best: int = 1 << 30
	for tile: Vector2i in model.province_tiles(province.id):
		best = mini(best, int(field.get(tile, 1 << 30)))
	return best


## Land-only BFS distances (in tiles) from a set of target tiles. Spies walk one
## orthogonal land tile per turn, so water simply has no entry.
static func _distance_field(model: MapModel, targets: Array) -> Dictionary:
	var distance: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for raw: Variant in targets:
		var tile: Vector2i = raw
		if not model.is_land(tile.x, tile.y) or distance.has(tile):
			continue
		distance[tile] = 0
		frontier.append(tile)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for tile: Vector2i in frontier:
			var step: int = int(distance[tile]) + 1
			for offset: Vector2i in CivilianMovement.NEIGHBORS:
				var neighbour: Vector2i = tile + offset
				if not model.in_bounds(neighbour.x, neighbour.y):
					continue
				if not model.is_land(neighbour.x, neighbour.y) or distance.has(neighbour):
					continue
				distance[neighbour] = step
				next.append(neighbour)
		frontier = next
	return distance
