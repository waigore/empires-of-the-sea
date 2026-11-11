class_name DefenceLens
extends Node2D
## Military lens: one parchment slip over every charted province, showing what
## would meet an attack — the owner's published order of battle, the wall and
## the hospital (wiki: combat § Strength, siege-mechanics, hospital_rules).
## Pure view — `DefenceSurvey` decides every number and band (REQ-P3-03).
## Slips draw above the fog because a charted province is remembered knowledge;
## ground the crown has not charted was dropped by the projection.

const TILE_SIZE: float = 22.0
const PLATE_W: float = 96.0
## A slip with a headcount and a wall needs a second line; open ground does not.
const PLATE_H: float = 40.0
const PLATE_H_OPEN: float = 26.0
const PLATE_PAD: float = 6.0
const RIBBON: float = 2.4

var model: MapModel = null
## Region roster the reading is derived from; null in a hand-built test.
var roster: ArmyLayer = null
var armies: Array[ArmyState] = []
var visibility: VisibilityModel = null
## Owning crown for the reading (Node.owner is taken, so `faction`).
var faction: int = MapModel.NO_ID
var active: bool = false
var hover_province: int = -1
## Latest `DefenceSurvey.snapshot`; empty until built.
var survey: Dictionary = {}

var _font: Font = null
var _reveal: float = 0.0
## Laid-out slip rects by province id, packed on refresh so slips never overlap
## each other in dense theatres.
var _rects: Dictionary = {}


func _ready() -> void:
	_font = UiTheme.serif()


## Rebuilds the projection. Called on region load, turn end, lens activation and
## after a march — never per frame.
func build(
	p_model: MapModel,
	p_roster: ArmyLayer,
	p_visibility: VisibilityModel,
	p_faction: int
) -> void:
	model = p_model
	roster = p_roster
	visibility = p_visibility
	faction = p_faction
	refresh()


## Fog changes move what the crown may read, and a march moves a garrison; the
## lens repaints on those events only (REQ-P4-01).
func watch(fog: MapOverlay) -> void:
	if fog != null and not fog.fog_changed.is_connected(refresh):
		fog.fog_changed.connect(refresh)
	if roster != null and not roster.army_moved.is_connected(_on_army_moved):
		roster.army_moved.connect(_on_army_moved)


func _on_army_moved(_army: ArmyState, _result: Dictionary) -> void:
	refresh()


func refresh() -> void:
	if model == null:
		survey = {}
		queue_redraw()
		return
	armies = []
	if roster != null:
		armies.assign(roster.regions.value(model.region_id, []))
	survey = DefenceSurvey.snapshot(model, armies, visibility, faction)
	_layout_plates()
	queue_redraw()


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if active:
		refresh()
		_reveal = 0.0
		var tween: Tween = create_tween()
		tween.tween_method(_set_reveal, 0.0, 1.0, 0.24).set_trans(Tween.TRANS_CUBIC)
	queue_redraw()


func toggle() -> void:
	set_active(not active)


## Province whose slip covers a world point (-1 when none). Slips can be packed
## away from their centre, so taps must resolve through the slip.
func hit_test(world_position: Vector2) -> int:
	for raw: Variant in survey.get("provinces", []):
		var id: int = int((raw as Dictionary)["id"])
		if _rects.has(id) and (_rects[id] as Rect2).has_point(world_position):
			return id
	return -1


func summary_for(province_id: int) -> String:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return String(entry.get("summary", ""))
	return ""


func _set_reveal(value: float) -> void:
	_reveal = value
	queue_redraw()


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if not active or survey.is_empty() or _reveal <= 0.001:
		return
	if _font == null:
		_font = UiTheme.serif()
	for raw: Variant in survey.get("provinces", []):
		_draw_plate(raw)


