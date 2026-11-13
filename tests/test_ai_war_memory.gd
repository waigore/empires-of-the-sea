extends GdToolsTest
## War memory (wiki: diplomacy § Cooldowns, § War goals and in-war reassessment;
## issue #475): a war that takes nothing wears the attacker down, and a peace
## that ends an unfought war holds the pair below the declaration bar past the
## 4-turn cooldown — so a crown stops re-declaring on the same enemy forever.

const AiFixture = preload("res://tests/ai_fixture.gd")

const OWNER: int = 0
const RIVAL: int = 1
const SEED: int = 1500


func _config(faction: int = RIVAL, agenda: String = AiAgenda.WARMONGER) -> AiConfig:
	return AiConfig.build(faction, SEED, AiProfile.NORMAL, agenda)


func _court() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(OWNER, RIVAL, 1)
	return state


# --- the arithmetic ----------------------------------------------------------


func test_a_war_inside_the_grace_carries_no_weariness() -> void:
	var config: AiConfig = _config()
	var ai_state := AiState.new()
	ai_state.note_war(RIVAL, OWNER, 10)
	var grace: int = config.parameter("diplomacy.war_weariness_grace")

	assert_eq(AiWarMemory.weariness(config, ai_state, 10, RIVAL, OWNER), 0)
	assert_eq(AiWarMemory.weariness(config, ai_state, 10 + grace, RIVAL, OWNER), 0)
	assert_eq(
		AiWarMemory.weariness(config, ai_state, 10 + grace + 1, RIVAL, OWNER),
		config.parameter("diplomacy.war_weariness"),
		"the first turn beyond the grace costs one step"
	)


func test_weariness_grows_turn_by_turn_and_stops_at_the_scale() -> void:
	var config: AiConfig = _config()
	var ai_state := AiState.new()
	ai_state.note_war(RIVAL, OWNER, 0)
	var grace: int = config.parameter("diplomacy.war_weariness_grace")
	var step: int = config.parameter("diplomacy.war_weariness")

	assert_eq(AiWarMemory.weariness(config, ai_state, grace + 3, RIVAL, OWNER), step * 3)
	assert_eq(AiWarMemory.weariness(config, ai_state, 400, RIVAL, OWNER), 100, "capped at the scale")


func test_a_truce_holds_the_pair_and_then_expires() -> void:
	var config: AiConfig = _config()
	var ai_state := AiState.new()
	ai_state.note_war(RIVAL, OWNER, 10)  # a two-turn war: unfought
	ai_state.note_truce(RIVAL, OWNER, 12)
	var turns: int = config.parameter("diplomacy.truce_turns")

	assert_eq(
		AiWarMemory.truce(config, ai_state, 12, RIVAL, OWNER),
		config.parameter("diplomacy.truce_penalty")
	)
	assert_eq(AiWarMemory.truce(config, ai_state, 12 + turns - 1, RIVAL, OWNER),
		config.parameter("diplomacy.truce_penalty"))
	assert_eq(AiWarMemory.truce(config, ai_state, 12 + turns, RIVAL, OWNER), 0)


func test_the_penalty_reads_the_right_memory_for_the_footing() -> void:
	var config: AiConfig = _config()
	var at_war := AiState.new()
	at_war.note_war(RIVAL, OWNER, 0)
	var peaceful := AiState.new()
	peaceful.note_war(RIVAL, OWNER, 0)
	peaceful.note_truce(RIVAL, OWNER, 1)
	var fought: int = config.parameter("diplomacy.war_weariness_grace") + 2
	var later: int = config.parameter("diplomacy.truce_turns") + 1

	assert_true(
		AiWarMemory.penalty(config, at_war, fought, RIVAL, OWNER, true) > 0,
		"at war the court reads its weariness"
	)
	assert_eq(
		AiWarMemory.penalty(config, peaceful, 1, RIVAL, OWNER, false),
		config.parameter("diplomacy.truce_penalty"),
		"at peace inside the truce an unfought war left it carries the truce"
	)
	assert_eq(
		AiWarMemory.penalty(config, peaceful, later, RIVAL, OWNER, false), 0,
		"past the truce a peace carries nothing"
	)
	assert_eq(AiWarMemory.penalty(null, at_war, fought, RIVAL, OWNER, true), 0)
	assert_eq(AiWarMemory.penalty(config, null, fought, RIVAL, OWNER, true), 0)


# --- the planner -------------------------------------------------------------


