class_name RoadInk
extends RefCounted
## Road and railroad strokes for the survey lens (wiki: capital-and-connectivity
## § Capital Setup, extraction-and-improvements § Transport Level). Static like
## `MapGlyphs`: the lens owns the node and the reveal, this owns the ink, so the
## drawing stays out of the projection and the plaque code (REQ-P3-03).

const TILE_SIZE: float = 22.0
const ROAD_INK := Color(0.30, 0.22, 0.14)
const UNDERLAY := Color(0.96, 0.92, 0.80)
## Corner cutting plus a small position-keyed warp: a road that turns is one
## curve, and a long run bows instead of ruling a line through the tile centres
## (REQ-P1-03).
const SMOOTH_PASSES: int = 3
const WARP: float = 1.3
const DASH_ON: float = 6.0
const DASH_PERIOD: float = 11.0
const SLEEPER_START: float = 5.5
const SLEEPER_PERIOD: float = 8.5
const SLEEPER_HALF: float = 3.4


## One stroke per inked run. A linked road is solid ink over a pale underlay; a
## railroad adds sleepers; a road the crown's network does not reach is dashed
## and fainter, so "cut off" reads without a second colour language.
static func draw_routes(canvas: CanvasItem, segments: Array, reveal: float) -> void:
	draw_runs(canvas, ink_paths(segments), reveal)


## The same ink from runs a caller already baked, so the lens traces the network
## once per refresh instead of once per repaint.
static func draw_runs(canvas: CanvasItem, runs: Array, reveal: float) -> void:
	for raw: Variant in runs:
		var run: Dictionary = raw
		var alpha: float = _alpha(bool(run["linked"]), bool(run["fogged"]), reveal)
		if alpha <= 0.01:
			continue
		var points: PackedVector2Array = run["points"]
		var ink := Color(ROAD_INK.r, ROAD_INK.g, ROAD_INK.b, alpha)
		if not bool(run["linked"]):
			_dashes(canvas, points, ink)
			continue
		canvas.draw_polyline(
			points, Color(UNDERLAY.r, UNDERLAY.g, UNDERLAY.b, alpha * 0.42), 4.6, true
		)
		canvas.draw_polyline(points, ink, 2.1, true)
		if bool(run["rail"]):
			_sleepers(canvas, points, ink)


## The inked runs for one survey: segments that read the same are traced into
## polylines, corner-cut and warped, so the network reads as a drawn highway
## rather than a grid of tile-centre chords. Pure, so a suite can assert the
## geometry without a canvas.
static func ink_paths(segments: Array, tile_size: float = TILE_SIZE) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for raw: Variant in segments:
		var segment: Dictionary = raw
		var key: String = _band(segment)
		if not groups.has(key):
			groups[key] = {
				"linked": bool(segment["linked"]),
				"rail": bool(segment["rail"]),
				"fogged": bool(segment.get("fogged", false)),
				"chords": [] as Array[PackedVector2Array],
			}
		var group: Dictionary = groups[key]
		var chords: Array[PackedVector2Array] = group["chords"]
		chords.append(_chord(segment, tile_size))
	var runs: Array[Dictionary] = []
	for key: String in groups:
		var group: Dictionary = groups[key]
		var chords: Array[PackedVector2Array] = group["chords"]
		for path: PackedVector2Array in InkPaths.smooth_segments(chords, SMOOTH_PASSES):
			if path.size() < 2:
				continue
			runs.append({
				"points": _warp(path, WARP),
				"linked": bool(group["linked"]),
				"rail": bool(group["rail"]),
				"fogged": bool(group["fogged"]),
			})
	return runs


## Segments only join a run when they read the same: a railroad never borrows a
## plain road's stroke, and a fogged stretch keeps its own fade.
static func _band(segment: Dictionary) -> String:
	return "%s/%s/%s" % [
		bool(segment["linked"]),
		bool(segment["rail"]),
		bool(segment.get("fogged", false)),
	]


static func _chord(segment: Dictionary, tile_size: float) -> PackedVector2Array:
	var from: Vector2i = segment["a"]
	var to: Vector2i = segment["b"]
	return PackedVector2Array([
		MapGeo.tile_center(from.x, from.y, tile_size),
		MapGeo.tile_center(to.x, to.y, tile_size),
	])


