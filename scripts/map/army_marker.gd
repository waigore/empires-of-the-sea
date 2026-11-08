class_name ArmyMarker
extends Node2D
## A land army's standard on the map: a company colour, a drum-badge with the
## regiment count, and a ring when selected. Presentation only — ArmyLayer owns
## position and state.

var faction: int = 0
var army_id: int = -1
var count: int = 0
var home: bool = false
var selected: bool = false

var _time: float = 0.0


func _ready() -> void:
	z_index = 6


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func refresh(p_count: int, p_home: bool) -> void:
	count = p_count
	home = p_home
	queue_redraw()


func _draw() -> void:
	if count <= 0:
		return
	var sway: float = sin(_time * 1.6 + float(army_id)) * 0.8
	var ink := Color(0.16, 0.12, 0.08, 0.92)
	var cloth: Color = Palette.faction_color(faction)
	var pole_top := Vector2(0.0 + sway, -20.0)

	# shadow and base
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(0, 4), 8.0, Color(0.10, 0.07, 0.03, 0.22))
	# pole
	draw_line(Vector2(sway, 3), pole_top, ink, 1.6, true)
	# banner
	draw_colored_polygon(
		PackedVector2Array([
			pole_top + Vector2(0, 0),
			pole_top + Vector2(16, 2),
			pole_top + Vector2(13, 12),
			pole_top + Vector2(0, 14),
		]),
		cloth
	)
	draw_polyline(
		PackedVector2Array([
			pole_top + Vector2(0, 0),
			pole_top + Vector2(16, 2),
			pole_top + Vector2(13, 12),
			pole_top + Vector2(0, 14),
			pole_top,
		]),
		ink, 1.1, true
	)
	# home army carries a crown pip; field armies a simple bar
	if home:
		draw_circle(pole_top + Vector2(7, 5), 2.0, Palette.GOLD_PALE)
	else:
		draw_line(pole_top + Vector2(4, 5), pole_top + Vector2(11, 6), ink, 1.2, true)
	# regiment count badge
	draw_circle(Vector2(0, 8), 7.0, Color(0.96, 0.92, 0.81, 0.95))
	draw_arc(Vector2(0, 8), 7.0, 0, TAU, 20, ink, 1.1, true)
	var font: Font = ThemeDB.fallback_font
	draw_string(
		font, Vector2(-7, 12), str(count), HORIZONTAL_ALIGNMENT_CENTER, 14, 11, ink
	)
	if selected:
		draw_arc(Vector2(0, 0), 23.0, 0, TAU, 36, Color(0.99, 0.93, 0.72, 0.9), 2.0, true)
		draw_arc(Vector2(0, 0), 27.0, 0, TAU, 36, Color(0.83, 0.69, 0.22, 0.32), 4.0, true)
