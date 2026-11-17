class_name LensLegend
extends Control
## Key cartouche shown while a map lens is on. Vector swatches mirror the lens
## inks (`Palette`) so the map and the key cannot drift apart (REQ-P1-02).
## One node serves both lenses: the survey key while the resource lens is on,
## the political key while the diplomatic lens is on.

const WIDTH: float = 244.0
## Tall enough for the six estate rows, the three road strokes and the three
## footer lines (badge, compass, the court's pick ring).
const HEIGHT: float = 226.0

const SURVEY_ROWS: Array[Dictionary] = [
	{"status": "producing", "text": "Yielding estate"},
	{"status": "building", "text": "Under works"},
	{"status": "vacant", "text": "Vacant — can raise"},
	{"status": "survey", "text": "Prospectable — send an Explorer"},
	{"status": "disconnected", "text": "No road to the crown"},
	{"status": "foreign", "text": "Foreign holding"},
]

## The lens carries the built network (roads leave the chart): three strokes,
## the same shapes `RoadInk` paints in world space.
const ROAD_ROWS: Array[Dictionary] = [
	{"kind": "road", "text": "Road to the crown"},
	{"kind": "rail", "text": "Railroad"},
	{"kind": "cut", "text": "No crown link"},
]

const DIPLOMACY_ROWS: Array[Dictionary] = [
	{"band": DiplomacySurvey.BAND_SELF, "text": "Your realm"},
	{"band": DiplomacySurvey.BAND_FRIENDLY, "text": "Friendly or allied"},
	{"band": DiplomacySurvey.BAND_NEUTRAL, "text": "Neutral"},
	{"band": DiplomacySurvey.BAND_WAR, "text": "At war"},
]

const CROWN_ROWS: Array[Dictionary] = [
	{"state": CrownRoadSurvey.STATE_ROAD, "text": "Road to the crown"},
	{"state": CrownRoadSurvey.STATE_TOWN, "text": "Town road only — capped"},
	{"state": CrownRoadSurvey.STATE_CUT, "text": "Cut off — road tiles left"},
]

## One row per defence band, in the order the shield colours run: open ground
## first, then a garrison, then the two wall tiers (DefenceSurvey.BANDS).
const DEFENCE_ROWS: Array[Dictionary] = [
	{"band": DefenceSurvey.BAND_OPEN, "text": "Open — no garrison, no wall"},
	{"band": DefenceSurvey.BAND_HELD, "text": "Garrison only"},
	{"band": DefenceSurvey.BAND_WALLED, "text": "Walled — fort 1–2"},
	{"band": DefenceSurvey.BAND_CITADEL, "text": "Citadel — fort 3"},
]

const KIND_SURVEY: String = "survey"
const KIND_DIPLOMACY: String = "diplomacy"
const KIND_CROWN_ROAD: String = "crown_road"
const KIND_DEFENCE: String = "defence"
const KIND_SEA: String = "sea"

## One pennant per sea band, in the order the threat runs: our own quiet water,
## a rival under the peace, hostile water we do not hold, then the two fights
## the turn will resolve — read and unread (SeaSurvey.BANDS).
const SEA_ROWS: Array[Dictionary] = [
	{"band": SeaSurvey.BAND_QUIET, "text": "Our water — no hostile sail"},
	{"band": SeaSurvey.BAND_WATCHED, "text": "A rival's sails, no war"},
	{"band": SeaSurvey.BAND_STANDOFF, "text": "Hostile water we do not hold"},
	{"band": SeaSurvey.BAND_CONTESTED, "text": "A battle resolves at turn end"},
	{"band": SeaSurvey.BAND_BLIND, "text": "…and her weight unread"},
]

## Which key to draw: KIND_SURVEY (default), KIND_DIPLOMACY, KIND_CROWN_ROAD,
## KIND_DEFENCE or KIND_SEA.
var kind: String = KIND_SURVEY

var _style: StyleBoxFlat = null
var _font: Font = null


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure()


func set_kind(value: String) -> void:
	if kind == value:
		return
	kind = value
	queue_redraw()


func is_survey() -> bool:
	return kind == KIND_SURVEY


func _draw() -> void:
	_ensure()
	draw_style_box(_style, Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT)))
	if kind == KIND_DIPLOMACY:
		_draw_diplomacy()
		return
	if kind == KIND_CROWN_ROAD:
		_draw_crown_road()
		return
	if kind == KIND_DEFENCE:
		_draw_defence()
		return
	if kind == KIND_SEA:
		_draw_sea()
		return
	_draw_survey()


