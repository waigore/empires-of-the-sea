extends GdToolsTest
## One boot for the map: the model and region table, fog visibility, the save
## halves, the camera, the fog layer, the minimap, the resource survey, the
## crown road lens and the canvas painting (wash, ink, names, plan marks).

## Merged from test_map_model, test_map_region_table, test_visibility,
## test_save_world, test_save_store, test_province_graph, test_map_camera,
## test_fog_layer, test_minimap, test_resource_survey, test_crown_road_lens,
## test_map_canvas.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const fog_layer_Fixture = preload("res://tests/map_fixture.gd")
const minimap_Fixture = preload("res://tests/map_fixture.gd")
const resource_survey_Fixture = preload("res://tests/map_fixture.gd")
const crown_road_lens_Fixture = preload("res://tests/map_fixture.gd")

const MAP := Vector2(2816.0, 1848.0)
const TILE_SIZE: float = 22.0

var _camera: MapCamera = null
var _overlay: MapOverlay = null
var _model: MapModel = null
var _visibility: VisibilityModel = null
var _minimap: Minimap = null
var screen: MapScreen = null
var saved: Array = []

var _suite_setup: String = ""

func before_all() -> void:
	_data_before_all()
	_hook_crown_road_lens_before_all()

func after_all() -> void:
	_hook_crown_road_lens_after_all()

func after_each() -> void:
	_canvas_after_each()
	_data_after_each()
	match _suite_setup:
		"map_camera":
			_teardown_map_camera()
		"fog_layer":
			_teardown_fog_layer()
		"minimap":
			_teardown_minimap()
	_suite_setup = ""

func _hook_crown_road_lens_before_all() -> void:
	saved = crown_road_lens_Fixture.snapshot(crown_road_lens_Fixture.world())
	screen = crown_road_lens_Fixture.attach_screen(self)

func _hook_crown_road_lens_after_all() -> void:
	if is_instance_valid(screen):
		screen.free()
	screen = null

func _setup_map_camera() -> void:
	_suite_setup = "map_camera"
	InputActions.ensure_actions()
	_camera = MapCamera.new()
	_camera.map_size = MAP
	_camera.position = MAP * 0.5
	_camera.zoom = Vector2.ONE * 1.2
	_camera.target_zoom = 1.2
	add_child(_camera)

func _setup_fog_layer() -> void:
	_suite_setup = "fog_layer"
	_overlay = MapOverlay.new()
	_overlay.build(fog_layer_Fixture.region())
	add_child(_overlay)

func _setup_minimap() -> void:
	_suite_setup = "minimap"
	_model = minimap_Fixture.region()
	_visibility = VisibilityModel.new()
	_visibility.setup(_model, FactionCatalog.PLAYER_FACTION)
	_minimap = Minimap.new()
	_minimap.size = Vector2(232.0, 160.0)
	add_child(_minimap)

func _setup_crown_road_lens() -> void:
	_suite_setup = "crown_road_lens"
	crown_road_lens_Fixture.restore(crown_road_lens_Fixture.world(), saved)
	if screen == null or not is_instance_valid(screen):
		screen = crown_road_lens_Fixture.attach_screen(self)
		return
	if screen.play.lens != null and screen.play.lens.active:
		MapPlayInput.set_lens(screen.play, false)
	if screen.play.diplomacy_lens != null and screen.play.diplomacy_lens.active:
		MapPlayInput.set_diplomacy_lens(screen.play, false)
	if screen.play.crown_lens != null and screen.play.crown_lens.active:
		MapPlayInput.set_crown_lens(screen.play, false)
	if screen.region_index != 0:
		screen.load_region(0)

func _teardown_map_camera() -> void:
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null

func _teardown_fog_layer() -> void:
	if is_instance_valid(_overlay):
		_overlay.free()
	_overlay = null

func _teardown_minimap() -> void:
	if is_instance_valid(_minimap):
		_minimap.queue_free()
	_minimap = null

# --- test_map_camera ---

func test_wheel_zooms_in_and_out() -> void:
	_setup_map_camera()
	var before: float = _camera.target_zoom
	_camera._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(300, 200)))
	assert_gt(_camera.target_zoom, before)
	var zoomed: float = _camera.target_zoom
	_camera._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(300, 200)))
	assert_lt(_camera.target_zoom, zoomed)

func test_zoom_keeps_the_cursor_anchored() -> void:
	_setup_map_camera()
	var anchor := Vector2(900.0, 300.0)
	var world_before: Vector2 = CameraMath.screen_to_world(
		_camera.position, _camera.zoom.x, anchor, _camera.viewport_size()
	)
	_camera.zoom_by(1.5, anchor)
	for _step in 8:
		_camera._process(0.1)
	var world_after: Vector2 = CameraMath.screen_to_world(
		_camera.position, _camera.zoom.x, anchor, _camera.viewport_size()
	)
	assert_lt(world_after.distance_to(world_before), 3.0)

func test_magnify_gesture_zooms() -> void:
	_setup_map_camera()
	var event := InputEventMagnifyGesture.new()
	event.factor = 1.3
	event.position = Vector2(640, 640)
	var before: float = _camera.target_zoom
	_camera._unhandled_input(event)
	assert_gt(_camera.target_zoom, before)

func test_pan_gesture_moves_the_camera() -> void:
	_setup_map_camera()
	var event := InputEventPanGesture.new()
	event.delta = Vector2(40, 0)
	event.position = Vector2(640, 640)
	var before: Vector2 = _camera.position
	_camera._unhandled_input(event)
	assert_lt(_camera.position.x, before.x)

func test_drag_marks_dragging_and_tracks_distance() -> void:
	_setup_map_camera()
	_camera._unhandled_input(_button(true, Vector2(400, 400)))
	assert_true(_camera.is_dragging())
	_camera._unhandled_input(_motion(Vector2(30, 0)))
	assert_gt(_camera.drag_distance(), 0.0)
	_camera._unhandled_input(_button(false, Vector2(430, 400)))
	assert_false(_camera.is_dragging())

func test_click_emits_tapped_with_world_position() -> void:
	_setup_map_camera()
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	_camera._unhandled_input(_button(false, Vector2(701, 500)))
	assert_eq(captured.size(), 1)
	var expected: Vector2 = CameraMath.screen_to_world(
		_camera.position, _camera.zoom.x, Vector2(701, 500), _camera.viewport_size()
	)
	assert_almost_eq(captured[0].x, expected.x, 0.5)
	assert_almost_eq(captured[0].y, expected.y, 0.5)

func test_drag_does_not_emit_tapped() -> void:
	_setup_map_camera()
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	_camera._unhandled_input(_motion(Vector2(80, 0)))
	_camera._unhandled_input(_button(false, Vector2(780, 500)))
	assert_eq(captured.size(), 0)

func test_drag_keeps_inertia_after_release() -> void:
	_setup_map_camera()
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	for _step in 4:
		_camera._unhandled_input(_motion(Vector2(40, 0)))
	var released_at: Vector2 = _camera.position
	_camera._unhandled_input(_button(false, Vector2(860, 500)))
	_camera._process(0.1)
	assert_ne(_camera.position, released_at)

func test_touch_tap_emits_tapped() -> void:
	_setup_map_camera()
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_touch(0, true, Vector2(500, 500)))
	_camera._unhandled_input(_touch(0, false, Vector2(502, 501)))
	assert_eq(captured.size(), 1)

func test_two_finger_pinch_zooms() -> void:
	_setup_map_camera()
	_camera._unhandled_input(_touch(0, true, Vector2(400, 400)))
	_camera._unhandled_input(_touch(1, true, Vector2(500, 400)))
	var before: float = _camera.target_zoom
	_camera._unhandled_input(_screen_drag(1, Vector2(120, 0), Vector2(620, 400)))
	assert_gt(_camera.target_zoom, before)

func test_single_finger_drag_pans() -> void:
	_setup_map_camera()
	var before: Vector2 = _camera.position
	_camera._unhandled_input(_touch(0, true, Vector2(400, 400)))
	_camera._unhandled_input(_screen_drag(0, Vector2(-60, -30), Vector2(340, 370)))
	assert_ne(_camera.position, before)

func test_keyboard_pan_moves_the_camera() -> void:
	_setup_map_camera()
	var before: Vector2 = _camera.position
	Input.action_press(InputActions.PAN_RIGHT)
	_camera._process(0.2)
	Input.action_release(InputActions.PAN_RIGHT)
	assert_gt(_camera.position.x, before.x)

func test_focus_on_settles_at_a_clamped_target() -> void:
	_setup_map_camera()
	_camera.focus_on(Vector2(2600, 1700), 0.9)
	for _step in 30:
		_camera._process(0.2)
	var expected: Vector2 = CameraMath.clamp_center(
		Vector2(2600, 1700), _camera.zoom.x, _camera.viewport_size(), MAP
	)
	assert_lt(_camera.position.distance_to(expected), 2.0)
	assert_almost_eq(_camera.zoom.x, 0.9, 0.001)

func test_zoom_buttons_step_and_clamp() -> void:
	_setup_map_camera()
	var before: float = _camera.target_zoom
	_camera.zoom_in()
	assert_gt(_camera.target_zoom, before)
	for _step in 40:
		_camera.zoom_in()
	assert_almost_eq(_camera.target_zoom, MapCamera.MAX_ZOOM, 0.0001)
	for _step in 80:
		_camera.zoom_out()
	assert_almost_eq(_camera.target_zoom, _camera.min_zoom(), 0.0001)

