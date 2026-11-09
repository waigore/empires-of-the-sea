class_name FogLayer
extends Node2D
## Fog of war: a tile-resolution state grid projected onto one small texture and
## scaled up, so revealing a zone costs one image update instead of thousands of
## draw calls (REQ-P4-01). Pure view — `VisibilityModel` decides the levels.
##
## The texture sprite draws behind the map artwork; the painted country borders
## and selection glows above it belong to the parent view (`MapOverlay`).

const TILE_SIZE: float = 22.0
const FOG_FADE_SPEED: float = 2.6

const FOG_VISIBLE: int = 0
const FOG_FOGGED: int = 1
const FOG_UNKNOWN: int = 2

var model: MapModel = null
var fog: PackedByteArray = PackedByteArray()

var _fade: PackedFloat32Array = PackedFloat32Array()
var _image: Image = null
var _texture: ImageTexture = null
## When false, skip the per-tile fade scan (map is large; scanning every frame
## starves headless tests and burns CPU in play).
var _fade_active: bool = false
## Fade or fog state moved this frame; the parent repaints whenever this is set.
var _dirty: bool = false
var _sprite: Sprite2D = null


func build(p_model: MapModel) -> void:
	model = p_model
	var count: int = model.width * model.height
	fog.resize(count)
	fog.fill(FOG_VISIBLE)
	_fade.resize(count)
	_fade.fill(0.0)
	_image = Image.create(model.width, model.height, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.centered = false
	_sprite.scale = Vector2(TILE_SIZE, TILE_SIZE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/fog.gdshader")
	var texel := Vector2(1.0 / float(model.width), 1.0 / float(model.height))
	material.set_shader_parameter("texel", texel)
	material.set_shader_parameter("map_tiles", Vector2(float(model.width), float(model.height)))
	material.set_shader_parameter("tile_size", TILE_SIZE)
	_sprite.material = material
	add_child(_sprite)
	_dirty = true


func set_fog_state(tile_index: int, state: int) -> void:
	if tile_index < 0 or tile_index >= fog.size():
		return
	if fog[tile_index] == state:
		return
	fog[tile_index] = state
	_dirty = true
	_fade_active = true


func set_fog_rect(rect: Rect2i, state: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if model.in_bounds(x, y):
				set_fog_state(model.index_of(x, y), state)


## Projects rules-engine visibility onto the fog texture (view reads state).
## `indices` are the tiles that changed; empty means resync the whole map.
func sync_visibility(visibility: VisibilityModel, indices: Array = []) -> void:
	if visibility == null or model == null:
		return
	if indices.is_empty():
		for index in fog.size():
			set_fog_state(index, fog_state_for(visibility.level_at_index(index)))
		return
	for raw: Variant in indices:
		var index: int = int(raw)
		set_fog_state(index, fog_state_for(visibility.level_at_index(index)))


static func fog_state_for(level: int) -> int:
	match level:
		VisibilityModel.Level.FULLY_VISIBLE:
			return FOG_VISIBLE
		VisibilityModel.Level.UNKNOWN:
			return FOG_UNKNOWN
		_:
			return FOG_FOGGED


## Jumps the fade animation to the current fog targets (used on first build so
## the map does not start fully revealed).
func snap_fog() -> void:
	for i in _fade.size():
		_fade[i] = target_alpha(fog[i])
	_dirty = true
	_fade_active = false


func fog_state_at(x: int, y: int) -> int:
	if model == null or not model.in_bounds(x, y):
		return FOG_UNKNOWN
	return fog[model.index_of(x, y)]


## Advances the fade toward each tile's target opacity and repaints when it
## moved. Returns whether the fog texture changed this frame, so the parent view
## knows its above-fog artwork must be repainted too.
func advance(delta: float) -> bool:
	if _fade_active:
		var animating: bool = false
		for i in _fade.size():
			var target: float = target_alpha(fog[i])
			var current: float = _fade[i]
			if absf(current - target) > 0.002:
				_fade[i] = move_toward(current, target, delta * FOG_FADE_SPEED)
				animating = true
		_dirty = _dirty or animating
		_fade_active = animating
	if not _dirty:
		return false
	_rebuild()
	return true


## True while the reveal fade is still running.
func is_fading() -> bool:
	return _fade_active


## Fog opacity a tile settles at: none, a thin mist over charted land, or paper
## covering the unknown.
static func target_alpha(state: int) -> float:
	match state:
		FOG_FOGGED:
			return 0.55
		FOG_UNKNOWN:
			return 1.0
	return 0.0


func _rebuild() -> void:
	_dirty = false
	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			var amount: float = _fade[index]
			if amount <= 0.004:
				_image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var state: int = fog[index]
			if state == FOG_UNKNOWN:
				var paper: Color = Palette.PAPER
				_image.set_pixel(x, y, Color(paper.r, paper.g, paper.b, amount))
			else:
				_image.set_pixel(x, y, Color(0.80, 0.82, 0.79, amount * 0.48))
	_texture.update(_image)
