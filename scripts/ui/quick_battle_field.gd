class_name QuickBattleField
extends Control
## Animated battlefield plate for Quick Battle. Pure presentation: it reads the
## battle record and paints a painted, period field — two colours of miniature
## regiments, waving standards, cannon smoke, muzzle flashes and a cavalry
## charge (REQ-P1-02, REQ-P1-04). No rule outcome is decided here (REQ-P2-03).

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
	BattlePlate.draw_ground(self, w, h, h * HORIZON, terrain)
	_draw_armies(w, h)
	_draw_effects(w, h)
	QuickBattleRail.draw(
		self, attacker_health, attacker_count, attacker_color,
		defender_health, defender_count, defender_color, w, h
	)
	QuickBattleRail.floaters(self, _floaters)


func _draw_armies(w: float, h: float) -> void:
	var ground: float = h * 0.74
	var soldier_h: float = BattlePlate.soldier_height(h)
	var push: float = minf(float(round_index), 3.0) * w * 0.035
	# The garrison musters on the wall's walk; a field battle meets at the line.
	var defended: float = BattlePlate.parapet_y(h, fort_level) if fort_level > 0 else ground
	if fort_level > 0:
		BattlePlate.draw_wall(self, w, h, fort_level, gates_broken, defender_color, _time)
	_draw_formation(
		Vector2(w * 0.24 + push, ground), attacker_count, attacker_start,
		attacker_color, 1.0, attacker_health
	)
	_draw_formation(
		Vector2(w * 0.80 - push, defended), defender_count, defender_start,
		defender_color, -1.0, defender_health
	)
	if guns > 0:
		for index in mini(guns, 4):
			BattlePlate.draw_cannon(
				self, Vector2(w * 0.86 - push + float(index) * 16.0, defended - 5.0),
				defender_color, -1.0, 0.0, soldier_h * 0.75
			)
	# The merlons paint over the garrison's legs: they hold the parapet.
	BattlePlate.draw_wall_crest(self, w, h, fort_level)
	BattlePlate.draw_cannon(
		self, Vector2(w * 0.10 + push, ground + 4.0), attacker_color, 1.0, _flash,
		soldier_h * 0.85
	)
	BattlePlate.draw_cannon(
		self, Vector2(w * 0.90 - push, ground + 4.0), defender_color, -1.0, _flash,
		soldier_h * 0.85
	)


func _draw_formation(
	centre: Vector2, count: int, start: int, color: Color, facing: float,
	health: Array = []
) -> void:
	var soldier_h: float = BattlePlate.soldier_height(size.y)
	var shown: int = clampi(count, 0, MAX_BLOCKS)
	var spacing: float = soldier_h * 0.66
	var width: float = float(maxi(shown - 1, 0)) * spacing
	var origin: float = centre.x - width * 0.5
	for index in shown:
		var jitter: float = _hash(float(index) * 3.0 + facing)
		var tall: float = soldier_h * (0.92 + jitter * 0.16)
		var bob: float = sin(_time * 2.6 + float(index) * 0.9) * 0.9
		var data: Dictionary = health[index] if index < health.size() else {}
		BattlePlate.draw_soldier(
			self,
			Vector2(origin + float(index) * spacing, centre.y + bob + (jitter - 0.5) * 3.0),
			tall, color, facing, index,
			float(data.get("fraction", 1.0)), int(data.get("medals", 0))
		)
	for index in shown:
		if index % 4 == 0:
			BattlePlate.draw_standard(
				self, Vector2(origin + float(index) * spacing, centre.y - soldier_h * 0.30),
				color, _time + float(index)
			)
	# Faded marks where the regiments already lost stood.
	var lost: int = maxi(0, start - count)
	for index in mini(lost, 6):
		var gx: float = origin - 12.0 - float(index) * 9.0 * facing
		draw_set_transform(Vector2(gx, centre.y + 1.0), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 5.0, Color(0.10, 0.08, 0.05, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Deterministic 0..1 from an index, so a replay of the same record looks alike.
static func _hash(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)


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
					Color(0.94, 0.91, 0.82, (0.13 - float(ring) * 0.03) * _smoke)
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
		for index in 4:
			var x: float = w * (0.12 + sweep * 0.62) + float(index) * 30.0
			var gallop: float = sin(_time * 9.0 + float(index)) * 1.6
			BattlePlate.draw_horse(
				self, Vector2(x, ground + 6.0 + float(index % 2) * 4.0 + gallop),
				attacker_color, BattlePlate.soldier_height(h) * 1.15
			)
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