func _draw_plate(entry: Dictionary) -> void:
	var rect: Rect2 = _plate_rect(entry)
	var alpha: float = _reveal * _charted_alpha(int(entry["charted"]))
	if alpha <= 0.01:
		return
	var shape: PackedVector2Array = _plate_shape(rect, 3.0)
	draw_colored_polygon(
		_offset_shape(shape, Vector2(1.4, 2.2)), Color(0.10, 0.08, 0.05, 0.32 * alpha)
	)
	draw_colored_polygon(shape, Color(0.945, 0.902, 0.792, 0.99 * alpha))
	draw_polyline(
		_closed(shape), Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.90 * alpha),
		1.4, true
	)
	var ribbon: Color = _owner_tint(int(entry["owner"]))
	ribbon.a *= alpha
	draw_rect(Rect2(rect.position + Vector2(2, 4), Vector2(RIBBON, rect.size.y - 8)), ribbon)

	var band: String = String(entry["band"])
	var tint: Color = Palette.defence_color(band)
	_draw_shield(Vector2(rect.position.x + 16.0, rect.position.y + 14.0), tint, alpha)
	var strength: int = int(entry["strength"])
	var number: String = "—" if strength <= 0 else str(strength)
	draw_string(
		_font, Vector2(rect.position.x + 30.0, rect.position.y + 20.0), number,
		HORIZONTAL_ALIGNMENT_LEFT, 30.0, 16, Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, alpha)
	)
	_draw_marks(entry, rect, tint, alpha)
	if int(entry["id"]) == hover_province:
		draw_rect(
			Rect2(rect.position + Vector2(2, rect.size.y - 4), Vector2(rect.size.x - 4, 2)),
			Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha)
		)


## A heraldic shield, filled in the band's ink: open rust, held ochre, walled
## slate, citadel indigo. The same shape keys the legend.
func _draw_shield(center: Vector2, tint: Color, alpha: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-6.0, -7.0),
		center + Vector2(6.0, -7.0),
		center + Vector2(6.0, 1.0),
		center + Vector2(0.0, 8.0),
		center + Vector2(-6.0, 1.0),
	])
	var fill := Color(tint.r, tint.g, tint.b, 0.90 * alpha)
	draw_colored_polygon(points, fill)
	draw_polyline(
		_closed(points), Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55 * alpha),
		1.0, true
	)


## Second line: the garrison's headcount and the wall, then a cross when the
## province keeps a hospital. An open province needs no words — the dash and the
## rust shield already say it — so the reading stays quiet on a calm map.
func _draw_marks(entry: Dictionary, rect: Rect2, tint: Color, alpha: float) -> void:
	var regiments: int = int(entry["regiments"])
	var fort: int = int(entry["fort"])
	var line: String = ""
	if regiments > 0:
		line = "%d reg" % regiments
		if fort > 0:
			line += " · Fort %d" % fort
	elif fort > 0:
		line = "No garrison · Fort %d" % fort
	if not line.is_empty():
		var dim := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.72 * alpha)
		draw_string(
			_font, Vector2(rect.position.x + 30.0, rect.position.y + 34.0), line,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 46.0, 10, dim
		)
	# One gold pip per standing gun, so a wall reads without the words.
	for i in int(entry["guns"]):
		draw_rect(
			Rect2(
				Vector2(rect.end.x - 8.0 - float(i) * 5.0, rect.position.y + 10.0),
				Vector2(3.2, 6.0)
			),
			Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha)
		)
	if int(entry["hospital"]) > 0:
		var spot := Vector2(rect.end.x - 10.0, rect.position.y + 26.0)
		var cross: Color = Color(tint.r, tint.g, tint.b, alpha)
		draw_line(spot + Vector2(-3.5, 0), spot + Vector2(3.5, 0), cross, 1.6, true)
		draw_line(spot + Vector2(0, -3.5), spot + Vector2(0, 3.5), cross, 1.6, true)


# --- layout ------------------------------------------------------------------


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


## Greedy pack: try the slip on the province's anchor, then step down until it
## clears every slip already placed, so dense theatres never stack two readings.
func _layout_plates() -> void:
	_rects.clear()
	var placed: Array[Rect2] = []
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		var size: Vector2 = _plate_size(entry)
		var center: Vector2 = Vector2(entry["anchor"]) * TILE_SIZE
		var chosen := Rect2(center + Vector2(-size.x * 0.5, 0.0), size)
		for step in 32:
			var candidate := Rect2(
				center + Vector2(-size.x * 0.5, float(step) * 22.0), size
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


## A held or walled province carries a second line, so its slip is taller.
func _plate_size(entry: Dictionary) -> Vector2:
	var tall: bool = int(entry["regiments"]) > 0 or int(entry["fort"]) > 0
	return Vector2(PLATE_W, PLATE_H if tall else PLATE_H_OPEN)


func _plate_rect(entry: Dictionary) -> Rect2:
	var id: int = int(entry["id"])
	if _rects.has(id):
		return _rects[id]
	return Rect2(Vector2.ZERO, _plate_size(entry))


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
