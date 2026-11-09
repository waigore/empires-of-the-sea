extends GdToolsTest
## Third-party intervention on a war against a Minor Nation or Tribe
## (wiki: diplomacy § Intervention). Embassy courts choose to join, stand aside
## or protest; AI courts roll the relation bands deterministically.

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_a_war_between_great_powers_never_invites_intervention() -> void:
	state.set_overture(1, 2, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(Intervention.candidates(state, 3, 2), [] as Array[int])
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 2)
	assert_eq(war.get("interventions", []), [] as Array[String])


func test_an_embassy_in_the_victim_court_makes_a_candidate() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(Intervention.has_embassy(state, 1, 6))
	assert_eq(Intervention.candidates(state, 3, 6), [1] as Array[int])


func test_a_consulate_alone_does_not_qualify() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(Intervention.candidates(state, 3, 6), [] as Array[int])


func test_nap_and_join_empire_keep_the_embassy() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(4, 6, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	assert_eq(Intervention.candidates(state, 3, 6), [1, 4] as Array[int])


func test_the_human_court_is_asked_once_per_declaration() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 6)
	var offer: Dictionary = Intervention.pending_for(state, 0)
	assert_false(offer.is_empty(), "the embassy court is asked")
	assert_eq(int(offer["aggressor"]), 3)
	assert_eq(int(offer["target"]), 6)
	assert_true(Intervention.has_pending(state, 0))
	assert_false(Intervention.queue_human(state, 3, 6, 0), "the same pair never asks twice")
	assert_eq(state.pending_interventions.size(), 1)
	assert_false(bool(war.get("interventions", []).is_empty()), "the court is told")


func test_intervening_joins_the_war_and_keeps_the_embassy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(state, Intervention.KIND_INTERVENE)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(state.relation(0, 3).at_war, "war on the aggressor starts immediately")
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(Intervention.has_pending(state, 0))
	assert_true(_event("interventionIntervened"))


func test_standing_aside_costs_the_embassy_and_subsidy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 10)
	DiplomacyRules.declare_war(state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(state, Intervention.KIND_NOTHING)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.subsidy(0, 6), 0)
	assert_false(state.relation(0, 3).at_war)
	assert_eq(state.relation(0, 3).score, 50.0, "standing aside is not a diplomatic act")
	assert_true(_event("interventionDoNothing"))


func test_protest_penalises_the_aggressor_and_keeps_the_embassy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(state, Intervention.KIND_PROTEST)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(state.relation(0, 3).at_war)
	assert_eq(state.relation(0, 3).score, 40.0, "−10 protest penalty")
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(_event("interventionProtest"))


func test_propaganda_softens_the_protest() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	Intervention.resolve_human(state, Intervention.KIND_PROTEST, {"propaganda": true})
	assert_eq(state.relation(0, 3).score, 45.0, "−5 against a propaganda aggressor")


func test_answering_without_an_offer_is_refused() -> void:
	var answer: Dictionary = Intervention.resolve_human(
		state, Intervention.KIND_INTERVENE
	)
	assert_false(answer["ok"])
	assert_false(state.relation(0, 3).at_war)


func test_ai_chance_follows_the_documented_bands() -> void:
	assert_eq(Intervention.chance_for(0.0), 0.0)
	assert_eq(Intervention.chance_for(25.0), 0.0)
	assert_eq(Intervention.chance_for(26.0), 0.25)
	assert_eq(Intervention.chance_for(50.0), 0.25)
	assert_eq(Intervention.chance_for(51.0), 0.5)
	assert_eq(Intervention.chance_for(75.0), 0.5)
	assert_eq(Intervention.chance_for(76.0), 0.8)
	assert_eq(Intervention.chance_for(100.0), 0.8)


func test_the_ai_roll_is_a_stable_unit_sample() -> void:
	var first: float = Intervention.roll(7, 3, 6, 1)
	assert_eq(first, Intervention.roll(7, 3, 6, 1), "replays decide the same way")
	assert_true(first >= 0.0 and first < 1.0)


func test_ai_intervention_follows_the_band() -> void:
	state.relation(1, 6).score = 90.0
	var expected: bool = Intervention.roll(state.turn, 3, 6, 1) < 0.8
	assert_eq(Intervention.ai_intervenes(state, 1, 3, 6), expected)
	state.relation(1, 6).score = 10.0
	assert_false(Intervention.ai_intervenes(state, 1, 3, 6), "0% never intervenes")


func test_a_court_already_at_war_with_the_aggressor_is_not_asked() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 3).at_war = true
	assert_eq(Intervention.candidates(state, 3, 6), [] as Array[int])


func test_a_tribe_war_can_invite_intervention() -> void:
	state.set_overture(1, 9, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(Intervention.candidates(state, 3, 9), [1] as Array[int])


func test_ai_answers_are_applied_at_the_declaration() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 6).score = 90.0
	var intervenes: bool = Intervention.roll(state.turn, 3, 6, 1) < 0.8
	DiplomacyRules.declare_war(state, 3, 6)
	assert_eq(state.relation(1, 3).at_war, intervenes, "the roll is the documented band")
	if not intervenes:
		assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "standing aside loses it")


func test_an_absorbed_faction_drops_its_waiting_offer() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	assert_true(Intervention.has_pending(state, 0))
	state.clear_relations_of(6)
	assert_false(Intervention.has_pending(state, 0))


func _event(kind: String) -> bool:
	for event: Dictionary in state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false
