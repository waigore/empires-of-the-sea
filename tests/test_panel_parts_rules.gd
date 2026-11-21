extends GdToolsTest
## One boot for the side panels: research, province and diplomacy, plus the
## road works the province dossier's Build road control dispatches.

## Merged from test_research_panel, test_province_panel, test_diplomacy_panel,
## test_road_works_rules, test_court_ui_parts. One Godot boot (coverage
## instrumentation) per theme instead of one per file. Each test runs only its
## own suite's setup; teardown follows the setup.
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

## The road works read the dossier's chart, network and orders; the three are
## shared with the province panel cases, so they live beside them.
var _roads_stock: Dictionary = {}
var _roads_view: VisibilityModel = null
var _roads_units: Array[CivilianState] = []

func after_each() -> void:
	_court_after_each()
	match _suite_setup:
		"research_panel":
			_teardown_research_panel()
		"province_panel":
			_teardown_province_panel()
		"diplomacy_panel":
			_teardown_diplomacy_panel()
		"road_works":
			_teardown_road_works()
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

## The road-works cases read the bare chart and its stockpile, so they pay one
## small fixture between them; the grid is dropped beside the units it spawned.
func _setup_road_works() -> void:
	_suite_setup = "road_works"
	_model = Fixture.build()
	_model.resource[_model.index_of(LINKED_TILE.x, LINKED_TILE.y)] = 0
	_model.resource[_model.index_of(VACANT_TILE.x, VACANT_TILE.y)] = 4
	_works = LandWorks.new()
	_works.set_improvement(_model, LINKED_TILE, 2)
	_works.set_improvement(_model, OFF_ROAD_TILE, 1)
	_works.set_prospected(0, _model, OFF_ROAD_TILE)
	_units = []
	_roads_stock = Fixture.stockpile()
	_roads_view = Fixture.visibility(_model)
	_roads_units = []

func _teardown_road_works() -> void:
	_roads_units = []
	_roads_stock = {}
	_roads_view = null

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

## A purchase row names what the study opens, under its price: the payoff is
## printed, never a hover a touch crown cannot reach (REQ-P1-05, REQ-P5-03).
func test_an_open_advance_names_what_it_opens() -> void:
	_setup_research_panel()
	_panel.refresh(_state, 2500)
	var cap: Label = _label_containing("Improves: extraction cap Timber 2.")
	assert_not_null(cap, "Saw Mill's row names the cap it lifts")
	assert_eq(cap.get_theme_font_size("font_size"), 10, "the payoff is a detail line")
	assert_not_null(
		_label_containing("Unlocks: research paths to Animal Husbandry"),
		"an advance that only opens the road names the road"
	)

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
	assert_eq(_panel.slot_rows().size(), ResearchState.DEFAULT_SLOTS)

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
	var close: Button = _panel._close
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
	var rows: Array[ResearchSlotRow] = _panel.slot_rows()
	return rows[index] if index < rows.size() else null

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


## The province sheet's Deeds row names the crown that bought land here — the bar
## an undeclared march meets — and leaves the grid when nobody has (wiki:
## factions § Tribe — "unless another GP has invested in the province";
## DR-20261120-05).
func test_the_province_sheet_names_the_deeds_bought_in_its_land() -> void:
	_setup_province_panel()
	_province_panel_panel.set_data(
		_model, _works, _units, null, Vector2i(0, 0), 0, {}, {}
	)
	_province_panel_panel.refresh(_model, Fixture.RIVAL_PROVINCE)
	var grid: ProvinceFactsGrid = _province_panel_panel._grid
	assert_false(grid.deeds.visible, "nobody has bought land here")
	assert_true(_model.purchase_tile(Fixture.RIVAL_GRAIN_TILE, 1), "a rival's deed")
	_province_panel_panel.refresh(_model, Fixture.RIVAL_PROVINCE)
	assert_true(grid.deeds.visible, "the row arrives with the deed")
	assert_eq(grid.deeds.text, "%s 1 tile" % FactionCatalog.name_of(1))


## The province sheet names what the wall soaks and what it spares the garrison
## — the fort table's own figures, so a plan is made against the wall a battle
## would fight — and leaves the row out on open ground (wiki: siege-mechanics
## § Wall Protection; DR-20261120-06).
func test_the_province_sheet_names_what_the_wall_soaks() -> void:
	_setup_province_panel()
	_province_panel_panel.set_data(
		_model, _works, _units, null, Vector2i(0, 0), 0, {}, {}
	)
	_province_panel_panel.refresh(_model, Fixture.RIVAL_PROVINCE)
	var grid: ProvinceFactsGrid = _province_panel_panel._grid
	assert_false(grid.wall.visible, "open ground says nothing")
	_model.province_data(Fixture.RIVAL_PROVINCE).fort_level = 1
	_province_panel_panel.refresh(_model, Fixture.RIVAL_PROVINCE)
	assert_true(grid.wall.visible, "the row arrives with the wall")
	assert_eq(grid.wall.text, "10 wall hp · 25% off a blow")
	_model.province_data(Fixture.RIVAL_PROVINCE).fort_level = 3
	_province_panel_panel.refresh(_model, Fixture.RIVAL_PROVINCE)
	assert_eq(grid.wall.text, "30 wall hp · 60% off a blow", "a modern wall")


## The province sheet prints the court's own reading and hides it when the
## reading is empty, so a province neither pass names carries no gold line
## (wiki: world-model § The crown's provinces; DR-20261121-19).
func test_the_province_sheet_prints_and_hides_the_counsel_it_is_handed() -> void:
	_setup_province_panel()
	_show()
	var wired: Callable = _province_panel_panel.counsel_source
	_province_panel_panel.counsel_source = (
		func(_model: MapModel, _province_id: int) -> String:
			return "The court would order its Builder to raise the lumber camp here."
	)
	_show()
	assert_eq(
		_province_panel_panel.counsel_text(),
		"The court would order its Builder to raise the lumber camp here."
	)
	assert_true(_province_panel_panel._counsel.visible, "the sheet prints the line")
	_province_panel_panel.counsel_source = Callable()
	_show()
	assert_eq(
		_province_panel_panel.counsel_text(), "", "an unwired sheet prints nothing"
	)
	assert_false(_province_panel_panel._counsel.visible, "and the line stands down")
	_province_panel_panel.counsel_source = wired


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

## Every estate type reads as its own pictogram (wiki: extraction-and-improvements
## § Improvement Naming; REQ-P1-08, DR-20261119-06): the nine works the catalogue
## publishes, nine kinds, each one a kind the control draws.
func test_each_estate_type_carries_its_own_pictogram() -> void:
	var seen: Dictionary = {}
	for resource: Variant in ImprovementCatalog.RESOURCES.keys():
		var kind: String = ImprovementCatalog.pictogram_kind(int(resource))
		seen[kind] = true
		assert_true(Icon.knows(kind), "%s has no painter" % [kind])
	var expected: Array[String] = [
		"cattle", "coin", "horse", "leaf", "log", "pelt", "pick", "sheep", "wheat",
	]
	var kinds: Array = seen.keys()
	kinds.sort()
	assert_eq(kinds, expected, "the catalogue publishes nine estate pictograms")

## Two estates of different work never read as one glyph: a farm, a pasture, a
## ranch's remounts, a ranch's beeves, a plantation, a fur post, a lumber camp
## and a mine each carry their own.
func test_two_works_on_one_chart_read_apart() -> void:
	var kinds: Array[String] = []
	for resource: int in [0, 1, 3, 4, 5, 6, 7, 13, 16]:
		kinds.append(ImprovementCatalog.pictogram_kind(resource))
	var unique: Dictionary = {}
	for kind: String in kinds:
		unique[kind] = true
	assert_eq(unique.size(), kinds.size(), "two works share a pictogram: %s" % [kinds])
	assert_eq(ImprovementCatalog.pictogram_kind(4), "wheat", "a farm keeps its sheaf")
	assert_eq(ImprovementCatalog.pictogram_kind(5), "sheep", "a pasture is a fleece")
	assert_eq(ImprovementCatalog.pictogram_kind(6), "horse", "remounts read as a shoe")
	assert_eq(ImprovementCatalog.pictogram_kind(7), "cattle", "beeves read as a head")
	assert_eq(ImprovementCatalog.pictogram_kind(0), "log", "a lumber camp is a felled log")
	assert_eq(ImprovementCatalog.pictogram_kind(1), "pick", "a mine is a pick")

## The survey lens still counts in its four published groups, whatever the
## estates' own pictograms say (issue #698): the lens's column key is `icon`.
func test_the_survey_lens_keeps_its_four_columns() -> void:
	assert_eq(",".join(ResourceTypes.ORDER), "tree,ore,coin,wheat")
	for resource: Variant in ImprovementCatalog.RESOURCES.keys():
		var column: String = ImprovementCatalog.icon_kind(int(resource))
		assert_true(
			ResourceTypes.ORDER.has(column),
			"resource %s reads outside the lens's columns: %s" % [resource, column]
		)
	assert_eq(ImprovementCatalog.icon_kind(5), "wheat", "a pasture stays a farm column")


## Each mark actually paints: the control raises one Icon per estate kind and
## the frame draws it, so no published pictogram is ever a silent blank
## (REQ-P1-08; DR-20261119-06).
func test_every_estate_pictogram_paints() -> void:
	var painted: Array[String] = []
	for kind: String in EstatePictograms.KINDS:
		var icon := Icon.new(kind, 24.0, Palette.estate_ink(kind))
		add_child(icon)
		icon.queue_redraw()
		painted.append(kind)
	await get_tree().process_frame
	assert_eq(painted.size(), 7, "the estates publish seven marks of their own")
	for kind: String in painted:
		assert_true(EstatePictograms.knows(kind), "%s has a painter" % [kind])
		assert_true(Icon.knows(kind), "the control draws %s too" % [kind])

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

## The dossier's town order reads the purse as well as the study: a crown that
## cannot pay the materials is told which ones, not offered a button the work
## order refuses (wiki: civilian-units § Builder; REQ-P2-03).
func test_the_town_order_shuts_for_the_stores_it_cannot_pay() -> void:
	_setup_province_panel()
	_model.provinces[0].town_development = 1
	var stock: Dictionary = {}
	_province_panel_panel.set_data(
		_model, _works, _units, null, Vector2i(0, 0), 0, {},
		{"national_bureaucracy": true}, stock
	)
	_province_panel_panel.refresh(_model, 0)
	assert_true(_province_panel_panel._orders.town_button.disabled, "an empty purse offers no order")
	assert_true(
		_province_panel_panel._orders.town_button.tooltip_text.contains("Stores are short of"),
		"and names the shortfall: %s" % _province_panel_panel._orders.town_button.tooltip_text
	)
	stock["lumber"] = 4
	stock["castIron"] = 4
	_province_panel_panel.refresh(_model, 0)
	assert_false(_province_panel_panel._orders.town_button.disabled, "paid, the order opens")

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


## The muster rail names what each craft does and the one study a hire waits on,
## and a gated craft greys out instead of offering an order the rules refuse — the
## gate used to arrive only in the refusal toast (wiki: civilian-units § Training;
## DR-20261118-09; REQ-P2-03, REQ-P5-05).
func test_the_muster_rail_names_what_each_craft_does() -> void:
	_setup_province_panel()
	_show()
	var rail: ProvinceOrdersSection = _province_panel_panel._orders
	var explorer: Dictionary = rail.training_row("explorer")
	assert_eq(
		(explorer["note"] as Label).text, "Charts a province and prospects its ground"
	)
	assert_false(
		(explorer["button"] as Button).disabled, "a starting craft hires at once"
	)
	# A Merchant waits on Merchant Companies: the row says so and the press is
	# dead until the study lands.
	var merchant: Dictionary = rail.training_row("merchant")
	assert_true((merchant["button"] as Button).disabled)
	assert_eq(
		(merchant["note"] as Label).text,
		"Buys land in a Minor's or Tribe's province · needs Merchant Companies",
	)
	assert_true(
		(merchant["button"] as Button).tooltip_text.contains("Merchant Companies"),
		"the tooltip is the order's own refusal",
	)
	_show({"merchant_companies": true})
	assert_false(
		(merchant["button"] as Button).disabled, "the study opens the hire"
	)
	assert_eq(
		(merchant["note"] as Label).text,
		"Buys land in a Minor's or Tribe's province",
		"an open hire carries no gate",
	)

func test_the_estate_block_names_the_ground_still_to_survey() -> void:
	_setup_province_panel()
	_show()
	# The fixture's iron tile is already prospected; the bare hills are not.
	var text: String = _province_panel_panel._resources.survey_text()
	assert_true(text.contains("Unsurveyed ground"), text)
	assert_true(text.contains("1 tile"), text)


## A province whose tiles tie between two terrains reads the ground the battle
## fights on — the reading ties to the lower terrain id, as
## `ArmyModifiers.terrain_for` does — not whichever terrain the tiles happen to
## name first (wiki: resource-terrain-region-rules § Player-facing terrain
## display names; combat § Modifiers; REQ-P2-03).
func test_a_tied_province_reads_the_ground_its_battle_uses() -> void:
	_setup_province_panel()
	# Six of the crown province's twelve tiles in hills, six in plains, hills
	# first in tile order: the sheet used to read the first maximum it met.
	var tiles: Array = _model.province_tiles(0)
	assert_eq(tiles.size(), 12, "the fixture's crown province")
	for index in tiles.size():
		var tile: Vector2i = tiles[index]
		_model.terrain[_model.index_of(tile.x, tile.y)] = (
			MapModel.Terrain.HILLS if index < 6 else MapModel.Terrain.PLAINS
		)
	_show()
	var ground: int = ArmyModifiers.terrain_for(_model, 0)
	assert_eq(ground, MapModel.Terrain.PLAINS, "the tie falls to the lower terrain id")
	assert_eq(
		_province_panel_panel._grid.terrain.text,
		"Plains (main) · also Hills",
		"the sheet names the ground the battle fights on, then the runner-up"
	)


## One province holds several grounds: the Terrain row says which one a battle
## here fights on and names the second-most common one, so a mixed province no
## longer reads as a single type (wiki: resource-terrain-region-rules
## § Player-facing terrain display names; issue #1084; REQ-P2-03).
func test_the_terrain_row_names_the_main_ground_and_the_second() -> void:
	_setup_province_panel()
	# Seven plains, three scrub and two hills: plains lead, scrub runs second.
	var tiles: Array = _model.province_tiles(0)
	for index in tiles.size():
		var tile: Vector2i = tiles[index]
		var terrain: int = MapModel.Terrain.PLAINS
		if index >= 10:
			terrain = MapModel.Terrain.HILLS
		elif index >= 7:
			terrain = MapModel.Terrain.SCRUB_FOREST
		_model.terrain[_model.index_of(tile.x, tile.y)] = terrain
	_show()
	assert_eq(
		_province_panel_panel._grid.terrain.text,
		"Plains (main) · also Scrub Forest",
		"the row names the main ground and the runner-up in published names"
	)


## A province that is one ground throughout says so once, without inventing a
## second type.
func test_a_single_ground_province_reads_as_one_type() -> void:
	_setup_province_panel()
	for tile: Vector2i in _model.province_tiles(0):
		_model.terrain[_model.index_of(tile.x, tile.y)] = MapModel.Terrain.SWAMP
	_show()
	assert_eq(_province_panel_panel._grid.terrain.text, "All Swamp")


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


## A sealed harbour is not a missing road: the estate line names the seal, so the
## dossier never sends the crown to lay a road it does not need (wiki:
## capital-and-connectivity § Blockade; REQ-P2-03).
func test_a_sealed_estate_names_the_harbour_not_a_missing_road() -> void:
	_setup_province_panel()
	var block := ProvinceResources.new()
	add_child(block)
	block.render([{
		"tile": Vector2i(0, 0),
		"level": 2,
		"resource": 0,
		"commodity": "timber",
		"icon": "tree",
		"ours": true,
		"connected": false,
		"blockaded": true,
		"output": 0,
		"working": false,
		"remaining": 0,
		"prospected": true,
		"needs_prospecting": false,
	}])
	var words: Array[String] = _row_text(block, Vector2i(0, 0))
	assert_true(words.has(ProvinceResources.HARBOUR_CUT), str(words))
	assert_false(words.has(ProvinceResources.UNLINKED), "the seal is not a missing road")
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
	assert_eq(row._icon.kind, "log", "the lumber camp is its own pictogram, not the survey group's")
	assert_eq(
		row._icon.tint, Palette.resource_ink("tree"),
		"timber green, not the status ink (DR-20261119-06)"
	)
	assert_eq(row._status_chip.text, "DISCONNECTED", "the chip still names the status")
	row.free()


## The row prices the raise beside its cost: the rules hand it the words and the
## row prints them in the crown's gold, never inventing a figure of its own
## (REQ-P3-02, REQ-P5-06).
func test_an_estate_row_prints_the_payoff_of_its_next_level() -> void:
	_setup_province_panel()
	var row := ImprovementRow.new()
	add_child(row)
	row.setup({
		"tile": Vector2i(0, 0),
		"level": 2,
		"status": "producing",
		"resource": 0,
		"name": "Lumber camp",
		"province_name": "Test",
		"connected": true,
		"output": 2,
		"commodity": "timber",
		"status_text": "Yields 2 timber / turn",
		"max_level": ImprovementCatalog.MAX_LEVEL,
		"cost_text": "4 lumber + 4 cast iron",
		"duration": 2,
		"build_reason": "",
		"working": false,
		"can_build": true,
		"builder_id": 2,
		"next_level": 3,
		"preview_text": "L3 pays 3 timber / turn (+1)",
	})
	assert_true(row._preview.visible, "a raise the ledger offers carries its payoff")
	assert_eq(row._preview.text, "L3 pays 3 timber / turn (+1)")
	assert_eq(row._preview.get_theme_color("font_color"), Palette.GOLD)
	row.free()
	# A finished estate's row has no raise to price, so no line prints.
	var done := ImprovementRow.new()
	add_child(done)
	done.setup({
		"tile": Vector2i(0, 0),
		"level": 4,
		"status": "maxed",
		"resource": 0,
		"name": "Lumber camp",
		"province_name": "Test",
		"connected": true,
		"output": 4,
		"commodity": "timber",
		"status_text": "Fully improved · 4 timber / turn",
		"max_level": ImprovementCatalog.MAX_LEVEL,
		"cost_text": "",
		"duration": 0,
		"build_reason": "",
		"working": false,
		"can_build": false,
		"builder_id": -1,
		"next_level": 4,
		"preview_text": "",
	})
	assert_false(done._preview.visible, "a finished estate prices no raise")
	done.free()

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


## A cut-off developed estate carries the one-tap road order (issue #671): an
## idle Engineer takes it, and a linked estate never offers one.
func test_a_cut_off_estate_offers_build_road() -> void:
	_setup_province_panel()
	_units = [Fixture.unit("engineer", Vector2i(0, 2))]
	_show()
	var cut := _road_button(OFF_ROAD_TILE)
	assert_not_null(cut, "a developed estate off the road offers Build road")
	assert_false(cut.disabled, "an idle Engineer can take the order")
	assert_true(
		cut.tooltip_text.contains("last road tile"),
		cut.tooltip_text
	)
	assert_null(_road_button(LINKED_TILE), "an estate beside the road offers none")


## No crew, no order: the control stays legible with the reason a tap would
## return, so the dossier never offers what the rules refuse (REQ-P2-03).
func test_build_road_waits_for_an_engineer() -> void:
	_setup_province_panel()
	_show()
	var cut := _road_button(OFF_ROAD_TILE)
	assert_not_null(cut, "the estate still names the gap")
	assert_true(cut.disabled, "no idle Engineer, so the control is disabled")
	assert_true(cut.tooltip_text.contains("Engineer"), cut.tooltip_text)


## The control is an intent, not a rule: a press carries the estate's tile out
## as "road:<x>,<y>" for the map screen to dispatch.
func test_build_road_emits_the_estates_tile() -> void:
	_setup_province_panel()
	_units = [Fixture.unit("engineer", Vector2i(0, 2))]
	_show()
	var actions: Array[String] = []
	_province_panel_panel.action_pressed.connect(
		func(action: String) -> void: actions.append(action)
	)
	var cut := _road_button(OFF_ROAD_TILE)
	assert_not_null(cut, "the row carries the order")
	cut.pressed.emit()
	assert_eq(actions.size(), 1, "one press, one intent")
	assert_eq(actions[0], "road:1,1")


## The Build road control printed on one estate's line, or null when the estate
## needs no road.
func _road_button(tile: Vector2i) -> Button:
	var block: ProvinceResources = _province_panel_panel._resources
	var rows: Array[Dictionary] = block.lines()
	for i in rows.size():
		if rows[i]["tile"] != tile:
			continue
		var line: Node = block._body.get_child(i)
		for node: Node in line.find_children("*", "Button", true, false):
			var button := node as Button
			if button != null and button.text == ProvinceResources.ROAD:
				return button
	return null


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

## The gift's sum is the crown's to choose: the published £1,000 steps, the
## purse's own ceiling, and one press that files the sum it shows (wiki:
## diplomacy § Amount parameters; DR-20261118-16; REQ-P2-02, REQ-P5-02).
func test_the_court_steps_the_gift_before_it_sends() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(1)
	var seen: Array[Array] = []
	panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			seen.append([kind, target, arg])
	)
	var press: Button = _find_button(panel._detail, "Grant Aid")
	assert_not_null(press)
	assert_eq(press.text, "Grant Aid · £1,000")
	assert_false(press.disabled, "an auto-embassy and a purse that covers the floor")
	assert_true(
		_has_text(panel._detail, "The regard a gift earns is fixed"),
		"the sheet says what the sum does and does not buy"
	)
	var up: Button = _find_button(panel._detail, "+")
	assert_not_null(up)
	assert_false(up.disabled)
	up.pressed.emit()
	assert_eq(_find_button(panel._detail, "Grant Aid").text, "Grant Aid · £2,000")
	assert_true(_find_button(panel._detail, "+").disabled, "the 2,500 purse covers no step further")
	_find_button(panel._detail, "Grant Aid").pressed.emit()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], "grant_aid")
	assert_eq(seen[0][1], 1)
	assert_eq(seen[0][2], "2000", "one order carries the sum the press shows")

## A stepped sum is the pair's, not the panel's: opening another court starts
## that court's gift at the floor again.
func test_the_stepped_gift_belongs_to_the_court_it_was_stepped_for() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(1)
	_find_button(panel._detail, "+").pressed.emit()
	assert_eq(panel._detail.gift_amount, 2000)
	panel.select_faction(6)
	assert_eq(panel._detail.gift_amount, DiplomacyCatalog.GRANT_AID_STEP)
	assert_eq(_find_button(panel._detail, "Grant Aid").text, "Grant Aid · £1,000")

