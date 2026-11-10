extends GdToolsTest
## The court panel's despatch block (wiki: civilian-units § Spy — court
## reports): a shadowed court shows last turn's report lines, an unwatched court
## shows nothing, and a quiet shadowed court says so (REQ-P5-02, REQ-P2-03).

const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6


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
