extends GdToolsTest
## Rival proposals to the human court: an AI court offers an alliance or the
## next overture, the turn waits for the court, and the human's answer runs
## through the shared diplomacy rules (wiki: diplomacy § GP AI policy).

const AiFixture = preload("res://tests/ai_fixture.gd")

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_accepting_an_alliance_proposal_signs_the_treaty() -> void:
	state.relation(0, 2).score = 80.0
	var queued: Dictionary = DiplomacyProposals.queue(
		state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	assert_true(DiplomacyProposals.has_pending(state, 0))
	assert_false(state.relation(0, 2).formal_alliance, "nothing is signed before the answer")
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_true(state.relation(0, 2).formal_alliance, "the human answer forms the treaty")
	assert_false(DiplomacyProposals.has_pending(state, 0))
	assert_true(_event("allianceFormed"))
	assert_true(_event("proposalAccepted"))


func test_refusing_an_alliance_proposal_leaves_the_courts_at_peace() -> void:
	state.relation(0, 2).score = 80.0
	DiplomacyProposals.queue(state, null, 2, DiplomacyProposals.KIND_ALLIANCE)
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, null, false)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(bool(answer["accepted"]))
	assert_false(state.relation(0, 2).formal_alliance)
	assert_eq(state.relation(0, 2).score, 80.0, "a refusal costs no relation")
	assert_true(_event("proposalRefused"))


