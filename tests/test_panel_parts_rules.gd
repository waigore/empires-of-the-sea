extends GdToolsTest
## One boot for the side panels: research, province and diplomacy.

## Merged from test_research_panel, test_province_panel, test_diplomacy_panel.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const Fixture = preload("res://tests/civilian_fixture.gd")

const LINKED_TILE: Vector2i = Vector2i(1, 0)
const VACANT_TILE: Vector2i = Vector2i(0, 1)
const OFF_ROAD_TILE: Vector2i = Vector2i(1, 1)

var _panel: ResearchPanel = null
var _state: ResearchState = null
var _model: MapModel = null
var _works: LandWorks = null
var _units: Array[CivilianState] = []
var _province_panel_panel: ProvincePanel = null
var state: DiplomacyState
var panel: DiplomacyPanel

var _suite_setup: String = ""

func after_each() -> void:
	match _suite_setup:
		"research_panel":
			_teardown_research_panel()
		"province_panel":
			_teardown_province_panel()
		"diplomacy_panel":
			_teardown_diplomacy_panel()
	_suite_setup = ""

func _setup_research_panel() -> void:
	_suite_setup = "research_panel"
	_state = ResearchState.make()
	_panel = ResearchPanel.new()
	add_child(_panel)

func _setup_province_panel() -> void:
	_suite_setup = "province_panel"
	_model = Fixture.build()
	_model.resource[_model.index_of(LINKED_TILE.x, LINKED_TILE.y)] = 0
	_model.resource[_model.index_of(VACANT_TILE.x, VACANT_TILE.y)] = 4
	_works = LandWorks.new()
	_works.set_improvement(_model, LINKED_TILE, 2)
	_works.set_improvement(_model, OFF_ROAD_TILE, 1)
	_works.set_prospected(0, _model, OFF_ROAD_TILE)
	_units = []
	_province_panel_panel = ProvincePanel.new()
	add_child(_province_panel_panel)

func _setup_diplomacy_panel() -> void:
	_suite_setup = "diplomacy_panel"
	state = DiplomacyState.new()
	state.initialize(1)
	panel = DiplomacyPanel.new()
	add_child(panel)
	panel.refresh(state, null, 0, 2500)

func _teardown_research_panel() -> void:
	if is_instance_valid(_panel):
		_panel.free()
	_panel = null

func _teardown_province_panel() -> void:
	if is_instance_valid(_province_panel_panel):
		_province_panel_panel.free()
	_province_panel_panel = null

func _teardown_diplomacy_panel() -> void:
	if is_instance_valid(panel):
		panel.free()
	panel = null

# --- test_research_panel ---

func test_the_panel_lists_every_slot() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	var idle: Array[Label] = _labels("Slot")
	assert_eq(idle.size(), ResearchState.DEFAULT_SLOTS)
	assert_gt(_panel.get_combined_minimum_size().y, 200.0)

func test_open_advances_are_listed_and_startable() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	var picked: Array[String] = []
	_panel.assign_requested.connect(func(tech_id: String) -> void: picked.append(tech_id))
	var button: Button = _button("Research")
	assert_not_null(button)
	button.pressed.emit()
	assert_eq(picked.size(), 1)
	assert_true(TechCatalog.known(picked[0]))
	assert_true(_state.researchable().has(picked[0]))

func test_a_full_roster_disables_new_studies() -> void:
	_setup_research_panel()
	for tech_id: String in ["crop_rotation", "saw_mill", "land_enclosure"]:
		_state.assign(tech_id)
	_panel.refresh(_state, 2500)
	for button: Button in _buttons():
		if button.text == "Research":
			assert_true(button.disabled)

func test_slots_show_progress_funding_and_cancel() -> void:
	_setup_research_panel()
	_state.assign("land_enclosure", "high")
	_state.add_progress("land_enclosure", 800)
	_panel.refresh(_state, 2500)
	var cancelled: Array[int] = []
	_panel.cancel_requested.connect(func(slot: int) -> void: cancelled.append(slot))
	var funding: Array[int] = []
	_panel.funding_requested.connect(func(slot: int) -> void: funding.append(slot))
	var high: Button = _button("High")
	assert_not_null(high)
	high.pressed.emit()
	assert_eq(funding, [0])
	var cancel: Button = _button("Cancel")
	assert_not_null(cancel)
	cancel.pressed.emit()
	assert_eq(cancelled, [0])
	var progress: Label = _label_containing("800 / 1,800 RP")
	assert_not_null(progress)

## The slot line must say what the study costs and what the next phase buys
## (REQ-P1-05 — gold a study spends is never silent).
func test_a_slot_names_its_spend_and_its_next_gain() -> void:
	_setup_research_panel()
	_state.assign("land_enclosure", "medium")
	_state.add_progress("land_enclosure", 800)
	_panel.refresh(_state, 2500)
	assert_not_null(_label_containing("150 ducats"), "the gold the slot spends a turn")
	assert_not_null(_label_containing("800 / 1,800 RP"), "banked against the cost")
	assert_not_null(_label_containing("+300 → 1,100"), "next turn's gain and where it lands")

func test_the_gauge_previews_the_next_phase() -> void:
	_setup_research_panel()
	_state.assign("land_enclosure", "high")
	_state.add_progress("land_enclosure", 800)
	_panel.refresh(_state, 2500)
	var bar: ResearchBar = _slot_row(0).bar()
	assert_eq(bar.target_progress(), 800)
	assert_eq(bar.next_gain(), 800)
	assert_almost_eq(bar.next_fraction(), 1600.0 / 1800.0, 0.001)
	assert_true(bar.is_paid())

