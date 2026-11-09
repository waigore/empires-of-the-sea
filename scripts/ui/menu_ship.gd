class_name MenuShip
extends Node2D
## A carrack silhouette cut from a painted plate (fal), riding the bay. It bobs
## and heels on the swell, trails a broken reflection and shows her stern
## lanterns, so the open water stays alive without any per-frame texture work
## (REQ-P1-02, P1-04, P4-04).

const HULL: Texture2D = preload("res://assets/art/menu/carrack.png")
const MIRROR: Texture2D = preload("res://assets/art/menu/carrack_reflection.png")
const RIPPLE: Shader = preload("res://ui/shaders/menu_reflection.gdshader")
const SILHOUETTE: Shader = preload("res://ui/shaders/menu_silhouette.gdshader")
const WARM := Color(1.0, 0.74, 0.40)

var width: float = 340.0
var water_y: float = 648.0
var origin_x: float = 960.0
var speed: float = 0.0
var heading: float = 1.0
var facing: float = 1.0
var bounds: Vector2 = Vector2(-420.0, 1700.0)
var phase: float = 0.0
var with_reflection: bool = true
var with_lanterns: bool = true

var _x: float = 0.0
var _clock: float = 0.0
var _unit: float = 1.0
var _height: float = 1.0
var _body: Sprite2D = null


func _ready() -> void:
	var tex_size: Vector2 = HULL.get_size()
	_unit = width / maxf(tex_size.x, 1.0)
	_height = tex_size.y * _unit
	_x = origin_x
	_body = Sprite2D.new()
	_body.texture = HULL
	_body.scale = Vector2(_unit, _unit)
	_body.flip_h = facing < 0.0
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Sink the keel a hair below the waterline so she sits in, not on, the sea.
	_body.position = Vector2(0.0, -_height * 0.5 + _height * 0.015)
	var material := ShaderMaterial.new()
	material.shader = SILHOUETTE
	material.set_shader_parameter("flip", 1.0 if facing < 0.0 else 0.0)
	_body.material = material
	add_child(_body)
	if with_reflection:
		_build_reflection()
	position = Vector2(_x, water_y)
	set_process(true)


func _build_reflection() -> void:
	var mirror := Sprite2D.new()
	mirror.texture = MIRROR
	mirror.centered = true
	mirror.scale = Vector2(_unit * facing, _unit * 0.55)
	mirror.position = Vector2(0.0, _height * 0.55 * 0.5)
	mirror.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var material := ShaderMaterial.new()
	material.shader = RIPPLE
	mirror.material = material
	add_child(mirror)


func _process(delta: float) -> void:
	advance(delta)


## Moves the hull and its bobbing pose. Public so tests can step it directly.
func advance(delta: float) -> void:
	_clock += delta
	if speed != 0.0:
		_x += speed * heading * delta
		if _x > bounds.y:
			_x = bounds.x
		elif _x < bounds.x:
			_x = bounds.y
	var bob: float = sin(_clock * 0.58 + phase) * width * 0.012
	var heel: float = sin(_clock * 0.43 + phase + 0.9) * 0.012
	position = Vector2(_x, water_y + bob)
	rotation = heel * heading
	modulate.a = _edge_fade()
	queue_redraw()


## Drops the hull at a lane position. Public so tests and scene tools can
## place it without touching the private motion state.
func place_at(x: float) -> void:
	_x = x
	position = Vector2(_x, water_y)
	modulate.a = _edge_fade()


## Ships dissolve at the edges of their lane instead of popping in.
func _edge_fade() -> float:
	if speed == 0.0:
		return 1.0
	var margin: float = 170.0
	return clampf(minf((_x - bounds.x) / margin, (bounds.y - _x) / margin), 0.0, 1.0)


func _draw() -> void:
	_draw_waterline()
	if speed != 0.0:
		_draw_wake()
	if with_lanterns:
		_draw_lanterns()


## Contact shadow and foam, so the keel meets the painted water instead of
## hovering over it.
func _draw_waterline() -> void:
	var half: float = width * 0.42 * facing
	var shadow := Color(0.028, 0.030, 0.042, 0.32)
	draw_line(Vector2(-half, 2.0), Vector2(half, 2.0), shadow, 6.0, true)
	draw_line(Vector2(-half * 0.74, 4.5), Vector2(half * 0.74, 4.5), shadow, 9.0, true)
	var foam := Color(0.96, 0.88, 0.72, 0.15)
	for i in 7:
		var t: float = float(i) / 6.0
		var x: float = lerpf(-half, half, t) + sin(_clock * 1.1 + t * 5.0) * 2.0
		var lift: float = 1.0 + sin(_clock * 1.3 + t * 7.0) * 1.2
		draw_line(Vector2(x, lift), Vector2(x + width * 0.028 * facing, lift - 0.6), foam, 1.5, true)


## Two lanterns astern, one on the sterncastle and one at the taffrail.
func _draw_lanterns() -> void:
	var pulse: float = 0.55 + 0.45 * sin(_clock * 1.7 + phase)
	for spot: Vector2 in [Vector2(-0.452, -0.235), Vector2(-0.474, -0.155)]:
		var local := Vector2(spot.x * width * facing, spot.y * _height)
		draw_circle(local, width * 0.020, Color(WARM.r, WARM.g, WARM.b, 0.10 * pulse))
		draw_circle(local, width * 0.006, Color(WARM.r, WARM.g, WARM.b, 0.85))
		draw_circle(local, width * 0.0026, Color(1.0, 0.95, 0.82))


func _draw_wake() -> void:
	var foam := Color(0.92, 0.85, 0.72, 0.14)
	for i in 3:
		var back: float = float(i + 1) * 0.09 * width * heading
		var stern_x: float = -0.46 * width * facing - back
		draw_line(Vector2(stern_x, 2.0 + float(i) * 2.0),
			Vector2(stern_x - 0.10 * width * heading, 4.0 + float(i) * 2.4),
			Color(foam.r, foam.g, foam.b, foam.a - float(i) * 0.03), 1.4, true)
