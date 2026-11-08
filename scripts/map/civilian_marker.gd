class_name CivilianMarker
extends Node2D
## A civilian map unit drawn as a small period medallion: a plume of parchment,
## the crown's colour and a trade glyph. Purely presentational; CivilianLayer
## owns the rules state and movement.

var unit_id: int = -1
var type_id: String = "explorer"
var faction: int = 0
var selected: bool = false
var working: bool = false
var progress: float = 0.0

var _time: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	z_index = 6
	_phase = float(unit_id) * 0.7


func _process(delta: float) -> void:
	_time += delta
	if selected or working:
		queue_redraw()


func set_state(is_selected: bool, is_working: bool, work_progress: float) -> void:
	selected = is_selected
	working = is_working
	progress = clampf(work_progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.4 + _phase)
	var ink := Color(0.16, 0.12, 0.08, 0.92)
	var paper := Color(0.94, 0.90, 0.80, 1.0)
	var crown: Color = Palette.faction_color(faction)

	# soft shadow so the medallion reads on any terrain
	draw_circle(Vector2(0.9, 1.6), 10.4, Color(0.10, 0.08, 0.05, 0.24))
	draw_circle(Vector2.ZERO, 10.2, paper)
	draw_circle(Vector2.ZERO, 10.2, ink, false, 1.4, true)
	draw_arc(Vector2.ZERO, 8.6, 0, TAU, 28, crown, 2.4, true)

	match type_id:
		"explorer":
			_draw_compass(ink, crown)
		"builder":
			_draw_hammer(ink, crown)
		"engineer":
			_draw_bridge(ink, crown)
		_:
			draw_circle(Vector2.ZERO, 2.8, crown)

	if working:
		var sweep: float = TAU * progress
		draw_arc(
			Vector2.ZERO, 13.0, -PI * 0.5, -PI * 0.5 + sweep, 26,
			Color(0.99, 0.93, 0.72, 0.95), 2.4, true
		)
		draw_arc(
			Vector2.ZERO, 13.0, 0, TAU, 32, Color(0.83, 0.69, 0.22, 0.30), 1.2, true
		)

	if selected:
		draw_arc(
			Vector2.ZERO, 16.5, 0, TAU, 40,
			Color(0.99, 0.93, 0.72, 0.75 + 0.2 * pulse), 2.2, true
		)


func _draw_compass(ink: Color, crown: Color) -> void:
	draw_line(Vector2(0, -6.0), Vector2(0, 6.0), ink, 1.2, true)
	draw_line(Vector2(-6.0, 0), Vector2(6.0, 0), ink, 1.2, true)
	draw_colored_polygon(
		PackedVector2Array([Vector2(0, -6.8), Vector2(2.2, 0), Vector2(0, 6.8), Vector2(-2.2, 0)]),
		crown
	)
	draw_circle(Vector2.ZERO, 1.4, Palette.GOLD_PALE)


func _draw_hammer(ink: Color, crown: Color) -> void:
	draw_line(Vector2(-4.6, 5.2), Vector2(3.0, -2.8), ink, 2.2, true)
	draw_rect(Rect2(Vector2(1.0, -6.4), Vector2(6.6, 3.8)), crown)
	draw_rect(Rect2(Vector2(1.0, -6.4), Vector2(6.6, 3.8)), ink, false, 1.2)
	draw_line(Vector2(1.0, -6.4), Vector2(2.0, -2.4), ink, 1.2, true)


func _draw_bridge(ink: Color, crown: Color) -> void:
	draw_arc(Vector2(0, 3.0), 5.2, PI, TAU, 18, crown, 2.2, true)
	draw_line(Vector2(-5.2, 3.0), Vector2(-5.2, 5.6), ink, 1.6, true)
	draw_line(Vector2(5.2, 3.0), Vector2(5.2, 5.6), ink, 1.6, true)
	draw_line(Vector2(-5.6, 3.0), Vector2(5.6, 3.0), ink, 1.4, true)