## A funding change repaints the slot the player is looking at; rebuilding it
## would lose the button and restart the gauge (REQ-P1-05).
func test_changing_the_priority_repaints_the_same_row() -> void:
	_setup_research_panel()
	_state.assign("land_enclosure", "medium")
	_panel.refresh(_state, 2500)
	var row: ResearchSlotRow = _slot_row(0)
	var funding: Array[int] = []
	_panel.funding_requested.connect(func(slot: int) -> void: funding.append(slot))
	var medium: Button = _button("Medium")
	assert_not_null(medium)
	medium.pressed.emit()
	assert_eq(funding, [0], "the row asks the controller to cycle the preset")
	_state.cycle_funding(0)
	_panel.refresh(_state, 2500)
	assert_is(row, _slot_row(0), "the funding change must not rebuild the slot")
	assert_not_null(_button("High"))
	assert_eq(row.bar().next_gain(), 800, "the gauge follows the new preset")
	assert_eq(_panel._slots_body.get_child_count(), ResearchState.DEFAULT_SLOTS)

func test_the_heading_totals_what_the_college_spends() -> void:
	_setup_research_panel()
	_state.assign("crop_rotation", "low")
	_state.assign("saw_mill", "medium")
	_panel.refresh(_state, 2500)
	assert_not_null(_label_containing("200 ducats & 400 RP a turn"))

## The treasury cannot cover a Maximum slot here, so the row must say so rather
## than promise points the phase will not pay for (wiki: tech-tree § Research
## Model — no partial funding).
func test_a_slot_the_treasury_cannot_cover_reads_unpaid() -> void:
	_setup_research_panel()
	_state.assign("land_enclosure", "maximum")
	_panel.refresh(_state, 100)
	assert_not_null(_label_containing("unpaid next turn"))
	assert_eq(_slot_row(0).gold_next(), 0)
	assert_eq(_slot_row(0).bar().next_gain(), 0)

func test_known_techs_move_to_the_known_tab() -> void:
	_setup_research_panel()
	_state.unlock("crop_rotation")
	_panel.refresh(_state, 2500)
	_panel.select_tab(1)
	var known: Label = _label_containing("Crop Rotation")
	assert_not_null(known)

func test_closing_emits_the_close_signal() -> void:
	_setup_research_panel()
	var closed: Array[bool] = []
	_panel.close_pressed.connect(func() -> void: closed.append(true))
	var close: Button = _button("Close")
	assert_not_null(close)
	close.pressed.emit()
	assert_eq(closed.size(), 1)

func test_the_goal_strip_starts_empty() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	assert_eq(_panel.goal_tech(), "")
	assert_not_null(_label_containing("No goal"))

func test_setting_a_goal_names_it_and_sorts_the_queue() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	_panel.set_goal("national_bureaucracy")
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "national_bureaucracy")
	assert_not_null(_label_containing("National Bureaucracy"))
	assert_eq(_first_available(), "Printing Press", "a prerequisite of the goal leads the queue")

func test_the_goal_marks_its_path() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	_panel.set_goal("national_bureaucracy")
	await get_tree().process_frame
	var marked: int = 0
	for node: Node in _nodes():
		if node is Label and (node as Label).text == ResearchRow.GOAL_ON_PATH:
			marked += 1
	assert_gt(marked, 0, "prerequisites on the goal's path carry the mark")

func test_clearing_the_goal_restores_catalog_order() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	_panel.set_goal("national_bureaucracy")
	var clear: Button = _button("Clear")
	assert_not_null(clear)
	clear.pressed.emit()
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "")
	assert_eq(_first_available(), "Crop Rotation")

func test_the_goal_button_steers_the_queue() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	var goal: Button = _button("Goal")
	assert_not_null(goal)
	var steered: Array[String] = []
	_panel.goal_changed.connect(func(tech_id: String) -> void: steered.append(tech_id))
	goal.pressed.emit()
	assert_eq(_panel.goal_tech(), "crop_rotation")
	assert_eq(steered, ["crop_rotation"])

func test_a_reached_goal_says_so() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	_panel.set_goal("crop_rotation")
	_state.unlock("crop_rotation")
	_panel.refresh(_state, 2500)
	await get_tree().process_frame
	assert_not_null(_label_containing("reached"))

func test_an_unknown_goal_clears_it() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	_panel.set_goal("crop_rotation")
	_panel.set_goal("no_such_tech")
	assert_eq(_panel.goal_tech(), "")

## The goal is kept with the campaign (DR-20261111-21): steering writes it into
## the research state, and the ledger reopens on it instead of catalog order.
func test_steering_writes_the_goal_into_the_campaign_state() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	_panel.set_goal("national_bureaucracy")
	assert_eq(_state.goal, "national_bureaucracy", "the goal is state the save carries")
	_panel.set_goal("")
	assert_eq(_state.goal, "", "clearing the goal clears it from the state")

func test_a_ledger_reopens_on_the_goal_the_campaign_carries() -> void:
	_setup_research_panel()
	_state.goal = "national_bureaucracy"
	_panel.refresh(_state, 2500)
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "national_bureaucracy")
	assert_not_null(_label_containing("National Bureaucracy"))
	assert_eq(_first_available(), "Printing Press", "the saved goal still sorts the queue")

## The persistent row the panel keeps for one slot.
func _slot_row(index: int) -> ResearchSlotRow:
	return _panel._slots_body.get_child(index) as ResearchSlotRow

