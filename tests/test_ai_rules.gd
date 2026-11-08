extends GdToolsTest
## Pure AI contracts: power bands, parameters, personalities and turn records.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const AiFixture = preload("res://tests/ai_fixture.gd")

# --- from test_ai_power.gd ---
## Power score and relative-power bands (wiki: diplomacy § Great Power power
## score, § GP AI policy for war vs. relations).


func test_relative_power_bands_match_the_wiki() -> void:
	assert_eq(int(AiPower.relative_band(135, 100)["bonus"]), 30)
	assert_eq(int(AiPower.relative_band(134, 100)["bonus"]), 5)
	assert_eq(int(AiPower.relative_band(85, 100)["bonus"]), 5)
	assert_eq(int(AiPower.relative_band(84, 100)["bonus"]), -25)
	assert_almost_eq(float(AiPower.relative_band(135, 100)["relative"]), 1.35, 0.0001)


func test_zero_target_power_counts_as_one() -> void:
	assert_almost_eq(float(AiPower.relative_band(10, 0)["relative"]), 10.0, 0.0001)
	assert_eq(int(AiPower.relative_band(0, 0)["bonus"]), -25)


func test_power_score_uses_provinces_regiments_and_ships() -> void:
	var world: WorldMap = AiFixture.world([7, 7, 1])
	assert_eq(AiPower.score(world, 7, 3, 2), 33, "2×10 + 3×1 + 2×5")
	assert_eq(AiPower.score(world, 1), 10)
	assert_eq(AiPower.score(world, 4), 0)


func test_power_score_weights_are_overridable() -> void:
	var world: WorldMap = AiFixture.world([7, 7, 1])
	assert_eq(AiPower.score(world, 7, 3, 2, {"province": 5}), 23, "2×5 + 3 + 10")
	assert_eq(AiPower.score(world, 7, 3, 2, {"ship": 0}), 23, "2×10 + 3 + 0")


func test_power_score_without_a_world_is_zero() -> void:
	assert_eq(AiPower.score(null, 7, 9, 9), 0)

# --- from test_ai_parameters.gd ---
## AI parameter registry and blessed profiles (wiki: ai-parameter-registry,
## ai-profile-overrides).


func test_registry_exposes_the_documented_defaults() -> void:
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_desire_base"), 50)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_declare_min_desire"), 51)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_relation_ceiling"), 50)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_cooldown_turns"), 4)
	assert_eq(AiParameterRegistry.default_of("diplomacy.overture_cooldown_turns"), 2)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_province_weight"), 10)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_regiment_weight"), 1)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_ship_weight"), 5)
	assert_eq(AiParameterRegistry.keys().size(), AiParameterRegistry.PARAMETERS.size())


func test_unknown_keys_fall_back_instead_of_crashing() -> void:
	assert_false(AiParameterRegistry.has("diplomacy.made_up"))
	assert_eq(AiParameterRegistry.default_of("diplomacy.made_up", -1), -1)
	assert_eq(AiParameterRegistry.resolve("diplomacy.made_up"), 0)
	assert_eq(AiParameterRegistry.in_bounds("diplomacy.made_up", 1), false)


func test_resolve_prefers_an_in_bounds_override() -> void:
	var overrides: Dictionary = {"diplomacy.war_relation_ceiling": 70}
	assert_eq(AiParameterRegistry.resolve("diplomacy.war_relation_ceiling", overrides), 70)
	assert_eq(
		AiParameterRegistry.resolve("diplomacy.war_declare_min_desire", overrides), 51,
		"missing keys inherit the registry default"
	)


func test_resolve_ignores_out_of_bounds_and_non_integer_overrides() -> void:
	assert_eq(
		AiParameterRegistry.resolve(
			"diplomacy.war_relation_ceiling", {"diplomacy.war_relation_ceiling": 200}
		),
		50
	)
	assert_eq(
		AiParameterRegistry.resolve(
			"diplomacy.war_relation_ceiling", {"diplomacy.war_relation_ceiling": "high"}
		),
		50
	)
	assert_eq(
		AiParameterRegistry.resolve(
			"diplomacy.war_relation_ceiling", {"diplomacy.war_relation_ceiling": 62.5}
		),
		50
	)


func test_validate_rejects_unknown_and_invalid_values() -> void:
	var good: Dictionary = AiParameterRegistry.validate(
		{"diplomacy.war_declare_min_desire": 45}
	)
	assert_true(bool(good["ok"]))
	var bad: Dictionary = AiParameterRegistry.validate(
		{"diplomacy.nope": 1, "diplomacy.war_cooldown_turns": 99}
	)
	assert_false(bool(bad["ok"]))
	assert_eq(bad["rejected"], ["diplomacy.nope", "diplomacy.war_cooldown_turns"])


