class_name MapLens
extends Node2D
## Shared chart-lens kit: raising a reading, the fade, tap resolution and the
## printed-slip layout every reading uses. A lens is a pure view over one
## `*Survey` snapshot — the projection decides the reading, this base only opens
## it, animates it and resolves a tap to a province (REQ-P3-03).

const TILE_SIZE: float = 22.0
## A reading fades in over the chart; the survey lens holds a beat longer.
const REVEAL_SECONDS: float = 0.24
## Candidate-slot step while a slip looks for a free lane.
const PACK_STEP: float = 22.0

var model: MapModel = null
## Fog reading: what the crown is allowed to remember.
var visibility: VisibilityModel = null
## Owning crown for the reading (Node.owner is taken, so `faction`).
var faction: int = MapModel.NO_ID
var active: bool = false
var hover_province: int = -1
## Latest survey snapshot; empty until built.
var survey: Dictionary = {}

var _font: Font = null
var _reveal: float = 0.0
## Laid-out slip rects by province id, packed so no two slips stack.
var _rects: Dictionary = {}


func _ready() -> void:
	_font = UiTheme.serif()


## Raises or lowers the reading: a raise rebuilds the projection and fades it
## in, a lower just stops painting.
func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if active:
		refresh()
		_reveal = 0.0
		var tween: Tween = create_tween()
		tween.tween_method(_set_reveal, 0.0, 1.0, _reveal_seconds()).set_trans(
			Tween.TRANS_CUBIC
		)
	queue_redraw()


func toggle() -> void:
	set_active(not active)


## Recomputes the projection. Each reading overrides this; called on region
## load, source changes and activation — never per frame.
func refresh() -> void:
	survey = {}
	queue_redraw()


## Province whose slip covers a world point (-1 when none). Slips can be packed
## away from their anchor, so taps must resolve through the printed rect.
func hit_test(world_position: Vector2) -> int:
	for raw: Variant in survey.get("provinces", []):
		var id: int = int((raw as Dictionary)["id"])
		if _rects.has(id) and (_rects[id] as Rect2).has_point(world_position):
			return id
	return -1


## The one hover line a province shows; each reading names its own text.
func summary_for(province_id: int) -> String:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return _summary_of(entry)
	return ""


## Subscribes a source node's change signal once, so a mounted lens never polls
## the chart for state it can be told about (REQ-P4-01).
func _watch(source: Object, change: StringName, action: Callable) -> void:
	if source == null or not source.has_signal(change):
		return
	if source.is_connected(change, action):
		return
	source.connect(change, action)


## Whether the reading should paint: raised, built and past the opening frame of
## its fade.
func _visible() -> bool:
	return active and not survey.is_empty() and _reveal > 0.001


func _set_reveal(value: float) -> void:
	_reveal = value
	queue_redraw()


func _reveal_seconds() -> float:
	return REVEAL_SECONDS


func _summary_of(entry: Dictionary) -> String:
	return String(entry.get("summary", ""))


# --- slip kit ----------------------------------------------------------------


## Greedy pack: try the slip on the province's anchor, then step down until it
## clears every slip already placed, so dense theatres never stack two readings.
func _layout_plates() -> void:
	_rects.clear()
	var placed: Array[Rect2] = []
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		var size: Vector2 = _plate_size(entry)
		var center: Vector2 = _plate_anchor(entry)
		var drop: float = _pack_drop(entry)
		var chosen := Rect2(center + Vector2(-size.x * 0.5, drop), size)
		for step in 32:
			var candidate := Rect2(
				center + Vector2(-size.x * 0.5, drop + float(step) * _pack_step()), size
			)
			var free: bool = true
			for other: Rect2 in placed:
				if other.intersects(candidate.grow(4.0)):
					free = false
					break
			if free:
				chosen = candidate
				break
		_rects[int(entry["id"])] = chosen
		placed.append(chosen)


func _plate_anchor(entry: Dictionary) -> Vector2:
	return Vector2(entry["anchor"]) * TILE_SIZE


func _pack_step() -> float:
	return PACK_STEP


func _pack_drop(_entry: Dictionary) -> float:
	return 0.0


## A slip's footprint; each reading sizes it from its own rows.
func _plate_size(_entry: Dictionary) -> Vector2:
	return Vector2.ZERO


func _plate_rect(entry: Dictionary) -> Rect2:
	var id: int = int(entry["id"])
	if _rects.has(id):
		return _rects[id]
	return Rect2(Vector2.ZERO, _plate_size(entry))


## A paper slip with clipped corners: period-appropriate and cheap to draw.
func _plate_shape(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	return PackedVector2Array([
		Vector2(p.x + chamfer, p.y),
		Vector2(e.x - chamfer, p.y),
		Vector2(e.x, p.y + chamfer),
		Vector2(e.x, e.y - chamfer),
		Vector2(e.x - chamfer, e.y),
		Vector2(p.x + chamfer, e.y),
		Vector2(p.x, e.y - chamfer),
		Vector2(p.x, p.y + chamfer),
	])


func _offset_shape(shape: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point: Vector2 in shape:
		moved.append(point + offset)
	return moved


func _closed(shape: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = shape.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _owner_tint(owner_id: int) -> Color:
	if owner_id < 0 or not FactionCatalog.has_faction(owner_id):
		return Color(0.52, 0.47, 0.39)
	return Palette.faction_color(owner_id)


func _charted_alpha(charted: int) -> float:
	if charted == VisibilityModel.Level.FULLY_VISIBLE:
		return 1.0
	if charted == VisibilityModel.Level.FOGGED:
		return 0.88
	return 0.0