## A purse that no longer covers the sum the crown had stepped to reads the
## validator's reason under the dead press, and the step falls back to the floor.
func test_a_gift_the_purse_cannot_cover_reads_its_reason() -> void:
	_setup_diplomacy_panel()
	panel.select_faction(1)
	_find_button(panel._detail, "+").pressed.emit()
	panel.refresh(state, null, 0, 500)
	var press: Button = _find_button(panel._detail, "Grant Aid")
	assert_eq(press.text, "Grant Aid · £1,000")
	assert_true(press.disabled)
	assert_true(_has_text(panel._detail, "The treasury cannot cover that aid."))

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
	# The alliance rides on the pact (wiki: diplomacy § Alliances; issue #750).
	state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
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
	state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
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
	assert_true(
		_has_text(panel._detail, "no deal clears between them"),
		"and names the barred deal, not only the rate"
	)
	assert_true(_has_text(panel._list, "Boycott"), "the row carries it too")
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "Boycotted by England"), "and the victim reads it")
	assert_true(
		_has_text(panel._detail, "no deal of ours clears with its colonies"),
		"the victim is told its colony deals are barred"
	)

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
			"line": "Light infantry · FPN 0 · FPM 3 · RNG 1 · DEF 3 · MVR 3 · 3 strength · 3 food",
		},
		{
			"type_id": "grenadiers",
			"name": "Grenadiers",
			"ok": false,
			"cost_text": "",
			"reason": "Need Organised Regiments",
			"line": "Heavy infantry · FPN 10 · FPM 8 · RNG 5 · DEF 5 · MVR 4 · 18 strength · 3 food",
		},
	]
	var heard: Array[String] = []
	panel._muster_box.action_pressed.connect(func(action: String) -> void: heard.append(action))

	var muster_opening := ArmyDossierOpening.of(army, true)
	muster_opening.muster = muster
	panel.refresh(model, muster_opening)
	panel.set_muster_open(true)

	assert_eq(
		panel._muster_box.get_child_count(),
		3,
		"two rows and the one press under them"
	)
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
	# The regiment's own numbers print under the price, on the sheet (DR-20261118-01).
	assert_eq(
		(panel._muster_box.get_child(0).get_child(2) as Label).text,
		String(muster[0]["line"])
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
	# A type the crown cannot raise yet keeps its line: the study is planned on it.
	assert_eq(
		(panel._muster_box.get_child(1).get_child(2) as Label).text,
		String(muster[1]["line"])
	)
	panel.free()


## The yard's foot files every ready row in one confirmed press, and its face
## names the count before the stores are spent (REQ-P5-04, REQ-P5-05;
## DR-20261118-07).
func test_the_army_muster_block_files_every_ready_row_in_one_press() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(22, 0, 1, ["guards"], true)
	var muster: Array[Dictionary] = [
		{
			"type_id": "peasant_levies",
			"name": "Peasant Levies",
			"ok": true,
			"batch_ready": true,
			"cost_text": "2,000 cash · 1 fabric",
			"reason": "",
			"line": "Light infantry · 3 strength",
		},
		{
			"type_id": "pikemen",
			"name": "Pikemen",
			"ok": true,
			"batch_ready": true,
			"cost_text": "4,000 cash · 1 fabric",
			"reason": "",
			"line": "Regular infantry · 5 strength",
		},
		{
			"type_id": "grenadiers",
			"name": "Grenadiers",
			"ok": false,
			"batch_ready": false,
			"cost_text": "",
			"reason": "Need Organised Regiments",
			"line": "Heavy infantry · 18 strength",
		},
	]
	var heard: Array[String] = []
	panel._muster_box.action_pressed.connect(func(action: String) -> void: heard.append(action))

	var muster_opening := ArmyDossierOpening.of(army, true)
	muster_opening.muster = muster
	panel.refresh(model, muster_opening)
	panel.set_muster_open(true)

	var press: RaiseBatchPress = panel._muster_box._batch
	assert_not_null(press, "the drill yard carries the one press")
	assert_true(press.visible, "the press stands when the yard holds a ready row")
	assert_eq(press.text, "Muster all ready (2)", "the press names the count it would file")
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap only arms")
	assert_eq(press.text, "Confirm — muster 2 regiments", "the second tap is named")
	press.pressed.emit()
	assert_false(press.is_armed(), "the press forgets the arm once it files")
	assert_eq(heard, ["recruit_all"], "one intent for the whole line")

	# No row is ready now (every order waits), so the press stands down.
	for row: Dictionary in muster:
		row["batch_ready"] = false
	var muster_opening2 := ArmyDossierOpening.of(army, true)
	muster_opening2.muster = muster
	panel.refresh(model, muster_opening2)
	assert_false(press.visible, "a yard with nothing ready carries no press")
	panel.free()


## A redraw re-reads the yard's own ledger, so the arm the player gave the sheet
## is spent with it: a count that falls under an armed press must not leave a
## one-tap confirm loaded against a line the face no longer names (REQ-P5-04).
func test_a_redrawn_muster_sheet_forgets_the_batch_arm() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(22, 0, 1, ["guards"], true)
	var muster: Array[Dictionary] = [
		{
			"type_id": "peasant_levies",
			"name": "Peasant Levies",
			"ok": true,
			"batch_ready": true,
			"cost_text": "2,000 cash · 1 fabric",
			"reason": "",
			"line": "Light infantry · 3 strength",
		},
		{
			"type_id": "pikemen",
			"name": "Pikemen",
			"ok": true,
			"batch_ready": true,
			"cost_text": "4,000 cash · 1 fabric",
			"reason": "",
			"line": "Regular infantry · 5 strength",
		},
	]
	var muster_opening := ArmyDossierOpening.of(army, true)
	muster_opening.muster = muster
	panel.refresh(model, muster_opening)
	panel.set_muster_open(true)
	var press: RaiseBatchPress = panel._muster_box._batch
	assert_eq(press.text, "Muster all ready (2)", "the sheet names its line")
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap arms")

	# One row's own Muster goes in, and the sheet is redrawn one step shorter.
	muster[0]["batch_ready"] = false
	var muster_opening2 := ArmyDossierOpening.of(army, true)
	muster_opening2.muster = muster
	panel.refresh(model, muster_opening2)

	assert_false(press.is_armed(), "the redraw spends the arm the player gave")
	assert_eq(press.text, "Muster all ready (1)", "the face names the line it now stands for")
	panel.free()


## The press's armed face names the line it will file, not the view it stands in:
## five ready towns over one idle Builder read `Confirm — raise 1 of 5 towns`, so
## one tap carries one pair of numbers (REQ-P5-05; DR-20261118-21). A line that
## carries nothing arms nothing, and a sheet that read no plan keeps its view.
func test_the_armed_press_names_the_line_it_will_file() -> void:
	var press := RaiseBatchPress.new()
	add_child(press)
	press.set_ready(5, "towns", 1)
	assert_true(press.visible, "a view with ready steps carries the press")
	assert_false(press.disabled, "and a line a crown can pay for enables it")
	assert_eq(press.text, "Raise all ready (5)", "the unarmed face names the view")
	assert_eq(press.carries(), 1, "the line carries one of the five")
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap only arms")
	assert_eq(press.text, "Confirm — raise 1 of 5 towns", "the confirm names the line")
	press.pressed.emit()
	assert_false(press.is_armed(), "the second tap files")

	press.set_ready(5, "towns", 0)
	assert_true(press.disabled, "a line that carries nothing stands the press down")
	press.arm()
	assert_false(press.is_armed(), "and a press with nothing to file cannot arm")

	press.set_ready(5, "towns")
	assert_false(press.disabled, "a sheet that read no plan keeps its published face")
	press.pressed.emit()
	assert_eq(press.text, "Confirm — raise 5 towns", "and files the view it names")
	press.free()


## The arm guard every destructive press shares: one key, one window, and a
## second tap that only spends the key the first tap armed (DR-20261109-01).
func test_the_arm_guard_asks_once_per_key() -> void:
	var guard := ArmGuard.new()
	add_child(guard)

	guard.arm("colours")

	assert_true(guard.holds("colours"), "the first tap arms the key")
	assert_eq(guard.key(), "colours", "and the guard names what it holds")
	assert_false(guard.spend("hulls"), "a tap on another order asks first")
	assert_true(guard.holds("colours"), "and leaves the first arm standing")

	assert_true(guard.spend("colours"), "the second tap spends the arm")
	assert_eq(guard.key(), "", "a spent arm forgets its key")
	assert_false(guard.spend("colours"), "and cannot be spent twice")
	guard.free()


## An arm the crown never confirms runs out on its own, and the owner hears about
## it so the press prints its resting face again (DR-20261109-01).
func test_the_arm_guard_window_runs_out_on_its_own() -> void:
	var guard := ArmGuard.new()
	add_child(guard)
	var rung: Array[bool] = []
	guard.expired.connect(func() -> void: rung.append(true))

	guard.arm("colours", 0.05)
	await get_tree().create_timer(0.15).timeout

	assert_eq(guard.key(), "", "the window forgets the first tap")
	assert_eq(rung, [true] as Array[bool], "and tells the owner to repaint")
	guard.free()


## A guard built outside the tree (a suite's own sheet) still asks once: it keeps
## the arm and takes no clock, so no case has to wait one out.
func test_a_guard_outside_the_tree_keeps_the_arm_and_takes_no_clock() -> void:
	var guard := ArmGuard.new()

	guard.arm("colours")

	assert_true(guard.holds("colours"), "a loose sheet still asks once")
	assert_true(guard.is_stopped(), "and ticks no clock of its own")
	guard.clear()
	assert_false(guard.holds("colours"), "and clear stands the arm down")
	guard.free()


## The roster's dismissal window outlives the repaint its own first tap causes:
## the clock is not a row, so the confirm is still running when the row comes
## back armed (wiki: military-armies § Dismissing regiments; DR-20261109-01).
func test_a_roster_dismissal_keeps_its_window_across_the_repaint() -> void:
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards", "pikemen"], false)
	var panel := ArmyPanel.new()
	add_child(panel)
	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var entry: VBoxContainer = panel._roster.get_child(0)
	var press: Button = (entry.get_child(1) as HBoxContainer).get_child(1) as Button
	press.pressed.emit()

	var guard: ArmGuard = panel._roster._arm
	assert_true(guard.holds(army.regiments[0]), "the first tap arms the row's key")
	assert_true(guard.is_inside_tree(), "the repaint keeps the row's clock")
	assert_false(guard.is_stopped(), "so the confirm window is still running")
	panel.free()


## A walk that carries nothing prints the rules' own refusal, in the sheet's own
## words: the disabled press above it sends the reader to that sentence rather
## than leaving a dead tap with no reason (REQ-P5-05; DR-20261118-21).
func test_a_line_that_carries_nothing_names_the_wait() -> void:
	var towns: Array[Dictionary] = [{"cost": {"lumber": 4}, "region": 0}]
	var reading: Dictionary = RaiseLine.plan(towns, {"lumber": 0}, 1, "Builder")
	assert_eq(int(reading["filed"]), 0, "the stores carry none of it")
	var line: String = RaiseLine.sheet_line(reading)
	assert_true(line.begins_with("Nothing in this view can be ordered — 1 waits: "), line)
	assert_true(line.ends_with("."), "the rules' sentence keeps its stop: %s" % line)

	var yard: Dictionary = RaiseBatchSum.blank()
	yard["count"] = 3
	yard["filed"] = 0
	yard["refusal"] = "The yard needs a free peasant"
	assert_eq(
		RaiseBatchSum.sheet_line(yard),
		"Nothing in this yard can be ordered — 3 wait: The yard needs a free peasant."
	)
	assert_eq(RaiseBatchSum.carries(yard), 0, "and the press would carry nothing")
	assert_eq(
		RaiseBatchSum.carries(RaiseBatchSum.blank()), -1, "an unread plan keeps the view"
	)


## The press and the sheet read one walk: whatever `plan` prices, `file` lays
## down in the same order, for the same spend, so a receipt can never name a price
## the crown did not read (REQ-P2-03, REQ-P5-04; DR-20261118-11).
func test_the_press_files_exactly_what_the_sheet_priced() -> void:
	var rows: Array[Dictionary] = [
		{"type_id": "sloop", "batch_ready": true},
		{"type_id": "fluyte", "batch_ready": true},
	]
	var purse: int = 100
	var stock: Dictionary = {"lumber": 5}
	var price := func(_type_id: String) -> int: return 40
	var inputs := func(_type_id: String) -> Dictionary: return {"lumber": 2}
	var gate := func(
		_type_id: String, gold: int, left: Dictionary, _filed: int
	) -> String:
		if gold < 40:
			return "Insufficient treasury"
		if int(left.get("lumber", 0)) < 2:
			return "Insufficient materials"
		return ""

	var plan: Dictionary = RaiseBatchSum.plan(rows, purse, stock, price, inputs, gate)
	var written: Array[String] = []
	var receipt: Dictionary = RaiseBatchSum.file(
		["sloop", "fluyte"],
		purse,
		stock,
		price,
		inputs,
		gate,
		func(type_id: String) -> void: written.append(type_id)
	)

	assert_eq(written.size(), 2, "the press lays down the whole line")
	assert_eq(written[0], "sloop", "in the yard's own order")
	assert_eq(written[1], "fluyte", "and never out of it")
	for key: String in ["filed", "ducats", "materials", "workers", "refusal"]:
		assert_eq(receipt[key], plan[key], "%s: the press and the line read one walk" % key)
	assert_eq(int(receipt["purse_after"]), int(plan["purse_after"]), "one purse")
	assert_eq(int(stock.get("lumber", 0)), 5, "a read walk leaves the stores untouched")


## A yard whose own gate forbids any order still answers in the press's shape, so
## the sheet never guards a receipt key of its own (REQ-P3-01).
func test_a_blocked_yard_answers_in_the_press_shape() -> void:
	var receipt: Dictionary = RaiseBatchSum.blocked(3, "Launch hulls at your capital port.")
	assert_eq(int(receipt["total"]), 3, "the view the press stood in")
	assert_eq(int(receipt["filed"]), 0, "nothing filed")
	assert_eq(RaiseBatchSum.carries(receipt), 0, "and the press carries nothing")
	assert_eq(
		RaiseBatchSum.sheet_line(receipt),
		"Nothing in this yard can be ordered — 3 wait: Launch hulls at your capital port."
	)


## The drill yard's foot names what the whole line costs before it is pressed: the
## plan its rows carry, printed once under them and re-read on every redraw
## (REQ-P5-06, REQ-P1-07; DR-20261118-11).
func test_the_muster_block_prints_the_lines_sum_once() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(23, 0, 1, ["guards"], true)
	var plan: Dictionary = {
		"count": 2,
		"filed": 2,
		"ducats": 6000,
		"materials": {"fabric": 2},
		"workers": 2,
		"purse": 20000,
		"purse_after": 14000,
		"refusal": "",
	}
	var muster: Array[Dictionary] = []
	for type_id: String in ["peasant_levies", "pikemen"]:
		muster.append({
			"type_id": type_id,
			"name": type_id,
			"ok": true,
			"batch_ready": true,
			"cost_text": "3,000 ducats · 1 Fabric · 1 worker",
			"reason": "",
			"line": "Light infantry · 3 strength",
			"batch": plan,
		})

	var muster_opening := ArmyDossierOpening.of(army, true)
	muster_opening.muster = muster
	panel.refresh(model, muster_opening)
	panel.set_muster_open(true)

	assert_eq(
		_sum_line_count(panel._muster_box),
		1,
		"the sheet prints one sum under its rows"
	)

	# A redraw re-reads the one label instead of stacking a second copy of it.
	var muster_opening2 := ArmyDossierOpening.of(army, true)
	muster_opening2.muster = muster
	panel.refresh(model, muster_opening2)
	assert_eq(_sum_line_count(panel._muster_box), 1, "one sum line however often")
	panel.free()


## How many sum lines the block prints, so a redraw can be told from a stack and
## a hidden label cannot pass for a printed one.
func _sum_line_count(box: VBoxContainer) -> int:
	var found: int = 0
	for child: Node in box.get_children():
		var label := child as Label
		if label != null and label.visible and label.text.contains("the purse keeps"):
			found += 1
	return found


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

	panel.refresh(model, ArmyDossierOpening.of(army, true))

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

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	assert_true(String(panel._location.text).contains("Aboard"), panel._location.text)
	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq(
		(row.get_child(0) as HBoxContainer).get_child_count(),
		2,
		"medallion and name only while aboard"
	)
	panel.free()


# --- ledger_frame (the docked ledgers' one chrome) ---

func _ledger_frames() -> Array[LedgerFrame]:
	var frames: Array[LedgerFrame] = [
		EconomyPanel.new(), ResearchPanel.new(), DiplomacyPanel.new()
	]
	for frame: LedgerFrame in frames:
		add_child(frame)
	return frames


func _free_ledger_frames(frames: Array[LedgerFrame]) -> void:
	for frame: LedgerFrame in frames:
		if is_instance_valid(frame):
			frame.free()


## The economy, college and court ledgers draw one sheet: the same padding, the
## same masthead and the same Close door, so a chrome fix lands in all three
## (REQ-P3-01).
func test_every_ledger_draws_the_same_sheet() -> void:
	var frames: Array[LedgerFrame] = _ledger_frames()
	for frame: LedgerFrame in frames:
		var sheet: StyleBoxFlat = frame.get_theme_stylebox("panel") as StyleBoxFlat
		assert_not_null(sheet, "%s paints its own sheet" % frame.title_text)
		assert_almost_eq(sheet.content_margin_left, LedgerFrame.PADDING.x, 0.01)
		assert_almost_eq(sheet.content_margin_bottom, LedgerFrame.PADDING.w, 0.01)
		assert_eq(frame._title.text, frame.title_text, "the masthead names the ledger")
		assert_eq(
			frame._title.get_theme_font_size("font_size"), LedgerFrame.TITLE_PIXELS
		)
		assert_not_null(frame._close, "every ledger has a door")
	_free_ledger_frames(frames)


## A phone takes the same two bites out of every ledger: the smaller padding,
## the smaller masthead and a thumb-sized door (REQ-P1-07, REQ-P5-07).
func test_a_phone_ledger_shrinks_its_chrome() -> void:
	var frames: Array[LedgerFrame] = _ledger_frames()
	for frame: LedgerFrame in frames:
		frame.set_compact(true)
		var sheet: StyleBoxFlat = frame.get_theme_stylebox("panel") as StyleBoxFlat
		assert_almost_eq(sheet.content_margin_left, LedgerFrame.PADDING_COMPACT.x, 0.01)
		assert_eq(
			frame._title.get_theme_font_size("font_size"),
			LedgerFrame.TITLE_PIXELS_COMPACT
		)
		assert_eq(frame._close.custom_minimum_size, CloseSeal.SIZE)
		if frame._hint != null:
			assert_false(frame._hint.visible, "a phone keeps the room for the list")
	for frame: LedgerFrame in frames:
		frame.set_compact(false)
		var sheet: StyleBoxFlat = frame.get_theme_stylebox("panel") as StyleBoxFlat
		assert_almost_eq(sheet.content_margin_left, LedgerFrame.PADDING.x, 0.01)
		assert_eq(frame._title.get_theme_font_size("font_size"), LedgerFrame.TITLE_PIXELS)
		assert_eq(frame._close.custom_minimum_size, CloseSeal.SIZE)
		if frame._hint != null:
			assert_true(frame._hint.visible, "the standing line returns")
	_free_ledger_frames(frames)


## The court's medallion is chrome too: it rides the same phone profile.
func test_the_court_crest_rides_the_phone_profile() -> void:
	var court := DiplomacyPanel.new()
	add_child(court)
	var wide := Vector2(LedgerFrame.CREST_PIXELS, LedgerFrame.CREST_PIXELS)
	assert_eq(court._crest.custom_minimum_size, wide)
	court.set_compact(true)
	assert_eq(
		court._crest.custom_minimum_size,
		Vector2(LedgerFrame.CREST_PIXELS_COMPACT, LedgerFrame.CREST_PIXELS_COMPACT)
	)
	court.free()


## One door per ledger, one signal: a button press anywhere reports through the
## frame the HUD already listens to (REQ-P3-02).
func test_every_close_door_emits_the_one_signal() -> void:
	var frames: Array[LedgerFrame] = _ledger_frames()
	var heard: Array[int] = [0]
	for frame: LedgerFrame in frames:
		frame.close_pressed.connect(func() -> void: heard[0] += 1)
		frame._close.pressed.emit()
	assert_eq(heard[0], frames.size(), "every ledger's door reports through the frame")
	_free_ledger_frames(frames)


## The tabbed ledgers share the strip: same name, same scroll wrapper and the
## same body gap, so a page added to either reads the same (REQ-P3-01). The
## college's whole tree is a full-screen chart of its own, so its strip carries
## only the two lists (DR-20261115-15).
func test_both_tabbed_ledgers_share_the_strip() -> void:
	var economy := EconomyPanel.new()
	add_child(economy)
	var college := ResearchPanel.new()
	add_child(college)
	assert_eq(economy._tabs.get_tab_count(), 3)
	assert_eq(college._tabs.get_tab_count(), 2)
	for tabs: TabContainer in [economy._tabs, college._tabs]:
		assert_eq(tabs.name, "Tabs")
		for page: Node in tabs.get_children():
			var scroll := page as ScrollContainer
			assert_not_null(scroll, "each page is a scroll")
			assert_true(scroll.get_child(0) is VBoxContainer, "each page holds a column")
	for title: String in [
		EconomyPanel.TAB_PRODUCTION, EconomyPanel.TAB_MARKET, EconomyPanel.TAB_WORKERS
	]:
		assert_not_null(economy.page_body(title), title)
	economy.free()
	college.free()

# --- from test_road_works_rules ---
# The crown's road works (wiki: capital-and-connectivity § Connectivity,
# civilian-units § Work Order Summary): the route that links a cut-off estate
# and the Engineer dispatch the province dossier's Build road control makes
# (issue #671). The dossier's own chart and network are already set up above.


func _roads_resolved() -> Dictionary:
	return LandConnectivity.resolve(_model, _works, 0, Fixture.BARE_TILE)


func _roads_engineer(tile: Vector2i = Vector2i(0, 2)) -> CivilianState:
	var unit: CivilianState = Fixture.unit("engineer", tile)
	_roads_units.append(unit)
	return unit


## The route is the tiles between the crown network and the estate: the network
## tile is already roaded and the estate extracts as soon as it stands beside
## the road, so neither is laid.
func test_the_route_lays_only_the_tiles_between_the_network_and_the_estate() -> void:
	_setup_road_works()
	var route: Array[Vector2i] = RoadWorks.route(
		_model, 0, _roads_resolved()["network"], OFF_ROAD_TILE
	)
	assert_eq(route.size(), 1, "one road tile links the cut-off estate")
	var step: Vector2i = route[0]
	assert_true(
		absi(step.x - Fixture.BARE_TILE.x) + absi(step.y - Fixture.BARE_TILE.y) == 1,
		"the first tile is the one beside the crown network"
	)
	assert_false(route.has(OFF_ROAD_TILE), "the estate tile itself is never laid")


## A tile the crown does not hold has no owned-land route at all.
func test_a_foreign_tile_has_no_route() -> void:
	_setup_road_works()
	var route: Array[Vector2i] = RoadWorks.route(
		_model, 0, _roads_resolved()["network"], Fixture.RIVAL_GRAIN_TILE
	)
	assert_true(route.is_empty(), "the route never crosses another crown's land")


func test_an_empty_network_has_no_route() -> void:
	_setup_road_works()
	var route: Array[Vector2i] = RoadWorks.route(_model, 0, {}, OFF_ROAD_TILE)
	assert_true(route.is_empty(), "no crown network, nothing to extend")


func test_a_missing_map_reads_no_plan() -> void:
	_setup_road_works()
	var plan: Dictionary = RoadWorks.plan(
		null, _works, _roads_units, 0, Fixture.BARE_TILE, OFF_ROAD_TILE
	)
	assert_false(bool(plan["needed"]), "nothing to read without a chart")
	plan = RoadWorks.plan(
		_model, _works, _roads_units, -1, Fixture.BARE_TILE, OFF_ROAD_TILE
	)
	assert_false(bool(plan["needed"]), "no crown, no estate of ours")


## The plan the dossier reads off its own chart.
func test_a_cut_off_estate_needs_a_road() -> void:
	_setup_road_works()
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, OFF_ROAD_TILE, _roads_resolved()
	)
	assert_true(bool(plan["needed"]), "the estate is developed and cut off")
	assert_eq(int(plan["gap"]), 1, "one road tile still to lay")
	assert_false(bool(plan["engineer"]), "no crew musters yet")
	assert_true(
		String(plan["reason"]).contains("Engineer"),
		"the reason names the missing crew: %s" % plan["reason"]
	)


func test_a_linked_estate_needs_no_road() -> void:
	_setup_road_works()
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, LINKED_TILE, _roads_resolved()
	)
	assert_false(bool(plan["needed"]), "an estate beside the road already extracts")


## A bare tile is the Build control's business: a road under it would still
## yield nothing (wiki: extraction-and-improvements).
func test_a_bare_estate_needs_no_road() -> void:
	_setup_road_works()
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, Fixture.BARE_TILE,
		_roads_resolved()
	)
	assert_false(bool(plan["needed"]), "an unimproved tile has no yield to link")


func test_a_foreign_estate_needs_no_road() -> void:
	_setup_road_works()
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, Fixture.RIVAL_GRAIN_TILE,
		_roads_resolved()
	)
	assert_false(bool(plan["needed"]), "another crown's estate is not ours to road")


## The dossier resolves the crown network once and hands it in, so a province of
## many estates costs one BFS (REQ-P4-01). The reading must not change.
func test_the_plan_reads_the_network_the_dossier_handed_in() -> void:
	_setup_road_works()
	var handed: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, OFF_ROAD_TILE, _roads_resolved()
	)
	var fresh: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, OFF_ROAD_TILE
	)
	assert_eq(int(handed["gap"]), int(fresh["gap"]), "same gap either way")
	assert_eq(
		(handed["route"] as Array).size(), (fresh["route"] as Array).size(),
		"same route either way"
	)


## The dispatch the Build road control issues.
func test_dispatch_refuses_without_an_engineer() -> void:
	_setup_road_works()
	var result: Dictionary = RoadWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, Fixture.BARE_TILE,
		OFF_ROAD_TILE
	)
	assert_false(bool(result["ok"]), "no crew, no order")
	assert_true(
		String(result["message"]).contains("Engineer"),
		"the refusal names the crew: %s" % result["message"]
	)


func test_dispatch_puts_the_engineer_on_the_first_road_tile() -> void:
	_setup_road_works()
	var engineer: CivilianState = _roads_engineer()
	var result: Dictionary = RoadWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, Fixture.BARE_TILE,
		OFF_ROAD_TILE
	)
	assert_true(bool(result["ok"]), String(result["message"]))
	assert_true(engineer.is_working(), "the Engineer takes the order")
	assert_eq(engineer.work_action(), "build_road")
	assert_true(
		engineer.work_tile() != OFF_ROAD_TILE,
		"the crew roads the tile beside the estate, not the estate itself"
	)
	assert_true(
		String(result["message"]).contains("last road tile"),
		"a one-tile gap reads as the last tile: %s" % result["message"]
	)


## The order is the rules' own: the road lands on completion and the estate
## starts reaching the crown (wiki: civilian-units § Work Types).
func test_the_road_links_the_estate_when_the_work_completes() -> void:
	_setup_road_works()
	_roads_engineer()
	RoadWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, Fixture.BARE_TILE,
		OFF_ROAD_TILE
	)
	CivilianWork.resolve_turn(_model, _roads_units, _works, _roads_view)
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, OFF_ROAD_TILE
	)
	assert_false(bool(plan["needed"]), "the estate reaches the crown now")
	var tiles: Dictionary = _roads_resolved()["tiles"]
	assert_true(
		tiles.has(_model.index_of(OFF_ROAD_TILE.x, OFF_ROAD_TILE.y)),
		"the estate is on the crown's network"
	)


## A second press on a linked estate is refused, never a silent no-op.
func test_dispatch_refuses_an_estate_that_already_reaches_the_crown() -> void:
	_setup_road_works()
	_roads_engineer()
	var result: Dictionary = RoadWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, Fixture.BARE_TILE,
		LINKED_TILE
	)
	assert_false(bool(result["ok"]))
	assert_true(
		String(result["message"]).contains("already reaches"),
		String(result["message"])
	)


## A gap of several tiles reads as the first of them, so the court knows the
## link is a road works, not one order (issue #671).
func test_a_multi_tile_gap_reads_as_the_first_of_many() -> void:
	_setup_road_works()
	var far: Vector2i = Vector2i(2, 3)
	_works.set_improvement(_model, far, 1)
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _roads_units, 0, Fixture.BARE_TILE, far, _roads_resolved()
	)
	assert_true(bool(plan["needed"]), "the far estate is cut off")
	assert_gt(int(plan["gap"]), 1, "more than one road tile to lay")
	_roads_engineer()
	var result: Dictionary = RoadWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, Fixture.BARE_TILE, far
	)
	assert_true(bool(result["ok"]), String(result["message"]))
	assert_true(
		String(result["message"]).contains("first of"),
		String(result["message"])
	)

