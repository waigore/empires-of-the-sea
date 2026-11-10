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


func test_the_court_shows_the_pair_chronicle_under_its_orders() -> void:
	DiplomacyRules.declare_war(state, 0, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "CHRONICLE"))
	assert_true(_has_text(panel._detail, "Spain declared war on Genoa"))
	assert_true(_has_text(panel._detail, "Year 1500 (Turn 1)"))


func test_a_quiet_court_says_so_instead_of_showing_an_empty_box() -> void:
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "CHRONICLE"))
	assert_true(_has_text(panel._detail, "No word of this court"))


func test_the_court_shows_its_dossier_under_the_chronicle() -> void:
	DiplomacyRules.declare_war(state, 1, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "DOSSIER"), "the reading sits under the news")
	assert_true(_has_text(panel._detail, "Reading:"))
	assert_true(_has_text(panel._detail, "Declared war on Genoa."), "the act is evidence")
	assert_false(_has_text(panel._detail, "Confirmed"), "one act cannot confirm an agenda")


func test_a_quiet_court_says_the_dossier_is_empty() -> void:
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "DOSSIER"))
	assert_true(_has_text(panel._detail, "no act has yet spoken"))
	assert_true(_has_text(panel._detail, "No observable act"))


func test_the_dossier_bands_acts_and_trims_older_evidence() -> void:
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


func test_the_court_speaks_in_its_envoy_strip() -> void:
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "THEIR ENVOY"), "the court has a voice")
	assert_true(_has_text(panel._detail, "“"), "and quotes its word")


func test_the_envoy_carries_the_face_of_the_court() -> void:
	panel.select_faction(6)
	var faces: Array[String] = []
	for mood: String in DialogueMood.MOODS:
		faces.append(mood.to_upper())
	assert_true(_has_any_face(faces), "a documented face is worn")


func test_a_declaration_is_quoted_under_the_herald() -> void:
	DiplomacyRules.declare_war(state, 0, 6)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "THEIR ENVOY"))
	assert_true(
		_has_text(panel._detail, "·  IRRITATED") or _has_text(panel._detail, "·  DISMISSIVE"),
		"a war puts a hard face on the court"
	)


func test_a_waiting_proposal_banner_quotes_the_proposing_court() -> void:
	state.relation(0, 2).score = 80.0
	DiplomacyProposals.queue(state, null, 2, DiplomacyProposals.KIND_ALLIANCE)
	panel.refresh(state, null, 0, 2500)
	assert_true(_has_text(panel._call_box, "PROPOSAL  ·  "), "the face rides the banner")
	assert_true(_has_text(panel._call_box, "“"), "and the words under it")


func test_a_great_power_offers_the_trading_pact_in_the_trade_block() -> void:
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
	state.ftps[state.pair_key(0, 1)] = state.turn
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(1)
	assert_true(_has_text(panel._list, "Trade Pact"))
	assert_true(_has_text(panel._detail, "our lots clear first"))
	assert_not_null(_find_button(panel._detail, "End Favoured Trading Pact"))


func test_subsidy_options_carry_a_plain_price_hint() -> void:
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
	state.ensure_relation(0, 6, state.turn)
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 10)
	panel.refresh(state, null, 0, 2500)
	panel.select_faction(6)
	assert_true(_has_text(panel._detail, "✓ Set Subsidy · 10%"), "the standing rate is marked")
	assert_not_null(_find_button(panel._detail, "End Subsidy · 10%"))


func test_a_boycott_is_stated_in_the_trade_block() -> void:
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