## The first name in the AVAILABLE tab, which is the goal-aware queue order.
func _first_available() -> String:
	var body: VBoxContainer = _panel._available_body
	if body.get_child_count() == 0:
		return ""
	for node: Node in _collect(body.get_child(0), [] as Array[Node]):
		if not node is Label:
			continue
		var text: String = (node as Label).text
		for tech_id: String in TechCatalog.ids():
			if TechCatalog.display_name(tech_id) == text:
				return text
	return ""

func _nodes() -> Array[Node]:
	return _collect(_panel, [] as Array[Node])

func _collect(root: Node, into: Array[Node]) -> Array[Node]:
	for child in root.get_children():
		into.append(child)
		_collect(child, into)
	return into

func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for node: Node in _nodes():
		if node is Button:
			out.append(node as Button)
	return out

func _button(text: String) -> Button:
	for button: Button in _buttons():
		if button.text == text:
			return button
	return null

func _labels(prefix: String) -> Array[Label]:
	var out: Array[Label] = []
	for node: Node in _nodes():
		if node is Label and (node as Label).text.begins_with(prefix):
			out.append(node as Label)
	return out

func _label_containing(text: String) -> Label:
	for node: Node in _nodes():
		if node is Label and (node as Label).text.contains(text):
			return node as Label
	return null

# --- test_province_panel ---

## A province's holder is named by its kind, so a tribe's land never reads as a
## crown's (wiki: factions — three governing types).
func test_the_head_names_the_kind_of_court_that_holds_the_land() -> void:
	_setup_province_panel()
	var head := ProvinceSheetHead.new()
	add_child(head)
	var data: ProvinceState = _model.province_data(0)
	var cases: Array = [
		[
			FactionCatalog.PLAYER_FACTION,
			"Crown of %s" % FactionCatalog.name_of(FactionCatalog.PLAYER_FACTION),
		],
		[6, "Minor nation of Genoa"],
		[9, "Tribe of the Aztec"],
		[-1, "Unclaimed territory"],
	]
	for spec: Array in cases:
		data.owner = int(spec[0])
		head.show_province(data)
		assert_eq(head.owner_label.text, String(spec[1]))
	head.free()

func test_the_dossier_lists_every_estate_not_just_the_headline() -> void:
	_setup_province_panel()
	_show()
	var rows: Array[Dictionary] = _province_panel_panel._resources.lines()
	assert_eq(rows.size(), 4, "four resource tiles, not the province's one headline")
	var tiles: Array[Vector2i] = []
	for row: Dictionary in rows:
		tiles.append(row["tile"])
	assert_true(tiles.has(LINKED_TILE), "the timber tile")
	assert_true(tiles.has(VACANT_TILE), "the grain tile")
	assert_true(tiles.has(OFF_ROAD_TILE), "the iron tile")
	assert_true(tiles.has(Fixture.TIMBER_TILE), "the province's other timber tile")

func test_each_estate_says_whether_it_is_developed_and_linked() -> void:
	_setup_province_panel()
	_show()
	var by_tile: Dictionary = _by_tile()
	assert_eq(int(by_tile[LINKED_TILE]["level"]), 2, "developed")
	assert_true(bool(by_tile[LINKED_TILE]["connected"]), "and linked")
	assert_eq(int(by_tile[VACANT_TILE]["level"]), 0, "bare")
	assert_true(bool(by_tile[VACANT_TILE]["connected"]), "but on the road")
	assert_eq(int(by_tile[OFF_ROAD_TILE]["level"]), 1, "developed")
	assert_false(bool(by_tile[OFF_ROAD_TILE]["connected"]), "and cut off")
	var words: Array[String] = _row_text(_province_panel_panel._resources, LINKED_TILE)
	assert_true(words.has("L2"), "the level is printed: %s" % [words])
	assert_true(words.has("linked"), "the capital link is printed: %s" % [words])
	words = _row_text(_province_panel_panel._resources, OFF_ROAD_TILE)
	assert_true(words.has("no road"), "a cut-off estate says so: %s" % [words])

## Every estate carries its own commodity medallion; a row whose good is not in
## the catalog keeps the category pictogram rather than losing its mark.
func test_an_estate_shows_its_goods_medallion() -> void:
	_setup_province_panel()
	_show()
	var art: Array[Node] = _province_panel_panel._resources.find_children("*", "TextureRect", true, false)
	assert_gt(art.size(), 0, "the estate block draws medallions")
	var plain: Control = _province_panel_panel._resources._art({"commodity": "", "icon": "ore"})
	assert_true(plain is Icon, "an unknown good falls back to the category pictogram")
	plain.free()

func test_the_roads_row_names_the_estates_that_reach_the_crown() -> void:
	_setup_province_panel()
	_show()
	assert_eq(_province_panel_panel._grid.road.text, "1 of 2 developed estates linked")
	assert_true(_province_panel_panel._grid.road.tooltip_text.contains("4 estates surveyed"))

func test_a_province_with_no_developed_estate_says_so() -> void:
	_setup_province_panel()
	_works = LandWorks.new()
	_show()
	assert_eq(_province_panel_panel._grid.road.text, "No developed estate yet")

func test_the_dossier_keeps_no_population_or_capital_row() -> void:
	_setup_province_panel()
	_show()
	var captions: Array[String] = _captions(_province_panel_panel._grid)
	assert_false(captions.has("Population"), "population has no rule behind it")
	assert_false(captions.has("Capital"), "the header badge already says CAPITAL")
	assert_true(captions.has("Terrain"))
	assert_true(captions.has("Roads"))

