extends GdToolsTest
## Rival court proposals: one queued offer at a time, the human's answer, the
## proposing rival paying, and the price/utility order against war and peace
## (wiki: diplomacy § Court proposals; DR-20261109-06).

const Fixture = preload("res://tests/map_fixture.gd")
const AiFixture = preload("res://tests/ai_fixture.gd")

var state: DiplomacyState
var ai: AiState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)
	ai = AiState.new()


func test_a_proposal_is_queued_and_only_one_may_wait() -> void:
	var first: Dictionary = DiplomacyProposals.offer(
		state, 1, 0, DiplomacyProposals.OFFER_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	assert_true(bool(first["ok"]), String(first.get("reason", "")))
	assert_eq(state.pending_proposals.size(), 1)
	assert_true(DiplomacyProposals.has_pending(state, 0))
	var second: Dictionary = DiplomacyProposals.offer(
		state, 2, 0, DiplomacyProposals.OFFER_ALLIANCE
	)
	assert_false(bool(second["ok"]), "a second rival waits its turn")
	assert_eq(state.pending_proposals.size(), 1)
	assert_true(_event("proposalOffered"))


func test_paid_overture_stages_and_war_are_never_proposed() -> void:
	var paid: Dictionary = DiplomacyProposals.offer(
		state, 1, 0, DiplomacyProposals.OFFER_OVERTURE, DiplomacyCatalog.STAGE_EMBASSY
	)
	assert_false(bool(paid["ok"]), "rivals only offer cost-free stages")
	state.relation(1, 0).at_war = true
	var war: Dictionary = DiplomacyProposals.offer(
		state, 1, 0, DiplomacyProposals.OFFER_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	assert_false(bool(war["ok"]), "no proposal while at war")


func test_accepting_an_overture_advances_both_ways_without_human_cost() -> void:
	DiplomacyProposals.offer(
		state, 1, 0, DiplomacyProposals.OFFER_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, ai, true)
	assert_true(bool(answer["ok"]))
	assert_true(bool(answer["accepted"]))
	assert_eq(state.overture(1, 0), DiplomacyCatalog.STAGE_NAP)
	assert_eq(state.overture(0, 1), DiplomacyCatalog.STAGE_NAP)
	assert_eq(state.pending_proposals.size(), 0)
	assert_true(_event("overtureEstablished"))
	assert_true(
		ai.overture_on_cooldown(1, 0, 1, 2), "the answer starts the pair's cooldown"
	)


func test_refusing_changes_no_score_and_still_starts_the_cooldown() -> void:
	DiplomacyProposals.offer(
		state, 1, 0, DiplomacyProposals.OFFER_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	var before: float = state.relation(0, 1).score
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, ai, false)
	assert_true(bool(answer["ok"]))
	assert_false(bool(answer["accepted"]))
	assert_eq(state.relation(0, 1).score, before, "a refusal costs no relation")
	assert_eq(state.overture(1, 0), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(ai.overture_on_cooldown(1, 0, 1, 2))
	assert_true(_event("proposalRefused"))


func test_accepting_an_alliance_runs_the_shared_treaty_rules() -> void:
	state.relation(1, 0).score = 80.0
	DiplomacyProposals.offer(state, 1, 0, DiplomacyProposals.OFFER_ALLIANCE)
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, ai, true)
	assert_true(bool(answer["accepted"]))
	assert_true(state.relation(0, 1).formal_alliance)
	assert_true(state.relation(0, 1).score >= DiplomacyCatalog.ALLIANCE_CLAMP)


func test_planner_proposes_the_next_free_overture_at_peace() -> void:
	var plan: Dictionary = _plan(1, 50.0, AiAgenda.TECH_THIEF)
	var action: Dictionary = plan["action"]
	assert_eq(String(action.get("kind", "")), AiDiplomacyPlanner.KIND_PROPOSAL)
	assert_eq(String(action.get("offer", "")), DiplomacyProposals.OFFER_OVERTURE)
	assert_eq(String(action.get("stage", "")), DiplomacyCatalog.STAGE_NAP)


func test_planner_prefers_an_alliance_on_a_utility_tie() -> void:
	var plan: Dictionary = _plan(1, 80.0, AiAgenda.TECH_THIEF)
	var action: Dictionary = plan["action"]
	assert_eq(String(action.get("kind", "")), AiDiplomacyPlanner.KIND_PROPOSAL)
	assert_eq(
		String(action.get("offer", "")),
		DiplomacyProposals.OFFER_ALLIANCE,
		"alliance wins the tie"
	)


func test_declare_war_outranks_every_proposal() -> void:
	var plan: Dictionary = _plan(2, 20.0, AiAgenda.TECH_THIEF)
	assert_eq(
		String(plan["action"].get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR
	)


func test_offer_peace_outranks_a_proposal_while_at_war() -> void:
	state.relation(1, 0).score = 80.0
	state.relation(1, 2).at_war = true
	var plan: Dictionary = _plan(1, 80.0, AiAgenda.TECH_THIEF)
	assert_eq(
		String(plan["action"].get("kind", "")), AiDiplomacyPlanner.KIND_OFFER_PEACE
	)


func test_a_waiting_proposal_suspends_the_turn_until_answered() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	var play: PlaySession = screen.play
	DiplomacyProposals.offer(
		play.diplomacy, 1, play.player_faction, DiplomacyProposals.OFFER_OVERTURE,
		DiplomacyCatalog.STAGE_NAP
	)
	MapPlayDiplomacy.open(play)
	assert_true(screen.hud.panels.diplomacy_panel._call_box.visible, "the court asks")
	var turn_before: int = play.turn
	MapPlayTurn.end_turn(play)
	assert_eq(play.turn, turn_before, "the calendar waits for the answer")
	assert_true(play.turn_suspended)
	MapPlayTurn.answer_proposal(play, true)
	assert_eq(play.diplomacy.overture(play.player_faction, 1), DiplomacyCatalog.STAGE_NAP)
	assert_eq(play.turn, turn_before + 1)
	assert_false(DiplomacyProposals.has_pending(play.diplomacy, play.player_faction))
	screen.free()


func test_a_waiting_proposal_survives_a_save_round_trip() -> void:
	DiplomacyProposals.offer(
		state, 1, 0, DiplomacyProposals.OFFER_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	var restored: DiplomacyState = SaveCodec._diplomacy_from(
		SaveCodec._capture_diplomacy(state)
	)
	assert_eq(restored.pending_proposals.size(), 1)
	assert_eq(int(restored.pending_proposals[0]["from"]), 1)
	assert_eq(String(restored.pending_proposals[0]["stage"]), DiplomacyCatalog.STAGE_NAP)


func _plan(faction: int, human_score: float, agenda: String) -> Dictionary:
	state.relation(faction, 0).score = human_score
	var config: AiConfig = AiConfig.build(faction, 1500, AiProfile.NORMAL, agenda)
	var world: WorldMap = AiFixture.world([2, 2, 2, 2, 1])
	var context: Dictionary = {
		"power": {0: 10, 1: 10, 2: 20, 3: 10, 4: 10, 5: 10},
		"regiments": {},
		"ships": {},
		"player": 0,
	}
	return AiDiplomacyPlanner.decide(config, state, ai, world, 1, context)


func _event(kind: String) -> bool:
	for event: Dictionary in state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false