class_name QuickBattleField
extends Control
## Animated battlefield plate for Quick Battle. Pure presentation: it reads the
## battle record and paints a bright, period field — two colours of regiment
## blocks, waving standards, cannon smoke, muzzle flashes and a cavalry charge
## (REQ-P1-02, REQ-P1-04). No rule outcome is decided here (REQ-P2-03).

const MAX_BLOCKS: int = 12
const HORIZON: float = 0.60

var attacker_color: Color = Palette.CRIMSON
var defender_color: Color = Palette.NAVY
var attacker_count: int = 0
var defender_count: int = 0
var attacker_start: int = 1
var defender_start: int = 1
var guns: int = 0
var round_index: int = 0
var outcome: int = -1

var _time: float = 0.0
var _flash: float = 0.0
var _smoke: float = 0.0
var _charge: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_flash = maxf(0.0, _flash - delta * 2.6)
	_smoke = maxf(0.0, _smoke - delta * 0.7)
	_charge = maxf(0.0, _charge - delta * 0.55)
	queue_redraw()


func set_battle(battle: Dictionary) -> void:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	attacker_color = Palette.faction_color(int(battle.get("attacker", 0)))
	defender_color = Palette.faction_color(int(battle.get("defender", 1)))
	attacker_start = maxi(1, int(quick.get("attacker_start", 1)))
	defender_start = maxi(1, int(quick.get("defender_start", 1)))
	attacker_count = int(quick.get("attacker_start", attacker_start))
	defender_count = int(quick.get("defender_start", defender_start))
	guns = int(quick.get("guns_start", 0))
	round_index = 0
	outcome = -1
	_flash = 0.0
	_smoke = 0.0
	_charge = 0.0
	queue_redraw()


func set_round(index: int, atk: int, def: int, guns_left: int) -> void:
	round_index = index
	attacker_count = atk
	defender_count = def
	guns = guns_left
	_flash = 1.0
	_smoke = 1.0
	_charge = 1.0 if index > 0 else 0.6
	queue_redraw()


func set_outcome(value: int) -> void:
	outcome = value
	_flash = 1.0
	_smoke = 1.0
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 1.0 or h <= 1.0:
		return
	_draw_sky(w, h)
	_draw_ground(w, h)
	_draw_armies(w, h)
	_draw_effects(w, h)


func _draw_sky(w: float, h: float) -> void:
	var horizon: float = h * HORIZON
	var top := Color(0.20, 0.34, 0.55)
	var low := Color(0.96, 0.72, 0.38)
	for band in 14:
		var t: float = float(band) / 13.0
		var color: Color = top.lerp(low, t)
		draw_rect(Rect2(0.0, horizon * t, w, horizon / 13.0 + 1.0), color)
	# Sun and its halo.
	var sun := Vector2(w * 0.78, horizon * 0.42)
	for ring in 4:
		draw_circle(sun, 26.0 + float(ring) * 12.0, Color(1.0, 0.86, 0.52, 0.10))
	draw_circle(sun, 24.0, Color(1.0, 0.93, 0.66))
	# Distant hills.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, horizon), Vector2(w * 0.18, horizon * 0.72),
		Vector2(w * 0.36, horizon), Vector2(w * 0.55, horizon * 0.78),
		Vector2(w * 0.78, horizon), Vector2(w, horizon * 0.80), Vector2(w, horizon),
	]), Color(0.42, 0.50, 0.38, 0.85))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, horizon), Vector2(w * 0.28, horizon * 0.86),
		Vector2(w * 0.52, horizon), Vector2(w * 0.72, horizon * 0.88),
		Vector2(w, horizon), Vector2(w, horizon), Vector2(0, horizon),
	]), Color(0.33, 0.42, 0.30, 0.9))


