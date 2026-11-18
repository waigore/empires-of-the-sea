class_name MapCanvasPassages
extends RefCounted
## Warp-zone Passage marks on the chart: the water wash, its drawn edges, the
## quiet "Passage" label, and lifting the zone's own sea name above the stack.
## Pure placement into a `MapCanvasPlan` (REQ-P3-01, REQ-P3-03).
##
## Split from `MapCanvasPlan` so passage geometry stays one module while the
## plan keeps names, marks and the compass.


## Marks every warp zone toward another region with a wash over its water, a
## ring and a quiet label so the way across is legible on a chart without
## selecting a fleet (wiki: map-topology).
static func add(plan: MapCanvasPlan, p_model: MapModel, p_world: WorldMap, tile_size: float) -> void:
	if p_world == null:
		return
	for zone_id: int in p_world.warp_zones(p_model.region_id):
		var zone: SeaZoneState = p_model.get_sea_zone(zone_id)
		if zone == null:
			continue
		var center: Vector2 = zone.center * tile_size
		if center == Vector2.ZERO:
			continue
		plan.passages.append(center)
		_add_water(plan, p_model, zone, tile_size)
		_lift_sea_name(plan, center)
		plan.labels.append({
			"text": "Passage",
			"position": center + Vector2(0, 26),
			"size": 12,
			"kind": "passage",
		})


## The zone's own name steps above the crossing mark, so the emblem and the
## Passage slip read as one stack instead of overprinting the type.
static func _lift_sea_name(plan: MapCanvasPlan, center: Vector2) -> void:
	for label: Dictionary in plan.labels:
		if String(label["kind"]) != "sea":
			continue
		if (label["position"] as Vector2).distance_to(center) > 0.5:
			continue
		label["position"] = center + Vector2(0, -36)
		return


## The whole warp zone reads as Passage water: its tiles merged into horizontal
## runs, so a tinted zone costs one rectangle per row instead of one per tile.
## Only tiles that still belong to the zone are washed, so a stale tile list
## cannot paint ordinary water.
static func _add_water(
	plan: MapCanvasPlan, p_model: MapModel, zone: SeaZoneState, tile_size: float
) -> void:
	var rows: Dictionary = {}
	for tile: Vector2i in zone.tiles:
		if p_model.sea_zone_at(tile.x, tile.y) != zone.id:
			continue
		var xs: Array = rows.get(tile.y, [])
		xs.append(tile.x)
		rows[tile.y] = xs
		_add_edges(plan, p_model, tile, zone.id, tile_size)
	var ys: Array = rows.keys()
	ys.sort()
	for y: int in ys:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = int(xs[0])
		var last: int = start
		for i in range(1, xs.size()):
			var x: int = int(xs[i])
			if x == last + 1:
				last = x
				continue
			plan.passage_water.append(_run_rect(start, last, y, tile_size))
			start = x
			last = x
		plan.passage_water.append(_run_rect(start, last, y, tile_size))


static func _run_rect(from_x: int, to_x: int, y: int, tile_size: float) -> Rect2:
	return Rect2(
		Vector2(float(from_x), float(y)) * tile_size,
		Vector2(float(to_x - from_x + 1), 1.0) * tile_size
	)


## One segment per side of a warp-zone tile that faces other water or land, so
## the wash is bounded by a drawn line rather than bleeding into the sea.
static func _add_edges(
	plan: MapCanvasPlan, p_model: MapModel, tile: Vector2i, zone_id: int, tile_size: float
) -> void:
	var sides: Array = [
		[Vector2i.UP, Vector2(tile.x, tile.y), Vector2(tile.x + 1, tile.y)],
		[Vector2i.RIGHT, Vector2(tile.x + 1, tile.y), Vector2(tile.x + 1, tile.y + 1)],
		[Vector2i.DOWN, Vector2(tile.x, tile.y + 1), Vector2(tile.x + 1, tile.y + 1)],
		[Vector2i.LEFT, Vector2(tile.x, tile.y), Vector2(tile.x, tile.y + 1)],
	]
	for side: Array in sides:
		var offset: Vector2i = side[0]
		if p_model.sea_zone_at(tile.x + offset.x, tile.y + offset.y) == zone_id:
			continue
		plan.passage_edges.append(PackedVector2Array([
			(side[1] as Vector2) * tile_size, (side[2] as Vector2) * tile_size
		]))