# --- rail works (DR-20261117-10) ---
# The crown's rail works (wiki: civilian-units § Rail Builder work): the road
# tiles that can still go rail and the Rail Builder dispatch the province
# dossier's Lay railroad control makes. The pick names a road ahead of the crew,
# so the dossier carries the press that follows it (REQ-P5-06).

const RAIL_TILE: Vector2i = Vector2i(1, 0)
const STEAM: Dictionary = {"early_steam_engine": true}


## The road-works chart with one roaded estate and the steam study read: the
## ground a railroad can still take.
func _setup_rail_works() -> void:
	_setup_road_works()
	_works.set_transport(_model, RAIL_TILE, LandWorks.TRANSPORT_ROAD)


func _rail_builder(tile: Vector2i = Vector2i(0, 2)) -> CivilianState:
	var unit: CivilianState = Fixture.unit("rail_builder", tile)
	_roads_units.append(unit)
	return unit


## A road tile the crown has studied for is the one ground a railroad can take.
func test_a_road_tile_can_go_rail() -> void:
	_setup_rail_works()
	var plan: Dictionary = RailWorks.plan(
		_model, _works, _roads_units, 0, RAIL_TILE, STEAM
	)
	assert_true(bool(plan["needed"]), "a road tile can still go rail")
	assert_false(bool(plan["rail_builder"]), "no crew musters yet")
	assert_true(
		String(plan["reason"]).contains("Rail Builder"),
		"the reason names the missing crew: %s" % plan["reason"]
	)


## Railroads upgrade an existing road: bare ground, a finished railroad and a
## tile the crown does not hold are none of the block's business.
func test_only_a_crown_road_without_a_railroad_can_go_rail() -> void:
	_setup_rail_works()
	assert_false(
		bool(RailWorks.plan(_model, _works, _roads_units, 0, Fixture.BARE_TILE, STEAM)["needed"]),
		"bare ground carries no road to upgrade"
	)
	_works.set_transport(_model, RAIL_TILE, LandWorks.TRANSPORT_RAIL)
	assert_false(
		bool(RailWorks.plan(_model, _works, _roads_units, 0, RAIL_TILE, STEAM)["needed"]),
		"a finished railroad is not offered again"
	)
	_works.set_transport(_model, RAIL_TILE, LandWorks.TRANSPORT_ROAD)
	_works.set_transport(_model, Fixture.RIVAL_GRAIN_TILE, LandWorks.TRANSPORT_ROAD)
	assert_false(
		bool(RailWorks.plan(
			_model, _works, _roads_units, 0, Fixture.RIVAL_GRAIN_TILE, STEAM
		)["needed"]),
		"another crown's road is not ours to rail"
	)


## The study is the gate the crew's own order reads: no steam, no press.
func test_rail_waits_for_the_steam_study() -> void:
	_setup_rail_works()
	assert_false(
		bool(RailWorks.plan(_model, _works, _roads_units, 0, RAIL_TILE, {})["needed"]),
		"without Early Steam Engine the tile is not offered"
	)


## A crew already on the tile has the order in hand: a second press would only
## spend a second Rail Builder's materials on the same ground.
func test_a_crew_already_on_the_tile_takes_no_second_press() -> void:
	_setup_rail_works()
	var crew: CivilianState = _rail_builder()
	crew.start_work("build_rail", RAIL_TILE, 2)
	assert_false(
		bool(RailWorks.plan(_model, _works, _roads_units, 0, RAIL_TILE, STEAM)["needed"]),
		"the work is already in hand"
	)


## The block's reading: one row per rail-ready road tile of the province, with
## the estate it serves in the catalog's own words.
func test_the_province_lists_its_rail_ready_roads() -> void:
	_setup_rail_works()
	var rows: Array[Dictionary] = RailWorks.province_plans(
		_model, _works, _roads_units, 0, Fixture.PLAYER_PROVINCE, STEAM
	)
	assert_eq(rows.size(), 1, "one road tile can go rail")
	assert_eq(rows[0]["tile"], RAIL_TILE)
	assert_eq(int(rows[0]["transport"]), LandWorks.TRANSPORT_ROAD)
	assert_eq(
		String(rows[0]["estate"]), "Lumber camp (L2)",
		"the row names the estate the rail would serve"
	)
	assert_true(
		RailWorks.province_plans(
			_model, _works, _roads_units, 0, Fixture.PLAYER_PROVINCE, {}
		).is_empty(),
		"no study, no rows"
	)


## The dispatch the Lay railroad control issues: the nearest idle Rail Builder
## takes the tile and the order is charged at the rules' own price.
func test_dispatch_puts_the_rail_builder_on_the_tile() -> void:
	_setup_rail_works()
	var crew: CivilianState = _rail_builder()
	var lumber_before: int = int(_roads_stock["lumber"])
	var steel_before: int = int(_roads_stock["steel"])
	var result: Dictionary = RailWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, RAIL_TILE, STEAM
	)
	assert_true(bool(result["ok"]), String(result["message"]))
	assert_true(crew.is_working(), "the Rail Builder takes the order")
	assert_eq(crew.work_action(), "build_rail")
	assert_eq(crew.work_tile(), RAIL_TILE, "on the tile the block named")
	assert_eq(int(_roads_stock["lumber"]), lumber_before - 2, "2 lumber")
	assert_eq(int(_roads_stock["steel"]), steel_before - 2, "2 steel")
	assert_true(
		String(result["message"]).contains("railroad"),
		String(result["message"])
	)


func test_dispatch_refuses_without_a_rail_builder() -> void:
	_setup_rail_works()
	var result: Dictionary = RailWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, RAIL_TILE, STEAM
	)
	assert_false(bool(result["ok"]), "no crew, no order")
	assert_true(
		String(result["message"]).contains("Rail Builder"),
		String(result["message"])
	)


## The order is the rules' own: the railroad lands on completion and the tile
## stops being offered (wiki: extraction-and-improvements § Road / Railroad
## Costs).
func test_the_railroad_lands_when_the_work_completes() -> void:
	_setup_rail_works()
	_rail_builder()
	RailWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0, RAIL_TILE, STEAM
	)
	# A railroad takes two turns (wiki: extraction-and-improvements § Railroad
	# Costs), so the tile changes on the second Build/Work pass.
	CivilianWork.resolve_turn(_model, _roads_units, _works, _roads_view)
	CivilianWork.resolve_turn(_model, _roads_units, _works, _roads_view)
	assert_eq(
		_works.transport_at(_model, RAIL_TILE), LandWorks.TRANSPORT_RAIL,
		"the tile carries a railroad now"
	)
	assert_false(
		bool(RailWorks.plan(_model, _works, _roads_units, 0, RAIL_TILE, STEAM)["needed"]),
		"and the block stops offering it"
	)


## The dossier's rail block prints the row and its press travels as one intent
## string, the same way the Build road control's does (REQ-P3-02).
func test_the_rail_block_emits_the_tile_it_names() -> void:
	_setup_province_panel()
	_works.set_transport(_model, RAIL_TILE, LandWorks.TRANSPORT_ROAD)
	_units = [] as Array[CivilianState]
	_units.append(_rail_builder())
	_show(STEAM)
	var block: ProvinceRailBlock = _province_panel_panel._rail
	assert_true(block.visible, "a rail-ready road shows the block")
	assert_eq(block.rows().size(), 1, "one row")
	var actions: Array[String] = []
	_province_panel_panel.action_pressed.connect(
		func(action: String) -> void: actions.append(action)
	)
	var button: Button = _rail_button(block, RAIL_TILE)
	assert_not_null(button, "the row carries the press")
	assert_false(button.disabled, "an idle Rail Builder can take the order")
	button.pressed.emit()
	assert_eq(actions, ["rail:1,0"] as Array[String], "one press, one intent")


## No crew, no order: the control stays legible with the reason a tap would
## return (REQ-P2-03).
func test_the_rail_block_waits_for_a_rail_builder() -> void:
	_setup_province_panel()
	_works.set_transport(_model, RAIL_TILE, LandWorks.TRANSPORT_ROAD)
	_show(STEAM)
	var block: ProvinceRailBlock = _province_panel_panel._rail
	var button: Button = _rail_button(block, RAIL_TILE)
	assert_not_null(button, "the row still names the ground")
	assert_true(button.disabled, "no idle Rail Builder, so the press is disabled")
	assert_true(button.tooltip_text.contains("Rail Builder"), button.tooltip_text)


## A province with nothing to rail says nothing: no heading over no ground.
func test_the_rail_block_hides_when_nothing_can_go_rail() -> void:
	_setup_province_panel()
	_show(STEAM)
	assert_false(_province_panel_panel._rail.visible, "no road, no block")


## The Lay railroad control printed on one row, or null when the tile is not
## offered.
func _rail_button(block: ProvinceRailBlock, tile: Vector2i) -> Button:
	var rows: Array[Dictionary] = block.rows()
	for i in rows.size():
		if rows[i]["tile"] != tile:
			continue
		var line: Node = block._body.get_child(i)
		for node: Node in line.find_children("*", "Button", true, false):
			var button := node as Button
			if button != null and button.text == ProvinceRailBlock.RAIL:
				return button
	return null


## A reading with nothing to read: no chart, no crown, no province.
func test_a_missing_chart_reads_no_rail_plan() -> void:
	_setup_rail_works()
	assert_false(
		bool(RailWorks.plan(null, _works, _roads_units, 0, RAIL_TILE, STEAM)["needed"]),
		"nothing to read without a chart"
	)
	assert_false(
		bool(RailWorks.plan(_model, _works, _roads_units, -1, RAIL_TILE, STEAM)["needed"]),
		"no crown, no road of ours"
	)
	assert_false(
		bool(RailWorks.plan(_model, _works, _roads_units, 0, Vector2i(-1, -1), STEAM)["needed"]),
		"no tile, no plan"
	)
	assert_true(
		RailWorks.province_plans(null, _works, _roads_units, 0, 0, STEAM).is_empty(),
		"no chart, no rows"
	)
	assert_true(
		RailWorks.province_plans(_model, _works, _roads_units, 0, 99, STEAM).is_empty(),
		"no such province, no rows"
	)


## The nearest idle Rail Builder takes the order; ties break on unit id, as the
## estates ledger's Builder dispatch does.
func test_the_nearest_rail_builder_takes_the_order() -> void:
	_setup_rail_works()
	var far: CivilianState = _rail_builder(Vector2i(0, 3))
	var near: CivilianState = _rail_builder(Vector2i(2, 0))
	assert_eq(
		RailWorks.nearest_rail_builder(_roads_units, 0, RAIL_TILE), near,
		"the closer crew is sent"
	)
	far.tile = near.tile
	assert_eq(
		RailWorks.nearest_rail_builder(_roads_units, 0, RAIL_TILE), far,
		"a tie breaks on the lower unit id"
	)
	assert_null(
		RailWorks.nearest_rail_builder(_roads_units, 9, RAIL_TILE),
		"another crown's crews are not ours to send"
	)


## A press the rules refuse says so: ground that cannot take a railroad, and a
## crew the stores cannot pay.
func test_dispatch_refuses_ground_and_stores_it_cannot_take() -> void:
	_setup_rail_works()
	_rail_builder()
	var bare: Dictionary = RailWorks.dispatch(
		_model, _roads_units, _works, _roads_stock, _roads_view, 0,
		Fixture.BARE_TILE, STEAM
	)
	assert_false(bool(bare["ok"]), "bare ground takes no railroad")
	assert_true(
		String(bare["message"]).contains("railroad"), String(bare["message"])
	)
	var empty: Dictionary = {}
	var broke: Dictionary = RailWorks.dispatch(
		_model, _roads_units, _works, empty, _roads_view, 0, RAIL_TILE, STEAM
	)
	assert_false(bool(broke["ok"]), "no stores, no order")
	assert_false(String(broke["message"]).is_empty(), "the refusal is spoken")


## A bare road tile is plain ground on the block: no estate to name, and the
## line still carries its press.
func test_a_bare_road_tile_reads_as_plain_ground() -> void:
	_setup_rail_works()
	var bare: Vector2i = Vector2i(2, 1)
	_works.set_transport(_model, bare, LandWorks.TRANSPORT_IMPROVED_ROAD)
	var rows: Array[Dictionary] = RailWorks.province_plans(
		_model, _works, _roads_units, 0, Fixture.PLAYER_PROVINCE, STEAM
	)
	var found: Dictionary = {}
	for row: Dictionary in rows:
		if row["tile"] == bare:
			found = row
	assert_false(found.is_empty(), "the bare road is offered")
	assert_eq(String(found["estate"]), "", "no estate to name")
	assert_eq(int(found["transport"]), LandWorks.TRANSPORT_IMPROVED_ROAD)
	_setup_province_panel()
	_works.set_transport(_model, bare, LandWorks.TRANSPORT_IMPROVED_ROAD)
	_show(STEAM)
	var block: ProvinceRailBlock = _province_panel_panel._rail
	var button: Button = _rail_button(block, bare)
	assert_not_null(button, "the bare road still carries its press")
	assert_true(button.disabled, "no crew, so the press waits")
	assert_true(button.tooltip_text.contains("Rail Builder"), button.tooltip_text)
	var title: Label = block._body.get_child(0).get_child(0) as Label
	assert_eq(title.text, "Road (2, 1)", "plain ground is named by its tile")

# --- yarn dialogue, plates and espionage ---

## One boot for yarn dialogue, symbol plates and espionage rules. Merged from
## test_dialogue_yarn, test_symbol_plates and test_espionage so coverage pays one
## instrumentation pass instead of three.

const SCRIPT: String = """
// A gate, a set and two nodes: everything the runtime reads, in one program.
title: gate
tags: category:reactive mood:calculating
---
Will you sign? #firm
<<if $score >= 80>>
Warm.
<<elseif $score >= 40>>
Civil.
<<else>>
Cold.
<<endif>>
<<set $seen = true>>
Seen: {$seen} at {$score + 1}.
===

title: signed
tags: category:diplomatic mood:pleased
---
It is signed.
===

title: ask
---
Will you sign?
-> Accept <<jump signed>> #bold
-> Refuse
===
"""


func _program() -> Dictionary:
	return YarnScript.parse(SCRIPT)


## Every beat the runner reads from one node, as plain text; options are listed
## as `-> <text>` so a test can read the whole scene in order.
func _read(source: String, node: String, vars: Dictionary = {}) -> Array[String]:
	var program := YarnScript.parse(source)
	var runner := YarnRunner.new(program, vars)
	var beats: Array[String] = []
	if not runner.start(node):
		return beats
	for _step in 40:
		var beat: Dictionary = runner.advance()
		if String(beat.get("kind", "")) == "line":
			beats.append(String(beat["text"]))
			continue
		if String(beat.get("kind", "")) == "options":
			for option: Variant in beat.get("options", []):
				beats.append("-> %s" % String((option as Dictionary).get("text", "")))
			runner.choose(0)
			continue
		break
	return beats


# --- the parser -------------------------------------------------------------

func test_a_node_reads_its_title_tags_lines_and_options() -> void:
	var program := _program()
	assert_true(bool(program["ok"]), String(program.get("error", "")))
	assert_eq(YarnScript.node_names(program), ["ask", "gate", "signed"] as Array[String])
	var node: Dictionary = program["nodes"]["gate"]
	assert_eq(node["tags"], ["category:reactive", "mood:calculating"] as Array[String])
	var steps: Array = node["steps"]
	assert_eq(String(steps[0]["kind"]), "line")
	assert_eq(String(steps[0]["text"]), "Will you sign?")
	assert_eq(steps[0]["tags"], ["firm"] as Array[String])
	assert_eq(String(steps[1]["kind"]), "if")
	var option_steps: Array = program["nodes"]["ask"]["steps"]
	assert_eq(String(option_steps[1]["kind"]), "options")
	assert_eq((option_steps[1]["options"] as Array).size(), 2, "two options, one group")
	assert_eq(String(option_steps[1]["options"][0]["command"]), "jump signed")
	assert_eq(String(option_steps[1]["options"][1]["command"]), "", "a bare option is silent")


func test_a_body_that_never_ends_is_refused() -> void:
	var broken := "title: gate\n---\nWill you sign?\n"
	var program := YarnScript.parse(broken)
	assert_false(bool(program["ok"]), "a node without === is refused")
	assert_true(String(program["error"]).contains("gate"), String(program["error"]))


func test_an_unclosed_condition_is_refused() -> void:
	var broken := "title: gate\n---\n<<if $x>>\nYes.\n===\n"
	var program := YarnScript.parse(broken)
	assert_false(bool(program["ok"]))
	assert_true(String(program["error"]).contains("endif"), String(program["error"]))


func test_an_unreadable_condition_is_refused() -> void:
	var broken := "title: gate\n---\n<<if $x ???>>\nYes.\n<<endif>>\n===\n"
	assert_false(bool(YarnScript.parse(broken)["ok"]))


func test_an_unknown_command_is_refused() -> void:
	var broken := "title: gate\n---\n<<teleport somewhere>>\n===\n"
	var program := YarnScript.parse(broken)
	assert_false(bool(program["ok"]))
	assert_true(String(program["error"]).contains("teleport"), String(program["error"]))


func test_an_option_without_text_is_refused() -> void:
	var broken := "title: gate\n---\n-> \n===\n"
	assert_false(bool(YarnScript.parse(broken)["ok"]))


func test_a_body_without_a_title_is_refused() -> void:
	assert_false(bool(YarnScript.parse("---\nA line.\n===\n")["ok"]))


func test_the_same_title_twice_is_refused() -> void:
	var twice := "title: gate\n---\nA.\n===\ntitle: gate\n---\nB.\n===\n"
	assert_false(bool(YarnScript.parse(twice)["ok"]))


# --- expressions ------------------------------------------------------------

func test_an_expression_reads_numbers_variables_and_flags() -> void:
	var vars: Dictionary = {"score": 70, "flag": true, "name": "Lisboa"}
	var cases: Dictionary = {
		"$score >= 40 and $flag": true,
		"not $flag or $score < 10": false,
		"($score + 10) * 2 == 160": true,
		"$score % 2 == 0": true,
		"$name == 'Lisboa'": true,
		"$missing": null,
		"$score / 0": 0,
		"not ($score < 40)": true,
	}
	for text: String in cases.keys():
		var ast := YarnExpr.parse(text)
		assert_false(ast.is_empty(), "'%s' parses" % text)
		assert_eq(YarnExpr.evaluate(ast, vars), cases[text], "'%s' reads" % text)


func test_a_malformed_expression_is_refused() -> void:
	for text: String in ["$x ==", "1 +", "and 2", "($x", "unknown_word", "$", "'unclosed"]:
		assert_true(YarnExpr.parse(text).is_empty(), "'%s' is refused" % text)


func test_arithmetic_and_string_joins_read() -> void:
	var vars: Dictionary = {"score": 70, "name": "Lisboa"}
	var cases: Dictionary = {
		"'a' + 'b' == 'ab'": true,
		"-$score == -70": true,
		"$score >= 70 and $score <= 70": true,
		"$score != 71": true,
		"2.5 + 0.5 == 3": true,
		"'12' < 20": true,
		"$score % 4 == 2": true,
		"$name + '!' == 'Lisboa!'": true,
	}
	for text: String in cases.keys():
		var ast := YarnExpr.parse(text)
		assert_false(ast.is_empty(), "'%s' parses" % text)
		assert_eq(YarnExpr.evaluate(ast, vars), cases[text], "'%s' reads" % text)
	assert_true(YarnExpr.truthy("x"), "a non-empty string is true")
	assert_false(YarnExpr.truthy(""), "an empty string is not")
	assert_true(YarnExpr.truthy(1), "a number is true")
	assert_false(YarnExpr.truthy(null), "a missing value is false")


# --- the runner -------------------------------------------------------------

func test_the_runner_speaks_lines_in_order() -> void:
	assert_eq(
		_read(SCRIPT, "signed"), ["It is signed."] as Array[String], "one line, one beat"
	)


func test_a_set_feeds_the_next_line() -> void:
	assert_eq(
		_read(SCRIPT, "gate", {"score": 50}),
		["Will you sign?", "Civil.", "Seen: true at 51."] as Array[String],
		"the set is read back through interpolation"
	)


func test_a_condition_picks_its_branch() -> void:
	assert_eq(_read(SCRIPT, "gate", {"score": 90})[1], "Warm.", "the first branch")
	assert_eq(_read(SCRIPT, "gate", {"score": 40})[1], "Civil.", "the elseif branch")
	assert_eq(_read(SCRIPT, "gate", {"score": 1})[1], "Cold.", "the else branch")
	assert_eq(
		_read(SCRIPT, "gate", {})[1], "Cold.", "a variable a script never set is false"
	)


func test_an_option_group_waits_for_the_choice() -> void:
	assert_eq(
		_read(SCRIPT, "ask"),
		["Will you sign?", "-> Accept", "-> Refuse", "It is signed."] as Array[String],
		"choosing the jump continues in the other node"
	)


func test_an_option_nobody_wrote_is_refused() -> void:
	var runner := YarnRunner.new(_program())
	assert_true(runner.start("ask"))
	assert_eq(String(runner.advance()["kind"]), "line")
	assert_eq(String(runner.advance()["kind"]), "options")
	assert_false(runner.choose(9), "an option nobody wrote is not taken")
	assert_false(runner.at_end(), "the scene waits for a real answer")
	assert_eq(String(runner.advance()["kind"]), "options", "the same options are still on offer")


func test_a_jump_into_a_missing_node_is_reported() -> void:
	var orphan := YarnScript.parse("title: gate\n---\n<<jump nowhere>>\n===\n")
	var runner := YarnRunner.new(orphan)
	assert_true(runner.start("gate"))
	var beat: Dictionary = runner.advance()
	assert_eq(String(beat["kind"]), "error")
	assert_true(String(beat["error"]).contains("nowhere"), String(beat["error"]))


func test_stop_ends_the_scene_without_the_lines_below_it() -> void:
	var stopped := "title: gate\n---\nOne.\n<<stop>>\nTwo.\n===\n"
	assert_eq(_read(stopped, "gate"), ["One."] as Array[String], "the stop is obeyed")


func test_an_unknown_node_cannot_start() -> void:
	assert_false(YarnRunner.new(_program()).start("no_such_node"))


func test_a_declare_fills_an_unset_variable() -> void:
	var declared := "title: gate\n---\n<<declare $x = 2>>\nCount: {$x}.\n===\n"
	assert_eq(_read(declared, "gate"), ["Count: 2."] as Array[String])


## DR-20261113-01: "`<<declare>>` as a default". The game layer sets a script's
## variables before the runner reads it (wiki: dialogue-content-and-yarn
## § Architecture), so a declaration must not overwrite one.
func test_a_declare_keeps_the_value_the_game_set() -> void:
	var declared := (
		"title: gate\n---\n<<declare $court = \"Ribe\">>\n"
		+ "<<declare $court = \"Lisboa\">>\nCourt: {$court}.\n"
		+ "<<set $court = \"Angra\">>\nSet: {$court}.\n===\n"
	)
	assert_eq(
		_read(declared, "gate", {"court": "Cadiz"}),
		["Court: Cadiz.", "Set: Angra."] as Array[String],
		"a declare is a default; only a set writes over the game's value"
	)
	assert_eq(
		_read(declared, "gate"), ["Court: Ribe.", "Set: Angra."] as Array[String],
		"with nothing set, the first default stands and a set still writes"
	)


## DR-20261113-01 § P4: "a jump loop is bounded at 200 beats, so authored content
## can never hang a refresh". A cycle with no line in it never reaches a beat, so
## this call must return rather than spin.
func test_a_jump_loop_that_never_speaks_is_stopped() -> void:
	var looping := "title: gate\n---\n<<jump gate>>\n===\n"
	var runner := YarnRunner.new(YarnScript.parse(looping))
	assert_true(runner.start("gate"))
	var beat: Dictionary = runner.advance()
	assert_eq(String(beat["kind"]), "error", str(beat))
	assert_true(String(beat.get("error", "")).contains("jump"), String(beat.get("error", "")))
	assert_true(runner.at_end(), "the loop is closed, not left to spin")


func test_two_nodes_jumping_to_each_other_are_stopped() -> void:
	var looping := (
		"title: a\n---\n<<jump b>>\n===\ntitle: b\n---\n<<jump a>>\n===\n"
	)
	var runner := YarnRunner.new(YarnScript.parse(looping))
	assert_true(runner.start("a"))
	assert_eq(String(runner.advance()["kind"]), "error", "a mutual loop is bounded too")


## A loop that speaks is bounded by the reader's beats, not by the runner: the
## guard must not cut a long but honest scene short.
func test_a_loop_that_speaks_still_yields_its_lines() -> void:
	var speaking := "title: gate\n---\nThe wheel turns.\n<<jump gate>>\n===\n"
	var runner := YarnRunner.new(YarnScript.parse(speaking))
	assert_true(runner.start("gate"))
	for beat in 3:
		var said: Dictionary = runner.advance()
		assert_eq(String(said["kind"]), "line", "beat %d" % beat)


func test_an_option_can_stop_the_scene() -> void:
	var scene := "title: ask\n---\nSign?\n-> Enough <<stop>>\nUnsigned.\n===\n"
	assert_eq(
		_read(scene, "ask"), ["Sign?", "-> Enough"] as Array[String], "the stop ends the scene"
	)


func test_an_unreadable_interpolation_is_left_as_written() -> void:
	var runner := YarnRunner.new(_program())
	assert_eq(runner.interpolate("A {$ } line."), "A {$ } line.", "no expression, no fill")
	assert_eq(runner.interpolate("A plain line."), "A plain line.")
	assert_eq(runner.interpolate("An open {$score line."), "An open {$score line.")