func test_the_town_row_names_the_town_level() -> void:
	_setup_province_panel()
	_show()
	assert_eq(_province_panel_panel._grid.town.text, "Level 1")
	_model.provinces[0].town_development = 4
	_show()
	assert_eq(_province_panel_panel._grid.town.text, "Level 4 · full")

## The town row's tip names the path the province on screen actually offers: a
## Builder in a crown's own land, a Merchant's deed in a Minor or Tribe province
## (wiki: civilian-units § Merchant; DR-20261112-01). A Builder a crown may not
## send there is not advice.
func test_the_town_row_names_the_path_that_province_offers() -> void:
	_setup_province_panel()
	_show()
	assert_true(
		_province_panel_panel._grid.town.tooltip_text.contains("A Builder raises the town"),
		"a crown's own town is its Builder's work"
	)
	_model.provinces[1].owner = 6
	_model.provinces[1].town_tile = Fixture.RIVAL_GRAIN_TILE
	_province_panel_panel.set_data(_model, _works, _units, null, Vector2i(0, 0), 0, {}, {})
	_province_panel_panel.refresh(_model, 1)
	assert_true(
		_province_panel_panel._grid.town.tooltip_text.contains("Merchant"),
		"a Minor's town grows only from a deed: %s" % _province_panel_panel._grid.town.tooltip_text
	)
	assert_false(
		_province_panel_panel._grid.town.tooltip_text.contains("A Builder raises the town"),
		"the tip never names a Builder a crown cannot send there"
	)
	assert_eq(
		DossierCopy.town_tip(null), DossierCopy.TOWN_TIP,
		"a missing province falls back to the Builder line"
	)

## The roads tip counts one road tile and one estate in the singular: the tooltip
## is the only place a province says how much of its network it holds.
func test_the_roads_tip_counts_one_in_the_singular() -> void:
	var province := ProvinceState.create(
		0, "Cádiz", [] as Array[Vector2i], Vector2(0, 0), 1, 0, true
	)
	province.road_paths = [[Vector2i(1, 1)]]
	var one: Array[Dictionary] = [
		{"ours": true, "level": 1, "connected": true},
	]
	assert_true(
		DossierCopy.roads_tip(province, one).contains("1 road tile laid here"),
		DossierCopy.roads_tip(province, one)
	)
	assert_true(
		DossierCopy.roads_tip(province, one).contains("1 estate surveyed"),
		DossierCopy.roads_tip(province, one)
	)
	assert_eq(DossierCopy.roads(one), "1 of 1 developed estate linked")
	province.road_paths = [[Vector2i(1, 1), Vector2i(2, 1)]]
	var two: Array[Dictionary] = [
		{"ours": true, "level": 1, "connected": true},
		{"ours": true, "level": 2, "connected": false},
	]
	assert_true(
		DossierCopy.roads_tip(province, two).contains("2 road tiles laid here"),
		DossierCopy.roads_tip(province, two)
	)
	assert_true(DossierCopy.roads_tip(province, two).contains("2 estates surveyed"))
	assert_eq(DossierCopy.roads(two), "1 of 2 developed estates linked")


func test_the_town_order_stays_shut_until_national_bureaucracy() -> void:
	_setup_province_panel()
	_show({})
	assert_true(_province_panel_panel._orders.town_button.disabled, "no tech, no order")
	assert_true(
		_province_panel_panel._orders.town_button.tooltip_text.contains("National Bureaucracy"),
		"the button says what it waits for: %s" % _province_panel_panel._orders.town_button.tooltip_text
	)
	_show({"national_bureaucracy": true})
	assert_false(_province_panel_panel._orders.town_button.disabled, "researched, the order opens")

func test_a_fully_developed_town_closes_the_order() -> void:
	_setup_province_panel()
	_model.provinces[0].town_development = 4
	_show({"national_bureaucracy": true})
	assert_true(_province_panel_panel._orders.town_button.disabled)
	assert_true(_province_panel_panel._orders.town_button.tooltip_text.contains("fully developed"))

func test_a_foreign_province_offers_no_town_order() -> void:
	_setup_province_panel()
	_model.provinces[1].town_tile = Fixture.RIVAL_GRAIN_TILE
	_province_panel_panel.set_data(
		_model, _works, _units, null, Vector2i(0, 0), 0, {},
		{"national_bureaucracy": true}
	)
	_province_panel_panel.refresh(_model, 1)
	assert_true(_province_panel_panel._orders.town_button.disabled)
	assert_true(_province_panel_panel._orders.town_button.tooltip_text.contains("not held by your crown"))

func test_every_dock_button_is_a_bare_glyph() -> void:
	_setup_province_panel()
	var panels: Array = [_province_panel_panel, FleetPanel.new(), ArmyPanel.new(), CivilianPanel.new()]
	for i in range(1, panels.size()):
		add_child(panels[i])
	for panel: Variant in panels:
		# Force dossiers keep the seal on their shared header; the sheets that
		# still own it expose `_dock` directly.
		var header: DossierHeader = panel.get("_header") as DossierHeader
		var dock: Button = header.dock if header != null else panel.get("_dock") as Button
		assert_true(dock != null, "%s has a dock button" % panel.get_class())
		panel.set_dock_affordance("▶", "Dock right")
		assert_eq(dock.text, "▶", "the glyph and nothing else")
		assert_false(dock.text.contains("Dock"), "no word on the button")
		assert_true(
			dock.custom_minimum_size.x <= 40.0 and dock.custom_minimum_size.y <= 40.0,
			"a corner button, not a bar: %s" % dock.custom_minimum_size
		)
	for i in range(1, panels.size()):
		(panels[i] as Node).free()