func test_accepting_an_overture_advances_both_directions_for_free() -> void:
	var queued: Dictionary = DiplomacyProposals.queue(
		state, null, 2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_eq(state.overture(2, 0), DiplomacyCatalog.STAGE_NAP)
	assert_eq(state.overture(0, 2), DiplomacyCatalog.STAGE_NAP)
	assert_true(_event("overtureEstablished"))
	assert_true(_event("proposalAccepted"))


func test_refusing_an_overture_keeps_the_previous_stage() -> void:
	DiplomacyProposals.queue(
		state, null, 2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, null, false)
	assert_false(bool(answer["accepted"]))
	assert_eq(state.overture(2, 0), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(_event("overtureRejected"))
	assert_true(_event("proposalRefused"))


func test_only_one_proposal_waits_on_the_court() -> void:
	state.relation(0, 2).score = 80.0
	state.relation(0, 3).score = 80.0
	assert_true(DiplomacyProposals.queue(state, null, 2, DiplomacyProposals.KIND_ALLIANCE)["ok"])
	var second: Dictionary = DiplomacyProposals.queue(
		state, null, 3, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(second["ok"], "the court answers one proposal at a time")
	assert_eq(state.pending_offers.size(), 1)


func test_no_proposal_is_offered_at_war_or_without_a_treaty_band() -> void:
	state.relation(0, 2).at_war = true
	var war: Dictionary = DiplomacyProposals.queue(
		state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(war["ok"])
	state.relation(0, 2).at_war = false
	state.relation(0, 2).score = 50.0
	var cool: Dictionary = DiplomacyProposals.queue(
		state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(cool["ok"], "the Allied band gates a formal alliance")


func test_accepting_a_peace_proposal_ends_the_war() -> void:
	state.relation(0, 2).at_war = true
	var queued: Dictionary = DiplomacyProposals.queue(
		state, null, 2, DiplomacyProposals.KIND_PEACE
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	assert_true(state.relation(0, 2).at_war, "the war holds until the court answers")
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_false(state.relation(0, 2).at_war, "the human answer ends the war")
	assert_false(DiplomacyProposals.has_pending(state, 0))
	assert_true(_event("peaceMade"))
	assert_true(_event("offerAccepted"))


func test_refusing_a_peace_proposal_keeps_the_war() -> void:
	state.relation(0, 2).at_war = true
	DiplomacyProposals.queue(state, null, 2, DiplomacyProposals.KIND_PEACE)
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, null, false)
	assert_false(bool(answer["accepted"]))
	assert_true(state.relation(0, 2).at_war, "a refusal does not end the war")
	assert_eq(state.relation(0, 2).score, 50.0, "a refusal costs no relation")
	assert_true(_event("offerRefused"))
	assert_false(_event("peaceMade"))


func test_a_peace_proposal_needs_a_war() -> void:
	var refused: Dictionary = DiplomacyProposals.queue(
		state, null, 2, DiplomacyProposals.KIND_PEACE
	)
	assert_false(refused["ok"], "white peace is offered only to a court at war")


func test_only_a_great_power_may_propose() -> void:
	state.relation(0, 6).at_war = true
	var minor: Dictionary = DiplomacyProposals.queue(
		state, null, 6, DiplomacyProposals.KIND_PEACE
	)
	assert_false(minor["ok"], "a Minor keeps no court to treat with")


func test_an_ai_court_proposes_peace_and_waits() -> void:
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.relation(0, 2).at_war = true
	var result: Dictionary = AiTurn.run(
		fresh,
		AiFixture.world([0, 0, 0, 0, 2]),
		AiState.new(),
		2,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(fresh.relation(0, 2).at_war, "nothing is signed during the AI pass")
	assert_eq(fresh.pending_offers.size(), 1, "the offer waits for the human court")
	assert_eq(String(fresh.pending_offers[0]["kind"]), DiplomacyProposals.KIND_PEACE)
	assert_true(String(record["message"]).contains("white peace"))


func test_describe_names_the_offer() -> void:
	assert_eq(
		DiplomacyProposals.describe(DiplomacyProposals.KIND_ALLIANCE, ""),
		"a formal alliance"
	)
	assert_eq(
		DiplomacyProposals.describe(
			DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
		),
		"the Non-Aggression Pact"
	)
	assert_eq(
		DiplomacyProposals.describe(DiplomacyProposals.KIND_PEACE, ""),
		"a white peace"
	)


func test_an_ai_court_offers_a_non_aggression_pact_and_waits() -> void:
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var result: Dictionary = AiTurn.run(
		fresh,
		AiFixture.world([0, 0, 0, 0, 2]),
		AiState.new(),
		1,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	var action: Dictionary = record["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_OVERTURE)
	assert_eq(String(action["stage"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(fresh.pending_offers.size(), 1, "the offer waits for the human court")
	assert_eq(
		fresh.overture(2, 0), DiplomacyCatalog.STAGE_EMBASSY,
		"nothing is signed during the AI pass"
	)
	assert_true(String(record["message"]).contains("proposes"))


func test_an_allied_court_proposes_a_formal_alliance() -> void:
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.relation(0, 2).score = 80.0
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var config: AiConfig = AiConfig.build(2, 1500)
	config.personality = AiPersonality.NEUTRAL
	config.agenda_traits = AiAgenda.NEUTRAL
	var context: Dictionary = AiFixture.context({0: 10, 2: 10}, {}, {})
	context["player"] = 0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, fresh, AiState.new(), AiFixture.world([2, 2, 2, 2, 1]), 1, context
	)
	assert_eq(
		String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_ALLIANCE,
		"the Allied band and a neutral agenda prefer the treaty"
	)


func test_the_improve_relations_cooldown_blocks_a_second_offer() -> void:
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var ai := AiState.new()
	ai.note_overture(2, 0, 1)
	var result: Dictionary = AiTurn.run(
		fresh,
		AiFixture.world([0, 0, 0, 0, 2]),
		ai,
		2,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_true((record["action"] as Dictionary).is_empty())
	assert_eq(
		String(record["candidates"][0]["offer"]["blocked"]), "overture cooldown"
	)


func _record_for(trace: Array, faction: int) -> Dictionary:
	for record: Dictionary in trace:
		if int(record["faction"]) == faction:
			return record
	return {}


func _event(kind: String) -> bool:
	for event: Dictionary in state.events:
		if String(event["kind"]) == kind:
			return true
	return false
