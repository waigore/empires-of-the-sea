class_name Ship
extends Node2D
## A fleet marker drawn as a small side-view vessel with a bobbing idle and a
## fading wake. A squadron of several hulls draws its escorts astern, a hull
## badge and a gold strength gauge, so one marker reads as a fleet and its
## fighting weight (wiki: ships-and-naval § Naval Strength Aggregation Formula).
## Purely presentational: the layer owns movement, zones and the numbers.

## Strength that fills the gauge: a squadron of twenty is a fleet of the line.
const GAUGE_MAX: float = 20.0
## Escorts drawn astern before the badge carries the count alone.
const ESCORT_LIMIT: int = 2
## Zoom at which the printed strength is legible enough to show.
const DETAIL_ZOOM: float = 0.85

var faction: int = 0
var fleet_id: int = -1
var zone: int = -1
var province: int = -1
var docked: bool = false
var speed: float = 34.0
var bob_phase: float = 0.0
var facing: float = 1.0
var selected: bool = false
## Hulls in the squadron and its weighted strength, mirrored from the fleet.
var hull_count: int = 1
var strength: float = 0.0
## Zoomed in enough to print the numbers beside the gauge.
var detail: bool = false

var _time: float = 0.0
var _wake_strength: float = 0.0


func _ready() -> void:
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## Mirrors the squadron's hulls and strength onto the marker.
func set_squadron(count: int, fighting_strength: float) -> void:
	hull_count = maxi(count, 1)
	strength = maxf(fighting_strength, 0.0)
	queue_redraw()


func _draw() -> void:
	var bob: float = sin(_time * 1.7 + bob_phase) * 1.5
	var tilt: float = sin(_time * 1.25 + bob_phase) * 0.05
	# Escorts astern, far hull first, so the lead vessel overlaps them and the
	# marker reads as a squadron in line rather than a row of loose boats.
	for index in range(mini(hull_count - 1, ESCORT_LIMIT), 0, -1):
		var size: float = 0.66 - 0.10 * float(index - 1)
		var astern := Vector2(-(18.0 + 16.0 * float(index)), 3.0 + 7.0 * float(index))
		draw_set_transform(
			Vector2(astern.x, bob + astern.y), tilt * 0.7, Vector2(facing * size, size)
		)
		_vessel(false, 0.74)
	draw_set_transform(Vector2(0, bob), tilt, Vector2(facing, 1.0))
	if not docked:
		_wake()
	_vessel(true, 1.0)
	# The badge and gauge never flip with the hull, or the figures would mirror.
	draw_set_transform(Vector2(0, bob), 0.0, Vector2.ONE)
	_squadron_badge()
	if selected:
		draw_arc(Vector2(0, 0), 24.0, 0, TAU, 40, Color(0.99, 0.93, 0.72, 0.9), 2.0, true)
		draw_arc(Vector2(0, 0), 29.0, 0, TAU, 40, Color(0.83, 0.69, 0.22, 0.35), 4.0, true)


func _wake() -> void:
	for i in 3:
		var offset: float = -18.0 - float(i) * 7.0
		var alpha: float = (0.30 - float(i) * 0.08) * (0.4 + _wake_strength)
		draw_arc(
			Vector2(offset, 3.0), 5.0 + float(i) * 2.0, -0.9, 0.9, 10,
			Color(0.98, 0.96, 0.90, alpha), 1.2, true
		)


## One vessel. The lead hull carries the full rigging; an escort keeps the
## silhouette that still reads at fit zoom without doubling the ink.
func _vessel(full: bool, alpha: float) -> void:
	var tex: Texture2D = MapSymbols.texture("ship")
	if tex == null:
		_ink_vessel(full, alpha)
		return
	# The painted hull sits on the same waterline as the ink one it replaced:
	# a 42 px hull with its keel at y = 9 and its mastheads above it.
	var side: float = 42.0
	draw_texture_rect(
		tex, Rect2(Vector2(1.0 - side * 0.5, 9.0 - side), Vector2(side, side)),
		false, Color(1.0, 1.0, 1.0, alpha)
	)
	if docked and full:
		draw_line(Vector2(0, 9), Vector2(0, 15), Color(0.16, 0.12, 0.08, 0.9), 1.4, true)
		draw_arc(
			Vector2(0, 13), 5.5, PI * 0.12, PI * 0.88, 14, Color(0.16, 0.12, 0.08, 0.9), 1.4, true
		)
	_pennant(alpha)


