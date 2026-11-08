extends GdToolsTest

const AiFixture = preload("res://tests/ai_fixture.gd")
## AI turn pass: one config per rival Great Power, legal orders applied through
## the shared rules, and a per-court trace (wiki: ai-architecture,
## turn-trace-interpretation).


func test_every_rival_court_takes_its_turn_and_traces_it() -> void:
	var run: Dictionary = _run()
	var trace: Array = run["result"]["trace"]
	assert_eq(trace.size(), 5, "five rival Great Powers, player excluded")
	var factions: Array[int] = []
	for record: Dictionary in trace:
		factions.append(int(record["faction"]))
		assert_false(String(record["leader"]).is_empty())
		assert_false(String(record["agenda"]).is_empty())
		assert_true(record.has("candidates"))
	assert_false(factions.has(FactionCatalog.PLAYER_FACTION), "the human court is never scripted")
	assert_eq(factions, [1, 2, 3, 4, 5])


func test_strong_rival_declares_war_through_the_rules() -> void:
	var run: Dictionary = _run()
	var state: DiplomacyState = run["state"]
	var record: Dictionary = _record_for(run["result"]["trace"], 2)
	var action: Dictionary = record["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_eq(int(action["target"]), 1)
	assert_eq(int(action["desired_territory"]), 1, "England holds one province")
	assert_true(state.relation(1, 2).at_war, "the shared rules applied the declaration")
	assert_true(String(record["message"]).contains("declares war"))
	assert_in(String(record["message"]), run["result"]["messages"])
	assert_true(
		(run["ai"] as AiState).war_on_cooldown(2, 1, 1, 4), "the pair starts its cooldown"
	)


func test_weak_rival_cannot_find_a_legal_war() -> void:
	var run: Dictionary = _run()
	var record: Dictionary = _record_for(run["result"]["trace"], 1)
	assert_true((record["action"] as Dictionary).is_empty())
	var candidate: Dictionary = record["candidates"][0]
	assert_false(String(candidate["blocked"]).is_empty(), "the trace explains the refusal")


func test_a_second_turn_does_not_repeat_the_war() -> void:
	var run: Dictionary = _run()
	var result: Dictionary = AiTurn.run(
		run["state"], AiFixture.world([2, 2, 2, 2, 1]), run["ai"], 2, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_true((record["action"] as Dictionary).is_empty())
	assert_eq(String(record["candidates"][0]["blocked"]), "war still worth waging")


func test_same_seed_and_state_produce_the_same_orders() -> void:
	var first: Dictionary = _run()
	var second: Dictionary = _run()
	assert_eq(
		String(_record_for(first["result"]["trace"], 2)["action"]["kind"]),
		String(_record_for(second["result"]["trace"], 2)["action"]["kind"])
	)
	assert_eq(
		(int(_record_for(first["result"]["trace"], 2)["action"]["target"])),
		(int(_record_for(second["result"]["trace"], 2)["action"]["target"]))
	)


func test_map_phase_runs_the_ai_without_views() -> void:
	var play := PlaySession.new()
	play.world = AiFixture.world([2, 2, 2, 2, 1])
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	play.diplomacy.ensure_relation(1, 2, 1)
	play.map_seed = 1500
	MapPlayDiplomacy.run_ai(play)
	assert_not_null(play.ai)
	assert_eq(play.ai_trace.size(), 5)
	assert_true(play.diplomacy.relation(1, 2).at_war)


func _run() -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(1, 2, 1)
	var ai_state := AiState.new()
	var result: Dictionary = AiTurn.run(
		state,
		AiFixture.world([2, 2, 2, 2, 1]),
		ai_state,
		1,
		FactionCatalog.PLAYER_FACTION,
		1500,
		{"regiments": {}, "ships": {}}
	)
	return {"state": state, "ai": ai_state, "result": result}


func _record_for(trace: Array, faction: int) -> Dictionary:
	for record: Dictionary in trace:
		if int(record["faction"]) == faction:
			return record
	return {}