func _draw_ground(w: float, h: float) -> void:
	var horizon: float = h * HORIZON
	draw_rect(Rect2(0, horizon, w, h - horizon), Color(0.55, 0.62, 0.34))
	draw_rect(Rect2(0, horizon + (h - horizon) * 0.35, w, h), Color(0.47, 0.55, 0.29))
	draw_rect(Rect2(0, horizon + (h - horizon) * 0.72, w, h), Color(0.38, 0.46, 0.24))
	# Grass tufts and wildflowers.
	for index in 26:
		var x: float = fmod(float(index) * 97.0 + 13.0, w)
		var y: float = horizon + 8.0 + fmod(float(index) * 53.0, h - horizon - 12.0)
		var sway: float = sin(_time * 1.4 + float(index)) * 2.0
		draw_line(Vector2(x, y), Vector2(x + sway, y - 7.0), Color(0.30, 0.40, 0.20), 1.4)
		if index % 5 == 0:
			draw_circle(Vector2(x + sway, y - 8.0), 1.8, Color(0.95, 0.82, 0.35))


func _draw_armies(w: float, h: float) -> void:
	var ground: float = h * 0.74
	var push: float = minf(float(round_index), 3.0) * w * 0.035
	_draw_formation(w * 0.24 + push, ground, attacker_count, attacker_start, attacker_color, 1.0)
	_draw_formation(w * 0.76 - push, ground, defender_count, defender_start, defender_color, -1.0)
	_draw_cannon(Vector2(w * 0.10 + push, ground + 4.0), attacker_color, 1.0)
	_draw_cannon(Vector2(w * 0.90 - push, ground + 4.0), defender_color, -1.0)
	if guns > 0:
		for index in guns:
			_draw_cannon(
				Vector2(w * 0.84 - push + float(index) * 16.0, ground - 10.0),
				defender_color, -1.0
			)


func _draw_formation(
	x: float, y: float, count: int, start: int, color: Color, facing: float
) -> void:
	var shown: int = clampi(count, 0, MAX_BLOCKS)
	var spacing: float = 15.0
	var width: float = float(maxi(shown - 1, 0)) * spacing
	var origin: float = x - width * 0.5
	for index in shown:
		var bob: float = sin(_time * 3.0 + float(index) * 0.7) * 1.2
		_draw_soldier(Vector2(origin + float(index) * spacing, y + bob), color, facing, index)
	# A standard every fourth file, and a colour party at the centre.
	for index in shown:
		if index % 4 == 0:
			_draw_standard(Vector2(origin + float(index) * spacing, y - 6.0), color, index)
	# Faded ghosts mark the regiments already lost.
	var lost: int = maxi(0, start - count)
	for index in mini(lost, 6):
		var gx: float = origin - 12.0 - float(index) * 9.0 * facing
		draw_circle(Vector2(gx, y + 2.0), 3.0, Color(0.15, 0.12, 0.09, 0.18))


func _draw_soldier(pos: Vector2, color: Color, facing: float, index: int) -> void:
	var ink := Color(0.14, 0.11, 0.08, 0.9)
	draw_rect(Rect2(pos.x - 2.4, pos.y - 8.0, 4.8, 9.0), color)
	draw_circle(Vector2(pos.x, pos.y - 10.0), 2.4, Color(0.93, 0.80, 0.62))
	draw_rect(Rect2(pos.x - 3.0, pos.y - 12.0, 6.0, 2.0), ink)
	draw_line(
		Vector2(pos.x + 2.0 * facing, pos.y - 7.0),
		Vector2(pos.x + 7.0 * facing, pos.y - 13.0), ink, 1.2
	)
	if index % 3 == 0:
		draw_line(Vector2(pos.x, pos.y - 1.0), Vector2(pos.x, pos.y + 2.0), ink, 1.0)