func _wheel(button: MouseButton, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = position
	return event

func _button(pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(400, 400)
	return event

func _touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event

func _screen_drag(index: int, relative: Vector2, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.relative = relative
	event.position = position
	return event

# --- test_fog_layer ---

func test_fog_is_a_child_sprite_behind_the_ink() -> void:
	_setup_fog_layer()
	var fog: FogLayer = _overlay.get_node_or_null("Fog")
	assert_not_null(fog)
	assert_eq(fog, _overlay.fog_layer)
	var sprite: Sprite2D = _fog_sprite(fog)
	assert_not_null(sprite)
	assert_true(sprite.show_behind_parent)

## A rebuild (region switch, political refresh) repaints the layer's one sprite.
## A fresh sprite per build would leave the previous region's fog stacked on the
## map — an all-paper New World wash covers the charted Old World.
func test_a_rebuild_repaints_one_sprite_instead_of_stacking() -> void:
	_setup_fog_layer()
	var fog: FogLayer = _overlay.fog_layer
	var sprite: Sprite2D = _fog_sprite(fog)
	_overlay.build(fog_layer_Fixture.region())
	assert_eq(fog.get_child_count(), 1, "no stale fog sprite is left behind")
	assert_eq(_fog_sprite(fog), sprite, "the fog sprite is reused")
	assert_eq(sprite.texture, fog._texture, "the sprite paints the latest grid")

func test_levels_map_to_fog_ids() -> void:
	_setup_fog_layer()
	assert_eq(MapOverlay.FOG_VISIBLE, FogLayer.FOG_VISIBLE)
	assert_eq(
		FogLayer.fog_state_for(VisibilityModel.Level.FULLY_VISIBLE), FogLayer.FOG_VISIBLE
	)
	assert_eq(FogLayer.fog_state_for(VisibilityModel.Level.UNKNOWN), FogLayer.FOG_UNKNOWN)
	assert_eq(FogLayer.fog_state_for(VisibilityModel.Level.FOGGED), FogLayer.FOG_FOGGED)
	assert_almost_eq(FogLayer.target_alpha(FogLayer.FOG_FOGGED), 0.55, 0.0001)
	assert_almost_eq(FogLayer.target_alpha(FogLayer.FOG_UNKNOWN), 1.0, 0.0001)
	assert_almost_eq(FogLayer.target_alpha(FogLayer.FOG_VISIBLE), 0.0, 0.0001)

func test_overlay_delegates_fog_state_to_the_layer() -> void:
	_setup_fog_layer()
	var tile: Vector2i = Vector2i(1, 1)
	_overlay.set_fog_state(_overlay.model.index_of(tile.x, tile.y), MapOverlay.FOG_FOGGED)
	assert_eq(_overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)
	assert_eq(
		_overlay.fog_layer.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED
	)

## The chart layers bake on change only: resyncing the chart already painted
## (a load that restores the same save, a re-seat) raises no fog change, so the
## readings keep the projection they hold instead of recomputing it.
func test_resyncing_the_painted_chart_raises_no_change() -> void:
	_setup_fog_layer()
	var raises: Array = []
	_overlay.fog_changed.connect(func() -> void: raises.append(true))
	var visibility := VisibilityModel.new()
	visibility.setup(_overlay.model, FactionCatalog.PLAYER_FACTION)
	visibility.apply_initial()
	_overlay.sync_visibility(visibility)
	assert_eq(raises.size(), 1, "the first resync charts the grid")
	_overlay.sync_visibility(visibility)
	assert_eq(raises.size(), 1, "the same chart raises nothing again")
	# A reveal moves the chart, so the readings are told to re-read it.
	visibility.raise_to(0, VisibilityModel.Level.FULLY_VISIBLE)
	_overlay.sync_visibility(visibility)
	assert_true(raises.size() > 1, "a chart that moved raises its change")

func test_snapped_fog_settles_and_stops_fading() -> void:
	_setup_fog_layer()
	var tile: Vector2i = Vector2i(2, 2)
	_overlay.set_fog_state(_overlay.model.index_of(tile.x, tile.y), MapOverlay.FOG_UNKNOWN)
	assert_true(_overlay.fog_layer.is_fading())
	_overlay.snap_fog()
	assert_false(_overlay.fog_layer.is_fading())
	assert_true(_overlay.fog_layer.advance(0.016), "snap repaints once")
	assert_false(_overlay.fog_layer.advance(0.016), "settled fog does not repaint")

## A raid rings the water it worked without stealing the selection (DR-20261110-13).
func test_a_ripple_marks_the_water_and_ages_out() -> void:
	_setup_fog_layer()
	_overlay.select_province(2)
	_overlay.ripple(Vector2(120.0, 64.0))
	assert_eq(_overlay.selected_province, 2, "the ripple never moves the selection")
	assert_eq(_overlay._ripples.size(), 1)
	assert_eq(_overlay._ripples[0]["position"], Vector2(120.0, 64.0))
	_overlay._age_ripples(1.2)
	assert_true(_overlay._ripples.is_empty(), "the ring is a moment, not a marker")

func _fog_sprite(fog: FogLayer) -> Sprite2D:
	for child in fog.get_children():
		if child is Sprite2D:
			return child as Sprite2D
	return null

# --- test_minimap ---

func test_uncharted_ground_stays_parchment_without_ink() -> void:
	_setup_minimap()
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

## A paint that never ran (a mount whose inset build was missed, or one made
## before its region existed) must not leave the frame's near-black panel
## showing for the campaign: the next frame bakes the chart itself (#563).
func test_a_chart_that_never_baked_heals_on_the_next_frame() -> void:
	_setup_minimap()
	_visibility.apply_initial()
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	assert_not_null(_minimap._texture, "the build bakes the chart")
	_minimap._texture = null
	_minimap._process(0.0)
	assert_not_null(_minimap._texture, "the inset bakes rather than staying blank")


## With no chart there is nothing to bake: the inset stays empty rather than
## painting a chartless wash over the chrome's frame.
func test_an_inset_with_no_chart_bakes_nothing() -> void:
	_setup_minimap()
	_minimap._process(0.0)
	assert_null(_minimap._texture, "no chart, no bake")


func test_charted_region_draws_coast_province_and_crown_ink() -> void:
	_setup_minimap()
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
	_setup_minimap()
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
	_setup_minimap()
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
	_setup_minimap()
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
	_setup_minimap()
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

## A second bake of the same chart keeps the texture it already drew: the inset
## bakes on change only, so a re-seat of the same save pays no texel pass.
func test_a_second_bake_of_the_same_chart_draws_nothing() -> void:
	_setup_minimap()
	_visibility.levels.fill(VisibilityModel.Level.FULLY_VISIBLE)
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	var baked: ImageTexture = _minimap._texture
	var borders: Dictionary = _minimap._country_borders
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	assert_eq(_minimap._texture, baked, "the same chart is not baked again")
	assert_eq(_minimap._country_borders, borders, "the ink is the one already drawn")
	_visibility.lower_to(_model.index_of(1, 1), VisibilityModel.Level.FOGGED)
	_minimap.build(_model, MapGeo.world_size(_model, TILE_SIZE), _visibility)
	assert_ne(_minimap._texture, baked, "a chart that moved bakes again")

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

# --- test_resource_survey ---

func test_snapshot_reads_every_charted_resource_tile() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, LandWorks.new(), [], FactionCatalog.PLAYER_FACTION
	)
	assert_gt(int(survey["counts"]["provinces"]), 0)
	assert_gt(int(survey["counts"]["estates"]), 0)
	var provinces: Array = survey["provinces"]
	for raw: Variant in provinces:
		var entry: Dictionary = raw
		assert_gt(int(entry["counts"]["estates"]), 0)
		assert_eq(int(entry["counts"]["estates"]), (entry["rows"] as Array).size())
		assert_false(String(entry["summary"]).is_empty())

func test_a_connected_estate_yields_and_counts_as_worked() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = resource_survey_Fixture.owned_resource_tile(model, works)
	assert_true(tile.x >= 0)
	works.set_improvement(model, tile, 1)
	works.set_prospected(owner, model, tile)
	# The tile itself is the seat: connectivity seeds there, so the estate pays.
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, works, [], owner, null, tile, {}
	)
	var entry: Dictionary = _entry(survey, model.province_at(tile.x, tile.y))
	var row: Dictionary = _row(entry, tile)
	assert_eq(String(row["status"]), "producing")
	assert_eq(
		int(row["output"]),
		Extraction.estate_yield_per_level(owner, String(row["commodity"])),
		"the estate pays its level at the published per-level yield"
	)
	assert_eq(int(entry["counts"]["worked"]), 1)
	assert_eq(int(entry["counts"]["developed"]), 1)
	assert_eq(int(entry["counts"]["linked"]), 1)
	assert_gt(int(entry["counts"]["producing"]), 0)
	assert_false((entry["output"] as Dictionary).is_empty())
	# The hover names the type with its built/linked/held badge, the same numbers
	# the plate prints (issue #698).
	var type_name: String = String(ResourceTypes.NAMES.get(String(row["icon"]), ""))
	assert_true(String(entry["summary"]).contains(type_name + " "))
	assert_true(String(entry["summary"]).contains("1/1/"))

func test_the_plate_counts_developed_estates_apart_from_linked_ones() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = resource_survey_Fixture.owned_resource_tile(model, works)
	works.set_improvement(model, tile, 1)
	works.set_prospected(owner, model, tile)
	var province: int = model.province_at(tile.x, tile.y)
	var linked: Dictionary = _entry(
		ResourceSurvey.snapshot(model, works, [], owner, null, tile, {}), province
	)
	var cut: Dictionary = _entry(
		ResourceSurvey.snapshot(
			model, works, [], owner, null, Vector2i(-1, -1), {}
		),
		province
	)
	assert_eq(int(cut["counts"]["developed"]), int(linked["counts"]["developed"]))
	assert_eq(int(cut["counts"]["linked"]), 0, "no capital, no crown link")
	assert_gt(int(linked["counts"]["linked"]), 0)

func test_roads_are_projected_as_segments_tagged_linked_or_cut() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var pair: Array[Vector2i] = _owned_pair(model)
	assert_eq(pair.size(), 2, "fixture needs two neighbouring owned tiles")
	works.set_transport(model, pair[0], LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, pair[1], LandWorks.TRANSPORT_RAIL)
	var routes: Dictionary = ResourceRoutes.snapshot(model, works, owner, pair[0])
	var segments: Array = routes["segments"]
	assert_eq(segments.size(), 1, "one pair, one segment")
	var segment: Dictionary = segments[0]
	assert_true(bool(segment["linked"]), "both ends reach the seat")
	assert_true(bool(segment["rail"]), "the higher level carries the stroke")
	assert_eq(int(routes["counts"]["linked"]), 1)
	# No capital means no crown network: the same road draws as cut ink.
	routes = ResourceRoutes.snapshot(model, works, owner, Vector2i(-1, -1))
	segment = (routes["segments"] as Array)[0]
	assert_false(bool(segment["linked"]))
	assert_eq(int(routes["counts"]["linked"]), 0)
	# Unknown ground never draws a road.
	var visibility := VisibilityModel.new()
	visibility.setup(model, owner)
	visibility.lower_to(
		model.index_of(pair[1].x, pair[1].y), VisibilityModel.Level.UNKNOWN
	)
	routes = ResourceRoutes.snapshot(model, works, owner, pair[0], visibility)
	assert_true((routes["segments"] as Array).is_empty())
	# Fogged ground still projects the stroke, tagged for fainter ink.
	visibility.setup(model, owner)
	visibility.lower_to(
		model.index_of(pair[1].x, pair[1].y), VisibilityModel.Level.FOGGED
	)
	routes = ResourceRoutes.snapshot(model, works, owner, pair[0], visibility)
	assert_eq((routes["segments"] as Array).size(), 1)
	assert_true(bool((routes["segments"] as Array)[0]["fogged"]))
	# Guard: empty chart and a bad owner never invent a network.
	routes = ResourceRoutes.snapshot(null, works, owner)
	assert_true((routes["segments"] as Array).is_empty())
	routes = ResourceRoutes.snapshot(model, works, -1)
	assert_true((routes["segments"] as Array).is_empty())

func test_a_coastal_road_does_not_pair_onto_the_sea() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var coast: Vector2i = _owned_coast_toward_sea(model)
	assert_true(coast.x >= 0, "fixture needs an owned land tile facing the sea")
	works.set_transport(model, coast, LandWorks.TRANSPORT_ROAD)
	var routes: Dictionary = ResourceRoutes.snapshot(model, works, owner, coast)
	assert_eq(int(routes["counts"]["road"]), 0, "sea never completes a road pair")

## The survey lens reads the court's seals itself, and a war that lifts one
## re-bakes the plate without a work moving: the same coast the phase withholds
## must never print a linked estate or a solid road (wiki:
## capital-and-connectivity § Blockade; REQ-P2-03, REQ-P4-01).
func test_the_survey_lens_reads_the_seals_and_rebakes_when_they_lift() -> void:
	var model := MapModel.new()
	model.setup(12, 9)
	var groups: Dictionary = {0: [], 1: [], 2: []}
	for y in 8:
		for x in 12:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			var province_id: int = 0 if x < 3 else (1 if x < 6 else 2)
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	for x in 12:
		model.terrain[model.index_of(x, 8)] = MapModel.Terrain.OCEAN
		model.sea_zone[model.index_of(x, 8)] = 0
	var provinces: Array[ProvinceState] = []
	for province_id in 3:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		provinces.append(
			ProvinceState.create(
				province_id, "P%d" % province_id, tiles, Vector2(1.0, 1.0),
				tiles.size(), FactionCatalog.PLAYER_FACTION, province_id == 0
			)
		)
	var capital := Vector2i(0, 1)
	var town := Vector2i(7, 2)
	var estate := Vector2i(6, 2)
	provinces[0].capital_tile = capital
	provinces[0].town_tile = capital
	provinces[1].town_tile = Vector2i(4, 1)
	provinces[2].town_tile = town
	provinces[2].town_development = 2
	model.provinces = provinces
	var works := LandWorks.new()
	works.add_port(model, town)
	works.set_transport(model, town, LandWorks.TRANSPORT_ROAD)
	works.set_improvement(model, estate, 4)
	works.set_transport(model, estate, LandWorks.TRANSPORT_ROAD)
	model.resource[model.index_of(estate.x, estate.y)] = 4
	var caps: Dictionary = {"grain": 4}
	var owner: int = FactionCatalog.PLAYER_FACTION
	var lens := ResourceLens.new()
	add_child(lens)
	lens.build(model, works, [], owner, null, capital, caps)
	assert_eq(int(lens.survey["counts"]["blocked"]), 0, "no seal, no cut")
	assert_eq(int(lens.survey["counts"]["linked"]), 1, "the open harbour links")
	assert_true(
		bool((lens.survey["routes"] as Array)[0]["linked"]),
		"the stroke reaches the crown through the harbour"
	)
	var seals := Blockades.new()
	seals.sealed = {model.region_id: {2: true}}
	lens.build(model, works, [], owner, null, capital, caps, seals)
	assert_eq(int(lens.survey["counts"]["blocked"]), 1, "the sealed estate reads cut")
	assert_eq(int(lens.survey["counts"]["linked"]), 0, "and stops counting as linked")
	assert_false(
		bool((lens.survey["routes"] as Array)[0]["linked"]),
		"the same stroke draws dashed under the seal"
	)
	# The war ends: the seal lifts with no work laid, so the plate re-bakes.
	seals.sealed = {}
	lens.build(model, works, [], owner, null, capital, caps, seals)
	assert_eq(int(lens.survey["counts"]["blocked"]), 0, "the lifted seal re-reads")
	assert_eq(int(lens.survey["counts"]["linked"]), 1)
	lens.free()

## The court's pick on the chart (DR-20261117-07): the ground a pick names wears
## one ring, a pick off the crew's own tile carries the step from the crew, and a
## pick whose crew is at work, off this chart's roster or on ground the crown has
## not charted is never marked (`REQ-P2-03`, `REQ-P5-06`).
func test_the_chart_marks_the_ground_the_court_would_send_a_crew_to() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var tiles: Array = (model.provinces[0].tiles as Array)
	assert_gte(tiles.size(), 3, "the fixture needs three tiles of one province")
	var own: Vector2i = tiles[0]
	var stand: Vector2i = tiles[1]
	var walk_to: Vector2i = tiles[2]
	var owner: int = FactionCatalog.PLAYER_FACTION
	var here: CivilianState = CivilianState.create(3, owner, "builder", own)
	var far: CivilianState = CivilianState.create(4, owner, "builder", stand)
	var crews: Array[CivilianState] = [here, far]
	var picks: Dictionary = {
		3: {"action": "build_improvement", "tile": own},
		4: {"action": MapPlayCivilianPick.KIND_MOVE, "tile": walk_to},
		# A second crew on the same ground adds no second ring.
		9: {"action": "explore", "tile": own},
	}

	var marks: Array[Dictionary] = CivicGlyphs.marks(picks, crews, model, null)

	assert_eq(marks.size(), 2, "one mark per ground named, the repeat folded")
	assert_eq(Vector2i(marks[0]["tile"]), own)
	assert_false(bool(marks[0]["march"]), "a work on the crew's own tile takes no step")
	assert_eq(
		Vector2(marks[0]["center"]), MapGeo.tile_center(own.x, own.y, CivicGlyphs.TILE_SIZE)
	)
	assert_eq(Vector2i(marks[1]["tile"]), walk_to)
	assert_true(bool(marks[1]["march"]), "a pick off the crew's tile is a march")
	assert_eq(
		Vector2(marks[1]["from"]),
		MapGeo.tile_center(stand.x, stand.y, CivicGlyphs.TILE_SIZE)
	)
	# A crew at work is already spoken for: its ground loses the ring.
	here.start_work("build_improvement", own, 1)
	assert_eq(CivicGlyphs.marks(picks, crews, model, null).size(), 1)
	# A crew this chart does not hold, and ground the crown has not charted.
	assert_true(
		CivicGlyphs.marks({99: {"tile": own}}, crews, model, null).is_empty(),
		"no crew on this chart, no mark"
	)
	var visibility := VisibilityModel.new()
	visibility.setup(model, owner)
	visibility.lower_to(model.index_of(own.x, own.y), VisibilityModel.Level.UNKNOWN)
	var fogged: Array[Dictionary] = CivicGlyphs.marks(
		{3: {"tile": own}}, [CivilianState.create(3, owner, "builder", own)], model, visibility
	)
	assert_true(fogged.is_empty(), "the crown marks no ground it has not charted")


## The lens carries the marks with the rest of the reading: a pick is baked on
## build, a build with no pick clears it, and the baked mark inks without a
## crash so the chart never prints a reading it cannot draw (DR-20261117-07).
func test_the_survey_lens_bakes_the_courts_picks() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = (model.provinces[0].tiles as Array)[0]
	var crew: CivilianState = CivilianState.create(7, owner, "builder", tile)
	var units: Array[CivilianState] = [crew]
	var lens := ResourceLens.new()
	add_child(lens)
	lens.picks = {7: {"action": "build_improvement", "tile": tile}}
	lens.build(model, works, units, owner, null, Vector2i(-1, -1), {})

	assert_eq(lens.marks.size(), 1, "the pick is baked with the reading")
	assert_eq(Vector2i(lens.marks[0]["tile"]), tile)
	# The draw path: the ring and the reading's ink run against a real canvas.
	lens.active = true
	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame
	lens.picks = {}
	lens.refresh()
	assert_true(lens.marks.is_empty(), "no pick, no mark")
	lens.free()


func test_severed_estate_reports_disconnected() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = resource_survey_Fixture.owned_resource_tile(model, works)
	works.set_improvement(model, tile, 1)
	works.set_prospected(owner, model, tile)
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, works, [], owner, null, Vector2i(-1, -1), {}
	)
	var row: Dictionary = _row(_entry(survey, model.province_at(tile.x, tile.y)), tile)
	assert_eq(String(row["status"]), "disconnected")
	assert_eq(int(row["output"]), 0)

func test_unknown_ground_is_never_surveyed() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: ProvinceState = model.provinces[0]
	var visibility := VisibilityModel.new()
	visibility.setup(model, owner)
	for tile: Vector2i in province.tiles:
		visibility.lower_to(
			model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, LandWorks.new(), [], owner, visibility
	)
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		assert_ne(int(entry["id"]), province.id)

func test_foreign_estates_say_whether_they_are_worked() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var tile: Vector2i = _foreign_resource_tile(model)
	assert_true(tile.x >= 0)
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: int = model.province_at(tile.x, tile.y)
	var survey: Dictionary = ResourceSurvey.snapshot(model, works, [], owner)
	assert_eq(String(_row(_entry(survey, province), tile)["status"]), "foreign")
	works.set_improvement(model, tile, 2)
	survey = ResourceSurvey.snapshot(model, works, [], owner)
	var row: Dictionary = _row(_entry(survey, province), tile)
	assert_eq(String(row["status"]), "foreign_worked")
	assert_eq(int(row["output"]), 0)

func test_builder_at_work_marks_building() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = resource_survey_Fixture.owned_resource_tile(model, works)
	var unit := CivilianState.create(1, owner, "builder", tile)
	unit.start_work("build_improvement", tile, 2)
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, works, [unit], owner, null, tile, {}
	)
	var entry: Dictionary = _entry(survey, model.province_at(tile.x, tile.y))
	var row: Dictionary = _row(entry, tile)
	assert_eq(String(row["status"]), "building")
	assert_eq(int(entry["counts"]["building"]), 1)
	assert_eq(int(entry["counts"]["worked"]), 0)
	assert_true(bool(row["working"]))
	assert_eq(int(row["remaining"]), 2)

func test_a_province_reads_one_row_per_resource_type() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var survey: Dictionary = ResourceSurvey.snapshot(model, LandWorks.new(), [], owner)
	var plates: int = 0
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		var types: Array = entry["types"]
		assert_false(types.is_empty(), "a province holding estates names its types")
		assert_true(types.size() <= ResourceTypes.ORDER.size())
		var held: int = 0
		for raw_type: Variant in types:
			var type_row: Dictionary = raw_type
			held += int(type_row["total"])
			assert_lte(int(type_row["linked"]), int(type_row["developed"]))
			assert_lte(int(type_row["developed"]), int(type_row["total"]))
			assert_eq(
				String(type_row["badge"]),
				ResourceTypes.badge(
					int(type_row["developed"]), int(type_row["linked"]),
					int(type_row["total"])
				)
			)
		assert_eq(held, (entry["rows"] as Array).size(), "every estate counts once, by type")
		plates += 1
	assert_gt(plates, 0)

func test_a_type_reads_its_estates_state_and_badge() -> void:
	var entry: Dictionary = {"rows": [
		_type_row("wheat", 1, true, "producing"),
		_type_row("wheat", 1, false, "disconnected"),
		_type_row("tree", 0, true, "foreign", false),
		_type_row("ore", 0, true, "vacant"),
		_type_row("coin", ImprovementCatalog.MAX_LEVEL, true, "maxed"),
		_type_row("wheat", 0, true, "building"),
	]}
	var types: Array[Dictionary] = ResourceTypes.rows(entry)
	assert_eq(types.size(), 4, "one row per emblem kind")
	assert_eq(String(types[0]["icon"]), "tree", "types read in the plate's order")
	assert_eq(String(types[0]["status"]), "foreign")
	assert_eq(String(types[1]["status"]), "vacant")
	assert_eq(String(types[2]["status"]), "maxed")
	# Two wheats built, one of them linked, three held, one under works: the
	# badge counts them and the ring says work is under way.
	assert_eq(String(types[3]["badge"]), "2/1/3")
	assert_eq(String(types[3]["status"]), "building")
	assert_eq(String(types[3]["name"]), "farm")

func test_a_built_type_counts_its_cut_estates() -> void:
	var entry: Dictionary = {"rows": [
		_type_row("ore", 1, true, "producing"),
		_type_row("ore", 1, false, "disconnected"),
	]}
	var types: Array[Dictionary] = ResourceTypes.rows(entry)
	assert_eq(types.size(), 1)
	assert_eq(String(types[0]["badge"]), "2/1/2", "one of the two built is cut off")
	assert_eq(String(types[0]["status"]), "disconnected")