func _show(tech: Dictionary = {}) -> void:
	_province_panel_panel.set_data(_model, _works, _units, null, Vector2i(0, 0), 0, {}, tech)
	_province_panel_panel.refresh(_model, 0)

func test_the_estate_block_names_the_ground_still_to_survey() -> void:
	_setup_province_panel()
	_show()
	# The fixture's iron tile is already prospected; the bare hills are not.
	var text: String = _province_panel_panel._resources.survey_text()
	assert_true(text.contains("Unsurveyed ground"), text)
	assert_true(text.contains("1 tile"), text)


## A good the catalog has no medallion for keeps its pictogram, and that mark
## wears the commodity ink the survey lens uses (REQ-P1-02, REQ-P1-08).
func test_an_estate_without_a_medallion_keeps_its_commodity_ink() -> void:
	_setup_province_panel()
	var block := ProvinceResources.new()
	add_child(block)
	var art := block._art({"icon": "ore", "commodity": ""}) as Icon
	assert_not_null(art, "a good outside the catalog still draws a pictogram")
	assert_eq(art.tint, Palette.resource_ink("ore"), "iron grey, not the old gold")
	block.free()


## The management ledger's pictogram names the commodity; the chip and pips
## beside it carry the works' status.
func test_an_estate_row_wears_its_commodity_ink_not_its_status() -> void:
	_setup_province_panel()
	var row := ImprovementRow.new()
	add_child(row)
	row.setup({
		"tile": Vector2i(0, 0),
		"level": 2,
		"status": "disconnected",
		"resource": 0,
		"name": "Lumber camp",
		"province_name": "Test",
		"connected": false,
		"output": 2,
		"commodity": "timber",
		"status_text": "No road to the crown",
		"max_level": ImprovementCatalog.MAX_LEVEL,
		"cost_text": "10 crowns",
		"duration": 3,
		"build_reason": "No Builder in reach",
		"working": false,
		"can_build": false,
		"builder_id": -1,
		"next_level": 3,
	})
	assert_eq(row._icon.kind, "tree")
	assert_eq(row._icon.tint, Palette.resource_ink("tree"), "timber green, not the status ink")
	assert_eq(row._status_chip.text, "DISCONNECTED", "the chip still names the status")
	row.free()

func test_an_empty_estate_block_still_names_the_ground_to_read() -> void:
	_setup_province_panel()
	var block := ProvinceResources.new()
	add_child(block)
	block.render([], 3)
	assert_true(block._empty.text.contains("No estates charted"))
	assert_true(block._empty.text.contains("3 tiles"))
	assert_true(block.survey_text().contains("3 tiles"))
	# A fully read province says nothing, and keeps the plain empty line.
	block.render([], 0)
	assert_true(block._empty.text.begins_with("No charted"))
	assert_eq(block.survey_text(), "")
	block.free()

func _by_tile() -> Dictionary:
	var by_tile: Dictionary = {}
	for row: Dictionary in _province_panel_panel._resources.lines():
		by_tile[row["tile"]] = row
	return by_tile

## Every label printed on the estate block's line for one tile.
func _row_text(block: ProvinceResources, tile: Vector2i) -> Array[String]:
	var words: Array[String] = []
	var rows: Array[Dictionary] = block.lines()
	for i in rows.size():
		if rows[i]["tile"] != tile:
			continue
		var line: Node = block._body.get_child(i)
		for node: Node in line.find_children("*", "Label", true, false):
			words.append((node as Label).text)
	return words

func _captions(grid: GridContainer) -> Array[String]:
	var captions: Array[String] = []
	for node: Node in grid.get_children():
		var label := node as Label
		if label != null and not label.text.is_empty():
			captions.append(label.text)
	return captions

# --- test_diplomacy_panel ---

func test_lists_known_courts_and_selects_the_first() -> void:
	_setup_diplomacy_panel()
	assert_eq(panel.selected_faction(), 1, "England sorts first among other Great Powers")
	assert_true(_has_text(panel._list, "England"))
	assert_true(_has_text(panel._list, "Genoa"))
	assert_false(_has_text(panel._list, "Aztec"), "uncontacted Tribes stay hidden")

func test_selecting_a_minor_updates_the_detail() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(6)
	assert_eq(panel.selected_faction(), 6)
	assert_true(_has_text(panel._detail, "Genoa"))
	assert_true(_has_text(panel._detail, "At Peace"))
	assert_true(_has_text(panel._detail, "Herald:"))

func test_relation_ladder_is_used_instead_of_the_raw_score() -> void:
	_setup_diplomacy_panel()
	state.relation(0, 6).score = 92.0
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "Devoted"))
	assert_false(_has_text(panel._detail, "92"))

func test_the_ten_word_ladder_is_the_only_relation_wording() -> void:
	_setup_diplomacy_panel()
	state.relation(0, 6).score = 22.4
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._list, "Distrustful"), "the court row carries the herald word")
	assert_true(_has_text(panel._detail, "Herald: Distrustful"))
	assert_false(_has_text(panel._detail, "Hostile"), "the superseded four-band word is not shown")

