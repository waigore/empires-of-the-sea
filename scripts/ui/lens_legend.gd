class_name LensLegend
extends Control
## Key cartouche shown while a map lens is on. Vector swatches mirror the lens
## inks (`Palette`) so the map and the key cannot drift apart (REQ-P1-02).
## One node serves both lenses: the survey key while the resource lens is on,
## the political key while the diplomatic lens is on.

const WIDTH: float = 244.0
const HEIGHT: float = 210.0

const SURVEY_ROWS: Array[Dictionary] = [
	{"status": "producing", "text": "Yielding estate"},
	{"status": "building", "text": "Under works"},
	{"status": "vacant", "text": "Vacant — can raise"},
	{"status": "unprospected", "text": "Needs prospecting"},
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

const KIND_SURVEY: String = "survey"
const KIND_DIPLOMACY: String = "diplomacy"

## Which key to draw: KIND_SURVEY (default) or KIND_DIPLOMACY.
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
	y += 4.0
	for row: Dictionary in ROAD_ROWS:
		_draw_road(Vector2(16, y - 4.5), String(row["kind"]))
		draw_string(
			_font, Vector2(44, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 54, 13, Palette.TEXT
		)
		y += 16.0
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Badge: estates worked  ·  link: to the crown",
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
