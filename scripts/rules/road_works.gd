class_name RoadWorks
extends RefCounted
## The crown's road works (wiki: capital-and-connectivity § Connectivity,
## civilian-units § Work Order Summary): the shortest owned-land route that
## brings a tile beside the crown network, and the Engineer dispatch that lays
## its first tile. Pure rules — the province dossier reads `plan` and emits the
## intent, CivilianWork gates and charges the order (REQ-P2-03, REQ-P3-03).
##
## The route is the same BFS the crown-road reading draws, so the dossier's
## Build road control and the lens's "n road tiles to lay" can never disagree
## (REQ-P3-02).

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]
const ENGINEER: String = "engineer"
const ROAD: String = "build_road"


## Tiles the crown must road before `target` stands beside the crown network:
## the BFS path over owned land minus the network tile it starts from and the
## target tile itself (an estate extracts as soon as it stands beside the
## road). Empty when no owned-land route exists. `network` is
## [method LandConnectivity.resolve]'s `network`.
static func route(
	model: MapModel, owner: int, network: Dictionary, target: Vector2i
) -> Array[Vector2i]:
	var route_tiles: Array[Vector2i] = [] as Array[Vector2i]
	if model == null or target.x < 0 or network.is_empty():
		return route_tiles
	var target_index: int = model.index_of(target.x, target.y)
	var parent: Dictionary = {}
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for raw: Variant in network.keys():
		var index: int = int(raw)
		seen[index] = true
		parent[index] = -1
		queue.append(_tile_of(model, index))
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		var index: int = model.index_of(tile.x, tile.y)
		if index == target_index:
			break
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			if not model.is_land(next.x, next.y):
				continue
			if model.owner_at(next.x, next.y) != owner:
				continue
			var next_index: int = model.index_of(next.x, next.y)
			if seen.has(next_index):
				continue
			seen[next_index] = true
			parent[next_index] = index
			queue.append(next)
	if not seen.has(target_index) or int(parent.get(target_index, -1)) < 0:
		return route_tiles
	# Walk back from the target to the network, then keep only the tiles between
	# them: the network tile is already roaded and the target extracts as soon
	# as it stands beside the road, so neither is laid.
	var chain: Array[Vector2i] = [] as Array[Vector2i]
	var index: int = target_index
	while index >= 0:
		chain.append(_tile_of(model, index))
		index = int(parent.get(index, -1))
	chain.reverse()
	for i in range(1, chain.size() - 1):
		route_tiles.append(chain[i])
	return route_tiles


## What the dossier reads for one estate: whether it needs a road at all, how
## many tiles the route still takes, whether an idle Engineer can take the order,
## what the order spends and how long it waits — so the press prints its own step
## rather than a hover (DR-20261125-08). `resolved` may be handed in so a whole
## province costs one [method LandConnectivity.resolve] (the dossier's own
## reading). `stockpile` is the crown's live purse when the caller knows it; null
## leaves the money gate to the order that charges it, as the wall, the ward and
## the town reads do (REQ-P2-03).
static func plan(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	capital_tile: Vector2i,
	tile: Vector2i,
	resolved: Dictionary = {},
	stockpile: Variant = null
) -> Dictionary:
	var plan_out: Dictionary = {
		"needed": false,
		"gap": 0,
		"route": [] as Array[Vector2i],
		"engineer": false,
		"reason": "",
		"cost": {},
		"turns": 0,
	}
	if model == null or works == null or owner < 0 or tile.x < 0:
		return plan_out
	if model.owner_at(tile.x, tile.y) != owner:
		return plan_out
	# A bare estate is the Build control's business; only a developed tile has
	# yield to lose to a missing road (wiki: extraction-and-improvements).
	if works.improvement_at(model, tile) <= 0:
		return plan_out
	var live: Dictionary = resolved
	if live.is_empty():
		live = LandConnectivity.resolve(model, works, owner, capital_tile)
	if (live.get("tiles", {}) as Dictionary).has(model.index_of(tile.x, tile.y)):
		return plan_out
	var route_tiles: Array[Vector2i] = route(
		model, owner, live.get("network", {}) as Dictionary, tile
	)
	plan_out["needed"] = true
	plan_out["gap"] = route_tiles.size()
	plan_out["route"] = route_tiles
	var dispatch_tile: Vector2i = route_tiles[0] if not route_tiles.is_empty() else tile
	var engineer: CivilianState = nearest_engineer(units, owner, dispatch_tile)
	plan_out["engineer"] = engineer != null
	# The step the press prints: the Engineer's own price and wait for this tile,
	# read off the order that charges it (DR-20261125-08).
	plan_out["cost"] = CivilianWorkPlan.cost_for(ROAD)
	plan_out["turns"] = CivilianWorkPlan.duration_for(model, ROAD, tile, works)
	# The stores and the tile's own exclusivity are the order's gates too, so a
	# press never offers a step the rules would refuse (REQ-P2-03;
	# DR-20261125-08).
	var short: String = CivilianWorkRefusals.known_stores(plan_out["cost"], stockpile)
	var busy: String = CivilianWorkRefusals.tile_busy(units, engineer, dispatch_tile)
	if route_tiles.is_empty():
		plan_out["reason"] = "No owned-land route to the crown."
	elif engineer == null:
		plan_out["reason"] = "No idle Engineer musters — train one at the capital."
	elif not busy.is_empty():
		plan_out["reason"] = busy
	elif not short.is_empty():
		plan_out["reason"] = short
	return plan_out