## One decision by the warmonger against a relation at war. The declaration is
## recorded so the weariness clock has a start.
func _decide(at_war: bool, turn: int, truce: int = -1, power: int = 10) -> Dictionary:
	var state: DiplomacyState = _court()
	var ai_state := AiState.new()
	ai_state.agendas[RIVAL] = AiAgenda.WARMONGER
	if at_war:
		assert_true(bool(DiplomacyRules.declare_war(state, RIVAL, OWNER)["ok"]))
		ai_state.note_war(RIVAL, OWNER, 1)
	if truce >= 0:
		ai_state.note_truce(RIVAL, OWNER, truce)
	return AiDiplomacyPlanner.decide(
		_config(), state, ai_state, AiFixture.world([OWNER, RIVAL, RIVAL, RIVAL]),
		turn, {
			"regiments": {}, "ships": {}, "player": OWNER,
			"power": {RIVAL: power, OWNER: 10},
		}
	)


func test_a_worn_attacker_puts_peace_to_an_even_enemy() -> void:
	var fresh: Dictionary = _decide(true, 1)
	assert_true(
		String(fresh["action"].get("kind", "")) != AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"inside the grace a warmonger keeps its war"
	)
	var worn: Dictionary = _decide(true, 200)
	assert_eq(
		String(worn["action"].get("kind", "")), AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"weariness ends a war no assault has won"
	)
	var candidate: Dictionary = (worn["candidates"] as Array)[0]
	assert_true(int(candidate["factors"].get("memory", 0)) < 0, "the trace names the weariness")


func test_a_court_that_clearly_outmatches_its_enemy_does_not_tire() -> void:
	# The war it is winning is the war it wants: no weariness, no white peace.
	var plan: Dictionary = _decide(true, 200, -1, 90)
	assert_true(
		String(plan["action"].get("kind", "")) != AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"a stronger court prosecutes its war"
	)


func test_a_truce_keeps_the_pair_below_the_declaration_bar() -> void:
	var barred: Dictionary = _decide(false, 8, 4)
	assert_true(
		String(barred["action"].get("kind", "")) != AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the 4-turn cooldown alone no longer re-opens the war"
	)
	var candidate: Dictionary = (barred["candidates"] as Array)[0]
	assert_eq(String(candidate["blocked"]), "war desire too low")
	assert_eq(
		int(candidate["factors"].get("memory", 0)),
		-_config().parameter("diplomacy.truce_penalty"),
		"the trace names the truce"
	)


