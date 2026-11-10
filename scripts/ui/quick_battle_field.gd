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
## The ground and the wall a siege is fought through (wiki: quick-battle §
## Terrain, siege-mechanics § Gates). Presentation only: these come from the
## battle record, never from a recomputation.
var terrain: String = "open"
var fort_level: int = 0
var gates_broken: int = 0
## Regiment condition as the report recorded it: each survivor's health
## fraction and chevrons. Empty means "full, unblooded" (a plate fixture).
var attacker_health: Array = []
var defender_health: Array = []

var _time: float = 0.0
var _flash: float = 0.0
var _smoke: float = 0.0
var _charge: float = 0.0
## Floating "-N" damage numbers, so a blow is read the instant it lands.
var _floaters: Array[Dictionary] = []


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
	for floater: Dictionary in _floaters:
		floater["life"] = float(floater["life"]) - delta
		floater["pos"] = (floater["pos"] as Vector2) - Vector2(0.0, delta * 26.0)
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return float(f["life"]) > 0.0)
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
	terrain = String(quick.get("terrain", "open"))
	fort_level = int(battle.get("fort_level", 0))
	gates_broken = int((quick.get("gates", {}) as Dictionary).get("broken", 0))
	attacker_health = []
	defender_health = []
	round_index = 0
	outcome = -1
	_flash = 0.0
	_smoke = 0.0
	_charge = 0.0
	_floaters.clear()
	queue_redraw()


func set_round(
	index: int,
	atk: int,
	def: int,
	guns_left: int,
	atk_health: Array = [],
	def_health: Array = [],
	gates: int = 0
) -> void:
	round_index = index
	attacker_count = atk
	defender_count = def
	guns = guns_left
	gates_broken = gates
	attacker_health = atk_health
	defender_health = def_health
	_flash = 1.0
	_smoke = 1.0
	_charge = 1.0
	queue_redraw()


## Queues the "-N" numbers one action's hits produced over the side it hurt.
func add_hits(side: String, hits: Array, color: Color) -> void:
	var base: float = size.x * (0.30 if side == "attacker" else 0.70)
	var ground: float = size.y * 0.74
	for index in hits.size():
		var hit: Dictionary = hits[index]
		var spread: float = (float(index) - float(hits.size()) * 0.5) * 24.0
		_floaters.append({
			"text": "-%d" % int(hit.get("damage", 0)),
			"pos": Vector2(base + spread, ground - 40.0 - float(index % 3) * 9.0),
			"life": 1.1,
			"color": color.lightened(0.35),
		})


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
	QuickBattleRail.draw(
		self, attacker_health, attacker_count, attacker_color,
		defender_health, defender_count, defender_color, w, h
	)
	QuickBattleRail.floaters(self, _floaters)


func _draw_sky(w: float, h: float) -> void:
	var horizon: float = h * HORIZON
	var top := Color(0.13, 0.30, 0.56)
	var mid := Color(0.46, 0.62, 0.70)
	var low := Color(0.99, 0.76, 0.36)
	for band in 18:
		var t: float = float(band) / 17.0
		var color: Color = top.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(low, (t - 0.5) * 2.0)
		draw_rect(Rect2(0.0, horizon * t, w, horizon / 17.0 + 1.0), color)
	# Warm haze along the horizon.
	draw_rect(Rect2(0, horizon - 10.0, w, 10.0), Color(1.0, 0.86, 0.55, 0.22))
	# Sun and its halo.
	var sun := Vector2(w * 0.78, horizon * 0.42)
	for ring in 5:
		draw_circle(sun, 20.0 + float(ring) * 11.0, Color(1.0, 0.86, 0.45, 0.09))
	draw_circle(sun, 24.0, Color(1.0, 0.95, 0.72))
	_draw_clouds(w, horizon)
	# Distant hills.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, horizon), Vector2(w * 0.18, horizon * 0.72),
		Vector2(w * 0.36, horizon), Vector2(w * 0.55, horizon * 0.78),
		Vector2(w * 0.78, horizon), Vector2(w, horizon * 0.80), Vector2(w, horizon),
	]), Color(0.35, 0.55, 0.38, 0.9))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, horizon), Vector2(w * 0.28, horizon * 0.86),
		Vector2(w * 0.52, horizon), Vector2(w * 0.72, horizon * 0.88),
		Vector2(w, horizon), Vector2(w, horizon), Vector2(0, horizon),
	]), Color(0.24, 0.45, 0.27, 0.95))


func _draw_clouds(w: float, horizon: float) -> void:
	for index in 4:
		var drift: float = fmod(_time * 3.0 + float(index) * 210.0, w + 160.0) - 80.0
		var y: float = horizon * (0.16 + float(index) * 0.09)
		var scale: float = 14.0 + float(index % 2) * 7.0
		for puff in 4:
			var offset := Vector2(float(puff) * scale * 0.9, sin(float(puff) * 1.7) * 3.0)
			var centre := Vector2(drift + offset.x, y + offset.y)
			for ring in 3:
				draw_circle(
					centre, scale * (0.62 + float(ring) * 0.20),
					Color(1.0, 0.97, 0.88, 0.10 - float(ring) * 0.025)
				)


