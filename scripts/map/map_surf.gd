class_name MapSurf
extends Node2D
## Breaking surf. The canvas inks the shore once; this layer only animates the
## foam, so the coastline stays a crisp drawn line while the water keeps moving
## (REQ-P1-04). Dashes are sampled along the smoothed coast paths and
## phase-offset, so the break is never one pulsing ring.

const SPACING: float = 26.0
const MAX_DASHES: int = 340
const SPEED: float = 1.8

var _dashes: Array[Dictionary] = []
var _time: float = 0.0


func setup(model: MapModel, coast: Array[PackedVector2Array], tile_size: float) -> void:
	_dashes.clear()
	for path: PackedVector2Array in coast:
		_collect(model, path, tile_size)
		if _dashes.size() >= MAX_DASHES:
			break
	_time = 0.0
	queue_redraw()


func dash_count() -> int:
	return _dashes.size()


func _collect(model: MapModel, path: PackedVector2Array, tile_size: float) -> void:
	if path.size() < 2:
		return
	var carry: float = SPACING * 0.5
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		carry += a.distance_to(b)
		if carry < SPACING:
			continue
		carry = 0.0
		var normal: Vector2 = _sea_normal(model, a, b, tile_size)
		if normal == Vector2.ZERO:
			continue
		_dashes.append({
			"position": b,
			"normal": normal,
			"tangent": (b - a).normalized(),
			"phase": _hash01(int(b.x), int(b.y)) * TAU,
			"width": 9.0 + _hash01(int(b.y), int(b.x)) * 10.0,
		})
		if _dashes.size() >= MAX_DASHES:
			return


## The coast is traced with either winding, so probe both sides for open water.
static func _sea_normal(model: MapModel, a: Vector2, b: Vector2, tile_size: float) -> Vector2:
	var delta: Vector2 = b - a
	if delta.length_squared() < 0.0001:
		return Vector2.ZERO
	var direction: Vector2 = delta.normalized()
	var normal := Vector2(-direction.y, direction.x)
	var probe: Vector2 = normal * tile_size * 0.7
	var tile: Vector2i = model.tile_at_world(b + probe, tile_size)
	if model.is_sea(tile.x, tile.y):
		return normal
	tile = model.tile_at_world(b - probe, tile_size)
	if model.is_sea(tile.x, tile.y):
		return -normal
	return Vector2.ZERO


func _process(delta: float) -> void:
	if _dashes.is_empty():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	for dash: Dictionary in _dashes:
		var wave: float = sin(_time * SPEED + float(dash["phase"])) * 0.5 + 0.5
		if wave < 0.16:
			continue
		var normal: Vector2 = dash["normal"]
		var tangent: Vector2 = dash["tangent"]
		var reach: float = 2.5 + wave * 7.5
		var half: float = float(dash["width"]) * (0.42 + wave * 0.58)
		var origin: Vector2 = dash["position"] + normal * reach
		draw_line(
			origin - tangent * half,
			origin + tangent * half,
			Color(0.992, 0.973, 0.914, 0.06 + wave * 0.42),
			1.0 + wave * 1.6,
			true
		)


func _hash01(x: int, y: int) -> float:
	var h: int = x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
