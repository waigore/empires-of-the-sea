extends GdToolsTest
## Tile model queries used by both the generator and the renderer.
## Consolidated rulebook: test_map_region_table, test_warp_travel,
## test_map_camera (one Godot boot per domain).


const Fixture = preload("res://tests/map_fixture.gd")

const MAP := Vector2(2816.0, 1848.0)

var world_map: WorldMap = null
var _model: MapModel = null
var _camera: MapCamera = null


func before_all() -> void:
	world_map = Fixture.world()


func before_each() -> void:
	_model = MapModel.new()
	_model.setup(4, 3)
	for x in 4:
		_model.terrain[_model.index_of(x, 0)] = MapModel.Terrain.PLAINS
	_model.terrain[_model.index_of(1, 1)] = MapModel.Terrain.HARDWOOD_FOREST
	_model.terrain[_model.index_of(2, 1)] = MapModel.Terrain.SHALLOW
	_model.province[_model.index_of(0, 0)] = 0
	_model.province[_model.index_of(1, 0)] = 0
	_model.province[_model.index_of(1, 1)] = 1
	_model.sea_zone[_model.index_of(2, 1)] = 0
	_model.sea_zone[_model.index_of(3, 1)] = 0
	var cadiz_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var coro_tiles: Array[Vector2i] = [Vector2i(1, 1)]
	var sea_tiles: Array[Vector2i] = [Vector2i(2, 1), Vector2i(3, 1)]
	_model.provinces = [
		ProvinceState.create(0, "Cádiz", cadiz_tiles, Vector2(1.0, 0.5), 2, 0, true),
		ProvinceState.create(1, "Coro", coro_tiles, Vector2(1.5, 1.5), 1, 1, false),
	]
	_model.sea_zones = [
		SeaZoneState.create(0, "Mar Caribe", sea_tiles, Vector2(3.0, 1.5), 2),
	]
	InputActions.ensure_actions()
	_camera = MapCamera.new()
	_camera.map_size = MAP
	_camera.position = MAP * 0.5
	_camera.zoom = Vector2.ONE * 1.2
	_camera.target_zoom = 1.2
	add_child(_camera)


func after_each() -> void:
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null


func test_setup_sizes_and_clears_arrays() -> void:
	var fresh := MapModel.new()
	fresh.setup(7, 5)
	assert_eq(fresh.terrain.size(), 35)
	assert_eq(fresh.province.size(), 35)
	assert_eq(fresh.province[0], MapModel.NO_ID)
	assert_eq(fresh.province_count(), 0)


func test_capital_tile_follows_the_province_record() -> void:
	_model.provinces[0].capital_tile = Vector2i(0, 0)
	assert_eq(_model.capital_tile_of(0), Vector2i(0, 0))
	assert_eq(_model.capital_tile_of(1), CapitalChoice.NO_TILE)
	assert_eq(_model.capital_tile_of(-1), CapitalChoice.NO_TILE)


func test_land_and_sea_classification() -> void:
	assert_true(_model.is_land(0, 0))
	assert_false(_model.is_land(2, 1))
	assert_true(_model.is_sea(2, 1))
	assert_false(_model.is_land(-1, 0))
	assert_false(_model.is_land(0, 99))


func test_out_of_bounds_reads_as_ocean_and_no_id() -> void:
	assert_eq(_model.terrain_at(50, 50), MapModel.Terrain.OCEAN)
	assert_eq(_model.province_at(50, 50), MapModel.NO_ID)
	assert_eq(_model.sea_zone_at(-3, 0), MapModel.NO_ID)


func test_province_lookup_helpers() -> void:
	assert_eq(_model.province_at(1, 0), 0)
	assert_eq(_model.province_name(1), "Coro")
	assert_eq(_model.province_owner(1), 1)
	assert_eq(_model.province_owner(99), MapModel.NO_ID)
	assert_eq(_model.province_center(0), Vector2(1.0, 0.5))
	assert_eq(_model.province_tiles(99), [])


