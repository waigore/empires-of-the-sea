extends GdToolsTest
## Presentation contract for the map artwork: the wash must sit behind the ink,
## the animated layers must exist, the bake must carry a coastline and a beach
## the player can read, and symbols must never bury a province name.

const Fixture = preload("res://tests/map_fixture.gd")

var _canvas: MapCanvas = null


func before_each() -> void:
	_canvas = MapCanvas.new()
	_canvas.build(Fixture.region())
	add_child(_canvas)


func after_each() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null


func test_wash_draws_behind_the_inked_layer() -> void:
	var wash: Sprite2D = _canvas.get_node_or_null("Wash")
	assert_not_null(wash)
	assert_true(wash.show_behind_parent)
	assert_true(wash.material is ShaderMaterial)
	# The paint is baked finer than the tile grid but the sprite still covers
	# exactly one map.
	var relief: MapRelief = _canvas.relief
	assert_true(relief.scale > 1, "the wash is baked at sub-tile resolution")
	assert_almost_eq(wash.scale.x * float(relief.scale), MapCanvas.TILE_SIZE, 0.001)
	assert_almost_eq(
		wash.scale.x * float(wash.texture.get_width()), _canvas.map_size().x, 0.05
	)


func test_land_shadow_sits_under_the_wash() -> void:
	var shade: Sprite2D = _canvas.get_node_or_null("Shade")
	assert_not_null(shade)
	assert_true(shade.show_behind_parent)
	assert_lt(_canvas.get_children().find(shade), _canvas.get_children().find(_canvas.get_node("Wash")))


## The ink coast is what demarcates the land the wash fills, so it has to sit on
## the tile edge, not half a tile inside it: marching squares samples a tile at
## its corner, and an unshifted contour drifts up and left of the fill.
func test_ink_coast_sits_on_the_tile_edge_the_wash_fills() -> void:
	var model := MapModel.new()
	model.setup(16, 8)
	for y in model.height:
		for x in model.width:
			model.terrain[model.index_of(x, y)] = (
				MapModel.Terrain.PLAINS if x < 8 else MapModel.Terrain.OCEAN
			)
	var canvas := MapCanvas.new()
	add_child(canvas)
	canvas.build(model)
	var edge: float = 8.0 * MapCanvas.TILE_SIZE
	var reach := Vector2(-INF, -INF)
	for path: PackedVector2Array in canvas._coast:
		for point: Vector2 in path:
			reach.x = maxf(reach.x, point.x)
			reach.y = maxf(reach.y, point.y)
	assert_almost_eq(reach.x, edge, 1.0, "the coast ends on the shore, not inside it")
	assert_almost_eq(reach.y, edge, 1.0, "the coast ends on the shore, not inside it")
	canvas.queue_free()


## Ownership has to read by fill, not only by the border ribbon: the wash moves
## each owned tile toward its crown's heraldic colour, and the baked paint keeps
## that tint despite the noise laid over it.
func test_owned_land_is_washed_toward_its_crown() -> void:
	var model: MapModel = _canvas.model
	var tile: Vector2i = _inland_owned_tile(model)
	assert_true(tile.x >= 0, "fixture has an owned inland tile")
	var terrain: Color = Palette.terrain_color(model.terrain_at(tile.x, tile.y))
	var crown: Color = FactionCatalog.color_of(model.owner_at(tile.x, tile.y))
	var expected: Color = terrain.lerp(crown, MapWash.OWNER_TINT)
	assert_true(MapWash.OWNER_TINT >= 0.5, "ownership stays readable at play zoom")
	var base: Color = _canvas.relief.tile_color(tile)
	assert_almost_eq(base.r, expected.r, 0.001)
	assert_almost_eq(base.g, expected.g, 0.001)
	assert_almost_eq(base.b, expected.b, 0.001)
	var painted: Color = _painted_mean(tile)
	assert_almost_eq(painted.r, expected.r, 0.14)
	assert_almost_eq(painted.g, expected.g, 0.14)
	assert_almost_eq(painted.b, expected.b, 0.14)


## The bake owns the shore: land on one side of the distance field, water on the
## other, so the painted edge and the ink agree instead of blurring together.
func test_coast_field_is_negative_at_sea_and_positive_on_land() -> void:
	var model: MapModel = _canvas.model
	var relief: MapRelief = _canvas.relief
	var wrong: int = 0
	for y in model.height:
		for x in model.width:
			var centre := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance: float = relief.coast_at(centre)
			if model.is_land(x, y) and distance <= 0.0:
				wrong += 1
			elif not model.is_land(x, y) and distance >= 0.0:
				wrong += 1
	assert_eq(wrong, 0, "every tile centre sits on the right side of the shore")


