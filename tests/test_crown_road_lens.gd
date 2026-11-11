extends GdToolsTest
## Integration: the crown-road lens on the live map. One MapScreen for the whole
## suite — remounting under coverage blows the tier-1 budget (docs/testing.md).

const Fixture = preload("res://tests/map_fixture.gd")

var screen: MapScreen = null
var saved: Array = []


func before_all() -> void:
	saved = Fixture.snapshot(Fixture.world())
	screen = Fixture.attach_screen(self)


func before_each() -> void:
	Fixture.restore(Fixture.world(), saved)
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	if screen.play.lens != null and screen.play.lens.active:
		MapPlayInput.set_lens(screen.play, false)
	if screen.play.diplomacy_lens != null and screen.play.diplomacy_lens.active:
		MapPlayInput.set_diplomacy_lens(screen.play, false)
	if screen.play.crown_lens != null and screen.play.crown_lens.active:
		MapPlayInput.set_crown_lens(screen.play, false)
	if screen.region_index != 0:
		screen.load_region(0)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.free()
	screen = null


func test_the_key_action_binds_the_r_key() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.CROWN_LENS))
	assert_ne(InputActions.CROWN_LENS, InputActions.LENS)
	assert_ne(InputActions.CROWN_LENS, InputActions.DIPLOMACY_LENS)
	assert_not_null(screen.hud._crown_lens_button.shortcut)


func test_toggle_key_exclusivity_road_and_draw() -> void:
	var lens: CrownRoadLens = screen.play.crown_lens
	assert_not_null(lens)
	assert_false(lens.active)

	MapPlayInput.toggle_crown_lens(screen.play)
	assert_true(lens.active)
	assert_true(screen.hud.lens_legend.visible)
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	assert_true(screen.hud._crown_lens_button.button_pressed)
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

	# Seal shortcut drops the lens (same path as pressing R).
	screen.hud._crown_lens_button.set_pressed(false)
	screen.hud._crown_lens_button.toggled.emit(false)
	assert_false(lens.active)
	assert_false(screen.hud.lens_legend.visible)


func test_region_switch_and_rail_budget() -> void:
	MapPlayInput.set_crown_lens(screen.play, true)
	screen._cycle_region()
	assert_eq(screen.play.crown_lens.model, screen.model)
	assert_eq(int(screen.play.crown_lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(screen.play.crown_lens.survey.has("runs"))
	screen.load_region(0)

	# Three seals share the left rail: crown sits past diplomacy, inside LEFT_RAIL.
	var hud: GameHud = screen.hud
	var crown: Rect2 = hud._crown_lens_button.get_global_rect()
	var diplo: Rect2 = hud._diplomacy_lens_button.get_global_rect()
	assert_gt(crown.position.x, diplo.end.x, "the three lens seals never overlap")
	assert_lt(crown.end.x, HudLayout.LEFT_RAIL + 1.0, "crown seal stays inside LEFT_RAIL")
	MapPlayInput.set_crown_lens(screen.play, true)
	assert_eq(hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	assert_true(hud.lens_legend.visible)


# --- helpers -----------------------------------------------------------------


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