func test_blessed_profiles_override_the_registry() -> void:
	assert_true(AiProfile.has(AiProfile.AGGRESSIVE))
	assert_false(AiProfile.has("bogus"))
	assert_eq(
		AiProfile.resolve("diplomacy.war_relation_ceiling", AiProfile.AGGRESSIVE), 70
	)
	assert_eq(
		AiProfile.resolve("diplomacy.war_declare_min_desire", AiProfile.ECONOMIC), 65
	)
	assert_eq(
		AiProfile.resolve("diplomacy.war_relation_ceiling", "bogus"), 50,
		"an unknown profile falls back to neutral defaults"
	)
	assert_true(bool(AiProfile.validate(AiProfile.AGGRESSIVE)["ok"]))
	assert_false(bool(AiProfile.validate("bogus")["ok"]))
	assert_eq(AiProfile.ids().size(), 3)

# --- from test_ai_personality.gd ---
## AI personalities and hidden agendas (wiki: ai-personalities, hidden-agendas).


func test_each_great_power_maps_to_a_canonical_leader() -> void:
	assert_eq(AiPersonality.leader_for(FactionCatalog.PLAYER_FACTION), "isabella")
	assert_eq(AiPersonality.leader_for(1), "victoria")
	assert_eq(AiPersonality.leader_for(2), "napoleon")
	assert_eq(AiPersonality.leader_for(3), "henry")
	assert_eq(AiPersonality.leader_for(4), "de_ruyter")
	assert_eq(AiPersonality.leader_for(5), "gustavus")
	assert_eq(AiPersonality.leader_for(99), LeaderCatalog.DEFAULT_KEY)
	assert_eq(AiPersonality.keys().size(), 7)


func test_known_leaders_resolve_to_their_archetype() -> void:
	assert_eq(String(AiPersonality.resolve("napoleon")["title"]), "fortifier")
	assert_eq(String(AiPersonality.resolve("victoria")["title"]), "industrial_trader")
	assert_eq(int(AiPersonality.resolve("napoleon")["war_bias"]), 15)
	assert_eq(int(AiPersonality.resolve("henry")["war_gate"]), -20)


func test_unknown_leaders_get_neutral_defaults() -> void:
	var neutral: Dictionary = AiPersonality.resolve("cleopatra")
	assert_eq(String(neutral["title"]), "reserve")
	assert_eq(int(neutral["war_bias"]), 0)
	assert_eq(int(neutral["war_gate"]), 0)
	assert_eq(int(AiPersonality.for_faction(99).get("war_bias", -99)), 0)


func test_domain_weights_follow_the_leader() -> void:
	assert_eq(int(AiPersonality.weights_for(1)["diplomacy"]), 3)
	assert_eq(int(AiPersonality.weights_for(2)["military"]), 3)
	assert_eq(int(AiPersonality.weights_for(0)["economy"]), 2)


func test_agenda_assignment_is_deterministic() -> void:
	var first: String = AiAgenda.assign(1500, 3)
	assert_eq(AiAgenda.assign(1500, 3), first)
	assert_in(first, AiAgenda.IDS)
	for faction: int in FactionCatalog.great_power_ids():
		assert_in(AiAgenda.assign(1500, faction), AiAgenda.IDS)


func test_agenda_modifiers_shift_war_thresholds() -> void:
	assert_eq(int(AiAgenda.resolve(AiAgenda.WARMONGER)["war_gate"]), 20)
	assert_eq(int(AiAgenda.resolve(AiAgenda.PEACEMAKER)["war_gate"]), -20)
	assert_eq(int(AiAgenda.resolve(AiAgenda.ISOLATIONIST)["alliance_bias"]), -25)
	var unknown: Dictionary = AiAgenda.resolve("no_such_agenda")
	assert_eq(int(unknown["war_gate"]), 0)
	assert_false(AiAgenda.has("no_such_agenda"))


func test_config_combines_leader_agenda_and_profile() -> void:
	var config: AiConfig = AiConfig.build(2, 1500, AiProfile.AGGRESSIVE, AiAgenda.PEACEMAKER)
	assert_eq(config.leader, "napoleon")
	assert_eq(config.profile, AiProfile.AGGRESSIVE)
	assert_eq(config.agenda, AiAgenda.PEACEMAKER)
	assert_eq(config.parameter("diplomacy.war_relation_ceiling"), 70, "profile wins")
	assert_eq(
		config.war_relation_ceiling(), 70,
		"napoleon +20 then peacemaker -20 cancel out"
	)
	assert_eq(config.war_bias(), 0, "+15 personality and -15 agenda cancel out")
	assert_eq(int(config.weights()["military"]), 3)


func test_config_keeps_the_first_agenda_for_the_run() -> void:
	var state := AiState.new()
	var first: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.WARMONGER)
	var second: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.PEACEMAKER)
	assert_eq(state.agenda_for(first), AiAgenda.WARMONGER)
	assert_eq(state.agenda_for(second), AiAgenda.WARMONGER, "agenda is fixed at game start")

# --- from test_ai_turn.gd ---
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
