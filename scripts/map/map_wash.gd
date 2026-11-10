class_name MapWash
extends RefCounted
## Tile-resolution terrain colour, height, and the land drop shadow.
## The shader shades everything finer than a tile (REQ-P1-03).

const TERRAIN_HEIGHT: Array[float] = [0.0, 0.0, 0.20, 0.32, 0.60, 0.95, 0.26, 0.16, 0.24]

## How far owned land moves toward its crown's heraldic colour. Ownership has
## to read by fill, not only by the border ribbon (REQ-P1-03).
const OWNER_TINT: float = 0.5


static func build(canvas: MapCanvas, model: MapModel) -> void:
	var w: int = model.width
	var h: int = model.height
	var color_image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var height_image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mask := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pale: Color = Palette.terrain_color(MapModel.Terrain.SHALLOW)
	var relief := FastNoiseLite.new()
	relief.seed = 17
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief.frequency = 0.09
	relief.fractal_octaves = 3
	for y in h:
		for x in w:
			var index: int = model.index_of(x, y)
			var terrain: int = model.terrain[index]
			if terrain == MapModel.Terrain.OCEAN:
				color_image.set_pixel(x, y, Color(pale.r, pale.g, pale.b, 0.0))
				height_image.set_pixel(x, y, Color(0, 0, 0, 1))
				mask.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var color: Color = Palette.terrain_color(terrain)
			if terrain == MapModel.Terrain.SHALLOW:
				color_image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.34))
				height_image.set_pixel(x, y, Color(0, 0, 0, 1))
				mask.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			color_image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
			mask.set_pixel(x, y, Color(1, 1, 1, 1))
			var owner: int = model.owner_at(x, y)
			if owner != MapModel.NO_ID:
				var tint: Color = color.lerp(FactionCatalog.color_of(owner), OWNER_TINT)
				color_image.set_pixel(x, y, Color(tint.r, tint.g, tint.b, 1.0))
			var height: float = TERRAIN_HEIGHT[terrain]
			height += relief.get_noise_2d(float(x), float(y)) * 0.24
			height = clampf(height, 0.0, 1.0)
			height_image.set_pixel(x, y, Color(height, height, height, 1.0))

	_shadow(canvas, mask)

	var sprite := Sprite2D.new()
	sprite.name = "Wash"
	sprite.centered = false
	sprite.show_behind_parent = true
	sprite.scale = Vector2(MapCanvas.TILE_SIZE, MapCanvas.TILE_SIZE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture = ImageTexture.create_from_image(color_image)
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/terrain.gdshader")
	material.set_shader_parameter("height_tex", ImageTexture.create_from_image(height_image))
	material.set_shader_parameter("texel", Vector2(1.0 / float(w), 1.0 / float(h)))
	material.set_shader_parameter("world_size", MapGeo.world_size(model, MapCanvas.TILE_SIZE))
	sprite.material = material
	canvas.add_child(sprite)


## Land drop shadow: the land mask offset a few pixels and darkened. Created
## before the wash so it draws underneath and lifts the coast off the water.
static func _shadow(canvas: MapCanvas, mask: Image) -> void:
	var shade := Sprite2D.new()
	shade.name = "Shade"
	shade.centered = false
	shade.show_behind_parent = true
	shade.position = Vector2(5, 6)
	shade.scale = Vector2(MapCanvas.TILE_SIZE, MapCanvas.TILE_SIZE)
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shade.texture = ImageTexture.create_from_image(mask)
	shade.modulate = Color(0.10, 0.07, 0.03, 0.22)
	canvas.add_child(shade)