func test_order_buttons_emit_kind_target_and_argument() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(6)
	var seen: Array[Array] = []
	panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			seen.append([kind, target, arg])
	)
	var button: Button = _find_button(panel._detail, "Offer Trade Consulate")
	assert_not_null(button)
	button.pressed.emit()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], "overture")
	assert_eq(seen[0][1], 6)
	assert_eq(seen[0][2], DiplomacyCatalog.STAGE_CONSULATE)

func test_disabled_orders_explain_the_refusal() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "An embassy is required before aid can be sent."))
	var button: Button = _find_button(panel._detail, "Grant Aid")
	assert_not_null(button)
	assert_true(button.disabled)

func test_at_war_updates_the_stand_and_offers_peace() -> void:
	_setup_diplomacy_panel()
	DiplomacyRules.declare_war(state, 0, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "At War"))
	assert_not_null(_find_button(panel._detail, "Offer Peace"))

func test_no_relations_shows_an_empty_court() -> void:
	_setup_diplomacy_panel()
	state.reset(1)
	panel.refresh(state, null, 0, 2500)
	assert_eq(panel.selected_faction(), -1)
	assert_true(_has_text(panel._detail, "No court"))

func test_the_court_shows_the_pair_chronicle_under_its_orders() -> void:
	_setup_diplomacy_panel()
	DiplomacyRules.declare_war(state, 0, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "CHRONICLE"))
	assert_true(_has_text(panel._detail, "Spain declared war on Genoa"))
	assert_true(_has_text(panel._detail, "Year 1500 (Turn 1)"))

func test_a_quiet_court_says_so_instead_of_showing_an_empty_box() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "CHRONICLE"))
	assert_true(_has_text(panel._detail, "No word of this court"))

func test_the_court_shows_its_dossier_under_the_chronicle() -> void:
	_setup_diplomacy_panel()
	DiplomacyRules.declare_war(state, 1, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "DOSSIER"), "the reading sits under the news")
	assert_true(_has_text(panel._detail, "Reading:"))
	assert_true(_has_text(panel._detail, "Declared war on Genoa."), "the act is evidence")
	assert_false(_has_text(panel._detail, "Confirmed"), "one act cannot confirm an agenda")

func test_a_quiet_court_says_the_dossier_is_empty() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "DOSSIER"))
	assert_true(_has_text(panel._detail, "no act has yet spoken"))
	assert_true(_has_text(panel._detail, "No observable act"))

func test_the_dossier_bands_acts_and_trims_older_evidence() -> void:
	_setup_diplomacy_panel()
	for _index in 4:
		state.record_event("warDeclared", 1, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "Warmonger"), "the agenda is named")
	assert_true(_has_text(panel._detail, "Likely 60%"), "four wars reach the Likely band")
	assert_true(_has_text(panel._detail, "…and 1 earlier observation"), "older acts are counted")
	assert_false(_has_text(panel._detail, "Confirmed"), "nothing is certain yet")

## The summary opens the full sheet on the court in view (REQ-P5-01,
## DR-20261110-25).
func test_the_dossier_offers_its_full_screen_for_the_selected_court() -> void:
	_setup_diplomacy_panel()
	DiplomacyRules.declare_war(state, 1, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(1)
	var sheet := CourtDossierScreen.new()
	add_child(sheet)
	panel.dossier_screen = sheet
	var button: Button = _find_button(panel._detail, "Full dossier")
	assert_not_null(button, "the reading has one door to its full copy")
	button.pressed.emit()
	assert_true(sheet.is_open(), "the door opens the full sheet")
	assert_eq(sheet._body.subject, 1, "on the court in view")
	sheet.free()

func test_a_waiting_intervention_prompts_and_emits_the_answer() -> void:
	_setup_diplomacy_panel()
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	panel.refresh(state, null, 0, 2500)
	assert_true(_has_text(panel._call_box, "INTERVENTION"))
	assert_true(_has_text(panel._call_box, "Genoa"))
	var seen: Array[Array] = []
	panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			seen.append([kind, target, arg])
	)
	var button: Button = _find_button(panel._call_box, "Protest")
	assert_not_null(button)
	button.pressed.emit()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], Intervention.KIND_PROTEST)
	assert_eq(seen[0][1], 3)

func test_a_waiting_call_to_arms_names_its_price_and_emits_the_answer() -> void:
	_setup_diplomacy_panel()
	state.relation(0, 1).score = 80.0
	state.relation(0, 1).formal_alliance = true
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 2, 1)
	panel.refresh(state, null, 0, 2500)
	assert_true(_has_text(panel._call_box, "CALL TO ARMS"))
	assert_true(_has_text(panel._call_box, "France"), "the aggressor is named")
	assert_true(_has_text(panel._call_box, "England"), "and the ally the call defends")
	assert_true(_has_text(panel._call_box, "−50"), "the treaty price is on the banner")
	assert_true(_has_text(panel._call_box, "−10"), "and the cascade with every other crown")
	var seen: Array[Array] = []
	panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			seen.append([kind, target, arg])
	)
	var button: Button = _find_button(panel._call_box, "Join the war")
	assert_not_null(button)
	button.pressed.emit()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], CallToArms.KIND_JOIN)
	assert_eq(seen[0][1], 2, "the answer names the aggressor")