func test_a_type_with_no_built_estate_is_vacant_not_disconnected() -> void:
	var entry: Dictionary = {"rows": [
		_type_row("ore", 0, true, "vacant"),
		_type_row("ore", 0, false, "foreign"),
	]}
	var types: Array[Dictionary] = ResourceTypes.rows(entry)
	assert_eq(types.size(), 1, "a foreign estate of the same kind stays in the column")
	assert_eq(String(types[0]["status"]), "vacant")
	assert_eq(String(types[0]["badge"]), "0/0/2")

func test_a_kind_outside_the_four_keeps_its_own_column() -> void:
	var entry: Dictionary = {"rows": [
		_type_row("wheat", 0, true, "vacant"),
		_type_row("cartload", 1, true, "producing"),
	]}
	var types: Array[Dictionary] = ResourceTypes.rows(entry)
	assert_eq(types.size(), 2)
	assert_eq(String(types[0]["icon"]), "wheat", "the known kinds read first")
	assert_eq(String(types[1]["icon"]), "cartload", "a kind the chart seeds later still shows")
	assert_eq(String(types[1]["name"]), "cartload")
	assert_eq(String(types[1]["badge"]), "1/1/1")

func test_the_hover_names_every_type_and_the_ground_still_to_read() -> void:
	var entry: Dictionary = {
		"rows": [
			_type_row("tree", 1, true, "producing"),
			_type_row("coin", 0, true, "vacant"),
		],
		"unsurveyed": 5,
	}
	entry["types"] = ResourceTypes.rows(entry)
	assert_eq(ResourceSurvey.summary_text(entry), "timber 1/1/1 · riches 0/0/1 · 5 unsurveyed")
	assert_eq(ResourceSurvey.summary_text({}), "")
	assert_eq(ResourceSurvey.summary_text({"rows": []}), "")

## One resource row as `ResourceSurvey._row` hands it to the type projection.
func _type_row(
	icon: String, level: int, connected: bool, status: String, ours: bool = true
) -> Dictionary:
	return {
		"icon": icon,
		"ours": ours,
		"level": level,
		"connected": connected,
		"status": status,
	}

func test_anchor_falls_back_to_a_charted_resource_tile() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var base: Dictionary = ResourceSurvey.snapshot(model, LandWorks.new(), [], owner)
	for raw: Variant in base["provinces"]:
		var entry: Dictionary = raw
		var center: Vector2 = entry["center"]
		var guess := Vector2i(roundi(center.x), roundi(center.y))
		if _row(entry, guess).size() > 0:
			continue
		var visibility := VisibilityModel.new()
		visibility.setup(model, owner)
		visibility.lower_to(
			model.index_of(guess.x, guess.y), VisibilityModel.Level.UNKNOWN
		)
		var survey: Dictionary = ResourceSurvey.snapshot(
			model, LandWorks.new(), [], owner, visibility
		)
		var moved: Dictionary = _entry(survey, int(entry["id"]))
		assert_false(moved.is_empty())
		var anchor: Vector2 = moved["anchor"]
		var anchor_tile := Vector2i(roundi(anchor.x), roundi(anchor.y))
		assert_ne(anchor_tile, guess)
		assert_ne(
			visibility.level_at(anchor_tile.x, anchor_tile.y),
			VisibilityModel.Level.UNKNOWN
		)
		return
	assert_true(false, "fixture needs a province whose centre is not a resource tile")

func test_a_hidden_mineral_is_never_surveyed_until_prospected() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = _owned_mineral_tile(model, works)
	if tile.x < 0:
		return
	var province: int = model.province_at(tile.x, tile.y)
	var survey: Dictionary = ResourceSurvey.snapshot(model, works, [], owner, null, tile)
	assert_true(_row(_entry(survey, province), tile).is_empty(),
		"an unsurveyed mineral has no survey row")
	assert_gt(
		MineralSurvey.unsurveyed_in_province(model, works, owner, province, null).size(),
		0, "the province still has ground to read"
	)
	# Once the crown prospects the tile the estate appears, unchanged by fog.
	works.set_prospected(owner, model, tile)
	survey = ResourceSurvey.snapshot(model, works, [], owner, null, tile)
	var row: Dictionary = _row(_entry(survey, province), tile)
	assert_false(row.is_empty(), "the survey now names the deposit")
	assert_true(bool(row["needs_prospecting"]))
	assert_true(bool(row["prospected"]))
	assert_eq(String(row["status"]), "vacant")

func test_the_dossier_reads_one_province_with_the_survey_vocabulary() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: ProvinceState = model.provinces[0]
	var rows: Array[Dictionary] = ResourceSurvey.province_rows(
		model, works, [], owner, province.id
	)
	var entry: Dictionary = _entry(
		ResourceSurvey.snapshot(model, works, [], owner), province.id
	)
	assert_eq(rows.size(), (entry["rows"] as Array).size(), "same estates as the lens")
	var surveyed: Array[Vector2i] = []
	for raw: Variant in entry["rows"]:
		surveyed.append((raw as Dictionary)["tile"])
	for row: Dictionary in rows:
		assert_true(province.tiles.has(row["tile"]), "only this province's tiles")
		assert_true(surveyed.has(row["tile"]), "the same tiles the lens draws")

func test_the_dossier_hides_estates_the_crown_has_not_charted() -> void:
	var model: MapModel = resource_survey_Fixture.region()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: ProvinceState = model.provinces[0]
	var visibility := VisibilityModel.new()
	visibility.setup(model, owner)
	for tile: Vector2i in province.tiles:
		visibility.lower_to(
			model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var rows: Array[Dictionary] = ResourceSurvey.province_rows(
		model, LandWorks.new(), [], owner, province.id, visibility
	)
	assert_true(rows.is_empty(), "unknown ground is never surveyed")

## One lane of owned land: a capital province west, a province east whose town
## sits south of the road, and one timber estate on the road at x=4.
func _lane(terrain: int, town_level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(6, 2)
	var groups: Dictionary = {0: [], 1: []}
	for y in 2:
		for x in 6:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			var province_id: int = 0 if x < 3 else 1
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	var provinces: Array[ProvinceState] = []
	for province_id in 2:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		provinces.append(ProvinceState.create(
			province_id, "P%d" % province_id, tiles, Vector2(2.0, 0.5),
			tiles.size(), FactionCatalog.PLAYER_FACTION, province_id == 0
		))
	provinces[0].capital_tile = Vector2i(0, 0)
	provinces[0].town_tile = Vector2i(0, 0)
	provinces[0].town_development = 4
	provinces[1].town_tile = Vector2i(3, 1)
	provinces[1].town_development = town_level
	model.provinces = provinces
	model.terrain[model.index_of(4, 0)] = terrain
	model.resource[model.index_of(4, 0)] = 0
	return model

## The lens row's yield and the Extraction phase's timber total for the estate.
func _read(model: MapModel, works: LandWorks) -> Dictionary:
	var owner: int = FactionCatalog.PLAYER_FACTION
	var entry: Dictionary = _entry(
		ResourceSurvey.snapshot(
			model, works, [], owner, null, Vector2i(0, 0), {"timber": 4}
		),
		1
	)
	var output: int = -1
	for row: Dictionary in entry["rows"]:
		if row["tile"] == Vector2i(4, 0):
			output = int(row["output"])
	var totals: Dictionary = Extraction.yields(
		model, owner, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	return {"lens": output, "phase": int(totals.get("timber", 0))}

## A non-capital estate on a rail path to the crown is not town-capped: town
## development limits only the Town-rule link (wiki: extraction-and-improvements
## § Extraction formula and town development cap).
func test_a_road_estate_is_not_priced_at_its_town_level() -> void:
	var model: MapModel = _lane(MapModel.Terrain.HARDWOOD_FOREST, 1)
	var works := LandWorks.new()
	for x in 6:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Vector2i(4, 0), 4)
	var read: Dictionary = _read(model, works)
	assert_eq(int(read["phase"]), 4, "a rail path to the crown pays in full")
	assert_eq(int(read["lens"]), 4, "the lens prices what the phase pays")

## The cap is the path's bottleneck, not the estate's own road level.
func test_a_bottleneck_behind_the_estate_caps_the_lens_reading() -> void:
	var model: MapModel = _lane(MapModel.Terrain.HARDWOOD_FOREST, 4)
	var works := LandWorks.new()
	for x in 6:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, Vector2i(4, 0), LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Vector2i(4, 0), 4)
	var read: Dictionary = _read(model, works)
	assert_eq(int(read["phase"]), 1, "the road west of the estate is the bottleneck")
	assert_eq(int(read["lens"]), 1, "the lens reads the path, not the tile")

## Scrub forest hard-caps timber at 1 after the tech cap; the map reading must
## consult it too (wiki: extraction-and-improvements § Terrain extraction hard
## caps — "the map-view builder action state").
func test_scrub_timber_is_read_at_its_terrain_cap() -> void:
	var model: MapModel = _lane(MapModel.Terrain.SCRUB_FOREST, 4)
	var works := LandWorks.new()
	for x in 6:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Vector2i(4, 0), 4)
	var read: Dictionary = _read(model, works)
	assert_eq(int(read["phase"]), 1, "scrub forest caps timber at level 1")
	assert_eq(int(read["lens"]), 1, "the lens cannot promise a yield the phase refuses")

func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}

## Two 4-adjacent land tiles the crown owns, for the road projection fixture.
func _owned_pair(model: MapModel) -> Array[Vector2i]:
	var pair: Array[Vector2i] = []
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next: Vector2i = tile + step
				if model.owner_at(next.x, next.y) != province.owner:
					continue
				pair.append(tile)
				pair.append(next)
				return pair
	return pair

## An owned land tile whose right or down neighbour is water (or off-chart), so
## the road walker hits the land/bounds guard without inventing a segment.
func _owned_coast_toward_sea(model: MapModel) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next: Vector2i = tile + step
				if not model.in_bounds(next.x, next.y) or not model.is_land(next.x, next.y):
					return tile
	return Vector2i(-1, -1)

func _row(entry: Dictionary, tile: Vector2i) -> Dictionary:
	if entry.is_empty():
		return {}
	for raw: Variant in entry["rows"]:
		var row: Dictionary = raw
		if row["tile"] == tile:
			return row
	return {}

func _foreign_resource_tile(model: MapModel) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner == FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if model.resource_at(tile.x, tile.y) >= 0:
				return tile
	return Vector2i(-1, -1)

func _owned_mineral_tile(model: MapModel, works: LandWorks) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			var resource: int = model.resource_at(tile.x, tile.y)
			if resource < 0 or not ImprovementCatalog.needs_prospecting(resource):
				continue
			if works.improvement_at(model, tile) > 0:
				continue
			return tile
	return Vector2i(-1, -1)

# --- test_crown_road_lens ---

func test_the_key_action_binds_the_r_key() -> void:
	_setup_crown_road_lens()
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.CROWN_LENS))
	assert_ne(InputActions.CROWN_LENS, InputActions.LENS)
	assert_ne(InputActions.CROWN_LENS, InputActions.DIPLOMACY_LENS)
	# The key still lands on the bar's one seal, which raises its reading.
	var event := InputEventAction.new()
	event.action = InputActions.CROWN_LENS
	event.pressed = true
	screen.hud.lens_seal._shortcut_input(event)
	assert_true(screen.play.crown_lens.active, "R names the crown road")
	MapPlayInput.set_crown_lens(screen.play, false)

func test_toggle_key_exclusivity_road_and_draw() -> void:
	_setup_crown_road_lens()
	var lens: CrownRoadLens = screen.play.crown_lens
	assert_not_null(lens)
	assert_false(lens.active)

	MapPlayInput.set_crown_lens(screen.play, true)
	assert_true(lens.active)
	assert_true(screen.hud.lens_legend.visible)
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	assert_true(screen.hud.lens_seal.button_pressed)
	assert_eq(screen.hud.lens_seal.active_kind, LensLegend.KIND_CROWN_ROAD)
	assert_gt(int(lens.survey["tiles"][CrownRoadSurvey.STATE_ROAD]), 0)
	assert_almost_eq(screen.civilian_layer.modulate.a, 0.22, 0.001)

	# Exclusivity: survey then diplomacy then crown again.
	MapPlayInput.set_lens(screen.play, true)
	assert_true(screen.play.lens.active)
	assert_false(lens.active)
	MapPlayInput.set_diplomacy_lens(screen.play, true)
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	MapPlayInput.set_crown_lens(screen.play, true)
	assert_true(lens.active)
	assert_false(screen.play.diplomacy_lens.active)
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)

	# A finished road repaints without polling.
	var before: int = int(lens.survey["tiles"][CrownRoadSurvey.STATE_CUT])
	var step: Vector2i = _frontier_tile()
	assert_true(step.x >= 0, "the map offers a tile the crown network can grow into")
	screen.play.land_works.set_transport(screen.model, step, LandWorks.TRANSPORT_ROAD)
	screen.civilian_layer.refresh_works()
	assert_lt(int(lens.survey["tiles"][CrownRoadSurvey.STATE_CUT]), before)

	# Draw path for a cut province + hover line.
	var province: ProvinceState = screen.model.provinces[0]
	var anchor: Vector2i = province.tiles[0]
	var survey: Dictionary = lens.survey.duplicate(true)
	survey["provinces"] = [{
		"id": province.id,
		"name": province.name,
		"state": CrownRoadSurvey.STATE_CUT,
		"linked": false,
		"gap": 2,
		"town": anchor,
		"town_level": 1,
		"anchor": anchor,
		"cut_tiles": 3,
		"charted": VisibilityModel.Level.FULLY_VISIBLE,
	}]
	survey["routes"] = [{
		"province": province.id,
		"town": anchor,
		"gap": 2,
		"tiles": [anchor, province.tiles[1]],
	}]
	lens.survey = survey
	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame
	assert_eq(
		lens.summary_for(province.id), "Crown road: 2 road tiles from the crown"
	)

	var entry: Dictionary = _linked_entry()
	if not entry.is_empty():
		var linked: ProvinceState = screen.model.province_data(int(entry["id"]))
		var point: Vector2 = _screen_point(linked.center)
		MapPlayInput.update_hover(screen.play, point)
		assert_true(screen.hud._tooltip_label.text.contains("Crown road: "))

	# The seal's menu names "No lens", which drops the reading.
	screen.hud.lens_seal.choose("")
	assert_false(lens.active)
	assert_false(screen.hud.lens_legend.visible)

