class_name Ship
extends Node2D
## A fleet marker drawn as a small side-view vessel with a bobbing idle and a
## fading wake. Purely presentational: the layer owns movement and zones.

var faction: int = 0
var fleet_id: int = -1
var zone: int = -1
var province: int = -1
var docked: bool = false
var speed: float = 34.0
var bob_phase: float = 0.0
var facing: float = 1.0
var selected: bool = false

var _time: float = 0.0
var _wake_strength: float = 0.0


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _draw() -> void:
	var bob: float = sin(_time * 1.7 + bob_phase) * 1.5
	var tilt: float = sin(_time * 1.25 + bob_phase) * 0.05
	draw_set_transform(Vector2(0, bob), tilt, Vector2(facing, 1.0))

	var ink := Color(0.16, 0.12, 0.08, 0.9)
	var hull := Color(0.30, 0.21, 0.13)
	var sail := Color(0.96, 0.92, 0.81)
	var flag: Color = Palette.faction_color(faction)

	# wake
	if not docked:
		for i in 3:
			var offset: float = -18.0 - float(i) * 7.0
			var alpha: float = (0.30 - float(i) * 0.08) * (0.4 + _wake_strength)
			draw_arc(
				Vector2(offset, 3.0), 5.0 + float(i) * 2.0, -0.9, 0.9, 10,
				Color(0.98, 0.96, 0.90, alpha), 1.2, true
			)

	# hull
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-15, 0), Vector2(-11, 6), Vector2(0, 8), Vector2(11, 6), Vector2(15, 0)
		]),
		hull
	)
	draw_polyline(
		PackedVector2Array([
			Vector2(-15, 0), Vector2(-11, 6), Vector2(0, 8), Vector2(11, 6), Vector2(15, 0)
		]),
		ink, 1.2, true
	)
	draw_line(Vector2(-15, 0), Vector2(15, 0), ink, 1.4, true)
	if docked:
		draw_line(Vector2(0, 1), Vector2(0, 13), ink, 1.4, true)
		draw_arc(Vector2(0, 11), 5.5, PI * 0.12, PI * 0.88, 14, ink, 1.4, true)
		draw_circle(Vector2(0, 0), 1.6, ink)
	# stern castle and bowsprit
	draw_rect(Rect2(-15, -6, 7, 6), hull)
	draw_rect(Rect2(-15, -6, 7, 6), ink, false, 1.0)
	draw_line(Vector2(15, 0), Vector2(23, -7), ink, 1.4, true)

	# masts and sails
	for mast in [{"x": -5.0, "top": -25.0, "sail_top": -22.0, "sail_bottom": -9.0},
			{"x": 6.0, "top": -21.0, "sail_top": -18.0, "sail_bottom": -8.0}]:
		var x: float = mast["x"]
		draw_line(Vector2(x, 0), Vector2(x, mast["top"]), ink, 1.3, true)
		var sail_points := PackedVector2Array([
			Vector2(x - 7.0, mast["sail_top"]),
			Vector2(x + 7.0, mast["sail_top"]),
			Vector2(x + 5.0, mast["sail_bottom"]),
			Vector2(x - 5.0, mast["sail_bottom"]),
		])
		draw_colored_polygon(sail_points, sail)
		draw_polyline(sail_points, ink, 1.0, true)
		draw_line(
			Vector2(x - 7.0, mast["sail_top"]), Vector2(x + 7.0, mast["sail_top"]), ink, 1.2, true
		)

	# pennant
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-5, -25), Vector2(3, -23), Vector2(-5, -21)
		]),
		flag
	)

	if selected:
		draw_arc(Vector2(0, 0), 24.0, 0, TAU, 40, Color(0.99, 0.93, 0.72, 0.9), 2.0, true)
		draw_arc(Vector2(0, 0), 29.0, 0, TAU, 40, Color(0.83, 0.69, 0.22, 0.35), 4.0, true)
