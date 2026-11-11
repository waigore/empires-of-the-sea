class_name AiEngineerWork
extends RefCounted
## Rival Engineer policy (wiki: civilian-work-planner, civilian-units
## § Engineer, capital-and-connectivity).
##
## An idle Engineer extends the transport network — a road to a resource the
## stores are shortest of and that still wants a road, a rail over an existing
## road — raises a port on its crown's first coastal province without one,
## raises province hospitals, and at war raises the capital's fort. Town links
## outrank incidental works and are scored by [AiTownRoads]; the Engineer's own
## fort, and at war a hospital, outrank a town link (DR-20261111-16). Every
## candidate runs through [AiCivilianCandidate], the same gate the player's
## dossier uses (REQ-P2-03, REQ-P3-03). Pure rules: state in, order out.

## Rail work starts at this base score so a rail outranks an ordinary road.
const RAIL_BASE: int = 20
## Score per unit of the crop shortage a road or rail would relieve.
const NEED_WEIGHT: int = 4
## A road to a tile that already holds an improvement is worth a premium.
const IMPROVEMENT_BONUS: int = 15
## A road beside the crown network joins the estates it connects.
const CONNECTED_BONUS: int = 30
## A fort is raised ahead of every other engineer work while invaded.
const FORT_URGENCY: int = 50


## Highest-scoring legal Engineer order for this court, or {} when none exists.
static func best_candidate(
	config: AiConfig,
	model: MapModel,
	unit: CivilianState,
	units: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	reserved: Dictionary
) -> Dictionary:
	if config == null or model == null or unit == null or works == null:
		return {}
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		model, works, unit.owner, context.get("capital_tile", CivilianState.NO_TILE)
	)
	var best: Dictionary = _better(
		_network_candidate(
			config, model, unit, units, works, stockpile, tech_caps,
			tech_unlocked, context, reserved, connected
		),
		_port_candidate(
			config, model, unit, units, works, stockpile, tech_caps,
			tech_unlocked, context, reserved
		)
	)
	if bool(context.get("at_war", false)):
		best = _better(best, fort_candidate(
			config, model, unit, units, works, stockpile, tech_caps,
			tech_unlocked, context
		))
	best = _better(best, AiHospitalWork.best_candidate(
		config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
		context, reserved
	))
	# A province's town only connects its estates when the town itself reaches
	# the capital, so a town link outranks incidental works — but not the
	# court's own fort when it is invaded, nor (at war) its hospitals
	# (wiki: ai-architecture § Town-per-province roads; DR-20261111-16).
	var town_road: Dictionary = AiTownRoads.best_candidate(
		config, model, unit, works, units, stockpile, tech_caps, tech_unlocked,
		context, connected, reserved
	)
	if not town_road.is_empty() and not AiHospitalWork.holds_over_town_link(best, context):
		best = town_road
	return best


# --- network ----------------------------------------------------------------


## Best of a rail over an existing road and a road to a resource without one.
static func _network_candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary,
	connected: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	var target: int = config.parameter("civilian.need_target")
	var road_weight: int = config.parameter("civilian.road_weight")
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if reserved.has(tile):
			continue
		var transport: int = works.transport_at(model, tile)
		if transport < LandWorks.TRANSPORT_ROAD:
			# A road only earns its keep as the link to a resource tile.
			if model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
				continue
			best = _better(best, _road(
				config, model, unit, tile, works, units, stockpile, tech_caps,
				tech_unlocked, context, target, road_weight, connected
			))
		else:
			best = _better(best, _candidate(
				config, model, unit, "build_rail", tile, works, units, stockpile,
				tech_caps, tech_unlocked, context, RAIL_BASE
			))
	return best


## A road to a resource tile without road: worth more the shorter the stores
## are of its crop, and a premium beside the capital network.
static func _road(
	config: AiConfig, model: MapModel, unit: CivilianState, tile: Vector2i,
	works: LandWorks, units: Array, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, target: int,
	road_weight: int, connected: Dictionary
) -> Dictionary:
	var score: int = road_weight
	score += AiBuilderWork.need(
		ImprovementCatalog.commodity(model.resource_at(tile.x, tile.y)),
		stockpile, target
	) * NEED_WEIGHT
	if works.improvement_at(model, tile) > 0:
		score += IMPROVEMENT_BONUS
	if _touches_connected(model, tile, connected):
		score += CONNECTED_BONUS
	return _candidate(
		config, model, unit, "build_road", tile, works, units, stockpile,
		tech_caps, tech_unlocked, context, score
	)


static func _touches_connected(
	model: MapModel, tile: Vector2i, connected: Dictionary
) -> bool:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var next: Vector2i = tile + offset
		if model.in_bounds(next.x, next.y) and connected.has(model.index_of(next.x, next.y)):
			return true
	return false


# --- harbour and fort -------------------------------------------------------


## The first coastal tile of the crown's first province without a port.
static func _port_candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> Dictionary:
	if config == null:
		return {}
	for province: ProvinceState in model.provinces:
		if province.owner != unit.owner or works.province_has_port(model, province.id):
			continue
		for tile: Vector2i in province.tiles:
			if reserved.has(tile) or not MapGeo.is_coastal_tile(model, tile.x, tile.y):
				continue
			return _candidate(
				config, model, unit, "build_port", tile, works, units, stockpile,
				tech_caps, tech_unlocked, context,
				config.parameter("civilian.port_weight")
			)
	return {}


## A fort on the province's own site — the town, as CivilianWork rules it — so
## the order names the tile the work will happen on rather than the seat
## (wiki: siege-mechanics § Fort Levels; DR-20261110-24).
static func fort_candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary
) -> Dictionary:
	if config == null or model == null or unit == null:
		return {}
	var province: int = int(context.get("capital_province", -1))
	if province < 0:
		return {}
	var site: Vector2i = FortRules.site_tile(model, province)
	if site.x < 0:
		return {}
	return _candidate(
		config, model, unit, "build_fort", site, works, units, stockpile,
		tech_caps, tech_unlocked, context,
		config.parameter("civilian.fort_weight") + FORT_URGENCY
	)


# --- shared helpers ---------------------------------------------------------


## AiCivilianCandidate.make with the shared planner arguments, guarded against
## a missing config so a narrow caller cannot raise an error. `target` lets a
## caller validate the work somewhere other than the tile it names.
static func _candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, action: String,
	tile: Vector2i, works: LandWorks, units: Array, stockpile: Dictionary,
	tech_caps: Dictionary, tech_unlocked: Dictionary, context: Dictionary,
	score: int, target: Vector2i = CivilianState.NO_TILE
) -> Dictionary:
	if config == null:
		return {}
	return AiCivilianCandidate.make(
		model, unit, action, tile, works, units, stockpile, tech_caps,
		tech_unlocked, context, score, target
	)


## Higher score wins; a tile tie goes to the earlier action name, so the same
## save always produces the same order, and stays fixed across candidates.
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
