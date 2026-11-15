class_name EstateRoadPlan
extends RefCounted
## The province dossier's one-tap road: which owned tile an Engineer must road
## next to link a developed estate to the crown, or why no order can run
## (wiki: capital-and-connectivity § Connectivity (Game Rule)).
##
## An estate links under the Road rule when it stands on, or beside, a path of
## owned tiles with transport level >= 1 that reaches the capital network, so the
## plan is the shortest owned-land route from that network to the estate with
## both ends dropped: the network tile is already roaded and the estate extracts
## as soon as it stands beside the road — the same reading CrownRoadSurvey draws
## for a province town.
##
## One Engineer order lays one tile, so a route of three open tiles takes three
## orders; the row reports the step it is on rather than promising one press.
## Pure read: nothing is charged and no unit is touched (REQ-P3-03).

const NO_TILE: Vector2i = Vector2i(-1, -1)
const ROAD: String = "build_road"
const ENGINEER: String = "engineer"


## {ok, reason, step, gap, route}. `step` is the owned tile to road now — the
## one nearest the crown network, so every order extends the road — and `gap` is
## how many road tiles the estate still lacks. `reason` is empty only when `ok`;
## a linked estate answers `ok` false with gap 0.
static func plan(
	model: MapModel,
	works: LandWorks,
	units: Array,
	owner: int,
	capital_tile: Vector2i,
	tile: Vector2i
) -> Dictionary:
	if model == null or works == null or owner < 0 or tile.x < 0:
		return _no("No estate to link.")
	if model.owner_at(tile.x, tile.y) != owner:
		return _no("This estate is held by another crown.")
	if works.improvement_at(model, tile) <= 0:
		return _no("Raise the estate before linking it.")
	var resolved: Dictionary = LandConnectivity.resolve(model, works, owner, capital_tile)
	if (resolved.get("tiles", {}) as Dictionary).has(model.index_of(tile.x, tile.y)):
		return _no("Already linked to the crown.")
	var route: Array[Vector2i] = CrownRoadSurvey.route_to(
		model, owner, resolved.get("network", {}) as Dictionary, tile
	)
	var open: Array[Vector2i] = []
	for step: Vector2i in route:
		if works.transport_at(model, step) < LandWorks.TRANSPORT_ROAD:
			open.append(step)
	if open.is_empty():
		return _no("No owned-land route to the crown.")
	var next: Vector2i = open[0]
	if working_road(units, owner, next) != null:
		return _no("An Engineer is already laying this road.")
	if nearest_engineer(units, owner, next) == null:
		return _no("No idle Engineer musters — train one at the capital.")
	return {"ok": true, "reason": "", "step": next, "gap": open.size(), "route": open}


## The Engineer already laying a road on this tile, or null.
static func working_road(
	units: Array, owner: int, tile: Vector2i
) -> CivilianState:
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner or not unit.is_working():
			continue
		if unit.work_action() == ROAD and unit.work_tile() == tile:
			return unit
	return null


## Closest idle Engineer by Manhattan distance; ties break on unit id.
static func nearest_engineer(
	units: Array, owner: int, tile: Vector2i
) -> CivilianState:
	var best: CivilianState = null
	var best_distance: int = 1 << 30
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner or not unit.is_idle():
			continue
		if unit.type_id != ENGINEER:
			continue
		var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
		if distance < best_distance or (distance == best_distance and unit.id < best.id):
			best = unit
			best_distance = distance
	return best


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "step": NO_TILE, "gap": 0, "route": []}
