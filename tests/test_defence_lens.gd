# gdlint: disable=max-public-methods
extends GdToolsTest
## Integration: the defence lens on the live map — toggle, key, mutual exclusion
## Also includes defence survey (one Godot boot).
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
	# The key still lands on the bar's one seal, which raises its reading.
	var event := InputEventAction.new()
	event.action = InputActions.DEFENCE_LENS
	event.pressed = true
	screen.hud.lens_seal._shortcut_input(event)
	assert_true(screen.play.defence_lens.active, "K names the defence reading")
	MapPlayInput.set_defence_lens(screen.play, false)


func test_toggle_key_exclusivity_and_draw() -> void:
	var lens: DefenceLens = screen.play.defence_lens
	assert_not_null(lens)
	assert_false(lens.active)

	MapPlayInput.set_defence_lens(screen.play, true)
	assert_true(lens.active)
	assert_true(screen.hud.lens_legend.visible)
	assert_eq(screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)
	assert_true(screen.hud.lens_seal.button_pressed)
	assert_eq(screen.hud.lens_seal.active_kind, LensLegend.KIND_DEFENCE)
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
	assert_eq(screen.hud.lens_seal.active_kind, LensLegend.KIND_DEFENCE)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_defence_lens(screen.play, false)
	assert_false(lens.active)
	assert_false(screen.hud.lens_legend.visible)
	assert_false(screen.hud.lens_seal.button_pressed)
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

# --- defence_survey ---
## Defence projection for the military lens: a province is banded by its wall
## first and its garrison second, the garrison is the published order of battle
## (FPN + FPM, no medals and no wounds) of the province's owner, and ground the
## crown has not charted never reaches the reading.

const WIDTH: int = 12
const HEIGHT: int = 4
const PLAYER: int = FactionCatalog.PLAYER_FACTION
const RIVAL: int = 3

var _model: MapModel = null
var _armies: Array[ArmyState] = []


func _setup_defence_survey() -> void:
	_model = _build()
	_armies = []


## Four provinces, three columns each: the crown's open ground, a garrisoned
## province in the open, a rival's stone wall and the crown's modern citadel.
func _build() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	var groups: Dictionary = {0: [], 1: [], 2: [], 3: []}
	for y in HEIGHT:
		for x in WIDTH:
			var sea: bool = y == HEIGHT - 1
			model.terrain[model.index_of(x, y)] = (
				MapModel.Terrain.OCEAN if sea else MapModel.Terrain.PLAINS
			)
			if sea:
				model.sea_zone[model.index_of(x, y)] = 0
				continue
			var province_id: int = mini(x / 3, 3)
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	var names: Array[String] = ["Sevilla", "Córdoba", "Évora", "Lisboa"]
	var owners: Array[int] = [PLAYER, PLAYER, RIVAL, PLAYER]
	var forts: Array[int] = [0, 0, 2, 3]
	var provinces: Array[ProvinceState] = []
	for province_id in 4:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		var province := ProvinceState.create(
			province_id, names[province_id], tiles, Vector2(tiles[0]),
			tiles.size(), owners[province_id], province_id == 0
		)
		province.fort_level = forts[province_id]
		provinces.append(province)
	provinces[1].hospital_level = 1
	model.provinces = provinces
	return model


func _army(owner: int, province: int, types: Array[String]) -> ArmyState:
	var army: ArmyState = ArmyState.muster(
		_armies.size() + 1, owner, province, false, types, 1
	)
	_armies.append(army)
	return army


func _snapshot(visibility: VisibilityModel = null) -> Dictionary:
	return DefenceSurvey.snapshot(_model, _armies, visibility, PLAYER)


func defence_survey_entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func test_the_wall_outranks_the_garrison() -> void:
	_setup_defence_survey()
	assert_eq(DefenceSurvey.band_for(0, 0), DefenceSurvey.BAND_OPEN)
	assert_eq(DefenceSurvey.band_for(0, 3), DefenceSurvey.BAND_HELD)
	assert_eq(DefenceSurvey.band_for(1, 0), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(2, 4), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(3, 0), DefenceSurvey.BAND_CITADEL)


