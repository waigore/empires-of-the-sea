extends GdToolsTest
## The chronicle read behind the court dossier (wiki: ai-dossier): which acts
## count, how the cap and the turn stamp behave, and how a stranger stays masked
## (REQ-P2-01, REQ-P3-01). IntelDossier's own suite covers the reading built on
## top of these observations.
## Consolidated rulebook: test_intel_evidence, test_court_reports,
## test_spy_networks, test_court_dossier_screen (one Godot boot per domain).

const Fixture = preload("res://tests/civilian_fixture.gd")
const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6
const PORTUGAL: int = 3

var state: DiplomacyState
var _model: MapModel = null


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)
	_model = Fixture.build()


func test_evidence_is_capped_and_newest_first() -> void:
	for index in 60:
		state.turn = 1 + index
		state.record_event("warDeclared", ENGLAND, GENOA)
	var entries: Array[Dictionary] = IntelEvidence.collect(state, null, VIEWER, ENGLAND)
	assert_eq(entries.size(), IntelEvidence.EVIDENCE_CAP, "the read is capped at 50")
	assert_eq(int(entries[0]["turn"]), 60, "the newest observation leads")
	assert_eq(int(entries[entries.size() - 1]["turn"]), 11, "the oldest drop first")


func test_an_unmet_court_is_named_not_leaked() -> void:
	state.record_event("callToArmsRefused", ENGLAND, 9, {"aggressor": PORTUGAL})
	var text: String = String((IntelEvidence.collect(state, null, VIEWER, ENGLAND)[0])["text"])
	assert_true(text.contains(IntelEvidence.UNKNOWN_COURT), "the stranger stays masked")
	assert_false(text.contains("Aztec"), "its name never reaches the page")


## The despatch narrates the turn that resolved, though the spy reports after the
## calendar has advanced: the observation keeps its own turn.
func test_a_despatch_keeps_the_turn_it_resolved() -> void:
	state.turn = 9
	state.record_event(
		IntelEvidence.SPY_TECH, ENGLAND, VIEWER,
		{"tech": "crop_rotation", IntelEvidence.OBSERVED_TURN: 8}
	)
	var entries: Array[Dictionary] = IntelEvidence.collect(state, null, VIEWER, ENGLAND)
	assert_eq(int(entries[0]["turn"]), 8, "the act belongs to the turn it resolved")
	state.record_event("warDeclared", ENGLAND, GENOA)
	assert_eq(IntelEvidence.turn_of(state.events[1]), 9, "a plain act keeps the chronicle stamp")


func test_a_viewer_reads_nothing_about_itself() -> void:
	state.record_event("warDeclared", VIEWER, GENOA)
	assert_true(IntelEvidence.collect(state, null, VIEWER, VIEWER).is_empty())


func test_a_missing_world_counts_no_provinces() -> void:
	assert_eq(IntelEvidence.provinces(null, ENGLAND), 0)

# --- from test_court_reports.gd ---
## The court panel's despatch block (wiki: civilian-units § Spy — court
## reports): a shadowed court shows last turn's report lines, an unwatched court
## shows nothing, and a quiet shadowed court says so (REQ-P5-02, REQ-P2-03).


func _reports(lines: Array, shadowed: Array = [ENGLAND]) -> Dictionary:
	return {"turn": 4, "shadowed": shadowed, "lines": {ENGLAND: lines}}


func test_a_shadowed_court_shows_the_kept_despatch() -> void:
	var panel := CourtReportsPanel.new()
	add_child(panel)
	panel.fill(ENGLAND, _reports(["took Coro from Spain", "finished Crop Rotation"]))
	assert_true(_has_text(panel, "COURT REPORTS"), "the block names itself")
	assert_true(_has_text(panel, "Turn 4"), "and stamps the turn")
	assert_true(_has_text(panel, "took Coro from Spain"))
	assert_true(_has_text(panel, "finished Crop Rotation"))
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
	assert_true(_has_text(panel, CourtReportsPanel.QUIET_LINE))
	panel.free()


func test_the_court_panel_carries_the_despatch_for_the_selected_crown() -> void:
	var state := DiplomacyState.new()
	state.initialize(1)
	var panel := DiplomacyPanel.new()
	add_child(panel)
	panel.refresh(state, null, VIEWER, 2500, {}, _reports(["took Coro from Spain"]))
	panel.select_faction(ENGLAND)
	assert_true(_has_text(panel._detail, "COURT REPORTS"))
	assert_true(_has_text(panel._detail, "took Coro from Spain"))
	panel.select_faction(GENOA)
	assert_false(_has_text(panel._detail, "COURT REPORTS"), "Genoa has no spy")
	panel.free()


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false

