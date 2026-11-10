class_name MapWash
extends RefCounted
## Tile-resolution terrain colour, height, and the land drop shadow.
## The paint itself is baked at sub-tile resolution by `MapRelief`; the shader
## shades everything finer than one of its texels (REQ-P1-03).

## How far owned land moves toward its crown's heraldic colour. Ownership has
## to read by fill, not only by the border ribbon (REQ-P1-03).
const OWNER_TINT: float = 0.5

## How many baked charts to keep. The per-texel paint is the costliest part of
## showing a region, and the view asks for the same map state again and again:
## every screen a suite mounts on the shared world, every region a player
## switches back to. A small bound keeps that free while a conquered province
## (or an edited terrain grid) still repaints.
const CACHE_LIMIT: int = 6
static var _baked: Dictionary = {}


static func build(canvas: MapCanvas, model: MapModel) -> MapRelief:
	var relief: MapRelief = baked(model)
	var texel_scale: float = MapCanvas.TILE_SIZE / float(relief.scale)

	_shadow(canvas, relief, texel_scale)

	var sprite := Sprite2D.new()
	sprite.name = "Wash"
	sprite.centered = false
	sprite.show_behind_parent = true
	sprite.scale = Vector2(texel_scale, texel_scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture = ImageTexture.create_from_image(relief.color)
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/terrain.gdshader")
	material.set_shader_parameter("height_tex", ImageTexture.create_from_image(relief.relief))
	material.set_shader_parameter(
		"texel", Vector2(1.0 / float(relief.width), 1.0 / float(relief.height))
	)
	material.set_shader_parameter("world_size", MapGeo.world_size(model, MapCanvas.TILE_SIZE))
	sprite.material = material
	canvas.add_child(sprite)
	return relief


## The bake for this map state, painted only the first time it is asked for.
## Callers must treat the returned relief as read-only.
static func baked(model: MapModel) -> MapRelief:
	var key: String = _cache_key(model)
	var relief: MapRelief = _baked.get(key)
	if relief == null:
		relief = MapRelief.new()
		relief.build(model, OWNER_TINT)
		if _baked.size() >= CACHE_LIMIT:
			_baked.clear()
		_baked[key] = relief
	return relief


## Drops every bake, so a following build is painted rather than reused.
static func clear_cache() -> void:
	_baked.clear()


## Everything the paint reads: grid size, terrain (coast and height), province
## assignment and the deed table (ownership tint). Content, not identity, so a
## restored map finds its own bake again.
static func _cache_key(model: MapModel) -> String:
	var seats := PackedInt32Array()
	for province: ProvinceState in model.provinces:
		seats.append(int(province.id))
		seats.append(province.owner)
	return "%dx%d|%d|%d|%d|%d" % [
		model.width,
		model.height,
		hash(model.terrain),
		hash(model.province),
		hash(seats),
		hash([model.ownership.owners, model.ownership.purchased]),
	]


## Land drop shadow: the land mask offset a few pixels and darkened. Created
## before the wash so it draws underneath and lifts the coast off the water.
static func _shadow(canvas: MapCanvas, relief: MapRelief, texel_scale: float) -> void:
	var shade := Sprite2D.new()
	shade.name = "Shade"
	shade.centered = false
	shade.show_behind_parent = true
	shade.position = Vector2(5, 6)
	shade.scale = Vector2(texel_scale, texel_scale)
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shade.texture = ImageTexture.create_from_image(relief.shadow)
	shade.modulate = Color(0.10, 0.07, 0.03, 0.20)
	canvas.add_child(shade)