## A beach inside the shore and a pale shoal outside it: that band is what makes
## a coastline read as drawn water rather than a soft smear.
func test_wash_paints_a_beach_and_a_shallow_band() -> void:
	var model: MapModel = _canvas.model
	var relief: MapRelief = _canvas.relief
	var image: Image = relief.color
	var sand: int = 0
	var shoal: int = 0
	var deep: int = 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.02:
				deep += 1
				continue
			if pixel.a > 0.85 and _near(pixel, MapRelief.SAND, 0.06):
				sand += 1
			elif pixel.a < 0.75 and _near(pixel, MapRelief.SHOAL, 0.14):
				shoal += 1
	assert_gt(sand, 40, "the shore carries a sand band")
	assert_gt(shoal, 40, "open water carries a shoal veil")
	assert_gt(deep, 40, "deep water is left to the sea shader")
	var coast: float = relief.coast_at(_land_centre(model))
	assert_gt(coast, 0.3, "inland ground sits well inside the shore")


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
	for glyph: Dictionary in _canvas.plan.glyphs:
		var kind: String = String(glyph["kind"])
		if kind == "port" or kind == "capital":
			continue
		marks += 1
		assert_false(_canvas.plan.under_label(glyph["position"]))
	assert_gt(marks, 0)


## Every non-capital province town is drawn on the chart, so a crown can see
## where its estates anchor (wiki: capital-and-connectivity § Town per province).
func test_every_non_capital_town_is_marked() -> void:
	var marks: Dictionary = {}
	for glyph: Dictionary in _canvas.plan.glyphs:
		if String(glyph["kind"]) == "town":
			marks[glyph["position"]] = true
	var expected: int = 0
	for province: ProvinceState in _canvas.model.provinces:
		if province.capital or province.town_tile.x < 0:
			continue
		var at: Vector2 = MapGeo.tile_center(
			province.town_tile.x, province.town_tile.y, MapCanvas.TILE_SIZE
		)
		if _canvas.plan.under_label(at):
			continue
		expected += 1
		assert_true(marks.has(at), "%s has no town mark" % province.name)
	assert_gt(expected, 0)
	assert_eq(marks.size(), expected)
## A province is painted, not speckled once: the scatter lays a second, smaller
## stamp on top of the first so a forest or an upland reads as a cluster.
func test_terrain_is_dense_with_two_stamp_kinds_per_tile() -> void:
	var kinds: Dictionary = {}
	var per_tile: Dictionary = {}
	for glyph: Dictionary in _canvas.plan.glyphs:
		var kind: String = String(glyph["kind"])
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if kind == "port" or kind == "capital":
			continue
		var at: Vector2 = glyph["position"]
		var tile: Vector2i = MapGeo.tile_at_world(at, MapCanvas.TILE_SIZE)
		per_tile[tile] = int(per_tile.get(tile, 0)) + 1
	var land: int = 0
	for y in _canvas.model.height:
		for x in _canvas.model.width:
			if _canvas.model.is_land(x, y):
				land += 1
	var marks: int = 0
	for kind: String in kinds.keys():
		if kind == "port" or kind == "capital":
			continue
		marks += int(kinds[kind])
	assert_gt(marks, land * 4 / 10, "the ground is painted, not left bare")
	assert_gt(kinds.size(), 5, "upland, woodland, scrub and plain marks all appear")
	assert_true(kinds.has("mountain") and kinds.has("tree"), "upland and woodland are drawn")
	var clustered: int = 0
	for tile: Vector2i in per_tile.keys():
		if int(per_tile[tile]) > 1:
			clustered += 1
	assert_gt(clustered, 4, "some tiles carry a second, smaller stamp")


func test_capital_star_has_ten_points() -> void:
	var star: PackedVector2Array = MapGlyphs.star_points(Vector2.ZERO, 10.0, 5, 0.45)
	assert_eq(star.size(), 10)
	assert_almost_eq(star[0].distance_to(Vector2.ZERO), 10.0, 0.001)


