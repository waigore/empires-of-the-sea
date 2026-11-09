class_name MenuBackdrop
extends Control
## Living title backdrop: a fal-painted colonial harbour at dusk. The painting
## is the far plane (slow breath of pan and zoom); light, haze, cloud shadow,
## carracks, gulls and embers are composited on top so the harbour keeps moving
## (REQ-P1-02, P1-04, P1-05).

const DESIGN: Vector2 = Vector2(1280.0, 720.0)
const OVERSCAN: float = 1.06
const DRIFT: float = 7.0

const PLATE: Texture2D = preload("res://assets/art/menu/dusk_harbour.png")
const ATMOSPHERE: Shader = preload("res://ui/shaders/menu_atmosphere.gdshader")
const CLOUDS: Shader = preload("res://ui/shaders/cloudshade.gdshader")
const SCRIM: Shader = preload("res://ui/shaders/menu_scrim.gdshader")
const VIGNETTE: Shader = preload("res://ui/shaders/vignette.gdshader")
const GRAIN: Shader = preload("res://ui/shaders/grain.gdshader")

var stage: Node2D = null
var plate: Sprite2D = null
var life: MenuLife = null
var ships: Array[MenuShip] = []

var _base: Vector2 = Vector2.ZERO
var _clock: float = 0.0
var _plate_unit: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(func() -> void: fit(size))
	fit(size)
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	# The painting breathes: a very slow zoom with a drifting frame.
	var breathe: float = 1.0 + 0.018 * sin(_clock * 0.045)
	plate.scale = Vector2.ONE * _plate_unit * breathe
	plate.position = DESIGN * 0.5 + Vector2(
		sin(_clock * 0.031) * 9.0, sin(_clock * 0.047) * 5.0
	)
	stage.position = _base + Vector2(
		sin(_clock * 0.09) * DRIFT, sin(_clock * 0.06) * DRIFT * 0.6
	)


func _build() -> void:
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	_build_plate()
	_build_weather()
	life = MenuLife.new()
	life.name = "Life"
	stage.add_child(life)
	# Far carrack first, hero last so she sails in front of the painted fort.
	_add_ship(Vector2(1190.0, 506.0), 100.0, -7.0, -1.0, 2.4)
	_add_ship(Vector2(1005.0, 655.0), 336.0, 7.0, 1.0, 0.3)
	_build_grade()


func _build_plate() -> void:
	plate = Sprite2D.new()
	plate.name = "Plate"
	plate.texture = PLATE
	plate.centered = true
	plate.position = DESIGN * 0.5
	_plate_unit = DESIGN.x / maxf(PLATE.get_width(), 1.0)
	plate.scale = Vector2.ONE * _plate_unit
	stage.add_child(plate)


## Cloud shadow and the animated light pass sit in design space, not on the
## painting, so their density stays constant as the plate zooms.
func _build_weather() -> void:
	var clouds := ColorRect.new()
	clouds.size = DESIGN
	clouds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = CLOUDS
	cloud_material.set_shader_parameter("world_size", DESIGN)
	cloud_material.set_shader_parameter("strength", 0.12)
	cloud_material.set_shader_parameter("speed", 0.0075)
	cloud_material.set_shader_parameter("scale", 2.1)
	clouds.material = cloud_material
	stage.add_child(clouds)

	var light := ColorRect.new()
	light.size = DESIGN
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var light_material := ShaderMaterial.new()
	light_material.shader = ATMOSPHERE
	light.material = light_material
	stage.add_child(light)


func _add_ship(
	origin: Vector2, width: float, speed: float, facing: float, phase: float
) -> MenuShip:
	var ship := MenuShip.new()
	ship.width = width
	ship.water_y = origin.y
	ship.origin_x = origin.x
	ship.speed = speed
	ship.heading = facing
	ship.facing = facing
	ship.phase = phase
	stage.add_child(ship)
	ships.append(ship)
	return ship


## Scrim, vignette and paper grain tie the painting to the printed HUD.
func _build_grade() -> void:
	_add_grade_layer(SCRIM, {
		"tint": Color(0.014, 0.017, 0.028, 0.60),
		"spread": 0.60,
	})
	_add_grade_layer(VIGNETTE, {
		"tint": Color(0.035, 0.030, 0.045),
		"strength": 0.62,
		"inner": 0.34,
		"outer": 0.96,
	})
	_add_grade_layer(GRAIN, {"strength": 0.05, "scale": 0.7})


func _add_grade_layer(shader: Shader, params: Dictionary) -> void:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in params:
		material.set_shader_parameter(key, params[key])
	rect.material = material


## Cover-fits the stage to a viewport in design units. Public so layout tests
## can drive it without a rendered frame.
func fit(view: Vector2) -> void:
	if view.x < 1.0 or view.y < 1.0:
		return
	var factor: float = maxf(view.x / DESIGN.x, view.y / DESIGN.y) * OVERSCAN
	stage.scale = Vector2.ONE * factor
	_base = (view - DESIGN * factor) * 0.5
	stage.position = _base


## The design-space rect the stage currently covers, for layout assertions.
func stage_rect() -> Rect2:
	return Rect2(stage.position, DESIGN * stage.scale.x)
