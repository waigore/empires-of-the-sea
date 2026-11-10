class_name ResourceLens
extends Node2D
## Survey lens: one parchment plaque over every charted province, showing its
## resource estates in a glance (wiki: extraction-and-improvements).
## Pure view — `ResourceSurvey` decides what exists. Plates draw above the fog
## (like painted borders) because they are remembered knowledge, but a resource
## tile that is still unknown is never surveyed.

const TILE_SIZE: float = 22.0
const EMBLEM: float = 16.0
const EMBLEM_GAP: float = 8.0
const PLATE_PAD: float = 7.0
const RIBBON: float = 5.0
const BADGE_W: float = 28.0
const PLATE_H: float = 32.0
const LABEL_DROP: float = 28.0

var model: MapModel = null
var works: LandWorks = null
var units: Array[CivilianState] = []
## Owning crown for the survey (Node.owner is taken, so `faction`).
var faction: int = MapModel.NO_ID
var visibility: VisibilityModel = null
var capital_tile: Vector2i = CivilianState.NO_TILE
var tech_caps: Dictionary = {}
var active: bool = false
var hover_province: int = -1
## Latest `ResourceSurvey.snapshot`; empty until built.
var survey: Dictionary = {}

var _font: Font = null
var _pulse: float = 0.0
var _reveal: float = 0.0
var _clock: float = 0.0
## True while any estate is under works; only then does the lens repaint.
var _animating: bool = false
## Laid-out plaque rects by province id, packed on refresh so plates never
## overlap each other in dense theatres.
var _rects: Dictionary = {}


func _ready() -> void:
	_font = UiTheme.serif()


func build(
	p_model: MapModel,
	p_works: LandWorks,
	p_units: Array[CivilianState],
	p_owner: int,
	p_visibility: VisibilityModel,
	p_capital_tile: Vector2i,
	p_tech_caps: Dictionary = {}
) -> void:
	model = p_model
	works = p_works
	units = p_units
	faction = p_owner
	visibility = p_visibility
	capital_tile = p_capital_tile
	tech_caps = p_tech_caps
	refresh()


## Source nodes whose changes invalidate the projection. Kept as a narrow
## subscription so the lens never polls the map (REQ-P4-01).
func watch(civilians: CivilianLayer, fog: MapOverlay) -> void:
	if civilians != null and not civilians.works_changed.is_connected(refresh):
		civilians.works_changed.connect(refresh)
	if fog != null and not fog.fog_changed.is_connected(refresh):
		fog.fog_changed.connect(refresh)


## Recomputes the projection. Called on region load, work completion, turn end
## and lens activation — never per frame.
func refresh() -> void:
	if model == null or works == null:
		survey = {}
		queue_redraw()
		return
	survey = ResourceSurvey.snapshot(
		model, works, units, faction, visibility, capital_tile, tech_caps
	)
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
		tween.tween_method(_set_reveal, 0.0, 1.0, 0.26).set_trans(Tween.TRANS_CUBIC)
	queue_redraw()


func toggle() -> void:
	set_active(not active)


## Province whose plaque covers a world point (-1 when none). Plates can be
## packed away from their centre, so taps must resolve through the slip.
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
			return ResourceSurvey.summary_text(entry)
	return ""


func _set_reveal(value: float) -> void:
	_reveal = value
	queue_redraw()


func _process(delta: float) -> void:
	if not active or not _animating:
		return
	_pulse += delta
	_clock += delta
	# Only a work in progress needs motion; a settled survey repaints on change.
	if _clock >= 0.1:
		_clock = 0.0
		queue_redraw()


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if not active or survey.is_empty() or _reveal <= 0.001:
		return
	if _font == null:
		_font = UiTheme.serif()
	var provinces: Array = survey.get("provinces", [])
	for raw: Variant in provinces:
		_draw_plate(raw)


func _draw_plate(entry: Dictionary) -> void:
	var rows: Array = entry["rows"]
	if rows.is_empty():
		return
	var rect: Rect2 = _plate_rect(entry)
	var alpha: float = _reveal * _charted_alpha(int(entry["charted"]))
	if alpha <= 0.01:
		return
	var shape: PackedVector2Array = _plate_shape(rect, 3.0)
	var shadow := _offset_shape(shape, Vector2(1.4, 2.2))
	draw_colored_polygon(shadow, Color(0.10, 0.08, 0.05, 0.32 * alpha))
	draw_colored_polygon(shape, Color(0.945, 0.902, 0.792, 0.99 * alpha))
	draw_polyline(
		_closed(shape), Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.90 * alpha),
		1.5, true
	)
	# A second engraved rule inside the edge: printed slip, not plastic tile.
	draw_polyline(
		_closed(_plate_shape(rect.grow(-2.0), 2.0)),
		Color(0.420, 0.337, 0.216, 0.30 * alpha), 0.8, true
	)

	var owner_id: int = int(entry["owner"])
	var ribbon: Color = _owner_tint(owner_id)
	ribbon.a *= alpha
	draw_rect(
		Rect2(rect.position + Vector2(2, 4), Vector2(2.4, rect.size.y - 8)), ribbon
	)

	var row_count: int = mini(rows.size(), 3)
	var extra: int = rows.size() - row_count
	var left: float = rect.position.x + PLATE_PAD + RIBBON
	for i in row_count:
		var row: Dictionary = rows[i]
		var center := Vector2(
			left + i * (EMBLEM + EMBLEM_GAP) + EMBLEM * 0.5,
			rect.position.y + 12.5
		)
		_draw_emblem(row, center, alpha)
	if extra > 0:
		draw_string(
			_font,
			Vector2(left + row_count * (EMBLEM + EMBLEM_GAP), rect.position.y + 17.0),
			"+%d" % extra, HORIZONTAL_ALIGNMENT_CENTER, 18.0, 11,
			Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.62 * alpha)
		)
	_draw_meter(entry, rect, alpha)
	_draw_badge(entry, rect, alpha)
	if int(entry["id"]) == hover_province:
		draw_rect(
			Rect2(
				rect.position + Vector2(2, rect.size.y - 4),
				Vector2(rect.size.x - 4, 2)
			),
			Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha)
		)


