extends GdToolsTest
## The full court dossier sheet (wiki: ai-dossier § Logical sections; DR-20261110-25):
## basic intel, the reading, one timeline per agenda, the whole observation list
## and the behaviour/build notes (REQ-P5-01, REQ-P1-07, REQ-P2-03).

const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6


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
	assert_true(_has_text(screen, "THE DOSSIER"))
	assert_true(_has_text(screen, "England"), "the court is named")
	assert_true(_has_text(screen, "SUSPICION"))
	assert_true(_has_text(screen, "TIMELINE"))
	assert_true(_has_text(screen, "BEHAVIOUR & BUILD NOTES"))
	assert_true(_has_text(screen, "Reading:"), "the best guess leads")
	assert_true(_has_text(screen, "Warmonger"), "every agenda is listed, banded or not")
	assert_true(_has_text(screen, "Declared war on Genoa."), "the act reaches the page")
	screen.free()


func test_the_reading_names_the_band_never_the_agenda_truth() -> void:
	var state: DiplomacyState = _state()
	for _index in 4:
		state.record_event("warDeclared", ENGLAND, GENOA)
	var screen: CourtDossierScreen = _screen(state, ENGLAND)
	assert_true(_has_text(screen, "Likely 60%"), "the band and its confidence are printed")
	assert_false(_has_text(screen, "Confirmed 100%"), "nothing is certain at four acts")
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
	assert_true(_has_text(screen, "no act has yet spoken"), "the reading says it plainly")
	assert_true(_has_text(screen, "No observable act has been written down."))
	assert_true(_has_text(screen, "No observable act feeds this reading yet."))
	screen.free()


func test_the_build_notes_name_what_a_spy_watched() -> void:
	var state: DiplomacyState = _state()
	state.record_event(
		IntelDossier.SPY_BUILD, ENGLAND, VIEWER, {"works": {"improvement": 2, "town": 1}}
	)
	state.record_event(IntelDossier.SPY_TECH, ENGLAND, VIEWER, {"tech": "crop_rotation"})
	var screen: CourtDossierScreen = _screen(state, ENGLAND)
	assert_true(_has_text(screen, "Under your spy's eye"), "the sightings are listed")
	assert_true(_has_text(screen, "2 estates"))
	assert_true(_has_text(screen, "1 town finished"))
	assert_true(_has_text(screen, "1 finished study"))
	assert_true(_has_text(screen, "Finished Crop Rotation while our spy watched."))
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


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false
