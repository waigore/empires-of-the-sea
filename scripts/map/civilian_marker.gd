class_name CivilianMarker
extends Node2D
## A civilian map unit drawn as a small period medallion: a parchment disc, the
## crown's colour and the trade's ink emblem. Each emblem is the map-scale take
## on that crew type's medallion in the crew screen, so a civilian reads as the
## same office at chart scale (issue #1007). Purely presentational;
## CivilianLayer owns the rules state and movement.

var unit_id: int = -1
var type_id: String = "explorer"
var faction: int = 0
var selected: bool = false
var working: bool = false
var progress: float = 0.0

## The disc a civilian is drawn on: big enough that the ink emblem inside it
## still reads at chart scale, small enough not to swallow the tile.
const DISC: float = 13.4
const RING: float = 11.0
## The emblem fills the disc: at chart scale a small mark reads as a smudge.
const EMBLEM: float = 1.18

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
	draw_circle(Vector2(0.9, 1.8), DISC + 0.4, Color(0.10, 0.08, 0.05, 0.24))
	draw_circle(Vector2.ZERO, DISC, paper)
	draw_circle(Vector2.ZERO, DISC, ink, false, 1.4, true)
	draw_arc(Vector2.ZERO, RING, 0, TAU, 30, crown, 2.2, true)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(EMBLEM, EMBLEM))
	match type_id:
		"explorer":
			_draw_spyglass(ink, crown, paper)
		"builder":
			_draw_hammer_and_saw(ink, crown)
		"engineer":
			_draw_bridge(ink, crown)
		"spy":
			_draw_hood(ink, paper)
		"merchant":
			_draw_scales(ink, crown)
		"rail_builder":
			_draw_rail(ink, crown)
		_:
			draw_circle(Vector2.ZERO, 3.0, crown)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if working:
		var sweep: float = TAU * progress
		draw_arc(
			Vector2.ZERO, DISC + 2.6, -PI * 0.5, -PI * 0.5 + sweep, 26,
			Color(0.99, 0.93, 0.72, 0.95), 2.4, true
		)
		draw_arc(
			Vector2.ZERO, DISC + 2.6, 0, TAU, 32, Color(0.83, 0.69, 0.22, 0.30), 1.2, true
		)

	if selected:
		draw_arc(
			Vector2.ZERO, DISC + 6.0, 0, TAU, 40,
			Color(0.99, 0.93, 0.72, 0.75 + 0.2 * pulse), 2.2, true
		)


## Explorer: the crew medallion's spyglass, tube toward the upper right, glass
## left pale so the instrument does not read as a plain stroke.
func _draw_spyglass(ink: Color, crown: Color, paper: Color) -> void:
	draw_line(Vector2(-4.8, 4.4), Vector2(4.0, -3.2), ink, 3.2, true)
	draw_line(Vector2(-2.4, 2.0), Vector2(0.2, -0.2), crown, 1.8, true)
	draw_circle(Vector2(4.2, -3.4), 2.3, ink)
	draw_circle(Vector2(4.2, -3.4), 1.2, paper)
	draw_circle(Vector2(4.2, -3.4), 0.7, crown)


## Builder: the crossed hammer over a hand saw, as on the crew medallion. The
## saw is one solid wedge: teeth drawn as ticks turn to noise at chart scale.
func _draw_hammer_and_saw(ink: Color, crown: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-6.4, 3.2), Vector2(6.2, 5.2), Vector2(6.2, 3.0), Vector2(-6.4, 1.2),
		]),
		crown
	)
	draw_polyline(
		PackedVector2Array([
			Vector2(-6.4, 3.2), Vector2(6.2, 5.2), Vector2(6.2, 3.0), Vector2(-6.4, 1.2),
		]),
		ink, 1.2, true
	)
	draw_line(Vector2(-4.6, 5.6), Vector2(2.4, -2.4), ink, 2.4, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-0.4, -6.6), Vector2(6.0, -3.6), Vector2(4.4, -0.4), Vector2(-1.0, -3.2),
		]),
		crown
	)
	draw_polyline(
		PackedVector2Array([
			Vector2(-0.4, -6.6), Vector2(6.0, -3.6), Vector2(4.4, -0.4), Vector2(-1.0, -3.2),
		]),
		ink, 1.2, true
	)


