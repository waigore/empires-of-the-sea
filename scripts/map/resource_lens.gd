class_name ResourceLens
extends MapLens
## Survey lens: one parchment plaque over every charted province, showing its
## resource estates in a glance (wiki: extraction-and-improvements).
## Pure view — `ResourceSurvey` decides what exists. Plates draw above the fog
## (like painted borders) because they are remembered knowledge, but a resource
## tile that is still unknown is never surveyed.

const EMBLEM: float = 16.0
const EMBLEM_GAP: float = 8.0
const PLATE_PAD: float = 7.0
const RIBBON: float = 5.0
const BADGE_W: float = 28.0
const PLATE_H: float = 44.0
const LABEL_DROP: float = 28.0

var works: LandWorks = null
var units: Array[CivilianState] = []
var capital_tile: Vector2i = CivilianState.NO_TILE
var tech_caps: Dictionary = {}

var _pulse: float = 0.0
var _clock: float = 0.0
## True while any estate is under works; only then does the lens repaint.
var _animating: bool = false


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
	_watch(civilians, &"works_changed", refresh)
	_watch(fog, &"fog_changed", refresh)


## Recomputes the projection. Called on region load, work completion, turn end
## and lens activation — never per frame.
func refresh() -> void:
	if model == null or works == null:
		survey = {}
		_animating = false
		queue_redraw()
		return
	survey = ResourceSurvey.snapshot(
		model, works, units, faction, visibility, capital_tile, tech_caps
	)
	# The chart itself draws no roads, so the lens carries the built network.
	survey["routes"] = ResourceRoutes.snapshot(
		model, works, faction, capital_tile, visibility
	)["segments"]
	_animating = false
	for raw: Variant in survey.get("provinces", []):
		for raw_row: Variant in (raw as Dictionary)["rows"]:
			var status: String = String((raw_row as Dictionary)["status"])
			if status == "building" or status == "foreign_building":
				_animating = true
	_layout_plates()
	queue_redraw()


## The survey lens holds its fade a beat longer than the wash-only readings.
func _reveal_seconds() -> float:
	return 0.26


func _summary_of(entry: Dictionary) -> String:
	return ResourceSurvey.summary_text(entry)


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
	if not _visible():
		return
	if _font == null:
		_font = UiTheme.serif()
	RoadInk.draw_routes(self, survey.get("routes", []), _reveal)
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
	# Ground still to read: a dotted survey ring on the slip's corner, the same
	# ink the key names (DR-20261111-26).
	if int(entry.get("unsurveyed", 0)) > 0:
		var mark: Vector2 = Vector2(rect.end.x - PLATE_PAD - 5.0, rect.end.y - 6.0)
		var survey_ink: Color = Palette.survey_color("survey")
		for i in 6:
			var angle: float = TAU * float(i) / 6.0
			draw_circle(
				mark + Vector2(cos(angle), sin(angle)) * 4.0, 1.0,
				Color(survey_ink.r, survey_ink.g, survey_ink.b, 0.90 * alpha)
			)
	RoadInk.draw_link(
		self, _font, entry["counts"],
		Vector2(rect.position.x + PLATE_PAD + RIBBON, rect.position.y + 37.0),
		rect.size.x - PLATE_PAD * 2.0 - RIBBON, alpha
	)
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
	# Status ink rings the emblem; the commodity ink fills it, so the estate's
	# state reads without painting every kind the same hue (REQ-P1-08).
	var ring: Color = _status_tint(status)
	ring.a *= alpha
	var tint: Color = Palette.emblem_ink(String(row["icon"]), status)
	tint.a *= alpha
	var radius: float = 9.2
	var worked: bool = int(row["level"]) > 0
	if worked:
		draw_circle(center, radius - 0.8, Color(tint.r, tint.g, tint.b, 0.16 * alpha))
	MapGlyphs.resource(self, String(row["icon"]), center, EMBLEM * 0.82, tint)
	match status:
		"disconnected":
			draw_arc(center, radius, 0, TAU, 22, ring, 1.3, true)
			draw_line(center + Vector2(-radius * 0.7, radius * 0.7),
				center + Vector2(radius * 0.7, -radius * 0.7), ring, 1.5, true)
		_:
			draw_arc(center, radius, 0, TAU, 22, ring, 1.6, true)
	if status == "building" or status == "foreign_building":
		var spin: float = _pulse * 2.4
		draw_arc(center, radius + 2.4, spin, spin + 1.5, 10, ring, 1.2, true)
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


# --- layout ------------------------------------------------------------------


## Plates are 32 px tall and the survey steps 24 px, so a free lane often needs
## step ≥ 2; four tries used to leave overlaps on the fixture chart.
func _pack_step() -> float:
	return 24.0


## Slips drop below the province name where the chart prints one, so the label
## is never covered.
func _pack_drop(entry: Dictionary) -> float:
	return LABEL_DROP if bool(entry.get("labelled", false)) else 0.0


func _plate_size(entry: Dictionary) -> Vector2:
	var estates: int = (entry["rows"] as Array).size()
	var count: int = mini(estates, 3)
	var width: float = PLATE_PAD * 2.0 + RIBBON + count * EMBLEM
	width += float(maxi(count - 1, 0)) * EMBLEM_GAP + BADGE_W
	if estates > count:
		width += 18.0
	return Vector2(width, PLATE_H)


func _status_tint(status: String) -> Color:
	match status:
		"foreign", "foreign_worked":
			return Palette.SURVEY_FOREIGN
		"foreign_building":
			return Palette.SURVEY_BUILDING
	return Palette.survey_color(status)