## The crown's pennant at the mainmasthead: the one part of the hull that must
## stay heraldic, since it is how a player tells friend from rival at a glance.
func _pennant(alpha: float) -> void:
	var flag: Color = Palette.faction_color(faction)
	flag.a = alpha
	draw_colored_polygon(
		PackedVector2Array([Vector2(2, -28), Vector2(13, -25), Vector2(2, -22)]), flag
	)


## The ink fallback, used only while the painted hull is missing.
func _ink_vessel(full: bool, alpha: float) -> void:
	var ink := Color(0.16, 0.12, 0.08, 0.9 * alpha)
	var hull := Color(0.30, 0.21, 0.13, alpha)
	var sail := Color(0.96, 0.92, 0.81, alpha)
	var flag: Color = Palette.faction_color(faction)
	flag.a = alpha

	var shell := PackedVector2Array([
		Vector2(-15, 0), Vector2(-11, 6), Vector2(0, 8), Vector2(11, 6), Vector2(15, 0)
	])
	draw_colored_polygon(shell, hull)
	draw_polyline(shell, ink, 1.2, true)
	draw_line(Vector2(-15, 0), Vector2(15, 0), ink, 1.4, true)
	if docked and full:
		draw_line(Vector2(0, 1), Vector2(0, 13), ink, 1.4, true)
		draw_arc(Vector2(0, 11), 5.5, PI * 0.12, PI * 0.88, 14, ink, 1.4, true)
		draw_circle(Vector2(0, 0), 1.6, ink)
	# stern castle and bowsprit
	draw_rect(Rect2(-15, -6, 7, 6), hull)
	draw_rect(Rect2(-15, -6, 7, 6), ink, false, 1.0)
	draw_line(Vector2(15, 0), Vector2(23, -7), ink, 1.4, true)

	# masts and sails: the lead carries two, an escort one
	var masts: Array = [
		{"x": -5.0, "top": -25.0, "sail_top": -22.0, "sail_bottom": -9.0},
		{"x": 6.0, "top": -21.0, "sail_top": -18.0, "sail_bottom": -8.0},
	]
	if not full:
		masts = [masts[0]]
	for mast: Dictionary in masts:
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
		PackedVector2Array([Vector2(-5, -25), Vector2(3, -23), Vector2(-5, -21)]), flag
	)


## Hull count on a parchment drum and the gold gauge of fighting strength. A
## lone hull keeps the gauge and drops the badge: one vessel needs no count.
func _squadron_badge() -> void:
	var ink := Color(0.16, 0.12, 0.08, 0.9)
	var base: float = 23.0 if docked else 17.0
	if hull_count > 1:
		draw_circle(Vector2(0, base), 7.0, Color(0.96, 0.92, 0.81, 0.95))
		draw_arc(Vector2(0, base), 7.0, 0, TAU, 20, ink, 1.1, true)
		draw_string(
			ThemeDB.fallback_font, Vector2(-7, base + 4), str(hull_count),
			HORIZONTAL_ALIGNMENT_CENTER, 14, 11, ink
		)
	var bar := Vector2(-11.0, base + 10.0)
	draw_rect(Rect2(bar, Vector2(22, 3)), Color(0.10, 0.08, 0.06, 0.55))
	draw_rect(
		Rect2(bar, Vector2(22.0 * clampf(strength / GAUGE_MAX, 0.0, 1.0), 3)), Palette.GOLD
	)
	draw_rect(Rect2(bar, Vector2(22, 3)), ink, false, 0.8)
	if not detail:
		return
	draw_string(
		ThemeDB.fallback_font, Vector2(-20, bar.y + 14), "%.1f" % strength,
		HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color(0.99, 0.93, 0.72, 0.95)
	)
