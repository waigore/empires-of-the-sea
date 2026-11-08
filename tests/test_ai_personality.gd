extends GdToolsTest
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