## Engineer: the arch bridge, with the crew medallion's crossed trowels above.
func _draw_bridge(ink: Color, crown: Color) -> void:
	draw_arc(Vector2(0, 4.6), 5.6, PI, TAU, 18, crown, 2.6, true)
	draw_line(Vector2(-6.4, 4.6), Vector2(6.4, 4.6), ink, 1.4, true)
	draw_line(Vector2(-6.4, 4.6), Vector2(-6.4, 6.4), ink, 1.4, true)
	draw_line(Vector2(6.4, 4.6), Vector2(6.4, 6.4), ink, 1.4, true)
	for side: float in [-1.0, 1.0]:
		draw_line(Vector2(0, 2.4), Vector2(side * 4.0, -5.0), ink, 1.6, true)
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(side * 4.0, -5.6),
				Vector2(side * 1.9, -5.0),
				Vector2(side * 3.2, -3.0),
			]),
			crown
		)


## Spy: the hooded courier of the crew medallion, face in shadow, a letter held
## forward.
func _draw_hood(ink: Color, paper: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-4.8, 6.0),
			Vector2(-6.0, -0.8),
			Vector2(-3.6, -5.2),
			Vector2(-0.4, -6.2),
			Vector2(1.8, -3.6),
			Vector2(1.2, 2.2),
			Vector2(2.2, 6.0),
		]),
		ink
	)
	draw_circle(Vector2(-2.2, -1.8), 1.7, paper)
	draw_rect(Rect2(Vector2(1.4, 2.2), Vector2(5.0, 3.4)), paper)
	draw_rect(Rect2(Vector2(1.4, 2.2), Vector2(5.0, 3.4)), ink, false, 0.9)
	draw_line(Vector2(1.6, 2.6), Vector2(3.9, 4.2), ink, 0.8, true)
	draw_line(Vector2(6.2, 2.6), Vector2(3.9, 4.2), ink, 0.8, true)


## Merchant: the balance over a strongbox, as on the crew medallion. Solid pans
## and a solid chest keep the trade readable when the disc is 27 px across.
func _draw_scales(ink: Color, crown: Color) -> void:
	draw_line(Vector2(0, -5.8), Vector2(0, 1.8), ink, 1.8, true)
	draw_line(Vector2(-6.0, -4.8), Vector2(6.0, -4.8), crown, 2.4, true)
	for side: float in [-1.0, 1.0]:
		draw_line(Vector2(side * 6.0, -4.8), Vector2(side * 4.2, 0.2), ink, 1.2, true)
		draw_circle(Vector2(side * 4.2, 0.9), 2.1, crown)
		draw_circle(Vector2(side * 4.2, 0.9), 2.1, ink, false, 1.0, true)
	draw_rect(Rect2(Vector2(-5.0, 2.2), Vector2(10.0, 4.0)), crown)
	draw_rect(Rect2(Vector2(-5.0, 2.2), Vector2(10.0, 4.0)), ink, false, 1.2)
	draw_line(Vector2(-5.0, 3.4), Vector2(5.0, 3.4), ink, 1.0, true)
	draw_circle(Vector2(0, 4.4), 1.0, ink)


## Rail builder: the crew medallion's crossed sledge and pick over a rail.
func _draw_rail(ink: Color, crown: Color) -> void:
	draw_line(Vector2(-5.2, 3.4), Vector2(4.6, -5.0), ink, 2.0, true)
	draw_line(Vector2(5.2, 3.4), Vector2(-4.6, -5.0), ink, 2.0, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(2.4, -6.0), Vector2(6.2, -4.0), Vector2(4.6, -2.2), Vector2(1.8, -4.0),
		]),
		crown
	)
	draw_line(Vector2(-4.6, -5.0), Vector2(-6.4, -6.0), crown, 1.8, true)
	draw_line(Vector2(-6.6, 4.6), Vector2(6.6, 4.6), ink, 1.2, true)
	draw_line(Vector2(-6.6, 6.2), Vector2(6.6, 6.2), ink, 1.0, true)
	for i in 3:
		var x: float = -4.8 + float(i) * 4.8
		draw_line(Vector2(x, 4.4), Vector2(x, 6.4), ink, 1.0, true)
