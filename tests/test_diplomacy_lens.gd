extends GdToolsTest
## Integration: the diplomatic lens on the live map — toggle, key, mutual
## exclusion with the survey lens, war repaints, region swap and hover line.
## Drawing is exercised by a rendered frame.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_toggle_raises_the_key_and_builds_a_survey() -> void:
	var lens: DiplomacyLens = _screen.play.diplomacy_lens
	assert_not_null(lens)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DIPLOMACY)
	assert_gt(int(lens.survey["tiles"]["self"]), 0)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_diplomacy_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud.lens_seal.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


## The two lenses are readings of the same map: raising one lowers the other,
## so the key can never show two legends at once.
func test_the_two_lenses_are_exclusive() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	assert_true(_screen.play.lens.active)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SURVEY)

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	assert_false(_screen.play.lens.active)
	assert_true(_screen.play.diplomacy_lens.active)
	assert_true(_screen.hud.lens_seal.button_pressed, "the one seal stays raised")
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DIPLOMACY)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	MapPlayInput.set_lens(_screen.play, true)
	assert_false(_screen.play.diplomacy_lens.active)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_SURVEY)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SURVEY)


func test_a_declaration_of_war_repaints_the_wash() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var owner: int = _foreign_owner()
	assert_true(owner >= 0)
	var relation: DiplomacyRelation = _screen.play.diplomacy.ensure_relation(
		_screen.player_faction, owner, _screen.play.turn
	)
	relation.set_score(50.0)
	MapPlaySetup.build_diplomacy_lens(_screen.play)
	assert_eq(
		DiplomacySurvey.band_for(
			_screen.play.diplomacy, _screen.player_faction, owner
		),
		DiplomacySurvey.BAND_NEUTRAL
	)

	relation.at_war = true
	relation.normalize()
	MapPlaySetup.build_diplomacy_lens(_screen.play)
	var entry: Dictionary = _entry(_screen.play.diplomacy_lens.survey, _province_of(owner))
	assert_eq(String(entry["band"]), DiplomacySurvey.BAND_WAR)
	assert_gt(int(_screen.play.diplomacy_lens.survey["tiles"]["war"]), 0)


func test_region_switch_rebuilds_the_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	_screen._cycle_region()
	assert_eq(_screen.play.diplomacy_lens.model, _screen.model)
	assert_eq(int(_screen.play.diplomacy_lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(_screen.play.diplomacy_lens.survey.has("runs"))
	# The New World starts unknown, so the wash paints nothing yet.
	assert_eq(int(_screen.play.diplomacy_lens.survey["counts"]["neutral"]), 0)

	# Charting one province makes it readable as neutral (no court yet).
	var province: ProvinceState = _screen.model.provinces[0]
	_screen.visibility.reveal_province(province.id)
	MapPlaySetup.build_diplomacy_lens(_screen.play)
	assert_false(
		_entry(_screen.play.diplomacy_lens.survey, province.id).is_empty()
	)


func test_hover_reports_the_standing_while_the_lens_is_on() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var entry: Dictionary = _visible_entry(_screen.play.diplomacy_lens.survey)
	assert_false(entry.is_empty())
	var province: ProvinceState = _screen.model.province_data(int(entry["id"]))
	var world: Vector2 = province.center * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	var screen_point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, screen_point)
	assert_true(_screen.hud._tooltip_label.text.contains("Standing: "))
	assert_true(_screen.hud._tooltip_label.text.contains(String(entry["standing"])))


## Raising the lens must refresh a tooltip that is already open: a stationary
## cursor is the common case, and the pre-lens line has no standing.
func test_the_hover_line_appears_when_the_lens_is_raised() -> void:
	var entry: Dictionary = _visible_entry(
		DiplomacySurvey.snapshot(
			_screen.model, _screen.play.diplomacy, _screen.player_faction,
			_screen.visibility
		)
	)
	assert_false(entry.is_empty())
	var province: ProvinceState = _screen.model.province_data(int(entry["id"]))
	var point: Vector2 = _screen_point(province.center)
	MapPlayInput.update_hover(_screen.play, point)
	assert_false(_screen.hud._tooltip_label.text.contains("Standing:"))

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(_screen.hud._tooltip_label.text.contains("Standing: "))


func test_the_key_action_binds_the_p_and_l_keys() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.DIPLOMACY_LENS))
	assert_true(InputMap.has_action(InputActions.LENS))
	assert_ne(InputActions.DIPLOMACY_LENS, InputActions.LENS)


## P toggles the political wash from the keyboard, like L does the survey.
func test_the_p_key_toggles_the_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_P
	event.pressed = true
	_screen._unhandled_input(event)
	assert_false(_screen.play.diplomacy_lens.active)
	assert_false(_screen.hud.lens_legend.visible)


## A political map refresh (Join Empire) rebuilds the wash with the new owners.
func test_a_political_refresh_rebuilds_the_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var before: int = int(_screen.play.diplomacy_lens.survey["tiles"]["self"])
	assert_gt(before, 0)
	_screen.refresh_political_map()
	assert_eq(_screen.play.diplomacy_lens.model, _screen.model)
	assert_eq(int(_screen.play.diplomacy_lens.survey["tiles"]["self"]), before)


# --- helpers -----------------------------------------------------------------


func _foreign_owner() -> int:
	for province: ProvinceState in _screen.model.provinces:
		if (
			province.owner != _screen.player_faction
			and province.owner != MapModel.NO_ID
		):
			return province.owner
	return MapModel.NO_ID


func _province_of(owner: int) -> int:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner == owner:
			return province.id
	return -1


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func _visible_entry(survey: Dictionary) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["charted"]) != VisibilityModel.Level.UNKNOWN:
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
