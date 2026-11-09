extends GdToolsTest
## The court panel: faction rows, relation stand, order intents (REQ-P1 / P2).

var state: DiplomacyState
var panel: DiplomacyPanel


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)
	panel = DiplomacyPanel.new()
	add_child(panel)
	panel.refresh(state, null, 0, 2500)


func after_each() -> void:
	if is_instance_valid(panel):
		panel.free()
	panel = null


func test_lists_known_courts_and_selects_the_first() -> void:
	assert_eq(panel.selected_faction(), 1, "England sorts first among other Great Powers")
	assert_true(_has_text(panel._list, "England"))
	assert_true(_has_text(panel._list, "Genoa"))
	assert_false(_has_text(panel._list, "Aztec"), "uncontacted Tribes stay hidden")


func test_selecting_a_minor_updates_the_detail() -> void:
	panel.select_faction(6)
	assert_eq(panel.selected_faction(), 6)
	assert_true(_has_text(panel._detail, "Genoa"))
	assert_true(_has_text(panel._detail, "At Peace"))
	assert_true(_has_text(panel._detail, "Herald:"))


func test_relation_ladder_is_used_instead_of_the_raw_score() -> void:
	state.relation(0, 6).score = 92.0
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "Devoted"))
	assert_false(_has_text(panel._detail, "92"))


func test_the_ten_word_ladder_is_the_only_relation_wording() -> void:
	state.relation(0, 6).score = 22.4
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._list, "Distrustful"), "the court row carries the herald word")
	assert_true(_has_text(panel._detail, "Herald: Distrustful"))
	assert_false(_has_text(panel._detail, "Hostile"), "the superseded four-band word is not shown")


func test_order_buttons_emit_kind_target_and_argument() -> void:
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
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "An embassy is required before aid can be sent."))
	var button: Button = _find_button(panel._detail, "Grant Aid")
	assert_not_null(button)
	assert_true(button.disabled)


func test_at_war_updates_the_stand_and_offers_peace() -> void:
	DiplomacyRules.declare_war(state, 0, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "At War"))
	assert_not_null(_find_button(panel._detail, "Offer Peace"))


func test_no_relations_shows_an_empty_court() -> void:
	state.reset(1)
	panel.refresh(state, null, 0, 2500)
	assert_eq(panel.selected_faction(), -1)
	assert_true(_has_text(panel._detail, "No court"))


func test_a_waiting_intervention_prompts_and_emits_the_answer() -> void:
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


func test_a_rival_proposal_prompts_and_emits_the_answer() -> void:
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