func test_coastal_tiles_touch_sea() -> void:
	assert_true(MapGeo.is_coastal_tile(_model, 1, 1))
	assert_false(MapGeo.is_coastal_tile(_model, 1, 0))
	assert_false(MapGeo.is_coastal_tile(_model, 2, 1))
	assert_eq(MapGeo.coastal_tiles(_model, 1), [Vector2i(1, 1)])


func test_map_border_is_not_a_coast() -> void:
	var border := MapModel.new()
	border.setup(3, 3)
	for index in border.terrain.size():
		border.terrain[index] = MapModel.Terrain.PLAINS
	assert_false(MapGeo.is_coastal_tile(border, 0, 0))
	assert_false(MapGeo.is_coastal_tile(border, 2, 2))


func test_tile_deeds_override_the_province_owner() -> void:
	var tile := Vector2i(1, 1)
	assert_eq(_model.owner_at(tile.x, tile.y), 1)
	assert_true(_model.purchase_tile(tile, 6))
	assert_eq(_model.owner_at(tile.x, tile.y), 6)
	assert_eq(_model.province_owner(1), 1, "the province itself does not change hands")
	assert_true(_model.is_purchased_tile(tile))
	assert_false(_model.purchase_tile(tile, 7), "one deed per tile")


func test_owned_tiles_follow_deeds_in_both_directions() -> void:
	var deed := Vector2i(1, 1)
	assert_true(_model.purchase_tile(deed, 6))
	var ownership: TileOwnership = _model.ownership
	assert_true(ownership.owned_tiles(_model, 6).has(deed), "buyer holds the enclave")
	assert_false(ownership.owned_tiles(_model, 1).has(deed), "seller no longer holds it")
	assert_true(
		ownership.owned_tiles(_model, 0).has(Vector2i(0, 0)),
		"ordinary province tiles remain"
	)


func test_tile_deeds_round_trip_through_plain_data() -> void:
	assert_true(_model.purchase_tile(Vector2i(1, 1), 6))
	var restored := TileOwnership.new()
	restored.apply_dict(_model.ownership.to_dict())
	assert_true(restored.is_purchased(_model.index_of(1, 1)))
	assert_eq(restored.owner_of(_model.index_of(1, 1), -1), 6)


func test_province_neighbors_are_cached_and_sorted() -> void:
	assert_eq(MapGeo.province_neighbors(_model, 0), [1])
	assert_true(_model.provinces[0].neighbors_cached)
	assert_eq(MapGeo.province_neighbors(_model, 99), [])


func test_sea_zone_neighbors() -> void:
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
	assert_eq(MapGeo.world_size(_model, 10.0), Vector2(40.0, 30.0))
	assert_eq(MapGeo.tile_center(0, 0, 10.0), Vector2(5.0, 5.0))
	assert_eq(MapGeo.tile_at_world(Vector2(15.0, 25.0), 10.0), Vector2i(1, 2))


func test_land_tile_count() -> void:
	assert_eq(MapGeo.land_tile_count(_model), 5)


func test_terrain_labels_cover_every_type() -> void:
	for terrain in MapModel.Terrain.values():
		assert_true(MapModel.TERRAIN_LABELS.has(terrain))


func test_palette_covers_every_terrain() -> void:
	for terrain in MapModel.Terrain.values():
		assert_true(terrain < Palette.TERRAIN_COLORS.size())
	assert_eq(Palette.faction_color(-1), Palette.INK_LINE)
	assert_eq(Palette.faction_color(99), Palette.INK_LINE)
	assert_eq(Palette.terrain_color(99), Color(0.5, 0.5, 0.5))


# --- merged from tests/test_map_region_table.gd ---


## Region tables: one table row per map region, plus the encode/decode walk the
## save codec uses instead of layer privates (REQ-P3-02 narrow APIs).
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


# --- merged from tests/test_warp_travel.gd ---


