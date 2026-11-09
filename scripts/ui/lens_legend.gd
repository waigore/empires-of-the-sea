class_name LensLegend
extends Control
## Survey-key cartouche shown while the resource lens is on. Vector swatches
## mirror `ResourceLens` so the map and the key cannot drift apart (REQ-P1-02).

const WIDTH: float = 244.0
const HEIGHT: float = 156.0

const ROWS: Array[Dictionary] = [
	{"status": "producing", "text": "Yielding estate"},
	{"status": "building", "text": "Under works"},
	{"status": "vacant", "text": "Vacant — can raise"},
	{"status": "unprospected", "text": "Needs prospecting"},
	{"status": "disconnected", "text": "No road to the crown"},
	{"status": "foreign", "text": "Foreign holding"},
]

var _style: StyleBoxFlat = null
var _font: Font = null


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = UiTheme.box(
		Color(0.10, 0.08, 0.06, 0.94), Palette.GOLD_DIM, 1, 3, Vector4.ZERO
	)
	_style.shadow_color = Color(0, 0, 0, 0.35)
	_style.shadow_size = 6
	_font = UiTheme.serif()


func _draw() -> void:
	_ensure()
	draw_style_box(_style, Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT)))
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("SURVEY KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 46.0
	for row: Dictionary in ROWS:
		_draw_swatch(Vector2(22, y - 4.5), String(row["status"]))
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 16.0
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Badge: estates worked  ·  bar: share",
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


func _draw_swatch(center: Vector2, status: String) -> void:
	var tint: Color = Palette.SURVEY_FOREIGN if status == "foreign" else Palette.survey_color(status)
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
