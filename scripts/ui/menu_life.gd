class_name MenuLife
extends Node2D
## Ambient life over the bay: gulls wheeling past the sun and warm embers
## lifting off the harbour lights. Cheap vector draws only, so the title screen
## keeps moving without any per-frame allocation (REQ-P1-04, P4-04).

const BIRD_COUNT: int = 7
const EMBER_COUNT: int = 22
const INK := Color(0.055, 0.052, 0.078, 0.62)
const WARM := Color(1.0, 0.72, 0.38)

var _birds: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	_seed()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for bird: Dictionary in _birds:
		_bird(bird)
	for ember: Dictionary in _embers:
		_ember(ember)


func _seed() -> void:
	_birds.clear()
	for i in BIRD_COUNT:
		var spawn: float = _hash01(float(i) * 7.3 + 1.0)
		_birds.append({
			"x": -60.0 + spawn * 1400.0,
			"y": 104.0 + _hash01(float(i) * 3.1) * 176.0,
			"span": 7.0 + _hash01(float(i) * 5.7) * 7.0,
			"speed": 5.0 + _hash01(float(i) * 9.4) * 7.0,
			"flap": _hash01(float(i) * 2.2) * TAU,
			"lift": 0.6 + _hash01(float(i) * 4.4) * 0.9,
		})
	_embers.clear()
	for i in EMBER_COUNT:
		var spawn: float = _hash01(float(i) * 6.1 + 4.0)
		_embers.append({
			"x": 150.0 + spawn * 400.0 + _hash01(float(i) * 1.7) * 60.0,
			"y": 400.0 + _hash01(float(i) * 8.3) * 230.0,
			"rise": 6.0 + _hash01(float(i) * 2.9) * 9.0,
			"sway": 5.0 + _hash01(float(i) * 5.5) * 9.0,
			"phase": _hash01(float(i) * 3.7) * TAU,
			"tint": 0.45 + _hash01(float(i) * 9.9) * 0.55,
		})


func _bird(bird: Dictionary) -> void:
	var span: float = bird["span"]
	var flap: float = sin(_time * 3.1 + float(bird["flap"]))
	var x: float = fposmod(float(bird["x"]) - _time * float(bird["speed"]) + 90.0, 1460.0) - 90.0
	var y: float = float(bird["y"]) + sin(_time * 0.55 + float(bird["flap"])) * 6.0
	var tip: float = -span * 0.5 * flap * float(bird["lift"])
	draw_polyline(PackedVector2Array([
		Vector2(x - span, y + tip), Vector2(x - span * 0.5, y - 1.8), Vector2(x, y),
	]), INK, 1.5, true)
	draw_polyline(PackedVector2Array([
		Vector2(x, y), Vector2(x + span * 0.5, y - 1.8), Vector2(x + span, y + tip),
	]), INK, 1.5, true)


func _ember(ember: Dictionary) -> void:
	var cycle: float = fposmod(_time * float(ember["rise"]) * 0.1 + float(ember["phase"]), 1.0)
	var x: float = float(ember["x"]) + sin(_time * 0.7 + float(ember["phase"])) * float(ember["sway"])
	var y: float = float(ember["y"]) - cycle * 170.0
	var fade: float = sin(cycle * PI) * float(ember["tint"])
	draw_circle(Vector2(x, y), 1.4, Color(WARM.r, WARM.g, WARM.b, 0.62 * fade))


func _hash01(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)
