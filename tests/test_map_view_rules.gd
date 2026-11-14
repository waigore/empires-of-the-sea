extends GdToolsTest
## One boot for the chart's view: the camera, the fog layer, the minimap, the
## resource survey and the crown road lens.

## Merged from test_map_camera, test_fog_layer, test_minimap, test_resource_survey,
## test_crown_road_lens.
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
	_hook_crown_road_lens_before_all()

func after_all() -> void:
	_hook_crown_road_lens_after_all()

func after_each() -> void:
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
	assert_eq(int(row["output"]), 1)
	assert_eq(int(entry["counts"]["worked"]), 1)
	assert_eq(int(entry["counts"]["developed"]), 1)
	assert_eq(int(entry["counts"]["linked"]), 1)
	assert_gt(int(entry["counts"]["producing"]), 0)
	assert_false((entry["output"] as Dictionary).is_empty())
	assert_true(String(entry["summary"]).contains("linked to the crown"))

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

	# The reading rides the cartouche now: the rail below is back to two seals.
	var hud: GameHud = screen.hud
	var seal: Rect2 = hud.lens_seal.get_global_rect()
	var bar: Rect2 = hud.top_bar.get_global_rect()
	assert_gt(seal.size.x, 0.0, "the lens seal is on the bar")
	assert_true(seal.position.y >= bar.position.y and seal.end.y <= bar.end.y + 0.5, "seal inside the bar")
	assert_lt(HudLayout.LEFT_RAIL, 260.0, "the rail covers only ESTATES and the Gazette")
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
		for offset: Vector2i in CrownRoadSurvey.NEIGHBORS:
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
