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
static func best_candidate(query: AiWorkQuery) -> Dictionary:
	if query.config == null or query.model == null or query.unit == null:
		return {}
	if query.works == null:
		return {}
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		query.model, query.works, query.unit.owner,
		query.context.get("capital_tile", CivilianState.NO_TILE)
	)
	var best: Dictionary = AiCivilianCandidate.better(
		_network_candidate(query, connected),
		_port_candidate(query)
	)
	if query.at_war():
		best = AiCivilianCandidate.better(best, fort_candidate(query))
	best = AiCivilianCandidate.better(best, AiHospitalWork.best_candidate(query))
	# A province's town only connects its estates when the town itself reaches
	# the capital, so a town link outranks incidental works — but not the
	# court's own fort when it is invaded, nor (at war) its hospitals
	# (wiki: ai-architecture § Town-per-province roads; DR-20261111-16).
	var town_road: Dictionary = AiTownRoads.best_candidate(query, connected)
	if not town_road.is_empty() and not AiHospitalWork.holds_over_town_link(
		best, query.context
	):
		best = town_road
	return best


# --- network ----------------------------------------------------------------


## Best of a rail over an existing road and a road to a resource without one.
static func _network_candidate(
	query: AiWorkQuery, connected: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	var target: int = query.config.parameter("civilian.need_target")
	var road_weight: int = query.config.parameter("civilian.road_weight")
	for tile: Vector2i in query.model.ownership.owned_tiles(
		query.model, query.unit.owner
	):
		if query.reserved.has(tile):
			continue
		var transport: int = query.works.transport_at(query.model, tile)
		if transport < LandWorks.TRANSPORT_ROAD:
			# A road only earns its keep as the link to a resource tile.
			if query.model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
				continue
			best = AiCivilianCandidate.better(
				best, _road(query, tile, target, road_weight, connected)
			)
		else:
			best = AiCivilianCandidate.better(best, AiCivilianCandidate.make(
				query, "build_rail", tile, RAIL_BASE
			))
	return best


## A road to a resource tile without road: worth more the shorter the stores
## are of its crop, and a premium beside the capital network.
static func _road(
	query: AiWorkQuery, tile: Vector2i, target: int, road_weight: int,
	connected: Dictionary
) -> Dictionary:
	var score: int = road_weight
	# A road is priced on the resource this court can actually read: a hidden
	# mineral earns no premium (DR-20261111-26).
	var known: int = MineralSurvey.known_resource(
		query.model, query.works, query.unit.owner, tile
	)
	score += AiBuilderWork.need(
		ImprovementCatalog.commodity(known), query.stockpile, target
	) * NEED_WEIGHT
	if query.works.improvement_at(query.model, tile) > 0:
		score += IMPROVEMENT_BONUS
	if _touches_connected(query.model, tile, connected):
		score += CONNECTED_BONUS
	return AiCivilianCandidate.make(query, "build_road", tile, score)


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
static func _port_candidate(query: AiWorkQuery) -> Dictionary:
	if query.config == null:
		return {}
	for province: ProvinceState in query.model.provinces:
		if province.owner != query.unit.owner:
			continue
		if query.works.province_has_port(query.model, province.id):
			continue
		for tile: Vector2i in province.tiles:
			if query.reserved.has(tile):
				continue
			if not MapGeo.is_coastal_tile(query.model, tile.x, tile.y):
				continue
			return AiCivilianCandidate.make(
				query, "build_port", tile,
				query.config.parameter("civilian.port_weight")
			)
	return {}


## A fort on the province's own site — the town, as CivilianWork rules it — so
## the order names the tile the work will happen on rather than the seat
## (wiki: siege-mechanics § Fort Levels; DR-20261110-24).
static func fort_candidate(query: AiWorkQuery) -> Dictionary:
	if query.config == null or query.model == null or query.unit == null:
		return {}
	var province: int = int(query.context.get("capital_province", -1))
	if province < 0:
		return {}
	var site: Vector2i = FortRules.site_tile(query.model, province)
	if site.x < 0:
		return {}
	return AiCivilianCandidate.make(
		query, "build_fort", site,
		query.config.parameter("civilian.fort_weight") + FORT_URGENCY
	)
