extends GdToolsTest
## Integration: the defence lens on the live map — toggle, key, mutual exclusion
## with the other three readings, a march repainting the reading, the slip tap
## and the hover line. Drawing is exercised by a rendered frame.

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
	if screen.play.defence_lens != null and screen.play.defence_lens.active:
		MapPlayInput.set_defence_lens(screen.play, false)
	if screen.region_index != 0:
		screen.load_region(0)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.free()
	screen = null


func test_the_key_action_binds_the_k_key() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.DEFENCE_LENS))
	assert_ne(InputActions.DEFENCE_LENS, InputActions.LENS)
	assert_ne(InputActions.DEFENCE_LENS, InputActions.DIPLOMACY_LENS)
	assert_ne(InputActions.DEFENCE_LENS, InputActions.CROWN_LENS)
	assert_not_null(screen.hud._defence_lens_button.shortcut)


func test_toggle_key_exclusivity_and_draw() -> void:
	var lens: DefenceLens = screen.play.defence_lens
	assert_not_null(lens)
	assert_false(lens.active)

	MapPlayInput.toggle_defence_lens(screen.play)
	assert_true(lens.active)
	assert_true(screen.hud.lens_legend.visible)
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)
	assert_true(screen.hud._defence_lens_button.button_pressed)
	assert_gt((lens.survey["provinces"] as Array).size(), 0)
	assert_almost_eq(screen.civilian_layer.modulate.a, 0.22, 0.001)

	# Every other reading lowers when this one is raised, and vice versa.
	MapPlayInput.set_lens(screen.play, true)
	assert_true(screen.play.lens.active)
	assert_false(lens.active)
	MapPlayInput.set_crown_lens(screen.play, true)
	assert_true(screen.play.crown_lens.active)
	assert_false(screen.play.lens.active)
	MapPlayInput.set_defence_lens(screen.play, true)
	assert_true(lens.active)
	assert_false(screen.play.crown_lens.active)
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)
	assert_false(screen.hud._crown_lens_button.button_pressed)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.toggle_defence_lens(screen.play)
	assert_false(lens.active)
	assert_false(screen.hud.lens_legend.visible)
	assert_false(screen.hud._defence_lens_button.button_pressed)
	assert_almost_eq(screen.civilian_layer.modulate.a, 1.0, 0.001)


func test_the_reading_names_the_crown_garrison_and_its_wall() -> void:
	MapPlayInput.set_defence_lens(screen.play, true)
	var lens: DefenceLens = screen.play.defence_lens
	var province: ProvinceState = _crown_garrisoned()
	assert_true(province != null, "the crown keeps a garrison on the fixture map")
	var entry: Dictionary = _entry(lens.survey, province.id)
	assert_gt(int(entry["strength"]), 0)
	assert_gt(int(entry["regiments"]), 0)
	var summary: String = lens.summary_for(province.id)
	assert_true(summary.contains("strength"), summary)


## A march moves a garrison: the lens reads the roster again on the signal, not
## on a frame poll.
func test_a_roster_change_repaints_the_reading() -> void:
	MapPlayInput.set_defence_lens(screen.play, true)
	var lens: DefenceLens = screen.play.defence_lens
	var army: ArmyState = _first_army_with_regiments()
	assert_true(army != null)
	var before: int = int(_entry(lens.survey, army.province)["regiments"])
	army.remove_regiment(army.regiments[0])
	screen.army_layer.army_moved.emit(army, {})
	var after: int = int(_entry(lens.survey, army.province)["regiments"])
	assert_eq(after, before - 1)


## A tap on a slip selects the province it belongs to, even when the slip was
## packed away from the province centre.
func test_a_tap_on_a_slip_selects_its_province() -> void:
	MapPlayInput.set_defence_lens(screen.play, true)
	var lens: DefenceLens = screen.play.defence_lens
	var province: ProvinceState = _unowned_slip()
	assert_true(province != null, "the fixture map offers a foreign slip")
	var rect: Rect2 = lens._rects[province.id]
	MapPlayInput.on_tapped(screen.play, rect.get_center())
	assert_eq(screen.play.selected_province, province.id)


func test_the_legend_carries_every_band() -> void:
	assert_eq(LensLegend.DEFENCE_ROWS.size(), DefenceSurvey.BANDS.size())
	screen.hud.lens_legend.set_kind(LensLegend.KIND_DEFENCE)
	screen.hud.lens_legend.queue_redraw()
	await get_tree().process_frame
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)


## The hover line carries the reading, and only while the lens is up.
func test_hover_reports_the_defence_while_the_lens_is_on() -> void:
	var province: ProvinceState = _crown_garrisoned()
	assert_true(province != null)
	var world: Vector2 = province.center * MapScreen.TILE_SIZE
	var point: Vector2 = CameraMath.world_to_screen(
		screen.camera.position, screen.camera.zoom.x, world,
		screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(screen.play, point)
	assert_false(screen.hud._tooltip_label.text.contains("Defence:"))
	MapPlayInput.set_defence_lens(screen.play, true)
	MapPlayInput.update_hover(screen.play, point)
	assert_true(screen.hud._tooltip_label.text.contains("Defence: "))


# --- fixture helpers ---------------------------------------------------------


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func _crown_garrisoned() -> ProvinceState:
	for province: ProvinceState in screen.model.provinces:
		if province.owner != screen.player_faction:
			continue
		if not screen.army_layer.armies_in(province.id, screen.player_faction).is_empty():
			return province
	return null


func _first_army_with_regiments() -> ArmyState:
	for raw: Variant in screen.army_layer.regions.value(screen.model.region_id, []):
		var army: ArmyState = raw
		if army.owner == screen.player_faction and not army.regiments.is_empty():
			return army
	return null


## A charted province the crown does not own and keeps no unit in, so the tap
## can only resolve through the slip.
func _unowned_slip() -> ProvinceState:
	var lens: DefenceLens = screen.play.defence_lens
	for province: ProvinceState in screen.model.provinces:
		if province.owner == screen.player_faction or not lens._rects.has(province.id):
			continue
		if screen.army_layer.army_at(lens._rects[province.id].get_center()) != null:
			continue
		if screen.civilian_layer.unit_at(lens._rects[province.id].get_center()) != null:
			continue
		return province
	return null
