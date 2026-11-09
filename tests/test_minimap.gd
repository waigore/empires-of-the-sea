extends GdToolsTest
## Contract for the minimap inset: parchment where nothing is charted, a bold
## heraldic wash where it is, and ink only along charted geography.
## (REQ-P1-03 legible art, REQ-P2-02 fog never leaks the map.)

const Fixture = preload("res://tests/map_fixture.gd")
const TILE_SIZE: float = 22.0

var _model: MapModel = null
var _visibility: VisibilityModel = null
var _minimap: Minimap = null


func before_each() -> void:
	_model = Fixture.region()
	_visibility = VisibilityModel.new()
	_visibility.setup(_model, FactionCatalog.PLAYER_FACTION)
	_minimap = Minimap.new()
	_minimap.size = Vector2(232.0, 160.0)
	add_child(_minimap)


func after_each() -> void:
	if is_instance_valid(_minimap):
		_minimap.queue_free()
	_minimap = null


func test_uncharted_ground_stays_parchment_without_ink() -> void:
	_visibility.levels.fill(VisibilityModel.Level.UNKNOWN)
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	var tile: Vector2i = _land_tile()
	var pixel: Color = _pixel_at(tile)
	assert_almost_eq(pixel.r, Palette.PAPER.r, 0.01)
	assert_almost_eq(pixel.g, Palette.PAPER.g, 0.01)
	assert_almost_eq(pixel.b, Palette.PAPER.b, 0.01)
	assert_true(_minimap._coast.is_empty(), "no coastline ink off the chart")
	assert_true(_minimap._province_ink.is_empty(), "no province ink off the chart")
	assert_true(_minimap._country_borders.is_empty(), "no crown ink off the chart")


func test_charted_region_draws_coast_province_and_crown_ink() -> void:
	_visibility.apply_initial()
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	assert_gt(_minimap._coast.size(), 0, "the charted coast is inked")
	assert_gt(_minimap._province_ink.size(), 0, "province hairlines subdivide it")
	assert_gt(_minimap._country_borders.size(), 0, "owners' borders are inked")
	for owner: int in _minimap._country_borders.keys():
		assert_true(FactionCatalog.has_faction(owner))


## The projection is what keeps strokes crisp: ink is cached in world units and
## remapped into the inset's own pixels once per build/resize.
func test_projected_ink_lands_inside_the_inset() -> void:
	_visibility.apply_initial()
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	var bounds: Rect2 = _minimap._fit_rect().grow(1.0)
	assert_gt(_minimap._ink_coast.size(), 0)
	for path: PackedVector2Array in _minimap._ink_coast:
		assert_gt(path.size(), 1)
		for point: Vector2 in path:
			assert_true(bounds.has_point(point), "ink stays inside the inset")
	for path: PackedVector2Array in _minimap._ink_provinces:
		for point: Vector2 in path:
			assert_true(bounds.has_point(point), "hairlines stay inside the inset")


## Ownership must read by fill, not only by border: the wash is bolder than the
## main map's and reaches the heraldic colour.
func test_owned_land_is_washed_toward_its_crown() -> void:
	_visibility.levels.fill(VisibilityModel.Level.FULLY_VISIBLE)
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	var tile: Vector2i = _owned_tile()
	var terrain: Color = Palette.terrain_color(_model.terrain_at(tile.x, tile.y))
	var crown: Color = FactionCatalog.color_of(_model.owner_at(tile.x, tile.y))
	var pixel: Color = _pixel_at(tile)
	assert_true(Minimap.OWNER_TINT >= 0.5, "the inset wash stays bold")
	assert_almost_eq(pixel.r, lerpf(terrain.r, crown.r, Minimap.OWNER_TINT), 0.01)
	assert_almost_eq(pixel.g, lerpf(terrain.g, crown.g, Minimap.OWNER_TINT), 0.01)
	assert_almost_eq(pixel.b, lerpf(terrain.b, crown.b, Minimap.OWNER_TINT), 0.01)


func test_fogged_land_keeps_its_shape_but_fades_toward_the_page() -> void:
	_visibility.levels.fill(VisibilityModel.Level.FULLY_VISIBLE)
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	var tile: Vector2i = _owned_tile()
	var charted: Color = _pixel_at(tile)
	_visibility.levels.fill(VisibilityModel.Level.FOGGED)
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	var fogged: Color = _pixel_at(tile)
	assert_ne(charted, fogged, "fog reads differently from a charted tile")
	var eased: float = (charted.r - Palette.PAPER.r) * (1.0 - Minimap.FOG_WASH)
	assert_almost_eq(fogged.r, Palette.PAPER.r + eased, 0.02)


## A conquest moves the flag without moving the chart, so the HUD asks the
## inset to repaint in place.
func test_a_conquest_recolours_the_inset_without_a_new_chart() -> void:
	var province: ProvinceState = _owned_province()
	var original: int = province.owner
	var tile: Vector2i = _owned_tile_of(province)
	var new_crown: int = FactionCatalog.great_power_ids()[1]
	_visibility.levels.fill(VisibilityModel.Level.FULLY_VISIBLE)
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	var before: Color = _pixel_at(tile)
	province.owner = new_crown
	_minimap.refresh_ownership()
	var after: Color = _pixel_at(tile)
	province.owner = original
	assert_ne(before, after, "a new crown recolours the tile")
	assert_almost_eq(
		after.r,
		lerpf(
			Palette.terrain_color(_model.terrain_at(tile.x, tile.y)).r,
			FactionCatalog.color_of(new_crown).r,
			Minimap.OWNER_TINT
		),
		0.01,
		"the repaint uses the new owner's colour"
	)


## A tile whose owner comes from the province, not from a merchant's deed.
func _owned_tile_of(province: ProvinceState) -> Vector2i:
	for tile: Vector2i in province.tiles:
		if _model.owner_at(tile.x, tile.y) == province.owner:
			return tile
	return province.tiles[0]


func _pixel_at(tile: Vector2i) -> Color:
	return _minimap._texture.get_image().get_pixel(tile.x, tile.y)


func _land_tile() -> Vector2i:
	for province: ProvinceState in _model.provinces:
		if not province.tiles.is_empty():
			return province.tiles[0]
	return Vector2i.ZERO


func _owned_province() -> ProvinceState:
	for province: ProvinceState in _model.provinces:
		if province.owner == FactionCatalog.PLAYER_FACTION:
			return province
	return _model.provinces[0]


func _owned_tile() -> Vector2i:
	for tile: Vector2i in _owned_province().tiles:
		if _model.owner_at(tile.x, tile.y) != MapModel.NO_ID:
			return tile
	return _land_tile()
