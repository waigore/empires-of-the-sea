class_name MapWash
extends RefCounted
## Tile-resolution terrain colour, height, and the land drop shadow.
## The paint itself is baked at sub-tile resolution by `MapRelief`; the shader
## shades everything finer than one of its texels (REQ-P1-03).

## How far owned land moves toward its crown's heraldic colour. Ownership has
## to read by fill, not only by the border ribbon (REQ-P1-03).
const OWNER_TINT: float = 0.5


static func build(canvas: MapCanvas, model: MapModel) -> MapRelief:
	var relief := MapRelief.new()
	relief.build(model, OWNER_TINT)
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
