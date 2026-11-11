class_name ResourceRoutes
extends RefCounted
## The crown's built roads and railroads, projected for the survey lens (wiki:
## capital-and-connectivity § Capital Setup, extraction-and-improvements
## § Transport Level). The chart itself draws no roads — they clutter the
## fit-zoom view — so the lens is the one place the network is shown.
##
## Pure projection (REQ-P3-03): one segment per 4-adjacent pair of the crown's
## own transport tiles, tagged road/rail and whether both ends reach the
## capital. Foreign roads and unknown ground never contribute (REQ-P1-03).

## Right and down only: each pair is emitted once, from its first tile.
const STEPS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN]


## `segments` are `{a, b, rail, linked, fogged}` in tile coordinates, in
## row-major order; `counts` totals road/rail segments and the linked ones.
static func snapshot(
	model: MapModel,
	works: LandWorks,
	owner: int,
	capital_tile: Vector2i = CivilianState.NO_TILE,
	visibility: VisibilityModel = null
) -> Dictionary:
	var segments: Array[Dictionary] = []
	var counts: Dictionary = {"road": 0, "rail": 0, "linked": 0}
	if model == null or works == null or owner < 0:
		return {"segments": segments, "counts": counts}
	var network: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile
	).get("network", {}) as Dictionary
	for y in model.height:
		for x in model.width:
			var tile := Vector2i(x, y)
			if not _road_tile(model, works, owner, tile, visibility):
				continue
			for step: Vector2i in STEPS:
				var next: Vector2i = tile + step
				if not _road_tile(model, works, owner, next, visibility):
					continue
				var segment: Dictionary = _segment(
					model, works, tile, next, network, visibility
				)
				segments.append(segment)
				var key: String = "rail" if bool(segment["rail"]) else "road"
				counts[key] = int(counts[key]) + 1
				if bool(segment["linked"]):
					counts["linked"] = int(counts["linked"]) + 1
	return {"segments": segments, "counts": counts}


## One segment's reading, so draw and tests agree on what a line means.
static func _segment(
	model: MapModel,
	works: LandWorks,
	from: Vector2i,
	to: Vector2i,
	network: Dictionary,
	visibility: VisibilityModel
) -> Dictionary:
	var level: int = maxi(
		works.transport_at(model, from), works.transport_at(model, to)
	)
	var from_index: int = model.index_of(from.x, from.y)
	var to_index: int = model.index_of(to.x, to.y)
	return {
		"a": from,
		"b": to,
		"rail": level >= LandWorks.TRANSPORT_RAIL,
		"linked": network.has(from_index) and network.has(to_index),
		"fogged": _fogged(visibility, from) or _fogged(visibility, to),
	}


## A road tile the lens may draw: the crown's own, on land and charted.
static func _road_tile(
	model: MapModel,
	works: LandWorks,
	owner: int,
	tile: Vector2i,
	visibility: VisibilityModel
) -> bool:
	if not model.in_bounds(tile.x, tile.y) or not model.is_land(tile.x, tile.y):
		return false
	if model.owner_at(tile.x, tile.y) != owner:
		return false
	if works.transport_at(model, tile) < LandWorks.TRANSPORT_ROAD:
		return false
	return not _unknown(visibility, tile)


static func _unknown(visibility: VisibilityModel, tile: Vector2i) -> bool:
	if visibility == null:
		return false
	return visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN


static func _fogged(visibility: VisibilityModel, tile: Vector2i) -> bool:
	if visibility == null:
		return false
	return visibility.level_at(tile.x, tile.y) != VisibilityModel.Level.FULLY_VISIBLE