## The Build road plans for one province, keyed by tile: only the estates that
## still need a road, so the dossier prints one press per row it can act on. The
## crown network is resolved once for the whole province, so a sheet of five
## estates costs one BFS (REQ-P4-01). `rows` is the estate survey the sheet
## already holds, so the plan and the row it sits under read the same tiles.
static func province_plans(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	capital_tile: Vector2i,
	rows: Array[Dictionary],
	stockpile: Variant = null
) -> Dictionary:
	var plans: Dictionary = {}
	if model == null or works == null or owner < 0:
		return plans
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile
	)
	for row: Dictionary in rows:
		var plan_out: Dictionary = plan(
			model, works, units, owner, capital_tile, row["tile"], resolved,
			stockpile
		)
		if bool(plan_out["needed"]):
			plans[row["tile"]] = plan_out
	return plans


## Dispatch the nearest idle Engineer onto the first tile of the route.
## Returns {ok, message}. Every gate and cost stays in CivilianWork.
static func dispatch(
	model: MapModel,
	units: Array[CivilianState],
	works: LandWorks,
	stockpile: Dictionary,
	visibility: VisibilityModel,
	owner: int,
	capital_tile: Vector2i,
	tile: Vector2i,
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var plan_out: Dictionary = plan(
		model, works, units, owner, capital_tile, tile, {}, stockpile
	)
	if not bool(plan_out["needed"]):
		return {"ok": false, "message": "This estate already reaches the crown."}
	var route_tiles: Array[Vector2i] = plan_out["route"]
	# The plan stays `needed` (the row still names its gap) and carries the gate
	# that shuts the press — a missing route, a missing crew, or a short purse.
	if not String(plan_out["reason"]).is_empty():
		return {"ok": false, "message": String(plan_out["reason"])}
	var engineer: CivilianState = nearest_engineer(units, owner, route_tiles[0])
	var result: Dictionary = CivilianWork.assign(
		model, engineer, ROAD, works, units, stockpile, visibility,
		route_tiles[0], {}, tech_unlocked
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("reason", ""))}
	var estate: String = ImprovementCatalog.display_name(
		model.resource_at(tile.x, tile.y), works.improvement_at(model, tile)
	)
	var left: int = route_tiles.size() - 1
	if left <= 0:
		return {
			"ok": true,
			"message": "%s lays the last road tile to %s — linked next turn." % [
				engineer.display_name(), estate
			],
		}
	return {
		"ok": true,
		"message": "%s lays the first of %d road tiles to %s." % [
			engineer.display_name(), route_tiles.size(), estate
		],
	}


static func idle_engineers(units: Array[CivilianState], owner: int) -> Array[CivilianState]:
	return CivilianWork.idle_crews(units, owner, ENGINEER)


## Closest idle Engineer by Manhattan distance; ties break on unit id, exactly
## as the estates ledger's Builder dispatch does. Null when no Engineer is free,
## so the plan and the dispatch read one hand (REQ-P3-02).
static func nearest_engineer(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return CivilianWork.nearest_crew(units, owner, tile, ENGINEER)


static func _tile_of(model: MapModel, index: int) -> Vector2i:
	var y: int = int(float(index) / float(model.width))
	return Vector2i(index - y * model.width, y)
