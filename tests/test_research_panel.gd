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
