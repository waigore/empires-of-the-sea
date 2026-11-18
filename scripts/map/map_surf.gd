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


func setup(
	model: MapModel,
	coast: Array[PackedVector2Array],
	tile_size: float,
	room: Array[PackedByteArray] = []
) -> void:
	_dashes.clear()
	for index in coast.size():
		var open: PackedByteArray = room[index] if index < room.size() else PackedByteArray()
		_collect(model, coast[index], tile_size, open)
		if _dashes.size() >= MAX_DASHES:
			break
	_time = 0.0
	queue_redraw()


func dash_count() -> int:
	return _dashes.size()


func _collect(
	model: MapModel, path: PackedVector2Array, tile_size: float, open: PackedByteArray
) -> void:
	if path.size() < 2:
		return
	var carry: float = SPACING * 0.5
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		carry += a.distance_to(b)
		# Spacing breathes with the shore: an even cadence reads as a printed
		# border, not as water (issue #1007).
		var beat: float = SPACING * (0.62 + MapGlyphs.hash01(int(b.x) + 7, int(b.y) + 3) * 0.76)
		if carry < beat:
			continue
		carry = 0.0
		# A narrow bank keeps no surf: two rows of breakers would meet in the
		# middle and print the channel as a pale band of ground (#456).
		if i + 1 < open.size() and open[i + 1] == 0:
			continue
		var normal: Vector2 = _sea_normal(model, a, b, tile_size)
		if normal == Vector2.ZERO:
			continue
		var seed: float = MapGlyphs.hash01(int(b.y), int(b.x))
		var tangent: Vector2 = (b - a).normalized()
		# Slide each crest along the shore by up to a third of a beat, so two
		# breakers never line up into one scalloped arc.
		var slide: float = (MapGlyphs.hash01(int(b.x) + 19, int(b.y) + 41) - 0.5) * SPACING * 0.6
		_dashes.append({
			"position": b + tangent * slide,
			"normal": normal,
			"tangent": tangent,
			"phase": seed * TAU,
			"width": 7.0 + seed * 13.0,
			"arc": 0.85 + MapGlyphs.hash01(int(b.x) + 3, int(b.y) + 11) * 0.75,
			"lean": (MapGlyphs.hash01(int(b.x) + 23, int(b.y) + 5) - 0.5) * 0.5,
			"foam": 0.55 + seed * 0.45,
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
	var tile: Vector2i = MapGeo.tile_at_world(b + probe, tile_size)
	if model.is_sea(tile.x, tile.y):
		return normal
	tile = MapGeo.tile_at_world(b - probe, tile_size)
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
		var colour := Color(0.992, 0.973, 0.914, (0.06 + wave * 0.42) * float(dash["foam"]))
		# A breaker is a crescent crest, not a dash: the foam bows out toward
		# open water and thins at both tips, with a second fainter crest
		# beneath it, so the shore reads as waves rolling in.
		var across: float = atan2(normal.y, normal.x) + float(dash["lean"])
		var span: float = float(dash["arc"])
		var centre: Vector2 = origin - normal * half * 0.55
		draw_arc(centre, half, across - span, across + span, 10, colour, 1.0 + wave * 1.6, true)
		draw_arc(
			centre + normal * half * 0.30,
			half * 0.72,
			across - span * 0.72,
			across + span * 0.72,
			8,
			Color(0.992, 0.973, 0.914, (0.03 + wave * 0.20) * float(dash["foam"])),
			0.8 + wave * 0.9,
			true
		)
		# A short foam tail trails behind the crest, along the shore.
		draw_line(
			origin - tangent * half * 0.30,
			origin - tangent * half * 0.05,
			Color(0.992, 0.973, 0.914, 0.04 + wave * 0.16),
			0.8,
			true
		)
