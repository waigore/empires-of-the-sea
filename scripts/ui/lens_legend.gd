class_name LensLegend
extends Control
## Key cartouche shown while a map lens is on. Vector swatches mirror the lens
## inks (`Palette`) so the map and the key cannot drift apart (REQ-P1-02).
## One node serves both lenses: the survey key while the resource lens is on,
## the political key while the diplomatic lens is on.

const WIDTH: float = 244.0
const HEIGHT: float = 156.0

const SURVEY_ROWS: Array[Dictionary] = [
	{"status": "producing", "text": "Yielding estate"},
	{"status": "building", "text": "Under works"},
	{"status": "vacant", "text": "Vacant — can raise"},
	{"status": "unprospected", "text": "Needs prospecting"},
	{"status": "disconnected", "text": "No road to the crown"},
	{"status": "foreign", "text": "Foreign holding"},
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

const KIND_SURVEY: String = "survey"
const KIND_DIPLOMACY: String = "diplomacy"
const KIND_CROWN_ROAD: String = "crown_road"

## Which key to draw: KIND_SURVEY (default), KIND_DIPLOMACY or KIND_CROWN_ROAD.
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
	_draw_survey()


func _draw_survey() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("SURVEY KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 46.0
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
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Badge: estates worked  ·  bar: share",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


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


func _draw_dot(center: Vector2, status: String, tint: Color) -> void:
	var radius: float = 6.2
	if status == "producing":
		draw_circle(center, radius - 0.6, Color(tint.r, tint.g, tint.b, 0.22))
	draw_circle(center, 2.0, tint)
	match status:
		"unprospected":
			for i in 8:
				var angle: float = TAU * float(i) / 8.0
				var spot: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
				draw_circle(spot, 1.0, tint)
		"disconnected":
			draw_arc(center, radius, 0, TAU, 18, tint, 1.1, true)
			draw_line(
				center + Vector2(-radius * 0.7, radius * 0.7),
				center + Vector2(radius * 0.7, -radius * 0.7), tint, 1.3, true
			)
		_:
			draw_arc(center, radius, 0, TAU, 18, tint, 1.4, true)