## Warp-zone crossings between the Old and New World (wiki: map-topology).
func test_a_warp_zone_links_to_one_zone_on_the_other_map() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(1, 0, zone)

	var check: Dictionary = WarpTravel.can_cross(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_true(bool(check["ok"]))
	assert_eq(int(check["to_region"]), FactionCatalog.NEW_WORLD)
	assert_eq(
		int(check["to_zone"]),
		int(world_map.warp_partner(FactionCatalog.OLD_WORLD, zone)["to_zone"])
	)
	assert_true(world_map.is_warp_zone(int(check["to_region"]), int(check["to_zone"])))


func test_crossing_moves_the_fleet_into_the_paired_zone() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(2, 0, zone, ["ship_2"], {"ship_2": "sloop"})

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["from_zone"]), zone)
	assert_eq(int(result["from_region"]), FactionCatalog.OLD_WORLD)
	assert_eq(int(result["to_region"]), FactionCatalog.NEW_WORLD)
	assert_eq(fleet.sea_zone, int(result["to_zone"]))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved)
	# Hulls cross intact, instance ids and types unchanged.
	assert_eq(fleet.ship_count(), 1)
	assert_eq(fleet.type_of("ship_2"), "sloop")


func test_a_crossing_can_be_made_back_the_other_way() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(3, 0, zone)
	var there: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)
	assert_true(bool(there["ok"]))
	fleet.moved = false

	var back: Dictionary = WarpTravel.apply_crossing(
		world_map, int(there["to_region"]), fleet
	)

	assert_true(bool(back["ok"]))
	assert_eq(int(back["to_region"]), FactionCatalog.OLD_WORLD)
	assert_true(world_map.is_warp_zone(FactionCatalog.OLD_WORLD, fleet.sea_zone))


## A crossing is the squadron's sail, so the station and the landing site are
## given up; province ids are region-local, so a marker carried across would
## name an unrelated coast on the other map (wiki: ships-and-naval § Missions
## and Movement — a mission persists until the squadron sails; § Naval transport
## — the beachhead marker is lost if the squadron sails).
func test_a_crossing_gives_up_the_station_and_the_landing_site() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var blockading := FleetState.at_sea(7, 0, zone)
	blockading.mission = FleetState.Mission.BLOCKADE
	blockading.blockade_province = 4
	blockading.beachhead_province = 4
	blockading.beachhead_turn = 3
	var landing := FleetState.at_sea(8, 0, zone)
	landing.mission = FleetState.Mission.BEACHHEAD
	landing.beachhead_province = 5
	landing.beachhead_turn = 3

	assert_true(bool(WarpTravel.apply_crossing(world_map, FactionCatalog.OLD_WORLD, blockading)["ok"]))
	assert_true(bool(WarpTravel.apply_crossing(world_map, FactionCatalog.OLD_WORLD, landing)["ok"]))

	assert_eq(blockading.mission, FleetState.Mission.NONE)
	assert_eq(blockading.blockade_province, MapModel.NO_ID, "the blockade coast does not cross")
	assert_false(blockading.has_beachhead(), "the landing site does not cross")
	assert_eq(blockading.beachhead_turn, -1)
	assert_eq(landing.mission, FleetState.Mission.NONE, "the beachhead mission is given up")
	assert_false(landing.has_beachhead())


func test_a_moved_fleet_cannot_cross() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(4, 0, zone)
	fleet.moved = true

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("already moved"))
	assert_eq(fleet.sea_zone, zone)


func test_a_fleet_in_port_cannot_cross() -> void:
	var province: int = int(world_map.region(FactionCatalog.OLD_WORLD).provinces[0].id)
	var fleet := FleetState.in_port(5, 0, province)

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("at sea"))
	assert_eq(fleet.location, FleetState.Location.IN_PORT)


func test_open_water_has_no_passage() -> void:
	var model: MapModel = world_map.region(FactionCatalog.OLD_WORLD)
	var zone: int = -1
	for data: SeaZoneState in model.sea_zones:
		if not world_map.is_warp_zone(FactionCatalog.OLD_WORLD, int(data.id)):
			zone = int(data.id)
			break
	assert_gt(zone, -1, "the Old World has ordinary water")
	var fleet := FleetState.at_sea(6, 0, zone)

	var check: Dictionary = WarpTravel.can_cross(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("passage"))
	assert_false(fleet.moved)