## The banner rides a 570-point court sheet on a landscape phone (914×411 and
## 800×360 both measured): the stakes line must stay inside the height the sheet
## has left, so a longer price cannot push the buttons out of reach
## (wiki: diplomacy § Alliances).
func test_the_call_banner_keeps_the_phone_sheet_height() -> void:
	_setup_diplomacy_panel()
	state.relation(0, 1).score = 80.0
	state.relation(0, 1).formal_alliance = true
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 2, 1)
	panel.size = Vector2(570, 600)
	panel.refresh(state, null, 0, 2500)
	await get_tree().process_frame
	var banner: Control = panel._call_box.get_child(0) as Control
	assert_not_null(banner, "the banner is up")
	assert_gt(banner.size.y, 100.0, "the banner is laid out with its copy and buttons")
	assert_true(
		banner.size.y <= 140.0,
		"the call banner must fit a phone sheet (%s > 140)" % banner.size.y
	)

## A rival's trade pact is answered blind unless the prompt carries the rate the
## pact publishes: the court reads the terms beside the offer and the envoy that
## brings it (wiki: world-market § FTP; dialogue-and-mood § Mood machine).
func test_a_pact_proposal_names_its_terms_and_its_envoy() -> void:
	_setup_diplomacy_panel()
	state.relation(0, 2).score = 70.0
	DiplomacyProposals.queue(state, null, 2, DiplomacyProposals.KIND_FTP)
	panel.size = Vector2(570, 600)
	panel.refresh(state, null, 0, 2500)
	assert_true(_has_text(panel._call_box, "PROPOSAL"))
	assert_true(_has_text(panel._call_box, "Favoured terms"))
	assert_true(_has_text(panel._call_box, "95%"), "the rate the pact pays")
	assert_true(_has_text(panel._call_box, "105%"), "and the rate it earns")
	assert_true(_has_text(panel._call_box, "“"), "the envoy who brings it speaks")
	await get_tree().process_frame
	var banner: Control = panel._call_box.get_child(0) as Control
	assert_not_null(banner, "the pact banner is up")
	assert_true(
		banner.size.y <= 150.0,
		"the pact banner must fit a phone sheet (%s > 150)" % banner.size.y
	)


func test_a_rival_proposal_prompts_and_emits_the_answer() -> void:
	_setup_diplomacy_panel()
	state.relation(0, 2).score = 80.0
	DiplomacyProposals.queue(state, null, 2, DiplomacyProposals.KIND_ALLIANCE)
	panel.refresh(state, null, 0, 2500)
	assert_true(_has_text(panel._call_box, "PROPOSAL"))
	assert_true(_has_text(panel._call_box, "France"))
	var seen: Array[Array] = []
	panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			seen.append([kind, target, arg])
	)
	var button: Button = _find_button(panel._call_box, "Accept")
	assert_not_null(button)
	button.pressed.emit()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], DiplomacyProposals.KIND_ACCEPT)
	assert_eq(seen[0][1], 2)

func test_the_court_speaks_in_its_envoy_strip() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "THEIR ENVOY"), "the court has a voice")
	assert_true(_has_text(panel._detail, "“"), "and quotes its word")

func test_the_envoy_carries_the_face_of_the_court() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(6)
	var faces: Array[String] = []
	for mood: String in DialogueMood.MOODS:
		faces.append(mood.to_upper())
	assert_true(_has_any_face(faces), "a documented face is worn")

func test_a_declaration_is_quoted_under_the_herald() -> void:
	_setup_diplomacy_panel()
	DiplomacyRules.declare_war(state, 0, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "THEIR ENVOY"))
	assert_true(
		_has_text(panel._detail, "·  IRRITATED") or _has_text(panel._detail, "·  DISMISSIVE"),
		"a war puts a hard face on the court"
	)

func test_a_waiting_proposal_banner_quotes_the_proposing_court() -> void:
	_setup_diplomacy_panel()
	state.relation(0, 2).score = 80.0
	DiplomacyProposals.queue(state, null, 2, DiplomacyProposals.KIND_ALLIANCE)
	panel.refresh(state, null, 0, 2500)
	assert_true(_has_text(panel._call_box, "PROPOSAL  ·  "), "the face rides the banner")
	assert_true(_has_text(panel._call_box, "“"), "and the words under it")

func test_a_great_power_offers_the_trading_pact_in_the_trade_block() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "TRADE TERMS"), "trade sits in its own block")
	assert_true(_has_text(panel._detail, "of the world price"), "terms are plain language")
	var button: Button = _find_button(panel._detail, "Offer Favoured Trading Pact")
	assert_not_null(button)
	var seen: Array[Array] = []
	panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			seen.append([kind, target, arg])
	)
	button.pressed.emit()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], DiplomacyOrders.KIND_FTP)
	assert_eq(seen[0][1], 1)

func test_a_standing_pact_shows_in_the_row_and_offers_the_way_out() -> void:
	_setup_diplomacy_panel()
	state.ftps[state.pair_key(0, 1)] = state.turn
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(1)
	assert_true(_has_text(panel._list, "Trade Pact"))
	assert_true(_has_text(panel._detail, "our lots clear first"))
	assert_not_null(_find_button(panel._detail, "End Favoured Trading Pact"))

func test_subsidy_options_carry_a_plain_price_hint() -> void:
	_setup_diplomacy_panel()
	state.ensure_relation(0, 6, state.turn)
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "TRADE TERMS"))
	assert_true(_has_text(panel._detail, "cost us 10% more"))
	var button: Button = _find_button(panel._detail, "Set Subsidy · 10%")
	assert_not_null(button)
	assert_false(button.disabled)
	var seen: Array[Array] = []
	panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			seen.append([kind, target, arg])
	)
	button.pressed.emit()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], DiplomacyOrders.KIND_SUBSIDY)
	assert_eq(seen[0][2], "10")