func test_the_declaration_returns_once_the_truce_expires() -> void:
	var turn: int = 4 + _config().parameter("diplomacy.truce_turns")
	var freed: Dictionary = _decide(false, turn, 4, 90)
	assert_eq(
		String(freed["action"].get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the war may be declared again after the truce"
	)


func test_a_peace_concludes_and_records_the_truce() -> void:
	# The warmonger is worn past its bar, so the target takes the white peace the
	# planning pass offers; the pair then carries a truce.
	var state: DiplomacyState = _court()
	state.human_faction = -1
	assert_true(bool(DiplomacyRules.declare_war(state, RIVAL, OWNER)["ok"]))
	var ai_state := AiState.new()
	ai_state.agendas[RIVAL] = AiAgenda.WARMONGER
	ai_state.agendas[OWNER] = AiAgenda.WARMONGER
	ai_state.note_war(RIVAL, OWNER, 1)
	var run: Dictionary = AiTurn.run(
		state, AiFixture.world([OWNER, RIVAL]), ai_state,
		200, 4, SEED, {"regiments": {}, "ships": {}}
	)

	assert_true(
		ai_state.last_truce_turn.has(AiState.pair_key(OWNER, RIVAL)),
		"a concluded peace starts the truce"
	)
	assert_false((state.relation(RIVAL, OWNER) as DiplomacyRelation).at_war)
	assert_true(run.has("trace"))


func test_a_peace_offered_to_the_human_starts_the_truce_too() -> void:
	# The worn warmonger puts the white peace to the human court instead of
	# signing it: the offer alone ends its appetite, so a refusal does not hand
	# the court a fresh war at the cooldown (issue #475).
	var state: DiplomacyState = _court()
	state.human_faction = OWNER
	assert_true(bool(DiplomacyRules.declare_war(state, RIVAL, OWNER)["ok"]))
	var ai_state := AiState.new()
	ai_state.agendas[RIVAL] = AiAgenda.WARMONGER
	ai_state.note_war(RIVAL, OWNER, 1)
	AiTurn.run(
		state, AiFixture.world([OWNER, RIVAL]), ai_state,
		200, 4, SEED, {"regiments": {}, "ships": {}}
	)

	assert_true(
		ai_state.last_truce_turn.has(AiState.pair_key(OWNER, RIVAL)),
		"the offer starts the truce"
	)


func test_a_colonial_war_carries_the_same_memory() -> void:
	# A war on a Minor Nation or a Tribe is still a war the court pays for: an
	# unprosecuted one leaves the same truce a crown war does, so a court cannot
	# re-declare on the same colonial target at every cooldown (issue #511).
	var config: AiConfig = _config()
	var ai_state := AiState.new()
	var minor: int = FactionCatalog.minor_ids()[0]
	ai_state.note_war(RIVAL, minor, 0)
	ai_state.note_truce(RIVAL, minor, 4)

	assert_eq(
		AiWarMemory.weariness(config, ai_state, 400, RIVAL, minor),
		AiWarMemory.MAX_PENALTY,
		"a colonial war that runs on wears the court down"
	)
	assert_eq(
		AiWarMemory.truce(config, ai_state, 5, RIVAL, minor),
		config.parameter("diplomacy.truce_penalty"),
		"a white peace with a Minor holds the pair"
	)


# --- the colonial churn ------------------------------------------------------


## One decision against a Tribe the court has just white-peaced at `truce`.
func _decide_colonial(turn: int, truce: int, at_war: bool = false) -> Dictionary:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(RIVAL, tribe, 1)
	var ai_state := AiState.new()
	ai_state.agendas[RIVAL] = AiAgenda.WARMONGER
	ai_state.note_war(RIVAL, tribe, 1)
	if at_war:
		assert_true(bool(DiplomacyRules.declare_war(state, RIVAL, tribe)["ok"]))
	else:
		ai_state.note_truce(RIVAL, tribe, truce)
	return AiDiplomacyPlanner.decide(
		_config(), state, ai_state, AiFixture.world([RIVAL, tribe]),
		turn, {
			"regiments": {}, "ships": {}, "player": OWNER,
			"power": {RIVAL: 90, tribe: 5},
		}
	)


func test_a_colonial_truce_is_named_in_the_turn_trace() -> void:
	# The trace explains a colonial pair the way it explains a crown one: the
	# memory term is what the second declaration now has to clear (acceptance
	# of issue #511).
	var plan: Dictionary = _decide_colonial(12, 6)
	var candidate: Dictionary = (plan["candidates"] as Array)[0]
	assert_eq(
		int(candidate["factors"].get("memory", 0)),
		-_config().parameter("diplomacy.truce_penalty"),
		"the trace names the colonial truce"
	)


func test_a_colonial_pair_is_not_re_declared_inside_its_truce() -> void:
	# Same pair, one cooldown after the peace: with the truce read, the desire
	# no longer clears the declaration bar (issue #511).
	var plan: Dictionary = _decide_colonial(12, 6)
	assert_true(
		String(plan["action"].get("kind", "")) != AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"a white-peaced Tribe is not re-declared at the cooldown"
	)


func test_a_court_that_outmatches_a_tribe_still_tires() -> void:
	# The "clearly stronger" exemption is peer-only: against a Tribe the same
	# strength is the precondition for a landing, not evidence of one, so a
	# colonial war that takes nothing wears the court down (DR-20261114-01).
	var plan: Dictionary = _decide_colonial(200, -1, true)
	var candidate: Dictionary = (plan["candidates"] as Array)[0]
	assert_true(
		int(candidate["factors"].get("memory", 0)) < 0,
		"a court far stronger than a Tribe still carries the weariness"
	)


func test_a_fought_war_leaves_no_truce() -> void:
	var config: AiConfig = _config()
	var ai_state := AiState.new()
	ai_state.note_war(RIVAL, OWNER, 4)
	ai_state.note_truce(RIVAL, OWNER, 20)  # a 16-turn war: prosecuted

	assert_eq(
		AiWarMemory.truce(config, ai_state, 21, RIVAL, OWNER), 0,
		"a war that was fought ends in a real settlement"
	)


func test_a_save_round_trips_the_truce() -> void:
	var ai_state := AiState.new()
	ai_state.note_war(RIVAL, OWNER, 16)
	ai_state.note_truce(RIVAL, OWNER, 17)
	var restored := AiState.from_dict(ai_state.to_dict())

	assert_eq(
		AiWarMemory.truce(_config(), restored, 18, RIVAL, OWNER),
		_config().parameter("diplomacy.truce_penalty")
	)
