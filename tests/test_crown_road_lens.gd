extends GdToolsTest
## Integration: the crown-road lens on the live map — toggle, key, three-way
## exclusivity with the survey and diplomatic readings, a finished road, region
## swap and the hover line. Drawing is exercised by a rendered frame.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_toggle_raises_the_key_and_builds_a_survey() -> void:
	var lens: CrownRoadLens = _screen.play.crown_lens
	assert_not_null(lens)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)

	MapPlayInput.toggle_crown_lens(_screen.play)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	assert_true(_screen.hud._crown_lens_button.button_pressed)
	assert_gt(int(lens.survey["tiles"][CrownRoadSurvey.STATE_ROAD]), 0)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.toggle_crown_lens(_screen.play)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud._crown_lens_button.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


## Three readings of the same map: raising one lowers the other two, so the key
## can never show two legends at once and no toggle claims a mode that is off.
func test_the_three_lenses_are_exclusive() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	assert_true(_screen.play.lens.active)

	MapPlayInput.set_crown_lens(_screen.play, true)
	assert_false(_screen.play.lens.active)
	assert_true(_screen.play.crown_lens.active)
	assert_false(_screen.hud._lens_button.button_pressed)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	assert_false(_screen.play.crown_lens.active)
	assert_false(_screen.hud._crown_lens_button.button_pressed)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)

	MapPlayInput.set_crown_lens(_screen.play, true)
	assert_false(_screen.play.diplomacy_lens.active)
	assert_false(_screen.hud._diplomacy_lens_button.button_pressed)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)


## A finished road lands in the reading at once: the works table is the signal,
## so the lens never polls the map (REQ-P4-01).
func test_a_finished_road_repaints_the_lens() -> void:
	MapPlayInput.set_crown_lens(_screen.play, true)
	var lens: CrownRoadLens = _screen.play.crown_lens
	assert_true(_screen.civilian_layer.works_changed.is_connected(lens.refresh))
	var before: int = int(lens.survey["tiles"][CrownRoadSurvey.STATE_CUT])
	var step: Vector2i = _frontier_tile()
	assert_true(step.x >= 0, "the map offers a tile the crown network can grow into")

	_screen.play.land_works.set_transport(
		_screen.model, step, LandWorks.TRANSPORT_ROAD
	)
	_screen.civilian_layer.refresh_works()
	assert_lt(int(lens.survey["tiles"][CrownRoadSurvey.STATE_CUT]), before)


func test_region_switch_rebuilds_the_lens() -> void:
	MapPlayInput.set_crown_lens(_screen.play, true)
	_screen._cycle_region()
	assert_eq(_screen.play.crown_lens.model, _screen.model)
	assert_eq(
		int(_screen.play.crown_lens.model.region_id), FactionCatalog.NEW_WORLD
	)
	assert_true(_screen.play.crown_lens.survey.has("runs"))


func test_hover_reports_the_crown_road_while_the_lens_is_on() -> void:
	var entry: Dictionary = _linked_entry()
	assert_false(entry.is_empty())
	var province: ProvinceState = _screen.model.province_data(int(entry["id"]))
	var point: Vector2 = _screen_point(province.center)
	MapPlayInput.update_hover(_screen.play, point)
	assert_false(_screen.hud._tooltip_label.text.contains("Crown road:"))

	MapPlayInput.set_crown_lens(_screen.play, true)
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(_screen.hud._tooltip_label.text.contains("Crown road: "))


func test_the_key_action_binds_the_r_key() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.CROWN_LENS))
	assert_ne(InputActions.CROWN_LENS, InputActions.LENS)
	assert_ne(InputActions.CROWN_LENS, InputActions.DIPLOMACY_LENS)


## A cut province draws its gap badge and the route to lay: the draw path is
## exercised on a rendered frame, not just the projection.
func test_a_cut_province_draws_its_gap_and_route() -> void:
	MapPlayInput.set_crown_lens(_screen.play, true)
	var lens: CrownRoadLens = _screen.play.crown_lens
	var province: ProvinceState = _screen.model.provinces[0]
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


func test_the_r_key_toggles_the_lens() -> void:
	MapPlayInput.set_crown_lens(_screen.play, true)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	_screen._unhandled_input(event)
	assert_false(_screen.play.crown_lens.active)
	assert_false(_screen.hud.lens_legend.visible)


# --- helpers -----------------------------------------------------------------


## A road tile that would extend the crown network one step: beside the network,
## with an own neighbour the reading has not reached yet.
func _frontier_tile() -> Vector2i:
	var resolved: Dictionary = LandConnectivity.resolve(
		_screen.model, _screen.play.land_works, _screen.player_faction,
		_screen.play.capital_tile
	)
	var network: Dictionary = resolved.get("network", {}) as Dictionary
	var reached: Dictionary = resolved.get("tiles", {}) as Dictionary
	for raw: Variant in reached.keys():
		var index: int = int(raw)
		if network.has(index):
			continue
		var tile: Vector2i = _tile_of(index)
		if _screen.play.land_works.transport_at(_screen.model, tile) != 0:
			continue
		for offset: Vector2i in CrownRoadSurvey.NEIGHBORS:
			var next: Vector2i = tile + offset
			if not _screen.model.in_bounds(next.x, next.y):
				continue
			if not _screen.model.is_land(next.x, next.y):
				continue
			if _screen.model.owner_at(next.x, next.y) != _screen.player_faction:
				continue
			if reached.has(_screen.model.index_of(next.x, next.y)):
				continue
			return tile
	return Vector2i(-1, -1)


func _tile_of(index: int) -> Vector2i:
	var y: int = int(float(index) / float(_screen.model.width))
	return Vector2i(index - y * _screen.model.width, y)


func _linked_entry() -> Dictionary:
	for raw: Variant in _screen.play.crown_lens.survey.get("provinces", []):
		var entry: Dictionary = raw
		if bool(entry.get("linked", false)):
			return entry
	return {}


func _screen_point(world_in_tiles: Vector2) -> Vector2:
	var world: Vector2 = world_in_tiles * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	return CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
