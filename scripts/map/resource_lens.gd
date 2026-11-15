class_name ResourceLens
extends MapLens
## Survey lens: one parchment plaque over every charted province, showing its
## resource types in a glance (wiki: extraction-and-improvements). Each type
## prints its own emblem and a built / linked / total badge, and ground still to
## prospect carries the Explorer's mark and a count (issue #698).
## Pure view — `ResourceSurvey` decides what exists. Plates draw above the fog
## (like painted borders) because they are remembered knowledge, but a resource
## tile that is still unknown is never surveyed.

const EMBLEM: float = 16.0
const PLATE_PAD: float = 7.0
const RIBBON: float = 5.0
## One type cell: its emblem above its badge, so a slip stays narrow while
## printing every type it holds.
const TYPE_CELL: float = 32.0
const TYPE_GAP: float = 2.0
const BADGE_FONT: int = 9
const ICON_Y: float = 12.0
const BADGE_Y: float = 30.0
const PLATE_H: float = 34.0
## Ground left to survey adds the Explorer line under the badges.
const CUE_Y: float = 42.0
const CUE_SIZE: float = 11.0
const CUE_GAP: float = 5.0
const PLATE_H_CUE: float = 46.0
const LABEL_DROP: float = 28.0

var works: LandWorks = null
var units: Array[CivilianState] = []
var capital_tile: Vector2i = CivilianState.NO_TILE
var tech_caps: Dictionary = {}

var _pulse: float = 0.0
var _clock: float = 0.0
## True while any estate is under works; only then does the lens repaint.
var _animating: bool = false
## State the projection was baked from, so a re-seat of the same save redraws
## nothing (`source_key`).
var _baked_key: int = 0
var _baked: bool = false
## The road strokes, traced and smoothed once per refresh: the lens repaints on
## a work in progress, and re-tracing the network every frame would be wasted
## ink (REQ-P4-01).
var _runs: Array = []


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
		_runs = []
		_baked = false
		_animating = false
		queue_redraw()
		return
	var key: int = hash([
		source_key(works, capital_tile, units),
		hash(tech_caps),
	])
	if _baked and key == _baked_key:
		return
	_baked_key = key
	_baked = true
	survey = ResourceSurvey.snapshot(
		model, works, units, faction, visibility, capital_tile, tech_caps
	)
	# The chart itself draws no roads, so the lens carries the built network.
	survey["routes"] = ResourceRoutes.snapshot(
		model, works, faction, capital_tile, visibility
	)["segments"]
	_runs = RoadInk.ink_paths(survey["routes"])
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
	RoadInk.draw_runs(self, _runs, _reveal)
	var provinces: Array = survey.get("provinces", [])
	for raw: Variant in provinces:
		_draw_plate(raw)


func _draw_plate(entry: Dictionary) -> void:
	var types: Array = entry.get("types", [])
	if types.is_empty():
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

	var left: float = rect.position.x + PLATE_PAD + RIBBON
	for i in types.size():
		_draw_type(
			types[i],
			Vector2(left + float(i) * (TYPE_CELL + TYPE_GAP), rect.position.y),
			alpha
		)
	_draw_prospect(entry, rect, alpha)
	if int(entry["id"]) == hover_province:
		draw_rect(
			Rect2(
				rect.position + Vector2(2, rect.size.y - 4),
				Vector2(rect.size.x - 4, 2)
			),
			Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha)
		)


## One emblem and one badge per resource type: the emblem carries the commodity
## ink and a status ring, the badge prints that type's built / linked / total
## estates, which replaces the old province badge and its `+N` overflow.
func _draw_type(group: Dictionary, origin: Vector2, alpha: float) -> void:
	var status: String = _type_status(group)
	var ring: Color = _status_tint(status)
	ring.a *= alpha
	var tint: Color = Palette.emblem_ink(String(group["icon"]), status)
	tint.a *= alpha
	var center: Vector2 = origin + Vector2(TYPE_CELL * 0.5, ICON_Y)
	var radius: float = 8.4
	if int(group["developed"]) > 0:
		draw_circle(center, radius - 0.8, Color(tint.r, tint.g, tint.b, 0.16 * alpha))
	MapGlyphs.resource(self, String(group["icon"]), center, EMBLEM * 0.82, tint)
	draw_arc(center, radius, 0, TAU, 22, ring, 1.5, true)
	if bool(group["building"]):
		var spin: float = _pulse * 2.4
		draw_arc(center, radius + 2.4, spin, spin + 1.5, 10, ring, 1.1, true)
	draw_string(
		_font, origin + Vector2(0, BADGE_Y),
		"%d/%d/%d" % [
			int(group["developed"]), int(group["linked"]), int(group["estates"])
		],
		HORIZONTAL_ALIGNMENT_CENTER, TYPE_CELL, BADGE_FONT, ring
	)


## Ground still to read: the Explorer's compass and the count of tiles this
## court may still prospect (wiki: fog-and-exploration § Prospecting;
## DR-20261111-26). Nothing prints once the province has been read through.
func _draw_prospect(entry: Dictionary, rect: Rect2, alpha: float) -> void:
	var count: int = int(entry.get("unsurveyed", 0))
	if count <= 0:
		return
	var ink: Color = Palette.survey_color("survey")
	ink.a *= alpha
	var origin := Vector2(rect.position.x + PLATE_PAD + RIBBON, rect.position.y + CUE_Y)
	MapGlyphs.explorer(self, origin + Vector2(CUE_SIZE * 0.5, -3.4), CUE_SIZE, ink)
	draw_string(
		_font, origin + Vector2(CUE_SIZE + CUE_GAP, 0.0), str(count),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - PLATE_PAD * 2.0 - RIBBON - 20.0,
		11, ink
	)


## The type's reading from its own counts: a full type yields, one under works
## or partly built reads building, untouched ground reads vacant, and a type a
## rival holds entire reads foreign.
func _type_status(group: Dictionary) -> String:
	var estates: int = int(group["estates"])
	var developed: int = int(group["developed"])
	if developed <= 0:
		return "foreign" if int(group["foreign"]) >= estates else "vacant"
	if int(group["linked"]) < developed:
		return "disconnected"
	return "producing" if developed >= estates else "building"


# --- layout ------------------------------------------------------------------


## Slips run 34–46 px tall and the survey steps 24 px, so a free lane often needs
## step ≥ 2; four tries used to leave overlaps on the fixture chart.
func _pack_step() -> float:
	return 24.0


## Slips drop below the province name, which every chart now prints, so the
## label is never covered.
func _pack_drop(_entry: Dictionary) -> float:
	return LABEL_DROP


func _plate_size(entry: Dictionary) -> Vector2:
	var types: int = (entry.get("types", []) as Array).size()
	var width: float = PLATE_PAD * 2.0 + RIBBON + float(types) * TYPE_CELL
	width += float(maxi(types - 1, 0)) * TYPE_GAP
	# The Explorer line prints under the badges, so a one-type slip is still as
	# wide as its compass and count.
	width = maxf(width, PLATE_PAD * 2.0 + RIBBON + CUE_SIZE + CUE_GAP + 20.0)
	var height: float = PLATE_H
	if int(entry.get("unsurveyed", 0)) > 0:
		height = PLATE_H_CUE
	return Vector2(width, height)


func _status_tint(status: String) -> Color:
	match status:
		"foreign", "foreign_worked":
			return Palette.SURVEY_FOREIGN
		"foreign_building":
			return Palette.SURVEY_BUILDING
	return Palette.survey_color(status)