func _draw_ground(w: float, h: float) -> void:
	QuickBattleArt.draw_ground(self, w, h, h * HORIZON, terrain, _time)


func _draw_armies(w: float, h: float) -> void:
	var ground: float = h * 0.74
	var push: float = minf(float(round_index), 3.0) * w * 0.035
	# The wall stands between the armies; the garrison musters behind it.
	var defended: float = ground - (30.0 if fort_level > 0 else 0.0)
	if fort_level > 0:
		QuickBattleArt.draw_wall(self, w, h, fort_level, gates_broken, defender_color, _time)
	_draw_formation(
		w * 0.24 + push, ground, attacker_count, attacker_start, attacker_color, 1.0,
		attacker_health
	)
	_draw_formation(
		w * 0.80 - push, defended, defender_count, defender_start, defender_color, -1.0,
		defender_health
	)
	_draw_cannon(Vector2(w * 0.10 + push, ground + 4.0), attacker_color, 1.0)
	_draw_cannon(Vector2(w * 0.90 - push, ground + 4.0), defender_color, -1.0)
	if guns > 0:
		for index in guns:
			_draw_cannon(
				Vector2(w * 0.84 - push + float(index) * 16.0, defended - 10.0),
				defender_color, -1.0
			)


func _draw_formation(
	x: float,
	y: float,
	count: int,
	start: int,
	color: Color,
	facing: float,
	health: Array = []
) -> void:
	var shown: int = clampi(count, 0, MAX_BLOCKS)
	var spacing: float = 17.0
	var width: float = float(maxi(shown - 1, 0)) * spacing
	var origin: float = x - width * 0.5
	for index in shown:
		var bob: float = sin(_time * 3.0 + float(index) * 0.7) * 1.4
		var data: Dictionary = health[index] if index < health.size() else {}
		_draw_soldier(
			Vector2(origin + float(index) * spacing, y + bob), color, facing, index,
			float(data.get("fraction", 1.0)), int(data.get("medals", 0))
		)
	# A standard every fourth file, and a colour party at the centre.
	for index in shown:
		if index % 4 == 0:
			_draw_standard(Vector2(origin + float(index) * spacing, y - 6.0), color, index)
	# Faded ghosts mark the regiments already lost.
	var lost: int = maxi(0, start - count)
	for index in mini(lost, 6):
		var gx: float = origin - 13.0 - float(index) * 10.0 * facing
		draw_circle(Vector2(gx, y + 2.0), 3.4, Color(0.12, 0.09, 0.06, 0.20))


func _draw_soldier(
	pos: Vector2, color: Color, facing: float, index: int,
	health: float = 1.0, medals: int = 0
) -> void:
	var ink := Color(0.10, 0.08, 0.05, 0.95)
	## A mauled regiment is a paler, bloodier block; the bar under its feet is
	## the number at a glance (REQ-P1-07, REQ-P5-05).
	var bright: Color = color.lightened(0.10).lerp(Palette.CRIMSON, (1.0 - health) * 0.55)
	draw_rect(Rect2(pos.x - 3.2, pos.y - 10.0, 6.4, 11.0), bright)
	draw_rect(Rect2(pos.x - 3.2, pos.y - 10.0, 6.4, 2.0), color.darkened(0.18))
	draw_circle(Vector2(pos.x, pos.y - 12.8), 3.0, Color(0.98, 0.83, 0.62))
	draw_rect(Rect2(pos.x - 3.8, pos.y - 15.6, 7.6, 2.6), ink)
	draw_line(
		Vector2(pos.x + 2.6 * facing, pos.y - 9.0),
		Vector2(pos.x + 9.0 * facing, pos.y - 16.0), ink, 1.4
	)
	draw_line(Vector2(pos.x, pos.y - 1.0), Vector2(pos.x, pos.y + 2.4), ink, 1.1)
	if index % 3 == 0:
		draw_circle(Vector2(pos.x, pos.y - 6.0), 1.2, Palette.GOLD_PALE)
	_draw_health(pos, health)
	if medals > 0:
		draw_texture_rect(
			ChromeIcons.texture("chevron"),
			Rect2(pos.x - 4.0, pos.y - 24.0, 8.0, 8.0), false,
			Color(1.0, 1.0, 1.0, 0.55 + 0.1 * float(medals))
		)


func _draw_health(pos: Vector2, fraction: float) -> void:
	var clamped: float = clampf(fraction, 0.0, 1.0)
	var fill: Color = Palette.HEALTH_HIGH.lerp(Palette.HEALTH_LOW, 1.0 - clamped)
	draw_rect(Rect2(pos.x - 4.6, pos.y + 2.6, 9.2, 2.2), Color(0.08, 0.06, 0.04, 0.85))
	if clamped > 0.0:
		draw_rect(Rect2(pos.x - 4.6, pos.y + 2.6, 9.2 * clamped, 2.2), fill)


