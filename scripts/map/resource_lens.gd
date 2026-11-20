class_name ResourceLens
extends MapLens
## Survey lens: one parchment plaque over every charted province, showing its
## resource estates in a glance (wiki: extraction-and-improvements).
## Pure view — `ResourceSurvey` decides what exists. Plates draw above the fog
## (like painted borders) because they are remembered knowledge, but a resource
## tile that is still unknown is never surveyed.

const EMBLEM: float = 16.0
## One column per resource type: its emblem over its badge, so a province's
## reading never depends on how many tiles it happens to hold.
const TYPE_COL: float = 34.0
## The Explorer cue's own column, when the province still has ground to read.
const CUE_W: float = 26.0
const PLATE_PAD: float = 7.0
const RIBBON: float = 5.0
const PLATE_H: float = 44.0
const LABEL_DROP: float = 28.0

var works: LandWorks = null
var units: Array[CivilianState] = []
var capital_tile: Vector2i = CivilianState.NO_TILE
var tech_caps: Dictionary = {}
## The crown's sealed coasts this turn, so a blockaded colony's estates read cut
## until the war lifts (wiki: capital-and-connectivity § Blockade).
var blockade: Blockades = null
## The court's own picks, one per idle crew (`MapPlayCivilianPick`): the chart
## marks the ground the pass would send each crew to. Read on a refresh only
## while the reading is up, so a closed lens never runs a plan pass
## (DR-20261117-07, `REQ-P4-01`).
var pick_source: Callable = Callable()
## The baked picks, one per idle crew: the ground the chart marks.
var picks: Dictionary = {}
## The baked marks, in world space: one per tile a pick names, with the step a
## march takes. Rebuilt on `refresh`, never per frame (`REQ-P4-01`).
var marks: Array[Dictionary] = []

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
	p_tech_caps: Dictionary = {},
	p_blockade: Blockades = null
) -> void:
	model = p_model
	works = p_works
	units = p_units
	faction = p_owner
	visibility = p_visibility
	capital_tile = p_capital_tile
	tech_caps = p_tech_caps
	blockade = p_blockade
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
		marks = []
		_baked = false
		_animating = false
		queue_redraw()
		return
	# The pick is read only while the reading is up: a closed lens costs no plan
	# pass, and a raised one always marks the court's current reading.
	if pick_source.is_valid():
		picks = pick_source.call() if active else {}
	var key: int = hash([
		source_key(works, capital_tile, units),
		hash(tech_caps),
		_seal_key(),
		hash(picks),
	])
	if _baked and key == _baked_key:
		return
	_baked_key = key
	_baked = true
	survey = ResourceSurvey.snapshot(
		model, works, units, faction, visibility, capital_tile, tech_caps, blockade
	)
	# The chart itself draws no roads, so the lens carries the built network.
	survey["routes"] = ResourceRoutes.snapshot(
		model, works, faction, capital_tile, visibility, blockade
	)["segments"]
	_runs = RoadInk.ink_paths(survey["routes"])
	# The court's own picks, marked on the ground they name; a crew at work or an
	# uncharted tile drops out here, so the mark can never outlive its reading.
	marks = CivicGlyphs.marks(picks, units, model, visibility)
	_animating = false
	for raw: Variant in survey.get("provinces", []):
		for raw_row: Variant in (raw as Dictionary)["rows"]:
			var status: String = String((raw_row as Dictionary)["status"])
			if status == "building" or status == "foreign_building":
				_animating = true
	_layout_plates()
	queue_redraw()


## The seals the projection was read under: a war that opens or lifts on a coast
## moves the reading without moving a single work, so the key carries it
## (wiki: capital-and-connectivity § Blockade).
func _seal_key() -> int:
	if blockade == null:
		return 0
	return hash([blockade.sealed, blockade.sea_cut])


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
	_ensure_font()
	RoadInk.draw_runs(self, _runs, _reveal)
	CivicGlyphs.draw_marks(
		self, marks, _reveal, Palette.ink(0.62), Palette.GOLD
	)
	var provinces: Array = survey.get("provinces", [])
	for raw: Variant in provinces:
		_draw_plate(raw)


## The reading paints while there is a plate or a pick to ink: a theatre whose
## provinces hold no charted estate still carries the crown's own picks.
func _visible() -> bool:
	if not active or _reveal <= 0.001:
		return false
	return not survey.is_empty() or not marks.is_empty()