## Placement stays pure: the plan can be built headless, and every province
## with enough land carries its name at the province centre. The shared
## Fixture region is too small for the fixed 60-province chart to clear the
## label area floor, so this case builds a Small-preset grid of its own.
func test_plan_places_names_without_a_node() -> void:
	var region: MapModel = MapGenerator.new().generate(Fixture.SEED, 96, 64)
	var plan := MapCanvasPlan.new()
	plan.build(region, null, MapCanvas.TILE_SIZE)
	var named: Dictionary = {}
	for label: Dictionary in plan.labels:
		if String(label["kind"]) == "province":
			named[String(label["text"])] = label
	var expected: int = 0
	for province: ProvinceState in region.provinces:
		if province.area < 26:
			continue
		expected += 1
		assert_true(named.has(province.name))
	assert_gt(expected, 0)
	assert_false(plan.passages.size() > 0, "no world means no sea-lane marks")


## The bake is the costliest part of showing a map, so a repeat ask for the same
## map state must reuse it: a second screen on the shared world, or a region a
## player switches back to, has nothing new to paint.
func test_an_unchanged_map_reuses_its_bake() -> void:
	var model := _small_chart()
	var first: MapRelief = MapWash.baked(model)
	assert_eq(MapWash.baked(model), first, "the same map state reuses its bake")
	var province: ProvinceState = model.provinces[0]
	var tile: Vector2i = province.tiles[0]
	var owner: int = province.owner
	var crown: int = FactionCatalog.great_power_ids()[1]

	province.owner = crown if owner != crown else FactionCatalog.great_power_ids()[2]
	var repainted: MapRelief = MapWash.baked(model)
	assert_ne(repainted, first, "a new crown repaints the wash")
	assert_ne(
		repainted.tile_color(tile), first.tile_color(tile), "the tint follows the crown"
	)

	province.owner = owner
	assert_eq(MapWash.baked(model), first, "the restored map finds its own bake")


## The cache is a bound, not a leak: a run that keeps redrawing a changing map
## drops the oldest bakes instead of keeping every one of them.
func test_the_bake_cache_stays_bounded() -> void:
	MapWash.clear_cache()
	var model := _small_chart()
	var province: ProvinceState = model.provinces[0]
	var owner: int = province.owner
	for step in MapWash.CACHE_LIMIT + 2:
		province.owner = owner + step + 1
		MapWash.baked(model)
	assert_lte(MapWash._baked.size(), MapWash.CACHE_LIMIT, "bakes stay bounded")
	MapWash.clear_cache()
	assert_eq(MapWash._baked.size(), 0, "clearing drops every bake")


## A tiny chart for cache cases: two coastal provinces on an eight by six grid,
## cheap to paint, whose owners can be changed in place.
func _small_chart() -> MapModel:
	var model := MapModel.new()
	model.setup(8, 6)
	for y in model.height:
		for x in model.width:
			model.terrain[model.index_of(x, y)] = (
				MapModel.Terrain.OCEAN if y >= 4 else MapModel.Terrain.PLAINS
			)
	for index in 2:
		var tiles: Array[Vector2i] = []
		for y in 4:
			for x in 2:
				var tile := Vector2i(index * 4 + x + 1, y)
				tiles.append(tile)
				model.province[model.index_of(tile.x, tile.y)] = index
		var province := ProvinceState.create(
			index,
			"P%d" % index,
			tiles,
			Vector2(float(index * 4 + 2), 1.0),
			tiles.size(),
			FactionCatalog.PLAYER_FACTION + index,
			index == 0
		)
		model.provinces.append(province)
	return model


func _inland_owned_tile(model: MapModel) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_depth: float = 0.9
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			var depth: float = _canvas.relief.coast_at(
				Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
			)
			if depth > best_depth:
				best_depth = depth
				best = tile
	return best


## Mean of the bake texels around a tile centre, so a single grain texel does
## not decide the assertion.
func _painted_mean(tile: Vector2i) -> Color:
	var image: Image = _canvas.relief.color
	var scale: int = _canvas.relief.scale
	var cx: int = tile.x * scale + scale / 2
	var cy: int = tile.y * scale + scale / 2
	var total := Color(0.0, 0.0, 0.0, 0.0)
	var count: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = clampi(cx + dx, 0, image.get_width() - 1)
			var y: int = clampi(cy + dy, 0, image.get_height() - 1)
			total += image.get_pixel(x, y)
			count += 1
	return total / float(count)


func _land_centre(model: MapModel) -> Vector2:
	for province: ProvinceState in model.provinces:
		for tile: Vector2i in province.tiles:
			var centre := Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
			if _canvas.relief.coast_at(centre) > 1.2:
				return centre
	return Vector2(0.5, 0.5)


func _near(pixel: Color, target: Color, tolerance: float) -> bool:
	return (
		absf(pixel.r - target.r) < tolerance
		and absf(pixel.g - target.g) < tolerance
		and absf(pixel.b - target.b) < tolerance
	)
