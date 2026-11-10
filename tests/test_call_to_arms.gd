extends GdToolsTest
## Mutual defence: a formal ally of a declared-upon Great Power is called to
## arms once, joins by relation or refuses with the unified penalty
## (wiki: diplomacy § Alliances § Mutual defence).

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_formal_ally_is_called_and_joins_at_fifty_or_better() -> void:
	_ally(1, 2, 80.0)
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 2)
	assert_true(war["ok"], war.get("reason", ""))
	assert_true(state.relation(1, 3).at_war, "England joins the war on Portugal")
	assert_true(_event("callToArmsAccepted"), "the answer is recorded in history")
	assert_eq(state.pending_calls.size(), 0, "AI allies need no consent prompt")


func test_informal_allied_band_alone_never_calls() -> void:
	state.relation(1, 2).score = 90.0
	assert_false(state.relation(1, 2).formal_alliance)
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 3, 2)
	assert_false(state.relation(1, 3).at_war, "no treaty, no obligation")
	assert_false(_event("callToArmsAccepted"))


func test_alliance_signed_this_turn_never_calls() -> void:
	state.relation(1, 2).formal_alliance = true
	state.relation(1, 2).score = 80.0
	# No snapshot: the treaty was signed after the preceding turn closed.
	DiplomacyRules.declare_war(state, 3, 2)
	assert_false(state.relation(1, 3).at_war)


func test_end_turn_freezes_alliances_for_the_next_turn() -> void:
	state.relation(1, 2).formal_alliance = true
	state.relation(1, 2).score = 80.0
	state.end_turn()
	DiplomacyRules.declare_war(state, 3, 2)
	assert_true(state.relation(1, 3).at_war)


func test_ai_ally_refuses_below_fifty_and_breaks_the_treaty() -> void:
	_ally(1, 2, 40.0)
	DiplomacyRules.declare_war(state, 3, 2)
	assert_false(state.relation(1, 3).at_war)
	assert_false(state.relation(1, 2).formal_alliance)
	assert_eq(state.relation(1, 2).score, 0.0, "−50 clamps at zero")
	assert_eq(state.relation(1, 0).score, 40.0, "−10 cascade to another GP")
	assert_eq(state.relation(1, 4).score, 40.0)
	assert_eq(state.relation(1, 5).score, 40.0)
	assert_eq(state.relation(1, 3).score, 50.0, "the aggressor is exempt")
	assert_true(_event("allianceBroken"))
	assert_true(_event("callToArmsRefused"))


func test_human_call_waits_for_consent() -> void:
	_ally(0, 2, 80.0)
	DiplomacyRules.declare_war(state, 3, 2)
	var call: Dictionary = CallToArms.pending_call_for(state, 0)
	assert_false(call.is_empty(), "the human court is asked")
	assert_eq(int(call["aggressor"]), 3)
	assert_eq(int(call["defender"]), 2)
	assert_false(state.relation(0, 3).at_war, "no war until the player answers")
	assert_true(CallToArms.has_pending(state, 0))
	var answer: Dictionary = CallToArms.resolve_human(state, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(state.relation(0, 3).at_war, "joining means war on the aggressor")
	assert_true(state.relation(0, 2).formal_alliance, "the alliance stands")
	assert_false(CallToArms.has_pending(state, 0))
	assert_true(_event("callToArmsAccepted"))


## The stakes line the court reads: the war it joins and the unified penalty a
## refusal costs (wiki: diplomacy § Alliances § Mutual defence, § Breaking an
## alliance).
func test_the_offer_names_what_each_answer_costs() -> void:
	_ally(0, 2, 80.0)
	DiplomacyRules.declare_war(state, 3, 2)
	var call: Dictionary = CallToArms.pending_call_for(state, 0)
	assert_false(call.is_empty(), "the court is asked")
	var text: String = CallToArms.offer_text(call)
	assert_true(text.contains("war against Portugal"), text)
	assert_true(text.contains("−50 with France"), text)
	assert_true(text.contains("−10 with every other Great Power"), text)


func test_human_join_cancels_subsidies_with_the_aggressor() -> void:
	_ally(0, 2, 80.0)
	state.set_subsidy(0, 3, 10)
	state.set_subsidy(3, 0, 5)
	DiplomacyRules.declare_war(state, 3, 2)
	CallToArms.resolve_human(state, true)
	assert_eq(state.subsidy(0, 3), 0)
	assert_eq(state.subsidy(3, 0), 0)


func test_human_refusal_applies_the_unified_penalty() -> void:
	_ally(0, 2, 90.0)
	DiplomacyRules.declare_war(state, 3, 2)
	var answer: Dictionary = CallToArms.resolve_human(state, false)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(state.relation(0, 2).formal_alliance)
	assert_eq(state.relation(0, 2).score, 40.0, "−50 with the abandoned ally")
	assert_eq(state.relation(0, 1).score, 40.0, "−10 cascade")
	assert_eq(state.relation(0, 4).score, 40.0)
	assert_eq(state.relation(0, 5).score, 40.0)
	assert_eq(state.relation(0, 3).score, 50.0, "the aggressor is exempt")
	assert_false(state.relation(0, 3).at_war)
	assert_true(_event("allianceBroken"))
	assert_true(_event("callToArmsRefused"))


func test_ally_already_at_war_with_the_aggressor_is_not_called() -> void:
	state.relation(1, 3).at_war = true
	_ally(1, 2, 80.0)
	DiplomacyRules.declare_war(state, 3, 2)
	assert_eq(CallToArms.candidates(state, 3, 2), [] as Array[int])
	assert_false(_event("callToArmsAccepted"))


func test_declaring_on_a_minor_never_calls_allies() -> void:
	_ally(1, 2, 80.0)
	DiplomacyRules.declare_war(state, 0, 6)
	assert_eq(CallToArms.candidates(state, 0, 6), [] as Array[int])
	assert_false(CallToArms.has_pending(state, 0))


func test_one_call_per_aggressor_and_defender_pair() -> void:
	assert_true(CallToArms.queue_human_call(state, 3, 2, 0))
	assert_false(CallToArms.queue_human_call(state, 3, 2, 0), "the same pair never asks twice")
	assert_eq(state.pending_calls.size(), 1)


func test_answering_without_a_waiting_call_is_refused() -> void:
	var answer: Dictionary = CallToArms.resolve_human(state, true)
	assert_false(answer["ok"])
	assert_false(state.relation(0, 3).at_war)


func _ally(a: int, b: int, score: float) -> void:
	var record: DiplomacyRelation = state.relation(a, b)
	record.formal_alliance = true
	record.score = score
	CallToArms.freeze_alliances(state)


func _event(kind: String) -> bool:
	for event: Dictionary in state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false