func _draw_standard(pos: Vector2, color: Color, index: int) -> void:
	var wave: float = sin(_time * 2.2 + float(index)) * 2.6
	draw_line(pos, pos + Vector2(0, -28), Color(0.16, 0.11, 0.06), 1.8)
	var cloth: Color = color.lightened(0.18)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0, -28), pos + Vector2(18 + wave, -24),
		pos + Vector2(15 + wave, -12), pos + Vector2(0, -15),
	]), cloth)
	draw_polyline(PackedVector2Array([
		pos + Vector2(0, -28), pos + Vector2(18 + wave, -24),
		pos + Vector2(15 + wave, -12), pos + Vector2(0, -15), pos + Vector2(0, -28),
	]), Palette.GOLD, 1.0, true)
	draw_circle(pos + Vector2(6, -20), 2.2, Palette.GOLD_PALE)


func _draw_cannon(pos: Vector2, color: Color, facing: float) -> void:
	var bronze := Color(0.55, 0.38, 0.16)
	draw_circle(pos + Vector2(-5, 3), 5.0, Color(0.26, 0.18, 0.10))
	draw_circle(pos + Vector2(5, 3), 5.0, Color(0.26, 0.18, 0.10))
	draw_line(pos + Vector2(0, -3), pos + Vector2(16.0 * facing, -9), bronze, 6.0)
	draw_line(pos + Vector2(0, -3), pos + Vector2(16.0 * facing, -9), Color(0.78, 0.58, 0.24), 2.0)
	draw_circle(pos + Vector2(0, -3), 3.0, color.darkened(0.15))
	if _flash > 0.0:
		var muzzle := pos + Vector2(19.0 * facing, -10)
		draw_circle(muzzle, 10.0 * _flash, Color(1.0, 0.82, 0.30, 0.85))
		draw_circle(muzzle, 5.0 * _flash, Color(1.0, 0.99, 0.86))


func _draw_effects(w: float, h: float) -> void:
	var ground: float = h * 0.74
	# Powder smoke drifting across the centre, thickest near the guns.
	if _smoke > 0.0:
		for index in 11:
			var t: float = fmod(_time * 0.30 + float(index) * 0.11, 1.0)
			var x: float = w * 0.5 + sin(float(index) * 2.1) * w * 0.22
			var y: float = ground - 8.0 - t * 40.0
			var radius: float = 9.0 + t * 16.0
			for ring in 3:
				draw_circle(
					Vector2(x, y), radius * (0.55 + float(ring) * 0.22),
					Color(0.94, 0.91, 0.82, (0.12 - float(ring) * 0.03) * _smoke)
				)
	# Muzzle flashes along the firing line.
	if _flash > 0.0:
		for index in 7:
			var x: float = w * 0.5 + (float(index) - 3.0) * w * 0.075
			draw_circle(Vector2(x, ground - 14.0), 5.0 * _flash, Color(1.0, 0.86, 0.36, 0.9))
			draw_circle(Vector2(x, ground - 14.0), 2.2 * _flash, Color(1.0, 0.99, 0.88))
	# Cavalry sweeps across during an assault round.
	if _charge > 0.0:
		var sweep: float = 1.0 - _charge
		for index in 6:
			var x: float = w * (0.12 + sweep * 0.62) + float(index) * 21.0
			_draw_horse(Vector2(x, ground + 7.0 + float(index % 2) * 4.0), attacker_color)
	# Warm light shafts and gold sparkles celebrate a decided field.
	if outcome >= 0:
		for shaft in 6:
			var x: float = w * (0.10 + float(shaft) * 0.16)
			draw_line(
				Vector2(x, 0), Vector2(x + 40.0, ground),
				Color(1.0, 0.90, 0.56, 0.05), 18.0
			)
		for spark in 14:
			var angle: float = TAU * float(spark) / 14.0 + _time * 0.35
			var radius: float = 60.0 + 12.0 * sin(_time * 2.0 + float(spark))
			var centre := Vector2(w * 0.5, h * 0.36)
			draw_circle(
				centre + Vector2(cos(angle), sin(angle)) * radius, 2.0,
				Color(1.0, 0.88, 0.42, 0.55)
			)


func _draw_horse(pos: Vector2, color: Color) -> void:
	var ink := Color(0.14, 0.09, 0.05)
	draw_rect(Rect2(pos.x - 11.0, pos.y - 9.0, 22.0, 7.0), color.lightened(0.05))
	draw_circle(Vector2(pos.x + 12.0, pos.y - 11.0), 4.2, color.lightened(0.05))
	draw_line(Vector2(pos.x - 10.0, pos.y - 2.0), Vector2(pos.x - 13.0, pos.y + 7.0), ink, 2.0)
	draw_line(Vector2(pos.x + 9.0, pos.y - 2.0), Vector2(pos.x + 12.0, pos.y + 7.0), ink, 2.0)
	draw_circle(Vector2(pos.x, pos.y - 17.0), 3.0, Color(0.98, 0.83, 0.62))
	draw_line(Vector2(pos.x, pos.y - 14.0), Vector2(pos.x + 10.0, pos.y - 26.0), ink, 1.8)
	draw_circle(Vector2(pos.x + 10.0, pos.y - 26.0), 1.6, Palette.GOLD_PALE)