func test_the_runner_names_the_node_it_reads() -> void:
	var runner := YarnRunner.new(_program())
	assert_true(runner.start("signed"))
	assert_eq(runner.node_name(), "signed")
	assert_false(runner.at_end(), "a node just started is not ended")
	runner.advance()
	assert_true(runner.at_end(), "the last line ends it")


# --- the court's standing word ---------------------------------------------

func test_the_court_speaks_its_standing_word_from_yarn() -> void:
	var program := DialogueYarn.program()
	assert_true(bool(program.get("ok", false)), "the authored source parses")
	assert_eq(
		DialogueYarn.points(),
		[
			"reactive/standing_alliance", "reactive/standing_cold",
			"reactive/standing_friendly", "reactive/standing_neutral",
			"reactive/standing_war",
		] as Array[String],
		"one node per band, keyed as a point"
	)
	for point: String in DialogueYarn.points():
		assert_eq(DialogueYarn.category_for(point), DialogueCatalog.CAT_REACTIVE, point)
		assert_true(DialogueYarn.lines_for(point).size() >= 2, "%s repeats less" % point)
		assert_false(DialogueYarn.moods_for(point).is_empty(), "%s wears a face" % point)
		for mood: Variant in DialogueYarn.moods_for(point):
			assert_true(DialogueMood.MOODS.has(String(mood)), "%s wears a real face" % point)


func test_the_standing_word_is_stable_and_inside_its_variants() -> void:
	for point: String in DialogueYarn.points():
		var lines: Array = DialogueYarn.lines_for(point)
		for salt: int in [0, 7, 131, 1000002]:
			var spoken: String = DialogueYarn.line_for(point, salt)
			assert_true(lines.has(spoken), "%s speaks one of its lines" % point)
			assert_eq(spoken, DialogueYarn.line_for(point, salt), "the same salt, the same word")


func test_the_merged_catalogue_keeps_every_point() -> void:
	assert_eq(
		DialogueCatalog.table().size(),
		DialogueCatalog.POINTS.size() + DialogueEpisodes.POINTS.size()
		+ DialogueAgendaLines.POINTS.size() + DialogueYarn.points().size(),
		"the merged catalogue loses no point"
	)
	for point: String in DialogueYarn.points():
		assert_true(DialogueCatalog.has_point(point), "%s is reachable" % point)
		assert_eq(DialogueCatalog.lines_for(point), DialogueYarn.lines_for(point), point)


func test_an_unknown_point_speaks_nothing() -> void:
	assert_eq(DialogueYarn.line_for("reactive/standing_unknown", 0), "")
	assert_eq(DialogueCatalog.line_for("reactive/standing_unknown", 0), "")
	assert_false(DialogueYarn.has_point("reactive/standing_unknown"))
	assert_eq(DialogueYarn.category_for("reactive/standing_unknown"), "")
	assert_eq(DialogueYarn.lines_for("reactive/standing_unknown"), [])
	assert_eq(DialogueYarn.moods_for("reactive/standing_unknown"), [])


func test_a_line_outside_a_node_is_refused() -> void:
	var stray := "title: gate\n---\nA.\n===\nA stray line.\n"
	var program := YarnScript.parse(stray)
	assert_false(bool(program["ok"]))
	assert_true(String(program["error"]).contains("stray"), String(program["error"]))


func test_a_jump_without_a_node_is_refused() -> void:
	assert_false(bool(YarnScript.parse("title: gate\n---\n<<jump>>\n===\n")["ok"]))


func test_an_option_command_that_is_not_closed_is_refused() -> void:
	var broken := "title: gate\n---\n-> Accept <<jump signed\n===\n"
	assert_false(bool(YarnScript.parse(broken)["ok"]))


# --- localization keys ------------------------------------------------------

func test_a_line_carries_a_stable_translation_key() -> void:
	assert_eq(
		DialogueLocale.line_key("reactive/standing_cold", 1),
		"DialoguePoint/reactive/standing_cold/1",
		"the key names the point and the variant"
	)


func test_an_untranslated_key_falls_back_to_the_authored_line() -> void:
	assert_eq(
		DialogueLocale.line("reactive/standing_cold", 0, "We have little to say."),
		"We have little to say.",
		"the source language is never lost"
	)
	assert_true(DialogueLocale.locales().has(DialogueLocale.SOURCE_LOCALE))


func test_english_is_the_only_supported_locale() -> void:
	DialogueLocale.set_locale("fr")
	assert_eq(DialogueLocale.locale(), DialogueLocale.SOURCE_LOCALE, "foreign codes are ignored")
	assert_eq(DialogueLocale.locales(), PackedStringArray([DialogueLocale.SOURCE_LOCALE]))
	assert_eq(
		DialogueCatalog.line_for("reactive/standing_war", 0),
		String(DialogueCatalog.lines_for("reactive/standing_war")[0]),
		"the court always speaks English"
	)


func test_the_english_court_speaks_as_authored() -> void:
	var changed: Array[String] = []
	for point: String in DialogueCatalog.points():
		var lines: Array = DialogueCatalog.lines_for(point)
		for index in lines.size():
			if DialogueCatalog.line_for(point, index) != String(lines[index]):
				changed.append(DialogueLocale.line_key(point, index))
	assert_eq(changed, [] as Array[String], "the English court speaks as it was authored: %s" % str(changed))


# --- the prompts' words ------------------------------------------------------
#
# Blocking decisions print English from [ConsentCopy] (wiki:
# dialogue-content-and-yarn § Playable slice; DR-20261113-10).

func test_a_prompt_names_the_courts_in_english() -> void:
	var call: Dictionary = {"aggressor": 2, "defender": 1}
	var english: String = ConsentCopy.call_body(call)
	assert_true(english.contains("France"), english)
	assert_true(english.contains("England"), english)
	assert_eq(ConsentCopy.button("join"), "Join the war")


func test_a_prompt_keeps_the_authored_source() -> void:
	DialogueLocale.set_locale("de")
	var line: String = ConsentCopy.say("call/toast", ["England", "France"])
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	assert_eq(
		line, "England calls on our alliance against France.",
		"English is the only court copy"
	)


## Each kind is named by its own sentence (REQ-P2-05).
func test_every_proposal_kind_names_its_own_offer() -> void:
	var kinds: Dictionary = {
		DiplomacyProposals.KIND_ALLIANCE: "a formal alliance",
		DiplomacyProposals.KIND_FTP: "a favoured trading pact",
		DiplomacyProposals.KIND_PEACE: "a white peace",
	}
	for kind: Variant in kinds.keys():
		var line: String = ConsentCopy.proposal_body(2, String(kind), "")
		assert_true(line.begins_with("France proposes "), line)
		assert_true(line.contains(String(kinds[kind])), line)
	var overture: String = ConsentCopy.proposal_body(
		2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	assert_eq(overture, "France proposes the Non-Aggression Pact.", overture)
	var by_stage: Array[String] = []
	for stage: String in DiplomacyCatalog.STAGES:
		by_stage.append(
			ConsentCopy.proposal_body(2, DiplomacyProposals.KIND_OVERTURE, stage)
		)
	for line: String in by_stage:
		assert_true(line.begins_with("France proposes "), line)
	assert_eq(
		ConsentCopy.proposal_body(
			2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NONE
		),
		"France proposes the No overture.",
		"a stage with nothing to offer still names the offer"
	)


# --- test_symbol_plates ---

## One boot for the drawn plates: tech, commodity and unit icons and the map's
## symbol stamp.

## Merged from test_tech_icons, test_commodity_icons, test_unit_icons,
## test_map_symbols.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.

const KINDS: Array[String] = [
	"mountain", "hill", "tree", "scrub", "dune", "reed", "grass", "field",
	"port", "capital", "town",
]

# --- test_tech_icons ---

func test_every_catalog_tech_names_a_series() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.series_of(tech_id).is_empty():
			missing.append(tech_id)
	assert_eq(missing.size(), 0, "techs without a plate: %s" % ", ".join(missing))

func test_every_series_ships_a_texture() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.texture(tech_id) == null:
			missing.append(TechIcons.series_of(tech_id))
	assert_eq(missing.size(), 0, "plates missing from assets/art/tech: %s" % ", ".join(missing))

func test_a_chain_shares_one_plate() -> void:
	assert_eq(TechIcons.series_of("crop_rotation"), TechIcons.series_of("land_enclosure"))
	assert_eq(TechIcons.series_of("sugar_planting"), TechIcons.series_of("sugar_industry"))

func test_a_long_chain_may_grow_a_grander_plate() -> void:
	assert_ne(TechIcons.series_of("saw_mill"), TechIcons.series_of("circular_saw"))

func test_an_unknown_tech_has_no_plate() -> void:
	assert_eq(TechIcons.series_of("no_such_tech"), "")
	assert_null(TechIcons.texture("no_such_tech"))

func test_no_plate_is_listed_twice() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for tech_id: String in TechIcons.covered_ids():
		if seen.has(tech_id):
			clashes.append(tech_id)
		seen[tech_id] = true
	assert_eq(clashes.size(), 0, "techs claimed by two plates: %s" % ", ".join(clashes))

# --- test_commodity_icons ---

func test_every_catalog_commodity_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if CommodityIcons.texture(id) == null:
			missing.append(id)
	assert_eq(missing.size(), 0, "goods with no plate: %s" % ", ".join(missing))

func test_two_goods_never_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		var art: Texture2D = CommodityIcons.texture(id)
		if art == null:
			continue
		if seen.has(art.resource_path):
			clashes.append("%s/%s" % [seen[art.resource_path], id])
		seen[art.resource_path] = id
	assert_eq(clashes.size(), 0, "goods sharing a plate: %s" % ", ".join(clashes))

func test_an_unknown_good_has_no_plate() -> void:
	assert_null(CommodityIcons.texture("no_such_good"))
	assert_null(CommodityIcons.texture(""))

func test_a_badge_draws_the_good_at_the_row_size() -> void:
	var badge: Control = CommodityIcons.badge("grain")
	var art: TextureRect = badge as TextureRect
	assert_not_null(art, "a known good draws a texture")
	assert_eq(art.texture, CommodityIcons.texture("grain"))
	assert_eq(art.custom_minimum_size, Vector2(CommodityIcons.ROW_SIZE, CommodityIcons.ROW_SIZE))
	badge.free()

func test_a_missing_plate_leaves_a_gap_of_the_same_width() -> void:
	var gap: Control = CommodityIcons.badge("no_such_good", 18)
	assert_null(gap as TextureRect, "a missing plate is not a texture")
	assert_eq(gap.custom_minimum_size, Vector2(18, 18), "the row keeps its columns")
	gap.free()

func test_a_name_cell_keeps_the_column_width() -> void:
	var cell: HBoxContainer = CommodityIcons.cell("timber", 132.0)
	assert_eq(cell.custom_minimum_size.x, 132.0, "the cell owns the column width")
	var labels: Array[Node] = cell.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 1, "one label per cell")
	assert_eq((labels[0] as Label).text, CommodityCatalog.label("timber"))
	var art: Array[Node] = cell.find_children("*", "TextureRect", true, false)
	assert_eq(art.size(), 1, "the medallion rides inside the cell")
	assert_eq((art[0] as TextureRect).texture, CommodityIcons.texture("timber"))
	cell.free()

## The plate is 128 px so it survives the phone's 3× draw scale.
func test_a_plate_is_a_128_px_source() -> void:
	var art: Texture2D = CommodityIcons.texture("coal")
	assert_not_null(art)
	assert_eq(art.get_width(), 128)
	assert_eq(art.get_height(), 128)

# --- test_unit_icons ---

func test_every_worker_type_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in CivilianCatalog.ORDER:
		if CivilianArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "workers without a plate: %s" % ", ".join(missing))

func test_every_hull_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: Variant in ShipStats.STATS.keys():
		if ShipArt.medallion(String(type_id)) == null:
			missing.append(String(type_id))
	assert_eq(missing.size(), 0, "hulls without a plate: %s" % ", ".join(missing))

func test_every_regiment_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in RegimentCatalog.ids():
		if RegimentArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "regiments without a plate: %s" % ", ".join(missing))

## Unique icons, not one plate reused under several names: every type resolves
## a file of its own.
func test_no_two_types_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for type_id: String in _every_type():
		var texture: Texture2D = _plate(type_id)
		var path: String = texture.resource_path if texture != null else ""
		if seen.has(path):
			clashes.append("%s = %s" % [type_id, String(seen[path])])
		seen[path] = type_id
	assert_eq(clashes.size(), 0, "types sharing a plate: %s" % ", ".join(clashes))

func test_an_unknown_hull_falls_back_to_the_default_plate() -> void:
	assert_eq(
		ShipArt.medallion("no_such_hull").resource_path,
		ShipArt.medallion(ShipStats.DEFAULT_TYPE).resource_path
	)
	assert_eq(
		RegimentArt.medallion("no_such_regiment").resource_path,
		RegimentArt.medallion(RegimentCatalog.DEFAULT_TYPE).resource_path
	)

func test_an_unknown_worker_has_no_plate() -> void:
	assert_null(CivilianArt.medallion("no_such_worker"))

## The row widget wears the plate at its own size, mipmapped, and a missing
## plate leaves a gap of the same width so the row's columns do not shift.
func test_the_row_widget_draws_the_plate_it_is_given() -> void:
	var plate: Texture2D = ShipArt.medallion("frigate")
	var medallion: UnitMedallion = UnitMedallion.of_ship("frigate", 40.0)
	assert_eq(medallion.texture, plate)
	assert_eq(medallion.custom_minimum_size, Vector2(40.0, 40.0))
	assert_eq(medallion.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	assert_eq(medallion.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(medallion.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	add_child(medallion)
	medallion.queue_free()
	var bare := UnitMedallion.new(null, 20.0)
	assert_null(bare.texture)
	assert_eq(bare.custom_minimum_size, Vector2(20.0, 20.0), "an absent plate keeps its width")
	add_child(bare)
	bare.queue_free()

func test_a_regiment_medallion_names_its_own_type() -> void:
	var medallion: UnitMedallion = UnitMedallion.of_regiment("grenadiers")
	assert_eq(medallion.texture, RegimentArt.medallion("grenadiers"))
	assert_eq(medallion.custom_minimum_size, Vector2(28.0, 28.0))

func _every_type() -> Array[String]:
	var all: Array[String] = []
	all.append_array(CivilianCatalog.ORDER)
	for type_id: Variant in ShipStats.STATS.keys():
		all.append(String(type_id))
	all.append_array(RegimentCatalog.ids())
	return all

func _plate(type_id: String) -> Texture2D:
	if CivilianCatalog.known(type_id):
		return CivilianArt.medallion(type_id)
	if ShipStats.known(type_id):
		return ShipArt.medallion(type_id)
	return RegimentArt.medallion(type_id)

# --- test_map_symbols ---

func test_every_planned_kind_has_a_painted_stamp() -> void:
	for kind: String in KINDS:
		var tex: Texture2D = MapSymbols.texture(kind)
		assert_not_null(tex, "%s has no painted stamp" % kind)
		assert_gt(tex.get_width(), 63, "%s is drawn from a downscaled source" % kind)

func test_unknown_kind_has_no_stamp() -> void:
	assert_null(MapSymbols.texture("nonesuch"))

## The stamp falls back to the ink vectors rather than drawing nothing.
func test_stamp_refuses_a_kind_it_has_no_art_for() -> void:
	assert_false(MapSymbols.stamp(_probe(), {"kind": "nonesuch", "position": Vector2.ZERO, "size": 20.0}))
	assert_false(MapSymbols.stamp(_probe(), {"kind": "tree", "position": Vector2.ZERO, "size": 0.0}))

## A scattered province uses more than one sprite, so a range is not one stamp.
func test_terrain_mountains_take_several_variants() -> void:
	var seen: Dictionary = {}
	for i in 40:
		var at := Vector2(float(i) * 37.0, float(i) * 91.0)
		seen[MapSymbols.texture("mountain", at)] = true
	assert_gt(seen.size(), 1, "a mountain range repeats one sprite")

func test_stamp_draws_a_scenery_mark() -> void:
	var drawn: bool = await _draw_mark({
		"kind": "tree", "position": Vector2(30, 30), "size": 18.0, "flip": true,
	})
	assert_true(drawn, "the painted stamp drew instead of falling back")

func test_stamp_draws_a_town() -> void:
	assert_true(await _draw_mark({"kind": "town", "position": Vector2(64, 64), "size": 20.0}))

## The capital flies its owner's pennant, and still draws when nobody holds it.
func test_capital_stamp_covers_owner_and_neutral() -> void:
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(90, 90), "size": 24.0, "owner": 2,
	}))
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(120, 120), "size": 24.0,
		"owner": MapModel.NO_ID,
	}))

func test_ship_uses_a_painted_hull() -> void:
	var tex: Texture2D = MapSymbols.texture("ship")
	assert_not_null(tex, "the fleet has no painted hull")
	assert_eq(tex.get_width(), 256)


## The estate marks a developed tile leaves on the chart are painted too, so a
## timber camp or a mine reads at map scale (issue #1007).
func test_every_estate_mark_has_a_painted_stamp() -> void:
	for kind: String in ["work_wood", "work_mine", "work_riches", "work_grain"]:
		var tex: Texture2D = MapSymbols.texture(kind)
		assert_not_null(tex, "%s has no painted stamp" % kind)
		assert_gt(tex.get_width(), 63, "%s is drawn from a downscaled source" % kind)


## A developed tile takes its family's mark: timber, ore, coin or grain.
func test_estate_marks_follow_the_resource_family() -> void:
	var seen: Dictionary = {}
	for resource in 20:
		seen[LandWorksPaint._kind(resource)] = true
	assert_true(seen.has("work_wood"), "timber has its own mark")
	assert_true(seen.has("work_mine"), "ore has its own mark")
	assert_true(seen.has("work_riches"), "coin has its own mark")
	assert_true(seen.has("work_grain"), "grain and unknown ground share the sheaf")


## The ink fallback still draws every family where no art is imported, which is
## the build a headless run gets (issue #1007).
func test_estate_ink_fallback_draws_each_family() -> void:
	var probe := _EstateProbe.new()
	probe.name = "EstateProbe"
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	assert_true(probe.drawn, "the ink fallback drew every family")
	probe.queue_free()

func _probe() -> _StampProbe:
	return _StampProbe.new()

## Drawing is only legal inside `_draw`, so the probe's own draw runs the stamp
## and the test reads its result after a rendered frame.
func _draw_mark(glyph: Dictionary) -> bool:
	var probe := _probe()
	probe.name = "StampProbe"
	probe.glyph = glyph
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	var drawn: bool = probe.result
	probe.queue_free()
	return drawn

class _StampProbe:
	extends Node2D

	var glyph: Dictionary = {}
	var result: bool = false

	func _draw() -> void:
		result = MapSymbols.stamp(self, glyph)


class _EstateProbe:
	extends Node2D

	var drawn: bool = false

	func _draw() -> void:
		for resource in [0, 1, 3, 4]:
			LandWorksPaint.ink_mark(self, Vector2(20, 20), resource)
		drawn = true
# --- test_espionage ---

## Espionage rules (wiki: civilian-units § Spy, research-state § Spy RP boost,
## diplomacy § Spy-death penalty) and the rival AI's spy/research policy.

const CivilianFixture = preload("res://tests/civilian_fixture.gd")
const NavalFixture = preload("res://tests/naval_fixture.gd")
const PLAYER: int = 0
const RIVAL: int = 1
const SEED: int = 7


class StubHud extends GameHud:
	var toasts: Array[String] = []

	func toast(text: String, _icon_name: String = "") -> void:
		toasts.append(text)


# --- roster and movement -----------------------------------------------------


func test_spy_is_playable_and_keeps_its_wiki_costs() -> void:
	assert_true(CivilianCatalog.is_implemented("spy"))
	assert_eq(CivilianCatalog.treasury_cost("spy"), 2000)
	assert_eq(CivilianCatalog.paper_cost("spy"), 4)
	assert_in("spy", CivilianCatalog.playable_types())
	assert_eq(CivilianCatalog.works("spy"), [SpyRules.WORK_COUNTER])


func test_spy_may_walk_into_a_foreign_province() -> void:
	var model: MapModel = CivilianFixture.build()
	assert_true(
		CivilianMovement.may_enter(model, "spy", PLAYER, CivilianFixture.RIVAL_GRAIN_TILE)
	)
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", Vector2i(2, 0)
	)
	var result: Dictionary = CivilianMovement.apply_move(
		model, spy, CivilianFixture.RIVAL_GRAIN_TILE
	)
	assert_true(bool(result.get("ok", false)))
	assert_eq(spy.tile, CivilianFixture.RIVAL_GRAIN_TILE)


## Walking a foreign province is quiet; being put ashore there is not. Landing
## needs crown land for every civilian but Explorer and Merchant
## (wiki: civilian-units § Overseas deployment).
func test_a_spy_cannot_land_on_a_foreign_coast() -> void:
	var model: MapModel = NavalFixture.build()
	var fleet: FleetState = FleetState.at_sea(2, PLAYER, 1, ["c"], {"c": "fluyte"})
	var spy: CivilianState = CivilianState.create(5, PLAYER, "spy", Vector2i(0, 0))
	spy.embarked_fleet = fleet.id
	fleet.add_civilian(spy.id)
	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(model, spy, fleet)
	assert_false(tiles.has(Vector2i(5, 0)), "a rival coast refuses a spy")
	assert_false(tiles.has(Vector2i(5, 1)), "nor its harbour")
	var explorer: CivilianState = CivilianState.create(6, PLAYER, "explorer", Vector2i(0, 0))
	explorer.embarked_fleet = fleet.id
	fleet.add_civilian(explorer.id)
	assert_true(
		CivilianVoyage.landing_tiles(model, explorer, fleet).has(Vector2i(5, 1)),
		"an explorer still surveys any coast"
	)
	var home: FleetState = FleetState.in_port(3, PLAYER, 0, ["d"], {"d": "fluyte"})
	var home_spy: CivilianState = CivilianState.create(7, PLAYER, "spy", Vector2i(0, 0))
	home_spy.embarked_fleet = home.id
	home.add_civilian(home_spy.id)
	assert_false(
		CivilianVoyage.landing_tiles(model, home_spy, home).is_empty(),
		"crown land still takes the spy ashore"
	)


func test_presence_holds_a_charted_province_for_its_owner_only() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	assert_eq(CivilianMovement.held_provinces(model, [spy], PLAYER), [RIVAL])
	assert_eq(CivilianMovement.held_provinces(model, [spy], RIVAL), [])
	assert_eq(
		SpyNetworks.qualifying_rivals(model, [spy], PLAYER), [RIVAL],
		"a spy on a rival court's land shadows that court"
	)


func test_a_spy_in_its_own_land_observes_nothing() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	assert_eq(SpyNetworks.qualifying_rivals(model, [spy], PLAYER), [])


# --- counter-espionage -------------------------------------------------------