func _draw_standard(pos: Vector2, color: Color, index: int) -> void:
	var wave: float = sin(_time * 2.2 + float(index)) * 2.0
	draw_line(pos, pos + Vector2(0, -22), Color(0.20, 0.15, 0.10), 1.4)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0, -22), pos + Vector2(13 + wave, -19),
		pos + Vector2(11 + wave, -10), pos + Vector2(0, -12),
	]), color.lightened(0.12))
	draw_circle(pos + Vector2(5, -16), 1.6, Palette.GOLD_PALE)


func _draw_cannon(pos: Vector2, color: Color, facing: float) -> void:
	var ink := Color(0.16, 0.13, 0.10)
	draw_circle(pos + Vector2(-4, 2), 4.0, Color(0.30, 0.22, 0.14))
	draw_circle(pos + Vector2(4, 2), 4.0, Color(0.30, 0.22, 0.14))
	draw_line(pos + Vector2(0, -2), pos + Vector2(12.0 * facing, -7), ink, 4.0)
	draw_circle(pos + Vector2(0, -2), 2.4, color.darkened(0.2))
	if _flash > 0.0:
		var muzzle := pos + Vector2(14.0 * facing, -8)
		draw_circle(muzzle, 7.0 * _flash, Color(1.0, 0.85, 0.35, 0.85))
		draw_circle(muzzle, 3.0 * _flash, Color(1.0, 0.98, 0.80))


func _draw_effects(w: float, h: float) -> void:
	var ground: float = h * 0.74
	# Powder smoke drifting across the centre.
	if _smoke > 0.0:
		for index in 7:
			var t: float = fmod(_time * 0.35 + float(index) * 0.14, 1.0)
			var x: float = w * 0.5 + sin(float(index) * 2.1) * w * 0.18
			var y: float = ground - 10.0 - t * 34.0
			draw_circle(Vector2(x, y), 8.0 + t * 12.0, Color(0.92, 0.90, 0.84, 0.16 * _smoke))
	# Muzzle flashes along the firing line.
	if _flash > 0.0:
		for index in 5:
			var x: float = w * 0.5 + (float(index) - 2.0) * w * 0.09
			draw_circle(Vector2(x, ground - 12.0), 4.0 * _flash, Color(1.0, 0.88, 0.42, 0.8))
	# Cavalry sweeps across during an assault round.
	if _charge > 0.0:
		var sweep: float = 1.0 - _charge
		for index in 3:
			var x: float = w * (0.18 + sweep * 0.55) + float(index) * 18.0
			_draw_horse(Vector2(x, ground + 6.0 + float(index) * 3.0), attacker_color)
	# Victory rays behind the centre.
	if outcome >= 0:
		var centre := Vector2(w * 0.5, h * 0.42)
		for ray in 12:
			var angle: float = TAU * float(ray) / 12.0 + _time * 0.15
			var inner := centre + Vector2(cos(angle), sin(angle)) * 30.0
			var outer := centre + Vector2(cos(angle), sin(angle)) * (70.0 + 8.0 * sin(_time * 2.0))
			draw_line(inner, outer, Color(1.0, 0.86, 0.40, 0.22), 3.0)


func _draw_horse(pos: Vector2, color: Color) -> void:
	var ink := Color(0.18, 0.13, 0.09)
	draw_rect(Rect2(pos.x - 7.0, pos.y - 6.0, 14.0, 5.0), color.darkened(0.15))
	draw_circle(Vector2(pos.x + 8.0, pos.y - 8.0), 3.0, color.darkened(0.15))
	draw_line(Vector2(pos.x - 6.0, pos.y - 1.0), Vector2(pos.x - 8.0, pos.y + 5.0), ink, 1.4)
	draw_line(Vector2(pos.x + 5.0, pos.y - 1.0), Vector2(pos.x + 7.0, pos.y + 5.0), ink, 1.4)
	draw_circle(Vector2(pos.x, pos.y - 12.0), 2.2, Color(0.93, 0.80, 0.62))
	draw_line(Vector2(pos.x, pos.y - 10.0), Vector2(pos.x + 6.0, pos.y - 18.0), ink, 1.2)