func test_a_garrison_is_read_on_the_published_order_of_battle() -> void:
	_setup_defence_survey()
	var army: ArmyState = _army(PLAYER, 1, ["musketeers", "pikemen"])
	# Chevrons and wounds are the crown's own reading, not the published one.
	army.regiment_medals["unit_1"] = 4
	army.regiment_health["unit_1"] = 10
	var survey: Dictionary = _snapshot()
	var held: Dictionary = defence_survey_entry(survey, 1)
	assert_eq(int(held["strength"]), 14, "9 + 5, with no medal multiplier")
	assert_eq(int(held["regiments"]), 2)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_HELD)
	assert_eq(int(held["hospital"]), 1)


func test_an_empty_province_reads_open_and_a_wall_reads_walled() -> void:
	_setup_defence_survey()
	_army(PLAYER, 3, ["guards"])
	var survey: Dictionary = _snapshot()
	assert_eq(String(defence_survey_entry(survey, 0)["band"]), DefenceSurvey.BAND_OPEN)
	assert_eq(int(defence_survey_entry(survey, 0)["strength"]), 0)
	var citadel: Dictionary = defence_survey_entry(survey, 3)
	assert_eq(String(citadel["band"]), DefenceSurvey.BAND_CITADEL)
	assert_eq(int(citadel["fort"]), 3)
	assert_eq(int(citadel["guns"]), 3)
	var rival: Dictionary = defence_survey_entry(survey, 2)
	assert_eq(String(rival["band"]), DefenceSurvey.BAND_WALLED)
	assert_eq(int(rival["guns"]), 2)


## The garrison is the owner's: a foreign host ashore is a contested ground,
## never part of the province's defence.
func test_a_foreign_host_is_flagged_and_never_counted_as_the_garrison() -> void:
	_setup_defence_survey()
	_army(PLAYER, 2, ["musketeers"])
	var rival: Dictionary = defence_survey_entry(_snapshot(), 2)
	assert_true(bool(rival["foreign"]))
	assert_eq(int(rival["strength"]), 0)
	assert_eq(int(rival["regiments"]), 0)


func test_counts_and_the_crown_totals() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers"])
	_army(PLAYER, 3, ["pikemen"])
	var survey: Dictionary = _snapshot()
	var counts: Dictionary = survey["counts"]
	assert_eq(int(counts[DefenceSurvey.BAND_OPEN]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_HELD]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_WALLED]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_CITADEL]), 1)
	var totals: Dictionary = survey["totals"]
	assert_eq(int(totals["provinces"]), 4)
	assert_eq(int(totals["undefended"]), 1, "Sevilla is the crown's only open province")
	assert_eq(int(totals["strength"]), 14, "9 + 5 over the crown's own garrisons")


func test_uncharted_ground_never_reaches_the_reading() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers"])
	var visibility := VisibilityModel.new()
	visibility.setup(_model, PLAYER)
	for tile: Vector2i in _model.provinces[0].tiles:
		visibility.lower_to(
			_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var survey: Dictionary = _snapshot(visibility)
	assert_true(defence_survey_entry(survey, 0).is_empty())
	assert_false(defence_survey_entry(survey, 1).is_empty())
	assert_eq(int(survey["totals"]["provinces"]), 3)


func test_the_hover_line_names_the_strength_the_wall_and_the_hospital() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers", "pikemen"])
	var held: Dictionary = defence_survey_entry(_snapshot(), 1)
	var text: String = DefenceSurvey.summary_text(held)
	assert_true(text.contains("14 strength"), text)
	assert_true(text.contains("2 regiments"), text)
	assert_true(text.contains("No wall"), text)
	assert_true(text.contains(HospitalRules.level_name(1)), text)
	var open_line: String = DefenceSurvey.summary_text(defence_survey_entry(_snapshot(), 0))
	assert_true(open_line.contains("No garrison"), open_line)
	assert_true(open_line.contains("No wall"), open_line)


func test_one_regiment_and_one_gun_read_in_the_singular() -> void:
	_setup_defence_survey()
	_army(PLAYER, 3, ["guards"])
	var text: String = DefenceSurvey.summary_text(defence_survey_entry(_snapshot(), 3))
	assert_true(text.contains("22 strength · 1 regiment"), text)
	assert_true(text.contains("Fort 3 (3 guns)"), text)


func test_an_embarked_army_defends_nothing() -> void:
	_setup_defence_survey()
	var army: ArmyState = _army(PLAYER, 1, ["musketeers"])
	army.embarked_fleet = 7
	var held: Dictionary = defence_survey_entry(_snapshot(), 1)
	assert_eq(int(held["strength"]), 0)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_OPEN)