func _draw_plate(entry: Dictionary) -> void:
	var types: Array = entry.get("types", [])
	if types.is_empty():
		return
	var rect: Rect2 = _plate_rect(entry)
	var alpha: float = _reveal * _charted_alpha(int(entry["charted"]))
	if alpha <= 0.01:
		return
	LensSlip.draw_plaque(self, rect, alpha, _owner_tint(int(entry["owner"])))

	# One column a type: the emblem, then the badge that counts its estates.
	var left: float = rect.position.x + PLATE_PAD + RIBBON
	var top: float = rect.position.y + 4.0
	for i in types.size():
		_draw_type(types[i], Rect2(left + float(i) * TYPE_COL, top, TYPE_COL, 38.0), alpha)
	_draw_prospect_cue(entry, rect, alpha)
	if int(entry["id"]) == hover_province:
		LensSlip.hover_rule(self, rect, alpha)


## One type's column: the emblem ringed in the state its estates stand in, and
## under it `built/linked/held`. The emblem's fill stays the commodity ink, so
## the kind reads without repainting it (REQ-P1-08).
func _draw_type(row: Dictionary, column: Rect2, alpha: float) -> void:
	var status: String = String(row["status"])
	var center := Vector2(column.position.x + column.size.x * 0.5, column.position.y + 8.5)
	var ring: Color = _status_tint(status)
	ring.a *= alpha
	var tint: Color = Palette.emblem_ink(String(row["icon"]), status)
	tint.a *= alpha
	var radius: float = 9.2
	if int(row["developed"]) > 0:
		draw_circle(center, radius - 0.8, Color(tint.r, tint.g, tint.b, 0.16 * alpha))
	MapMarks.resource(self, String(row["icon"]), center, EMBLEM * 0.82, tint)
	match status:
		"disconnected":
			draw_arc(center, radius, 0, TAU, 22, ring, 1.3, true)
			draw_line(center + Vector2(-radius * 0.7, radius * 0.7),
				center + Vector2(radius * 0.7, -radius * 0.7), ring, 1.5, true)
		_:
			draw_arc(center, radius, 0, TAU, 22, ring, 1.6, true)
	if status == "building":
		var spin: float = _pulse * 2.4
		draw_arc(center, radius + 2.4, spin, spin + 1.5, 10, ring, 1.2, true)
	var badge: Color = _link_tint(int(row["developed"]), int(row["linked"]))
	badge.a *= alpha
	draw_string(
		_font, Vector2(column.position.x, column.position.y + 26.0),
		String(row["badge"]), HORIZONTAL_ALIGNMENT_CENTER, column.size.x, 10, badge
	)


## Ground still to read: the Explorer's own compass mark and the tiles it could
## prospect, in its own column so the count never collides with a type's badge
## (issue #698). Hidden when the province has nothing left to survey.
func _draw_prospect_cue(entry: Dictionary, rect: Rect2, alpha: float) -> void:
	var left: int = int(entry.get("unsurveyed", 0))
	if left <= 0:
		return
	var column := Rect2(
		rect.end.x - PLATE_PAD - CUE_W, rect.position.y + 4.0, CUE_W, 38.0
	)
	var ink: Color = Palette.ink(0.74 * alpha)
	var needle: Color = Palette.survey_color("survey")
	needle.a *= alpha
	var center := Vector2(column.position.x + column.size.x * 0.5, column.position.y + 8.5)
	CivicGlyphs.explorer(self, center, 13.0, ink, needle)
	draw_string(
		_font, Vector2(column.position.x, column.position.y + 26.0), str(left),
		HORIZONTAL_ALIGNMENT_CENTER, column.size.x, 10, needle
	)


## The badge's ink speaks the same reading the link row used to: green when a
## type's built estates all reach the crown, amber when some do, crimson when
## they are all cut off, and quiet ink while nothing is built.
func _link_tint(developed: int, linked: int) -> Color:
	if developed <= 0:
		return Palette.ink(0.46)
	if linked >= developed:
		return Palette.SURVEY_YIELDING
	if linked > 0:
		return Palette.SURVEY_BUILDING
	return Palette.SURVEY_VACANT


# --- layout ------------------------------------------------------------------


## Plates are 32 px tall and the survey steps 24 px, so a free lane often needs
## step ≥ 2; four tries used to leave overlaps on the fixture chart.
func _pack_step() -> float:
	return 24.0


## Slips drop below the province name, which every chart now prints, so the
## label is never covered.
func _pack_drop(_entry: Dictionary) -> float:
	return LABEL_DROP


func _plate_size(entry: Dictionary) -> Vector2:
	var types: int = maxi((entry.get("types", []) as Array).size(), 1)
	var width: float = PLATE_PAD * 2.0 + RIBBON + float(types) * TYPE_COL
	if int(entry.get("unsurveyed", 0)) > 0:
		width += CUE_W
	return Vector2(width, PLATE_H)


func _status_tint(status: String) -> Color:
	match status:
		"foreign", "foreign_worked":
			return Palette.SURVEY_FOREIGN
		"foreign_building":
			return Palette.SURVEY_BUILDING
	return Palette.survey_color(status)
