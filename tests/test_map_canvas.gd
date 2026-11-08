extends GdToolsTest
## Presentation contract for the map artwork: the wash must sit behind the ink,
## the animated layers must exist, and symbols must never bury a province name.

var _canvas: MapCanvas = null


func before_each() -> void:
	_canvas = MapCanvas.new()
	_canvas.build(MapGenerator.new().generate(1500, 48, 32))
	add_child(_canvas)


func after_each() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null


func test_wash_draws_behind_the_inked_layer() -> void:
	var wash: Sprite2D = _canvas.get_node_or_null("Wash")
	assert_not_null(wash)
	assert_true(wash.show_behind_parent)
	assert_almost_eq(wash.scale.x, MapCanvas.TILE_SIZE, 0.001)
	assert_true(wash.material is ShaderMaterial)


func test_land_shadow_sits_under_the_wash() -> void:
	var shade: Sprite2D = _canvas.get_node_or_null("Shade")
	assert_not_null(shade)
	assert_true(shade.show_behind_parent)
	assert_lt(_canvas.get_children().find(shade), _canvas.get_children().find(_canvas.get_node("Wash")))


func test_animated_layers_exist() -> void:
	var surf: MapSurf = _canvas.get_node_or_null("Surf")
	assert_not_null(surf)
	assert_gt(surf.dash_count(), 0)
	var cloud: ColorRect = _canvas.get_node_or_null("CloudShade")
	assert_not_null(cloud)
	assert_true(cloud.material is ShaderMaterial)
	assert_gt(cloud.size.x, _canvas.map_size().x)


func test_surf_points_always_face_open_water() -> void:
	var surf: MapSurf = _canvas.get_node("Surf")
	for dash: Dictionary in surf._dashes:
		var origin: Vector2 = dash["position"]
		var normal: Vector2 = dash["normal"]
		var probe: Vector2 = origin + normal * MapCanvas.TILE_SIZE * 0.7
		var tile: Vector2i = MapGeo.tile_at_world(probe, MapCanvas.TILE_SIZE)
		assert_true(_canvas.model.is_sea(tile.x, tile.y))


func test_terrain_symbols_never_cover_province_labels() -> void:
	var marks: int = 0
	for glyph: Dictionary in _canvas._glyphs:
		var kind: String = String(glyph["kind"])
		if kind == "port" or kind == "capital":
			continue
		marks += 1
		assert_false(_canvas._under_label(glyph["position"]))
	assert_gt(marks, 0)


func test_capital_star_has_ten_points() -> void:
	var star: PackedVector2Array = MapGlyphs.star_points(Vector2.ZERO, 10.0, 5, 0.45)
	assert_eq(star.size(), 10)
	assert_almost_eq(star[0].distance_to(Vector2.ZERO), 10.0, 0.001)