func test_counter_spy_is_an_ongoing_owned_order() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	var units: Array[CivilianState] = [spy]
	var check: Dictionary = CivilianWork.validate(
		model, spy, SpyRules.WORK_COUNTER, LandWorks.new(), units,
		CivilianFixture.stockpile()
	)
	assert_true(bool(check.get("ok", false)), "an owned province is a legal screen")
	assert_eq(CivilianWork.assign(
		model, spy, SpyRules.WORK_COUNTER, LandWorks.new(), units,
		CivilianFixture.stockpile()
	).get("ok", false), true)
	assert_true(spy.is_working())
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		model, units, LandWorks.new()
	)
	assert_true(reports.is_empty(), "the screen never advances or completes")
	assert_true(spy.is_working(), "counter-espionage stays up until cancelled")
	var rival_tile: CivilianState = CivilianState.create(
		2, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var rival_check: Dictionary = CivilianWork.validate(
		model, rival_tile, SpyRules.WORK_COUNTER, LandWorks.new(),
		[rival_tile] as Array[CivilianState], CivilianFixture.stockpile()
	)
	assert_false(
		bool(rival_check.get("ok", false)), "a foreign province is not a legal target"
	)


# --- research intelligence ---------------------------------------------------


func test_research_bonus_stacks_per_observed_rival() -> void:
	var bonus: Dictionary = SpyNetworks.research_boost(
		[RIVAL, 2],
		{RIVAL: {"crop_rotation": true}, 2: {"crop_rotation": true, "saw_mill": true}}
	)
	assert_eq(int(bonus.get("crop_rotation", 0)), 30, "two rivals, two +15%")
	assert_eq(int(bonus.get("saw_mill", 0)), 15)
	var none: Dictionary = SpyNetworks.research_boost(
		[RIVAL], {RIVAL: {"saw_mill": true}}
	)
	assert_eq(int(none.get("crop_rotation", 0)), 0, "a tech the rival lacks earns nothing")


func test_research_turn_applies_the_spy_bonus() -> void:
	var state := ResearchState.make()
	state.assign("crop_rotation", "medium")
	var economy := PlayerEconomy.starting()
	assert_eq(ResearchTurn.points_for(state, "crop_rotation", "medium"), 300)
	assert_eq(
		ResearchTurn.points_for(state, "crop_rotation", "medium", 15), 345,
		"a 15% network lifts 300 RP to 345"
	)
	var report: Dictionary = ResearchTurn.resolve(
		state, economy, {"crop_rotation": 15}
	)
	assert_eq(int(report["slots"][0]["rp"]), 345)
	assert_eq(state.progress_of("crop_rotation"), 345)


func test_map_phase_prepares_the_player_spy_bonus() -> void:
	var play: PlaySession = _play_with_spy()
	var controller: EconomyController = play.economy
	controller.economy.research.slots[0] = {"tech": "crop_rotation", "funding": "medium"}
	var rival_economy: PlayerEconomy = play.ai.economy_for(RIVAL)
	rival_economy.research.unlocked["crop_rotation"] = true
	var bonus: Dictionary = MapPlayEspionage.research_boost(play)
	assert_eq(int(bonus.get("crop_rotation", 0)), 15)
	controller.research_boost = bonus
	assert_eq(int(controller.research_boost.get("crop_rotation", 0)), 15)
	play.hud.free()
	controller.free()


func test_rival_spies_are_invisible_on_the_map() -> void:
	var model: MapModel = CivilianFixture.build()
	var layer := CivilianLayer.new()
	layer.viewer_faction = PLAYER
	layer.spawn(model, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	var rival_spy: CivilianState = layer.add_unit(
		RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var own_spy: CivilianState = layer.add_unit(PLAYER, "spy", CivilianFixture.BARE_TILE)
	assert_false(layer.marker_for(rival_spy).visible, "a rival spy leaves no marker")
	assert_true(layer.marker_for(own_spy).visible)
	var rival_point: Vector2 = MapGeo.tile_center(
		CivilianFixture.RIVAL_GRAIN_TILE.x, CivilianFixture.RIVAL_GRAIN_TILE.y,
		PlaySession.TILE_SIZE
	)
	var own_point: Vector2 = MapGeo.tile_center(
		CivilianFixture.BARE_TILE.x, CivilianFixture.BARE_TILE.y, PlaySession.TILE_SIZE
	)
	assert_null(layer.unit_at(rival_point), "a rival spy is not selectable")
	assert_eq(layer.unit_at(own_point), own_spy)
	layer.free()


# --- kill and defection ------------------------------------------------------


func test_counter_espionage_kills_and_turns_spies() -> void:
	var model: MapModel = CivilianFixture.build()
	var rolls: Dictionary = _find_rolls(model)
	assert_true(int(rolls["kill"]) > 0, "5% kill chance lands within the search")
	assert_true(int(rolls["defect"]) > 0, "10% defection lands within the search")
	var units: Array[CivilianState] = _spy_pair()
	var events: Array[Dictionary] = SpyRules.resolve_turn(
		model, units, int(rolls["kill"]), SEED
	)
	assert_eq(String(events[0]["kind"]), "killed")
	assert_eq(units.size(), 1, "the killed spy leaves the roster")
	var defectors: Array[CivilianState] = _spy_pair()
	var defected: Array[Dictionary] = SpyRules.resolve_turn(
		model, defectors, int(rolls["defect"]), SEED
	)
	assert_eq(String(defected[0]["kind"]), "defected")
	assert_eq(int(defected[0]["unit"].owner), RIVAL, "the survivor changes coat")


func test_a_killed_spy_cools_relations_by_eight() -> void:
	var play: PlaySession = _play_with_spy()
	play.turn = int(_find_rolls(play.model)["kill"])
	play.diplomacy.ensure_relation(PLAYER, RIVAL, 1)
	play.diplomacy.relation(PLAYER, RIVAL).score = 60.0
	play.civilian_layer.units = _spy_pair()
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	var events: Array[Dictionary] = MapPlaySpies.resolve(play)
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["kind"]), "killed")
	assert_almost_eq(play.diplomacy.relation(PLAYER, RIVAL).score, 52.0, 0.001)
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(
		play.hud.toasts[0].contains("−8 with England"),
		"the court hears what its loss cost: " + play.hud.toasts[0]
	)
	var chronicle: Array[Dictionary] = DiplomacyHistory.entries(play.diplomacy, PLAYER, RIVAL)
	assert_false(chronicle.is_empty(), "the chronicle keeps the act")
	assert_true(
		String(chronicle[0]["text"]).contains("agent was taken in"),
		"the standing shifted for a stated reason: " + String(chronicle[0]["text"])
	)
	play.hud.free()
	play.economy.free()


## Every line the court can hear for a spy event, and the ones it cannot: a
## rival spy's province is invisible to this crown, so another pair's kill stays
## silent (wiki: civilian-units § Spy (4)). A killed spy costs the pair 8, so
## each line names that price (wiki: diplomacy § Spy-death penalty).
func test_spy_notice_names_the_price_and_the_court() -> void:
	var caught: Dictionary = {"kind": "killed", "owner": RIVAL, "territory_owner": PLAYER}
	assert_eq(
		MapPlaySpies.notice(caught, "Coro", PLAYER),
		"Counter-espionage caught England's spy in Coro — −8 with England."
	)
	var lost: Dictionary = {"kind": "killed", "owner": PLAYER, "territory_owner": RIVAL}
	assert_eq(
		MapPlaySpies.notice(lost, "Coro", PLAYER),
		"A spy in Coro has gone silent — −8 with England."
	)
	var turned: Dictionary = {"kind": "defected", "owner": RIVAL, "territory_owner": PLAYER}
	assert_eq(
		MapPlaySpies.notice(turned, "Coro", PLAYER),
		"England's spy in Coro has turned coat and now serves your crown."
	)
	assert_eq(
		MapPlaySpies.notice(turned, "Coro", RIVAL), "A spy in Coro has turned coat."
	)
	var abroad: Dictionary = {"kind": "killed", "owner": 2, "territory_owner": RIVAL}
	assert_eq(MapPlaySpies.notice(abroad, "Coro", PLAYER), "", "another court's business")
	assert_eq(MapPlaySpies.notice({}, "Coro", PLAYER), "")


func test_an_unscreened_spy_is_never_touched() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var units: Array[CivilianState] = [spy]
	for turn in 50:
		assert_true(SpyRules.resolve_turn(model, units, turn, SEED).is_empty())
	assert_eq(units.size(), 1, "no counter-spy means no kill or defection roll")


## One spy on `counter_spy` anywhere screens every owned province, so a screen
## kept at home must hunt an enemy spy standing in another region's colony
## (wiki: civilian-units § Spy (3): "empire-wide ... in all owned provinces").
func test_counter_espionage_screen_covers_every_region() -> void:
	var play: PlaySession = _two_region_play()
	var events: Array[Dictionary] = []
	for turn in range(1, 401):
		play.turn = turn
		events.append_array(MapPlaySpies.resolve(play))
	assert_false(events.is_empty(), "the home screen hunts the colonial intruder")
	for event: Dictionary in events:
		assert_eq(int(event.get("region", -1)), 1, "the intruder stood in region 1")


# --- rival AI ----------------------------------------------------------------


func test_ai_spy_walks_toward_a_rival_province() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var units: Array = [spy]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context()
	)
	assert_eq((plan["moves"] as Array).size(), 1)
	assert_eq((plan["orders"] as Array).size(), 0)
	var step: Vector2i = plan["moves"][0]["tile"]
	assert_true(step.x > CivilianFixture.RIVAL_GRAIN_TILE.x - 2)


func test_ai_spy_holds_a_foreign_province() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context()
	)
	assert_true((plan["moves"] as Array).is_empty())
	assert_true((plan["orders"] as Array).is_empty(), "presence duty, not a work order")


func test_ai_spy_raises_a_counter_screen_at_war() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), SpyRules.WORK_COUNTER)


func test_ai_war_screen_frees_the_second_spy_to_observe() -> void:
	var model: MapModel = CivilianFixture.build()
	var first: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var second: CivilianState = CivilianState.create(
		2, RIVAL, "spy", Vector2i(4, 0)
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [first, second], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_eq((plan["orders"] as Array).size(), 1, "one spy keeps the screen")
	assert_eq(String(plan["orders"][0]["action"]), SpyRules.WORK_COUNTER)
	assert_eq((plan["moves"] as Array).size(), 1, "the other walks abroad")


func test_ai_recalls_a_spy_to_screen_at_war() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_true((plan["orders"] as Array).is_empty())
	assert_eq((plan["moves"] as Array).size(), 1, "the spy walks home to screen")
	assert_true(Vector2i(plan["moves"][0]["tile"]).x > CivilianFixture.BARE_TILE.x)


func test_ai_trains_a_spy_after_its_base_roster() -> void:
	# Floors with no regional work: 2 builders, engineer_target (2), explorer_target (3).
	# The court is neutral here so the floors are the published ones — an
	# archetype's own crew is a target of its own (AiStaffTaste, test_ai_rules).
	var config: AiConfig = AiConfig.build(RIVAL, 1500)
	config.personality = AiPersonality.NEUTRAL
	var roster: Array[CivilianState] = [
		CivilianState.create(1, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(9, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(2, RIVAL, "engineer", CivilianFixture.BARE_TILE),
		CivilianState.create(3, RIVAL, "engineer", CivilianFixture.BARE_TILE),
		CivilianState.create(4, RIVAL, "explorer", CivilianFixture.BARE_TILE),
		CivilianState.create(5, RIVAL, "explorer", CivilianFixture.BARE_TILE),
		CivilianState.create(6, RIVAL, "explorer", CivilianFixture.BARE_TILE),
	]
	var order: Dictionary = AiCivilianHire.training_order(config, roster, _context())
	assert_true(bool(order.get("ok", false)))
	assert_eq(String(order["type_id"]), "spy")
	var war_roster: Array[CivilianState] = [
		CivilianState.create(1, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(9, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(2, RIVAL, "engineer", CivilianFixture.BARE_TILE),
		CivilianState.create(3, RIVAL, "engineer", CivilianFixture.BARE_TILE),
	]
	var war_context: Dictionary = _context()
	war_context["at_war"] = true
	var war_order: Dictionary = AiCivilianHire.training_order(config, war_roster, war_context)
	assert_eq(String(war_order["type_id"]), "spy", "a war court wants a screen first")


func test_ai_research_planner_opens_a_study() -> void:
	var economy := PlayerEconomy.starting()
	var plan: Dictionary = AiResearchPlanner.plan(
		AiConfig.build(RIVAL, 1500), economy, {}
	)
	var assignments: Array = plan["assignments"]
	assert_false(assignments.is_empty(), "the planner fills a free slot")
	var tech: String = String(assignments[0]["tech"])
	assert_false(tech.is_empty())
	assert_true(ResearchFunding.known(String(assignments[0]["funding"])))
	var before: int = economy.research.progress_of(tech)
	ResearchTurn.resolve(economy.research, economy)
	assert_true(
		economy.research.progress_of(tech) > before
		or economy.research.is_unlocked(tech),
		"the Research phase advances the assigned study"
	)


func test_ai_research_is_deterministic() -> void:
	var first := PlayerEconomy.starting()
	var second := PlayerEconomy.starting()
	var config: AiConfig = AiConfig.build(RIVAL, 1500)
	var left: Dictionary = AiResearchPlanner.plan(config, first, {})
	var right: Dictionary = AiResearchPlanner.plan(config, second, {})
	assert_eq(
		String(left["assignments"][0]["tech"]),
		String(right["assignments"][0]["tech"])
	)


# --- court reports -----------------------------------------------------------


func test_court_report_names_battles_and_techs() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": RIVAL,
		"defender": PLAYER,
		"captured": true,
	}
	var sea: Dictionary = {"region": 0, "zone": 0, "attacker": RIVAL, "defender": PLAYER}
	var report: Dictionary = {
		"factions": {
			RIVAL: {"resolved": {"research": {"researched": ["crop_rotation"]}}},
		},
	}
	MapPlaySpies.report(play, [land], [sea], report)
	assert_true(play.hud.toasts.is_empty(), "the despatch is not a toast")
	var lines: Array = (play.court_reports["lines"] as Dictionary)[RIVAL]
	var joined: String = " · ".join(lines)
	assert_true(joined.contains("took Coro from Spain"), joined)
	assert_true(joined.contains("squadron action in Mar Caribe"), joined)
	assert_true(joined.contains("Crop Rotation"), joined)
	play.hud.free()
	play.economy.free()


func test_court_report_names_a_lost_province() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": PLAYER,
		"defender": RIVAL,
		"captured": true,
	}
	MapPlaySpies.report(play, [land], [], {})
	assert_true(play.hud.toasts.is_empty(), "the despatch is not a toast")
	var lines: Array = (play.court_reports["lines"] as Dictionary)[RIVAL]
	assert_true((" · ".join(lines)).contains("lost Coro to Spain"))
	play.hud.free()
	play.economy.free()


func test_court_report_names_a_diplomatic_act() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = [{"faction": RIVAL, "message": "England declares war on France."}]
	MapPlaySpies.report(play, [], [], {})
	assert_true(play.hud.toasts.is_empty(), "the despatch is not a toast")
	var lines: Array = (play.court_reports["lines"] as Dictionary)[RIVAL]
	assert_true((" · ".join(lines)).contains("declares war"))
	play.hud.free()
	play.economy.free()


## A study the spy watched is written into the chronicle, stamped with the turn
## it resolved, so the dossier can weigh it long after the toast has gone
## (DR-20261110-25).
func test_a_shadowed_study_enters_the_dossier() -> void:
	var play: PlaySession = _play_with_spy()
	var report: Dictionary = {
		"factions": {
			RIVAL: {"resolved": {"research": {"researched": ["crop_rotation"]}}},
		},
	}
	MapPlaySpies.report(play, [], [], report)
	var events: Array = play.diplomacy.events
	assert_eq(events.size(), 1, "one study, one observation")
	var event: Dictionary = events[0] as Dictionary
	assert_eq(String(event["kind"]), IntelEvidence.SPY_TECH)
	assert_eq(String((event["data"] as Dictionary)["tech"]), "crop_rotation")
	assert_eq(IntelEvidence.turn_of(event), 1, "stamped with the turn that resolved")
	var scores: Dictionary = IntelDossier.suspicion(
		IntelDossier.evidence(play.diplomacy, play.world, PLAYER, RIVAL)
	)
	assert_eq(int(scores.get(AiAgenda.TECH_THIEF, 0)), IntelEvidence.W_SPY_TECH)
	play.hud.free()
	play.economy.free()


## Only a shadowed court's studies are read; a rival the spy does not watch
## keeps its research (wiki: civilian-units § Spy — court reports).
func test_an_unwatched_court_keeps_its_studies() -> void:
	var play: PlaySession = _play_with_spy()
	var report: Dictionary = {
		"factions": {
			2: {"resolved": {"research": {"researched": ["crop_rotation"]}}},
		},
	}
	MapPlaySpies.report(play, [], [], report)
	assert_true(play.diplomacy.events.is_empty(), "no spy, no despatch")
	play.hud.free()
	play.economy.free()


## Builds are notes: the spy counts what the court's builders begin and the
## dossier lists them without weighing an agenda (DR-20261110-25).
func test_a_shadowed_build_reads_as_a_note_not_evidence() -> void:
	var play: PlaySession = _play_with_spy()
	var report: Dictionary = {
		"factions": {
			RIVAL: {
				"civilians": {
					"orders": [
						{"action": "build_improvement"},
						{"action": "build_improvement"},
						{"action": "upgrade_town"},
						{"action": "counter_spy"},
					],
				},
			},
		},
	}
	MapPlaySpies.report(play, [], [], report)
	var notes: Dictionary = IntelDossier.report(play.diplomacy, play.world, PLAYER, RIVAL)["notes"]
	var build: Dictionary = notes["build"] as Dictionary
	assert_eq(int(build.get("improvement", 0)), 2)
	assert_eq(int(build.get("town", 0)), 1)
	assert_eq(int(notes["war"]), 0, "the build notes do not displace the behaviour counts")
	var scores: Dictionary = IntelDossier.suspicion(
		IntelDossier.evidence(play.diplomacy, play.world, PLAYER, RIVAL)
	)
	assert_true(scores.is_empty(), "a build weighs on no agenda")
	play.hud.free()
	play.economy.free()


func test_court_report_stays_readable_after_the_toast() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": RIVAL,
		"defender": PLAYER,
		"captured": true,
	}
	MapPlaySpies.report(play, [land], [], {})
	assert_eq(int(play.court_reports["turn"]), 1, "the turn that just resolved")
	assert_true((play.court_reports["shadowed"] as Array).has(RIVAL))
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq((kept[RIVAL] as Array).size(), 1, "the toast's line is kept")
	assert_eq(String((kept[RIVAL] as Array)[0]), "took Coro from Spain")
	play.hud.free()
	play.economy.free()


func test_a_despatch_is_a_page_not_a_chronicle() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = []
	for index in 12:
		play.ai_trace.append(
			{"faction": RIVAL, "message": "England word %d." % index}
		)
	MapPlaySpies.report(play, [], [], {})
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq((kept[RIVAL] as Array).size(), MapPlaySpies.MAX_LINES)
	play.hud.free()
	play.economy.free()


func test_a_stranger_court_stays_masked_in_the_despatch() -> void:
	var play: PlaySession = _play_with_spy()
	var stranger: int = 9
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": stranger,
		"defender": RIVAL,
		"captured": true,
	}
	MapPlaySpies.report(play, [land], [], {})
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq(String((kept[RIVAL] as Array)[0]), "lost Coro to Unknown faction")
	play.hud.free()
	play.economy.free()


func test_a_structured_act_masks_an_unmet_target() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = [{
		"faction": RIVAL,
		"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": 9},
		"message": "England declares war on France.",
	}]
	MapPlaySpies.report(play, [], [], {})
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq(String((kept[RIVAL] as Array)[0]), "England declares war on Unknown faction.")
	play.hud.free()
	play.economy.free()


## An order the rules refused never reached the court: a despatch that reported
## it would invent a war (wiki: civilian-units § Spy (5); issue #426).
func test_a_refused_act_is_not_reported() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = [{
		"faction": RIVAL,
		"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": 9},
		"result": {"ok": false, "reason": "No envoy has reached that court."},
		"message": "",
	}]
	MapPlaySpies.report(play, [], [], {})
	assert_true(play.hud.toasts.is_empty(), "no despatch for an act that never resolved")
	play.hud.free()
	play.economy.free()


## The despatch says what resolved, not what the planner meant: a refused peace
## reads as refused and a one-sided act keeps its own verb (issue #426).
func test_peace_and_acts_read_as_they_resolved() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = [{
		"faction": RIVAL,
		"action": {"kind": AiDiplomacyPlanner.KIND_OFFER_PEACE, "target": 9},
		"result": {"ok": true, "accepted": false},
		"message": "Unknown faction refuses a white peace.",
	}]
	MapPlaySpies.report(play, [], [], {})
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq(
		String((kept[RIVAL] as Array)[0]),
		"England sues for peace with Unknown faction and is refused."
	)
	play.ai_trace = [{
		"faction": RIVAL,
		"action": {"kind": AiDiplomacyOffers.KIND_AID, "target": 9},
		"result": {"ok": true},
		"message": "England sends aid to France.",
	}]
	MapPlaySpies.report(play, [], [], {})
	kept = play.court_reports["lines"] as Dictionary
	assert_eq(String((kept[RIVAL] as Array)[0]), "England sends aid to Unknown faction.")
	play.hud.free()
	play.economy.free()


func test_court_report_is_silent_without_a_spy() -> void:
	var play: PlaySession = _play_with_spy()
	play.civilian_layer.units.clear()
	play.ai_trace = [{"faction": RIVAL, "message": "England declares war on France."}]
	MapPlaySpies.report(play, [], [], {})
	assert_true(play.hud.toasts.is_empty())
	play.hud.free()
	play.economy.free()


# --- rules guards and dossier copy -------------------------------------------


func test_spy_rules_guards_skip_nulls_and_home_tiles() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var builder: CivilianState = CivilianState.create(
		2, PLAYER, "builder", CivilianFixture.BARE_TILE
	)
	assert_false(SpyRules.is_spy(null))
	assert_false(SpyRules.is_spy(builder))
	assert_false(SpyRules.hidden_from(null, PLAYER))
	assert_false(SpyRules.hidden_from(spy, -1))
	assert_false(SpyRules.hidden_from(spy, PLAYER))
	assert_true(SpyRules.hidden_from(spy, RIVAL))
	assert_false(SpyRules.is_foreign(null, spy))
	assert_false(SpyRules.is_foreign(model, builder))
	spy.embark_on(1)
	assert_false(SpyRules.is_foreign(model, spy))
	spy.put_ashore(Vector2i(0, 4))
	assert_eq(model.owner_at(0, 4), MapModel.NO_ID)
	assert_false(SpyRules.is_foreign(model, spy))
	assert_false(SpyRules.has_counter_spy([null, builder], PLAYER))
	assert_true(SpyRules.screened_owners(null, [spy]).is_empty())
	assert_eq(SpyRules.resolve_turn(null, [spy], 1, SEED).size(), 0)


