class_name MapCoastField
extends RefCounted
## The shore a chart is painted from: a signed distance to the coast for every
## tile, and the basin's own reach (its deepest water within `REACH` tiles).
##
## Tile geometry only — no colour, no nodes, no image — so the wash bake and any
## later reader of the coastline agree on one shore instead of each recomputing
## it (REQ-P3-01, REQ-P3-03). A bake makes one of these and paints from it.

## How far a tile looks for its basin's deepest water, in tiles.
const REACH: int = 3

var width: int = 0
var height: int = 0
## Signed distance to the shore in tiles, positive inland, negative at sea, zero
## on the inked shoreline.
var sd: PackedFloat32Array = PackedFloat32Array()
## Deepest water within `REACH` tiles of each tile, in tiles: the basin's own
## half-width, which caps the shoal veil so a narrow gulf keeps open water.
var reach: PackedFloat32Array = PackedFloat32Array()


static func build(model: MapModel) -> MapCoastField:
	var field := MapCoastField.new()
	field.width = model.width
	field.height = model.height
	field._coast(model)
	field._reach_field(model)
	return field


## Signed distance to the shore in tiles at a sub-tile position (tile units,
## tile centres on the half). Positive inland, negative at sea, zero on the
## inked shoreline.
func coast_at(tile: Vector2) -> float:
	if sd.is_empty():
		return 0.0
	var g: Vector2 = tile - Vector2(0.5, 0.5)
	var x0: int = clampi(int(floor(g.x)), 0, width - 1)
	var y0: int = clampi(int(floor(g.y)), 0, height - 1)
	var x1: int = clampi(x0 + 1, 0, width - 1)
	var y1: int = clampi(y0 + 1, 0, height - 1)
	var fx: float = clampf(g.x - floor(g.x), 0.0, 1.0)
	var fy: float = clampf(g.y - floor(g.y), 0.0, 1.0)
	var a: float = lerpf(sd[y0 * width + x0], sd[y0 * width + x1], fx)
	var b: float = lerpf(sd[y1 * width + x0], sd[y1 * width + x1], fx)
	return lerpf(a, b, fy)


## A whole tile block this far inside open water can only be deep sea: the bake
## skips its texels, which is most of an ocean map.
func is_deep_water(x: int, y: int, threshold: float) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cx: int = clampi(x + dx, 0, width - 1)
			var cy: int = clampi(y + dy, 0, height - 1)
			if sd[cy * width + cx] > threshold:
				return false
	return true


func _coast(model: MapModel) -> void:
	var n: int = model.width * model.height
	var land := PackedByteArray()
	land.resize(n)
	for i in n:
		land[i] = 1 if model.is_land(i % model.width, int(i / model.width)) else 0
	var to_land: PackedFloat32Array = _distance_to(land, model.width, model.height)
	var to_sea := PackedByteArray()
	to_sea.resize(n)
	for i in n:
		to_sea[i] = 0 if land[i] == 1 else 1
	var to_water: PackedFloat32Array = _distance_to(to_sea, model.width, model.height)
	sd.resize(n)
	for i in n:
		sd[i] = to_water[i] - to_land[i]


## Deepest water within `REACH` tiles: caps the shoal veil so a narrow gulf
## keeps open water down its middle instead of a shore-to-shore wash (#456).
func _reach_field(model: MapModel) -> void:
	var w: int = model.width
	var h: int = model.height
	var depth := PackedFloat32Array()
	depth.resize(w * h)
	for i in w * h:
		depth[i] = maxf(-sd[i], 0.0)
	var rows := PackedFloat32Array()
	rows.resize(w * h)
	for y in h:
		for x in w:
			var best: float = 0.0
			for dx in range(-REACH, REACH + 1):
				best = maxf(best, depth[y * w + clampi(x + dx, 0, w - 1)])
			rows[y * w + x] = best
	reach.resize(w * h)
	for y in h:
		for x in w:
			var best: float = 0.0
			for dy in range(-REACH, REACH + 1):
				best = maxf(best, rows[clampi(y + dy, 0, h - 1) * w + x])
			reach[y * w + x] = best


## Two-pass chamfer distance transform (1 / sqrt2 steps). Accurate enough for a
## coastal band, and linear in the tile count.
static func _distance_to(
	source: PackedByteArray, w: int, h: int
) -> PackedFloat32Array:
	var far: float = float(w + h) * 2.0
	var out := PackedFloat32Array()
	out.resize(w * h)
	for i in w * h:
		out[i] = 0.0 if source[i] == 1 else far
	var diagonal: float = sqrt(2.0)
	for y in h:
		for x in w:
			var i: int = y * w + x
			var best: float = out[i]
			if x > 0:
				best = minf(best, out[i - 1] + 1.0)
			if y > 0:
				best = minf(best, out[i - w] + 1.0)
				if x > 0:
					best = minf(best, out[i - w - 1] + diagonal)
				if x < w - 1:
					best = minf(best, out[i - w + 1] + diagonal)
			out[i] = best
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i: int = y * w + x
			var best: float = out[i]
			if x < w - 1:
				best = minf(best, out[i + 1] + 1.0)
			if y < h - 1:
				best = minf(best, out[i + w] + 1.0)
				if x < w - 1:
					best = minf(best, out[i + w + 1] + diagonal)
				if x > 0:
					best = minf(best, out[i + w - 1] + diagonal)
			out[i] = best
	return out