func test_an_active_subsidy_is_ticked_and_can_be_ended() -> void:
	_setup_diplomacy_panel()
	state.ensure_relation(0, 6, state.turn)
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 10)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "✓ Set Subsidy · 10%"), "the standing rate is marked")
	assert_not_null(_find_button(panel._detail, "End Subsidy · 10%"))

func test_a_boycott_is_stated_in_the_trade_block() -> void:
	_setup_diplomacy_panel()
	state.set_colony(9, 0)
	DiplomacyTrade.boycott(state, 0, 2)
	state.boycotts["1>0"] = state.turn
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(2)
	assert_true(_has_text(panel._detail, "closed to France"), "the issuer states the boycott")
	assert_true(_has_text(panel._list, "Boycott"), "the row carries it too")
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "Boycotted by England"), "and the victim reads it")

func test_orders_are_grouped_under_readable_headings() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "TREATIES"))
	assert_true(_has_text(panel._detail, "AID"))
	assert_true(_has_text(panel._detail, "TRADE TERMS"))

func _has_any_face(faces: Array[String]) -> bool:
	for face: String in faces:
		if _has_text(panel._detail, "·  %s" % face):
			return true
	return false

func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false

func _find_button(node: Node, needle: String) -> Button:
	if node is Button and String((node as Button).text).contains(needle):
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, needle)
		if found != null:
			return found
	return null


# --- Army dossier roster / muster blocks (ui domain; REQ-P3-01) ---
const ArmyFixture = preload("res://tests/army_fixture.gd")


## Drill-yard rows render cost or refusal, and a Muster tap emits recruit.
func test_army_muster_block_fills_ok_and_blocked_rows() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(20, 0, 1, ["guards"], true)
	var muster: Array[Dictionary] = [
		{
			"type_id": "peasant_levies",
			"name": "Peasant Levies",
			"ok": true,
			"cost_text": "2,000 cash · 1 fabric",
			"reason": "",
		},
		{
			"type_id": "grenadiers",
			"name": "Grenadiers",
			"ok": false,
			"cost_text": "",
			"reason": "Need Organised Regiments",
		},
	]
	var heard: Array[String] = []
	panel._muster_box.action_pressed.connect(func(action: String) -> void: heard.append(action))

	panel.refresh(model, army, true, false, "", muster)
	panel.set_muster_open(true)

	assert_eq(panel._muster_box.get_child_count(), 2)
	var ok_top: HBoxContainer = panel._muster_box.get_child(0).get_child(0)
	assert_true(ok_top.get_child(0) is UnitMedallion)
	assert_eq((ok_top.get_child(1) as Label).text, "Peasant Levies")
	var ok_btn: Button = ok_top.get_child(2) as Button
	assert_false(ok_btn.disabled)
	assert_eq(ok_btn.tooltip_text, "2,000 cash · 1 fabric")
	assert_eq(
		(panel._muster_box.get_child(0).get_child(1) as Label).text,
		"2,000 cash · 1 fabric"
	)
	ok_btn.pressed.emit()
	assert_eq(heard, ["recruit:peasant_levies"])

	var blocked_top: HBoxContainer = panel._muster_box.get_child(1).get_child(0)
	var blocked_btn: Button = blocked_top.get_child(2) as Button
	assert_true(blocked_btn.disabled)
	assert_eq(blocked_btn.tooltip_text, "Need Organised Regiments")
	assert_eq(
		(panel._muster_box.get_child(1).get_child(1) as Label).text,
		"Need Organised Regiments"
	)
	panel.free()


## Chevrons and a mauled bar live on the roster block; strength names the count.
func test_army_roster_block_shows_chevrons_wounds_and_record() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(21, 0, 1, ["guards", "pikemen"], false)
	var veteran: String = army.regiments[0]
	army.regiment_medals[veteran] = 2
	army.regiment_health[veteran] = 60
	army.regiment_engagements[veteran] = 3
	army.regiment_wins[veteran] = 2
	var heard: Array[String] = []
	panel._roster.action_pressed.connect(func(action: String) -> void: heard.append(action))

	panel.refresh(model, army, true)

	var row: VBoxContainer = panel._roster.get_child(0)
	assert_true(String(panel._strength.text).contains("2 chevrons"), panel._strength.text)
	var condition: HBoxContainer = row.get_child(2)
	assert_true(condition.get_child(0) is TextureRect)
	assert_eq((condition.get_child(1) as Label).text, "×2")
	assert_almost_eq((condition.get_child(2) as ProgressBar).value, 0.5, 0.01)
	assert_eq((condition.get_child(3) as Label).text, "50%")
	var record: Label = row.get_child(row.get_child_count() - 1)
	assert_eq(String(record.text), "3 engagements · 2 won")
	var detach: Button = (row.get_child(0) as HBoxContainer).get_child(2) as Button
	detach.pressed.emit()
	assert_eq(heard, ["detach:%s" % veteran])
	panel.free()


## Embarked armies keep roster detail but drop detach; strength says aboard.
func test_army_roster_block_hides_detach_while_embarked() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(22, 0, 0, ["guards", "pikemen"], false)
	var fleet := FleetState.in_port(1, 0, 0, ["ship_1", "ship_2"])
	assert_true(bool(NavalTransport.embark(model, army, fleet)["ok"]))

	panel.refresh(model, army, true)

	assert_true(String(panel._location.text).contains("Aboard"), panel._location.text)
	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq(
		(row.get_child(0) as HBoxContainer).get_child_count(),
		2,
		"medallion and name only while aboard"
	)
	panel.free()