func test_civilian_panel_names_tradecraft_and_counter_status() -> void:
	var model: MapModel = CivilianFixture.build()
	var abroad: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var screen: CivilianState = CivilianState.create(
		2, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(model, _crew_opening(abroad))
	assert_true(panel._status.text.contains("At large"))
	panel.refresh(model, _crew_opening(screen))
	assert_eq(panel._status.text, "Counter-espionage · ongoing.")
	panel.free()


## A dossier may only promise what the standing actually buys: an idle spy keeps
## no screen, and a minor court shares no research (wiki: civilian-units § Spy
## (2)–(3); DR-20261110-03). Both promises used to be unconditional.
func test_the_dossier_promises_only_what_the_standing_buys() -> void:
	var home: MapModel = CivilianFixture.build()
	var idle: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(home, _crew_opening(idle))
	assert_eq(
		_panel_row(panel, "Tradecraft"),
		"No screen up — only the counter-espionage order covers your land"
	)
	idle.start_work(SpyRules.WORK_COUNTER, idle.tile, 1)
	panel.refresh(home, _crew_opening(idle))
	var screen_row: String = _panel_row(panel, "Tradecraft")
	assert_true(
		screen_row.begins_with("Counter-espionage screen"),
		"the screen exists once the order is up"
	)
	assert_true(
		screen_row.contains("%d%% a turn to take" % SpyRules.KILL_PCT)
		and screen_row.contains("%d%% to turn one" % SpyRules.DEFECT_PCT),
		"the dossier names the trade it buys: " + screen_row
	)
	var minor_model: MapModel = CivilianFixture.build_minor()
	var minor_spy: CivilianState = CivilianState.create(
		2, PLAYER, "spy", Vector2i(2, 0)
	)
	assert_eq(minor_model.owner_at(2, 0), 6, "the fixture tile is Genoa's")
	panel.refresh(minor_model, _crew_opening(minor_spy))
	var row: String = _panel_row(panel, "Tradecraft")
	assert_true(row.contains("presence reveal only"))
	assert_false(row.contains("%"), "a minor court never shares research")
	assert_true(panel._status.text.contains("no research share"))
	panel.free()


## The work list prices the spend, so it names the prize beside it: the transport
## a road lands on the crew's own tile, printed under the button in the crown's
## gold, and no second line for the orders a ledger already prices (REQ-P5-06,
## REQ-P3-02; DR-20261117-05).
func test_the_work_order_list_names_what_the_road_lands() -> void:
	var model: MapModel = CivilianFixture.build()
	var engineer: CivilianState = CivilianState.create(1, PLAYER, "engineer", Vector2i(0, 1))
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(model, _crew_opening(engineer))
	var lines: PackedStringArray = PackedStringArray()
	for child: Node in panel._orders.get_children():
		var label := child as Label
		if label != null:
			lines.append(label.text)
	var printed: String = " | ".join(lines)
	assert_true(
		printed.contains("Transport 1 — an estate here gathers up to 1 a turn"),
		"the road's payoff prints under its price: " + printed
	)
	assert_false(
		printed.contains("soaks"),
		"the wall is priced on the walls sheet, not here: " + printed
	)
	panel.free()


## The court's own pick rides on the crew's sheet in the crown's gold, in the
## words the map layer reads — the panel invents no figure of its own, and a
## crew the planner names nothing for carries no line (REQ-P5-06, REQ-P3-02;
## DR-20261117-06).
func test_the_dossier_names_the_work_the_court_would_give_it() -> void:
	var model: MapModel = CivilianFixture.build()
	var builder: CivilianState = CivilianState.create(
		1, PLAYER, "builder", CivilianFixture.TIMBER_TILE
	)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(model, _crew_opening(builder))
	assert_false(panel._pick.visible, "no pick, no line")
	var picked := _crew_opening(builder)
	picked.context = {
		"pick": {
			"action": "build_improvement",
			"tile": CivilianFixture.TIMBER_TILE,
			"line": "the court would raise the lumber camp — L2 pays 2 timber / turn (+1)",
			"short": "raise the lumber camp",
		}
	}
	panel.refresh(model, picked)
	assert_true(panel._pick.visible, "the pick prints")
	assert_eq(
		panel._pick.text,
		"The court would raise the lumber camp — L2 pays 2 timber / turn (+1)."
	)
	panel.free()


## An idle crew with no order it can take says so: a status that says "choose an
## order below" over a list where every row is refused sends the crown hunting
## for a press that does not exist (REQ-P5-06).
func test_the_sheet_says_when_no_order_can_be_taken() -> void:
	var model: MapModel = CivilianFixture.build()
	var view: VisibilityModel = CivilianFixture.visibility(model)
	var explorer: CivilianState = CivilianState.create(
		1, PLAYER, "explorer", CivilianFixture.BARE_TILE
	)
	var panel := CivilianPanel.new()
	add_child(panel)
	var explored := _crew_opening(explorer)
	explored.visibility = view
	panel.refresh(model, explored)
	assert_eq(panel._legal, 0, "charted plains offer an Explorer nothing")
	assert_eq(panel._status.text, "Idle — no order can be taken here.")
	# A crew that does have a press keeps the standing invitation.
	var engineer: CivilianState = CivilianState.create(
		1, PLAYER, "engineer", CivilianFixture.COAST_TILE
	)
	var harboured := _crew_opening(engineer)
	harboured.visibility = view
	panel.refresh(model, harboured)
	assert_true(panel._legal > 0, "a harbour can be raised here")
	assert_eq(panel._status.text, "Idle — choose an order below.")
	panel.free()


## The plain crew dossier a test paints: the crew alone on a fresh works, with
## the fixture's stores. Tests that need fog or a pick add those fields.
func _crew_opening(unit: CivilianState) -> CivilianDossierOpening:
	var opening := CivilianDossierOpening.of(unit)
	opening.works = LandWorks.new()
	opening.units = [unit]
	opening.stockpile = CivilianFixture.stockpile()
	return opening


## The value column of one dossier row, or "" when the caption is absent.
func _panel_row(panel: CivilianPanel, caption: String) -> String:
	var children: Array[Node] = panel._detail.get_children()
	var index: int = 0
	while index + 1 < children.size():
		var key: Label = children[index] as Label
		var value: Label = children[index + 1] as Label
		if key != null and key.text == caption:
			return value.text if value != null else ""
		index += 2
	return ""


# --- fixtures ----------------------------------------------------------------


func _spy_pair() -> Array[CivilianState]:
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var screen: CivilianState = CivilianState.create(
		2, RIVAL, "spy", Vector2i(4, 0)
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	var units: Array[CivilianState] = [spy, screen]
	return units


func _find_rolls(model: MapModel) -> Dictionary:
	var kill: int = -1
	var defect: int = -1
	for turn in range(1, 2000):
		var units: Array[CivilianState] = _spy_pair()
		for event: Dictionary in SpyRules.resolve_turn(model, units, turn, SEED):
			if String(event["kind"]) == "killed" and kill < 0:
				kill = turn
			elif String(event["kind"]) == "defected" and defect < 0:
				defect = turn
		if kill > 0 and defect > 0:
			break
	return {"kill": kill, "defect": defect}


## Two regions on one session: the player's counter-espionage screen stands at
## home (region 0) while an enemy spy holds the player's colonial province in
## region 1.
func _two_region_play() -> PlaySession:
	var first: MapModel = CivilianFixture.build()
	first.region_id = 0
	var second: MapModel = CivilianFixture.build()
	second.region_id = 1
	var world := WorldMap.new()
	world.add_region(first)
	world.add_region(second)
	var layer := CivilianLayer.new()
	layer.spawn(first, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	var screen: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	layer.units.append(screen)
	layer.regions.set_region(0, layer.units)
	var intruder: CivilianState = CivilianState.create(
		2, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var region_one: Array[CivilianState] = [intruder]
	layer.regions.set_region(1, region_one)
	var play := PlaySession.new()
	play.player_faction = PLAYER
	play.world = world
	play.model = first
	play.region_index = 0
	play.civilian_layer = layer
	play.map_seed = SEED
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	return play


func _play_with_spy() -> PlaySession:
	var model: MapModel = CivilianFixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	layer.add_unit(PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE)
	var play := PlaySession.new()
	play.player_faction = PLAYER
	play.world = world
	play.model = model
	play.region_index = model.region_id
	play.civilian_layer = layer
	play.map_seed = SEED
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	play.ai = AiState.new()
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()
	play.economy = controller
	play.hud = StubHud.new()
	add_child(play.hud)
	return play


func _context() -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": CivilianFixture.BARE_TILE,
		"at_war": false,
	}

# ==== merged from test_court_ui_parts.gd (one coverage boot; docs/testing.md § Speed rules) ====
## One boot for the small UI parts that mount no chart: court reports and dossier,
## toasts, the panel dock, ledger text/helpers and the civilian layer parts.

## Merged from test_court_reports, test_court_dossier_screen, test_hud_toast,
## test_panel_dock, test_ledger_text, test_ledger_helpers, test_civilian_layer_parts,
## test_unit_icons, test_menu_door.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const court_Fixture = preload("res://tests/civilian_fixture.gd")

const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6
const court_dossier_screen_VIEWER: int = 0
const court_dossier_screen_ENGLAND: int = 1
const court_dossier_screen_GENOA: int = 6
const LINE := "France holds Burgundy — 2 of 2 emplaced guns silenced"
const TEMP_PATH := "user://test_panel_dock.cfg"

var _hud: GameHud = null

var court__suite_setup: String = ""

func _court_after_each() -> void:
	match court__suite_setup:
		"hud_toast":
			_teardown_hud_toast()
		"panel_dock":
			_teardown_panel_dock()
	court__suite_setup = ""

func _setup_hud_toast() -> void:
	court__suite_setup = "hud_toast"
	_hud = GameHud.new()
	add_child(_hud)

func _setup_panel_dock() -> void:
	court__suite_setup = "panel_dock"
	pass

func _setup_unit_icons() -> void:
	court__suite_setup = "unit_icons"
	pass

func _teardown_hud_toast() -> void:
	if is_instance_valid(_hud):
		_hud.free()
	_hud = null

func _teardown_panel_dock() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))

# --- test_court_reports ---

func _reports(lines: Array, shadowed: Array = [ENGLAND]) -> Dictionary:
	return {"turn": 4, "shadowed": shadowed, "lines": {ENGLAND: lines}}

func test_a_shadowed_court_shows_the_kept_despatch() -> void:
	var panel := CourtReportsPanel.new()
	add_child(panel)
	panel.fill(ENGLAND, _reports(["took Coro from Spain", "finished Crop Rotation"]))
	assert_true(court__has_text(panel, "COURT REPORTS"), "the block names itself")
	assert_true(court__has_text(panel, "Turn 4"), "and stamps the turn")
	assert_true(court__has_text(panel, "took Coro from Spain"))
	assert_true(court__has_text(panel, "finished Crop Rotation"))
	panel.free()

func test_an_unwatched_court_shows_no_block() -> void:
	var panel := CourtReportsPanel.new()
	add_child(panel)
	panel.fill(GENOA, _reports(["took Coro from Spain"]))
	assert_eq(panel.get_child_count(), 0, "no spy, no section")
	panel.free()

func test_a_quiet_court_says_so() -> void:
	var panel := CourtReportsPanel.new()
	add_child(panel)
	panel.fill(ENGLAND, _reports([]))
	assert_true(court__has_text(panel, CourtReportsPanel.QUIET_LINE))
	panel.free()

func test_the_court_panel_carries_the_despatch_for_the_selected_crown() -> void:
	var state := DiplomacyState.new()
	state.initialize(1)
	var panel := DiplomacyPanel.new()
	add_child(panel)
	panel.refresh(state, null, VIEWER, 2500, {}, _reports(["took Coro from Spain"]))
	panel.select_faction(ENGLAND)
	assert_true(court__has_text(panel._detail, "COURT REPORTS"))
	assert_true(court__has_text(panel._detail, "took Coro from Spain"))
	panel.select_faction(GENOA)
	assert_false(court__has_text(panel._detail, "COURT REPORTS"), "Genoa has no spy")
	panel.free()

func court__has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if court__has_text(child, needle):
			return true
	return false

# --- test_court_dossier_screen ---

func court__state() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.initialize(1)
	return state

func _screen(state: DiplomacyState, subject: int) -> CourtDossierScreen:
	var screen := CourtDossierScreen.new()
	add_child(screen)
	screen.show_for(state, null, court_dossier_screen_VIEWER, subject)
	return screen

func test_the_sheet_reads_every_section_in_order() -> void:
	var state: DiplomacyState = court__state()
	DiplomacyRules.declare_war(state, court_dossier_screen_ENGLAND, court_dossier_screen_GENOA)
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	assert_true(screen.is_open(), "the sheet is up")
	assert_true(_court_dossier_screen_has_text(screen, "THE DOSSIER"))
	assert_true(_court_dossier_screen_has_text(screen, "England"), "the court is named")
	assert_true(_court_dossier_screen_has_text(screen, "SUSPICION"))
	assert_true(_court_dossier_screen_has_text(screen, "TIMELINE"))
	assert_true(_court_dossier_screen_has_text(screen, "BEHAVIOUR & BUILD NOTES"))
	assert_true(_court_dossier_screen_has_text(screen, "Reading:"), "the best guess leads")
	assert_true(_court_dossier_screen_has_text(screen, "Warmonger"), "every agenda is listed, banded or not")
	assert_true(_court_dossier_screen_has_text(screen, "Declared war on Genoa."), "the act reaches the page")
	screen.free()

func test_the_reading_names_the_band_never_the_agenda_truth() -> void:
	var state: DiplomacyState = court__state()
	for _index in 4:
		state.record_event("warDeclared", court_dossier_screen_ENGLAND, court_dossier_screen_GENOA)
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	assert_true(_court_dossier_screen_has_text(screen, "Likely 60%"), "the band and its confidence are printed")
	assert_false(_court_dossier_screen_has_text(screen, "Confirmed 100%"), "nothing is certain at four acts")
	screen.free()

## The strongest reading starts open; every other row opens on a press, so the
## sheet reads as a table first and a story second.
func test_an_agenda_row_toggles_its_own_timeline() -> void:
	var state: DiplomacyState = court__state()
	DiplomacyRules.declare_war(state, court_dossier_screen_ENGLAND, court_dossier_screen_GENOA)
	state.record_event("grantAid", court_dossier_screen_ENGLAND, court_dossier_screen_GENOA, {"amount": 100})
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	var pacifist: Button = _agenda_button(screen, "Peacemaker")
	assert_not_null(pacifist, "the quieter reading still has a row")
	assert_true(pacifist.text.begins_with("▸"), "a quiet agenda starts folded")
	pacifist.pressed.emit()
	assert_true(pacifist.text.begins_with("▾"), "a press unfolds its timeline")
	screen.free()

func test_a_quiet_court_says_so_instead_of_showing_an_empty_sheet() -> void:
	var screen: CourtDossierScreen = _screen(court__state(), court_dossier_screen_GENOA)
	assert_true(_court_dossier_screen_has_text(screen, "no act has yet spoken"), "the reading says it plainly")
	assert_true(_court_dossier_screen_has_text(screen, "No observable act has been written down."))
	assert_true(_court_dossier_screen_has_text(screen, "No observable act feeds this reading yet."))
	screen.free()

func test_the_build_notes_name_what_a_spy_watched() -> void:
	var state: DiplomacyState = court__state()
	state.record_event(
		IntelEvidence.SPY_BUILD, court_dossier_screen_ENGLAND, court_dossier_screen_VIEWER, {"works": {"improvement": 2, "town": 1}}
	)
	state.record_event(IntelEvidence.SPY_TECH, court_dossier_screen_ENGLAND, court_dossier_screen_VIEWER, {"tech": "crop_rotation"})
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	assert_true(_court_dossier_screen_has_text(screen, "Under your spy's eye"), "the sightings are listed")
	assert_true(_court_dossier_screen_has_text(screen, "2 estates"))
	assert_true(_court_dossier_screen_has_text(screen, "1 town finished"))
	assert_true(_court_dossier_screen_has_text(screen, "1 finished study"))
	assert_true(_court_dossier_screen_has_text(screen, "Finished Crop Rotation while our spy watched."))
	screen.free()

func test_close_dismisses_the_sheet() -> void:
	var screen: CourtDossierScreen = _screen(court__state(), court_dossier_screen_ENGLAND)
	screen.close()
	assert_false(screen.is_open())
	screen.free()

func _agenda_button(screen: CourtDossierScreen, label: String) -> Button:
	for child: Node in screen._body.get_children():
		if child is Button and String((child as Button).text).contains(label):
			return child as Button
	return null

func _court_dossier_screen_has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _court_dossier_screen_has_text(child, needle):
			return true
	return false

# --- test_hud_toast ---

func test_a_plain_toast_keeps_its_single_label() -> void:
	_setup_hud_toast()
	_hud.toast("The turn opens")
	var panel: Control = _hud.despatches.box.get_child(0)
	assert_eq(panel.get_child_count(), 1)
	var label: Label = panel.get_child(0) as Label
	assert_true(label != null)
	assert_eq(label.text, "The turn opens")

func test_a_siege_toast_carries_the_silenced_battery_medallion() -> void:
	_setup_hud_toast()
	_hud.toast(LINE, "silenced_gun")
	var panel: Control = _hud.despatches.box.get_child(0)
	var row: HBoxContainer = panel.get_child(0) as HBoxContainer
	assert_true(row != null, "the medallion sits in a row with its line")
	var medallion: TextureRect = row.get_child(0) as TextureRect
	assert_true(medallion != null)
	assert_true(medallion.texture != null, "the icon asset is imported")
	assert_eq(medallion.custom_minimum_size, Vector2(26.0, 26.0))
	var label: Label = row.get_child(1) as Label
	assert_true(label != null)
	assert_eq(label.text, LINE)

func test_a_hidden_hud_keeps_no_toast_plates() -> void:
	_setup_hud_toast()
	_hud.visible = false
	_hud.toast(LINE, "silenced_gun")
	assert_eq(_hud.despatches.box.get_child_count(), 0)

## The lane is the despatches' alone: the HUD keeps no copy, so unmounting it
## leaves nothing to read, and a missing battle plate never queues a fight
## (REQ-P3-01, REQ-P5-06).
func test_a_lane_less_hud_stays_quiet() -> void:
	_setup_hud_toast()
	assert_not_null(_hud.despatches.box)
	assert_eq(_hud.despatches.waiting().size(), 0)
	_hud.despatches = null
	_hud.toast("silence")
	# The plate is still mounted: the guard's second term is what refuses.
	_hud.show_quick_battle({"rounds": []}, "Flanders")
	assert_true(_hud._quick_queue.is_empty())
	# The guard reads the plates' handle, not the view node (BattlePlates since
	# the sea despatch landed), so the missing plate is unmounted there.
	_hud.plates.land_plate = null
	_hud.show_quick_battle({"rounds": []}, "Flanders")
	assert_true(_hud._quick_queue.is_empty())

## News raised under a plate waits, the oldest lines drop past the cap, and
## the last plate of the turn prints what remains (REQ-P5-06).
func test_news_waits_out_the_plate_and_the_oldest_lines_drop() -> void:
	_setup_hud_toast()
	var battle := {"attacker": 0, "defender": 1, "outcome": 0}
	_hud.show_quick_battle(battle, "Flanders")
	_hud.toast("under the plate")
	assert_eq(_hud.despatches.waiting().size(), 1)
	assert_eq(_hud.despatches.held().size(), 1)
	for index in HudDespatches.TOAST_QUEUE_CAP + 2:
		_hud.toast("news %d" % index)
	assert_eq(_hud.despatches.held().size(), HudDespatches.TOAST_QUEUE_CAP)
	assert_eq(String(_hud.despatches.held()[0]), "news 2", "the oldest lines go first")
	_hud.quick_battle_overlay.skip()
	_hud.quick_battle_overlay._on_continue()
	assert_false(_hud.is_quick_battle_shown())
	assert_gt(_hud.despatches.box.get_child_count(), 0, "held news reaches the court")

# --- test_panel_dock ---

func test_defaults_to_right() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	assert_eq(dock.side, PanelDock.Side.RIGHT)
	assert_false(dock.is_left())

func test_toggle_flips_side() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	assert_eq(dock.toggle(), PanelDock.Side.LEFT)
	assert_eq(dock.toggle(), PanelDock.Side.RIGHT)

func test_save_and_load_round_trip() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	assert_true(dock.save(TEMP_PATH))

	var fresh := PanelDock.new()
	assert_true(fresh.load_from(TEMP_PATH))
	assert_eq(fresh.side, PanelDock.Side.LEFT)

func test_missing_file_keeps_default() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	assert_false(dock.load_from("user://definitely_not_panel_dock.cfg"))
	assert_eq(dock.side, PanelDock.Side.RIGHT)

func test_right_shown_offsets_match_legacy_panel() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	var wrap := Control.new()
	add_child(wrap)
	dock.place_shown(wrap)
	assert_eq(wrap.offset_left, -(PanelDock.WIDTH + PanelDock.MARGIN))
	assert_eq(wrap.offset_right, -PanelDock.MARGIN)
	wrap.free()

func test_left_shown_offsets_clear_the_margin() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	var wrap := Control.new()
	add_child(wrap)
	dock.place_shown(wrap)
	assert_eq(wrap.offset_left, PanelDock.MARGIN)
	assert_eq(wrap.offset_right, PanelDock.MARGIN + PanelDock.WIDTH)
	wrap.free()

func test_prepare_wrap_uses_left_anchors_when_docked_left() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	var wrap := Control.new()
	add_child(wrap)
	dock.prepare_wrap(wrap)
	assert_eq(wrap.anchor_left, 0.0)
	assert_eq(wrap.anchor_right, 0.0)
	assert_eq(wrap.offset_left, PanelDock.MARGIN - PanelDock.WIDTH)
	wrap.free()

## A show right after a hide must cancel the outgoing slide: its callback would
## otherwise park the panel off screen while the dossier reports it open.
func test_a_slide_in_cancels_a_running_slide_out() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	var host := Node.new()
	add_child(host)
	var wrap := Control.new()
	host.add_child(wrap)
	dock.prepare_wrap(wrap)
	dock.slide_out(host, wrap, func() -> void: wrap.visible = false)
	var outgoing: Tween = wrap.get_meta(PanelDock.SLIDE_KEY)

	dock.slide_in(host, wrap)

	assert_false(outgoing.is_valid(), "the slide-out tween is killed")
	assert_true(wrap.visible)
	assert_ne(wrap.get_meta(PanelDock.SLIDE_KEY), outgoing)
	host.free()

# --- test_ledger_text ---

func test_a_quiet_market_prints_nothing() -> void:
	assert_eq(LedgerMarketText.market_summary({}, 0), "")

## The disband row promises no refund and names what the tier eats
## (wiki: workers-and-population § Disband, § Tiers).
func test_the_disband_hint_names_the_promise_and_the_saving() -> void:
	var hint: String = LedgerWorkersText.disband_hint(WorkerPool.Tier.APPRENTICE)
	assert_true(hint.contains("no recruit cost is refunded"), hint)
	assert_true(hint.contains("An apprentice eats 2 food"), hint)
	assert_true(hint.contains("a unit of Refined Sugar"), hint)
	var master: String = LedgerWorkersText.disband_hint(WorkerPool.Tier.MASTER)
	assert_true(master.contains("A master eats 2 food and a unit of Fur Hats"), master)

## The recruit row's line is the price plus one clause: the study a locked tier
## waits on, the rule that stops it, or the ration it eats
## (wiki: workers-and-population § Recruiting, § Tech gates, § Worker Tiers).
func test_the_workers_row_names_its_price_and_its_clause() -> void:
	var none: Array[String] = []
	var two: Array[String] = ["apprentice_workers", "sugar_refining"]
	var three: Array[String] = ["apprentice_workers", "sugar_refining", "university"]
	assert_eq(LedgerWorkersText.recruit_price(WorkerPool.Tier.PEASANT), "Recruit Fabric ×2")
	assert_eq(
		LedgerWorkersText.recruit_price(WorkerPool.Tier.MASTER), "Recruit 1000 ducats · Paper ×10"
	)
	assert_eq(
		LedgerWorkersText.ration_line(WorkerPool.Tier.PEASANT), "eats 1 grain or meat a turn"
	)
	assert_eq(
		LedgerWorkersText.ration_line(WorkerPool.Tier.MASTER),
		"eats 1 grain + 1 meat and Fur Hats a turn"
	)
	assert_eq(LedgerWorkersText.gate_line(two), "needs Apprentice Workers and Sugar Refining")
	assert_eq(LedgerWorkersText.gate_line(none), "", "no gate, no clause")
	var one: Array[String] = ["university"]
	assert_eq(LedgerWorkersText.gate_line(one), "needs University", "one gate reads alone")
	assert_eq(
		LedgerWorkersText.gate_line(three),
		"needs Apprentice Workers, Sugar Refining and University",
		"three gates still read as one clause"
	)
	assert_eq(
		LedgerWorkersText.recruit_line(WorkerPool.Tier.APPRENTICE, "", two),
		"Recruit 200 ducats · Paper ×2 — needs Apprentice Workers and Sugar Refining"
	)
	assert_eq(
		LedgerWorkersText.recruit_line(WorkerPool.Tier.PEASANT, "Insufficient treasury", none),
		"Recruit Fabric ×2 — insufficient treasury"
	)
	assert_eq(
		LedgerWorkersText.recruit_line(WorkerPool.Tier.JOURNEYMAN, "", none),
		"Recruit 500 ducats · Paper ×5 — eats 1 grain + 1 meat and Cigars a turn"
	)
	# The gate query reads the same table the order checks.
	var unlocked: Dictionary = {"master_artisans": true}
	var missing: Array[String] = WorkerPool.missing_techs(WorkerPool.Tier.MASTER, unlocked)
	assert_eq(missing.size(), 1, "one study still stands")
	assert_eq(missing[0], "hat_production")

func test_fills_carry_and_lapse_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"bought": 2, "spent": 60, "sold": 1}},
		"carry": [{"commodity": "timber"}],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 0,
			"commodity": "grain",
		}],
	}
	var line: String = LedgerMarketText.market_summary(report, 0)
	assert_true(line.contains("bought 2 for 60 ducats"))
	assert_true(line.contains("sold 1"))
	assert_true(line.contains("1 order carried"))
	assert_true(line.contains("1 order lapsed"))

## A sale names the ducats it paid, and the overseas share is named even when
## the court traded nothing itself: the auction is the purse movement the
## per-turn figure cannot project (wiki: world-market § Trade orders, § First
## right of refusal).
func test_a_sale_and_an_overseas_share_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"sold": 1, "earned": 50}},
		"credits": {"by_gp": {0: 89.4}},
		"carry": [],
		"notes": [],
	}
	var line: String = LedgerMarketText.market_summary(report, 0)
	assert_true(line.contains("sold 1 for 50 ducats"), line)
	assert_true(line.contains("89 ducats in shares"), line)
	# A court with no fills of its own still reads its share.
	var quiet: Dictionary = {"fills": {}, "credits": {"by_gp": {0: 12.0}}}
	assert_true(
		LedgerMarketText.market_summary(quiet, 0).contains("12 ducats in shares"),
		LedgerMarketText.market_summary(quiet, 0),
	)
	assert_eq(LedgerMarketText.share_credit({"credits": {0: 7.6}}, 0), 8, "a bare map is read too")

## The "Next turn" promise names the orders that settle after it, so a staged
## order is never read as already counted (wiki: stockpiles-and-production
## § Production flow — the auction clears after Production).
func test_the_preview_names_the_auction_it_excludes() -> void:
	var staged: Dictionary = {
		"stockpile_delta": {"grain": 3},
		"treasury_delta": 0,
		"staged_orders": 2,
	}
	var line: String = LedgerMarketText.preview(staged)
	assert_true(line.contains("Grain +3"), line)
	assert_true(line.contains("2 orders settle at the auction"), line)
	var one: Dictionary = {"stockpile_delta": {}, "treasury_delta": 0, "staged_orders": 1}
	assert_true(
		LedgerMarketText.preview(one).contains("1 order settles at the auction"),
		LedgerMarketText.preview(one),
	)
	# Nothing staged: the calm line stays exactly as it was.
	assert_eq(
		LedgerMarketText.preview({"stockpile_delta": {}, "treasury_delta": 0}),
		"Next turn: no stock changes.",
	)

func test_another_courts_lapse_is_not_ours() -> void:
	var report: Dictionary = {
		"fills": {},
		"carry": [],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 1,
			"commodity": "grain",
		}],
	}
	assert_eq(LedgerMarketText.market_summary(report, 0), "")

# --- test_ledger_helpers ---

func test_thousands_groups_and_keeps_the_sign() -> void:
	assert_eq(TextFormat.thousands(0), "0")
	assert_eq(TextFormat.thousands(999), "999")
	assert_eq(TextFormat.thousands(1000), "1,000")
	assert_eq(TextFormat.thousands(1234567), "1,234,567")
	assert_eq(TextFormat.thousands(-1234), "-1,234")

func test_recipe_title_names_the_single_input() -> void:
	var recipe_id: String = ProductionRecipes.available_ids({})[0]
	var title: String = LedgerProductionText.recipe_title(recipe_id)
	assert_true(title.contains(CommodityCatalog.label(ProductionRecipes.output(recipe_id))))
	assert_true(LedgerProductionText.recipe_tooltip(recipe_id).contains("→"))

func test_production_gate_copy_names_town_then_hand() -> void:
	assert_true(
		LedgerProductionText.gate_note("garments", 0).contains("level-2 town"),
		"a garments row waits on the town's works first"
	)
	assert_true(
		LedgerProductionText.gate_tooltip("garments", 0).contains("TOWNS sheet"),
		"the long form points at the TOWNS sheet"
	)
	assert_true(
		LedgerProductionText.gate_note("cigars", 0).contains("Apprentice"),
		"a cigar row names the hand it needs when the town is open"
	)
	assert_true(
		LedgerProductionText.gate_tooltip("cigars", 0).contains("WORKERS tab"),
		"the long form points at the WORKERS tab"
	)


func test_manufacture_hint_remembers_last_phase() -> void:
	assert_false(
		LedgerProductionText.manufacture_hint(0).contains("Last phase"),
		"an idle workshop adds no memory"
	)
	assert_true(
		LedgerProductionText.manufacture_hint(1).contains("made 1 good."),
		"one good stays singular"
	)
	assert_true(
		LedgerProductionText.manufacture_hint(3).contains("made 3 goods."),
		"several goods take the plural"
	)


func test_recipes_for_output_put_ungated_first() -> void:
	var rows: Array[String] = LedgerProductionText.recipes_for_output("fabric", {})
	assert_false(rows.is_empty(), "wool weave is always known")
	assert_true(
		ProductionRecipes.required_tech(rows[0]).is_empty(),
		"the always-available weave sits at the top"
	)


func test_workshop_row_note_names_last_output() -> void:
	var economy: PlayerEconomy = PlayerEconomy.new()
	assert_eq(LedgerWorkshop.row_note(economy, "lumber"), "", "idle one-turn rows stay blank")
	economy.production.set_made({"lumber": 2})
	assert_eq(
		LedgerWorkshop.row_note(economy, "lumber"), "made 2",
		"an idle row that worked last phase says so"
	)
	assert_true(
		LedgerWorkshop.row_tooltip(economy, "lumber").contains("Last phase it made 2"),
		"the long form names the good"
	)

func test_the_summary_reads_the_report() -> void:
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.treasury = 1234
	var report: Dictionary = {
		"consumption": {"idle_labour": 3, "strikers": 2, "navy_demand": 5},
	}
	var line: String = LedgerReportText.summary(economy, report)
	assert_true(line.contains("1,234 ducats"))
	assert_true(line.contains("labour 3 /"))
	assert_true(line.contains("strikes 2"))