# --- from test_spy_networks.gd ---
## Espionage rules (wiki: civilian-units § Spy; fog-and-exploration § Explorer vs
## Spy; DR-20261110-03): which rival courts a posted Spy shadows, and how much
## research their finished work hands over.


## Fixture province 1 belongs to Great Power 1; province 0 to the player.
const PLAYER: int = 0
const RIVAL: int = 1
const MINOR: int = 6


func _spy(tile: Vector2i, owner: int = PLAYER) -> CivilianState:
	return CivilianState.create(1, owner, "spy", tile)


func test_a_spy_on_a_rival_great_powers_land_shadows_that_court() -> void:
	# (3, 1) sits in province 1, owned by Great Power 1.
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(3, 1))], PLAYER
	)
	assert_eq(rivals, [RIVAL])


func test_a_spy_on_the_crowns_own_land_shadows_nobody() -> void:
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(1, 1))], PLAYER
	)
	assert_eq(rivals, [], "own soil is no rival court")


func test_minor_nations_and_tribes_are_not_research_rivals() -> void:
	var model: MapModel = Fixture.build_minor()
	# build_minor() province 1 belongs to Minor Nation 6.
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		model, [_spy(Vector2i(2, 1))], PLAYER
	)
	assert_eq(rivals, [], "the wiki names rival Great Powers only")
	assert_eq(model.province_owner(1), MINOR, "fixture sanity")


func test_two_spies_in_one_court_shadow_it_once() -> void:
	var units: Array[CivilianState] = [
		_spy(Vector2i(3, 0)), _spy(Vector2i(3, 1)),
	]
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(_model, units, PLAYER)
	assert_eq(rivals, [RIVAL], "one court, one share")


func test_each_shadowed_court_counts_its_own_land() -> void:
	var model: MapModel = _three_courts_map()
	var units: Array[CivilianState] = [
		_spy(Vector2i(2, 1)), _spy(Vector2i(4, 1)),
	]
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(model, units, PLAYER)
	assert_eq(rivals, [RIVAL, 2], "ascending, one entry per court")
	assert_eq(SpyNetworks.rival_names(rivals), "England, France")


func test_a_deed_putting_land_in_a_crowns_hands_counts_as_its_land() -> void:
	# An England-owned deed inside Genoa's province makes England the host.
	var model: MapModel = Fixture.build_minor()
	assert_true(model.purchase_tile(Vector2i(3, 1), RIVAL))
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		model, [_spy(Vector2i(3, 1))], PLAYER
	)
	assert_eq(rivals, [RIVAL])


func test_an_offscreen_spy_reads_nothing() -> void:
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(99, 99))], PLAYER
	)
	assert_eq(rivals, [])


func test_a_boost_lands_only_on_techs_the_shadowed_court_already_knows() -> void:
	var boost: Dictionary = SpyNetworks.research_boost(
		[RIVAL], {RIVAL: {"navigation": true, "land_enclosure": false}}
	)
	assert_eq(SpyNetworks.boost_for(boost, "navigation"), 15)
	assert_eq(SpyNetworks.boost_for(boost, "land_enclosure"), 0, "locked tech")
	assert_eq(SpyNetworks.boost_for(boost, "saw_mill"), 0, "unknown tech")


func test_two_shadowed_courts_stack_on_a_shared_advance() -> void:
	var boost: Dictionary = SpyNetworks.research_boost(
		[RIVAL, 2],
		{
			RIVAL: {"navigation": true},
			2: {"navigation": true, "saw_mill": true},
		}
	)
	assert_eq(SpyNetworks.boost_for(boost, "navigation"), 30)
	assert_eq(SpyNetworks.boost_for(boost, "saw_mill"), 15)


func test_no_rivals_means_no_boost() -> void:
	assert_true(SpyNetworks.research_boost([], {}).is_empty())
	assert_eq(SpyNetworks.boost_for({}, "navigation"), 0)


## Six tiles wide: the crown's province, England's, then France's.
func _three_courts_map() -> MapModel:
	var model := MapModel.new()
	model.setup(6, 3)
	var mine: Array[Vector2i] = []
	var england: Array[Vector2i] = []
	var france: Array[Vector2i] = []
	for y in 3:
		for x in 6:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 2:
				model.province[model.index_of(x, y)] = 0
				mine.append(tile)
			elif x < 4:
				model.province[model.index_of(x, y)] = 1
				england.append(tile)
			else:
				model.province[model.index_of(x, y)] = 2
				france.append(tile)
	var provinces: Array[ProvinceState] = [
		ProvinceState.create(0, "Cádiz", mine, Vector2(0.5, 1.0), mine.size(), PLAYER, true),
		ProvinceState.create(1, "Plymouth", england, Vector2(2.5, 1.0), england.size(), 1, false),
		ProvinceState.create(2, "Brest", france, Vector2(4.5, 1.0), france.size(), 2, false),
	]
	model.provinces = provinces
	return model