## Six readings, the three road strokes, then the two lines that spell the
## plate's badge and its Explorer cue out. The rows close at 174 so the two footer
## lines never sit on the last road row.
func _draw_survey() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("SURVEY KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 44.0
	for row: Dictionary in SURVEY_ROWS:
		var status: String = String(row["status"])
		var tint: Color = (
			Palette.SURVEY_FOREIGN if status == "foreign" else Palette.survey_color(status)
		)
		_draw_dot(Vector2(22, y - 4.5), status, tint)
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 16.0
	y += 2.0
	for row: Dictionary in ROAD_ROWS:
		_draw_road(Vector2(16, y - 4.5), String(row["kind"]))
		draw_string(
			_font, Vector2(44, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 54, 13, Palette.TEXT
		)
		y += 16.0
	draw_string(
		_font, Vector2(14, HEIGHT - 38), "Badge: built / linked / held, per resource type",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 22), "Compass: tiles an Explorer can still read",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 8), "Ring: the court's pick for an idle crew",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## The three road strokes at key size: solid ink for a road to the crown, sleepers
## for a railroad, dashes for a road the network does not reach.
func _draw_road(start: Vector2, kind: String) -> void:
	var end: Vector2 = start + Vector2(18, 0)
	var ink: Color = Palette.GOLD_DIM
	match kind:
		"rail":
			draw_line(start, end, ink, 1.8, true)
			for i in 2:
				var x: float = start.x + 6.0 + float(i) * 8.0
				draw_line(Vector2(x, start.y - 3.4), Vector2(x, start.y + 3.0), ink, 1.3, true)
		"cut":
			for i in 3:
				var x: float = start.x + float(i) * 7.0
				draw_line(
					Vector2(x, start.y), Vector2(x + 4.0, start.y),
					Palette.TEXT_DIM, 1.5, true
				)
		_:
			draw_line(start, end, ink, 2.1, true)


## Four readings, one per band. The wash is a flat tint, so the key shows the
## same flat swatch rather than a status ring.
func _draw_diplomacy() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("DIPLOMACY KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in DIPLOMACY_ROWS:
		var band: String = String(row["band"])
		var tint: Color = Palette.diplo_color(band)
		draw_rect(
			Rect2(Vector2(14, y - 13), Vector2(16, 16)),
			Color(tint.r, tint.g, tint.b, 0.72)
		)
		draw_rect(
			Rect2(Vector2(14, y - 13), Vector2(16, 16)),
			Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55), false, 1.0
		)
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Charted land only  ·  grey: no court",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## Three readings, one per state, plus the gap badge the cut rows carry. The
## wash is a flat tint, so the key shows the same flat swatch as the lens.
func _draw_crown_road() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("CROWN ROAD KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in CROWN_ROWS:
		var state: String = String(row["state"])
		var tint: Color = Palette.crown_color(state)
		draw_rect(
			Rect2(Vector2(14, y - 13), Vector2(16, 16)),
			Color(tint.r, tint.g, tint.b, 0.72)
		)
		draw_rect(
			Rect2(Vector2(14, y - 13), Vector2(16, 16)),
			Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55), false, 1.0
		)
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 30), "Badge: road tiles still to lay",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Gold line: the route the crew walks",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## Four bands, one shield each, in the same order as the colours: open ground,
## a garrison, a walled province and a citadel. The gold pips are the guns and
## the cross is the hospital, exactly as the slips carry them.
func _draw_defence() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("DEFENCE KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in DEFENCE_ROWS:
		var band: String = String(row["band"])
		_draw_shield(Vector2(22, y - 4), Palette.defence_color(band))
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 30), "Number: strength · pips: guns",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Cross: hospital · charted land only",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## One pennant per band, in the same ink the water carries: our quiet sea, a
## rival under the peace, hostile water, then the two fights the turn resolves.
## The footer spells the two figures a slip prints.
func _draw_sea() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("SEA KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in SEA_ROWS:
		var band: String = String(row["band"])
		_draw_pennant(Vector2(22, y - 4), Palette.sea_color(band))
		draw_string(
			_font, Vector2(40, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 50, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 30), "Line: our hulls and strength · below: station, foe",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "??? : a weight not yet read · red rule: a fight",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## The pennant over a short mast the slips carry, at key size.
func _draw_pennant(center: Vector2, tint: Color) -> void:
	draw_line(
		center + Vector2(-5.0, -9.0), center + Vector2(-5.0, 9.0),
		Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55), 1.2, true
	)
	var fly := PackedVector2Array([
		center + Vector2(-4.0, -8.0),
		center + Vector2(10.0, -3.0),
		center + Vector2(-4.0, 2.0),
	])
	draw_colored_polygon(fly, Color(tint.r, tint.g, tint.b, 0.92))


## The same heraldic shield the map slips carry, at key size.
func _draw_shield(center: Vector2, tint: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-7.0, -8.0),
		center + Vector2(7.0, -8.0),
		center + Vector2(7.0, 1.0),
		center + Vector2(0.0, 9.0),
		center + Vector2(-7.0, 1.0),
	])
	draw_colored_polygon(points, Color(tint.r, tint.g, tint.b, 0.90))
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[3], points[4], points[0]]),
		Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55), 1.0, true
	)


func _ensure() -> void:
	if _font != null:
		return
	_style = UiTheme.box(
		Color(0.10, 0.08, 0.06, 0.94), Palette.GOLD_DIM, 1, 3, Vector4.ZERO
	)
	_style.shadow_color = Color(0, 0, 0, 0.35)
	_style.shadow_size = 6
	_font = UiTheme.serif()
	custom_minimum_size = Vector2(WIDTH, HEIGHT)


## One swatch per reading. `survey` is the Explorer's own compass mark, the same
## the plates carry beside their prospectable count; a plate's badge reads
## `built/linked/held` per resource type, which the footer spells out.
func _draw_dot(center: Vector2, status: String, tint: Color) -> void:
	if status == "survey":
		CivicGlyphs.explorer(self, center, 13.0, Palette.TEXT_DIM, tint)
		return
	var radius: float = 6.2
	if status == "producing":
		draw_circle(center, radius - 0.6, Color(tint.r, tint.g, tint.b, 0.22))
	draw_circle(center, 2.0, tint)
	match status:
		"disconnected":
			draw_arc(center, radius, 0, TAU, 18, tint, 1.1, true)
			draw_line(
				center + Vector2(-radius * 0.7, radius * 0.7),
				center + Vector2(radius * 0.7, -radius * 0.7), tint, 1.3, true
			)
		_:
			draw_arc(center, radius, 0, TAU, 18, tint, 1.4, true)