func test_the_preview_reports_deltas_or_calm() -> void:
	assert_eq(LedgerMarketText.preview({}), "Next turn: no stock changes.")
	var line: String = LedgerMarketText.preview(
		{"stockpile_delta": {"grain": 3}, "treasury_delta": -10}
	)
	assert_true(line.contains("+3"))
	assert_true(line.contains("ducats -10"))

func test_the_cargo_banner_covers_three_states() -> void:
	assert_true(LedgerMarketText.cargo_line({}).contains("unknown"))
	var empty: Dictionary = {"holds": 0, "free": 0}
	assert_true(LedgerMarketText.cargo_line(empty).contains("No cargo holds"))
	assert_eq(LedgerMarketText.cargo_color(empty), Palette.GOLD_PALE)
	var laden: Dictionary = {"holds": 4, "free": 1}
	assert_true(LedgerMarketText.cargo_line(laden).contains("4 holds"))
	assert_eq(LedgerMarketText.cargo_color(laden), Palette.TEXT)

func test_report_counters_default_to_zero() -> void:
	assert_eq(LedgerReportText.idle_labour({}), 0)
	assert_eq(LedgerReportText.navy_food({"consumption": {"navy_demand": 7}}), 7)

func _group(id: int, name: String, rows: Array) -> Dictionary:
	var producing: int = 0
	for row: Dictionary in rows:
		if int(row.get("output", 0)) > 0:
			producing += 1
	return {"id": id, "name": name, "rows": rows, "producing": producing}

func _rows() -> Array:
	return [
		{"output": 2, "working": false, "status": "producing"},
		{"output": 0, "working": true, "status": "building"},
		{"output": 0, "working": false, "status": "vacant"},
		{"output": 0, "working": false, "status": "disconnected"},
	]

func test_groups_keep_province_order_and_merge_duplicates() -> void:
	var snapshot: Dictionary = {
		"groups": [
			_group(4, "OLD", _rows().slice(0, 2)),
			_group(4, "OLD", _rows().slice(2)),
			_group(9, "NEW", _rows().slice(0, 1)),
		],
	}
	var groups: Array[Dictionary] = EstateLedger.grouped(snapshot)
	assert_eq(groups.size(), 2)
	assert_eq(groups[0]["name"], "OLD")
	assert_eq((groups[0]["rows"] as Array).size(), 4)

func test_province_filter_keeps_one_group() -> void:
	var groups: Array[Dictionary] = EstateLedger.grouped(
		{"groups": [_group(1, "A", _rows()), _group(2, "B", _rows())]}
	)
	assert_eq(EstateLedger.in_province(groups, -1).size(), 2)
	assert_eq(EstateLedger.in_province(groups, 2).size(), 1)

func test_each_filter_selects_its_rows() -> void:
	var rows: Array = _rows()
	assert_eq(EstateLedger.matching(rows, "all").size(), 4)
	assert_eq(EstateLedger.matching(rows, "producing").size(), 1)
	assert_eq(EstateLedger.matching(rows, "building").size(), 1)
	assert_eq(EstateLedger.matching(rows, "vacant").size(), 1)
	assert_eq(EstateLedger.matching(rows, "issues").size(), 1)

func test_total_output_sums_every_yield() -> void:
	assert_eq(EstateLedger.total_output({"lumber": 2, "iron": 3}), 5)
	assert_eq(EstateLedger.total_output({}), 0)

func test_row_builder_builds_themed_widgets() -> void:
	var row: HBoxContainer = UiRowBuilder.row(38.0)
	assert_eq(row.custom_minimum_size.y, 38.0)
	var label: Label = UiRowBuilder.label("hi", 14, Palette.TEXT)
	assert_eq(label.text, "hi")
	var caption: Label = UiRowBuilder.caption("x", 10, Palette.TEXT_DIM, 44.0)
	assert_eq(caption.custom_minimum_size.x, 44.0)
	var button: Button = UiRowBuilder.button("Go", 38.0, 70.0)
	assert_eq(button.text, "Go")
	assert_eq(button.custom_minimum_size, Vector2(70, 38))
	row.free()
	label.free()
	caption.free()
	button.free()

func test_clear_empties_a_container() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	UiRowBuilder.spacer(box)
	box.add_child(UiRowBuilder.label("gone", 12, Palette.TEXT))
	box.add_child(UiRowBuilder.label("gone too", 12, Palette.TEXT))
	assert_eq(box.get_child_count(), 3)
	UiRowBuilder.clear(box)
	assert_eq(box.get_child_count(), 0)
	box.queue_free()

# --- test_civilian_layer_parts ---

func test_capital_tile_prefers_the_seat() -> void:
	var model: MapModel = court_Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	assert_true(seat.x >= 0)
	assert_true(model.is_land(seat.x, seat.y))

func test_capital_tile_guards_and_falls_back() -> void:
	assert_eq(CivilianPlacement.capital_tile(null, 0), Vector2i(-1, -1))
	var model: MapModel = court_Fixture.build()
	assert_eq(CivilianPlacement.capital_tile(model, 99), Vector2i(-1, -1))
	var data: ProvinceState = model.province_data(0)
	data.capital_tile = Vector2i(-1, -1)
	var fallback: Vector2i = CivilianPlacement.capital_tile(model, 0)
	assert_eq(fallback, model.province_tiles(0)[0])

func test_mustering_tile_keeps_the_seat_clear() -> void:
	var model: MapModel = court_Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [], 0)
	assert_true(tile.x >= 0)
	assert_ne(tile, seat, "fresh crews leave the capital seat readable")

func test_spies_and_nulls_do_not_block_mustering() -> void:
	var model: MapModel = court_Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var taken: Dictionary = {seat: true}
	var open: Vector2i = CivilianPlacement.free_tile(model, 0, seat, taken)
	assert_true(open.x >= 0)
	var spy := CivilianState.create(1, 0, SpyRules.TYPE, open)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [null, spy], 0)
	assert_eq(tile, open, "a spy's tile stays free for mustering")
	assert_eq(CivilianPlacement.free_tile(null, 0, seat, {}), Vector2i(-1, -1))
	assert_eq(CivilianPlacement.mustering_tile(null, [], 0), Vector2i(-1, -1))

func test_a_full_province_reclaims_the_seat() -> void:
	var model: MapModel = court_Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var units: Array[CivilianState] = []
	var id: int = 1
	for tile: Vector2i in model.province_tiles(0):
		if tile == seat:
			continue
		units.append(CivilianState.create(id, 0, "builder", tile))
		id += 1
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, units, 0)
	assert_eq(tile, seat, "when every other tile is taken the seat musters")

func test_turn_pass_restores_moves_on_every_region() -> void:
	var model: MapModel = court_Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var explorer: CivilianState = layer.add_unit(0, "explorer", Vector2i(1, 1))
	layer.regions.set_region(model.region_id, layer.units)
	assert_true(bool(CivilianMovement.apply_move(model, explorer, Vector2i(2, 1))["ok"]))
	assert_true(explorer.moved)
	CivilianTurnPass.resolve(layer, world, null)
	assert_false(explorer.moved, "the pass restores moves without the layer")
	layer.free()

func test_turn_pass_guards_and_offscreen_rosters() -> void:
	assert_eq(CivilianTurnPass.resolve(null, null, null).size(), 0)
	var home: MapModel = court_Fixture.build()
	var away: MapModel = court_Fixture.build()
	away.region_id = 1
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(away)
	var layer := CivilianLayer.new()
	layer.spawn(home, 0, 0, [], false)
	var idle: CivilianState = CivilianState.create(9, 0, "explorer", Vector2i(1, 1))
	idle.moved = true
	var remote: Array[CivilianState] = [null, idle]
	layer.regions.set_region(1, remote)
	CivilianTurnPass.resolve(layer, world, null)
	assert_false(idle.moved, "an off-screen crew still gets its move back")
	layer.free()

func test_paint_covers_mines_woods_riches_and_ports() -> void:
	LandWorksPaint.paint(null, null, null, 22.0)
	var model: MapModel = court_Fixture.build()
	var works := LandWorks.new()
	works.set_improvement(model, court_Fixture.IRON_TILE, 2)
	works.set_improvement(model, court_Fixture.TIMBER_TILE, 1)
	var gold := Vector2i(2, 2)
	model.resource[model.index_of(gold.x, gold.y)] = 3
	works.set_improvement(model, gold, 1)
	var farm := Vector2i(0, 1)
	model.resource[model.index_of(farm.x, farm.y)] = 4
	works.set_improvement(model, farm, 1)
	works.add_port(model, court_Fixture.COAST_TILE)
	var layer := CivilianLayer.new()
	add_child(layer)
	layer.model = model
	layer.works = works
	layer.queue_redraw()
	await get_tree().process_frame
	layer.free()


# --- the HUD's despatches and unit medallions (from test_ui_rules) ---
## Toast plates, the plaque handles the playtests read, the quick-battle
## queue, and one carved medallion per worker, hull and regiment
## (REQ-P1-02, REQ-P5-05, DR-20261110-22).

func test_the_hud_keeps_a_read_only_view_of_its_despatches() -> void:
	_setup_hud_toast()
	_hud.toast("The turn opens")
	assert_eq(_hud.despatches.box.get_child_count(), 1)
	assert_true(_hud.despatches.waiting().is_empty(), "a raised line is not still waiting")


## Drives reach the plaques through the chips the bar mounts, and the HUD keeps
## no forwarding copy of any reading (REQ-P1-02, REQ-P3-01).

func test_the_chips_hold_the_plaques_and_the_hud_only_mounts_them() -> void:
	_setup_hud_toast()
	_hud.stats.set_treasury(900, false)
	_hud.stats.set_income(0)
	_hud.stats.set_fleets(2)
	_hud.stats.set_civilians(1)
	_hud.stats.set_armies(4)
	assert_eq(_hud.stats._treasury_value, 900)
	assert_eq(_hud.stats.treasury_label.text, "900")
	assert_eq(_hud.stats.fleet_label.text, "2")
	assert_eq(_hud.stats.army_label.text, "4")
	_hud.stats = null
	assert_false(_has_property(_hud, "_treasury_label"), "the HUD keeps no plaque copy")
	assert_false(_has_property(_hud, "_army_chip"), "nor a chip copy")
	assert_false(_has_property(_hud, "_toast_box"), "nor a despatch lane copy")


## Whether an object still declares a property by that name.
func _has_property(obj: Object, name: String) -> bool:
	for entry: Dictionary in obj.get_property_list():
		if String(entry.get("name", "")) == name:
			return true
	return false


## Unbound plaques refuse to paint; a missing battle plate never queues a fight.

func test_unbound_plaques_and_a_missing_battle_plate_stay_quiet() -> void:
	_setup_hud_toast()
	var chips := HudStatChips.new()
	chips.set_treasury(1)
	chips.set_income(1)
	chips.set_fleets(1)
	chips.set_civilians(1)
	chips.set_armies(1)
	chips.flash_income(1)
	chips._refresh_treasury_tooltip()
	_hud.quick_battle_overlay = null
	assert_false(_hud.is_quick_battle_shown())
	_hud.show_quick_battle({"rounds": []}, "Flanders")
	assert_true(_hud._quick_queue.is_empty())


## A second fight of the turn waits behind the plate; closing it releases held news.

func test_a_second_battle_waits_then_releases_held_news() -> void:
	_setup_hud_toast()
	var battle := {"attacker": 0, "defender": 1, "outcome": 0}
	_hud.show_quick_battle(battle, "Flanders")
	assert_true(_hud.is_quick_battle_shown())
	_hud.toast("news under the plate")
	_hud.show_quick_battle(battle, "Burgundy")
	assert_eq(_hud._quick_queue.size(), 1)
	_hud.quick_battle_overlay.skip()
	_hud.quick_battle_overlay._on_continue()
	assert_true(_hud.is_quick_battle_shown(), "the queued fight takes the plate")
	_hud.quick_battle_overlay.skip()
	_hud.quick_battle_overlay._on_continue()
	assert_false(_hud.is_quick_battle_shown())
	assert_eq(_hud.despatches.box.get_child_count(), 1, "held news reaches the court")


# --- merged from tests/test_panel_dock.gd ---


## Left/right selection-dossier dock persistence and layout (REQ-P1 / P3).

func test_court_every_worker_type_ships_a_medallion() -> void:
	_setup_unit_icons()
	var missing: Array[String] = []
	for type_id: String in CivilianCatalog.ORDER:
		if CivilianArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "workers without a plate: %s" % ", ".join(missing))

func test_court_every_hull_ships_a_medallion() -> void:
	_setup_unit_icons()
	var missing: Array[String] = []
	for type_id: Variant in ShipStats.STATS.keys():
		if ShipArt.medallion(String(type_id)) == null:
			missing.append(String(type_id))
	assert_eq(missing.size(), 0, "hulls without a plate: %s" % ", ".join(missing))

func test_court_every_regiment_ships_a_medallion() -> void:
	_setup_unit_icons()
	var missing: Array[String] = []
	for type_id: String in RegimentCatalog.ids():
		if RegimentArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "regiments without a plate: %s" % ", ".join(missing))


## Unique icons, not one plate reused under several names: every type resolves
## a file of its own.

func test_court_no_two_types_share_one_plate() -> void:
	_setup_unit_icons()
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for type_id: String in court__every_type():
		var texture: Texture2D = court__plate(type_id)
		var path: String = texture.resource_path if texture != null else ""
		if seen.has(path):
			clashes.append("%s = %s" % [type_id, String(seen[path])])
		seen[path] = type_id
	assert_eq(clashes.size(), 0, "types sharing a plate: %s" % ", ".join(clashes))

func test_court_an_unknown_hull_falls_back_to_the_default_plate() -> void:
	_setup_unit_icons()
	assert_eq(
		ShipArt.medallion("no_such_hull").resource_path,
		ShipArt.medallion(ShipStats.DEFAULT_TYPE).resource_path
	)
	assert_eq(
		RegimentArt.medallion("no_such_regiment").resource_path,
		RegimentArt.medallion(RegimentCatalog.DEFAULT_TYPE).resource_path
	)

func test_court_an_unknown_worker_has_no_plate() -> void:
	_setup_unit_icons()
	assert_null(CivilianArt.medallion("no_such_worker"))


## --- worker tiers: one plate per rank, struck in its own metal -------------


## Every worker tier carries a plate of its own, and the art ids follow the
## roster's own names so a renamed tier cannot silently lose its medallion
## (REQ-P1-08; tools/art/unit-medallions.md).

func test_every_worker_tier_ships_a_medallion() -> void:
	_setup_unit_icons()
	var missing: Array[String] = []
	for tier in WorkerPool.TIER_COUNT:
		assert_eq(
			WorkerTierArt.tier_id(tier),
			WorkerPool.tier_one(tier).to_lower(),
			"tier %d keeps the roster's name" % tier
		)
		if WorkerTierArt.medallion(tier) == null:
			missing.append(WorkerPool.tier_name(tier))
	assert_eq(missing.size(), 0, "tiers without a plate: %s" % ", ".join(missing))

func test_an_unknown_tier_has_no_plate() -> void:
	_setup_unit_icons()
	assert_eq(WorkerTierArt.tier_id(-1), "")
	assert_eq(WorkerTierArt.tier_id(WorkerPool.TIER_COUNT), "")
	assert_null(WorkerTierArt.medallion(-1))
	assert_null(WorkerTierArt.medallion(WorkerPool.TIER_COUNT))

func test_no_two_worker_tiers_share_a_plate() -> void:
	_setup_unit_icons()
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for tier in WorkerPool.TIER_COUNT:
		var plate: Texture2D = WorkerTierArt.medallion(tier)
		var path: String = plate.resource_path if plate != null else ""
		if seen.has(path):
			clashes.append("%s = %s" % [WorkerPool.tier_name(tier), String(seen[path])])
		seen[path] = WorkerPool.tier_name(tier)
	assert_eq(clashes.size(), 0, "tiers sharing a plate: %s" % ", ".join(clashes))


## Distinct in silhouette *and* colour: the frame is identical on every plate, so
## the mean mark colour of two ranks must sit well apart — iron, copper, blued
## steel and gold, never one metal under four names (REQ-P1-08).

func test_each_worker_tier_strikes_its_own_metal() -> void:
	_setup_unit_icons()
	var inks: Dictionary = {}
	for tier in WorkerPool.TIER_COUNT:
		inks[tier] = _mark_colour(WorkerTierArt.medallion(tier))
	for first in WorkerPool.TIER_COUNT:
		for second in range(first + 1, WorkerPool.TIER_COUNT):
			var a: Color = inks[first]
			var b: Color = inks[second]
			var gap: float = Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			assert_gt(
				gap,
				0.08,
				"%s and %s read as one metal (%.3f)"
				% [WorkerPool.tier_name(first), WorkerPool.tier_name(second), gap]
			)


## Mean colour of a plate's subject: the field's own darks and the shell's ring
## are left out, so only the tier's metal is measured.