func _draw_emblem(row: Dictionary, center: Vector2, alpha: float) -> void:
	var status: String = String(row["status"])
	var tint: Color = _status_tint(status)
	tint.a *= alpha
	var radius: float = 9.2
	var worked: bool = int(row["level"]) > 0
	if worked:
		draw_circle(center, radius - 0.8, Color(tint.r, tint.g, tint.b, 0.16 * alpha))
	MapGlyphs.resource(self, String(row["icon"]), center, EMBLEM * 0.82, tint)
	match status:
		"unprospected":
			_dotted_ring(center, radius, tint)
		"disconnected":
			draw_arc(center, radius, 0, TAU, 22, tint, 1.3, true)
			draw_line(center + Vector2(-radius * 0.7, radius * 0.7),
				center + Vector2(radius * 0.7, -radius * 0.7), tint, 1.5, true)
		_:
			draw_arc(center, radius, 0, TAU, 22, tint, 1.6, true)
	if status == "building" or status == "foreign_building":
		var spin: float = _pulse * 2.4
		draw_arc(center, radius + 2.4, spin, spin + 1.5, 10, tint, 1.2, true)
	# One gold pip per completed level, so a worked estate reads at a glance.
	var level: int = mini(int(row["level"]), ImprovementCatalog.MAX_LEVEL)
	for i in level:
		var pip := Rect2(
			center + Vector2(-7.0 + i * 4.2, radius - 1.2), Vector2(2.6, 2.6)
		)
		draw_rect(pip, Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha))


func _draw_meter(entry: Dictionary, rect: Rect2, alpha: float) -> void:
	var counts: Dictionary = entry["counts"]
	var total: int = int(counts["estates"])
	if total <= 0:
		return
	var span: float = rect.size.x - PLATE_PAD * 2.0 - RIBBON
	var start := Vector2(rect.position.x + PLATE_PAD + RIBBON, rect.position.y + 24.0)
	var track := Rect2(start, Vector2(span, 3.0))
	draw_rect(track, Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.20 * alpha))
	var worked: int = int(counts["worked"])
	if worked <= 0:
		return
	var fill: Color = Palette.SURVEY_YIELDING if worked >= total else Palette.SURVEY_BUILDING
	fill.a *= alpha
	draw_rect(
		Rect2(start, Vector2(span * float(worked) / float(total), 3.0)), fill
	)


func _draw_badge(entry: Dictionary, rect: Rect2, alpha: float) -> void:
	var counts: Dictionary = entry["counts"]
	var total: int = int(counts["estates"])
	var worked: int = int(counts["worked"])
	var tint: Color = Palette.SURVEY_VACANT
	if worked >= total:
		tint = Palette.SURVEY_YIELDING
	elif worked > 0:
		tint = Palette.SURVEY_BUILDING
	tint.a *= alpha
	draw_string(
		_font,
		Vector2(rect.end.x - PLATE_PAD - BADGE_W, rect.position.y + 20.0),
		"%d/%d" % [worked, total],
		HORIZONTAL_ALIGNMENT_CENTER, BADGE_W, 15, tint
	)


func _dotted_ring(center: Vector2, radius: float, tint: Color) -> void:
	for i in 8:
		var angle: float = TAU * float(i) / 8.0
		var spot: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		draw_circle(spot, 1.5, tint)


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


## Greedy pack: try the slip below the name, then further down, so dense
## theatres never stack one province's survey over another's. Keep walking
## (plates are 32 px tall and steps are 24 px, so a free lane often needs
## step ≥ 2); four tries used to leave overlaps on the fixture chart.
func _layout_plates() -> void:
	_rects.clear()
	_animating = false
	var placed: Array[Rect2] = []
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		for raw_row: Variant in entry["rows"]:
			var status: String = String((raw_row as Dictionary)["status"])
			if status == "building" or status == "foreign_building":
				_animating = true
		var size: Vector2 = _plate_size(entry)
		var center: Vector2 = Vector2(entry["anchor"]) * TILE_SIZE
		var drop: float = LABEL_DROP if bool(entry.get("labelled", false)) else 0.0
		var chosen := Rect2(center + Vector2(-size.x * 0.5, drop), size)
		for step in 32:
			var candidate := Rect2(
				center + Vector2(-size.x * 0.5, drop + float(step) * 24.0), size
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


func _plate_size(entry: Dictionary) -> Vector2:
	var estates: int = (entry["rows"] as Array).size()
	var count: int = mini(estates, 3)
	var width: float = PLATE_PAD * 2.0 + RIBBON + count * EMBLEM
	width += float(maxi(count - 1, 0)) * EMBLEM_GAP + BADGE_W
	if estates > count:
		width += 18.0
	return Vector2(width, PLATE_H)


func _plate_rect(entry: Dictionary) -> Rect2:
	var id: int = int(entry["id"])
	if _rects.has(id):
		return _rects[id]
	return Rect2(Vector2.ZERO, _plate_size(entry))


func _status_tint(status: String) -> Color:
	match status:
		"foreign", "foreign_worked":
			return Palette.SURVEY_FOREIGN
		"foreign_building":
			return Palette.SURVEY_BUILDING
	return Palette.survey_color(status)


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