func test_region_switch_and_rail_budget() -> void:
	_setup_crown_road_lens()
	MapPlayInput.set_crown_lens(screen.play, true)
	screen._cycle_region()
	assert_eq(screen.play.crown_lens.model, screen.model)
	assert_eq(int(screen.play.crown_lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(screen.play.crown_lens.survey.has("runs"))
	screen.load_region(0)

	# The reading rides the cartouche now, and the rail below it is empty: the
	# estates and Gazette doors moved onto the bar (REQ-P1-07).
	var hud: GameHud = screen.hud
	var seal: Rect2 = hud.lens_seal.get_global_rect()
	var bar: Rect2 = hud.top_bar.get_global_rect()
	assert_gt(seal.size.x, 0.0, "the lens seal is on the bar")
	assert_true(seal.position.y >= bar.position.y and seal.end.y <= bar.end.y + 0.5, "seal inside the bar")
	assert_eq(HudLayout.LEFT_RAIL, 0.0, "nothing is parked on the left rail")
	assert_not_null(hud.top_row.find_child("EstatesSeal", true, false), "estates door on the bar")
	assert_not_null(hud.top_row.find_child("GazetteSeal", true, false), "Gazette door on the bar")
	MapPlayInput.set_crown_lens(screen.play, true)
	assert_eq(hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	assert_true(hud.lens_legend.visible)

func _frontier_tile() -> Vector2i:
	var resolved: Dictionary = LandConnectivity.resolve(
		screen.model, screen.play.land_works, screen.player_faction,
		screen.play.capital_tile
	)
	var network: Dictionary = resolved.get("network", {}) as Dictionary
	var reached: Dictionary = resolved.get("tiles", {}) as Dictionary
	for raw: Variant in reached.keys():
		var index: int = int(raw)
		if network.has(index):
			continue
		var tile: Vector2i = _tile_of(index)
		if screen.play.land_works.transport_at(screen.model, tile) != 0:
			continue
		for offset: Vector2i in RoadWorks.NEIGHBORS:
			var next: Vector2i = tile + offset
			if not screen.model.in_bounds(next.x, next.y):
				continue
			if not screen.model.is_land(next.x, next.y):
				continue
			if screen.model.owner_at(next.x, next.y) != screen.player_faction:
				continue
			if reached.has(screen.model.index_of(next.x, next.y)):
				continue
			return tile
	return Vector2i(-1, -1)

func _tile_of(index: int) -> Vector2i:
	var y: int = int(float(index) / float(screen.model.width))
	return Vector2i(index - y * screen.model.width, y)

func _linked_entry() -> Dictionary:
	for raw: Variant in screen.play.crown_lens.survey.get("provinces", []):
		var entry: Dictionary = raw
		if bool(entry.get("linked", false)):
			return entry
	return {}

func _screen_point(world_in_tiles: Vector2) -> Vector2:
	var world: Vector2 = world_in_tiles * MapScreen.TILE_SIZE
	screen.camera.focus_on(world, 0.8, true)
	screen.camera._process(0.016)
	return CameraMath.world_to_screen(
		screen.camera.position, screen.camera.zoom.x, world,
		screen.camera.viewport_size()
	)

# ==== merged from test_map_data_rules.gd (one coverage boot; docs/testing.md § Speed rules) ====
## One boot for the map data: the model and region table, fog visibility, and the
## world/store halves of a save (wiki: the-map).

## Merged from test_map_model, test_map_region_table, test_visibility,
## test_save_world, test_save_store, test_province_graph.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.

const PLAYER: int = 0
const DIR: String = "user://test_save_store"

var data__model: MapModel = null
var _visibility_model: MapModel = null
var data__visibility: VisibilityModel = null

var data__suite_setup: String = ""

func _data_after_each() -> void:
	match data__suite_setup:
		"save_store":
			_teardown_save_store()
	data__suite_setup = ""

func _setup_map_model() -> void:
	data__suite_setup = "map_model"
	data__model = MapModel.new()
	data__model.setup(4, 3)
	for x in 4:
		data__model.terrain[data__model.index_of(x, 0)] = MapModel.Terrain.PLAINS
	data__model.terrain[data__model.index_of(1, 1)] = MapModel.Terrain.HARDWOOD_FOREST
	data__model.terrain[data__model.index_of(2, 1)] = MapModel.Terrain.SHALLOW
	data__model.province[data__model.index_of(0, 0)] = 0
	data__model.province[data__model.index_of(1, 0)] = 0
	data__model.province[data__model.index_of(1, 1)] = 1
	data__model.sea_zone[data__model.index_of(2, 1)] = 0
	data__model.sea_zone[data__model.index_of(3, 1)] = 0
	var cadiz_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var coro_tiles: Array[Vector2i] = [Vector2i(1, 1)]
	var sea_tiles: Array[Vector2i] = [Vector2i(2, 1), Vector2i(3, 1)]
	data__model.provinces = [
		ProvinceState.create(0, "Cádiz", cadiz_tiles, Vector2(1.0, 0.5), 2, 0, true),
		ProvinceState.create(1, "Coro", coro_tiles, Vector2(1.5, 1.5), 1, 1, false),
	]
	data__model.sea_zones = [
		SeaZoneState.create(0, "Mar Caribe", sea_tiles, Vector2(3.0, 1.5), 2),
	]

func _setup_visibility() -> void:
	data__suite_setup = "visibility"
	_visibility_model = _build_region()
	data__visibility = VisibilityModel.new()
	data__visibility.setup(_visibility_model, PLAYER)

func _setup_save_store() -> void:
	data__suite_setup = "save_store"
	_clean_dir()

func _teardown_save_store() -> void:
	_clean_dir()

# --- test_map_model ---

func test_setup_sizes_and_clears_arrays() -> void:
	_setup_map_model()
	var fresh := MapModel.new()
	fresh.setup(7, 5)
	assert_eq(fresh.terrain.size(), 35)
	assert_eq(fresh.province.size(), 35)
	assert_eq(fresh.province[0], MapModel.NO_ID)
	assert_eq(fresh.province_count(), 0)

func test_capital_tile_follows_the_province_record() -> void:
	_setup_map_model()
	data__model.provinces[0].capital_tile = Vector2i(0, 0)
	assert_eq(data__model.capital_tile_of(0), Vector2i(0, 0))
	assert_eq(data__model.capital_tile_of(1), CapitalChoice.NO_TILE)
	assert_eq(data__model.capital_tile_of(-1), CapitalChoice.NO_TILE)

func test_land_and_sea_classification() -> void:
	_setup_map_model()
	assert_true(data__model.is_land(0, 0))
	assert_false(data__model.is_land(2, 1))
	assert_true(data__model.is_sea(2, 1))
	assert_false(data__model.is_land(-1, 0))
	assert_false(data__model.is_land(0, 99))

func test_out_of_bounds_reads_as_ocean_and_no_id() -> void:
	_setup_map_model()
	assert_eq(data__model.terrain_at(50, 50), MapModel.Terrain.OCEAN)
	assert_eq(data__model.province_at(50, 50), MapModel.NO_ID)
	assert_eq(data__model.sea_zone_at(-3, 0), MapModel.NO_ID)

func test_province_lookup_helpers() -> void:
	_setup_map_model()
	assert_eq(data__model.province_at(1, 0), 0)
	assert_eq(data__model.province_name(1), "Coro")
	assert_eq(data__model.province_owner(1), 1)
	assert_eq(data__model.province_owner(99), MapModel.NO_ID)
	assert_eq(data__model.province_center(0), Vector2(1.0, 0.5))
	assert_eq(data__model.province_tiles(99), [])

func test_coastal_tiles_touch_sea() -> void:
	_setup_map_model()
	assert_true(MapGeo.is_coastal_tile(data__model, 1, 1))
	assert_false(MapGeo.is_coastal_tile(data__model, 1, 0))
	assert_false(MapGeo.is_coastal_tile(data__model, 2, 1))
	assert_eq(MapGeo.coastal_tiles(data__model, 1), [Vector2i(1, 1)])

func test_map_border_is_not_a_coast() -> void:
	_setup_map_model()
	var border := MapModel.new()
	border.setup(3, 3)
	for index in border.terrain.size():
		border.terrain[index] = MapModel.Terrain.PLAINS
	assert_false(MapGeo.is_coastal_tile(border, 0, 0))
	assert_false(MapGeo.is_coastal_tile(border, 2, 2))

func test_tile_deeds_override_the_province_owner() -> void:
	_setup_map_model()
	var tile := Vector2i(1, 1)
	assert_eq(data__model.owner_at(tile.x, tile.y), 1)
	assert_true(data__model.purchase_tile(tile, 6))
	assert_eq(data__model.owner_at(tile.x, tile.y), 6)
	assert_eq(data__model.province_owner(1), 1, "the province itself does not change hands")
	assert_true(data__model.is_purchased_tile(tile))
	assert_false(data__model.purchase_tile(tile, 7), "one deed per tile")

func test_owned_tiles_follow_deeds_in_both_directions() -> void:
	_setup_map_model()
	var deed := Vector2i(1, 1)
	assert_true(data__model.purchase_tile(deed, 6))
	var ownership: TileOwnership = data__model.ownership
	assert_true(ownership.owned_tiles(data__model, 6).has(deed), "buyer holds the enclave")
	assert_false(ownership.owned_tiles(data__model, 1).has(deed), "seller no longer holds it")
	assert_true(
		ownership.owned_tiles(data__model, 0).has(Vector2i(0, 0)),
		"ordinary province tiles remain"
	)

func test_tile_deeds_round_trip_through_plain_data() -> void:
	_setup_map_model()
	assert_true(data__model.purchase_tile(Vector2i(1, 1), 6))
	var restored := TileOwnership.new()
	restored.apply_dict(data__model.ownership.to_dict())
	assert_true(restored.is_purchased(data__model.index_of(1, 1)))
	assert_eq(restored.owner_of(data__model.index_of(1, 1), -1), 6)

func test_province_neighbors_are_cached_and_sorted() -> void:
	_setup_map_model()
	assert_eq(MapGeo.province_neighbors(data__model, 0), [1])
	assert_true(data__model.provinces[0].neighbors_cached)
	assert_eq(MapGeo.province_neighbors(data__model, 99), [])

func test_sea_zone_neighbors() -> void:
	_setup_map_model()
	var second := MapModel.new()
	second.setup(3, 1)
	second.sea_zone[0] = 0
	second.sea_zone[1] = 0
	second.sea_zone[2] = 1
	var tiles_a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tiles_b: Array[Vector2i] = [Vector2i(2, 0)]
	second.sea_zones = [
		SeaZoneState.create(0, "A", tiles_a, Vector2.ZERO, 2),
		SeaZoneState.create(1, "B", tiles_b, Vector2.ZERO, 1),
	]
	assert_eq(MapGeo.sea_zone_neighbors(second, 0), [1])
	assert_eq(MapGeo.sea_zone_neighbors(second, 99), [])

func test_world_helpers() -> void:
	_setup_map_model()
	assert_eq(MapGeo.world_size(data__model, 10.0), Vector2(40.0, 30.0))
	assert_eq(MapGeo.tile_center(0, 0, 10.0), Vector2(5.0, 5.0))
	assert_eq(MapGeo.tile_at_world(Vector2(15.0, 25.0), 10.0), Vector2i(1, 2))

func test_land_tile_count() -> void:
	_setup_map_model()
	assert_eq(MapGeo.land_tile_count(data__model), 5)

func test_terrain_labels_cover_every_type() -> void:
	_setup_map_model()
	for terrain in MapModel.Terrain.values():
		assert_true(MapModel.TERRAIN_LABELS.has(terrain))

func test_palette_covers_every_terrain() -> void:
	_setup_map_model()
	for terrain in MapModel.Terrain.values():
		assert_true(terrain < Palette.TERRAIN_COLORS.size())
	assert_eq(Palette.faction_color(-1), Palette.INK_LINE)
	assert_eq(Palette.faction_color(99), Palette.INK_LINE)
	assert_eq(Palette.terrain_color(99), Color(0.5, 0.5, 0.5))

# --- test_map_region_table ---

func test_missing_region_falls_back_without_creating_a_row() -> void:
	var table := MapRegionTable.new()

	assert_false(table.has_region(3))
	assert_eq(table.value(3, []), [])
	assert_false(table.has_region(3))

func test_rows_are_addressed_by_region_and_clear_together() -> void:
	var table := MapRegionTable.new()
	var roster: Array[int] = [1, 2]
	table.set_region(5, roster)
	table.set_region(2, [9])

	assert_true(table.has_region(5))
	assert_eq(table.value(5, []), [1, 2])
	assert_eq(table.region_ids(), [2, 5])
	assert_eq(table.values().size(), 2)

	table.clear()
	assert_false(table.has_region(5))
	assert_eq(table.values(), [])

func test_snapshot_copies_rosters_so_readers_do_not_alias_live_state() -> void:
	var table := MapRegionTable.new()
	var roster: Array[int] = [1, 2]
	table.set_region(5, roster)
	table.set_region(2, 7)

	var snap: Dictionary = table.snapshot()

	assert_eq(snap.size(), 2)
	assert_eq(snap[5], [1, 2])
	assert_eq(snap[2], 7)
	var live: Array = table.value(5, [])
	live.append(9)
	assert_eq(snap[5], [1, 2], "the snapshot copied the roster")
	table.set_region(5, [4])
	assert_eq(snap[5], [1, 2], "the snapshot does not follow later writes")

func test_encode_walks_rosters_and_single_values() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, 2])
	table.set_region(1, 7)
	table.set_region(2, [])

	var encoded: Dictionary = table.encode(
		func(item: Variant) -> Dictionary: return {"n": int(item)}
	)

	assert_eq(encoded[0], [{"n": 1}, {"n": 2}])
	assert_eq(encoded[1], {"n": 7})
	assert_eq(encoded[2], [])

func test_encode_drops_null_entries_and_null_rows() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, null, 2])
	table.set_region(1, null)

	var encoded: Dictionary = table.encode(func(item: Variant) -> int: return int(item))

	assert_eq(encoded[0], [1, 2])
	assert_false(encoded.has(1))

func test_decode_replaces_rows_and_skips_null_results() -> void:
	var table := MapRegionTable.new()
	table.set_region(9, 99)

	table.decode({0: 4, 1: 5, 2: 6}, func(raw: Variant) -> Variant:
		return null if int(raw) == 5 else int(raw)
	)

	assert_eq(table.value(0, -1), 4)
	assert_eq(table.value(2, -1), 6)
	assert_false(table.has_region(1))
	assert_false(table.has_region(9))

# --- test_visibility ---

func test_old_world_starts_fogged_before_the_setup_pass() -> void:
	_setup_visibility()
	assert_eq(data__visibility.level_at(0, 0), VisibilityModel.Level.FOGGED)
	assert_eq(data__visibility.level_at(11, 5), VisibilityModel.Level.FOGGED)

func test_new_world_starts_unknown_until_a_reveal() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	var view := VisibilityModel.new()
	view.setup(map, PLAYER)
	var unknown: int = 0
	for index in view.levels.size():
		if view.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown += 1
	assert_eq(unknown, view.levels.size(), "New World starts unknown, not fogged")
	view.apply_initial()
	unknown = 0
	for index in view.levels.size():
		if view.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown += 1
	assert_eq(unknown, view.levels.size(), "no ownership means no setup reveal")

func test_new_world_setup_still_lights_land_the_player_owns() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	map.provinces[0].owner = PLAYER
	var view := VisibilityModel.new()
	view.setup(map, PLAYER)
	view.apply_initial()
	var tile: Vector2i = map.province_tiles(0)[0]
	assert_eq(view.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)

func test_coast_links_follow_the_tile_grid() -> void:
	_setup_visibility()
	assert_eq(data__visibility.province_sea_zones.get(0), [0])
	assert_eq(data__visibility.province_sea_zones.get(3), [1, 2])
	assert_false(data__visibility.sea_zone_provinces.has(3))
	assert_false(data__visibility.sea_zone_provinces.has(4))