func test_court_the_row_widget_draws_the_plate_it_is_given() -> void:
	_setup_unit_icons()
	var plate: Texture2D = ShipArt.medallion("frigate")
	var medallion: UnitMedallion = UnitMedallion.of_ship("frigate", 40.0)
	assert_eq(medallion.texture, plate)
	assert_eq(medallion.custom_minimum_size, Vector2(40.0, 40.0))
	assert_eq(medallion.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	assert_eq(medallion.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(medallion.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	add_child(medallion)
	medallion.queue_free()
	var bare := UnitMedallion.new(null, 20.0)
	assert_null(bare.texture)
	assert_eq(bare.custom_minimum_size, Vector2(20.0, 20.0), "an absent plate keeps its width")
	add_child(bare)
	bare.queue_free()

func test_court_a_regiment_medallion_names_its_own_type() -> void:
	_setup_unit_icons()
	var medallion: UnitMedallion = UnitMedallion.of_regiment("grenadiers")
	assert_eq(medallion.texture, RegimentArt.medallion("grenadiers"))
	assert_eq(medallion.custom_minimum_size, Vector2(28.0, 28.0))

func _mark_colour(plate: Texture2D) -> Color:
	var image: Image = plate.get_image()
	var centre := Vector2(image.get_width(), image.get_height()) * 0.5
	var field: float = minf(centre.x, centre.y) * 0.82
	var sum := Vector3.ZERO
	var count: int = 0
	for y in image.get_height():
		for x in image.get_width():
			if Vector2(x, y).distance_to(centre) > field:
				continue
			var ink: Color = image.get_pixel(x, y)
			if ink.a < 0.9 or ink.get_luminance() <= 0.35:
				continue
			sum += Vector3(ink.r, ink.g, ink.b)
			count += 1
	assert_gt(count, 40, "the tier's mark fills enough of the field to measure")
	return Color(sum.x / float(count), sum.y / float(count), sum.z / float(count))


## The row widget wears the plate at its own size, mipmapped, and a missing
## plate leaves a gap of the same width so the row's columns do not shift.

func court__every_type() -> Array[String]:
	var all: Array[String] = []
	all.append_array(CivilianCatalog.ORDER)
	for type_id: Variant in ShipStats.STATS.keys():
		all.append(String(type_id))
	all.append_array(RegimentCatalog.ids())
	return all

func court__plate(type_id: String) -> Texture2D:
	if CivilianCatalog.known(type_id):
		return CivilianArt.medallion(type_id)
	if ShipStats.known(type_id):
		return ShipArt.medallion(type_id)
	return RegimentArt.medallion(type_id)


# --- the pause door (from test_menu_door) ---
## One MENU seal, parked by every full-screen ledger and sealed for good by
## the full-AI observer (REQ-P3-02, REQ-P5-02, REQ-P3-04).

func _seal() -> Button:
	var seal := Button.new()
	add_child(seal)
	return seal


func test_a_parked_door_hides_the_seal_and_a_release_shows_it() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	assert_true(seal.visible, "a fresh menu shows its seal")

	door.park()
	assert_false(seal.visible, "a ledger parks the seal")
	assert_true(door.is_parked(), "the door knows a ledger holds it")

	door.release()
	assert_true(seal.visible, "closing the ledger gives the seal back")
	assert_false(door.is_parked())


## The estates card, the civilian roster and the muster roll all use this rule:
## the first to open parks, the second leaves it alone, and the second to close
## does not hand the seal back while the first still holds it.
func test_two_ledgers_keep_the_door_parked_until_the_last_closes() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)

	var first: bool = GameMenuDoor.set_held(door, false, false)
	assert_true(first, "the first ledger parks the door")
	var second: bool = GameMenuDoor.set_held(door, false, false)
	assert_false(second, "a second ledger finds it already parked and claims nothing")
	assert_false(seal.visible)

	# The second ledger closes: it claimed no hold, so the door stays parked.
	assert_false(GameMenuDoor.set_held(door, true, second), "the second close releases nothing")
	assert_false(seal.visible, "the first ledger's frame keeps the seal parked")
	# The first ledger closes: the last close hands the seal back.
	assert_false(GameMenuDoor.set_held(door, true, first), "the last close is not its own either")
	assert_true(seal.visible, "the seal returns once the last ledger closes")


## A ledger that closes without opening (the estates card lives on the map all
## turn) must not hand the seal to the observer's hidden chrome.
func test_a_close_without_an_open_never_releases_the_seal() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	door.seal()

	assert_false(
		GameMenuDoor.set_held(door, true, false),
		"a stray close claims no hold"
	)
	assert_false(seal.visible, "the observer keeps its chrome sealed")


func test_a_standalone_menu_without_a_page_keeps_its_seal() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	assert_false(GameMenuDoor.set_held(null, true, false), "no menu, no hold")
	assert_true(GameMenuDoor.set_held(null, false, true), "no menu, nothing parked")
	assert_true(seal.visible)


## The observer's seal outlives every ledger: a panel that parks and releases
## while the observatory runs still leaves the human chrome hidden.
func test_a_release_never_lifts_the_observers_seal() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	door.seal()
	door.park()
	door.release()
	assert_false(seal.visible, "the observer keeps its seal")


## A door that never got its crest (a menu built without a page) still tracks
## parking instead of crashing on the missing button.
func test_a_door_without_a_crest_still_tracks_its_hold() -> void:
	var door := GameMenuDoor.new()
	door.park()
	assert_true(door.is_parked(), "no crest, the state still moves")
	door.release()
	assert_false(door.is_parked())


## The pause page's campaign reading: a missing screen yields the catalog default
## and no seed, and COPY is a no-op when nothing is shown (REQ-P3-01).
func test_the_pause_campaign_reading_stands_alone() -> void:
	assert_eq(GameMenuCampaign.resolve_seed(null), 0, "no screen, no seed")
	assert_eq(
		GameMenuCampaign.resolve_leader(null),
		LeaderCatalog.DEFAULT_KEY,
		"no screen, the catalog default"
	)
	var seed_label := Label.new()
	var crown := Label.new()
	var copy := Button.new()
	add_child(seed_label)
	add_child(crown)
	add_child(copy)
	var shown: int = GameMenuCampaign.refresh(null, seed_label, copy, crown)
	assert_eq(shown, 0)
	assert_eq(seed_label.text, "—")
	assert_true(copy.disabled, "copy stays shut with no seed")
	assert_eq(crown.text, LeaderCatalog.crown_line(LeaderCatalog.DEFAULT_KEY))
	var status := Label.new()
	add_child(status)
	GameMenuCampaign.copy_seed(0, status)
	assert_eq(status.text, "", "a zero seed copies nothing")
	GameMenuCampaign.copy_seed(42, status)
	assert_eq(status.text, "Seed copied.", "a live seed confirms")


## The pause desk builds its own rows so GameMenu only wires them (REQ-P3-01).
func test_the_pause_desk_builds_its_rows() -> void:
	var frame := VBoxContainer.new()
	add_child(frame)
	var desk := GameMenuPause.new()
	desk.build(frame, true)
	assert_not_null(desk.pause_page, "the desk mounts a page")
	assert_not_null(desk.crown_label, "with the crown line")
	assert_not_null(desk.seed_label, "the seed digits")
	assert_not_null(desk.copy_seed_button, "the copy door")
	assert_not_null(desk.resume_button, "resume")
	assert_not_null(desk.save_button, "save")
	assert_not_null(desk.load_button, "load")
	assert_not_null(desk.keys_button, "keys")
	assert_not_null(desk.main_menu_button, "main menu")
	assert_not_null(desk.sound_desk, "the mix desk")
	assert_not_null(desk.status, "and a status line")
	assert_eq(desk.pause_page.get_parent(), frame, "the page sits on the frame")


## The screen-side door case (`test_the_screen_binds_the_door_and_the_observer_
## seals_it`) rides the observer suite's one mount (`test_ai_observer`): a
## second observer mount here cost ~15 s under coverage for the same asserts.


# --- the civilian dossier's two halves (from test_civilian_dossier_parts) ----
## The dossier's ground rows and standing lines are pure reads out of the sheet:
## [CivilianPanelDetail] words the ground rows and [CivilianPanelStatus] the
## standing lines, so the panel only composes them (REQ-P3-01, REQ-P3-03). They
## ride this boot instead of paying a Godot boot of their own.

## The ground rows the sheet prints are a pure read, so the module answers with
## words alone and the panel only composes them (REQ-P3-01, REQ-P3-03).
func test_the_dossier_ground_rows_read_the_tile() -> void:
	var model: MapModel = Fixture.build()
	var builder: CivilianState = CivilianState.create(
		1, PLAYER, "builder", Fixture.TIMBER_TILE
	)
	var rows: Array[Array] = CivilianPanelDetail.rows(
		model, builder, LandWorks.new(), {}
	)
	var by_caption: Dictionary = {}
	for row: Array in rows:
		by_caption[String(row[0])] = String(row[1])
	assert_eq(
		String(by_caption.get("Tile", "")),
		"%d, %d" % [Fixture.TIMBER_TILE.x, Fixture.TIMBER_TILE.y]
	)
	assert_eq(
		String(by_caption.get("Held by", "")),
		FactionCatalog.name_of(PLAYER)
	)
	assert_true(by_caption.has("Province") and by_caption.has("Works"), "the ground reads")
	assert_false(by_caption.has("Tradecraft"), "a builder keeps no tradecraft row")
	assert_false(by_caption.has("Survey"), "and no survey row")
	var spy: CivilianState = CivilianState.create(
		2, PLAYER, "spy", Fixture.BARE_TILE
	)
	var tradecraft: String = _dossier_detail_of(spy, model, "Tradecraft")
	assert_eq(
		tradecraft,
		"No screen up — only the counter-espionage order covers your land"
	)
	# A rival reading the sheet reads the ground through its own survey record,
	# so a Prospected mark the crew's owner holds never shows on the rival's
	# sheet (wiki: fog-and-exploration § Prospecting; DR-20261111-26).
	var works := LandWorks.new()
	var owner_ground: Array[Array] = CivilianPanelDetail.rows(model, builder, works, {})
	assert_false(_dossier_row_of(owner_ground, "Works").contains("Prospected"), "unprospected")
	works.set_prospected(PLAYER, model, Fixture.TIMBER_TILE)
	owner_ground = CivilianPanelDetail.rows(model, builder, works, {})
	assert_true(
		_dossier_row_of(owner_ground, "Works").contains("Prospected"), "the owner sees it"
	)
	var rival_ground: Array[Array] = CivilianPanelDetail.rows(
		model, builder, works, {}, 5
	)
	assert_false(
		_dossier_row_of(rival_ground, "Works").contains("Prospected"), "the rival does not"
	)


## The standing line and the pick's wording are one module's job: the panel adds
## the capitals, the module answers the words (REQ-P5-06, DR-20261117-06).
func test_the_dossier_standing_lines_are_plain_words() -> void:
	var model: MapModel = Fixture.build()
	var builder: CivilianState = CivilianState.create(
		1, PLAYER, "builder", Fixture.TIMBER_TILE
	)
	assert_eq(
		CivilianPanelStatus.text(model, builder, PLAYER), "Idle — choose an order below."
	)
	assert_eq(
		CivilianPanelStatus.text(model, builder, 9), "Enemy colours · no orders"
	)
	builder.start_work("build_improvement", builder.tile, 2)
	assert_eq(
		CivilianPanelStatus.text(model, builder, PLAYER),
		"Build improvement · 2 turns left."
	)
	assert_eq(CivilianPanelStatus.pick_line({}), "", "no pick, no line")
	assert_eq(
		CivilianPanelStatus.pick_line({"pick": {"line": "the court would raise a road"}}),
		"The court would raise a road."
	)


## The pick's door: an estate is raised from the estates ledger, a road or a
## railroad from the province dossier, and every order the crew's own sheet can
## press names none (REQ-P5-06; wiki: playtest-learnings § next targets;
## DR-20261117-10).
func test_the_pick_names_the_door_that_can_press_it() -> void:
	assert_eq(
		MapPlayCivilianPick.door_for("build_improvement"),
		MapPlayCivilianPick.DOOR_ESTATES,
		"an estate is raised from the estates ledger"
	)
	assert_eq(
		MapPlayCivilianPick.door_for("build_road"),
		MapPlayCivilianPick.DOOR_PROVINCE,
		"a road is pressed from the province dossier"
	)
	assert_eq(
		MapPlayCivilianPick.door_for("build_rail"),
		MapPlayCivilianPick.DOOR_PROVINCE,
		"a railroad is pressed from the province dossier's rail block"
	)
	for action: String in [
		"explore", "prospect", "build_port", "build_fort", "build_hospital",
		"upgrade_town", "purchase_land", "counter_spy",
		MapPlayCivilianPick.KIND_MOVE, "",
	]:
		assert_eq(
			MapPlayCivilianPick.door_for(action), "",
			"%s is pressed from the crew's own sheet" % action
		)
	var press: String = MapPlayCivilianFollow.press(
		1, Vector2i(4, 7), "build_improvement"
	)
	assert_eq(press, "follow_pick:1:4,7:build_improvement", "the press names its ground")
	assert_true(MapPlayCivilianFollow.is_follow(press), "the press is a follow")
	assert_false(
		MapPlayCivilianFollow.is_follow("build_improvement"), "an order is not a follow"
	)


## The crew's sheet on bought ground names the deed, not a bare label: who signed
## it and what it keeps for them (REQ-P5-03, REQ-P5-05; DR-20261118-05).
func test_the_dossier_names_the_deed_that_holds_the_ground() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant: CivilianState = CivilianState.create(
		1, PLAYER, "merchant", Vector2i(3, 1)
	)
	assert_eq(_dossier_detail_of(merchant, model, "Deed"), "", "unsold ground")
	assert_true(model.purchase_tile(Vector2i(3, 1), PLAYER))
	assert_eq(
		_dossier_detail_of(merchant, model, "Deed"),
		"%s · first refusal on 1 grain / turn" % FactionCatalog.name_of(PLAYER)
	)


## The passengers block's own rows: the one press that boards a whole berth and
## the line under it are the block's foot, not one of the coasts or crews a row
## reads (wiki: civilian-units § Boarding; DR-20261119-18).
func _crew_rows(block: FleetCrewSection) -> Array[Node]:
	var rows: Array[Node] = [] as Array[Node]
	for node: Node in block.find_children("", "Button", true, false):
		if node == block._batch:
			continue
		rows.append(node)
	return rows


## The passengers block reads a landing as a tile and a crew: a coast with one
## legal ground lands in one press, a coast with several opens its grounds, the
## ground's press carries that tile and the crew kind the row named, and the row
## prints what the crown can read of the ground (wiki: civilian-units § Landing;
## DR-20261118-19).
func test_the_passengers_block_opens_a_coast_s_grounds() -> void:
	var block := FleetCrewSection.new()
	add_child(block)
	var fired: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: fired.append(action))
	block.set_data({
		"count": 1,
		"note": "1 aboard: Explorer",
		"embark": [],
		"sortie": [],
		"land": [
			{
				"province": 4, "name": "Cadiz", "crew": "explorer",
				"crew_name": "Explorer", "tiles": [{"x": 2, "y": 3}],
			},
			{
				"province": 5, "name": "Vera Cruz", "crew": "explorer",
				"crew_name": "Explorer",
				"tiles": [
					{"x": 7, "y": 8, "ground": "Hills · iron"},
					{"x": 9, "y": 10},
				],
			},
		],
	})
	var coasts: Array[Node] = _crew_rows(block)
	assert_eq(coasts.size(), 2, "one press per coast")
	var single: Button = coasts[0] as Button
	assert_eq(single.text, "Put the Explorer ashore at Cadiz")
	single.pressed.emit()
	assert_eq(fired, ["crew:land:2:3:explorer"], "one ground lands in one press")
	assert_eq(block.open_coast, -1, "a single-ground coast opens nothing")

	var many: Button = coasts[1] as Button
	assert_true(many.text.begins_with("Put the Explorer ashore at Vera Cruz · 2 grounds"))
	many.pressed.emit()
	assert_eq(block.open_coast, 5, "the coast opens")
	assert_eq(block.open_crew, "explorer", "the open grounds belong to the crew read")
	assert_eq(fired.size(), 1, "opening a coast orders nothing")
	var rows: Array[Node] = _crew_rows(block)
	assert_eq(rows.size(), 3, "the way back and the coast's two grounds")
	assert_eq(
		(rows[1] as Button).text, "Vera Cruz (7, 8) — Hills · iron",
		"the ground row names what the crown can read of the tile"
	)
	assert_eq((rows[2] as Button).text, "Vera Cruz (9, 10)", "an uncharted ground reads bare")
	(rows[1] as Button).pressed.emit()
	assert_eq(fired.size(), 2)
	assert_eq(
		fired[1], "crew:land:7:8:explorer",
		"the ground's press carries its own tile and the crew"
	)
	assert_eq(block.open_coast, -1, "the press closes the coast")

	# The coasts are back, and the way back out of a coast orders nothing.
	var reopened: Array[Node] = _crew_rows(block)
	assert_eq(reopened.size(), 2, "the coasts are back")
	(reopened[1] as Button).pressed.emit()
	var grounds: Array[Node] = _crew_rows(block)
	(grounds[0] as Button).pressed.emit()
	assert_eq(block.open_coast, -1, "the way back closes the coast")
	assert_eq(block.open_crew, "", "the way back forgets the crew")
	assert_eq(fired.size(), 2, "no order leaves the way back")

	block.set_data({"count": 0, "land": [], "embark": [], "sortie": []})
	assert_false(block.visible, "no passengers, no block")
	block.free()


## Two crew kinds aboard one squadron read one line each per coast, so the crown
## picks the crew as well as the ground: a Builder and an Explorer on the same
## coast are two presses, and each carries its own kind (wiki: civilian-units
## § Landing; DR-20261118-19).
func test_the_passengers_block_names_the_crew_it_lands() -> void:
	var block := FleetCrewSection.new()
	add_child(block)
	var fired: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: fired.append(action))
	block.set_data({
		"count": 2,
		"note": "2 aboard: Builder · Explorer",
		"embark": [],
		"sortie": [],
		"land": [
			{
				"province": 4, "name": "Cadiz", "crew": "builder",
				"crew_name": "Builder", "tiles": [{"x": 2, "y": 3}],
			},
			{
				"province": 4, "name": "Cadiz", "crew": "explorer",
				"crew_name": "Explorer", "tiles": [{"x": 2, "y": 3}],
			},
		],
	})
	var rows: Array[Node] = _crew_rows(block)
	assert_eq(rows.size(), 2, "one press per crew kind on the coast")
	assert_eq((rows[0] as Button).text, "Put the Builder ashore at Cadiz")
	assert_eq((rows[1] as Button).text, "Put the Explorer ashore at Cadiz")
	(rows[1] as Button).pressed.emit()
	assert_eq(
		fired, ["crew:land:2:3:explorer"],
		"the Explorer's press lands the Explorer, not the first crew aboard"
	)
	block.free()


## The crown's own seat reads above the list as one press, so a port province
## whose coast holds a whole province of ground never makes a crown open the
## list to land at home (wiki: civilian-units § Landing; DR-20261118-28).
func test_the_passengers_block_lands_a_crew_at_the_seat_in_one_press() -> void:
	var block := FleetCrewSection.new()
	add_child(block)
	var fired: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: fired.append(action))
	block.set_data({
		"count": 1,
		"note": "1 aboard: Explorer",
		"embark": [],
		"sortie": [],
		"land": [
			{
				"province": 4, "name": "Cadiz", "crew": "explorer",
				"crew_name": "Explorer",
				"seat": {"x": 5, "y": 6, "ground": "Plains · grain"},
				"tiles": [
					{"x": 5, "y": 6, "ground": "Plains · grain"},
					{"x": 7, "y": 8, "ground": "Hills · iron"},
				],
			},
		],
	})
	var rows: Array[Node] = _crew_rows(block)
	assert_eq(rows.size(), 2, "the seat and the list")
	assert_eq(
		(rows[0] as Button).text,
		"Put the Explorer ashore at Cadiz (5, 6) — Plains · grain",
		"the seat reads first, with the ground the chart knows"
	)
	assert_true(
		(rows[1] as Button).text.begins_with("Put the Explorer ashore at Cadiz · 2 grounds")
	)
	(rows[0] as Button).pressed.emit()
	assert_eq(fired, ["crew:land:5:6:explorer"], "the seat lands in one press")

	# A coast with one legal ground keeps its published single press, seat or not.
	block.set_data({
		"count": 1, "note": "1 aboard: Explorer", "embark": [], "sortie": [],
		"land": [
			{
				"province": 4, "name": "Cadiz", "crew": "explorer",
				"crew_name": "Explorer",
				"seat": {"x": 5, "y": 6, "ground": "Plains · grain"},
				"tiles": [{"x": 5, "y": 6, "ground": "Plains · grain"}],
			},
		],
	})
	var single: Array[Node] = _crew_rows(block)
	assert_eq(single.size(), 1, "one ground, one press")
	assert_eq((single[0] as Button).text, "Put the Explorer ashore at Cadiz")
	block.free()


## The block's one press stands under the embark rows: it names the crews the
## hulls can take now, arms on the first tap, files the whole berth on the second,
## and prints the crew that waits beside the rules' own reason (wiki:
## civilian-units § Boarding; DR-20261119-18).
func test_the_passengers_block_takes_a_whole_berth_in_one_press() -> void:
	var block := FleetCrewSection.new()
	add_child(block)
	var fired: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: fired.append(action))
	block.set_data({
		"count": 0, "note": "No colonists aboard.",
		"embark": [
			{"id": 4, "name": "Builder"}, {"id": 5, "name": "Explorer"},
			{"id": 6, "name": "Spy"},
		],
		"embark_batch": {
			"count": 3, "filed": 2,
			"refusal": "The squadron has 2 hulls and cannot carry another civilian.",
		},
		"land": [], "sortie": [],
	})
	assert_true(block._batch.visible, "the press stands under the rows")
	assert_eq(block._batch.text, "Take all ready (3)", "the face names the view")
	assert_true(block._batch_line.visible, "the berth that waits is spoken")
	assert_eq(
		block._batch_line.text,
		"1 of 3 waits: The squadron has 2 hulls and cannot carry another civilian.",
		"the line names the crew that waits and why"
	)
	block._batch.pressed.emit()
	assert_true(block._batch.is_armed(), "the first tap arms")
	assert_eq(
		block._batch.text, "Confirm — take 2 of 3 crews",
		"the armed face names the line the berth carries"
	)
	block._batch.pressed.emit()
	assert_eq(fired, ["crew:embark:all"], "the second tap files the berth")
	assert_false(block._batch.is_armed(), "the press forgets the arm it spent")

	# A berth that carries every crew has nothing to say under the press.
	block.set_data({
		"count": 0, "note": "No colonists aboard.",
		"embark": [{"id": 4, "name": "Builder"}, {"id": 5, "name": "Explorer"}],
		"embark_batch": {"count": 2, "filed": 2, "refusal": ""},
		"land": [], "sortie": [],
	})
	assert_eq(block._batch.text, "Take all ready (2)")
	assert_false(block._batch_line.visible, "a covered berth prints no wait")

	# Nothing the hulls can take hides the press; a coast's open grounds do too.
	block.set_data({
		"count": 0, "note": "No colonists aboard.", "embark": [],
		"embark_batch": {"count": 0, "filed": 0, "refusal": ""},
		"land": [], "sortie": [],
	})
	assert_false(block._batch.visible, "nothing ready, no press")
	block.set_data({
		"count": 0, "note": "No colonists aboard.",
		"embark": [{"id": 4, "name": "Builder"}],
		"embark_batch": {"count": 1, "filed": 1, "refusal": ""},
		"land": [{
			"province": 4, "name": "Cadiz", "crew": "builder", "crew_name": "Builder",
			"tiles": [{"x": 2, "y": 3}, {"x": 4, "y": 5}],
		}],
		"sortie": [],
	})
	assert_true(block._batch.visible, "the press is back on the coasts")
	var coasts: Array[Node] = _crew_rows(block)
	(coasts[0] as Button).pressed.emit()
	assert_eq(block.open_coast, 4, "the coast opens")
	assert_false(block._batch.visible, "an open coast reads alone")
	coasts = _crew_rows(block)
	(coasts[0] as Button).pressed.emit()
	assert_eq(block.open_coast, -1, "the way back closes it")
	assert_true(block._batch.visible, "the press comes back with the coasts")
	block.free()


## A port coast offers its whole province of ground — 32 rows at Madrid — so the
## open list reads in a window of whole rows: the way back stays pinned above it,
## a short list keeps its own height, and every ground is still one press on its
## own tile (wiki: civilian-units § Landing; DR-20261119-03).
func test_the_passengers_block_windows_a_coast_s_whole_land() -> void:
	var block := FleetCrewSection.new()
	add_child(block)
	var fired: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: fired.append(action))
	var tiles: Array = []
	for i in 32:
		tiles.append({"x": i % 8, "y": int(i / 8), "ground": "Plains · grain"})
	block.set_data({
		"count": 1, "note": "1 aboard: Builder", "embark": [], "sortie": [],
		"land": [{
			"province": 4, "name": "Madrid", "crew": "builder",
			"crew_name": "Builder", "tiles": tiles,
		}],
	})
	var coasts: Array[Node] = _crew_rows(block)
	assert_eq((coasts[0] as Button).text, "Put the Builder ashore at Madrid · 32 grounds ›")
	(coasts[0] as Button).pressed.emit()
	assert_eq(block.open_coast, 4, "the coast opens")

	# The way back is the block's own row, above the window, and names the count.
	var rows: Array[Node] = _crew_rows(block)
	assert_eq((rows[0] as Button).text, "‹ Back to the coasts · 32 grounds")
	var window: ScrollContainer = block._ground_scroll
	assert_true(window.visible, "the open grounds ride a window")
	var grounds: Node = window.get_child(0)
	assert_eq(grounds.get_child_count(), 32, "every legal ground is listed")
	assert_eq((rows[0] as Button).get_parent(), block._rows_box, "the way back is pinned")
	assert_eq((grounds.get_child(0) as Button).get_parent(), grounds, "the grounds scroll")

	# The window is whole rows: the sheet's own budget, never the whole coast.
	var compact: bool = HudLayout.is_compact(block.get_viewport_rect().size)
	assert_eq(window.custom_minimum_size.y, GroundsWindow.height(32, compact))
	assert_eq(GroundsWindow.rows(32, true), 4, "a handset reads four rows")
	assert_eq(GroundsWindow.rows(32, false), 8, "the atlas reads eight")
	assert_eq(GroundsWindow.rows(3, true), 3, "a short list asks for its own height")
	assert_eq(
		GroundsWindow.height(3, false),
		3.0 * GroundsWindow.ROW_HEIGHT + 2.0 * float(GroundsWindow.ROW_GAP),
		"whole rows and the gaps between them"
	)
	assert_true(
		window.custom_minimum_size.y
			< float(tiles.size()) * GroundsWindow.ROW_HEIGHT,
		"the long coast is a window, not the sheet"
	)

	# A ground still lands its own tile and closes the window after it.
	(grounds.get_child(5) as Button).pressed.emit()
	assert_eq(fired, ["crew:land:5:0:builder"], "the row's own tile and crew")
	assert_false(window.visible, "the window closes with the landing")
	assert_eq(block.open_coast, -1)
	block.free()


func _dossier_detail_of(unit: CivilianState, model: MapModel, caption: String) -> String:
	for row: Array in CivilianPanelDetail.rows(model, unit, LandWorks.new(), {}):
		if String(row[0]) == caption:
			return String(row[1])
	return ""


func _dossier_row_of(rows: Array[Array], caption: String) -> String:
	for row: Array in rows:
		if String(row[0]) == caption:
			return String(row[1])
	return ""


## The mission block's advice line: the pick the court's own admiral would give
## the squadron prints under the station note and hides when there is none, so a
## sheet never shows an empty gold row (wiki: ships-and-naval § Missions and
## Movement; DR-20261120-04).
func test_the_mission_block_prints_the_courts_pick_under_its_station() -> void:
	var block := FleetMissionSection.new()
	add_child(block)
	block.set_data("No station held.", [], "The court would dock her at Cádiz.")
	assert_true(block.visible, "a pick needs no station row of its own")
	assert_eq(block._pick.text, "The court would dock her at Cádiz.")
	assert_true(block._pick.visible, "the advice prints")
	assert_eq(block._note.text, "No station held.", "the station note keeps its own line")
	block.set_data("No station held.", [])
	assert_false(block._pick.visible, "no pick, no gold row")
	assert_eq(block._pick.text, "", "and nothing left over from the last squadron")
	block.set_data("", [], "")
	assert_false(block.visible, "nothing to say, nothing raised")
	block.queue_free()


## The passenger block's voyage line: the step the court's own colonisation pass
## would take prints in gold under the note, and hides when the court would sail
## nothing — a block never shows an empty gold row (wiki: civilian-units
## § Overseas deployment; DR-20261121-08).
func test_the_passenger_block_prints_the_voyage_the_court_would_make() -> void:
	var block := FleetCrewSection.new()
	add_child(block)
	block.set_data({
		"count": 0, "note": "", "embark": [], "embark_batch": {}, "land": [],
		"sortie": [],
		"pick": {"kind": "embark", "line": "the court would take an Explorer aboard at Cádiz"},
	})
	assert_true(block.visible, "a voyage line raises the block on its own")
	assert_eq(block._pick.text, "The court would take an Explorer aboard at Cádiz.")
	assert_true(block._pick.visible, "the advice prints")
	block.set_data({
		"count": 0, "note": "", "embark": [], "embark_batch": {}, "land": [],
		"sortie": [], "pick": {},
	})
	assert_false(block.visible, "nothing to say, nothing raised")
	assert_false(block._pick.visible, "no pick, no gold row")
	assert_eq(block._pick.text, "", "and nothing left over from the last squadron")
	block.queue_free()


# --- panel close seal (docs/ui-panels.md; issue #1161) -----------------------

## Every known dismissible panel: the shared chrome (a bare SheetFrame and
## LedgerFrame, the two header rows) and each one-off that draws its own plate.
## A new sheet joins this list, so the rule is proved on the panel itself.
func _dismissible_panels() -> Array[Node]:
	var desk := SoundDesk.new()
	desk.closable = true
	return [
		SheetFrame.new(),
		LedgerFrame.new(),
		DossierHeader.make(20),
		ProvinceSheetHead.new(),
		TechTreePanel.new(),
		CourtDossierScreen.new(),
		ArmyPanel.new(),
		FleetPanel.new(),
		ProvincePanel.new(),
		CivilianPanel.new(),
		ImprovementPanel.new(),
		GazettePlate.new(),
		ObserverProvinceSheet.new(),
		desk,
	]


func _seal_of(panel: Node) -> CloseSeal:
	for node: Node in _collect(panel, [] as Array[Node]):
		if node is CloseSeal:
			return node as CloseSeal
	return null


## The seal is the shell's own medallion: one glyph, no word, and a thumb-sized
## target (REQ-P1-05, REQ-P1-08; docs/ui-panels.md).
func test_the_close_seal_is_one_medallion_control() -> void:
	var seal := CloseSeal.make()
	add_child(seal)
	assert_eq(seal.text, "", "the seal carries no word")
	assert_eq(seal.tooltip_text, "Close", "the words live in the tip")
	assert_eq(seal.icon, ChromeIcons.texture("close"), "the shell's medallion set")
	assert_true(
		seal.custom_minimum_size.x >= 44.0 and seal.custom_minimum_size.y >= 44.0,
		"a phone keeps a thumb-sized door: %s" % seal.custom_minimum_size
	)
	seal.free()


## Every known dismissible panel wears exactly one seal, in the last slot of its
## header row, and prints no one-off "Close" or "×" door of its own.
func test_every_known_panel_wears_the_shared_close_seal() -> void:
	for panel: Node in _dismissible_panels():
		add_child(panel)
		var seals: Array[CloseSeal] = []
		var text_doors: Array[String] = []
		for node: Node in _collect(panel, [] as Array[Node]):
			if node is CloseSeal:
				seals.append(node as CloseSeal)
			elif node is Button:
				var words: String = (node as Button).text
				if words.contains("Close") or words == "×" or words == "✕":
					text_doors.append(words)
		assert_eq(seals.size(), 1, "%s wears one close seal" % panel.get_class())
		var seal: CloseSeal = seals[0]
		var row: Node = seal.get_parent()
		assert_true(row is HBoxContainer, "%s pins its seal in a header row" % panel.get_class())
		assert_eq(
			seal.get_index(),
			row.get_child_count() - 1,
			"%s pins its seal in the header's right-hand slot" % panel.get_class()
		)
		assert_eq(
			text_doors,
			[] as Array[String],
			"%s must not print a one-off close door" % panel.get_class()
		)
		remove_child(panel)
		panel.free()


## A press on the seal closes the panel it heads, through the panel's own
## signal or its one visible flag (REQ-P5-07).
func test_the_close_seal_closes_the_panel_beside_it() -> void:
	for panel: Node in _dismissible_panels():
		add_child(panel)
		var heard: Array[bool] = []
		if panel is ModalShell:
			(panel as ModalShell).visible = true
		elif panel is ProvincePanel:
			(panel as ProvincePanel).close_pressed.connect(func() -> void: heard.append(true))
		elif panel is CivilianPanel:
			(panel as CivilianPanel).close_pressed.connect(func() -> void: heard.append(true))
		elif panel is ProvinceSheetHead:
			(panel as ProvinceSheetHead).close_pressed.connect(func() -> void: heard.append(true))
		elif panel is DossierHeader:
			(panel as DossierHeader).close_pressed.connect(func() -> void: heard.append(true))
		elif panel is LedgerFrame:
			(panel as LedgerFrame).close_pressed.connect(func() -> void: heard.append(true))
		elif panel is ArmyPanel:
			(panel as ArmyPanel).close_pressed.connect(func() -> void: heard.append(true))
		elif panel is FleetPanel:
			(panel as FleetPanel).close_pressed.connect(func() -> void: heard.append(true))
		elif panel is ObserverProvinceSheet:
			(panel as ObserverProvinceSheet).closed.connect(func() -> void: heard.append(true))
		elif panel is SoundDesk:
			(panel as SoundDesk).close_requested.connect(func() -> void: heard.append(true))
		_seal_of(panel).pressed.emit()
		if panel is ModalShell:
			assert_false((panel as ModalShell).visible, "%s closes on its seal" % panel.get_class())
		else:
			assert_eq(heard.size(), 1, "%s reports its seal's press" % panel.get_class())
		remove_child(panel)
		panel.free()


## The seal adds a door; it never takes the back gesture or Escape away.
func test_escape_still_closes_a_panel_beside_the_seal() -> void:
	var sheet := SheetFrame.new()
	add_child(sheet)
	sheet.visible = true
	InputActions.ensure_actions()
	var event := InputEventAction.new()
	event.action = InputActions.CANCEL
	event.pressed = true
	sheet._input(event)
	assert_false(sheet.visible, "Back and Escape keep closing the sheet")
	sheet.free()