# --- from test_court_dossier_screen.gd ---
## The full court dossier sheet (wiki: ai-dossier § Logical sections; DR-20261110-25):
## basic intel, the reading, one timeline per agenda, the whole observation list
## and the behaviour/build notes (REQ-P5-01, REQ-P1-07, REQ-P2-03).


func _state() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.initialize(1)
	return state


func _screen(state: DiplomacyState, subject: int) -> CourtDossierScreen:
	var screen := CourtDossierScreen.new()
	add_child(screen)
	screen.show_for(state, null, VIEWER, subject)
	return screen


func test_the_sheet_reads_every_section_in_order() -> void:
	var state: DiplomacyState = _state()
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	var screen: CourtDossierScreen = _screen(state, ENGLAND)
	assert_true(screen.is_open(), "the sheet is up")
	assert_true(_screen_has_text(screen, "THE DOSSIER"))
	assert_true(_screen_has_text(screen, "England"), "the court is named")
	assert_true(_screen_has_text(screen, "SUSPICION"))
	assert_true(_screen_has_text(screen, "TIMELINE"))
	assert_true(_screen_has_text(screen, "BEHAVIOUR & BUILD NOTES"))
	assert_true(_screen_has_text(screen, "Reading:"), "the best guess leads")
	assert_true(_screen_has_text(screen, "Warmonger"), "every agenda is listed, banded or not")
	assert_true(_screen_has_text(screen, "Declared war on Genoa."), "the act reaches the page")
	screen.free()


func test_the_reading_names_the_band_never_the_agenda_truth() -> void:
	var state: DiplomacyState = _state()
	for _index in 4:
		state.record_event("warDeclared", ENGLAND, GENOA)
	var screen: CourtDossierScreen = _screen(state, ENGLAND)
	assert_true(_screen_has_text(screen, "Likely 60%"), "the band and its confidence are printed")
	assert_false(_screen_has_text(screen, "Confirmed 100%"), "nothing is certain at four acts")
	screen.free()


## The strongest reading starts open; every other row opens on a press, so the
## sheet reads as a table first and a story second.
func test_an_agenda_row_toggles_its_own_timeline() -> void:
	var state: DiplomacyState = _state()
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	state.record_event("grantAid", ENGLAND, GENOA, {"amount": 100})
	var screen: CourtDossierScreen = _screen(state, ENGLAND)
	var pacifist: Button = _agenda_button(screen, "Peacemaker")
	assert_not_null(pacifist, "the quieter reading still has a row")
	assert_true(pacifist.text.begins_with("▸"), "a quiet agenda starts folded")
	pacifist.pressed.emit()
	assert_true(pacifist.text.begins_with("▾"), "a press unfolds its timeline")
	screen.free()


func test_a_quiet_court_says_so_instead_of_showing_an_empty_sheet() -> void:
	var screen: CourtDossierScreen = _screen(_state(), GENOA)
	assert_true(_screen_has_text(screen, "no act has yet spoken"), "the reading says it plainly")
	assert_true(_screen_has_text(screen, "No observable act has been written down."))
	assert_true(_screen_has_text(screen, "No observable act feeds this reading yet."))
	screen.free()


func test_the_build_notes_name_what_a_spy_watched() -> void:
	var state: DiplomacyState = _state()
	state.record_event(
		IntelEvidence.SPY_BUILD, ENGLAND, VIEWER, {"works": {"improvement": 2, "town": 1}}
	)
	state.record_event(IntelEvidence.SPY_TECH, ENGLAND, VIEWER, {"tech": "crop_rotation"})
	var screen: CourtDossierScreen = _screen(state, ENGLAND)
	assert_true(_screen_has_text(screen, "Under your spy's eye"), "the sightings are listed")
	assert_true(_screen_has_text(screen, "2 estates"))
	assert_true(_screen_has_text(screen, "1 town finished"))
	assert_true(_screen_has_text(screen, "1 finished study"))
	assert_true(_screen_has_text(screen, "Finished Crop Rotation while our spy watched."))
	screen.free()


func test_close_dismisses_the_sheet() -> void:
	var screen: CourtDossierScreen = _screen(_state(), ENGLAND)
	screen.close()
	assert_false(screen.is_open())
	screen.free()


func _agenda_button(screen: CourtDossierScreen, label: String) -> Button:
	for child: Node in screen._body.get_children():
		if child is Button and String((child as Button).text).contains(label):
			return child as Button
	return null


func _screen_has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _screen_has_text(child, needle):
			return true
	return false