## A small warp keyed on each point's own position: two runs that meet at a tile
## centre still meet after it, and a long straight run bows like a drawn road
## instead of ruling the grid.
static func _warp(points: PackedVector2Array, amplitude: float) -> PackedVector2Array:
	var warped := PackedVector2Array()
	for point: Vector2 in points:
		warped.append(point + Vector2(
			sin(point.x * 0.21 + point.y * 0.13) * amplitude,
			sin(point.x * 0.13 - point.y * 0.19 + 1.7) * amplitude
		))
	return warped


static func _alpha(linked: bool, fogged: bool, reveal: float) -> float:
	var alpha: float = reveal * (0.72 if linked else 0.36)
	if fogged:
		alpha *= 0.62
	return alpha


## Segments only join a run when they read the same: a railroad never borrows a
## plain road's stroke, and a fogged stretch keeps its own fade.
static func _band(segment: Dictionary) -> String:
	return "%s/%s/%s" % [
		bool(segment["linked"]),
		bool(segment["rail"]),
		bool(segment.get("fogged", false)),
	]


static func _chord(segment: Dictionary, tile_size: float) -> PackedVector2Array:
	var from: Vector2i = segment["a"]
	var to: Vector2i = segment["b"]
	return PackedVector2Array([
		MapGeo.tile_center(from.x, from.y, tile_size),
		MapGeo.tile_center(to.x, to.y, tile_size),
	])


## A small warp keyed on each point's own position: two runs that meet at a tile
## centre still meet after it, and a long straight run bows like a drawn road
## instead of ruling the grid.
static func _warp(points: PackedVector2Array, amplitude: float) -> PackedVector2Array:
	var warped := PackedVector2Array()
	for point: Vector2 in points:
		warped.append(point + Vector2(
			sin(point.x * 0.21 + point.y * 0.13) * amplitude,
			sin(point.x * 0.13 - point.y * 0.19 + 1.7) * amplitude
		))
	return warped


static func _alpha(linked: bool, fogged: bool, reveal: float) -> float:
	var alpha: float = reveal * (0.72 if linked else 0.36)
	if fogged:
		alpha *= 0.62
	return alpha


## A cut road: short dashes rather than a solid line, so a break in the network
## is visible at fit zoom — and they follow the curve, not a straight chord.
static func _dashes(canvas: CanvasItem, points: PackedVector2Array, ink: Color) -> void:
	var run: float = _length(points)
	var at: float = 1.0
	while at < run - 1.0:
		_span(canvas, points, at, minf(at + DASH_ON, run - 1.0), ink, 1.6)
		at += DASH_PERIOD


## The part of a polyline between two arc lengths, one line per piece, so a dash
## bends with the road.
static func _span(
	canvas: CanvasItem,
	points: PackedVector2Array,
	from: float,
	to: float,
	ink: Color,
	width: float
) -> void:
	var travel: float = 0.0
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		if length <= 0.001:
			continue
		var start: float = travel
		travel += length
		if travel <= from or start >= to:
			continue
		canvas.draw_line(
			a.lerp(b, (maxf(from, start) - start) / length),
			a.lerp(b, (minf(to, travel) - start) / length),
			ink, width, true
		)


## Railroad sleepers across the line: level 4 reads at a glance without a legend
## colour of its own (wiki: extraction-and-improvements § Transport Level).
static func _sleepers(canvas: CanvasItem, points: PackedVector2Array, ink: Color) -> void:
	var run: float = _length(points)
	var at: float = SLEEPER_START
	while at < run:
		var spot: Dictionary = _along(points, at)
		var point: Vector2 = spot["point"]
		var normal: Vector2 = spot["normal"]
		canvas.draw_line(
			point - normal * SLEEPER_HALF, point + normal * SLEEPER_HALF, ink, 1.4, true
		)
		at += SLEEPER_PERIOD


## The point and its normal `at` px along a polyline, so a sleeper sits square
## to the road even where it bends.
static func _along(points: PackedVector2Array, at: float) -> Dictionary:
	var travel: float = 0.0
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		if length <= 0.001:
			continue
		if travel + length >= at:
			var direction: Vector2 = (b - a) / length
			return {
				"point": a.lerp(b, (at - travel) / length),
				"normal": Vector2(-direction.y, direction.x),
			}
		travel += length
	return {"point": points[points.size() - 1], "normal": Vector2.UP}


static func _length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total