func test_setup_makes_own_provinces_visible_and_rival_land_fogged() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	assert_eq(data__visibility.level_at(0, 0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(6, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)
	assert_eq(data__visibility.level_at(5, 0), VisibilityModel.Level.FOGGED)

func test_setup_reveals_sea_zones_next_to_owned_coast() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	for tile: Vector2i in [
		Vector2i(0, 4), Vector2i(3, 5), Vector2i(4, 4), Vector2i(6, 5), Vector2i(7, 0)
	]:
		assert_eq(data__visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(8, 0), VisibilityModel.Level.FOGGED)
	assert_eq(data__visibility.level_at(11, 5), VisibilityModel.Level.FOGGED)

func test_ship_reveal_lights_water_and_the_strict_coastal_ring_only() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	var changed: Array = data__visibility.reveal_sea_zone(0)
	assert_eq(changed.size(), 2)
	assert_eq(data__visibility.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(3, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(4, 3), VisibilityModel.Level.FOGGED)
	assert_eq(data__visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)

func test_ship_reveal_opens_open_water_without_touching_land() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	var changed: Array = data__visibility.reveal_sea_zone(3)
	assert_eq(changed.size(), 18)
	assert_eq(data__visibility.level_at(8, 0), VisibilityModel.Level.FULLY_VISIBLE)


## A crown whose leader publishes the charting lean charts one further orthogonal
## land ring off the strict coastal ring, and stops there (wiki: leader-bonuses
## § Bonus Table — Henry the Navigator).
func test_the_charting_leader_adds_one_coastal_land_ring() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	var charted: Array = data__visibility.reveal_sea_zone(
		0, LeaderCatalog.coastal_rings("henry")
	)
	assert_eq(charted.size(), 5, "the strict coastal ring plus one further step")
	assert_eq(data__visibility.level_at(2, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(3, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(
		data__visibility.level_at(4, 3), VisibilityModel.Level.FULLY_VISIBLE,
		"the ring wraps the end of the coast, one step inland"
	)
	assert_eq(
		data__visibility.level_at(2, 1), VisibilityModel.Level.FOGGED,
		"the bonus is one ring, not the province interior"
	)


func test_a_ship_reveal_without_the_charting_leader_keeps_the_strict_ring() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	assert_eq(LeaderCatalog.coastal_rings("de_ruyter"), 0)
	var changed: Array = data__visibility.reveal_sea_zone(0)
	assert_eq(changed.size(), 2)
	assert_eq(data__visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)

func test_end_of_turn_decays_only_foreign_fully_visible_land() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	data__visibility.reveal_sea_zone(0)
	data__visibility.end_of_turn([])
	assert_eq(data__visibility.level_at(2, 3), VisibilityModel.Level.FOGGED)
	assert_eq(data__visibility.level_at(0, 0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(6, 2), VisibilityModel.Level.FULLY_VISIBLE)

func test_end_of_turn_never_raises_unknown_tiles() -> void:
	_setup_visibility()
	var index: int = _visibility_model.index_of(8, 0)
	data__visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	data__visibility.end_of_turn([])
	assert_eq(data__visibility.level_at(8, 0), VisibilityModel.Level.UNKNOWN)

func test_end_of_turn_fogs_distant_sea_without_a_fleet() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	data__visibility.reveal_sea_zone(3)
	data__visibility.end_of_turn([])
	assert_eq(data__visibility.level_at(8, 0), VisibilityModel.Level.FOGGED)

func test_end_of_turn_keeps_a_zone_where_the_fleet_rides() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	data__visibility.reveal_sea_zone(3)
	data__visibility.end_of_turn([3])
	assert_eq(data__visibility.level_at(8, 0), VisibilityModel.Level.FULLY_VISIBLE)

func test_owning_a_coast_reveals_its_zone_at_end_of_turn() -> void:
	_setup_visibility()
	_visibility_model.provinces[1].owner = PLAYER
	data__visibility.end_of_turn([])
	assert_eq(data__visibility.level_at(2, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(3, 3), VisibilityModel.Level.FULLY_VISIBLE)

func test_losing_the_only_coast_fogs_its_zone() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	_visibility_model.provinces[3].owner = 2
	data__visibility.end_of_turn([])
	assert_eq(data__visibility.level_at(4, 4), VisibilityModel.Level.FOGGED)
	assert_eq(data__visibility.level_at(7, 0), VisibilityModel.Level.FOGGED)
	assert_eq(data__visibility.level_at(0, 4), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(5, 2), VisibilityModel.Level.FOGGED)

func test_a_purchased_tile_stays_visible_in_a_rival_province() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	var tile := Vector2i(2, 2)
	assert_true(_visibility_model.purchase_tile(tile, PLAYER))
	data__visibility.end_of_turn([])
	assert_eq(data__visibility.level_at(2, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(3, 2), VisibilityModel.Level.FOGGED)

func test_each_player_has_an_independent_map() -> void:
	_setup_visibility()
	var rival := VisibilityModel.new()
	rival.setup(_visibility_model, 1)
	rival.apply_initial()
	data__visibility.apply_initial()
	data__visibility.reveal_sea_zone(0)
	assert_eq(rival.level_at(0, 0), VisibilityModel.Level.FOGGED)
	assert_eq(rival.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)

func test_knowledge_levels_are_ordered() -> void:
	_setup_visibility()
	var index: int = _visibility_model.index_of(2, 2)
	assert_false(data__visibility.raise_to(index, VisibilityModel.Level.FOGGED))
	assert_true(data__visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE))
	assert_false(data__visibility.raise_to(index, VisibilityModel.Level.FOGGED))
	assert_false(data__visibility.lower_to(index, VisibilityModel.Level.FULLY_VISIBLE))
	assert_true(data__visibility.lower_to(index, VisibilityModel.Level.FOGGED))
	assert_false(data__visibility.lower_to(index, VisibilityModel.Level.FOGGED))

func test_reveal_province_opens_every_tile() -> void:
	_setup_visibility()
	var changed: Array = data__visibility.reveal_province(1)
	assert_true(changed.size() > 0)
	assert_true(data__visibility.is_province_fully_visible(1))

func test_civilian_presence_holds_a_foreign_province() -> void:
	_setup_visibility()
	data__visibility.reveal_province(1)
	data__visibility.end_of_turn([], [1])
	assert_true(data__visibility.is_province_fully_visible(1))
	data__visibility.end_of_turn([])
	assert_false(data__visibility.is_province_fully_visible(1))

func test_a_departed_spy_leaves_five_turns_of_charter() -> void:
	_setup_visibility()
	# Spy timer expiry (wiki: fog-and-exploration § Spy timer expiry): the
	# province a Spy leaves keeps its charted tiles for five turns, then decays.
	data__visibility.reveal_province(1)
	data__visibility.end_of_turn([], [1], [1])
	assert_eq(data__visibility.spy_charter.left(1), SpyCharter.TURNS)
	for turn in SpyCharter.TURNS:
		data__visibility.end_of_turn([], [], [])
		assert_true(
			data__visibility.is_province_fully_visible(1),
			"turn %d of the grace still reads the province" % (turn + 1)
		)
	data__visibility.end_of_turn([], [], [])
	assert_false(
		data__visibility.is_province_fully_visible(1), "the sixth turn puts it back in the fog"
	)
	assert_eq(data__visibility.spy_charter.left(1), 0)

func test_a_spy_in_the_province_holds_it_again() -> void:
	_setup_visibility()
	data__visibility.reveal_province(1)
	data__visibility.end_of_turn([], [1], [1])
	data__visibility.end_of_turn([], [], [])
	assert_eq(data__visibility.spy_charter.left(1), 4)
	# A spy posted again resets the clock rather than letting it run out.
	data__visibility.end_of_turn([], [1], [1])
	assert_eq(data__visibility.spy_charter.left(1), SpyCharter.TURNS)

func test_a_spy_never_times_out_on_its_own_ground() -> void:
	_setup_visibility()
	var units: Array[CivilianState] = [
		CivilianState.create(1, PLAYER, "spy", Vector2i(0, 1)),
		CivilianState.create(2, PLAYER, "explorer", Vector2i(3, 1)),
		CivilianState.create(3, PLAYER, "spy", Vector2i(3, 1)),
	]
	var spies: Array = CivilianMovement.spy_provinces(_visibility_model, units, PLAYER)
	assert_eq(spies, [1], "only the rival province takes a timer")
	data__visibility.reveal_province(0)
	data__visibility.end_of_turn([], [], spies)
	assert_eq(data__visibility.spy_charter.left(0), 0, "own ground never carries a timer")

func test_the_spy_grace_survives_a_save() -> void:
	_setup_visibility()
	data__visibility.reveal_province(1)
	data__visibility.end_of_turn([], [1], [1])
	data__visibility.end_of_turn([], [], [])
	var restored := VisibilityModel.new()
	restored.setup(_visibility_model, PLAYER)
	assert_true(restored.apply_dict(data__visibility.to_dict()))
	assert_eq(restored.spy_charter.left(1), 4, "the counter is carried with the grid")
	var legacy := data__visibility.to_dict()
	legacy.erase("spy_hold")
	var old_save := VisibilityModel.new()
	old_save.setup(_visibility_model, PLAYER)
	assert_true(old_save.apply_dict(legacy), "a save without the counter still loads")
	assert_eq(old_save.spy_charter.left(1), 0, "and starts with no timer")

func test_a_junk_charter_payload_starts_empty() -> void:
	var charter := SpyCharter.new()
	charter.apply_dict("not a dictionary")
	assert_eq(charter.left(1), 0, "junk is dropped, never invented")
	charter.apply_dict({1: 0, 2: 3})
	assert_eq(charter.left(1), 0, "a spent clock is not carried")
	assert_eq(charter.left(2), 3, "a live clock is")
	assert_eq(charter.book([-1, 2], []), [2], "a bad id is skipped, the spy still holds")

func test_presence_never_surveys_unknown_terrain() -> void:
	_setup_visibility()
	for tile: Vector2i in _visibility_model.province_tiles(1):
		var index: int = _visibility_model.index_of(tile.x, tile.y)
		data__visibility.levels[index] = VisibilityModel.Level.UNKNOWN
	var held: Array = data__visibility.hold_explored_province(1)
	var unknown_left: int = 0
	for tile: Vector2i in _visibility_model.province_tiles(1):
		var index: int = _visibility_model.index_of(tile.x, tile.y)
		if data__visibility.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown_left += 1
	assert_eq(held, [], "presence holds nothing unknown")
	assert_eq(unknown_left, 12, "every tile stays unknown")

func test_presence_holds_only_the_fogged_tile() -> void:
	_setup_visibility()
	var tiles: Array[Vector2i] = _visibility_model.province_tiles(1)
	var charted: Vector2i = tiles[0]
	var charted_index: int = _visibility_model.index_of(charted.x, charted.y)
	data__visibility.levels[charted_index] = VisibilityModel.Level.UNKNOWN
	var opened: int = data__visibility.hold_explored_province(1).size()
	var charted_level: int = data__visibility.level_at_index(charted_index)
	var still_unknown: int = 0
	for tile: Vector2i in tiles:
		if data__visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN:
			still_unknown += 1
	assert_eq(opened, 11, "every fogged tile is held")
	assert_eq(charted_level, VisibilityModel.Level.UNKNOWN, "unknown stays unknown")
	assert_eq(still_unknown, 1, "only the cleared tile stays unknown")

func test_a_spy_holds_the_province_it_shadows() -> void:
	_setup_visibility()
	# Presence holds, presence never reveals (DR-20261109-04): a spy posted in a
	# rival province keeps its charted tiles in view for its own crown.
	var units: Array[CivilianState] = []
	units.append(CivilianState.create(1, PLAYER, "spy", Vector2i(2, 2)))
	units.append(CivilianState.create(2, 1, "explorer", Vector2i(2, 2)))
	assert_eq(CivilianMovement.held_provinces(_visibility_model, units, PLAYER), [1], "a spy holds")
	assert_eq(CivilianMovement.held_provinces(_visibility_model, units, 1), [1], "own explorer holds")
	assert_eq(
		CivilianMovement.held_provinces(_visibility_model, units, 2), [],
		"another crown reads nothing from these units"
	)

func test_a_spy_never_promotes_unknown_ground() -> void:
	_setup_visibility()
	# A New World province starts unknown; a spy posted there holds it but the
	# tiles stay dark until an Explorer surveys them (DR-20261109-04).
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	var view := VisibilityModel.new()
	view.setup(map, PLAYER)
	var units: Array[CivilianState] = [CivilianState.create(1, PLAYER, "spy", Vector2i(2, 2))]
	assert_eq(CivilianMovement.held_provinces(map, units, PLAYER), [1], "posted")
	assert_eq(view.hold_explored_province(1), [], "unknown ground never opens")
	assert_eq(
		view.province_visibility(1), VisibilityModel.Level.UNKNOWN,
		"the province stays unknown"
	)

func test_province_visibility_uses_the_highest_tile() -> void:
	_setup_visibility()
	data__visibility.apply_initial()
	assert_eq(data__visibility.province_visibility(0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(data__visibility.province_visibility(1), VisibilityModel.Level.FOGGED)
	assert_true(data__visibility.is_province_known(1))
	assert_false(data__visibility.is_province_fully_visible(1))
	data__visibility.reveal_sea_zone(0)
	assert_false(data__visibility.is_province_fully_visible(1))
	for tile: Vector2i in _visibility_model.province_tiles(1):
		data__visibility.raise_to(_visibility_model.index_of(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_true(data__visibility.is_province_fully_visible(1))

func test_out_of_range_reads_are_safe() -> void:
	_setup_visibility()
	assert_eq(data__visibility.level_at(-1, 0), VisibilityModel.Level.UNKNOWN)
	assert_eq(data__visibility.level_at_index(9999), VisibilityModel.Level.UNKNOWN)
	assert_false(data__visibility.raise_to(-1, VisibilityModel.Level.FULLY_VISIBLE))
	assert_false(data__visibility.lower_to(9999, VisibilityModel.Level.UNKNOWN))
	assert_eq(data__visibility.reveal_sea_zone(99), [])
	assert_eq(data__visibility.province_visibility(99), VisibilityModel.Level.UNKNOWN)
	assert_false(data__visibility.is_province_fully_visible(99))
	assert_false(data__visibility.owns_coast(99))

func test_unassigned_tiles_are_ignored() -> void:
	_setup_visibility()
	var map := MapModel.new()
	map.setup(4, 2)
	for x in 4:
		map.terrain[map.index_of(x, 0)] = MapModel.Terrain.PLAINS
	for x in range(1, 4):
		map.province[map.index_of(x, 0)] = 0
	var lonely_tiles: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	map.provinces.append(
		ProvinceState.create(0, "Lonely", lonely_tiles, Vector2.ZERO, 3, PLAYER)
	)
	for x in 2:
		map.sea_zone[map.index_of(x, 1)] = 0
	var bay_tiles: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
	map.sea_zones.append(SeaZoneState.create(0, "Bay", bay_tiles, Vector2.ZERO, 2))
	var orphan_tiles: Array[Vector2i] = []
	map.sea_zones.append(SeaZoneState.create(1, "Orphan", orphan_tiles, Vector2.ZERO, 0))

	var visibility := VisibilityModel.new()
	visibility.setup(map, PLAYER)
	visibility.apply_initial()
	assert_eq(visibility.province_sea_zones.get(0), [0])
	assert_eq(visibility.level_at(0, 1), VisibilityModel.Level.FULLY_VISIBLE)
	visibility.end_of_turn([])
	assert_eq(visibility.level_at(0, 0), VisibilityModel.Level.FOGGED)

## One region as a world with a rival chart per Great Power. `human_views` is
## the table the session's own grid lives in, so the human court routes there.
func _charts_for(model: MapModel, human_views: Dictionary = {}) -> CourtCharts:
	var world := WorldMap.new()
	world.add_region(model)
	var charts := CourtCharts.new()
	charts.setup(world, PLAYER, human_views)
	return charts

func test_every_rival_carries_its_own_chart() -> void:
	_setup_visibility()
	var charts: CourtCharts = _charts_for(_visibility_model)
	var rival: int = FactionCatalog.great_power_ids()[1]
	var other: int = FactionCatalog.great_power_ids()[2]
	var view: VisibilityModel = charts.model_for(rival, 0)
	assert_true(view != null, "a rival Great Power has a chart")
	assert_eq(view.player_id, rival)
	assert_true(view != charts.model_for(other, 0), "each court reads its own grid")

func test_a_rival_chart_is_cut_only_when_a_rule_reads_it() -> void:
	_setup_visibility()
	var charts: CourtCharts = _charts_for(_visibility_model)
	assert_true(charts.courts.is_empty(), "mounting a chart cuts no rival grid")
	var rival: int = FactionCatalog.great_power_ids()[1]
	assert_not_null(charts.model_for(rival, 0), "the first read cuts that court")
	assert_eq(charts.courts.size(), 1, "and only that court")
	assert_not_null(charts.regions_of(rival), "a table read cuts the whole court")

func test_a_save_carries_every_rival_chart_even_when_unread() -> void:
	_setup_visibility()
	var charts: CourtCharts = _charts_for(_visibility_model)
	assert_true(charts.courts.is_empty(), "nothing was read before the save")
	var data: Dictionary = charts.to_dict()
	var courts: Dictionary = data["courts"]
	assert_eq(
		courts.size(), FactionCatalog.great_power_ids().size() - 1,
		"the save still carries one grid per rival Great Power"
	)
	assert_eq((courts[FactionCatalog.great_power_ids()[1]] as Dictionary).size(), 1)

func test_a_rival_chart_follows_the_setup_reveals() -> void:
	_setup_visibility()
	var charts: CourtCharts = _charts_for(_visibility_model)
	var rival: int = FactionCatalog.great_power_ids()[1]
	var view: VisibilityModel = charts.model_for(rival, 0)
	assert_eq(
		view.province_visibility(1), VisibilityModel.Level.FULLY_VISIBLE,
		"its own province is fully visible"
	)
	assert_eq(
		view.province_visibility(0), VisibilityModel.Level.FOGGED,
		"a rival coast is fogged, not charted"
	)
	assert_eq(
		view.province_visibility(2), VisibilityModel.Level.FOGGED,
		"another court's land is fogged too"
	)
	assert_true(charts.knows_province(rival, 0, 0))
	assert_true(charts.knows_zone(rival, 0, 0), "its coastal zone is charted")

func test_the_human_grid_is_shared_not_copied() -> void:
	_setup_visibility()
	var human := VisibilityModel.new()
	human.setup(_visibility_model, PLAYER)
	var human_views: Dictionary = {0: human}
	var charts: CourtCharts = _charts_for(_visibility_model, human_views)
	assert_eq(charts.model_for(PLAYER, 0), human, "the session owns the human grid")
	charts.reveal_province(PLAYER, 0, 2)
	assert_eq(
		human.province_visibility(2), VisibilityModel.Level.FULLY_VISIBLE,
		"a human reveal lands on the shared grid"
	)
	assert_eq(charts.regions_of(PLAYER), human_views)

func test_an_uncharted_new_world_is_unknown_to_every_rival() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	var charts: CourtCharts = _charts_for(map)
	var rival: int = FactionCatalog.great_power_ids()[1]
	assert_true(charts.known_zones(rival, 0).is_empty(), "no water is charted")
	assert_false(charts.knows_province(rival, 0, 0))
	assert_true(
		charts.charted_tiles(rival, 0, [Vector2i(1, 3)]).is_empty(),
		"no land is charted"
	)
	charts.reveal_sea_zone(rival, 0, 0)
	assert_true(charts.knows_zone(rival, 0, 0), "the entered zone is charted")
	var zones: Array[int] = [0]
	assert_eq(charts.known_zones(rival, 0), zones)
	var expected: Array[Vector2i] = [Vector2i(1, 3)]
	assert_eq(
		charts.charted_tiles(rival, 0, [Vector2i(1, 3), Vector2i(1, 0)]),
		expected,
		"the coastal ring is charted, the province interior is not"
	)

func test_a_rival_explore_completion_reveals_only_its_own_chart() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	var human := VisibilityModel.new()
	human.setup(map, PLAYER)
	var charts: CourtCharts = _charts_for(map, {0: human})
	var rival: int = FactionCatalog.great_power_ids()[1]
	var beach: Vector2i = map.province_tiles(2)[0]
	charts.reveal_landing(rival, 0, beach)
	var unit: CivilianState = CivilianState.create(1, rival, "explorer", beach)
	unit.start_work("explore", beach, 1)
	var crew: Array[CivilianState] = [unit]
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		map, crew, LandWorks.new(), charts.model_for(rival, 0)
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(
		charts.model_for(rival, 0).province_visibility(2),
		VisibilityModel.Level.FULLY_VISIBLE,
		"the explorer charts the province for its own court"
	)
	assert_eq(
		human.province_visibility(2), VisibilityModel.Level.UNKNOWN,
		"the player's fog is untouched"
	)

func test_rival_fog_decays_at_the_end_of_the_turn() -> void:
	_setup_visibility()
	var world := WorldMap.new()
	world.add_region(_build_region())
	var play := PlaySession.new()
	play.world = world
	play.model = world.region(0)
	play.player_faction = PLAYER
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = play.model
	play.ship_layer.world = world
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = play.model
	MapPlayCourtFog.build(play)
	var rival: int = FactionCatalog.great_power_ids()[1]
	play.court_charts.reveal_sea_zone(rival, 0, 0)
	var view: VisibilityModel = play.court_charts.model_for(rival, 0)
	assert_eq(view.level_at(0, 3), VisibilityModel.Level.FULLY_VISIBLE)
	MapPlayCourtFog.resolve(play)
	assert_eq(
		view.level_at(0, 3), VisibilityModel.Level.FOGGED,
		"a foreign coast fogs once the squadron is gone"
	)
	assert_eq(
		view.province_visibility(1), VisibilityModel.Level.FULLY_VISIBLE,
		"the court's own land never decays"
	)
	play.ship_layer.free()
	play.civilian_layer.free()

func test_no_difficulty_level_widens_a_rival_chart() -> void:
	_setup_visibility()
	var baseline: PackedByteArray = _court_grid(Difficulty.DEFAULT)
	for level: String in Difficulty.IDS:
		assert_eq(_court_grid(level), baseline, "%s charts the same fog" % level)

func _court_grid(difficulty_id: String) -> PackedByteArray:
	var world := WorldMap.new()
	world.add_region(_build_region())
	var play := PlaySession.new()
	play.world = world
	play.model = world.region(0)
	play.player_faction = PLAYER
	play.difficulty = Difficulty.normalize(difficulty_id)
	MapPlayCourtFog.build(play)
	var rival: int = FactionCatalog.great_power_ids()[1]
	return play.court_charts.model_for(rival, 0).levels

func test_a_rival_chart_round_trips_through_the_save() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	var world := WorldMap.new()
	world.add_region(map)
	var charts := CourtCharts.new()
	charts.setup(world, PLAYER, {})
	var rival: int = FactionCatalog.great_power_ids()[1]
	charts.reveal_sea_zone(rival, 0, 0)
	var restored := CourtCharts.new()
	assert_true(restored.apply_dict(world, charts.to_dict()))
	assert_eq(
		restored.model_for(rival, 0).levels, charts.model_for(rival, 0).levels,
		"a load restores the chart the rival earned"
	)
	assert_false(restored.apply_dict(world, 7), "a malformed payload is refused")
	assert_false(restored.apply_dict(world, {}), "a save without charts keeps the grid")
	assert_true(restored.courts.is_empty() == false, "the good grid survives")

## The links are pure map data, so every court charting one region asks for the
## same table: it is built once per grid state and handed out as a copy.
func test_the_coast_table_is_built_once_per_grid() -> void:
	VisibilityModel.clear_cache()
	var grid := _build_region()
	var first := VisibilityModel.new()
	first.setup(grid, PLAYER)
	assert_eq(VisibilityModel._coast_cache.size(), 1, "one table for one grid")
	var second := VisibilityModel.new()
	second.setup(grid, 1)
	assert_eq(VisibilityModel._coast_cache.size(), 1, "a second court reuses it")
	assert_eq(second.province_sea_zones, first.province_sea_zones, "the copy answers alike")
	second.province_sea_zones[99] = [9]
	assert_false(first.province_sea_zones.has(99), "each chart keeps its own table")
	first.province_sea_zones[98] = [8]
	var third := VisibilityModel.new()
	third.setup(grid, 2)
	assert_false(third.province_sea_zones.has(98), "a chart cannot edit the shelf")
	VisibilityModel.clear_cache()


func test_an_edited_grid_builds_its_own_table() -> void:
	VisibilityModel.clear_cache()
	var first := VisibilityModel.new()
	var grid := _build_region()
	first.setup(grid, PLAYER)
	var edited: MapModel = _build_region()
	edited.terrain[edited.index_of(0, 4)] = MapModel.Terrain.PLAINS
	_claim(edited, 4, 0, 2, 4, 4, PLAYER)
	var second := VisibilityModel.new()
	second.setup(edited, PLAYER)
	assert_eq(VisibilityModel._coast_cache.size(), 2, "an edited grid gets its own table")
	assert_ne(second.province_sea_zones, first.province_sea_zones, "and it reads differently")
	VisibilityModel.clear_cache()


func test_the_coast_cache_stays_bounded() -> void:
	VisibilityModel.clear_cache()
	var model: MapModel = _build_region()
	for step in VisibilityModel.CACHE_LIMIT + 2:
		model.terrain[model.index_of(step % 6, 5)] = (
			MapModel.Terrain.HILLS if step % 2 == 0 else MapModel.Terrain.OCEAN
		)
		var view := VisibilityModel.new()
		view.setup(model, PLAYER)
	assert_lte(VisibilityModel._coast_cache.size(), VisibilityModel.CACHE_LIMIT, "bounded")
	VisibilityModel.clear_cache()
	assert_eq(VisibilityModel._coast_cache.size(), 0, "clearing drops every table")


func _build_region() -> MapModel:
	var map := MapModel.new()
	map.setup(12, 6)
	for y in 4:
		for x in 7:
			map.terrain[map.index_of(x, y)] = MapModel.Terrain.PLAINS
	_claim(map, 0, 0, 1, 0, 3, PLAYER)
	_claim(map, 1, 2, 4, 0, 3, 1)
	_claim(map, 2, 5, 6, 0, 1, 2)
	_claim(map, 3, 5, 6, 2, 3, PLAYER)
	_zone(map, 0, 0, 3, 4, 5)
	_zone(map, 1, 4, 6, 4, 5)
	_zone(map, 2, 7, 7, 0, 5)
	_zone(map, 3, 8, 10, 0, 5)
	_zone(map, 4, 11, 11, 0, 5)
	return map

func _claim(
	map: MapModel, id: int, x_min: int, x_max: int, y_min: int, y_max: int, owner: int
) -> void:
	var tiles: Array[Vector2i] = []
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			map.province[map.index_of(x, y)] = id
			tiles.append(Vector2i(x, y))
	map.provinces.append(
		ProvinceState.create(id, "Province %d" % id, tiles, Vector2.ZERO, tiles.size(), owner)
	)

func _zone(
	map: MapModel, id: int, x_min: int, x_max: int, y_min: int, y_max: int
) -> void:
	var tiles: Array[Vector2i] = []
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			map.sea_zone[map.index_of(x, y)] = id
			tiles.append(Vector2i(x, y))
	map.sea_zones.append(
		SeaZoneState.create(id, "Sea %d" % id, tiles, Vector2.ZERO, tiles.size())
	)

# --- test_save_world ---

func test_round_trip_applies_owners_resources_and_array_tiles() -> void:
	var world: WorldMap = _world()
	var captured: Array[Dictionary] = SaveWorld.capture(world)
	var region: Dictionary = captured[0]
	var province: Dictionary = region["provinces"][0]
	province["owner"] = 3
	province["capital"] = true
	province["town_development"] = 2
	province["town_tile"] = [2, 1]
	province["fort_level"] = FortRules.MAX_LEVEL + 4
	province["resource"] = 7
	province["resource_tile"] = [1, 0]
	province["population"] = 42
	province["road_paths"] = [[Vector2i(0, 0), Vector2i(1, 0)]]
	region["provinces"][0] = province
	# JSON-shaped resources arrive as Array; PackedInt32Array is the capture path.
	var resources: Array = []
	for index in world.region(0).resource.size():
		resources.append(9 if index == 0 else -1)
	region["resources"] = resources
	region["tile_deeds"] = {"owners": {0: 3}, "purchased": {0: 3}}
	captured[0] = region

	assert_true(SaveWorld.apply(world, captured), "matching save applies")
	var model: MapModel = world.region(0)
	assert_eq(model.provinces[0].owner, 3)
	assert_true(model.provinces[0].capital)
	assert_eq(model.provinces[0].town_development, 2)
	assert_eq(model.provinces[0].town_tile, Vector2i(2, 1))
	assert_eq(model.provinces[0].fort_level, FortRules.MAX_LEVEL)
	assert_eq(model.provinces[0].resource, 7)
	assert_eq(model.provinces[0].resource_tile, Vector2i(1, 0))
	assert_eq(model.provinces[0].population, 42)
	assert_eq(model.provinces[0].road_paths, [[Vector2i(0, 0), Vector2i(1, 0)]])
	assert_eq(model.resource[0], 9)
	assert_eq(model.owner_at(0, 0), 3)

func test_apply_refuses_shape_mismatches_and_corrupt_entries() -> void:
	var world: WorldMap = _world()
	var good: Array[Dictionary] = SaveWorld.capture(world)

	assert_false(SaveWorld.apply(world, {}), "non-array regions refuse")
	assert_false(SaveWorld.apply(world, []), "wrong region count refuses")
	assert_false(SaveWorld.apply(world, [good[0], "x"]), "non-dict region refuses")

	var wide: Dictionary = good[0].duplicate(true)
	wide["width"] = world.region(0).width + 1
	assert_false(SaveWorld.apply(world, [wide]), "size mismatch refuses")

	var short_provinces: Dictionary = good[0].duplicate(true)
	short_provinces["provinces"] = []
	assert_false(SaveWorld.apply(world, [short_provinces]), "province count refuses")

	var bad_province: Dictionary = good[0].duplicate(true)
	bad_province["provinces"] = ["x"]
	assert_false(SaveWorld.apply(world, [bad_province]), "non-dict province refuses")

	var missing_id: Dictionary = good[0].duplicate(true)
	var row: Dictionary = missing_id["provinces"][0].duplicate(true)
	row["id"] = 99
	missing_id["provinces"][0] = row
	assert_false(SaveWorld.apply(world, [missing_id]), "unknown province refuses")

	var bad_roads: Dictionary = good[0].duplicate(true)
	row = bad_roads["provinces"][0].duplicate(true)
	row["road_paths"] = "not-an-array"
	bad_roads["provinces"][0] = row
	assert_false(SaveWorld.apply(world, [bad_roads]), "bad road_paths refuse")

	var bad_resources: Dictionary = good[0].duplicate(true)
	bad_resources["resources"] = PackedInt32Array([1])
	assert_false(SaveWorld.apply(world, [bad_resources]), "wrong packed size refuses")
	bad_resources["resources"] = [1]
	assert_false(SaveWorld.apply(world, [bad_resources]), "wrong array size refuses")

func test_reusable_requires_matching_region_sizes() -> void:
	var world: WorldMap = _world()
	var regions: Array[Dictionary] = SaveWorld.capture(world)

	assert_null(SaveWorld.reusable(null, regions))
	assert_null(SaveWorld.reusable(WorldMap.new(), regions))
	assert_eq(SaveWorld.reusable(world, regions), world, "matching region sizes reuse")

	var other: WorldMap = WorldMap.new()
	var model: MapModel = MapModel.new()
	model.setup(world.region(0).width + 1, world.region(0).height)
	other.add_region(model)
	assert_null(SaveWorld.reusable(other, regions), "wrong size is not reused")
	assert_null(SaveWorld.reusable(world, {}), "non-array regions refuse")
	assert_null(SaveWorld.reusable(world, []), "wrong region count refuses")

## A world's charts are sized per region (the New World is wider than the Old),
## so the save's own sizes must be the check — one shared width rejected every
## real preset and regenerated the whole world on each load.
func test_reusable_accepts_charts_of_differing_sizes() -> void:
	var world := WorldMap.new()
	var old: MapModel = MapModel.new()
	old.setup(4, 3)
	world.add_region(old)
	var new_world: MapModel = MapModel.new()
	new_world.setup(6, 3)
	world.add_region(new_world)

	var regions: Array = [
		{"width": 4, "height": 3},
		{"width": 6, "height": 3},
	]
	assert_eq(SaveWorld.reusable(world, regions), world, "per-chart sizes reuse")
	regions[1] = {"width": 5, "height": 3}
	assert_null(SaveWorld.reusable(world, regions), "a mismatched chart refuses")
	regions[1] = "x"
	assert_null(SaveWorld.reusable(world, regions), "a non-dict chart refuses")

func test_resource_tile_accepts_vector2i_and_falls_back() -> void:
	var world: WorldMap = _world()
	var captured: Array[Dictionary] = SaveWorld.capture(world)
	var region: Dictionary = captured[0]
	var row: Dictionary = region["provinces"][0].duplicate(true)
	row["resource_tile"] = Vector2i(0, 0)
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(world.region(0).provinces[0].resource_tile, Vector2i(0, 0))

	row = region["provinces"][0].duplicate(true)
	row["resource_tile"] = "junk"
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(world.region(0).provinces[0].resource_tile, Vector2i(-1, -1))

	row = region["provinces"][0].duplicate(true)
	row["resource_tile"] = [1]
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(world.region(0).provinces[0].resource_tile, Vector2i(-1, -1))

func test_visibility_round_trips_and_skips_unknown_regions() -> void:
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = 0
	var visibility := VisibilityModel.new()
	visibility.setup(play.world.region(0), play.player_faction)
	visibility.raise_to(0, VisibilityModel.Level.FULLY_VISIBLE)
	play.visibility_by_region[0] = visibility

	var captured: Dictionary = SaveWorld.capture_visibility(play)
	assert_true(captured["by_region"].has(0), "every charted region is captured")

	var restored := PlaySession.new()
	restored.world = _world()
	restored.player_faction = 0
	SaveWorld.restore_visibility(restored, captured)
	assert_true(restored.visibility_by_region.has(0), "the charted region comes back")
	assert_eq(
		restored.visibility_by_region[0].level_at(0, 0),
		VisibilityModel.Level.FULLY_VISIBLE,
		"seen tiles stay seen"
	)

func test_visibility_restore_tolerates_junk_and_unknown_regions() -> void:
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = 0
	SaveWorld.restore_visibility(play, "not-a-dict")
	assert_true(play.visibility_by_region.is_empty(), "junk clears to no fog model")
	SaveWorld.restore_visibility(play, {"by_region": {7: {"seen": []}, 0: "junk"}})
	assert_true(
		play.visibility_by_region.is_empty(),
		"an unknown region and a malformed entry are both skipped"
	)

## A court seated by hand round-trips its tile and harbour, so a reload keeps
## the seat the player chose instead of the regenerated auto-choice one
## (wiki: capital-choice-phase § Player choice).
func test_a_chosen_seat_round_trips_its_tile_and_ports() -> void:
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	model.provinces[0].capital_tile = Vector2i(1, 0)
	model.provinces[0].ports = {2: Vector2i(1, 0)}
	var captured: Array[Dictionary] = SaveWorld.capture(world)

	model.provinces[0].capital_tile = Vector2i(-1, -1)
	model.provinces[0].ports = {}
	assert_true(SaveWorld.apply(world, captured))
	assert_eq(model.provinces[0].capital_tile, Vector2i(1, 0))
	assert_eq(model.provinces[0].ports, {2: Vector2i(1, 0)})

	# A malformed port entry is dropped; the rest of the harbour still loads.
	var region: Dictionary = captured[0].duplicate(true)
	var row: Dictionary = region["provinces"][0].duplicate(true)
	row["ports"] = {0: "junk", 1: [0, 1]}
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(model.provinces[0].ports, {1: Vector2i(0, 1)})

func _world() -> WorldMap:
	var model := MapModel.new()
	model.setup(2, 1)
	model.terrain[0] = MapModel.Terrain.PLAINS
	model.terrain[1] = MapModel.Terrain.PLAINS
	model.province[0] = 0
	model.province[1] = 0
	model.provinces = [
		ProvinceState.create(0, "A", [Vector2i(0, 0), Vector2i(1, 0)], Vector2(0.5, 0.5), 2, 0, true),
	]
	var world := WorldMap.new()
	world.add_region(model)
	return world

# --- test_save_store ---

func test_slots_report_existing_saves_and_empty_slots() -> void:
	_setup_save_store()
	var rows: Array[Dictionary] = SaveStore.slots(DIR)
	assert_eq(rows.size(), SaveStore.SLOT_COUNT)
	assert_false(bool(rows[0]["exists"]), "fresh slot is empty")

	assert_true(SaveStore.save_slot(3, _data(7), DIR), "slot 3 saves")
	assert_true(SaveStore.has_slot(3, DIR), "slot 3 exists")
	assert_false(SaveStore.has_slot(2, DIR), "slot 2 stays empty")
	rows = SaveStore.slots(DIR)
	assert_true(bool(rows[2]["exists"]), "row reports the save")
	assert_eq(int(rows[2]["turn"]), 7, "row carries the turn")
	assert_eq(String(rows[2]["nation"]), "Spain", "row carries the nation")
	assert_eq(String(rows[2]["region"]), "Old World", "row carries the region")
	assert_eq(int(rows[2]["seed"]), 4242, "row carries the seed")
	assert_false(String(rows[2]["saved_at"]).is_empty(), "row carries a timestamp")
	assert_eq(String(rows[2]["length"]), "Historical", "row names the campaign length")

## The campaign length is a rule a load cannot change, so the row that offers
## the load names it; a save without the key reads Historical, exactly as the
## loaded campaign will (wiki: campaign-persistence § Load and resume).
func test_slot_rows_name_the_campaign_length() -> void:
	_setup_save_store()
	assert_true(SaveStore.save_slot(1, _data(4, true), DIR), "the endless save writes")
	assert_true(SaveStore.save_slot(2, _data(5, false), DIR), "the historical save writes")
	assert_true(SaveStore.save_slot(3, _data(6), DIR), "the legacy save writes")
	var rows: Array[Dictionary] = SaveStore.slots(DIR)
	assert_eq(String(rows[0]["length"]), "Endless", "endless is named")
	assert_eq(String(rows[1]["length"]), "Historical", "historical is named")
	assert_eq(String(rows[2]["length"]), "Historical", "a save without the key is historical")
	assert_eq(SaveCodec.length_label(true), "Endless")
	assert_eq(SaveCodec.length_label(false), "Historical")

## A slot holding a file this build cannot read is not an empty slot: the row
## keeps the file's presence (so the overwrite guard still asks) and says it
## cannot be read, inventing no summary (wiki: campaign-persistence
## § Load and resume — announced, never silent).
func test_an_unreadable_slot_is_reported_not_empty() -> void:
	_setup_save_store()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(SaveStore.path_for(2, DIR), FileAccess.WRITE)
	assert_not_null(file, "the corrupt fixture opens")
	if file == null:
		return
	file.store_string("not a variant")
	file.close()
	# A save written by a newer format is a readable dictionary this build must
	# still refuse (wiki: campaign-persistence § Snapshots — version).
	assert_true(
		SaveStore.write(SaveStore.path_for(3, DIR), {"version": SaveCodec.VERSION + 1}),
		"the newer-format fixture writes"
	)

	var rows: Array[Dictionary] = SaveStore.slots(DIR)
	assert_true(bool(rows[1]["exists"]), "a file is in the slot")
	assert_false(bool(rows[1]["readable"]), "the corrupt file cannot be read")
	assert_false(rows[1].has("turn"), "no summary is invented for it")
	assert_true(bool(rows[2]["exists"]), "the newer-format slot is not empty")
	assert_false(bool(rows[2]["readable"]), "a newer format is refused")

func test_overwrite_replaces_the_slot_and_delete_clears_it() -> void:
	_setup_save_store()
	assert_true(SaveStore.save_slot(1, _data(2), DIR))
	assert_true(SaveStore.save_slot(1, _data(11), DIR), "slot overwrites")
	assert_eq(int(SaveStore.slots(DIR)[0]["turn"]), 11, "newer save wins")
	assert_true(SaveStore.delete_slot(1, DIR), "slot deletes")
	assert_false(SaveStore.has_slot(1, DIR), "deleted slot is gone")
	assert_false(SaveStore.delete_slot(1, DIR), "deleting twice is a no-op")

func test_slot_numbers_are_clamped_and_bad_data_is_refused() -> void:
	_setup_save_store()
	assert_eq(SaveStore.path_for(0, DIR), SaveStore.path_for(1, DIR))
	assert_eq(SaveStore.path_for(99, DIR), SaveStore.path_for(SaveStore.SLOT_COUNT, DIR))
	assert_false(SaveStore.save_slot(1, {}, DIR), "empty data is refused")
	assert_false(SaveStore.save_slot(1, {"version": 999}, DIR), "bad version refused")

## `infinite` is left null for a save written before the key existed.
func _data(turn: int, infinite: Variant = null) -> Dictionary:
	var session: Dictionary = {
		"map_seed": 4242,
		"map_width": 64,
		"map_height": 42,
		"player_faction": 0,
		"region_index": 0,
		"turn": turn,
	}
	if infinite != null:
		session["infinite_mode"] = infinite
	return {
		"version": SaveCodec.VERSION,
		"saved_at": "2026-11-08 12:00:00",
		"session": session,
		"regions": [{}],
	}

func _clean_dir() -> void:
	var path: String = ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)


# --- province graph ----------------------------------------------------------
## Province-graph queries (`ProvinceGraph`) and the Minor share's pocket pass:
## components, connectivity, land hops and ownership tallies over an induced set
## (wiki: game-setup, map-topology). Pure rules, so one row of tiles per case.

## Non-underscore so before_all state is copied onto each test instance.
var province_graph_grid: MapModel = null


func _data_before_all() -> void:
	province_graph_grid = _graph_owners(9, 1, [])


func test_components_split_a_set_into_its_landmasses_largest_first() -> void:
	# Runs 0-1-2 and 6-7-8 are equal-sized and apart.
	assert_eq(
		_graph_components([0, 1, 2, 6, 7, 8]), [[0, 1, 2], [6, 7, 8]]
	)
	# The longer run comes first whatever its ids are.
	assert_eq(
		_graph_components([0, 1, 4, 5, 6, 7]), [[4, 5, 6, 7], [0, 1]]
	)


func test_components_of_an_empty_set_is_no_landmass() -> void:
	assert_eq(_graph_components([]), [])


func test_a_set_is_connected_only_when_nothing_sits_apart() -> void:
	assert_true(
		ProvinceGraph.is_contiguous(province_graph_grid, [4, 5, 6, 7]), "one run"
	)
	assert_true(
		ProvinceGraph.is_contiguous(province_graph_grid, [3]), "one province holds"
	)
	assert_false(
		ProvinceGraph.is_contiguous(province_graph_grid, [0, 1, 8]),
		"an island splits it",
	)
	assert_false(
		ProvinceGraph.is_contiguous(province_graph_grid, []),
		"no land is no holding",
	)


func test_hops_count_land_steps_from_the_source() -> void:
	assert_eq(
		ProvinceGraph.hops(province_graph_grid, [0, 1, 2, 3], 0),
		{0: 0, 1: 1, 2: 2, 3: 3},
	)
	# A source outside the set reaches nothing.
	assert_eq(ProvinceGraph.hops(province_graph_grid, [0, 1], 9), {})


func test_owner_counts_and_unowned_read_one_set() -> void:
	# Tile 0 and 1 belong to court 2, tile 2 to court 3, the rest are open.
	var model: MapModel = _graph_owners(3, 1, [2, 2, 3])
	assert_eq(ProvinceGraph.owner_counts(model, [0, 1, 2]), {2: 2, 3: 1})
	assert_eq(ProvinceGraph.unowned(model, [0, 1, 2]), [])
	model.province_data(1).owner = MapModel.NO_ID
	assert_eq(ProvinceGraph.unowned(model, [0, 1, 2]), [1], "open land, ascending")


## A cove a Minor Nation seals is too small to seat a Great Power, so the
## bordering court takes it and the pool comes back without it
## (wiki: game-setup § Minor Nation assignment).
func test_a_sealed_cove_joins_the_bordering_minor() -> void:
	# 10 owns tile 0, 11 owns tile 1; pocket tiles 2-3 sit on the bottom row
	# beside 10's tile, and no Great Power is left to take them.
	var model: MapModel = _graph_owners(
		2, 2, [10, 11, MapModel.NO_ID, MapModel.NO_ID]
	)
	var pool: Array = MinorShare.absorb_pockets(model, _graph_ids(model), [10, 11], 0)
	assert_eq(model.province_data(2).owner, 10, "the bordering court takes the cove")
	assert_eq(model.province_data(3).owner, 10, "the whole cove follows")
	assert_true(pool.is_empty(), "nothing is left for the Great Powers")
	assert_true(model.province_data(2).population > 0, "a taken pocket is settled")


## A court that cannot take a pocket leaves it open rather than vanish land.
func test_a_pocket_with_no_minor_border_stays_open() -> void:
	var model: MapModel = _graph_owners(
		2, 2, [10, 11, MapModel.NO_ID, MapModel.NO_ID]
	)
	var pool: Array = MinorShare.absorb_pockets(
		model, _graph_ids(model), [] as Array[int], 0
	)
	assert_eq(pool, [2, 3], "no taker, no change")
	assert_eq(model.province_data(2).owner, MapModel.NO_ID, "the cove keeps no owner")


func _graph_components(ids: Array) -> Array:
	return ProvinceGraph.components(province_graph_grid, ids)


## One-tile provinces on a square grid; `owners` is row-major (index -> owner).
func _graph_owners(width: int, height: int, owners: Array) -> MapModel:
	var model: MapModel = MapModel.new()
	model.setup(width, height)
	var provinces: Array[ProvinceState] = []
	for y in height:
		for x in width:
			var index: int = model.index_of(x, y)
			model.terrain[index] = MapModel.Terrain.PLAINS
			model.province[index] = index
			var tiles: Array[Vector2i] = [Vector2i(x, y)]
			var owner: int = (
				int(owners[index]) if index < owners.size() else MapModel.NO_ID
			)
			provinces.append(ProvinceState.create(
				index, "P%d" % index, tiles, Vector2(x + 0.5, y + 0.5), 1, owner
			))
	model.provinces = provinces
	return model


func _graph_ids(model: MapModel) -> Array:
	return range(model.provinces.size())

# ==== merged from test_map_canvas.gd (one coverage boot; docs/testing.md § Speed rules) ====
## Presentation contract for the map artwork: the wash must sit behind the ink,
## the animated layers must exist, the bake must carry a coastline and a beach
## the player can read, and symbols must never bury a province name.

const Fixture = preload("res://tests/map_fixture.gd")
## The shared 48x32 fixture is all pocket provinces (every one under
## `MapCanvasPlan.NAME_ROOM`), so the case that reads both type sizes — full and
## pocket — uses a 72x52 chart instead. It is generated once per worker: under
## coverage a chart costs seconds, and a case that rebuilt it would pay that
## again. Old World only — the placement rules never read a world's sea lanes,
## and one region keeps the retry loop (setup_errors -> a fresh seed) from
## paying for a second chart.
const NAME_CHART: Vector2i = Vector2i(72, 52)

static var _name_chart: MapModel = null

var _canvas: MapCanvas = null


## Mounted lazily: only the cases that read the artwork pay for a canvas, and
## the plan cases below read the chart without one.
func _mounted() -> MapCanvas:
	if not is_instance_valid(_canvas):
		_canvas = MapCanvas.new()
		_canvas.build(Fixture.region())
		add_child(_canvas)
	return _canvas


func _canvas_after_each() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null


## The name-placement chart the two placement cases share, generated once per
## worker.
func _name_chart_model() -> MapModel:
	if _name_chart == null:
		_name_chart = MapGenerator.new().generate_region(
			Fixture.SEED, FactionCatalog.OLD_WORLD, NAME_CHART.x, NAME_CHART.y
		)
	return _name_chart


func test_wash_draws_behind_the_inked_layer() -> void:
	var canvas: MapCanvas = _mounted()
	var wash: Sprite2D = canvas.get_node_or_null("Wash")
	assert_not_null(wash)
	assert_true(wash.show_behind_parent)
	assert_true(wash.material is ShaderMaterial)
	# The paint is baked finer than the tile grid but the sprite still covers
	# exactly one map.
	var relief: MapRelief = canvas.relief
	assert_true(relief.scale > 1, "the wash is baked at sub-tile resolution")
	assert_almost_eq(wash.scale.x * float(relief.scale), MapCanvas.TILE_SIZE, 0.001)
	assert_almost_eq(
		wash.scale.x * float(wash.texture.get_width()), canvas.map_size().x, 0.05
	)


func test_land_shadow_sits_under_the_wash() -> void:
	var canvas: MapCanvas = _mounted()
	var shade: Sprite2D = canvas.get_node_or_null("Shade")
	assert_not_null(shade)
	assert_true(shade.show_behind_parent)
	assert_lt(canvas.get_children().find(shade), canvas.get_children().find(canvas.get_node("Wash")))


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
func test_canvas_owned_land_is_washed_toward_its_crown() -> void:
	_mounted()
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
	var model: MapModel = _mounted().model
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


## The shore is one published reading: the bake paints from `MapCoastField`, so
## a later reader of the coastline cannot end up with a second answer, and the
## basin reach the shoal veil follows is the deepest sounding within its reach.
func test_the_bake_paints_from_the_published_coast_field() -> void:
	var model: MapModel = _mounted().model
	var relief: MapRelief = _canvas.relief
	var field: MapCoastField = relief.coast
	assert_not_null(field, "the bake keeps the field it read")
	assert_false(field.sd.is_empty(), "the field carries a distance per tile")
	assert_eq(field.width, model.width)
	assert_eq(field.height, model.height)
	var shallow: int = 0
	var drift: int = 0
	for y in model.height:
		for x in model.width:
			var i: int = y * model.width + x
			if field.reach[i] < maxf(-field.sd[i], 0.0):
				shallow += 1
			var centre := Vector2(float(x) + 0.5, float(y) + 0.5)
			if absf(relief.coast_at(centre) - field.coast_at(centre)) > 0.00001:
				drift += 1
	assert_eq(shallow, 0, "the reach holds the deepest sounding of every basin")
	assert_eq(drift, 0, "the bake reads the field's shore, never its own copy")


## A beach inside the shore and a pale shoal outside it: that band is what makes
## a coastline read as drawn water rather than a soft smear.
func test_wash_paints_a_beach_and_a_shallow_band() -> void:
	var model: MapModel = _mounted().model
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


## A narrow gulf must read as water, not as a land-coloured wash. The shoal veil
## follows the basin instead of a fixed width, so open water shows down the
## middle and only a thin shelf clings to the shore (issue #456). The minimap
## colours these tiles from terrain, so agreeing with it means the basin stays
## water the model already called sea, with solid ground on its walls.
func test_a_narrow_gulf_keeps_open_water_down_its_middle() -> void:
	var model := _narrow_gulf()
	var relief := MapRelief.new()
	relief.build(model, MapWash.OWNER_TINT)
	var centre: float = _painted_alpha(relief, Vector2i(11, 12))
	assert_lt(centre, 0.02, "the gulf's middle is left to the sea backdrop")
	# The shelf survives, just thin: it hugs the shore inside the gulf.
	var shelf: float = _widest_alpha(relief, 12, 11, 12)
	assert_gt(shelf, 0.10, "a thin shoal shelf still clings to the gulf's shore")
	assert_lt(shelf, 0.45, "the shelf is a band, never a fill")
	assert_true(model.is_sea(11, 12) and model.is_sea(12, 12))
	assert_gt(_painted_alpha(relief, Vector2i(10, 12)), 0.9, "the walls stay solid land")


## Open water keeps the chart's full shoal band: the veil narrows only where the
## basin itself is narrow, so a coast does not lose its drawn shallows (#456).
func test_open_water_keeps_the_full_shoal_band() -> void:
	var relief := MapRelief.new()
	relief.build(_open_coast(), MapWash.OWNER_TINT)
	assert_gt(_painted_alpha(relief, Vector2i(12, 2)), 0.04, "the shelf is still drawn")
	assert_lt(_painted_alpha(relief, Vector2i(12, 6)), 0.02, "deep water stays open")


## The ink under a shore must not fill a basin either: the pale rim, the wet-sand
## band and the damp edge each spill most of a tile into the sea, so a creek two
## tiles across printed solid from bank to bank and read as barren ground while
## the model — and the minimap — called it sea (#456).
func test_a_narrow_gulf_takes_the_line_alone() -> void:
	var model := _narrow_gulf()
	var canvas := _chart_of(model)
	var marked: int = 0
	for path_index in canvas._coast.size():
		var path: PackedVector2Array = canvas._coast[path_index]
		for i in path.size():
			if not _on_the_creek(path[i]):
				continue
			marked += 1
			assert_eq(canvas._coast_open[path_index][i], 0, "the creek keeps only its line")
	assert_gt(marked, 0, "the creek's walls were measured")
	canvas.queue_free()


## The same paints that would flood a creek are what draw a coast's beach and
## surf rim, so open water keeps them (#456).
func test_open_water_keeps_the_shores_full_paint() -> void:
	var model := _open_coast()
	var canvas := _chart_of(model)
	var marked: int = 0
	for path_index in canvas._coast.size():
		var path: PackedVector2Array = canvas._coast[path_index]
		for i in path.size():
			var tile: Vector2i = MapGeo.tile_at_world(path[i], MapCanvas.TILE_SIZE)
			if tile.y < 2 or tile.y > 6:
				continue
			marked += 1
			assert_eq(canvas._coast_open[path_index][i], 1, "open water keeps its paints")
	assert_gt(marked, 0, "the open coast was measured")
	canvas.queue_free()


## Two banks of breakers meeting in a creek would print it as foam-grey ground,
## so the surf stays off water the shore cannot fit its paints in (#456).
func test_a_narrow_gulf_carries_no_breaking_surf() -> void:
	var canvas := _chart_of(_narrow_gulf())
	var surf: MapSurf = canvas.get_node("Surf")
	assert_gt(surf.dash_count(), 0, "the chart still breaks surf somewhere")
	for dash: Dictionary in surf._dashes:
		var probe: Vector2 = (
			(dash["position"] as Vector2)
			+ (dash["normal"] as Vector2) * MapCanvas.TILE_SIZE * 0.7
		)
		var tile: Vector2i = MapGeo.tile_at_world(probe, MapCanvas.TILE_SIZE)
		assert_false(
			tile.x >= 11 and tile.x <= 12 and tile.y >= 6, "no breakers inside the creek"
		)
	canvas.queue_free()


## A gulf must read as water by its tone, not only by its thin veil. Water is
## cool and land is warm, and no sea or shelf tone may sit within a confounding
## distance of any land tone — the chart's pale bands were exactly land-coloured
## and made a basin look like barren ground (issue #456).
func test_sea_tones_never_read_as_land() -> void:
	var land_tones: Array[Color] = []
	for terrain in Palette.TERRAIN_COLORS.size():
		if terrain == MapModel.Terrain.OCEAN or terrain == MapModel.Terrain.SHALLOW:
			continue
		land_tones.append(Palette.TERRAIN_COLORS[terrain])
	for sea: Color in [Palette.SEA_DEEP, Palette.SEA_MID, Palette.SEA_PALE]:
		assert_gt(sea.b, sea.r + 0.12, "a sea tone stays cool; land is warm")
		for land: Color in land_tones:
			assert_gt(_tone_distance(sea, land), 0.30, "sea and land keep their distance")
	for shelf: Color in [MapRelief.SHOAL, MapRelief.SHOAL_DEEP, MapRelief.SHOAL_RING]:
		assert_gt(shelf.b, shelf.r + 0.12, "the coastal shelf is painted as water too")


## The chart's water comes from the palette table the minimap paints, so the two
## views can never disagree about which side of the coast is sea (issue #456).
func test_chart_water_is_the_minimap_water() -> void:
	# Shader defaults are not readable until set; pin them in the source so a
	# backdrop that has not been fitted yet still paints the same water.
	var src := FileAccess.get_file_as_string("res://ui/shaders/sea.gdshader")
	for tone: Color in [Palette.SEA_DEEP, Palette.SEA_MID, Palette.SEA_PALE, Palette.SEA_CREST]:
		var lit := "%.3f, %.3f, %.3f" % [tone.r, tone.g, tone.b]
		assert_true(src.contains(lit), "sea shader default matches palette %s" % lit)
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/shaders/sea.gdshader")
	var backdrop := ColorRect.new()
	backdrop.material = material
	SeaBackdrop.fit(backdrop, Vector2(1000.0, 700.0))
	assert_eq(material.get_shader_parameter("deep_color"), Palette.SEA_DEEP)
	assert_eq(material.get_shader_parameter("mid_color"), Palette.SEA_MID)
	assert_eq(material.get_shader_parameter("pale_color"), Palette.SEA_PALE)
	assert_eq(material.get_shader_parameter("crest_color"), Palette.SEA_CREST)
	backdrop.free()


func test_animated_layers_exist() -> void:
	var canvas: MapCanvas = _mounted()
	var surf: MapSurf = canvas.get_node_or_null("Surf")
	assert_not_null(surf)
	assert_gt(surf.dash_count(), 0)
	var cloud: ColorRect = canvas.get_node_or_null("CloudShade")
	assert_not_null(cloud)
	assert_true(cloud.material is ShaderMaterial)
	assert_gt(cloud.size.x, canvas.map_size().x)


func test_surf_points_always_face_open_water() -> void:
	var canvas: MapCanvas = _mounted()
	var surf: MapSurf = canvas.get_node("Surf")
	for dash: Dictionary in surf._dashes:
		var origin: Vector2 = dash["position"]
		var normal: Vector2 = dash["normal"]
		var probe: Vector2 = origin + normal * MapCanvas.TILE_SIZE * 0.7
		var tile: Vector2i = MapGeo.tile_at_world(probe, MapCanvas.TILE_SIZE)
		assert_true(canvas.model.is_sea(tile.x, tile.y))


## Scenery never sits in a province name's clearing. Places do carry the same
## exemption the capital star and the port anchor always had: a town mark stands
## on its tile whether or not a neighbouring province's name runs across it.
func test_terrain_symbols_never_cover_province_labels() -> void:
	var plan: MapCanvasPlan = _mounted().plan
	var marks: int = 0
	for glyph: Dictionary in plan.glyphs:
		var kind: String = String(glyph["kind"])
		if kind == "port" or kind == "capital" or kind == "town":
			continue
		marks += 1
		assert_false(plan.under_label(glyph["position"]))
	assert_gt(marks, 0)


## Every non-capital province town is drawn on the chart, so a crown can see
## where its estates anchor (wiki: capital-and-connectivity § Town per province).
## The mark never steps aside for the province name: the name steps aside for it.
func test_every_non_capital_town_is_marked() -> void:
	var model: MapModel = _mounted().model
	var marks: Dictionary = {}
	for glyph: Dictionary in _canvas.plan.glyphs:
		if String(glyph["kind"]) == "town":
			marks[glyph["position"]] = true
	var expected: int = 0
	for province: ProvinceState in model.provinces:
		if province.capital or province.town_tile.x < 0:
			continue
		if not model.is_land(province.town_tile.x, province.town_tile.y):
			continue
		expected += 1
		var at: Vector2 = MapGeo.tile_center(
			province.town_tile.x, province.town_tile.y, MapCanvas.TILE_SIZE
		)
		assert_true(marks.has(at), "%s has no town mark" % province.name)
	assert_gt(expected, 0)
	assert_eq(marks.size(), expected)


## The case that bit: a named inland province picks the tile nearest its centroid
## as its town, which is where the name is drawn. The mark has to stand on that
## tile and the name has to clear it.
func test_a_province_name_clears_its_town_mark() -> void:
	var region: MapModel = _name_chart_model()
	var plan := MapCanvasPlan.new()
	plan.build(region, null, MapCanvas.TILE_SIZE)
	var marks: Dictionary = {}
	for glyph: Dictionary in plan.glyphs:
		if String(glyph["kind"]) == "town":
			marks[glyph["position"]] = true
	var named: Dictionary = {}
	for label: Dictionary in plan.labels:
		if String(label["kind"]) == "province":
			named[String(label["text"])] = label["position"]
	var moved: int = 0
	var marked: int = 0
	for province: ProvinceState in region.provinces:
		if province.capital or province.town_tile.x < 0:
			continue
		if not region.is_land(province.town_tile.x, province.town_tile.y):
			continue
		marked += 1
		var at: Vector2 = MapGeo.tile_center(
			province.town_tile.x, province.town_tile.y, MapCanvas.TILE_SIZE
		)
		assert_true(marks.has(at), "%s has no town mark" % province.name)
		if not named.has(province.name):
			continue
		var anchor: Vector2 = named[province.name]
		var clear: bool = (
			absf(at.x - anchor.x) >= MapCanvasPlan.LABEL_HALF_WIDTH
			or at.y <= anchor.y - MapCanvasPlan.LABEL_CLEAR_ABOVE
			or at.y >= anchor.y + MapCanvasPlan.LABEL_CLEAR_BELOW
		)
		assert_true(clear, "%s hides its town under its own name" % province.name)
		if anchor != Vector2(province.center) * MapCanvas.TILE_SIZE:
			moved += 1
	assert_gt(marked, 20, "the chart carries a town per province")
	assert_gt(moved, 0, "a name made room for its town mark")


## A province is painted, not speckled once: the scatter lays a second, smaller
## stamp on top of the first so a forest or an upland reads as a cluster.
func test_terrain_is_dense_with_two_stamp_kinds_per_tile() -> void:
	var canvas: MapCanvas = _mounted()
	var kinds: Dictionary = {}
	var per_tile: Dictionary = {}
	for glyph: Dictionary in canvas.plan.glyphs:
		var kind: String = String(glyph["kind"])
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if kind == "port" or kind == "capital":
			continue
		var at: Vector2 = glyph["position"]
		var tile: Vector2i = MapGeo.tile_at_world(at, MapCanvas.TILE_SIZE)
		per_tile[tile] = int(per_tile.get(tile, 0)) + 1
	var land: int = 0
	for y in canvas.model.height:
		for x in canvas.model.width:
			if canvas.model.is_land(x, y):
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
## carries its name at the province centre — a pocket province one step smaller
## rather than nameless (issue #665). The name chart carries both sizes.
func test_plan_places_names_without_a_node() -> void:
	var region: MapModel = _name_chart_model()
	var plan := MapCanvasPlan.new()
	plan.build(region, null, MapCanvas.TILE_SIZE)
	var named: Dictionary = {}
	for label: Dictionary in plan.labels:
		if String(label["kind"]) == "province":
			named[String(label["text"])] = label
	var full: int = 0
	var pockets: int = 0
	for province: ProvinceState in region.provinces:
		assert_true(named.has(province.name), "%s has no chart name" % province.name)
		var size: int = int(named[province.name]["size"])
		if province.area < MapCanvasPlan.NAME_ROOM:
			pockets += 1
			assert_eq(size, MapCanvasPlan.POCKET_NAME_SIZE, "%s is a pocket" % province.name)
		else:
			full += 1
			assert_eq(size, MapCanvasPlan.NAME_SIZE, "%s has room" % province.name)
	assert_gt(full, 0, "the chart carries a province with room for full type")
	assert_gt(pockets, 0, "the chart carries a pocket province")
	assert_false(plan.passages.size() > 0, "no world means no sea-lane marks")


## Every warp zone on both regions is marked: a centre, a wash over its water,
## an inked edge and a Passage label. The wash covers exactly the zone's water,
## so ordinary sea is never painted as a crossing (REQ-P1-07).
func test_plan_marks_every_warp_zone_on_both_regions() -> void:
	var world: WorldMap = Fixture.world()
	for region in world.region_count():
		var model: MapModel = world.region(region)
		var plan := MapCanvasPlan.new()
		plan.build(model, world, MapCanvas.TILE_SIZE)
		var zones: Array[int] = world.warp_zones(region)
		assert_gt(zones.size(), 0, "the fixture world has crossings")
		assert_eq(plan.passages.size(), zones.size(), "one mark per warp zone")
		assert_gt(plan.passage_water.size(), 0, "the zone water is washed")
		assert_gt(plan.passage_edges.size(), 0, "the wash has a drawn edge")
		var labelled: int = 0
		for label: Dictionary in plan.labels:
			if String(label["kind"]) == "passage":
				labelled += 1
		assert_eq(labelled, zones.size(), "every crossing is named")
		var covered: int = 0
		for run: Rect2 in plan.passage_water:
			var tile: Vector2i = MapGeo.tile_at_world(
				run.position + Vector2(1, 1), MapCanvas.TILE_SIZE
			)
			assert_true(model.is_sea(tile.x, tile.y), "the wash sits on water")
			assert_true(
				zones.has(model.sea_zone_at(tile.x, tile.y)), "only warp water is washed"
			)
			covered += int(run.size.x / MapCanvas.TILE_SIZE) * int(run.size.y / MapCanvas.TILE_SIZE)
		var expected: int = 0
		for zone_id: int in zones:
			for tile: Vector2i in model.get_sea_zone(zone_id).tiles:
				if model.sea_zone_at(tile.x, tile.y) == zone_id:
					expected += 1
		assert_eq(covered, expected, "the whole zone is washed, no more")


## The zone's own name steps above the crossing mark, so the emblem and the
## Passage slip do not overprint the type.
func test_passage_mark_keeps_the_sea_name_clear() -> void:
	var plan := MapCanvasPlan.new()
	plan.labels.append({
		"text": "Mar", "position": Vector2(100, 100), "size": 13, "kind": "sea"
	})
	plan._lift_sea_name(Vector2(100, 100))
	var at: Vector2 = plan.labels[0]["position"]
	assert_lt(at.y, 100.0, "the sea name sits above the mark")
	assert_almost_eq(at.x, 100.0, 0.001, "the name keeps its column")
	var world: WorldMap = Fixture.world()
	var model: MapModel = world.region(FactionCatalog.OLD_WORLD)
	var chart := MapCanvasPlan.new()
	chart.build(model, world, MapCanvas.TILE_SIZE)
	for centre: Vector2 in chart.passages:
		for label: Dictionary in chart.labels:
			if String(label["kind"]) != "sea":
				continue
			assert_gt(
				(label["position"] as Vector2).distance_to(centre), 1.0,
				"no sea name sits on a crossing mark"
			)


## The Passage artwork is drawn, not only planned: mounting a canvas on the
## shared world inks the wash boundary and survives a repaint.
func test_passage_artwork_draws_on_the_shared_world() -> void:
	var world: WorldMap = Fixture.world()
	var canvas := MapCanvas.new()
	add_child(canvas)
	canvas.build(world.region(FactionCatalog.OLD_WORLD), world)
	assert_gt(canvas.plan.passages.size(), 0)
	assert_gt(canvas._passage_ink.size(), 0, "the wash edge is inked")
	canvas.queue_redraw()
	await get_tree().process_frame
	canvas.queue_free()


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


## A full cache drops the state the run stopped asking for, not the whole
## shelf: a suite that keeps mounting the shared chart between one-off states
## finds its bake still there.
func test_a_full_cache_keeps_the_chart_in_use() -> void:
	MapWash.clear_cache()
	var kept := _small_chart()
	var kept_province: ProvinceState = kept.provinces[0]
	var kept_owner: int = kept_province.owner
	var kept_bake: MapRelief = MapWash.baked(kept)
	var first_one_off: MapRelief = null
	# Each case visits the shared chart, then a state it never returns to.
	for step in MapWash.CACHE_LIMIT + 2:
		MapWash.baked(kept)
		var other := _small_chart()
		var province: ProvinceState = other.provinces[0]
		province.owner = kept_owner + step + 1
		var one_off: MapRelief = MapWash.baked(other)
		if first_one_off == null:
			first_one_off = one_off
	assert_eq(
		MapWash.baked(kept), kept_bake, "the chart in use survives a full cache"
	)
	assert_false(
		MapWash._baked.values().has(first_one_off), "a state the run left behind is gone"
	)
	assert_lte(MapWash._baked.size(), MapWash.CACHE_LIMIT, "still bounded")
	MapWash.clear_cache()


## A canvas mounted on one fixture model, so a case can read the shoreline flags
## the paints are drawn from.
func _chart_of(model: MapModel) -> MapCanvas:
	var canvas := MapCanvas.new()
	add_child(canvas)
	canvas.build(model)
	return canvas


## Whether a coast point stands on the walls of the fixture's creek, the two
## water columns of `_narrow_gulf`.
static func _on_the_creek(point: Vector2) -> bool:
	var tile: Vector2i = MapGeo.tile_at_world(point, MapCanvas.TILE_SIZE)
	if tile.y < 5:
		return false
	return tile.x >= 10 and tile.x <= 13


## A narrow gulf cut into a solid landmass: two tiles wide and open to the sea
## at the bottom, the basin the shoal veil used to flood from shore to shore.
func _narrow_gulf() -> MapModel:
	var model := MapModel.new()
	model.setup(24, 20)
	for y in model.height:
		for x in model.width:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	for y in range(6, model.height):
		for x in range(11, 13):
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.SHALLOW
	return model


## A straight coast with the whole sea below it, so a veil can be read at its
## designed width away from any basin wall.
func _open_coast() -> MapModel:
	var model := MapModel.new()
	model.setup(24, 20)
	for y in model.height:
		for x in model.width:
			model.terrain[model.index_of(x, y)] = (
				MapModel.Terrain.PLAINS if y < 2 else MapModel.Terrain.OCEAN
			)
	return model


## Straight RGB distance between two tones: how far apart they read.
func _tone_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Mean paint alpha around a tile centre: the shoal veil's strength there.
func _painted_alpha(relief: MapRelief, tile: Vector2i) -> float:
	var image: Image = relief.color
	var scale: int = relief.scale
	var cx: int = tile.x * scale + scale / 2
	var cy: int = tile.y * scale + scale / 2
	var total: float = 0.0
	var count: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = clampi(cx + dx, 0, image.get_width() - 1)
			var y: int = clampi(cy + dy, 0, image.get_height() - 1)
			total += image.get_pixel(x, y).a
			count += 1
	return total / float(count)


## Widest paint alpha over one bake row inside a tile span: a narrow basin's
## shelf is only a texel or two wide, so a tile mean would read as open water.
func _widest_alpha(relief: MapRelief, tile_y: int, x0: int, x1: int) -> float:
	var image: Image = relief.color
	var scale: int = relief.scale
	var best: float = 0.0
	for sy in scale:
		var y: int = clampi(tile_y * scale + sy, 0, image.get_height() - 1)
		for x in range(x0 * scale, (x1 + 1) * scale):
			best = maxf(best, image.get_pixel(clampi(x, 0, image.get_width() - 1), y).a)
	return best


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
