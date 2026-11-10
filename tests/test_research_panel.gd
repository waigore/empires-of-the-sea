extends GdToolsTest
## The research ledger renders live research state and emits intents
## (wiki: research-state; REQ-P2-03, REQ-P3-03).

var _panel: ResearchPanel = null
var _state: ResearchState = null


func before_each() -> void:
	_state = ResearchState.make()
	_panel = ResearchPanel.new()
	add_child(_panel)


func after_each() -> void:
	if is_instance_valid(_panel):
		_panel.free()
	_panel = null


func test_the_panel_lists_every_slot() -> void:
	_panel.refresh(_state, 2500)
	var idle: Array[Label] = _labels("Slot")
	assert_eq(idle.size(), ResearchState.DEFAULT_SLOTS)
	assert_gt(_panel.get_combined_minimum_size().y, 200.0)


func test_open_advances_are_listed_and_startable() -> void:
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
	for tech_id: String in ["crop_rotation", "saw_mill", "land_enclosure"]:
		_state.assign(tech_id)
	_panel.refresh(_state, 2500)
	for button: Button in _buttons():
		if button.text == "Research":
			assert_true(button.disabled)


func test_slots_show_progress_funding_and_cancel() -> void:
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
	var progress: Label = _label_containing("800 / 1800")
	assert_not_null(progress)


func test_known_techs_move_to_the_known_tab() -> void:
	_state.unlock("crop_rotation")
	_panel.refresh(_state, 2500)
	_panel.select_tab(1)
	var known: Label = _label_containing("Crop Rotation")
	assert_not_null(known)


func test_closing_emits_the_close_signal() -> void:
	var closed: Array[bool] = []
	_panel.close_pressed.connect(func() -> void: closed.append(true))
	var close: Button = _button("Close")
	assert_not_null(close)
	close.pressed.emit()
	assert_eq(closed.size(), 1)


# --- goal slot ---------------------------------------------------------------


func test_the_goal_strip_starts_empty() -> void:
	_panel.refresh(_state, 2500)
	assert_eq(_panel.goal_tech(), "")
	assert_not_null(_label_containing("No goal"))


func test_setting_a_goal_names_it_and_sorts_the_queue() -> void:
	_panel.refresh(_state, 2500)
	_panel.set_goal("national_bureaucracy")
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "national_bureaucracy")
	assert_not_null(_label_containing("National Bureaucracy"))
	assert_eq(_first_available(), "Printing Press", "a prerequisite of the goal leads the queue")


func test_the_goal_marks_its_path() -> void:
	_panel.refresh(_state, 2500)
	_panel.set_goal("national_bureaucracy")
	await get_tree().process_frame
	var marked: int = 0
	for node: Node in _nodes():
		if node is Label and (node as Label).text == ResearchRow.GOAL_ON_PATH:
			marked += 1
	assert_gt(marked, 0, "prerequisites on the goal's path carry the mark")


func test_clearing_the_goal_restores_catalog_order() -> void:
	_panel.refresh(_state, 2500)
	_panel.set_goal("national_bureaucracy")
	var clear: Button = _button("Clear")
	assert_not_null(clear)
	clear.pressed.emit()
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "")
	assert_eq(_first_available(), "Crop Rotation")


func test_the_goal_button_steers_the_queue() -> void:
	_panel.refresh(_state, 2500)
	var goal: Button = _button("Goal")
	assert_not_null(goal)
	var steered: Array[String] = []
	_panel.goal_changed.connect(func(tech_id: String) -> void: steered.append(tech_id))
	goal.pressed.emit()
	assert_eq(_panel.goal_tech(), "crop_rotation")
	assert_eq(steered, ["crop_rotation"])


func test_a_reached_goal_says_so() -> void:
	_panel.refresh(_state, 2500)
	_panel.set_goal("crop_rotation")
	_state.unlock("crop_rotation")
	_panel.refresh(_state, 2500)
	await get_tree().process_frame
	assert_not_null(_label_containing("reached"))


func test_an_unknown_goal_clears_it() -> void:
	_panel.refresh(_state, 2500)
	_panel.set_goal("crop_rotation")
	_panel.set_goal("no_such_tech")
	assert_eq(_panel.goal_tech(), "")


# --- helpers -----------------------------------------------------------------


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


# --- helpers -----------------------------------------------------------------


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