# --- merged from tests/test_map_camera.gd ---


## Camera input: every way the player pans and zooms (REQ-P1-05, REQ-P4-02).
func test_wheel_zooms_in_and_out() -> void:
	var before: float = _camera.target_zoom
	_camera._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(300, 200)))
	assert_gt(_camera.target_zoom, before)
	var zoomed: float = _camera.target_zoom
	_camera._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(300, 200)))
	assert_lt(_camera.target_zoom, zoomed)


func test_zoom_keeps_the_cursor_anchored() -> void:
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
	var event := InputEventMagnifyGesture.new()
	event.factor = 1.3
	event.position = Vector2(640, 640)
	var before: float = _camera.target_zoom
	_camera._unhandled_input(event)
	assert_gt(_camera.target_zoom, before)


func test_pan_gesture_moves_the_camera() -> void:
	var event := InputEventPanGesture.new()
	event.delta = Vector2(40, 0)
	event.position = Vector2(640, 640)
	var before: Vector2 = _camera.position
	_camera._unhandled_input(event)
	assert_lt(_camera.position.x, before.x)


func test_drag_marks_dragging_and_tracks_distance() -> void:
	_camera._unhandled_input(_button(true, Vector2(400, 400)))
	assert_true(_camera.is_dragging())
	_camera._unhandled_input(_motion(Vector2(30, 0)))
	assert_gt(_camera.drag_distance(), 0.0)
	_camera._unhandled_input(_button(false, Vector2(430, 400)))
	assert_false(_camera.is_dragging())


func test_click_emits_tapped_with_world_position() -> void:
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
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	_camera._unhandled_input(_motion(Vector2(80, 0)))
	_camera._unhandled_input(_button(false, Vector2(780, 500)))
	assert_eq(captured.size(), 0)


func test_drag_keeps_inertia_after_release() -> void:
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	for _step in 4:
		_camera._unhandled_input(_motion(Vector2(40, 0)))
	var released_at: Vector2 = _camera.position
	_camera._unhandled_input(_button(false, Vector2(860, 500)))
	_camera._process(0.1)
	assert_ne(_camera.position, released_at)


func test_touch_tap_emits_tapped() -> void:
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_touch(0, true, Vector2(500, 500)))
	_camera._unhandled_input(_touch(0, false, Vector2(502, 501)))
	assert_eq(captured.size(), 1)


func test_two_finger_pinch_zooms() -> void:
	_camera._unhandled_input(_touch(0, true, Vector2(400, 400)))
	_camera._unhandled_input(_touch(1, true, Vector2(500, 400)))
	var before: float = _camera.target_zoom
	_camera._unhandled_input(_screen_drag(1, Vector2(120, 0), Vector2(620, 400)))
	assert_gt(_camera.target_zoom, before)


func test_single_finger_drag_pans() -> void:
	var before: Vector2 = _camera.position
	_camera._unhandled_input(_touch(0, true, Vector2(400, 400)))
	_camera._unhandled_input(_screen_drag(0, Vector2(-60, -30), Vector2(340, 370)))
	assert_ne(_camera.position, before)


func test_keyboard_pan_moves_the_camera() -> void:
	var before: Vector2 = _camera.position
	Input.action_press(InputActions.PAN_RIGHT)
	_camera._process(0.2)
	Input.action_release(InputActions.PAN_RIGHT)
	assert_gt(_camera.position.x, before.x)


func test_focus_on_settles_at_a_clamped_target() -> void:
	_camera.focus_on(Vector2(2600, 1700), 0.9)
	for _step in 30:
		_camera._process(0.2)
	var expected: Vector2 = CameraMath.clamp_center(
		Vector2(2600, 1700), _camera.zoom.x, _camera.viewport_size(), MAP
	)
	assert_lt(_camera.position.distance_to(expected), 2.0)
	assert_almost_eq(_camera.zoom.x, 0.9, 0.001)


func test_zoom_buttons_step_and_clamp() -> void:
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
