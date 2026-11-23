extends GdToolsTest
## Pure AI contracts: power bands, parameters, personalities and turn records,
## the war-footing phase and the civilian work planners.
## Merged from test_ai_phase_rules, test_ai_work_rules, test_ai_campaign_rules
## and test_ai_planner_rules so coverage pays a single Godot boot for the whole
## AI surface (docs/testing.md speed rules).

const AiFixture = preload("res://tests/ai_fixture.gd")
const NavalFixture = preload("res://tests/naval_fixture.gd")
const CivilianFixture = preload("res://tests/civilian_fixture.gd")


## Collects the sighting lines a rival naval pass emits.
class StubHud extends GameHud:
	var toasts: Array[String] = []

	func toast(text: String, _icon_name: String = "") -> void:
		toasts.append(text)

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


## The planner weighs relative power by the published order of battle — FPN + FPM
## over every land army — and never by a head count (wiki: diplomacy § Great
## Power power score). Forty guards against five is a strong court even though
## the stronger court holds fewer provinces.
func test_the_planner_reads_power_from_the_order_of_battle() -> void:
	var owners: Array[int] = []
	for _index in 5:
		owners.append(0)
	for _index in 20:
		owners.append(1)
	var world: WorldMap = AiFixture.world(owners)
	var context: Dictionary = AiTurnRead.context(
		world,
		{"regiments": {0: 40, 1: 5}, "ships": {}, "strengths": {0: 360.0, 1: 45.0}},
		0
	)
	assert_eq(int(context["power"][0]), 410, "5 × 10 provinces + 360 strength")
	assert_eq(int(context["power"][1]), 245, "20 × 10 provinces + 45 strength")
	assert_eq(
		int(AiPower.relative_band(
			int(context["power"][0]), int(context["power"][1])
		)["bonus"]),
		30,
		"the published score makes this a strong court"
	)

## A caller that supplies no order of battle keeps the legacy head count, so a
## headless fixture (no army layer) still scores instead of reading zero.
func test_a_context_without_strengths_keeps_the_head_count() -> void:
	var world: WorldMap = AiFixture.world([0, 0, 0, 0, 0, 1, 1, 1])
	var context: Dictionary = AiTurnRead.context(
		world, {"regiments": {0: 40, 1: 5}, "ships": {}}, 0
	)
	assert_eq(int(context["power"][0]), 90, "5 × 10 provinces + 40 regiments")
	assert_eq(int(context["power"][1]), 35, "3 × 10 provinces + 5 regiments")
	assert_false(context.has("strengths"), "no strength map to hand a view")

## A court's charted docket carries the orders of battle it has seen, so a rival
## weighs the power of the armies it knows of by their weight, not their count
## (wiki: diplomacy § Great Power power score; DR-20261112-09).
func test_a_charted_docket_powers_the_reading_by_strength() -> void:
	var world: WorldMap = AiFixture.world([0, 0, 1, 1])
	var context: Dictionary = AiTurnRead.context(
		world,
		{
			"regiments": {0: 2, 1: 9},
			"ships": {},
			"strengths": {0: 18.0, 1: 27.0},
			"readings": {
				0: {
					"regiments": {0: 2, 1: 9},
					"ships": {},
					"strength": {0: 18.0, 1: 27.0},
				}
			},
		},
		0
	)
	var reading: Dictionary = AiTurnRead.reading(context, 0)
	assert_eq(int(reading["power"][1]), 47, "2 × 10 provinces + 27 strength seen")
	assert_eq(int(reading["power"][0]), 38, "2 × 10 + the court's own 18")

# --- from test_ai_parameters.gd ---
## AI parameter registry and blessed profiles (wiki: ai-parameter-registry,
## ai-profile-overrides).


func test_registry_exposes_the_documented_defaults() -> void:
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_desire_base"), 50)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_declare_min_desire"), 51)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_relation_ceiling"), 50)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_cooldown_turns"), 4)
	assert_eq(AiParameterRegistry.default_of("diplomacy.overture_cooldown_turns"), 2)
	assert_eq(AiParameterRegistry.default_of("diplomacy.peace_refusal_cap"), 24)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_province_weight"), 10)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_regiment_weight"), 1)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_ship_weight"), 5)
	assert_eq(AiParameterRegistry.default_of("military.attack_margin_pct"), 110)
	assert_eq(AiParameterRegistry.default_of("military.defence_weight"), 500)
	assert_eq(AiParameterRegistry.default_of("victory.pressure_start"), 250)
	assert_eq(AiParameterRegistry.default_of("victory.pressure_regiments"), 2)
	assert_eq(AiParameterRegistry.default_of("victory.pressure_boost"), 1250)
	assert_eq(AiParameterRegistry.default_of("victory.pressure_war"), 30)
	assert_eq(AiParameterRegistry.keys().size(), AiParameterRegistry.entries().size())


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


func test_a_bound_temperament_reaches_the_courts_config() -> void:
	# The new-game screen binds one blessed profile per rival. The roster covers
	# every Great Power, trims the name it is handed, and drops one the catalog
	# does not bless, so a stale map cannot invent a temperament (wiki:
	# ai-profile-overrides § Resolution; ai-parameter-registry § Seed profiles).
	var bound: Dictionary = AiProfile.roster({1: AiProfile.AGGRESSIVE, 2: "bogus"})
	assert_eq(String(bound.get(1, "")), AiProfile.AGGRESSIVE)
	assert_eq(String(bound.get(2, "")), AiProfile.NORMAL, "an unknown name plans neutral")
	assert_eq(String(bound.get(5, "")), AiProfile.NORMAL, "an unbound crown plans neutral")
	assert_eq(bound.size(), FactionCatalog.great_power_ids().size())
	assert_eq(AiProfile.bound({1: " Economic "}, 1), AiProfile.ECONOMIC, "the name is trimmed")
	assert_eq(String(AiProfile.from_saved({"3": AiProfile.ECONOMIC}).get(3, "")), AiProfile.ECONOMIC)
	assert_eq(
		AiProfile.for_court(1, 1500, {1: AiProfile.AGGRESSIVE}).parameter(
			"diplomacy.war_relation_ceiling"
		),
		70,
		"the bound profile raises that court's knob"
	)
	assert_eq(
		AiProfile.for_court(1, 1500, {}).parameter("diplomacy.war_relation_ceiling"), 50,
		"a run with no binding reads the registry"
	)
	assert_gt(
		AiProfile.for_court(1, 1500, {1: AiProfile.AGGRESSIVE}).war_relation_ceiling(),
		AiProfile.for_court(1, 1500, {}).war_relation_ceiling(),
		"the same court, same agenda, declares on warmer neighbours"
	)


func test_every_profile_names_what_it_shifts() -> void:
	# A profile a sheet can print must carry a name and one line of effect, and
	# the words must not lie about the direction the numbers move (wiki:
	# ai-profile-overrides; REQ-P5-05).
	for id: String in AiProfile.ids():
		assert_false(AiProfile.label(id).is_empty(), id)
		assert_false(AiProfile.hint(id).is_empty(), id)
	assert_eq(AiProfile.label("bogus"), "Normal", "an unknown id reads as the neutral profile")
	assert_eq(AiProfile.hint("bogus"), AiProfile.hint(AiProfile.NORMAL))
	assert_gt(
		AiProfile.resolve("diplomacy.war_relation_ceiling", AiProfile.AGGRESSIVE),
		AiParameterRegistry.default_of("diplomacy.war_relation_ceiling"),
		"aggressive declares on warmer neighbours"
	)
	assert_lt(
		AiProfile.resolve("diplomacy.war_declare_min_desire", AiProfile.AGGRESSIVE),
		AiParameterRegistry.default_of("diplomacy.war_declare_min_desire"),
		"aggressive declares sooner"
	)
	assert_gt(
		AiProfile.resolve("economy.reserve_target", AiProfile.ECONOMIC),
		AiParameterRegistry.default_of("economy.reserve_target"),
		"economic banks more"
	)
	assert_gt(
		AiProfile.resolve("civilian.improvement_weight", AiProfile.ECONOMIC),
		AiParameterRegistry.default_of("civilian.improvement_weight"),
		"economic raises more works"
	)
	assert_lt(
		AiProfile.resolve("civilian.work_per_staff", AiProfile.ECONOMIC),
		AiParameterRegistry.default_of("civilian.work_per_staff"),
		"economic keeps more crews about them"
	)


## The map passes build their court's config through `AiBind`, so a bound
## temperament reaches the live planners and not only the diplomacy turn; a
## frozen baseline keeps the hill's own neutral planner (wiki:
## ai-profile-overrides § Resolution).
func test_the_bind_hands_a_live_court_its_temperament() -> void:
	var bound: Variant = AiBind.config(
		AiControl.KIND_SUBJECT, 2, 1500, {2: AiProfile.ECONOMIC}
	)
	assert_not_null(bound, "a submission court has a config")
	if bound == null:
		return
	assert_eq(
		String((bound as AiConfig).profile), AiProfile.ECONOMIC,
		"the court plans on the profile the run bound"
	)
	var plain: Variant = AiBind.config(AiControl.KIND_SUBJECT, 2, 1500, {})
	assert_eq(
		String((plain as AiConfig).profile), AiProfile.NORMAL,
		"a run with no binding reads the neutral profile"
	)


func test_the_bound_temperament_is_the_one_a_rival_turn_plans_on() -> void:
	# One rival bound at creation plans on that profile; its neighbour, bound to
	# nothing, plans neutral, and the trace names the profile each court read
	# (wiki: ai-profile-overrides § Resolution; turn-trace-interpretation).
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(1, 2, 1)
	var result: Dictionary = AiTurn.run(
		state, AiFixture.world([2, 2, 2, 2, 1]), AiState.new(), 1,
		FactionCatalog.PLAYER_FACTION, 1500,
		{"regiments": {}, "ships": {}, "profiles": {2: AiProfile.AGGRESSIVE}}
	)
	assert_eq(
		String(_record_for(result["trace"], 2).get("profile", "")),
		AiProfile.AGGRESSIVE,
		"the bound court plans aggressive"
	)
	assert_eq(
		String(_record_for(result["trace"], 1).get("profile", "")),
		AiProfile.NORMAL,
		"an unbound court keeps the neutral profile"
	)

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


func test_every_agenda_declares_every_trait() -> void:
	# One trait per documented agenda behaviour (wiki: hidden-agendas § Scoring
	# hooks; DR-20261111-27). An agenda missing a key would read as a neutral
	# court and its dossier could name a motive that moves nothing.
	var keys: Array = AiAgenda.NEUTRAL.keys()
	assert_eq(keys.size(), 8)
	for agenda_id: String in AiAgenda.IDS:
		var traits: Dictionary = AiAgenda.resolve(agenda_id)
		assert_eq(traits.size(), keys.size(), agenda_id)
		for key: Variant in keys:
			assert_true(traits.has(key), "%s declares %s" % [agenda_id, String(key)])


func test_the_seed_agendas_pull_on_their_documented_decisions() -> void:
	assert_eq(int(AiAgenda.resolve(AiAgenda.BACKSTABBER)["betray_bias"]), 25, "hits allies")
	assert_eq(int(AiAgenda.resolve(AiAgenda.ISOLATIONIST)["trade_bias"]), -20, "minimal trade")
	assert_eq(int(AiAgenda.resolve(AiAgenda.ENVY)["rival_bias"]), 20, "resents a lead")
	assert_eq(int(AiAgenda.resolve(AiAgenda.TECH_THIEF)["research_bias"]), 1, "pays to catch up")
	assert_eq(int(AiAgenda.resolve(AiAgenda.PEACEMAKER)["peace_bias"]), 15, "early peace")
	assert_eq(int(AiAgenda.resolve(AiAgenda.WARMONGER)["peace_bias"]), -10, "keeps the war alive")


func test_config_reads_an_agendas_traits() -> void:
	var hawk: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.WARMONGER)
	assert_eq(hawk.peace_bias(), -10)
	assert_eq(hawk.betray_bias(), 0)
	var sneak: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.BACKSTABBER)
	assert_eq(sneak.betray_bias(), 25)
	var loner: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.ISOLATIONIST)
	assert_eq(loner.trade_bias(), -20)
	var jealous: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.ENVY)
	assert_eq(jealous.rival_bias(), 20)
	var thief: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	assert_eq(thief.research_bias(), 1)
	var neutral: AiConfig = AiConfig.build(1, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	neutral.agenda_traits = AiAgenda.NEUTRAL
	assert_eq(neutral.peace_bias(), 0)
	assert_eq(neutral.betray_bias(), 0)
	assert_eq(neutral.trade_bias(), 0)
	assert_eq(neutral.rival_bias(), 0)
	assert_eq(neutral.research_bias(), 0)


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
	assert_eq(
		String((record["action"] as Dictionary).get("kind", "")),
		AiDiplomacyOffers.KIND_OVERTURE,
		"a court that cannot fight courts a friend instead"
	)
	assert_eq(String(record["candidates"][0]["blocked"]), "war desire too low")


func test_a_second_turn_does_not_repeat_the_war() -> void:
	# The weak court offers the peace it wants (desire 10 < 50) and the stronger
	# one refuses it while the war is still worth waging, so the war it declared
	# stands and no second declaration is made (wiki: diplomacy § Planner
	# selection, § Cooldowns).
	var run: Dictionary = _run()
	var result: Dictionary = AiTurn.run(
		run["state"], AiFixture.world([2, 2, 2, 2, 1]), run["ai"], 2, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_true((record["action"] as Dictionary).is_empty())
	assert_true(
		(run["state"] as DiplomacyState).relation(1, 2).at_war,
		"a war still worth waging is not signed away"
	)
	assert_eq(String(record["candidates"][0]["blocked"]), "war still worth waging")
	var weak: Dictionary = _record_for(result["trace"], 1)
	assert_eq(String(weak["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(String(weak["message"]).contains("refuses a white peace"))


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
	MapPlayDiplomacyAi.run(play)
	assert_not_null(play.ai)
	assert_eq(play.ai_trace.size(), 5)
	assert_true(play.diplomacy.relation(1, 2).at_war)


## A rival's war on a third court is World news: the Gazette narrates it from the
## recorded `warDeclared` event and a spy's court report carries it, so the toast
## lane does not announce the same declaration a third time (wiki: the-gazette
## § Not the Gazette; civilian-units § Spy (5)).
func test_a_rival_war_on_a_third_court_is_left_to_the_gazette() -> void:
	var play := PlaySession.new()
	play.world = AiFixture.world([2, 2, 2, 2, 1])
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	play.diplomacy.ensure_relation(1, 2, 1)
	play.map_seed = 1500
	play.hud = StubHud.new()
	add_child(play.hud)
	MapPlayDiplomacyAi.run(play)
	var toasts: Array[String] = (play.hud as StubHud).toasts
	assert_true(play.diplomacy.relation(1, 2).at_war, "the declaration still resolves")
	for line: String in toasts:
		assert_false(line.contains("declares war"), "not toasted: %s" % line)
	play.hud.free()


## A declaration on the crown is told at once: it governs this turn's movement
## and combat (wiki: diplomacy § Turn Sequence).
func test_a_declaration_on_the_crown_is_told_at_once() -> void:
	var play := PlaySession.new()
	var crown: int = play.human_faction_id()
	var record: Dictionary = {
		"faction": 2,
		"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": crown},
		"message": "",
		"messages": ["France declares war on the crown."],
	}
	assert_eq(MapPlayDiplomacyAi._announcements(play, record).size(), 1, "the line is told")
	# A trace from before the pass kept per-court lines still speaks.
	var legacy: Dictionary = {
		"faction": 2,
		"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": crown},
		"message": "France declares war on the crown.",
	}
	var spoken: Array[String] = MapPlayDiplomacyAi._announcements(play, legacy)
	assert_eq(String(spoken[0]), "France declares war on the crown.")
	# An empty record says nothing at all.
	assert_true(MapPlayDiplomacyAi._announcements(play, {"faction": 2}).is_empty())


## The merged observer record counts a declaration only when the rules accepted
## it: a refused order is not a war (wiki: turn-trace-interpretation).
func test_a_refused_order_is_not_a_declaration_in_the_turn_log() -> void:
	var play := PlaySession.new()
	play.ai_trace = [{
		"faction": 2,
		"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": 1},
		"result": {"ok": false, "reason": "Austria is already at war with us."},
		"message": "",
	}]
	var merged: Dictionary = AiTurnLog.record(play, [], [], {})
	var bucket: Dictionary = merged["factions"][2]
	assert_false((bucket["actions"] as Dictionary).has("war"), "no war is counted")
	assert_true((bucket["events"] as Array).is_empty(), "no declaration is invented")


# --- from test_ai_military.gd ---
## Rival land pass: a court at war on its border detaches a field army, then
## defends, storms or stages through the shared ArmyMovement rules (docs/ai.md).

const HOME_TYPES: Array[String] = [
	"peasant_levies", "peasant_levies", "pikemen", "arquebusiers", "squires"
]
const MINOR_ROSTER: Array[String] = ["peasant_levies", "peasant_levies", "bowmen"]
const TRIBE_ROSTER: Array[String] = ["peasant_levies", "peasant_levies"]


func test_ai_military_holds_its_army_at_peace() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _peace_state(1, 2)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = _home_armies()
	assert_eq(AiMilitaryPlanner.split_orders(config, state, model, armies).size(), 0)
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_ai_military_splits_the_home_army_on_a_hostile_border() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 1, true, HOME_TYPES, 101),
	]
	var splits: Array[Dictionary] = AiMilitaryPlanner.split_orders(config, state, model, armies)
	assert_eq(splits.size(), 1)
	assert_eq(String(splits[0]["kind"]), AiMilitaryPlanner.KIND_SPLIT)
	assert_eq((splits[0]["regiments"] as Array).size(), 4, "one regiment guards the seat")
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	var split: Dictionary = ArmyRoster.split(armies, armies[1], ids, 10)
	assert_true(bool(split["ok"]))
	var field: ArmyState = split["army"] as ArmyState
	assert_eq(field.count(), 4)
	assert_eq(armies[1].count(), 1)
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 0, "the undefended human province")
	assert_eq(int(plan["orders"][0]["army_id"]), field.id)


func test_ai_military_does_not_split_twice() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = _home_armies()
	armies.append(
		ArmyState.muster(3, 2, 1, false, ["peasant_levies"] as Array[String], 201)
	)
	assert_eq(AiMilitaryPlanner.split_orders(config, state, model, armies).size(), 0)


## The guard is a condition, not a lifetime lock (issue #974): a Home Army that
## has reached the court's muster target cuts a fresh field force even while
## another stands — the musters refill the seat.
func test_ai_military_cuts_a_second_field_force_at_target() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var home_types: Array[String] = []
	home_types.assign(HOME_TYPES)
	home_types.append_array(
		["pikemen", "arquebusiers", "squires", "pikemen"] as Array[String]
	)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 1, true, home_types, 101),
		ArmyState.muster(3, 2, 1, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var splits: Array[Dictionary] = AiMilitaryPlanner.split_orders(config, state, model, armies)

	assert_eq(splits.size(), 1, "a court at its target fields the surplus")
	assert_eq(
		(splits[0]["regiments"] as Array).size(), 8,
		"the second cut keeps one guard and fields the rest"
	)


## The rotation (issue #974): an under-strength field army marches home on
## interior lines while the Home Army holds mustered mass above the guard, so
## the merge and the next cut field a full-strength replacement.
func test_ai_military_rotates_an_under_strength_army_home() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2, 2], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 1, true, HOME_TYPES, 101),
		ArmyState.muster(3, 2, 2, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	var rotated: Array[Dictionary] = []
	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			rotated.append(order)

	assert_eq(rotated.size(), 1)
	assert_eq(String(rotated[0]["kind"]), AiMilitaryPlanner.KIND_ROTATE)
	assert_eq(int(rotated[0]["province"]), 1, "the march home merges with the Home Army")


## No mass beyond the guard, no rotation (issue #974): a court whose Home Army
## holds only the seat's guard leaves its field army in the field.
func test_ai_military_rotates_only_from_mustered_mass() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2, 2], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 1, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 2, 2, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)

	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			assert_ne(
				String(order["kind"]), AiMilitaryPlanner.KIND_ROTATE,
				"the lone guard's field army is left in the field"
			)


## A host standing on ground it does not hold has no interior lines, so when no
## attack, defence or staging order answers it walks home one province at a time
## (wiki: military-armies § Movement and attacks; DR-20261121-15).
func test_ai_military_walks_a_stranded_host_home() -> void:
	# P0 and P1 are unclaimed wilderness; P2 is the court's own and P3 its seat.
	var world: WorldMap = _walk_world([MapModel.NO_ID, MapModel.NO_ID, 2, 2], {3: true})
	var model: MapModel = world.region(0)
	var state := _war_state(2, 3)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 3, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 2, 0, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	var walked: Array[Dictionary] = []
	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			walked.append(order)

	assert_eq(walked.size(), 1, "the stranded host is given a march")
	assert_eq(String(walked[0]["kind"]), AiMilitaryPlanner.KIND_WALK_HOME)
	assert_eq(int(walked[0]["province"]), 1, "the first leg toward the seat")


## The rotation's own order is refused when no own land touches, so a stranded
## host the rotation picks walks the first leg home instead of sitting on an
## order the rules would deny (DR-20261121-15).
func test_ai_military_rotation_walks_a_stranded_host_home() -> void:
	var world: WorldMap = _walk_world([MapModel.NO_ID, MapModel.NO_ID, 2, 2], {3: true})
	var model: MapModel = world.region(0)
	var state := _war_state(2, 3)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 3, true, HOME_TYPES, 101),
		ArmyState.muster(3, 2, 0, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	var walked: Array[Dictionary] = []
	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			walked.append(order)

	assert_eq(walked.size(), 1)
	assert_eq(
		String(walked[0]["kind"]),
		AiMilitaryPlanner.KIND_WALK_HOME,
		"the seat is out of one march's reach, so the host walks"
	)
	assert_eq(int(walked[0]["province"]), 1)


## A step onto the court's own land is the road home itself: the host walks onto
## the own province beside it, and interior lines open from there. The seat two
## marches on is no one-march step, however near it reads on the field
## (DR-20261121-15).
func test_ai_military_walks_a_stranded_host_onto_its_own_land() -> void:
	var world: WorldMap = _walk_world([MapModel.NO_ID, 2, 2], {2: true})
	var model: MapModel = world.region(0)
	var state := _war_state(2, 3)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 2, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 2, 0, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	var walked: Array[Dictionary] = []
	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			walked.append(order)

	assert_eq(walked.size(), 1)
	assert_eq(String(walked[0]["kind"]), AiMilitaryPlanner.KIND_WALK_HOME)
	assert_eq(
		int(walked[0]["province"]), 1,
		"its own ground beside it, the road home"
	)


## Own land is the road's end, so a host beside its own border walks onto it even
## when a wilderness step reads nearer the seat: the published walk names the
## province that shortens the road, and own land is the seat's own distance
## (wiki: military-armies § Movement and attacks — "own land is the seat's own
## distance, so it always wins"; DR-20261121-15).
func test_ai_military_walks_onto_its_own_land_before_nearer_wilderness() -> void:
	# P0 the seat, then the wilderness road P1 → P2. The host stands in P3, beside
	# both P2 (two marches from the seat) and its own ground P4 (four).
	var model: MapModel = _walk_chart(
		[[0, 1, 1], [1, 2, 1], [2, 2, 3], [3, 3, 3], [3, 4, 4]],
		{0: 2, 4: 2}, {0: true}
	)
	var state := _war_state(2, 3)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 0, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 2, 3, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	var walked: Array[Dictionary] = []
	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			walked.append(order)

	assert_eq(walked.size(), 1)
	assert_eq(String(walked[0]["kind"]), AiMilitaryPlanner.KIND_WALK_HOME)
	assert_eq(
		int(walked[0]["province"]), 4,
		"its own ground beside it, the road's end — a nearer wilderness step is no walk"
	)


## Two steps home at the same distance: the lower province id wins, so the same
## state always walks the same way (DR-20261121-15).
func test_ai_military_walks_the_lower_step_on_a_tie() -> void:
	# P0 the seat, P3 and P1 both one march from it, P2 the host beside both.
	var model: MapModel = _walk_chart(
		[[0, 3], [1, 2]], {0: 2}, {0: true}
	)
	var state := _war_state(2, 3)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 0, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 2, 2, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	var walked: Array[Dictionary] = []
	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			walked.append(order)

	assert_eq(walked.size(), 1)
	assert_eq(String(walked[0]["kind"]), AiMilitaryPlanner.KIND_WALK_HOME)
	assert_eq(int(walked[0]["province"]), 1, "the lower id of the two equal steps")


## A step onto the court's own ground is the road's end, not one more province on
## it: the walk takes the own province beside the host even when a wilderness
## neighbour reads nearer the seat on the field, because own land is the seat's
## own distance and always wins (wiki: military-armies § Movement and attacks;
## DR-20261121-15).
func test_ai_military_walks_onto_own_land_before_nearer_wilderness() -> void:
	# P0 the seat; P4 the court's own ground, four marches out; P8 the host, beside
	# both P4 and the wilderness P6/P7 that sit two marches from the seat.
	var model: MapModel = _walk_chart(
		[[0, 1, 2], [5, 7, 3], [6, 8, 4], [9, 10, 11]],
		{0: 2, 4: 2},
		{0: true}
	)
	var state := _war_state(2, 3)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 0, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 2, 8, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	var walked: Array[Dictionary] = []
	for order: Dictionary in plan["orders"]:
		if int(order["army_id"]) == 3:
			walked.append(order)

	assert_eq(walked.size(), 1)
	assert_eq(String(walked[0]["kind"]), AiMilitaryPlanner.KIND_WALK_HOME)
	assert_eq(
		int(walked[0]["province"]), 4,
		"its own ground beside it, the road home, never the nearer wilderness"
	)


## A chart that holds no seat of the court lies across the sea, so the walk's
## road ends at the crown's own harbour there — the quay its own sentence names
## — and own ground beside the host is no end at all: the host walks for the
## quay even when an own province stands one march away, because only a squadron
## at that quay carries it home (wiki: military-armies § Movement and attacks;
## DR-20261122-09, DR-20261123-09).
func test_ai_military_walks_across_the_sea_toward_its_harbour() -> void:
	# P0 the host; P1 the wilderness step nearer the quay on the tie; P3 the
	# court's own inland ground beside it; P5 its own harbour, two marches on.
	var model: MapModel = _walk_chart(
		[[0, 1, 2], [3, 4, 5]], {3: 2, 5: 2}
	)
	model.region_id = FactionCatalog.NEW_WORLD
	model.province_data(5).port_tile = Vector2i(2, 1)
	var host: ArmyState = ArmyState.muster(
		3, 2, 0, false, ["pikemen", "bowmen"] as Array[String], 201
	)

	var walked: Dictionary = AiMilitaryPlanner._walk_home_order(model, host)

	assert_eq(String(walked.get("kind", "")), AiMilitaryPlanner.KIND_WALK_HOME)
	assert_eq(
		int(walked.get("province", -1)), 1,
		"the step toward the quay, never the own ground beside it"
	)


## A crown that keeps no harbour on that chart leaves the host no road at all:
## no squadron can take it aboard, so the walk names no step (wiki:
## military-armies § Movement and attacks; DR-20261122-09, DR-20261123-09).
func test_ai_military_walks_nothing_across_the_sea_without_a_harbour() -> void:
	var model: MapModel = _walk_chart(
		[[0, 1, 2], [3, 4, 5]], {3: 2, 5: 2}
	)
	model.region_id = FactionCatalog.NEW_WORLD
	var host: ArmyState = ArmyState.muster(
		3, 2, 0, false, ["pikemen", "bowmen"] as Array[String], 201
	)

	assert_true(
		AiMilitaryPlanner._walk_home_order(model, host).is_empty(),
		"no harbour, no road home"
	)


## The walk's own guards: no chart, no army, or a court the catalogue gives no
## chart names no step at all (DR-20261121-15).
func test_ai_military_walks_nothing_without_a_chart_or_a_seat() -> void:
	assert_true(AiMilitaryPlanner._walk_home_order(null, null).is_empty())
	var model: MapModel = _walk_chart([[0]], {0: 2})
	var host: ArmyState = ArmyState.muster(
		3, 2, 0, false, ["pikemen"] as Array[String], 201
	)
	assert_true(
		AiMilitaryPlanner._walk_home_order(model, host).is_empty(),
		"a host on its own ground has nowhere to walk"
	)
	var chartless: ArmyState = ArmyState.muster(
		4, 99, 0, false, ["pikemen"] as Array[String], 301
	)
	assert_true(
		AiMilitaryPlanner._walk_home_order(model, chartless).is_empty(),
		"a court the catalogue gives no chart has no seat to read"
	)


## A host walled in by foreign land at peace has no step it may take: the walk
## names nothing rather than a march the rules would deny (DR-20261121-15).
func test_ai_military_leaves_a_walled_in_host_where_it_stands() -> void:
	var world: WorldMap = _walk_world([1, 1, 2], {2: true})
	var model: MapModel = world.region(0)
	var state := _war_state(2, 3)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 2, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 2, 0, false, ["pikemen", "bowmen"] as Array[String], 201),
	]

	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)

	for order: Dictionary in plan["orders"]:
		assert_ne(
			int(order["army_id"]), 3, "no step shortens the road, so no order"
		)


## A tiny chart minted from rows of province ids (`-1` is open ground), so a tie
## between two steps home can be seated where a straight line cannot.
func _walk_chart(rows: Array, owners: Dictionary, capitals: Dictionary = {}) -> MapModel:
	var model := MapModel.new()
	var height: int = rows.size()
	var width: int = (rows[0] as Array).size()
	model.setup(width, height)
	model.terrain.fill(MapModel.Terrain.PLAINS)
	var tiles: Dictionary = {}
	for y in height:
		var row: Array = rows[y]
		for x in row.size():
			var id: int = int(row[x])
			model.province[model.index_of(x, y)] = id
			if id < 0:
				continue
			if not tiles.has(id):
				tiles[id] = []
			(tiles[id] as Array).append(Vector2i(x, y))
	for id: int in tiles.keys():
		var list: Array[Vector2i] = []
		list.assign(tiles[id])
		var center := Vector2.ZERO
		for tile: Vector2i in list:
			center += Vector2(tile)
		var owner: int = int(owners.get(id, MapModel.NO_ID))
		model.provinces.append(
			ProvinceState.create(
				id, "P%d" % id, list, center / float(list.size()), list.size(),
				owner, capitals.has(id)
			)
		)
		if not model.faction_ids.has(owner):
			model.faction_ids.append(owner)
	model.provinces.sort_custom(
		func(a: ProvinceState, b: ProvinceState) -> bool: return a.id < b.id
	)
	return model


## A line of provinces with the given owners; `-1` is unclaimed wilderness, which
## the fixture's own builder does not mint (it reads a faction for every row), so
## the row is built under a placeholder and struck out afterwards.
func _walk_world(owners: Array[int], capitals: Dictionary = {}) -> WorldMap:
	var built: Array[int] = []
	for owner: int in owners:
		built.append(9 if owner == MapModel.NO_ID else owner)
	var world: WorldMap = AiFixture.land_world(built, capitals)
	var model: MapModel = world.region(0)
	for index in owners.size():
		if owners[index] == MapModel.NO_ID:
			model.provinces[index].owner = MapModel.NO_ID
	model.faction_ids.erase(9)
	return world


## The rotation's merge leg (issue #974): a field army the court marched home
## folds into the Home Army through the published combine, and the trace names
## it; an army that did not reach the seat stays in the field.
func test_a_rotated_army_folds_into_the_home_army() -> void:
	var world: WorldMap = army_AiFixture.land_world([campaign_OWNER, campaign_OWNER], {0: true})
	var model: MapModel = world.region(0)
	var play := PlaySession.new()
	play.world = world
	var home: ArmyState = ArmyState.muster(1, campaign_OWNER, 0, true, ["peasant_levies"], 1)
	var field: ArmyState = ArmyState.muster(2, campaign_OWNER, 0, false, ["pikemen", "squires"], 10)
	var roster: Array[ArmyState] = [home, field]
	var plan: Dictionary = {
		"orders": [{"army_id": 2, "province": 0, "kind": AiMilitaryPlanner.KIND_ROTATE}],
		"candidates": [],
	}
	var trace: Array[Dictionary] = []

	assert_true(MapPlayArmyAi._apply_rotation_combine(play, model, roster, campaign_OWNER, plan, trace))
	assert_eq(home.count(), 3, "the Home Army is always the merge target")
	assert_eq(roster.size(), 1, "the folded standard leaves the roster")
	assert_eq(trace.size(), 1)
	assert_eq(String(trace[0]["kind"]), MapPlayArmyAi.KIND_COMBINE)
	assert_false(
		MapPlayArmyAi._apply_rotation_combine(play, model, roster, campaign_OWNER, plan, trace),
		"nothing left to fold"
	)


func test_ai_military_leaves_a_marched_army_in_place() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 1, true, HOME_TYPES, 101),
		ArmyState.muster(3, 2, 1, false, HOME_TYPES, 201),
	]
	armies[2].moved = true
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_ai_military_prefers_a_capital_target() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2, 1], {2: true})
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = _home_armies()
	_split_home(config, state, model, armies)
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq(int(plan["orders"][0]["province"]), 2, "the enemy seat outranks a plain province")


func test_ai_military_does_not_storm_a_stronger_defender() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = _home_armies()
	_split_home(config, state, model, armies)
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq((plan["orders"] as Array).size(), 0, "four regiments never storm five")
	assert_true((plan["candidates"] as Array).is_empty())


## An empty walled province is stormed, not walked (issue #1314): the gate
## prices the standing battery too — the resolver's storm threshold is wall HP
## + emplaced strength, so a host that beats the wall but not the battery is
## repelled and never marches (wiki: siege-mechanics § Storming an empty
## walled province). The battery is the **defender's** line; the gate cannot
## read it, so it prices the top of the ladder (Siege Guns, 19) and a host the
## Royal floor would have admitted stays home rather than be turned back.
func test_ai_military_prices_an_empty_wall_at_the_storm_threshold() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	# Province 0 stands hostile and empty behind a Wood fort: 40 wall HP + one
	# 19-strength Siege gun = a 59-strength storm ceiling. A levy is 3.
	model.province_data(0).fort_level = 1
	var armies: Array[ArmyState] = []
	var thin: Array[String] = []
	thin.resize(18)
	thin.fill("peasant_levies")
	var host: ArmyState = ArmyState.muster(2, 2, 1, false, thin, 101)
	armies.append(host)
	assert_eq(host.strength(), 54.0, "eighteen levies beat a Royal wall's 51 and are still refused")
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq(
		(plan["orders"] as Array).size(), 0,
		"a host under the heaviest battery the wall could mount never marches"
	)
	var over: Array[String] = []
	over.resize(20)
	over.fill("peasant_levies")
	armies[0] = ArmyState.muster(2, 2, 1, false, over, 101)
	assert_eq(armies[0].strength(), 60.0, "twenty levies clear the 59 ceiling")
	plan = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq((plan["orders"] as Array).size(), 1, "one levy over the ceiling storms the empty wall")
	assert_eq(int(plan["orders"][0]["province"]), 0)


func test_ai_military_storms_a_weaker_defender() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies", "peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 1, true, HOME_TYPES, 101),
	]
	_split_home(config, state, model, armies)
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 0)


func test_ai_military_marches_through_its_own_land_to_stage() -> void:
	var world: WorldMap = AiFixture.land_world([1, 1, 2, 2, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = _home_armies(4)
	_split_home(config, state, model, armies)
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq(int(plan["orders"][0]["province"]), 2, "nearest own frontier province")
	assert_eq(String(plan["orders"][0]["kind"]), "stage")


func test_ai_military_defends_an_occupied_own_province() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2, 2])
	var model: MapModel = world.region(0)
	var state := _war_state(2, 1)
	var config: AiConfig = AiConfig.build(2, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, HOME_TYPES, 1),
		ArmyState.muster(2, 2, 1, true, HOME_TYPES, 101),
		ArmyState.muster(3, 1, 2, false, ["peasant_levies"] as Array[String], 201),
	]
	_split_home(config, state, model, armies)
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq(int(plan["orders"][0]["province"]), 2, "the occupied province comes first")
	assert_eq(String(plan["orders"][0]["kind"]), "defend")


## Issue #1259: the seat has fallen to the invader — a host marching toward it
## outranks the foreign adventure the staging branch would price. The land war
## is on the court's soil, so defence first (wiki: military-armies § Home Army).
func test_ai_military_marches_home_when_the_seat_falls() -> void:
	# P0 own, P1 the fallen seat, P2-P3 the invader's rear: the field army at
	# P0 holds its own ground and the lost seat is one march away — it storms
	# the lost seat home instead of staging for the frontier. The storm onto
	# the fallen seat is `defend` and outranks any frontier attack beside it.
	var world: WorldMap = AiFixture.land_world([1, 1, 2, 2], {1: true})
	var model: MapModel = world.region(0)
	model.provinces[1].owner = 2
	var state := _war_state(2, 1)
	# The defending court plans: the config faction is the one losing its seat.
	var config: AiConfig = AiConfig.build(1, 1500)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 3, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(3, 1, 0, false, ["pikemen", "bowmen", "bowmen"], 201),
	]
	var plan: Dictionary = AiMilitaryPlanner.march_orders(config, state, model, armies)
	assert_eq(plan["orders"].size(), 1, "the field army takes the one march")
	assert_eq(String(plan["orders"][0]["kind"]), "defend")
	assert_eq(int(plan["orders"][0]["province"]), 1, "the storm onto the lost seat")
	# The home-defence read generalises to a shrinking frontier: two hostile
	# provinces standing on the court's own land, the seat itself held — the
	# rear host the invader cut off marches home through the staging road,
	# the walk-home's own road field naming the leg.
	var world2: WorldMap = AiFixture.land_world([2, 1, 1, 2, 2], {2: true})
	var model2: MapModel = world2.region(0)
	var plan2: Dictionary = AiMilitaryPlanner.march_orders(config, state, model2, [
		ArmyState.muster(1, 2, 4, true, ["peasant_levies"] as Array[String], 101),
		ArmyState.muster(2, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(3, 1, 1, false, ["pikemen", "bowmen", "bowmen"], 201),
	])
	assert_eq(plan2["orders"].size(), 1, "the rear host takes the one march")
	assert_eq(String(plan2["orders"][0]["kind"]), "defend")
	assert_eq(int(plan2["orders"][0]["province"]), 0, "the storm onto the invader's frontier")


func test_map_phase_moves_rival_armies_without_a_hud() -> void:
	var world: WorldMap = AiFixture.land_world([1, 2])
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, 2, 1, true, HOME_TYPES, 101),
	]
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = 1
	play.world = world
	play.model = model
	play.diplomacy = _war_state(2, 1)
	play.army_layer = layer
	play.map_seed = 1500
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	assert_eq(trace.size(), 2, "one split and one march")
	assert_eq(String(trace[0]["kind"]), AiMilitaryPlanner.KIND_SPLIT)
	assert_eq(String(trace[1]["kind"]), AiMilitaryPlanner.KIND_MARCH)
	var field: ArmyState = null
	for army: ArmyState in layer.armies:
		if army.owner == 2 and not army.home:
			field = army
	assert_not_null(field)
	assert_eq(field.province, 0, "the rival standard now stands on human land")
	assert_eq(layer.regions.value(0, []).size(), 3)
	layer.free()


# --- Minor / Tribe defence (wiki: factions § Minor Nation, § Tribe) ---
## Those crowns never attack: at peace they hold, and at war they only send a
## relief column onto their own invaded soil.


func test_a_minor_holds_its_army_at_peace() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _peace_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
	]
	assert_eq(AiDefensePlanner.split_orders(state, model, armies, 6).size(), 0)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_a_minor_sends_a_relief_column_to_an_invaded_province() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		_invading_army(2, 0, 0),
	]
	var splits: Array[Dictionary] = AiDefensePlanner.split_orders(state, model, armies, 6)
	assert_eq(splits.size(), 1)
	assert_eq((splits[0]["regiments"] as Array).size(), 2, "one regiment keeps the seat")
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	var split: Dictionary = ArmyRoster.split(armies, armies[0], ids, 10)
	assert_true(bool(split["ok"]))
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 0, "the invaded province")
	assert_eq(String(plan["orders"][0]["kind"]), AiDefensePlanner.KIND_RELIEVE)


func test_an_invaded_capital_keeps_the_home_army_in_place() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		_invading_army(2, 1, 0),
	]
	assert_eq(
		AiDefensePlanner.split_orders(state, model, armies, 6).size(),
		0,
		"the Home Army already holds the seat"
	)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_a_minor_never_marches_into_foreign_land() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		ArmyState.muster(2, 6, 0, false, ["peasant_levies"] as Array[String], 201),
		ArmyState.muster(3, 0, 2, false, ["pikemen"] as Array[String], 301),
	]
	armies[2].moved = true
	assert_eq(
		AiDefensePlanner.split_orders(state, model, armies, 6).size(),
		0,
		"no invader stands on home soil"
	)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0, "a Minor never attacks")


func test_a_tribe_sends_the_same_relief_column() -> void:
	var world: WorldMap = AiFixture.land_world([9, 9, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 9)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 9, 1, true, TRIBE_ROSTER, 101),
		_invading_army(2, 0, 0),
	]
	var splits: Array[Dictionary] = AiDefensePlanner.split_orders(state, model, armies, 9)
	assert_eq(splits.size(), 1)
	assert_eq((splits[0]["regiments"] as Array).size(), 1)
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	ArmyRoster.split(armies, armies[0], ids, 10)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 9)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 0)


func test_a_field_army_already_in_the_field_blocks_a_second_detach() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		ArmyState.muster(2, 6, 0, false, ["bowmen"] as Array[String], 201),
		_invading_army(3, 0, 0),
	]
	armies[1].moved = true
	assert_eq(
		AiDefensePlanner.split_orders(state, model, armies, 6).size(),
		0,
		"the home army is not drained twice"
	)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0, "the column already holds the province")


func test_a_field_army_can_relieve_the_invaded_capital() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		ArmyState.muster(2, 6, 0, false, ["bowmen"] as Array[String], 201),
		_invading_army(3, 1, 0),
	]
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 1, "the seat outranks other provinces")


func test_a_home_army_with_one_regiment_cannot_spare_a_column() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, ["peasant_levies"] as Array[String], 101),
		_invading_army(2, 0, 0),
	]
	assert_eq(AiDefensePlanner.split_orders(state, model, armies, 6).size(), 0)


func test_a_great_power_keeps_its_offensive_planner() -> void:
	var world: WorldMap = AiFixture.land_world([1, 1])
	var model: MapModel = world.region(0)
	var state := _war_state(0, 1)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, MINOR_ROSTER, 101),
		_invading_army(2, 1, 0),
	]
	assert_eq(AiDefensePlanner.split_orders(state, model, armies, 1).size(), 0)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 1)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_the_relief_column_joins_the_defence() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var invader := ArmyState.muster(
		2, 0, 0, false, ["pikemen", "pikemen", "pikemen"] as Array[String], 201
	)
	invader.moved = true
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		invader,
	]
	var splits: Array[Dictionary] = AiDefensePlanner.split_orders(state, model, armies, 6)
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	var split: Dictionary = ArmyRoster.split(armies, armies[0], ids, 10)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	var field: ArmyState = split["army"] as ArmyState
	ArmyMovement.apply_move(model, field, int(plan["orders"][0]["province"]), true)
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies)
	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["defender"]), 6)
	assert_ne(
		int(reports[0]["outcome"]),
		ArmyCombat.Outcome.CAPTURE,
		"the relief column turns an unopposed capture into a battle"
	)


func test_the_map_phase_moves_a_minor_relief_without_a_hud() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		_invading_army(2, 0, 0),
	]
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.diplomacy = _war_state(0, 6)
	play.army_layer = layer
	play.map_seed = 1500
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	assert_eq(trace.size(), 2, "one detach and one relief march")
	assert_eq(String(trace[0]["kind"]), AiMilitaryPlanner.KIND_SPLIT)
	assert_eq(String(trace[1]["kind"]), AiDefensePlanner.KIND_RELIEVE)
	var field: ArmyState = null
	for army: ArmyState in layer.armies:
		if army.owner == 6 and not army.home:
			field = army
	assert_not_null(field)
	assert_eq(field.province, 0, "the relief column stands with the invaders")
	layer.free()


## A hostile column that has marched into home soil; the flag is the marker
## ArmyCombat uses, and the planner reads the presence itself.
func _invading_army(id: int, province: int, owner: int) -> ArmyState:
	var army := ArmyState.muster(
		id, owner, province, false, ["pikemen"] as Array[String], id * 100
	)
	army.moved = true
	return army


func _home_armies(ai_province: int = 1) -> Array[ArmyState]:
	return [
		ArmyState.muster(1, 1, 0, true, HOME_TYPES, 1),
		ArmyState.muster(2, 2, ai_province, true, HOME_TYPES, 101),
	]


func _split_home(
	config: AiConfig, state: DiplomacyState, model: MapModel, armies: Array[ArmyState]
) -> void:
	var splits: Array[Dictionary] = AiMilitaryPlanner.split_orders(config, state, model, armies)
	assert_eq(splits.size(), 1)
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	var split: Dictionary = ArmyRoster.split(armies, armies[1], ids, 10)
	assert_true(bool(split["ok"]))


func _peace_state(first: int, second: int) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(first, second, 1)
	return state


func _war_state(attacker: int, target: int) -> DiplomacyState:
	var state := _peace_state(attacker, target)
	state.relation(attacker, target).at_war = true
	return state


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


# --- rival squadrons sail (AiNavalPlanner, MapPlayFleetAi) ---
## A court at war hunts the squadrons it can match and otherwise holds station
## (wiki: ai-architecture § Naval policy, ships-and-naval § missions).


func test_ai_naval_hunts_a_hostile_squadron_one_zone_over() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 2, 1, "sloop"),
		_squadron(1, 1, 0, "sloop"),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_PURSUE)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "the zone holding the hostile hull")
	assert_eq(int(plan["orders"][0]["fleet_id"]), 0)


func test_ai_naval_declines_an_overwhelming_squadron() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 2, 1, "sloop"),
		_squadron(1, 1, 0, "galleon"),
		_squadron(2, 1, 0, "galleon"),
		_squadron(3, 1, 0, "galleon"),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0, "the caution knob keeps the hull home")


## Issue #1259: a hostile hull carrying an army is an invasion fleet — the
## seat's warship sorties after it even past the caution margin, because the
## landing it carries is the war itself. A home fleet whose hostiles are
## unladen keeps the published caution (wiki: ai-architecture § Naval policy
## — defence first).
func test_ai_naval_sorties_after_an_invasion_fleet() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	# The seat's guard: one sloop against three galleons — a fight the caution
	# knob declines when the hulls are unladen.
	var home := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "sloop"})
	var invasion := FleetState.at_sea(1, 1, 0, ["h1"] as Array[String], {"h1": "galleon"})
	invasion.embarked_army = 7
	var fleets: Array[FleetState] = [home, invasion]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1, "the invasion fleet is fought")
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_SORTIE)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "the water the invasion crosses")
	# The same fleet unladen but overwhelming — three galleons of the invader's
	# nation: the caution knob keeps the guard in the harbour as published.
	invasion.embarked_army = -1
	var invading2 := FleetState.at_sea(2, 1, 0, ["h2"] as Array[String], {"h2": "galleon"})
	var invading3 := FleetState.at_sea(3, 1, 0, ["h3"] as Array[String], {"h3": "galleon"})
	var declined: Dictionary = AiNavalPlanner.orders(
		config, _war_state(0, 1), model, [home, invasion, invading2, invading3]
	)
	assert_eq((declined["orders"] as Array).size(), 0, "an unladen armada stays declined")


## A court at peace has no station to keep: its sea-going squadrons sail home
## and dock, so holds, yard and harbour roster are where the rules use them
## (wiki: ai-architecture § Naval policy; DR-20261110-30). A crown with no
## harbour at all has nowhere to go and simply holds.
func test_ai_naval_brings_a_peaceful_squadron_home() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 0, 0, "galleon")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _peace_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1, "the homeward order")
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_HOME)
	assert_true(bool(plan["orders"][0]["dock"]), "the harbour borders its zone")
	assert_eq(int(plan["orders"][0]["province"]), 0, "Cádiz, the crown's seat")
	assert_eq(int(plan["orders"][0]["threat"]), 0, "home orders carry no threat")


func test_ai_naval_sails_one_zone_toward_home() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 0, 1, "galleon")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _peace_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_HOME)
	assert_false(bool(plan["orders"][0]["dock"]), "one zone a turn, not a leap")
	assert_eq(int(plan["orders"][0]["zone"]), 0, "the water off its own harbour")
	assert_eq(int(plan["orders"][0]["threat"]), 0, "a homeward sail is not a fight")


## A squadron on a station spends its turn there; going home is for the idle.
func test_ai_naval_keeps_a_patrol_at_peace() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var patrol: FleetState = _squadron(0, 0, 0, "galleon")
	patrol.mission = FleetState.Mission.PATROL
	var fleets: Array[FleetState] = [patrol]
	var plan: Dictionary = AiNavalPlanner.orders(config, _peace_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_ai_naval_a_crown_without_a_harbour_holds_station() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 2, 1, "galleon")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _peace_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0, "no port of its own to make for")


## Home water is still water it must have charted (wiki: fog-and-exploration
## § Visibility Levels; DR-20261110-21): an uncharted leg keeps the hull out.
func test_ai_naval_sails_home_only_through_charted_water() -> void:
	var home: MapModel = NavalFixture.build()
	var model: MapModel = NavalFixture.build()
	model.region_id = FactionCatalog.NEW_WORLD
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(model)
	# Faction 0 is the sailing court, so its chart must be built as a rival's:
	# a human court's views come from the session's own table.
	var charts := CourtCharts.new()
	charts.setup(world, 2, {})
	var config: AiConfig = AiConfig.build(0, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 0, 1, "galleon")]
	var view: VisibilityModel = charts.model_for(0, model.region_id)
	for tile: Vector2i in model.sea_zone_data(0).tiles:
		view.lower_to(model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	var blind: Dictionary = AiNavalPlanner.orders(
		config, _peace_state(0, 1), model, fleets, charts
	)
	assert_eq((blind["orders"] as Array).size(), 0, "the leg home is uncharted")
	charts.reveal_sea_zone(0, model.region_id, 0)
	var charted: Dictionary = AiNavalPlanner.orders(
		config, _peace_state(0, 1), model, fleets, charts
	)
	assert_eq((charted["orders"] as Array).size(), 1, "once charted it may sail")


func test_map_phase_moors_a_homecoming_squadron_in_the_home_fleet() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var home: FleetState = FleetState.in_port(
		0, 0, 0, ["h0"] as Array[String], {"h0": "carrack"}
	)
	var incoming: FleetState = _squadron(1, 0, 0, "fluyte")
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [home, incoming]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _peace_state(0, 1)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1, "one homeward order")
	assert_eq(String(trace[0]["kind"]), AiNavalPlanner.KIND_HOME)
	assert_eq(int(trace[0]["province"]), 0, "the seat")
	assert_eq(int(trace[0]["merged_into"]), 0, "the home squadron absorbs it")
	var moored: Array = layer.regions.value(0, [])
	assert_eq(moored.size(), 1, "no second squadron left in the seat's port")
	assert_eq(home.hulls.size(), 2, "the hulls are preserved")
	assert_true(home.hulls.has("h1"))
	assert_eq(TradeCargo.fleet_holds(home), 7, "the merchant's holds now count at home")
	layer.free()


## A peaceful squadron two zones from its harbour takes one leg home and the
## trace names it — with no battle threat to name (wiki: ships-and-naval § Home
## Fleet; DR-20261110-30).
func test_map_phase_sails_a_peaceful_squadron_one_leg_home() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var away: FleetState = _squadron(0, 0, 1, "fluyte")
	var home: FleetState = FleetState.in_port(
		1, 0, 0, ["h1"] as Array[String], {"h1": "galleon"}
	)
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [away, home]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _peace_state(0, 1)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1, "one homeward leg")
	assert_eq(String(trace[0]["kind"]), AiNavalPlanner.KIND_HOME)
	assert_eq(int(trace[0]["zone"]), 0, "it enters the zone off its own harbour")
	assert_eq(int(trace[0]["threat"]), 0, "a homeward leg threatens nobody")
	assert_eq(away.sea_zone, 0)
	layer.free()


func test_ai_naval_sorties_from_a_port_into_a_hostile_zone() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var moored := FleetState.in_port(0, 2, 0, ["h0"] as Array[String], {"h0": "sloop"})
	var fleets: Array[FleetState] = [moored, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_SORTIE)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "the zone off its own harbour")


## A rival hunts only in water its own chart holds (wiki: fog-and-exploration
## § Visibility Levels; DR-20261110-21): a hull in uncharted water is not a
## target, and a charted zone is.
func test_ai_naval_hunts_only_charted_water() -> void:
	# A New World region at world index 1, so the chart it reads is that region's.
	var home: MapModel = NavalFixture.build()
	var model: MapModel = NavalFixture.build()
	model.region_id = FactionCatalog.NEW_WORLD
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(model)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 2, 1, "sloop"),
		_squadron(1, 1, 0, "sloop"),
	]
	var blind: Dictionary = AiNavalPlanner.orders(
		config, _war_state(2, 1), model, fleets, charts
	)
	assert_eq((blind["orders"] as Array).size(), 0, "it has not charted the hostile's water")
	charts.reveal_sea_zone(2, 1, 0)
	var charted: Dictionary = AiNavalPlanner.orders(
		config, _war_state(2, 1), model, fleets, charts
	)
	assert_eq((charted["orders"] as Array).size(), 1, "once charted it may hunt")
	assert_true(AiNavalPlanner.charts_water(charts, 2, 1, 0))
	assert_false(AiNavalPlanner.charts_water(charts, 2, 1, 1))
	assert_true(AiNavalPlanner.charts_water(null, 2, 1, 1), "a fixture chart answers yes")


## The home squadron is not a hulk: a hostile squadron in the water beside the
## seat meets a sortie out of the harbour, and the fight outranks any raid
## (DR-20261109-17; wiki: ai-architecture § Naval policy — defence first).
func test_ai_naval_home_squadron_sorties_to_defend_its_seat() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var home := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "sloop"})
	var fleets: Array[FleetState] = [home, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1, "the seat answers a hostile in reach")
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_SORTIE)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "the water off its own harbour")


## A fight it declines is still a threat to its own port: with a stronger
## squadron beside the seat the home squadron keeps the harbour instead of
## sailing off to work a coast (wiki: ai-architecture § Naval policy).
func test_ai_naval_home_squadron_keeps_the_seat_when_a_hostile_is_beside_it() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var home := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "sloop"})
	var fleets: Array[FleetState] = [
		home,
		_squadron(1, 1, 0, "galleon"),
		_squadron(2, 1, 0, "galleon"),
		_squadron(3, 1, 0, "galleon"),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0, "the home fleet holds its capital")
	assert_true(home.is_in_port())


## With no fight to be had a warship-bearing home squadron puts to sea and works
## the enemy's trade: a rival whose whole navy berths at its seat is the common
## case, and the raid leg is for exactly that squadron (DR-20261111-17).
func test_ai_naval_home_squadron_sorties_to_raid_a_hostile_coast() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var home := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "sloop"})
	var plan: Dictionary = AiNavalPlanner.orders(
		config, _war_state(0, 1), model, [home] as Array[FleetState]
	)
	assert_eq((plan["orders"] as Array).size(), 1, "the home squadron works the trade")
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_RAID)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "the first leg off its own harbour")
	assert_eq(int(plan["orders"][0]["threat"]), 0, "a raid is not a battle")


## At war with no squadron to fight, a warship works the enemy's trade: it sails
## for a hostile coast so the station pass can blockade it (DR-20261111-17).
func test_ai_naval_sails_for_a_hostile_coast_to_raid() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 2, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_RAID)
	assert_eq(int(plan["orders"][0]["zone"]), 1, "the water off Coro")
	assert_eq(int(plan["orders"][0]["threat"]), 0, "a raid is not a battle")


## A merchant squadron is cargo, not a predator: only a warship takes the raid.
func test_ai_naval_a_merchant_squadron_does_not_raid() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 2, 0, "galleon")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0)


## A convoy hull cannot pick a fight: a merchant squadron in reach of a weaker
## hostile at war leaves the leg to the trade rules — with another berth
## ashore the hull hunts nothing, and with none it convoys home (issue #1258).
func test_ai_naval_a_merchant_squadron_never_pursues_at_war() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 0, 1, "galleon"),
		_squadron(1, 1, 0, "sloop"),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	for raw: Variant in plan["orders"]:
		assert_ne(
			String((raw as Dictionary)["kind"]), AiNavalPlanner.KIND_PURSUE,
			"a merchant hull joins no war hunt"
		)
		assert_ne(
			String((raw as Dictionary)["kind"]), AiNavalPlanner.KIND_SORTIE,
			"a merchant hull picks no fight"
		)


## A merchant home fleet that answers a hostile beside its berth still does not
## read as a war sortie: the kind is the hull's own, so the trace names a
## convoy's move for what it is (wiki: ships-and-naval § Ship Types; #1258).
func test_ai_naval_a_merchant_seat_guard_convoys_out_of_the_harbour() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var guard := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "galleon"})
	var fleets: Array[FleetState] = [guard, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1, "the berth answers the hostile")
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_CONVOY)


## A warship-bearing home fleet still answers a hostile beside the seat: the
## convoy rule is for hulls that cannot fight, never for the seat's guard
## (wiki: ai-architecture § Naval policy — defence first; issue #1258).
func test_ai_naval_a_warship_home_fleet_still_sorties_to_defend() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var home := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "galleon"})
	home.hull_types["h0"] = "sloop"
	var fleets: Array[FleetState] = [home, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1, "the seat answers a hostile in reach")
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_SORTIE)


## A warship already on a hostile coast holds there: the station pass posts the
## blockade, and sailing on would waste the turn (DR-20261111-17).
func test_ai_naval_a_warship_on_a_hostile_coast_holds_for_its_station() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 2, 1, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0)


## A laden coast outranks a bare hostile shore: the rival makes for the seat
## whose merchant hulls are in port (DR-20261111-17).
func test_ai_naval_prefers_a_laden_coast() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var state := _peace_state(2, 0)
	state.relation(2, 0).at_war = true
	state.ensure_relation(2, 1, 1)
	state.relation(2, 1).at_war = true
	var laden := FleetState.in_port(
		9, 0, 0, ["r1"] as Array[String], {"r1": "fluyte"}
	)
	var fleets: Array[FleetState] = [_squadron(0, 2, 1, "sloop"), laden]
	var plan: Dictionary = AiNavalPlanner.orders(config, state, model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_RAID)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "Cádiz, where the merchant hulls lie")


## A court at war with nowhere to fight and no trade to raid brings its hulls
## home instead of idling on station: holds and escorts are worth something
## there (DR-20261110-30).
func test_ai_naval_a_warship_with_no_war_work_comes_home() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 0, 1, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 2), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_HOME)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "one leg toward Cádiz")


## The raid also obeys the court's chart (wiki: fog-and-exploration § Visibility
## Levels; DR-20261110-21): uncharted enemy water is not a station it can work.
func test_ai_naval_raids_only_charted_water() -> void:
	var home: MapModel = NavalFixture.build()
	var model: MapModel = NavalFixture.build()
	model.region_id = FactionCatalog.NEW_WORLD
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(model)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 2, 0, "sloop")]
	var blind: Dictionary = AiNavalPlanner.orders(
		config, _war_state(2, 1), model, fleets, charts
	)
	assert_eq((blind["orders"] as Array).size(), 0, "the hostile coast is uncharted")
	charts.reveal_sea_zone(2, 1, 1)
	var charted: Dictionary = AiNavalPlanner.orders(
		config, _war_state(2, 1), model, fleets, charts
	)
	assert_eq((charted["orders"] as Array).size(), 1, "once charted it may raid")
	assert_eq(String(charted["orders"][0]["kind"]), AiNavalPlanner.KIND_RAID)


## The map applies the raid order through NavalMovement, then the station pass
## blockades the coast on the following turn (DR-20261111-17).
func test_map_phase_sails_to_a_hostile_coast_then_blockades_it() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var raider: FleetState = _squadron(0, 0, 0, "sloop")
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [raider]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _war_state(0, 1)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1, "one raid order")
	assert_eq(String(trace[0]["kind"]), AiNavalPlanner.KIND_RAID)
	assert_eq(int(trace[0]["zone"]), 1, "the water off Coro")
	assert_eq(raider.sea_zone, 1)
	assert_eq(raider.mission, FleetState.Mission.NONE, "the move spends the turn")
	NavalMovement.begin_turn(roster)
	MapPlayFleets.run_ai(play)
	assert_eq(raider.mission, FleetState.Mission.BLOCKADE, "next turn it works the coast")
	assert_eq(raider.blockade_province, 1)
	layer.free()


## A rival whose whole navy berths at its seat is the common case: the home
## squadron sorties out of the port through FleetSortie, takes the sea leg
## toward the hostile coast and, arrived, works it with a blockade
## (DR-20261109-17, DR-20261111-17). Nothing is invented: the sortie is the
## same one the player's dossier offers, and NavalMovement owns the rest.
func test_map_phase_sorties_the_home_squadron_to_raid_a_coast() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var home: FleetState = FleetState.in_port(
		0, 0, 0, ["h0"] as Array[String], {"h0": "sloop"}
	)
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [home]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _war_state(0, 1)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1, "one raid order from the home squadron")
	assert_eq(String(trace[0]["kind"]), AiNavalPlanner.KIND_RAID)
	assert_eq(int(trace[0]["zone"]), 0, "it puts to sea off its own harbour")
	assert_true(home.is_at_sea(), "the sortie turns it into a sea-going squadron")
	assert_eq(home.sea_zone, 0)
	assert_eq(home.mission, FleetState.Mission.NONE, "the sortie spends the turn")
	NavalMovement.begin_turn(roster)
	MapPlayFleets.run_ai(play)
	assert_eq(home.sea_zone, 1, "the second leg reaches the hostile coast")
	NavalMovement.begin_turn(roster)
	MapPlayFleets.run_ai(play)
	assert_eq(home.mission, FleetState.Mission.BLOCKADE, "arrived, it works the coast")
	assert_eq(home.blockade_province, 1)
	layer.free()


func test_ai_naval_needs_a_hostile_fleet_at_sea() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 2, 1, "sloop"),
		FleetState.in_port(1, 1, 1, ["h1"] as Array[String], {"h1": "sloop"}),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0, "a port fleet is not a target")


## A rival's station obeys its own chart (wiki: fog-and-exploration § Visibility
## Levels; DR-20261110-23): no blockade on uncharted water, a standing one lapses
## there, and charted water takes the station as before.
func test_ai_naval_blockades_only_charted_water() -> void:
	var home: MapModel = NavalFixture.build()
	var model: MapModel = NavalFixture.build()
	model.region_id = FactionCatalog.NEW_WORLD
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(model)
	var play := PlaySession.new()
	play.world = world
	play.diplomacy = _war_state(2, 1)
	play.court_charts = CourtCharts.new()
	play.court_charts.setup(world, 0, {})
	var fleet := FleetState.at_sea(1, 2, 1)
	var roster: Array[FleetState] = [fleet]
	var trace: Array[Dictionary] = []
	MapPlayFleetAi._station_orders(play, model, roster, 2, trace)
	assert_eq(fleet.mission, FleetState.Mission.NONE, "no blockade on uncharted water")
	fleet.mission = FleetState.Mission.BLOCKADE
	fleet.blockade_province = 1
	MapPlayFleetAi._station_orders(play, model, roster, 2, trace)
	assert_eq(fleet.mission, FleetState.Mission.NONE, "the blockade lapses there")
	play.court_charts.reveal_sea_zone(2, 1, 1)
	MapPlayFleetAi._station_orders(play, model, roster, 2, trace)
	assert_eq(fleet.mission, FleetState.Mission.BLOCKADE, "charted water takes the station")
	assert_eq(fleet.blockade_province, 1)


## A court that keeps no holds in port at its seat is closed to every import,
## so the squadron carrying them comes home even with a weaker hostile one zone
## over: a merchant hull is cargo, and the holds are the build inputs and the
## colony voyage (wiki: ships-and-naval § Cargo holds and capacity; issue #530).
func test_ai_naval_a_trade_garrison_comes_home_instead_of_hunting() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 0, 1, "galleon"),
		_squadron(1, 1, 0, "sloop"),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_HOME)
	assert_eq(String(plan["orders"][0]["reason"]), AiNavalPlanner.REASON_TRADE)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "one leg toward Cádiz")


## The garrison stays berthed: a court with its holds nowhere else does not sail
## the squadron that carries them out to work a coast (issue #530).
func test_ai_naval_a_trade_garrison_does_not_put_to_sea_to_raid() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var moored := FleetState.in_port(
		0, 0, 0, ["h0", "h1"] as Array[String], {"h0": "sloop", "h1": "galleon"}
	)
	var fleets: Array[FleetState] = [moored]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0, "the holds stay berthed")
	assert_true(moored.is_in_port())


## A berth ashore is what the policy answers: with another squadron's holds in
## port at the seat the first is free to hunt again (issue #530).
func test_ai_naval_a_berth_ashore_frees_a_squadron_to_hunt() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var berthed := FleetState.in_port(
		9, 0, 0, ["h9"] as Array[String], {"h9": "fluyte"}
	)
	var fleets: Array[FleetState] = [
		_squadron(0, 0, 1, "sloop"),
		berthed,
		_squadron(1, 1, 0, "sloop"),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	var order: Dictionary = {}
	for raw: Variant in plan["orders"]:
		if int((raw as Dictionary)["fleet_id"]) == 0:
			order = raw
	assert_eq(String(order.get("kind", "")), AiNavalPlanner.KIND_PURSUE, "the holds can wait")


## The station pass gives the station up rather than strand the holds: a court
## at war that keeps none in port at its seat needs them ashore, and the trace
## names the station abandoned (wiki: ships-and-naval § Missions and Movement;
## issue #530).
func test_map_phase_releases_a_trade_garrison_from_its_station() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var raider: FleetState = _squadron(0, 0, 0, "galleon")
	raider.mission = FleetState.Mission.BLOCKADE
	raider.blockade_province = 1
	var roster: Array[FleetState] = [raider]
	var play := _naval_play(world, model, ShipLayer.new())
	play.diplomacy = _war_state(0, 1)
	play.court_charts = CourtCharts.new()
	play.court_charts.setup(world, 0, {})
	var trace: Array[Dictionary] = []
	MapPlayFleetAi._station_orders(play, model, roster, 0, trace)
	assert_eq(raider.mission, FleetState.Mission.NONE, "the station is given up")
	assert_eq(raider.blockade_province, MapModel.NO_ID, "the blockade hook goes with it")
	assert_eq(trace.size(), 1)
	assert_eq(String(trace[0]["reason"]), AiNavalPlanner.REASON_TRADE)
	assert_eq(String(trace[0]["released"]), "blockade")


## The turn log names the trade garrison: the row reads as the holds coming
## home, not as a squadron sailing into the sea zone it just left (issue #530).
func test_the_observer_log_reads_the_trade_garrison() -> void:
	var play := PlaySession.new()
	var fleet_trace: Array[Dictionary] = [
		{
			"faction": 0,
			"kind": AiNavalPlanner.KIND_HOME,
			"fleet": 0,
			"zone": 0,
			"zone_name": "Mar Caribe",
			"region": 0,
			"threat": 0,
			"reason": AiNavalPlanner.REASON_TRADE,
		},
	]
	var merged: Dictionary = AiTurnLog.record(play, [], fleet_trace, {})
	var record: Dictionary = merged["factions"][0]
	assert_eq(int(record["actions"].get("home", 0)), 1, "a sailing home, not a pursuit")
	var lines: Array = record["events"]
	assert_eq(lines.size(), 1)
	assert_true(String(lines[0]).contains("holds home"), "the row names why")


## The observer log names a convoy hull's sail: the action reads as a convoy,
## never as the war sortie the old suffix rule gave every port fleet (issue
## #1258). A warship's own sortie keeps its `sortie` row.
func test_the_observer_log_names_a_convoy_sail_apart_from_a_sortie() -> void:
	var play := PlaySession.new()
	var fleet_trace: Array[Dictionary] = [
		{
			"faction": 0,
			"kind": AiNavalPlanner.KIND_CONVOY,
			"fleet": 0,
			"zone": 0,
			"zone_name": "Golfo de México",
			"region": 0,
			"threat": 0,
		},
		{
			"faction": 0,
			"kind": AiNavalPlanner.KIND_SORTIE,
			"fleet": 1,
			"zone": 1,
			"zone_name": "Mar Caribe",
			"region": 0,
			"threat": 3,
		},
	]
	var merged: Dictionary = AiTurnLog.record(play, [], fleet_trace, {})
	var record: Dictionary = merged["factions"][0]
	assert_eq(
		int(record["actions"].get("cargo", 0)), 0,
		"a convoy sail is no cargo route: the economy owns that key"
	)
	assert_eq(int(record["actions"].get("convoy", 0)), 1, "the convoy names itself")
	assert_eq(int(record["actions"].get("sortie", 0)), 1, "the warship still sorties")
	assert_eq(int(record["actions"].get("pursue", 0)), 0)
	var lines: Array = record["events"]
	assert_eq(lines.size(), 2)
	assert_true(String(lines[0]).contains("convoy"), "the row says what the hull did")
	assert_false(String(lines[0]).contains("squadron sails"), "not a war move's words")


## A berth guard that docks through the seat's own merge reads home — the dock
## branch names its harbour, not a zone (wiki: ships-and-naval § Home Fleet;
## issue #1258).
func test_the_observer_log_reads_a_convoy_dock_at_the_harbour() -> void:
	var play := PlaySession.new()
	var fleet_trace: Array[Dictionary] = [
		{
			"faction": 0,
			"kind": AiNavalPlanner.KIND_CONVOY,
			"fleet": 0,
			"zone": -1,
			"zone_name": "Cádiz",
			"region": 0,
			"threat": 0,
			"dock": true,
			"province": 0,
		},
	]
	var merged: Dictionary = AiTurnLog.record(play, [], fleet_trace, {})
	var record: Dictionary = merged["factions"][0]
	assert_eq(int(record["actions"].get("convoy", 0)), 1, "a docked convoy still names itself")
	var lines: Array = record["events"]
	assert_eq(lines.size(), 1)
	assert_true(String(lines[0]).contains("convoy"), "the dock row keeps the hull's own kind")


func test_ai_naval_skips_a_squadron_that_already_moved() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var spent: FleetState = _squadron(0, 2, 1, "galleon")
	spent.moved = true
	var fleets: Array[FleetState] = [spent, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_map_phase_moves_a_rival_squadron_and_it_fights() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var ai: FleetState = _squadron(0, 0, 1, "ship_of_the_line")
	var human: FleetState = _squadron(1, 1, 0, "sloop")
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [ai, human]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _war_state(0, 1)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1, "one rival order")
	assert_eq(String(trace[0]["kind"]), AiNavalPlanner.KIND_PURSUE)
	assert_eq(ai.sea_zone, 0, "the rival standard now shares the human's zone")
	assert_true(ai.moved)
	assert_eq(human.sea_zone, 0, "the human squadron is never planned")
	var battles: Array[Dictionary] = ShipTurnPass.resolve_battles(
		layer, world, func(a: int, b: int) -> bool: return a != b
	)
	assert_eq(battles.size(), 1, "the contested zone fights this turn")
	assert_eq(int(battles[0]["zone"]), 0)
	layer.free()


func test_map_phase_leaves_a_peaceful_navy_in_port() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var ai: FleetState = FleetState.in_port(0, 2, 0, ["h0"] as Array[String], {"h0": "galleon"})
	var human: FleetState = _squadron(1, 1, 0, "sloop")
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [ai, human]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _peace_state(2, 1)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 0)
	assert_true(ai.is_in_port())
	layer.free()


func test_naval_caution_knob_is_a_registry_key() -> void:
	assert_true(AiParameterRegistry.has("naval.caution_margin_pct"))
	assert_eq(AiParameterRegistry.default_of("naval.caution_margin_pct"), 120)
	assert_eq(AiParameterRegistry.resolve("naval.caution_margin_pct", {"naval.caution_margin_pct": 300}), 300)
	assert_eq(AiParameterRegistry.resolve("naval.caution_margin_pct", {"naval.caution_margin_pct": 1}), 120)


## Rounds used to hide this: 10.9 and 10.1 both ceil to 11, so the old rule took
## the lower zone id and sailed at the stronger squadron (wiki: ai-architecture
## § Naval policy — "the weakest hostile squadron it can reach").
func test_ai_naval_picks_the_weakest_of_two_reachable_squadrons() -> void:
	var model: MapModel = _line_zones()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [
		_fleet_of(0, 2, 1, ["ship_of_the_line", "ship_of_the_line"]),
		_fleet_of(1, 1, 0, ["galleon", "galleon", "carrack", "clipper"]),
		_fleet_of(2, 1, 2, ["indiaman", "indiaman", "fluyte", "fluyte"]),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(
		int(plan["orders"][0]["zone"]),
		2,
		"the east squadron is weaker even though its zone id sorts higher"
	)


func test_rival_sail_reports_a_sighting_in_charted_water() -> void:
	var world := WorldMap.new()
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	var ai: FleetState = _squadron(0, 0, 1, "ship_of_the_line")
	var human: FleetState = _squadron(1, 1, 0, "sloop")
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [ai, human]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _war_state(0, 1)
	var hud := StubHud.new()
	play.hud = hud
	play.visibility = VisibilityModel.new()
	play.visibility.setup(model, play.player_faction)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1)
	assert_eq(ai.sea_zone, 0, "the rival sails into the human's zone")
	assert_eq(hud.toasts.size(), 1, "charted (fogged) water earns one sighting line")
	layer.free()


func _squadron(id: int, owner: int, zone: int, type_id: String) -> FleetState:
	return FleetState.at_sea(
		id, owner, zone, ["h%d" % id] as Array[String], {"h%d" % id: type_id}
	)


func _fleet_of(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var hulls: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "h%d_%d" % [id, index]
		hulls.append(hull_id)
		hull_types[hull_id] = types[index]
	return FleetState.at_sea(id, owner, zone, hulls, hull_types)


## Three sea zones in a row so an at-sea squadron has two reachable targets.
func _line_zones() -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	for x in 3:
		model.sea_zone[model.index_of(x, 0)] = x
	model.sea_zones = [
		SeaZoneState.create(0, "West", [Vector2i(0, 0)] as Array[Vector2i], Vector2(0.5, 0.5), 1),
		SeaZoneState.create(1, "Middle", [Vector2i(1, 0)] as Array[Vector2i], Vector2(1.5, 0.5), 1),
		SeaZoneState.create(2, "East", [Vector2i(2, 0)] as Array[Vector2i], Vector2(2.5, 0.5), 1),
	]
	return model


static func _naval_play(world: WorldMap, model: MapModel, layer: ShipLayer) -> PlaySession:
	var play := PlaySession.new()
	play.player_faction = 1
	play.world = world
	play.model = model
	play.region_index = model.region_id
	play.ship_layer = layer
	play.map_seed = 1500
	return play


# --- rival economies (AiEconomyPlanner, AiState) ----------------------------
## The deferred half of docs/ai.md: each rival keeps a ledger, allocates
## production under the shared labour budget, and recruits through the same
## rules the player obeys (wiki: economy-planner, growth-stage-planner).


func test_ai_state_keeps_and_restores_rival_ledgers() -> void:
	var ai := AiState.new()
	var economy: PlayerEconomy = ai.economy_for(1)
	economy.add("grain", 7)
	economy.add_treasury(123)
	economy.production.set_assignment("lumber", 2)
	var restored: AiState = AiState.from_dict(ai.to_dict())
	var loaded: PlayerEconomy = restored.economy_for(1)
	assert_eq(loaded.quantity("grain"), economy.quantity("grain"))
	assert_eq(loaded.treasury, economy.treasury)
	assert_eq(loaded.production.assignment_units("lumber"), 2)


func test_ai_economy_respects_labour_and_inputs() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"timber": 10, "wool": 4}
	economy.workers = WorkerPool.make(6)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	var assignments: Array = plan["assignments"]
	assert_false(assignments.is_empty())
	var labour_used: int = 0
	var timber_used: int = 0
	var recipes: Array[String] = []
	for assignment: Dictionary in assignments:
		var recipe: String = String(assignment["recipe"])
		var units: int = int(assignment["units"])
		recipes.append(recipe)
		labour_used += units * ProductionRecipes.labour(recipe)
		timber_used += units * int(ProductionRecipes.inputs(recipe).get("timber", 0))
	assert_eq(labour_used, 6, "the plan spends exactly the available labour")
	assert_true(timber_used <= 10, "the same timber is never promised twice")
	# One run each in rank order: no build input takes the whole labour while
	# the muster's cloth goes unwoven (issue #474).
	assert_eq(recipes, ["fabric_from_wool", "lumber", "paper"] as Array[String])


func test_ai_economy_spreads_the_labour_across_the_build_inputs() -> void:
	# Iron and wool both in store, castIron's deficit as deep as fabric's: a
	# greedy plan wove no cloth at all, because castIron (which works spend
	# every turn) won the tie on every turn and the muster starved with a full
	# war chest (issue #474).
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"iron": 20, "wool": 21, "timber": 20}
	economy.workers = WorkerPool.make(10)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	var woven: int = 0
	for assignment: Dictionary in plan["assignments"]:
		if String(assignment["recipe"]) == "fabric_from_wool":
			woven = int(assignment["units"])
	assert_true(woven >= 1, "the court weaves cloth from the wool it holds")


func test_ai_economy_ignores_recipes_it_cannot_feed() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {}
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_true((plan["assignments"] as Array).is_empty())


## The raw the muster's and the hull's own material rows claim stands out of
## manufacture's reach: the plan never promises a run whose inputs would eat
## the regiment's cloth or the hull's timber, so a court saving for either can
## still manufacture everything else (issue #484, #878; wiki: economy-planner
## § Reservations).
func test_manufacture_plans_around_the_rows_the_chests_claim() -> void:
	var config: AiConfig = AiConfig.build(1, 1500)
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"timber": 4, "wool": 8}
	economy.workers = WorkerPool.make(6)
	var plain: Dictionary = AiEconomyPlanner.production_orders(config, economy)
	assert_true(_units_for(plain, "lumber") > 0, "the sawmill runs on its timber")

	var held: Dictionary = AiEconomyPlanner.production_orders(
		config, economy, 0, {"timber": 4}
	)
	assert_eq(_units_for(held, "lumber"), 0, "the yard's timber is not sawn")
	assert_eq(_units_for(held, "paper"), 0, "nor is any other timber row promised")
	assert_true(
		_units_for(held, "fabric_from_wool") > 0,
		"the rest of the plan still runs beside the chest"
	)


## A luxury row is a trained hand's work: a court with tobacco and furs but no
## apprentice is offered neither cigars nor fur hats, because the Production
## phase would refuse the run (wiki: production-recipes § Worker-tier gates;
## DR-20261114-07; REQ-P2-03).
func test_ai_economy_offers_no_gated_row_without_the_hand() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"tobacco": 20, "furs": 20}
	economy.workers = WorkerPool.make(6)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	for assignment: Dictionary in plan["assignments"]:
		assert_ne(String(assignment["recipe"]), "cigars", "no apprentice, no cigars")
		assert_ne(String(assignment["recipe"]), "furHats", "no journeyman, no fur hats")
	for candidate: Dictionary in plan["candidates"]:
		assert_ne(String(candidate["recipe"]), "cigars", "a gated row is no candidate")
		assert_ne(String(candidate["recipe"]), "furHats", "a gated row is no candidate")
	# One apprentice opens the cigar row, and the court takes it.
	economy.workers = WorkerPool.make(5, 1)
	var opened: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	var cigars: int = 0
	for assignment: Dictionary in opened["assignments"]:
		if String(assignment["recipe"]) == "cigars":
			cigars = int(assignment["units"])
	assert_true(cigars > 0, "an apprentice opens the cigar row")
	for assignment: Dictionary in opened["assignments"]:
		assert_ne(String(assignment["recipe"]), "furHats", "an apprentice is no journeyman")


## A court whose best town is too young for the second-stage rows is offered
## neither garments nor rum, because the Production phase would refuse the run;
## a level-2 town opens the cloth and a level-4 town the finer works (wiki:
## production-recipes § Town-works gates; DR-20261116-04; REQ-P2-03).
func test_ai_economy_offers_no_town_row_without_the_works() -> void:
	var economy := PlayerEconomy.starting()
	# Cloth and refined sugar in store: the second-stage rows are the only
	# deficits left, so the plan's answer is the works gate alone.
	economy.stockpile = {"fabric": 40, "refinedSugar": 40}
	economy.workers = WorkerPool.make(6)
	var config: AiConfig = AiConfig.build(1, 1500)
	for town_level in [0, 1]:
		var young: Dictionary = AiEconomyPlanner.production_orders(
			config, economy, town_level
		)
		for candidate: Dictionary in young["candidates"]:
			assert_ne(String(candidate["recipe"]), "garments", "a village has no works")
			assert_ne(String(candidate["recipe"]), "rum", "a village has no works")
	var town_two: Dictionary = AiEconomyPlanner.production_orders(config, economy, 2)
	assert_true(_units_for(town_two, "garments") > 0, "a level-2 town beats out cloth")
	assert_eq(_units_for(town_two, "rum"), 0, "the finer works wait on a level-4 town")
	var town_four: Dictionary = AiEconomyPlanner.production_orders(config, economy, 4)
	assert_true(_units_for(town_four, "rum") > 0, "a level-4 town opens the finer works")


## The plan and the phase read one town: a run the plan offers must be a run
## Production starts, or the court spends labour on nothing (REQ-P2-03).
func test_ai_economy_plan_runs_the_town_row_it_offers() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"fabric": 40, "refinedSugar": 40}
	economy.workers = WorkerPool.make(6)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy, 2
	)
	var report: Dictionary = ProductionPhase.plan(
		plan["assignments"] as Array[Dictionary],
		economy.stockpile.duplicate(),
		6,
		economy.tech_unlocked,
		{},
		economy.workers,
		2
	)
	assert_true(
		int((report["runs"] as Dictionary).get("garments", 0)) > 0,
		"the phase starts the cloth its town opened"
	)


## Units the plan assigns to one recipe, 0 when it names none.
func _units_for(plan: Dictionary, recipe_id: String) -> int:
	for assignment: Dictionary in plan["assignments"]:
		if String(assignment["recipe"]) == recipe_id:
			return int(assignment["units"])
	return 0


## A phantom run spends the plan's labour and reserves its inputs, then the phase
## refuses it: the court works less than it could. The plan must spend the whole
## idle labour on rows the phase will actually run (REQ-P2-03).
func test_ai_economy_plan_spends_the_labour_the_phase_will_use() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"tobacco": 20, "timber": 20}
	economy.workers = WorkerPool.make(6)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	var report: Dictionary = ProductionPhase.plan(
		plan["assignments"] as Array[Dictionary],
		economy.stockpile.duplicate(),
		6,
		economy.tech_unlocked,
		{},
		economy.workers
	)
	assert_eq(int(report["labour_used"]), 6, "the plan spends the labour the phase can use")


## The bench's random filler court draws from the same legal rows: a gated row is
## never its pick (wiki: production-recipes § Worker-tier gates; REQ-P2-03).
func test_random_court_never_picks_a_gated_row() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"tobacco": 40, "furs": 40}
	economy.workers = WorkerPool.make(8)
	for seed_value in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var plan: Dictionary = AiRandomCourt._random_production(economy, rng)
		for assignment: Dictionary in plan["assignments"]:
			assert_ne(String(assignment["recipe"]), "cigars", "no apprentice, no cigars")
			assert_ne(String(assignment["recipe"]), "furHats", "no journeyman, no fur hats")


func test_ai_economy_is_deterministic() -> void:
	var first := PlayerEconomy.starting()
	first.stockpile = {"timber": 8, "wool": 6}
	var second := PlayerEconomy.starting()
	second.stockpile = {"timber": 8, "wool": 6}
	var config: AiConfig = AiConfig.build(1, 1500)
	assert_eq(
		str(AiEconomyPlanner.production_orders(config, first)["assignments"]),
		str(AiEconomyPlanner.production_orders(config, second)["assignments"])
	)


func test_ai_economy_does_not_restack_the_workshop() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"copper": 60, "tin": 60}
	economy.workers = WorkerPool.make(0, 0, 0, 8)
	var config: AiConfig = AiConfig.build(1, 1500)
	var first: Dictionary = AiEconomyPlanner.production_orders(config, economy)
	var assigned: int = 0
	for assignment: Dictionary in first["assignments"]:
		if String(assignment["recipe"]) == "bronze":
			assigned = int(assignment["units"])
	assert_true(assigned > 0, "an empty reserve makes bronze worth running")
	economy.production_wip = {"bronze": [{"units": 99, "turns_left": 1}]}
	var second: Dictionary = AiEconomyPlanner.production_orders(config, economy)
	for assignment: Dictionary in second["assignments"]:
		assert_ne(String(assignment["recipe"]), "bronze", "the workshop already fills the deficit")


## A slow row's bench holds three pieces, so a fourth run waits for a landing.
## A plan that asks for it anyway spends the labour and reserves the inputs for
## a run the phase refuses, and the court works less than it could (wiki:
## production-recipes § Workshop queue; DR-20261114-12, DR-20261115-02).
func test_ai_economy_asks_no_run_the_full_bench_will_refuse() -> void:
	var economy := PlayerEconomy.starting()
	# Only lumber and steel are short: the bench's row is the one the plan must
	# leave alone, and the lumber runs are what the freed labour goes to.
	economy.stockpile = {
		"iron": 40, "coal": 40, "timber": 40, "lumber": 0,
		"castIron": 20, "fabric": 20, "paper": 20, "bronze": 20, "steel": 0,
	}
	economy.workers = WorkerPool.make(6)
	# The bench is full and still serving its first phase: no steel run starts.
	economy.production_wip = {"steel": [{"units": 3, "turns_left": 2}]}
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	var steel: int = 0
	for assignment: Dictionary in plan["assignments"]:
		if String(assignment["recipe"]) == "steel":
			steel = int(assignment["units"])
	assert_eq(steel, 0, "a full bench takes no fourth run")
	# The labour the phantom run would have eaten goes to the rows that start.
	var report: Dictionary = ProductionPhase.plan(
		plan["assignments"] as Array[Dictionary],
		economy.stockpile.duplicate(),
		6,
		economy.tech_unlocked,
		economy.production.wip.duplicate(true),
		economy.workers
	)
	assert_eq(int(report["labour_used"]), 6, "the plan spends the labour the phase can use")
	assert_eq(
		int((report["runs"] as Dictionary).get("steel", 0)), 0,
		"the phase starts no steel run the plan did not ask for"
	)


## A bench with one place left takes exactly one run: the plan reads the room,
## never the row's whole reserve (DR-20261114-12).
func test_ai_economy_fills_only_the_room_left_on_the_bench() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {
		"iron": 40, "coal": 40, "lumber": 20,
		"castIron": 20, "fabric": 20, "paper": 20, "bronze": 20, "steel": 0,
	}
	economy.workers = WorkerPool.make(8)
	economy.production_wip = {"steel": [{"units": 2, "turns_left": 2}]}
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	var steel: int = 0
	for assignment: Dictionary in plan["assignments"]:
		if String(assignment["recipe"]) == "steel":
			steel = int(assignment["units"])
	assert_eq(steel, 1, "two pieces on the anvil leave one place, not a whole batch")


## The bench's random filler court draws from the rows that can start: a full
## bench is no candidate either (wiki: production-recipes § Workshop queue;
## REQ-P2-03).
func test_random_court_never_asks_a_full_bench() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {
		"iron": 40, "coal": 40, "copper": 40, "tin": 40, "tobacco": 40, "furs": 40,
	}
	economy.workers = WorkerPool.make(0, 0, 1, 8)
	economy.production_wip = {
		"steel": [{"units": 3, "turns_left": 2}],
		"bronze": [{"units": 3, "turns_left": 2}],
		"cigars": [{"units": 3, "turns_left": 2}],
		"furHats": [{"units": 3, "turns_left": 2}],
	}
	for seed_value in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var plan: Dictionary = AiRandomCourt._random_production(economy, rng)
		for assignment: Dictionary in plan["assignments"]:
			var recipe_id: String = String(assignment["recipe"])
			assert_true(
				ProductionWorkshop.room(
					economy.production.wip, recipe_id,
					ProductionRecipes.turns(recipe_id)
				) > 0,
				"a full bench is no candidate: %s" % recipe_id
			)


## A plan takes effect after this phase resolves, so the run the queued
## assignment will start this phase already fills the reserve: the court must not
## stack a second alloy batch against it (DR-20261112-11).
func test_ai_economy_counts_the_run_this_phase_will_start() -> void:
	var economy := PlayerEconomy.starting()
	economy.workers = WorkerPool.make(0, 0, 0, 1)
	economy.stockpile = {
		"copper": 60, "tin": 60, "grain": 200, "meat": 200, "furHats": 200,
		"bronze": 19,
	}
	var config: AiConfig = AiConfig.build(1, 1500)
	economy.production.set_assignment("bronze", 1)
	var plan: Dictionary = AiEconomyPlanner.production_orders(config, economy)
	for assignment: Dictionary in plan["assignments"]:
		assert_ne(
			String(assignment["recipe"]), "bronze",
			"the queued run already fills the one unit the reserve is short"
		)


func test_ai_economy_recruits_the_highest_affordable_tier() -> void:
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {
		"apprentice_workers": true,
		"sugar_refining": true,
		"trained_journeymen": true,
		"cigar_production": true,
	}
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_eq(orders.size(), 1)
	assert_eq(int(orders[0]["tier"]), WorkerPool.Tier.JOURNEYMAN)
	assert_eq(economy.workers.total(), 6, "planning never spends the live ledger")


func test_ai_economy_stops_recruiting_at_the_worker_target() -> void:
	var economy := PlayerEconomy.starting()
	economy.workers = WorkerPool.make(10)
	assert_true(
		AiEconomyPlanner.recruitment_orders(AiConfig.build(1, 1500), economy).is_empty()
	)


func test_ai_economy_buys_peasants_until_the_worker_target() -> void:
	var economy := PlayerEconomy.starting()
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_eq(orders.size(), 1, "one recruit a turn")
	assert_eq(
		int(orders[0]["tier"]), WorkerPool.Tier.PEASANT,
		"the only tier a techless court can buy"
	)
	var applied: PlayerEconomy = economy.copy()
	assert_true(bool(applied.recruit(WorkerPool.Tier.PEASANT).get("ok", false)))
	assert_eq(applied.workers.total(), 7, "a peasant recruit grows the pool")
	assert_eq(applied.quantity("fabric"), 10, "two fabric per peasant")


## Wiki: workers-and-population § Rival training throttle — training never eats
## the last peasant, so a rival can still muster and keep headcount.
func test_ai_economy_never_trains_away_its_last_peasant() -> void:
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers = WorkerPool.make(2)
	economy.treasury = 600
	economy.add("paper", 10)
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_eq(orders.size(), 1, "two peasants is the floor to train against")
	assert_eq(int(orders[0]["tier"]), WorkerPool.Tier.APPRENTICE)
	economy.workers = WorkerPool.make(1)
	orders = AiEconomyPlanner.recruitment_orders(AiConfig.build(1, 1500), economy)
	assert_true(orders.is_empty(), "one peasant must stay to raise more")


## The purse throttle: a court that could train again next turn never drops
## under `economy.min_treasury` (500) by more than one training's price.
func test_ai_economy_training_stops_when_the_next_turn_could_repeat() -> void:
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers = WorkerPool.make(4)
	economy.treasury = 900
	economy.add("paper", 10)
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_eq(orders.size(), 1, "one training a turn however fat the purse")
	assert_eq(int(orders[0]["tier"]), WorkerPool.Tier.APPRENTICE)
	assert_eq(economy.treasury, 900, "planning never spends the live ledger")


## The war chest the muster needs outranks worker growth: a court saving for its
## next regiment trains nobody until the purse clears the muster floor its
## planner hands it (wiki: growth-stage-planner § Recruitment modulation;
## issue #474).
func test_ai_economy_holds_the_muster_war_chest_before_training() -> void:
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers = WorkerPool.make(4)
	economy.treasury = 1500
	economy.add("paper", 10)
	var config: AiConfig = AiConfig.build(1, 1500)

	assert_true(
		AiEconomyPlanner.recruitment_orders(config, economy, 2400).is_empty(),
		"the purse is short of the muster, so no hand is hired"
	)
	assert_false(
		AiEconomyPlanner.recruitment_orders(config, economy).is_empty(),
		"without a muster the same purse still grows the pool"
	)


## The muster hand reservation, behind the un-latch (issue #807): a court at war
## under its target with the line's row in store and the chest in hand keeps
## `army.min_peasants` + the levy's own hand in the fields, so training never
## makes the muster illegal (`labour 0/1`).
func test_ai_economy_keeps_the_musters_own_hand() -> void:
	var config: AiConfig = AiConfig.build(1, 1500)
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.treasury = 5000
	# The retuned floor is 1 free hand (issue #1314 companion; issue #1355), so
	# the reservation is the floor plus the levy's hand — two heads — and the
	# published last-peasant throttle holds while the pool stands at it. The
	# extra head is the reservation's own point: a levy that drew the floor's
	# hand to the head would leave an empty pool behind it.
	economy.stockpile = {"fabric": 10, "castIron": 10, "lumber": 10}
	economy.add("paper", 10)
	var hands: int = AiArmyReinforce.muster_hands(config, economy, 0, true)
	assert_eq(
		hands, config.parameter("army.min_peasants") + 1,
		"the muster's floor plus the levy's own hand"
	)
	# The pool stands at the reservation: the last-peasant throttle keeps it
	# there — the levy's hand survives the pass.
	economy.workers = WorkerPool.make(hands)
	assert_true(
		AiEconomyPlanner.recruitment_orders(config, economy, 0, -1, hands).is_empty(),
		"the reserved hand survives the pass"
	)
	assert_eq(
		hands, config.parameter("army.min_peasants") + 1,
		"the fields still spare the muster its hand"
	)
	# One head over the reservation and the pass hires again: the reservation
	# is a floor the pool grows past, not a wall (the retune's own point).
	economy.workers = WorkerPool.make(hands + 1)
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		config, economy, 0, -1, hands
	)
	assert_eq(orders.size(), 1, "one recruit a turn above the reservation")
	assert_eq(int(orders[0]["tier"]), WorkerPool.Tier.APPRENTICE, "the spare head grows the pool")


func test_a_court_not_arming_keeps_no_hand() -> void:
	var config: AiConfig = AiConfig.build(1, 1500)
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.treasury = 5000
	economy.add("paper", 10)
	economy.stockpile = {"fabric": 10, "castIron": 10, "lumber": 10}

	assert_eq(
		AiArmyReinforce.muster_hands(config, economy, 0, false), 0,
		"at peace the pool grows freely"
	)
	assert_eq(
		AiArmyReinforce.muster_hands(config, economy, 12, true), 0,
		"at the war target the court is not arming"
	)
	var broke: PlayerEconomy = economy.copy()
	broke.treasury = 500
	assert_eq(
		AiArmyReinforce.muster_hands(config, broke, 0, true), 0,
		"the chest is not in hand, so no hand is kept"
	)


## The standing study's own row move (issue #1059): through the state's public
## row API, so no study's progress is cancelled — the swap restores what it
## moved. A placeholder for the shape the probe caught; the real lift is the
## planner's `_swap_slots`.
func _swap_slots(state: ResearchState, from_slot: int, to_slot: int) -> void:
	if state == null or from_slot == to_slot:
		return
	var from_tech: String = state.tech_at(from_slot)
	var to_tech: String = state.tech_at(to_slot)
	if from_tech.is_empty() or to_tech.is_empty():
		return
	var from_funding: String = state.funding_at(from_slot)
	var from_progress: int = state.progress_of(from_tech)
	var to_funding: String = state.funding_at(to_slot)
	var to_progress: int = state.progress_of(to_tech)
	state.cancel(from_slot)
	state.cancel(to_slot)
	if not bool(state.assign(from_tech, from_funding, to_slot).get("ok", false)):
		return
	if not bool(state.assign(to_tech, to_funding, from_slot).get("ok", false)):
		return
	if from_progress > 0:
		state.add_progress(from_tech, from_progress)
	if to_progress > 0:
		state.add_progress(to_tech, to_progress)


## The bar the harvest carries (issue #1059): a court banking for its army
## hires to the levy's own pool — `army.min_peasants` plus the levy's hand —
## and stops there, because every mouth past it eats one of the rations the
## muster's own gate plans with. The measured probe watched the farms' growth
## (+7 rations a turn by t80) fall whole into six new mouths; the slack sat at
## 0 for a hundred turns and the muster's gate with it.
func test_a_banking_court_paces_the_hires_to_the_harvest() -> void:
	var config: AiConfig = AiConfig.build(1, 1500)
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	# The retuned levy floor is 2 (min_peasants 1 + the levy's hand 1, issue
	# #1314 companion), so the pool that "is met" moves down with it.
	economy.workers = WorkerPool.make(4)
	economy.treasury = 8000
	economy.add("paper", 10)
	# The bank holds and the land carries one more ration: the levy's pool is
	# past its floor and the bank paces — the trained tiers and the worker
	# target wait for the muster to stand.
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		config, economy, 0, -1, 0, true, 1
	)
	assert_true(orders.is_empty(), "the levy's pool is met; the ladder waits")
	# One peasant short of the levy floor: the farmhand comes first (the
	# #1023 provision), paid against the harvest it eats.
	economy.workers = WorkerPool.make(1)
	orders = AiEconomyPlanner.recruitment_orders(
		config, economy, 0, -1, 0, true, 1
	)
	assert_eq(orders.size(), 1, "the farmhand the levy needs")
	assert_eq(int(orders[0]["tier"]), WorkerPool.Tier.PEASANT)
	# The land cannot carry one more ration: the hire stands down, and the
	# slack the muster plans with is not spent on a mouth.
	orders = AiEconomyPlanner.recruitment_orders(
		config, economy, 0, -1, 0, true, 0
	)
	assert_true(orders.is_empty(), "no ration spare, no hire")
	# An unbanked court keeps the published pool target (10): the same purse
	# and the same slack still grow the pool.
	economy.workers = WorkerPool.make(4)
	orders = AiEconomyPlanner.recruitment_orders(
		config, economy, 0, -1, 0, false, 1
	)
	assert_eq(orders.size(), 1, "no bank, the published ladder leads")
	# A caller with no harvest reading (-2) keeps the published target too.
	orders = AiEconomyPlanner.recruitment_orders(
		config, economy, 0, -1, 0, true, -2
	)
	assert_eq(orders.size(), 1, "no reading, the published behaviour")
	var short_row: PlayerEconomy = economy.copy()
	short_row.stockpile = {"fabric": 0}
	assert_eq(
		AiArmyReinforce.muster_hands(config, short_row, 0, true), 0,
		"the row is not in store, so no hand is kept"
	)


## The reserve is a floor for a court with slack, not a veto: a purse that can no
## longer fund the next row (and more) still takes the one training it can.
func test_ai_economy_spends_the_last_affordable_training() -> void:
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers = WorkerPool.make(4)
	economy.treasury = 400
	economy.add("paper", 10)
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_eq(orders.size(), 1, "400 cannot fund two apprentices, but one fits")
	assert_eq(int(orders[0]["tier"]), WorkerPool.Tier.APPRENTICE)
	var applied: PlayerEconomy = economy.copy()
	assert_true(bool(applied.recruit(WorkerPool.Tier.APPRENTICE).get("ok", false)))
	assert_eq(applied.treasury, 200, "the live ledger pays the same 200 row")


## A rich court that would train a journeyman under the reserve still holds when a
## cheaper trained tier remains affordable from today's slack (the purse throttle's
## true branch: best cost and next-turn cost differ).
func test_ai_economy_holds_a_journeyman_when_slack_could_retrain() -> void:
	var economy := PlayerEconomy.starting()
	economy.tech_unlocked = {
		"apprentice_workers": true,
		"sugar_refining": true,
		"trained_journeymen": true,
		"cigar_production": true,
	}
	economy.workers = WorkerPool.make(4)
	economy.treasury = 900
	economy.add("paper", 10)
	var orders: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_true(
		orders.is_empty(),
		"900 − 500 lands under 500 while 900 − 500 still funds an apprentice"
	)
	assert_true(
		AiEconomyPlanner._next_training_affordable(economy, 500),
		"slack outside the reserve already pays a trained row"
	)
	assert_true(AiEconomyPlanner._techs_open(economy, WorkerPool.Tier.APPRENTICE))
	assert_eq(AiEconomyPlanner._trains(null, WorkerPool.Tier.APPRENTICE), -1)
	assert_eq(AiEconomyPlanner._trains(economy, -1), -1)
	assert_eq(AiEconomyPlanner._trains(economy, WorkerPool.TIER_COUNT), -1)


# --- rival civilians (AiCivilianPlanner) ------------------------------------


func test_ai_builder_raises_an_owned_estate() -> void:
	var model: MapModel = CivilianFixture.build()
	var units: Array = [CivilianState.create(1, 0, "builder", CivilianFixture.BARE_TILE)]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_improvement")
	assert_eq(Vector2i(orders[0]["tile"]), CivilianFixture.TIMBER_TILE)


## A crew aboard a squadron is off the map: every candidate the pass scores is
## gated by CivilianWork, so its plan names a passenger neither work nor a march
## (wiki: civilian-units § Overseas deployment).
func test_ai_plans_no_work_for_a_crew_aboard_a_squadron() -> void:
	var model: MapModel = CivilianFixture.build()
	var passenger: CivilianState = CivilianState.create(
		1, 0, "builder", CivilianFixture.BARE_TILE
	)
	passenger.embark_on(3)
	var units: Array = [passenger]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	assert_true((plan["orders"] as Array).is_empty(), "no estate for a passenger")
	assert_true((plan["moves"] as Array).is_empty(), "and no march")
	# The same court with the crew ashore still books the raise, so the skip is
	# the passenger's state and not the fixture.
	passenger.embarked_fleet = -1
	passenger.tile = CivilianFixture.BARE_TILE
	var ashore: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	assert_eq((ashore["orders"] as Array).size(), 1)


func test_ai_explorer_prospects_its_own_mineral() -> void:
	var model: MapModel = CivilianFixture.build()
	var units: Array = [
		CivilianState.create(1, 0, "explorer", CivilianFixture.IRON_TILE)
	]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), "prospect")
	assert_eq(Vector2i(plan["orders"][0]["tile"]), CivilianFixture.IRON_TILE)


func test_ai_explorer_walks_toward_an_unprospected_mineral() -> void:
	var model: MapModel = CivilianFixture.build()
	var units: Array = [
		CivilianState.create(1, 0, "explorer", CivilianFixture.BARE_TILE)
	]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	var moves: Array = plan["moves"]
	assert_eq(moves.size(), 1)
	assert_ne(Vector2i(moves[0]["tile"]), CivilianFixture.BARE_TILE)


func test_ai_engineer_builds_a_road_to_a_resource() -> void:
	var model: MapModel = CivilianFixture.build()
	var units: Array = [
		CivilianState.create(1, 0, "engineer", CivilianFixture.BARE_TILE)
	]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), "build_road")
	var tile: Vector2i = plan["orders"][0]["tile"]
	assert_ne(model.resource_at(tile.x, tile.y), MapModel.NO_ID, "the road reaches a resource")


func test_ai_engineer_raises_a_fort_when_at_war() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	works.set_transport(model, CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, CivilianFixture.IRON_TILE, LandWorks.TRANSPORT_ROAD)
	works.add_port(model, CivilianFixture.COAST_TILE)
	var units: Array = [
		CivilianState.create(1, 0, "engineer", CivilianFixture.BARE_TILE)
	]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, works,
		CivilianFixture.stockpile(), {}, {}, _civilian_context(true)
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), "build_fort")


func test_ai_civilian_training_needs_a_capital_and_a_purse() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var rich: Dictionary = _civilian_context()
	var order: Dictionary = AiCivilianHire.training_order(config, [], rich)
	assert_true(bool(order.get("ok", false)))
	assert_eq(String(order["type_id"]), "builder")
	var poor: Dictionary = _civilian_context()
	poor["treasury"] = 0
	assert_false(bool(AiCivilianHire.training_order(config, [], poor).get("ok", false)))
	poor["capital_province"] = -1
	poor["treasury"] = 2500
	assert_false(bool(AiCivilianHire.training_order(config, [], poor).get("ok", false)))


## The bank holds the purse (issue #1059): a court short of the bar banking for
## its next line hires its provision crews — the Builder and the Engineer the
## farms and their roads need — against the works purse it always had, but the
## rest of the college's ladder (Explorer, Merchant, Spy) stands behind the
## chest, so the chart the empire grows does not burn the fill the muster
## waits for. The measured bench banked 193 turns while the college re-hired
## an Explorer roughly every tenth turn.
func test_a_banking_court_hires_only_its_provision_crews() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var banked: Dictionary = _civilian_context()
	banked["conquest_bank"] = true
	# A Builder rides the works purse the farm trim keeps: the hire stands.
	var builder: Dictionary = AiCivilianHire.training_order(config, [], banked)
	assert_true(bool(builder.get("ok", false)), "the provision Builder keeps its purse")
	assert_eq(String(builder["type_id"]), "builder")
	# An Engineer serves the same farms (their roads): the hire stands too.
	banked["staff_targets"] = {"engineer": 1, "builder": 0}
	var engineer: Dictionary = AiCivilianHire.training_order(
		config, [CivilianState.create(1, 0, "builder", CivilianFixture.BARE_TILE)], banked
	)
	assert_true(bool(engineer.get("ok", false)), "the road crew serves the farms")
	assert_eq(String(engineer["type_id"]), "engineer")
	# The Explorer's ladder reads the standing purse: a banked court with a
	# purse under its chest hires no new chart, and the closed hire says why.
	banked["staff_targets"] = {"explorer": 3}
	var chart: Dictionary = AiCivilianHire.training_order(
		config,
		[
			CivilianState.create(1, 0, "builder", CivilianFixture.BARE_TILE),
			CivilianState.create(2, 0, "engineer", CivilianFixture.BARE_TILE),
		],
		banked
	)
	assert_eq(String(chart.get("reason", "")), AiCivilianHire.REASON_BANK)
	assert_false(bool(chart.get("ok", false)), "the chart stands behind the chest")


## A court not banking keeps the published purses: the Explorer still rides
## the works purse on `earn` (the #489/#603 income lever), and a baseline
## court's config never reaches the banked read at all.
func test_an_unbanked_court_keeps_the_published_hire_purses() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var plain: Dictionary = _civilian_context()
	plain["hire_treasury"] = 100
	plain["staff_targets"] = {"explorer": 3}
	# `earn` lifts the works purse to the treasury itself (published read).
	plain["earn"] = true
	var chart: Dictionary = AiCivilianHire.training_order(config, [], plain)
	assert_true(bool(chart.get("ok", false)), "the published purse hires the chart")
	assert_eq(String(chart["type_id"]), "explorer")


## Staff targets read the region's work: plains floor, hills digs, and the
## voyage slot — and training stops when every target is already met. The court
## here is neutral, so the targets are the region's own and nothing else: the
## archetype's extra crew is the next test's reading.
func test_ai_civilian_staff_targets_follow_the_regions_work() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	config.personality = AiPersonality.NEUTRAL
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	var context: Dictionary = _civilian_context()
	var floors: Dictionary = AiCivilianTargets.staff_targets(
		config, null, null, [], {}, {}, context
	)
	assert_eq(int(floors["builder"]), 2)
	assert_eq(int(floors["engineer"]), config.parameter("civilian.engineer_target"))
	assert_eq(int(floors["explorer"]), config.parameter("civilian.explorer_target"))
	context["muster_port"] = CivilianFixture.COAST_TILE
	var with_voyage: Dictionary = AiCivilianTargets.staff_targets(
		config, model, works, [], CivilianFixture.stockpile(), {}, context
	)
	assert_true(
		int(with_voyage["explorer"]) > int(floors["explorer"]),
		"a pending voyage keeps one Explorer free to sail"
	)
	assert_true(int(with_voyage["engineer"]) >= int(floors["engineer"]))
	var met: Array[CivilianState] = []
	for i in int(floors["builder"]):
		met.append(CivilianState.create(i + 1, 0, "builder", CivilianFixture.BARE_TILE))
	for i in int(floors["engineer"]):
		met.append(CivilianState.create(10 + i, 0, "engineer", CivilianFixture.BARE_TILE))
	for i in int(floors["explorer"]):
		met.append(CivilianState.create(20 + i, 0, "explorer", CivilianFixture.BARE_TILE))
	met.append(CivilianState.create(30, 0, "spy", CivilianFixture.BARE_TILE))
	var stop: Dictionary = _civilian_context()
	stop["staff_targets"] = floors
	assert_true(
		AiCivilianHire.training_order(config, met, stop).is_empty(),
		"a court at its targets trains nothing"
	)


## The archetype's own crew (wiki: civilian-build-planner § Architecture): a
## court keeps one more of the type its leader leans on than the region's work
## asks, and nothing more — a merchant still waits on a deed, the spy's second
## stands only for the tactician, and a court with no archetype keeps the
## published targets exactly.
func test_ai_civilian_taste_keeps_the_archetypes_own_crew() -> void:
	var context: Dictionary = _civilian_context()
	var own: Dictionary = AiCivilianTargets.region_targets(
		AiConfig.new(), null, null, [], {}, {}, context
	)
	var fortifier: AiConfig = AiConfig.build(2, 1500)
	var napoleon: Dictionary = AiCivilianTargets.staff_targets(
		fortifier, null, null, [], {}, {}, context
	)
	assert_eq(int(napoleon["engineer"]), int(own["engineer"]) + 1)
	assert_eq(int(napoleon["builder"]), int(own["builder"]))
	assert_eq(AiStaffTaste.note(fortifier), "the fortifier's taste")
	var explorer: Dictionary = AiCivilianTargets.staff_targets(
		AiConfig.build(0, 1500), null, null, [], {}, {}, context
	)
	assert_eq(int(explorer["explorer"]), int(own["explorer"]) + 1)
	assert_eq(int(explorer["builder"]), int(own["builder"]))
	var trader: Dictionary = AiCivilianTargets.staff_targets(
		AiConfig.build(1, 1500), null, null, [], {}, {}, context
	)
	assert_eq(int(trader["builder"]), int(own["builder"]) + 1)
	# A merchant is only wanted when a deed door is open, so the trader's crew
	# waits on the door rather than hiring a merchant with nowhere to walk.
	var ruyter: AiConfig = AiConfig.build(4, 1500)
	var no_deed: Dictionary = AiCivilianTargets.staff_targets(
		ruyter, null, null, [], {}, {}, context
	)
	assert_eq(int(no_deed["merchant"]), 0)
	var deed: Dictionary = _civilian_context()
	deed["merchant_targets"] = 1
	assert_eq(
		int(AiCivilianTargets.staff_targets(ruyter, null, null, [], {}, {}, deed)["merchant"]),
		2,
	)
	var tactician: Dictionary = AiCivilianTargets.staff_targets(
		AiConfig.build(5, 1500), null, null, [], {}, {}, context
	)
	assert_eq(int(tactician["spy"]), int(own["spy"]) + 1)
	var no_archetype := AiConfig.new()
	no_archetype.faction = 0
	var plain: Dictionary = AiCivilianTargets.staff_targets(
		no_archetype, null, null, [], {}, {}, context
	)
	for type_id: String in AiStaffTaste.TYPES:
		assert_eq(
			int(plain.get(type_id, 0)),
			int(own.get(type_id, 0)),
			"a court with no archetype keeps the published %s target" % type_id,
		)


## A court at every target the map asks for still hires its own crew, and the
## order says the taste asked rather than the region (REQ-P5-05): the crew is
## paid at the catalogue's price through the published gate.
func test_ai_civilian_taste_crew_is_hired_at_the_maps_target() -> void:
	var context: Dictionary = _civilian_context()
	var fortifier: AiConfig = AiConfig.build(2, 1500)
	var own: Dictionary = AiCivilianTargets.region_targets(
		fortifier, null, null, [], {}, {}, context
	)
	var met: Array[CivilianState] = []
	for type_id: String in ["builder", "engineer", "explorer", "spy"]:
		for i in int(own.get(type_id, 0)):
			met.append(CivilianState.create(
				met.size() + 1, fortifier.faction, type_id, CivilianFixture.BARE_TILE
			))
	context["own_targets"] = own
	context["staff_targets"] = AiCivilianTargets.staff_targets(
		fortifier, null, null, met, {}, {}, _civilian_context()
	)
	var order: Dictionary = AiCivilianHire.training_order(fortifier, met, context)
	assert_true(bool(order.get("ok", false)), "the region's targets are met, the taste's is not")
	assert_eq(String(order["type_id"]), "engineer")
	assert_true(bool(order["taste"]), "the hire is the court's own crew")
	fortifier.personality = AiPersonality.NEUTRAL
	var neutral: Dictionary = _civilian_context()
	neutral["own_targets"] = own
	neutral["staff_targets"] = own
	assert_true(
		AiCivilianHire.training_order(fortifier, met, neutral).is_empty(),
		"without a taste the same roster has nothing left to hire"
	)


func test_ai_civilian_leaves_a_working_unit_alone() -> void:
	var model: MapModel = CivilianFixture.build()
	var builder: CivilianState = CivilianState.create(
		1, 0, "builder", CivilianFixture.TIMBER_TILE
	)
	builder.start_work("build_improvement", CivilianFixture.TIMBER_TILE, 1)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [builder], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())


## One ranker for every civilian work module (REQ-P3-01 reuse): the highest
## score wins, and a tie falls back to the earlier tile, then the earlier action
## name, so two closures over one tile never depend on evaluation order.
func test_civilian_candidate_ranking_is_one_shared_rule() -> void:
	var low: Dictionary = {"action": "build_road", "tile": Vector2i(4, 4), "score": 10}
	var high: Dictionary = {"action": "build_rail", "tile": Vector2i(9, 9), "score": 30}
	assert_eq(
		String(AiCivilianCandidate.better(low, high)["action"]), "build_rail"
	)
	assert_eq(String(AiCivilianCandidate.better(high, low)["action"]), "build_rail")
	var east: Dictionary = {"action": "build_road", "tile": Vector2i(5, 2), "score": 10}
	var north: Dictionary = {"action": "build_road", "tile": Vector2i(1, 1), "score": 10}
	assert_eq(AiCivilianCandidate.better(east, north)["tile"], Vector2i(1, 1))
	var rail: Dictionary = {"action": "build_rail", "tile": Vector2i(1, 1), "score": 10}
	assert_eq(String(AiCivilianCandidate.better(rail, north)["action"]), "build_rail")
	assert_eq(String(AiCivilianCandidate.better(north, rail)["action"]), "build_rail")
	assert_eq(
		AiCivilianCandidate.better(low, {}).get("action"), low["action"],
		"an empty candidate never displaces a real one"
	)
	assert_eq(AiCivilianCandidate.better({}, low).get("action"), low["action"])
	assert_true(AiCivilianCandidate.better({}, {}).is_empty())


## A closure that decides somewhere other than where its unit stands ranks by
## that site, so a sailed charter is ordered by its destination.
func test_civilian_candidate_ranks_by_site_before_the_unit() -> void:
	var stand: Vector2i = CivilianFixture.BARE_TILE
	var unit: CivilianState = CivilianState.create(1, 0, "merchant", stand)
	assert_eq(AiCivilianCandidate.rank_tile({"tile": Vector2i(3, 1)}), Vector2i(3, 1))
	assert_eq(
		AiCivilianCandidate.rank_tile({"tile": CivilianState.NO_TILE, "target": Vector2i(7, 2)}),
		Vector2i(7, 2)
	)
	assert_eq(AiCivilianCandidate.rank_tile({"unit": unit}), stand)
	assert_eq(
		AiCivilianCandidate.rank_tile({"action": "sail"}),
		CivilianState.NO_TILE
	)


func test_ai_civilian_never_plans_another_courts_units() -> void:
	var model: MapModel = CivilianFixture.build()
	var rival: CivilianState = CivilianState.create(
		1, 1, "builder", CivilianFixture.BARE_TILE
	)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [rival], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _civilian_context()
	)
	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())


## The crown's own pick (DR-20261117-06): an idle Builder of the crown is named
## with the estate the published planner would raise, and the line prices the
## level in the estates ledger's own words. It is a reading — the plan is not
## applied, so the crew is still idle and the tile still unraised afterwards.
func test_the_crowns_pick_names_the_estate_its_builder_would_raise() -> void:
	var play: PlaySession = _rival_economy_play()
	var model: MapModel = play.model
	var layer: CivilianLayer = play.civilian_layer
	var grain := Vector2i(1, 1)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", grain)
	layer.units.assign([builder] as Array[CivilianState])
	layer.regions.set_region(0, layer.units)
	var economy: PlayerEconomy = play.ai.economy_for(1)
	economy.stockpile["lumber"] = 40
	economy.stockpile["castIron"] = 40
	layer.works.set_improvement(model, grain, 0)

	var picks: Dictionary = MapPlayCivilianPick.picks(play, 1)

	var pick: Dictionary = picks.get(builder.id, {}) as Dictionary
	assert_false(pick.is_empty(), "the crown's Builder is given a pick")
	assert_eq(String(pick["action"]), "build_improvement", "it raises the estate")
	assert_eq(Vector2i(pick["tile"]), grain, "on the ground it stands on")
	var line: String = String(pick["line"])
	assert_true(line.begins_with("the court would raise the "), line)
	assert_true(line.contains("L1"), "the level the order would buy: " + line)
	assert_eq(String(pick["short"]), "raise the farm", "the short form names the work")
	assert_false(builder.is_working(), "a reading, not an order")
	assert_eq(layer.works.improvement_at(model, grain), 0, "and the estate is unraised")
	layer.free()


## The sheet's own wiring: a crew of the crown that waits carries the pick into
## its dossier, a working crew carries none, and a caller that names no crew
## reads the purse alone (DR-20261117-06).
func test_the_crowns_sheet_carries_the_pick_only_for_a_crew_that_waits() -> void:
	var play: PlaySession = _rival_economy_play()
	var model: MapModel = play.model
	var layer: CivilianLayer = play.civilian_layer
	var grain := Vector2i(1, 1)
	play.player_faction = 1
	var controller := EconomyController.new()
	controller.economy = play.ai.economy_for(1)
	play.economy = controller
	var builder: CivilianState = CivilianState.create(1, 1, "builder", grain)
	layer.units.assign([builder] as Array[CivilianState])
	layer.regions.set_region(0, layer.units)
	layer.works.set_improvement(model, grain, 0)
	var economy: PlayerEconomy = play.ai.economy_for(1)
	economy.stockpile["lumber"] = 40
	economy.stockpile["castIron"] = 40
	controller.economy = economy

	var sheet: Dictionary = MapPlayCivilians._context(play, builder)

	assert_true(sheet.has("pick"), "an idle crew's sheet carries its pick")
	assert_eq(
		String((sheet["pick"] as Dictionary).get("action", "")), "build_improvement"
	)
	assert_false(
		MapPlayCivilians._context(play).has("pick"), "no crew named, no pick"
	)
	builder.start_work("build_improvement", grain, 1)
	assert_false(
		MapPlayCivilians._context(play, builder).has("pick"),
		"a crew at work is already spoken for"
	)
	layer.free()


## The pick's own words, order kind by order kind: the label the sheet prints and
## the payoff the ledger that sells the work already names (DR-20261117-06). The
## words are handed to the sheet verbatim, so this is where every branch is read.
func test_the_pick_words_every_order_kind() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	var road: Dictionary = _pick_of("build_road", CivilianFixture.BARE_TILE, model, works)
	assert_eq(String(road["short"]), "build a road")
	assert_true(
		String(road["line"]).contains("an estate here gathers up to"),
		String(road["line"])
	)
	assert_eq(
		String(_pick_of("build_port", CivilianFixture.COAST_TILE, model, works)["short"]),
		"build a harbour"
	)
	var rail: Dictionary = _pick_of("build_rail", CivilianFixture.BARE_TILE, model, works)
	assert_eq(String(rail["short"]), "lay a railroad")
	assert_true(String(rail["line"]).contains("Transport 4"), String(rail["line"]))
	var fort: Dictionary = _pick_of("build_fort", CivilianFixture.BARE_TILE, model, works)
	assert_eq(String(fort["short"]), "raise the wood fort")
	assert_true(String(fort["line"]).contains("wall hp"), String(fort["line"]))
	var ward: Dictionary = _pick_of(
		"build_hospital", CivilianFixture.BARE_TILE, model, works
	)
	assert_eq(String(ward["short"]), "raise the L1 ward")
	assert_true(String(ward["line"]).contains("rests"), String(ward["line"]))
	var town_pick: Dictionary = _pick_of(
		"upgrade_town", CivilianFixture.BARE_TILE, model, works
	)
	assert_eq(String(town_pick["short"]), "raise the town to L2")
	assert_true(
		String(town_pick["line"]).contains("L2 pays 1 manufacture per 4 raw"),
		"the pick names what the level pays, not only the step: %s" % town_pick["line"]
	)
	var survey: Dictionary = _pick_of("explore", CivilianFixture.BARE_TILE, model, works)
	assert_eq(String(survey["short"]), "survey Cádiz")
	assert_eq(String(survey["line"]), "the court would survey Cádiz", "no ledger pays it")
	var deed: Dictionary = _pick_of(
		"purchase_land", CivilianFixture.BARE_TILE, model, works
	)
	assert_true(String(deed["short"]).begins_with("buy the deed at"))
	var screen: Dictionary = _pick_of(
		"counter_spy", CivilianFixture.BARE_TILE, model, works
	)
	assert_eq(String(screen["short"]), "keep the counter-espionage screen")
	# An order kind with no line of its own falls back to the work's own label.
	assert_eq(
		String(_pick_of("sail", CivilianFixture.BARE_TILE, model, works)["short"]), "sail"
	)
	# Ground outside every province reads as the wilds, not a blank place.
	assert_eq(
		String(_pick_of("explore", Vector2i(4, 4), model, works)["short"]),
		"survey the wilds"
	)


## The work is not always underfoot — a Builder raises an estate anywhere on
## crown land — so a pick away from the crew names the ground. The task list the
## line sits on presses the crew's own tile, and the chart rings the named one
## (wiki: civilian-units § Work Order Summary; DR-20261117-06).
func test_the_pick_names_the_ground_when_the_work_is_not_underfoot() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	var away: Array[CivilianState] = [
		CivilianState.create(1, 0, "builder", CivilianFixture.BARE_TILE)
	]
	var order: Dictionary = {"action": "build_improvement", "unit_id": 1}
	order["tile"] = CivilianFixture.TIMBER_TILE
	var pick: Dictionary = MapPlayCivilianPick._order_pick(
		model, works, away, 0, {}, CivilianFixture.stockpile(),
		{"capital_tile": CivilianFixture.BARE_TILE}, null, order
	)
	assert_true(
		String(pick["line"]).contains("at Cádiz (0, 2)"),
		"the ground the order names: " + String(pick["line"])
	)
	assert_eq(String(pick["short"]), "raise the lumber camp", "the short form still names the work")
	# Standing on the estate, the line says nothing it does not need.
	var here: Array[CivilianState] = [
		CivilianState.create(1, 0, "builder", CivilianFixture.TIMBER_TILE)
	]
	var underfoot: Dictionary = MapPlayCivilianPick._order_pick(
		model, works, here, 0, {}, CivilianFixture.stockpile(),
		{"capital_tile": CivilianFixture.BARE_TILE}, null, order
	)
	assert_false(
		String(underfoot["line"]).contains("(0, 2)"),
		"no ground clause underfoot: " + String(underfoot["line"])
	)


## The march the pass books when no work is legal: the step and the ground it
## walks toward, so the crown sees where its crew is being sent.
func test_the_pick_names_the_march_the_court_would_order() -> void:
	var model: MapModel = CivilianFixture.build()
	var move: Dictionary = MapPlayCivilianPick._move_pick(
		model, {"tile": CivilianFixture.BARE_TILE}
	)
	assert_eq(String(move["action"]), MapPlayCivilianPick.KIND_MOVE)
	assert_eq(String(move["line"]), "the court would march toward Cádiz (0, 0)")
	assert_true(MapPlayCivilianPick._move_pick(model, {}).is_empty(), "no step, no pick")


## The reading keeps its edges quiet: no session, no roster, no ledger and a
## court the planner may not answer for all read no pick (REQ-P2-03).
func test_the_pick_is_quiet_where_there_is_nothing_to_read() -> void:
	assert_true(MapPlayCivilianPick.picks(null, 0).is_empty(), "no session")
	var bare := PlaySession.new()
	assert_true(MapPlayCivilianPick.picks(bare, 0).is_empty(), "no civilian layer")
	bare.civilian_layer = CivilianLayer.new()
	assert_true(MapPlayCivilianPick.picks(bare, 0).is_empty(), "no ledger")
	var idle: PlaySession = _rival_economy_play()
	idle.ai_mode = AiControl.NOOP
	assert_true(MapPlayCivilianPick.picks(idle, 1).is_empty(), "no planner for this court")
	idle.civilian_layer.free()
	# A region with no plan contributes no words.
	var empty: Dictionary = {}
	MapPlayCivilianPick._words({}, 0, {}, null, empty)
	assert_true(empty.is_empty(), "an empty entry prints nothing")


func _pick_of(
	action: String, tile: Vector2i, model: MapModel, works: LandWorks
) -> Dictionary:
	var roster: Array[CivilianState] = [
		CivilianState.create(1, 0, "engineer", tile)
	]
	return MapPlayCivilianPick._order_pick(
		model, works, roster, 0, {}, CivilianFixture.stockpile(),
		{"capital_tile": CivilianFixture.BARE_TILE}, null,
		{"action": action, "tile": tile}
	)


# --- map phase wiring (MapPlayEconomyAi) ------------------------------------


## One rival court on a two-crown land world, its seat holding a worked grain
## tile: the fixture every `MapPlayEconomyAi` case in this section reads.
func _rival_economy_play() -> PlaySession:
	var world: WorldMap = AiFixture.land_world([0, 1], {0: true, 1: true})
	var model: MapModel = world.region(0)
	var grain := Vector2i(1, 1)
	model.resource[model.index_of(grain.x, grain.y)] = 4
	var layer := CivilianLayer.new()
	layer.spawn(model, 1, 0, [], false)
	layer.works.set_improvement(model, grain, 1)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.civilian_layer = layer
	play.map_seed = 1500
	play.ai = AiState.new()
	return play


func test_map_phase_resolves_rival_economies_and_civilian_work() -> void:
	var play: PlaySession = _rival_economy_play()
	var layer: CivilianLayer = play.civilian_layer
	var report: Dictionary = MapPlayEconomyAi.run(play)
	assert_true((report["factions"] as Dictionary).has(1))
	var entry: Dictionary = report["factions"][1]
	assert_true(int(entry["extraction"].get("grain", 0)) >= 6)
	assert_true(layer.unit_count_all(1) >= 3, "the rival musters its opening civilians")
	var seeded_civilians: Array = entry["civilians"]["orders"]
	assert_eq(layer.unit_count_all(0), 0, "the human court is never seeded")
	assert_false(
		seeded_civilians.is_empty(),
		"the rival engineer starts a legal work order"
	)
	for _turn in 3:
		MapPlayEconomyAi.run(play)
	assert_true(
		layer.unit_count_all(1) >= 4,
		"rival training keeps the opening staff and may hire for work"
	)
	layer.free()


## Each rival row files the whole economy report under `resolved`, and the
## research phase rides under its own `research` key — the slot the turn close's
## fort step, the Gazette's research report and the spy despatch read. A reader
## that takes `resolved` for the research report sees no finished study at all
## (wiki: siege-mechanics § Fort Levels; issue #919).
func test_map_phase_files_the_research_report_the_turn_close_reads() -> void:
	var play: PlaySession = _rival_economy_play()
	var report: Dictionary = MapPlayEconomyAi.run(play)
	var resolved: Dictionary = report["factions"][1]["resolved"]
	assert_true(resolved.has("research"), "the research phase is a key of the report")
	assert_true(
		(resolved["research"] as Dictionary).has("researched"),
		"the finished studies are filed inside the research phase"
	)
	assert_false(
		resolved.has("researched"),
		"and never at the economy report's top level, where the fort step looked"
	)
	play.civilian_layer.free()


## The economy pass reads the footing's market slot: a court at war bids only
## the rows its commitments claim, and the report names the top-up it withheld
## (DR-20261117-01).
func test_map_phase_a_court_at_war_opens_no_speculative_bid() -> void:
	var peace: PlaySession = _rival_economy_play()
	var open: Dictionary = MapPlayEconomyAi.run(peace)["factions"][1]["trade"]
	assert_eq(int((open["plan"] as Dictionary).get("held", 0)), 0, "at peace nothing is held")
	assert_eq(String(open.get("bids_blocked", "")), "", "and nothing is reported")
	peace.civilian_layer.free()
	var play: PlaySession = _rival_economy_play()
	play.diplomacy = _war_state(1, 0)
	var ledger: PlayerEconomy = play.ai.economy_for(1)
	for id: String in AiEconomyPlanner.BUILD_INPUTS:
		ledger.stockpile[id] = 0
	var trade: Dictionary = MapPlayEconomyAi.run(play)["factions"][1]["trade"]
	assert_true(
		int((trade["plan"] as Dictionary).get("held", 0)) > 0,
		"the war footing holds the unclaimed rows back"
	)
	assert_eq(
		String(trade.get("bids_blocked", "")), AiMarketPlanner.REASON_SPECULATE,
		"the report names the top-up the footing held shut"
	)
	play.civilian_layer.free()


## The phoney war holds no front (issue #995): a crown war past its grace with
## no attack on the enemy is the war the diplomacy pass is already eroding to
## its peace (#999), so the market's speculative top-up opens again while the
## peace leg ends it — the coin a silent front kept shut belongs to the bank's
## chest. A war being fought keeps the slot shut as published.
func test_a_phoney_war_opens_the_market_top_up_again() -> void:
	var window: int = AiConfig.build(1, 1500).parameter("diplomacy.pointless_window")
	# A war the court has fought and then abandoned: declared long ago, its last
	# attack even older, so the pointless read has fired many times over.
	var play: PlaySession = _rival_economy_play()
	play.diplomacy = _war_state(1, 0)
	play.turn = 100
	play.ai.note_war(1, 0, 1)
	var ledger: PlayerEconomy = play.ai.economy_for(1)
	for id: String in AiEconomyPlanner.BUILD_INPUTS:
		ledger.stockpile[id] = 0
	var trade: Dictionary = MapPlayEconomyAi.run(play)["factions"][1]["trade"]
	assert_eq(
		int((trade["plan"] as Dictionary).get("held", 0)), 0,
		"a phoney war holds no rows back"
	)
	assert_eq(
		String(trade.get("bids_blocked", "")), "",
		"the report claims no shut top-up for a war that takes nothing"
	)
	play.civilian_layer.free()
	# The same footing with a live front keeps the published hold: an attack
	# inside the window is a war being fought, and its coin is the front's.
	var fought: PlaySession = _rival_economy_play()
	fought.diplomacy = _war_state(1, 0)
	fought.turn = 100
	fought.ai.note_war(1, 0, 1)
	AiWarMemory.note_attack(fought.ai, 1, 0, 100 - window)
	var war_ledger: PlayerEconomy = fought.ai.economy_for(1)
	for id: String in AiEconomyPlanner.BUILD_INPUTS:
		war_ledger.stockpile[id] = 0
	var shut: Dictionary = MapPlayEconomyAi.run(fought)["factions"][1]["trade"]
	assert_true(
		int((shut["plan"] as Dictionary).get("held", 0)) > 0,
		"a war the court is still fighting holds the unclaimed rows back"
	)
	assert_eq(
		String(shut.get("bids_blocked", "")), AiMarketPlanner.REASON_SPECULATE,
		"the report names the top-up the live front held shut"
	)
	fought.civilian_layer.free()


## The bank's college ladder reads the chest, never the wobbling money goal
## (issue #995): the #603 valve re-routes the goal's own reserve to the cash
## floor while the fill stands still, and a ladder that falls with it burns
## the very fill the bank is holding for — measured 450 ducats on the one turn
## a big sale landed. The bank's floors read the canonical chest, so the
## ladder waits with the bank; the standing study keeps its #490 cash-floor
## gate either way, so a court parked at the floor still learns.
func test_a_banking_courts_college_reads_the_chest_not_the_wobble() -> void:
	var stalled: PlaySession = _rival_economy_play()
	var ledger: PlayerEconomy = stalled.ai.economy_for(1)
	ledger.treasury = 900
	# The #603 wobble: the muster aim has stood still two turns, so the goal's
	# own reserve re-routes to the cash floor — a ladder that reads it would
	# treat the 900-ducat purse as spendable above 500 (issue #995's probe
	# caught exactly this burn).
	stalled.ai.deferrals[1] = {
		"muster.line": {"turns": 2, "low": 0, "shortfall": {"ducats": 1}},
	}
	var report: Dictionary = MapPlayEconomyAi.run(stalled)["factions"][1]
	assert_eq(
		String((report["income"] as Dictionary).get("goal", "")),
		AiIncome.GOAL_SPEND,
		"the valve re-routed the wobbling goal to its floor"
	)
	var spent: int = int(
		((report["resolved"] as Dictionary).get("research", {}) as Dictionary).get(
			"spent", 0
		)
	)
	assert_true(
		spent <= 50,
		"the college waits with the bank — only the standing study may pay (%d ducats)" % spent
	)
	stalled.civilian_layer.free()



## The rival's court reads the crown's best town from the world and hands it to
## the planner and the phase alike: a village court is offered no second-stage
## row, and a court whose own province grows a level-2 town beats out cloth
## (wiki: production-recipes § Town-works gates; DR-20261116-04; REQ-P2-03).
func test_rival_court_runs_the_town_rows_its_works_open() -> void:
	var play: PlaySession = _rival_economy_play()
	var economy: PlayerEconomy = play.ai.economy_for(1)
	economy.stockpile = {"grain": 200, "fabric": 20, "refinedSugar": 20}
	economy.workers = WorkerPool.make(6)
	var village: Dictionary = MapPlayEconomyAi.run(play)["factions"][1]
	assert_eq(
		_units_for(village["production"], "garments"), 0,
		"a village has no works to beat out cloth"
	)
	# The rival's own province grows a level-2 town: the cloth row opens.
	var data: ProvinceState = play.world.region(0).province_data(1)
	data.town_development = 2
	var town: Dictionary = MapPlayEconomyAi.run(play)["factions"][1]
	assert_true(
		_units_for(town["production"], "garments") > 0,
		"the works open the cloth for the rival"
	)
	play.civilian_layer.free()


## A fleetless court on `earn` still manufactures: the old blunt skip froze
## every sawmill and forge for the whole save, so a court saving its yard chest
## could neither raise an estate nor fill the chest it was saving for. The rows
## the muster and the yard claim stand out of the plan's reach instead, and the
## court's own works keep the manufactures they pay for (issue #484, #878).
func test_a_fleetless_earning_court_still_manufactures() -> void:
	var play: PlaySession = _rival_economy_play()
	var economy: PlayerEconomy = play.ai.economy_for(1)
	economy.tech_unlocked["superior_hull_design"] = true
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	economy.treasury = 1000
	economy.stockpile = {"grain": 100, "timber": 12}
	economy.workers = WorkerPool.make(6)
	var court: MapPlayEconomyCourt = MapPlayEconomyCourt.open(
		play, 1, WorldMarket.with_default_prices()
	)
	court.plan_turn()
	assert_eq(
		String(court.income["goal"]), AiIncome.GOAL_EARN,
		"the yard chest puts the court on its money goal"
	)
	assert_true(
		_units_for(court.production, "lumber") > 0,
		"the court still saws the timber its works and yard pay for"
	)
	play.civilian_layer.free()


## The sale is staged after the works are priced: what a crew is about to spend
## is held back, so the court never sells its own workshop's timber (wiki:
## economy-planner § Reservations — one stockpile serves build, work and trade).
func test_the_rival_keeps_the_row_its_planned_works_will_spend() -> void:
	var probe_play: PlaySession = _rival_economy_play()
	var probe: Dictionary = MapPlayEconomyAi.run(probe_play)["factions"][1]["works_reserved"]
	probe_play.civilian_layer.free()
	assert_true(not probe.is_empty(), "a rival's planned works name their row")

	# Hold exactly the reserve and the row the works claim: the surplus is nil,
	# so not one unit of it may reach the market.
	var config: AiConfig = AiConfig.build(1, 1500)
	var keep: int = config.parameter("market.sell_reserve")
	var play: PlaySession = _rival_economy_play()
	var economy: PlayerEconomy = play.ai.economy_for(1)
	for commodity: Variant in probe.keys():
		var id: String = String(commodity)
		economy.stockpile[id] = keep + int(probe[id])
	var entry: Dictionary = MapPlayEconomyAi.run(play)["factions"][1]
	var held: Dictionary = entry["works_reserved"]
	var offered: Dictionary = {}
	for raw: Variant in (entry["trade"]["plan"] as Dictionary)["offers"]:
		var offer: Dictionary = raw
		offered[String(offer["commodity"])] = int(offer["quantity"])
	for commodity: Variant in held.keys():
		var id: String = String(commodity)
		assert_eq(
			int(offered.get(id, 0)), 0,
			"the works' %s never goes to market" % id
		)
	play.civilian_layer.free()


## The civilian pass owns the rival roster: one seed per court per region, and
## none where the court holds no capital (a colony or a foreign shore).
func test_civilian_pass_seeds_once_and_only_at_a_capital() -> void:
	var world: WorldMap = AiFixture.land_world([0, 1], {0: true, 1: true})
	var model: MapModel = world.region(0)
	var layer := CivilianLayer.new()
	layer.spawn(model, 1, 0, [], false)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.civilian_layer = layer

	MapPlayCivilianAi.seed(play, 1)
	var seeded: int = layer.unit_count_all(1)
	assert_eq(seeded, MapPlayCivilianAi.RIVAL_STARTING_CIVILIANS.size())
	MapPlayCivilianAi.seed(play, 1)
	assert_eq(layer.unit_count_all(1), seeded, "a second seed adds nothing")

	var landless: WorldMap = AiFixture.land_world([0, 1], {0: true})
	play.world = landless
	play.model = landless.region(0)
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.spawn(play.model, 1, 0, [], false)
	MapPlayCivilianAi.seed(play, 1)
	assert_eq(play.civilian_layer.unit_count_all(1), 0, "no capital, no muster")
	play.civilian_layer.free()
	layer.free()


## Guard rails on the civilian pass helpers: no tile without a model or
## province, no unit for a missing id, and training refuses an empty order.
func test_civilian_pass_helpers_refuse_empty_inputs() -> void:
	assert_eq(
		CivilianMuster.mustering_tile(null, -1, []),
		CivilianState.NO_TILE
	)
	assert_eq(CivilianMuster.unit_by_id([], 99), null)
	var play := PlaySession.new()
	play.world = AiFixture.land_world([0], {0: true})
	play.model = play.world.region(0)
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.spawn(play.model, 1, 0, [], false)
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.treasury = 100
	assert_true(
		CivilianMuster.train(
			play, play.model.region_id, [], 1, economy, {}, {"capital_province": 0}
		).is_empty(),
		"training with no type_id pays nothing"
	)
	play.civilian_layer.free()


## The muster seam's own refusals: no world, no home region, no squadron, no
## purse, and a province with no seat tile still musters at its first tile. An
## off-screen region stores the new unit in its table instead of the live layer.
func test_the_muster_seam_refuses_what_it_cannot_pay_for() -> void:
	var bare := PlaySession.new()
	assert_eq(
		CivilianMuster.muster_port(bare, 1, 0, null), CivilianState.NO_TILE,
		"no world, no harbour"
	)
	assert_false(CivilianMuster.has_free_squadron(bare, 0, 1), "no layer, no squadron")

	var world: WorldMap = AiFixture.land_world([1], {0: true})
	world.add_region(AiFixture.land_world([1], {0: true}).region(0))
	var play := PlaySession.new()
	play.world = world
	play.model = world.region(0)
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.spawn(play.model, 1, 0, [], false)
	assert_eq(
		CivilianMuster.muster_port(play, 1, WorldMap.NEW_WORLD, world.region(1)),
		CivilianState.NO_TILE,
		"a court musters only in its own region"
	)

	var ships := ShipLayer.new()
	ships.regions.set_region(0, [FleetState.at_sea(1, 2, 0)])
	play.ship_layer = ships
	assert_false(
		CivilianMuster.has_free_squadron(play, 0, 1), "another court's hull is no lift"
	)

	var poor: PlayerEconomy = PlayerEconomy.new()
	assert_true(
		CivilianMuster.train(
			play, 0, [], 1, poor, {"ok": true, "type_id": "builder"},
			{"capital_province": 0}
		).is_empty(),
		"an empty purse raises nobody"
	)

	var rich: PlayerEconomy = PlayerEconomy.new()
	rich.treasury = 1000
	rich.add("paper", 10)
	var stored: Array[CivilianState] = []
	var next_id: int = play.civilian_layer.next_id
	var hired: Dictionary = CivilianMuster.train(
		play, WorldMap.NEW_WORLD, stored, 1, rich, {"ok": true, "type_id": "builder"},
		{"capital_province": 0}
	)
	assert_eq(String(hired.get("type_id", "")), "builder", "the off-screen muster pays")
	assert_eq(stored.size(), 1, "and lands in the region's own table")
	assert_eq(play.civilian_layer.next_id, next_id + 1, "through the layer's id counter")

	var seatless := MapModel.new()
	assert_eq(
		CivilianMuster.mustering_tile(seatless, 0, []), CivilianState.NO_TILE,
		"a province with no tiles musters nowhere"
	)
	ships.free()
	play.civilian_layer.free()


## A rival's colonial estate ships home on the same holds as the player's: no
## free tonnage from the other region (wiki: extraction-and-improvements
## § Flow to Stockpile; DR-20261109-17; REQ-P2-03).
func test_a_rival_ships_its_colony_only_on_its_home_holds() -> void:
	var world: WorldMap = AiFixture.land_world([0, 1], {0: true, 1: true})
	var colony := MapModel.new()
	colony.setup(2, 1)
	colony.province[colony.index_of(0, 0)] = 0
	colony.province[colony.index_of(1, 0)] = 0
	var tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var province := ProvinceState.create(0, "Colony", tiles, Vector2.ZERO, 2, 1)
	province.town_development = 4
	colony.provinces.append(province)
	colony.resource[colony.index_of(0, 0)] = 0
	colony.resource[colony.index_of(1, 0)] = 4
	world.add_region(colony)
	var layer := CivilianLayer.new()
	layer.spawn(world.region(WorldMap.OLD_WORLD), 1, 0, [], false)
	var works := LandWorks.new()
	works.add_port(colony, Vector2i(0, 0))
	works.set_improvement(colony, Vector2i(0, 0), 1)
	layer.works_regions.set_region(WorldMap.NEW_WORLD, works)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = world.region(WorldMap.OLD_WORLD)
	play.civilian_layer = layer
	var economy: PlayerEconomy = PlayerEconomy.starting()

	var without_holds: Dictionary = MapPlayEconomyLarder.overseas(play, 1, economy)["extraction"]
	assert_eq(_tons(without_holds), 5, "the rival's home yield needs no hold")
	assert_eq(int(MapPlayEconomyLarder.overseas(play, 1, economy)["extraction"]["grain"]), 5)

	var ships := ShipLayer.new()
	var home: FleetState = FleetState.in_port(
		1, 1, 1, ["a"], {"a": "fluyte"}
	)
	ships.regions.set_region(WorldMap.OLD_WORLD, [home] as Array[FleetState])
	play.ship_layer = ships
	var with_holds: Dictionary = MapPlayEconomyLarder.overseas(play, 1, economy)["extraction"]
	assert_eq(_tons(with_holds), 6, "one hold carries the colony's ton")

	# Hulls that wait at the colony quay are not the home fleet: the squadron that
	# carried them across has sailed, so the colony's ton stays ashore (wiki:
	# ships-and-naval § Cargo holds and capacity — "the home squadron's merchant
	# hulls are the only holds"; § Home Fleet — every other squadron is "at sea or
	# in port at non-capital owned provinces").
	var sorted: FleetState = FleetState.at_sea(2, 1, 0, ["b"], {"b": "fluyte"})
	var moored: FleetState = FleetState.in_port(3, 1, 0, ["c"], {"c": "fluyte"})
	ships.regions.set_region(WorldMap.OLD_WORLD, [sorted] as Array[FleetState])
	ships.regions.set_region(WorldMap.NEW_WORLD, [moored] as Array[FleetState])
	assert_eq(
		_tons(MapPlayEconomyLarder.overseas(play, 1, economy)["extraction"]), 5,
		"a colony quay is no home fleet"
	)
	ships.free()
	layer.free()


func _tons(totals: Dictionary) -> int:
	var total: int = 0
	for raw: Variant in totals.values():
		total += int(raw)
	return total


## A finished work, a rival's or the crown's own, stays off the despatch lane:
## the chart, the crew panel and the province sheet carry it (wiki: hud-toasts).
func test_rival_civilian_completion_stays_off_the_lane() -> void:
	var model: MapModel = CivilianFixture.build()
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [])
	var world := WorldMap.new()
	world.add_region(model)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.civilian_layer = layer
	play.hud = StubHud.new()
	add_child(play.hud)
	var explorer: CivilianState = CivilianState.create(
		7, 1, "explorer", CivilianFixture.RIVAL_GRAIN_TILE
	)
	explorer.start_work("explore", CivilianFixture.RIVAL_GRAIN_TILE, 1)
	layer.units.append(explorer)
	MapPlayCivilians.resolve_work(play)
	assert_false(explorer.is_working(), "the work still resolves")
	assert_true(play.hud.toasts.is_empty(), "Build/Work does not use the lane")
	var own: CivilianState = CivilianState.create(
		8, 0, "explorer", CivilianFixture.BARE_TILE
	)
	own.start_work("explore", CivilianFixture.BARE_TILE, 1)
	layer.units.append(own)
	MapPlayCivilians.resolve_work(play)
	assert_false(own.is_working(), "the crown's own work resolves too")
	assert_true(play.hud.toasts.is_empty(), "and still says nothing on the lane")
	layer.free()


func test_map_phase_gives_diplomacy_the_rival_stockpiles() -> void:
	var play := PlaySession.new()
	play.world = AiFixture.world([2, 2, 2, 2, 1])
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	play.diplomacy.ensure_relation(1, 2, 1)
	play.map_seed = 1500
	MapPlayDiplomacyAi.run(play)
	assert_not_null(play.ai)
	assert_true(play.ai.economies.has(1))
	assert_false(play.ai.economy_for(1).stockpile.is_empty())


func _civilian_context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": CivilianFixture.BARE_TILE,
		"at_war": at_war,
	}


# --- from test_ai_research.gd ------------------------------------------------
## Rival research policy (wiki: ai-architecture § Research planner,
## research-state, tech-tree): scoring, funding, slot filling, and the shared
## ResearchTurn actually advancing a rival's tree.


func _research_config(weights: Dictionary = {}) -> AiConfig:
	var config := AiConfig.new()
	config.faction = 3
	config.profile = AiProfile.NORMAL
	var merged: Dictionary = {
		"economy": 2, "military": 2, "diplomacy": 2, "research": 2,
	}
	merged.merge(weights, true)
	config.personality = {"weights": merged}
	config.agenda_traits = {}
	return config


func _has_tech(candidates: Array[Dictionary], tech_id: String) -> bool:
	for entry: Dictionary in candidates:
		if String(entry["tech"]) == tech_id:
			return true
	return false


func test_a_fresh_court_fills_every_slot_at_medium_funding() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var plan: Dictionary = AiResearchPlanner.plan(_research_config(), economy)
	var assignments: Array[Dictionary] = plan["assignments"]
	assert_eq(assignments.size(), ResearchState.DEFAULT_SLOTS)
	for entry: Dictionary in assignments:
		assert_eq(String(entry["funding"]), "medium")
		assert_eq(economy.research.tech_at(int(entry["slot"])), String(entry["tech"]))


func test_the_tech_thief_pays_a_step_more_for_its_catch_up() -> void:
	# tech_thief is the only agenda that carries a research step (wiki:
	# hidden-agendas — tech catch-up posture; DR-20261111-27).
	var plain: AiConfig = _research_config()
	var thief: AiConfig = _research_config()
	thief.agenda_traits = AiAgenda.resolve(AiAgenda.TECH_THIEF)
	var index: int = ResearchFunding.ORDER.find(AiResearchPlanner.funding_for(plain))
	assert_eq(
		ResearchFunding.ORDER.find(AiResearchPlanner.funding_for(thief)),
		index + 1,
		"one funding step above the published preset"
	)
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var plan: Dictionary = AiResearchPlanner.plan(thief, economy)
	for entry: Dictionary in plan["assignments"]:
		assert_eq(String(entry["funding"]), AiResearchPlanner.funding_for(thief))


func test_occupied_research_slots_are_left_alone() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(economy.research.assign("crop_rotation", "low", 0)["ok"]))
	var plan: Dictionary = AiResearchPlanner.plan(_research_config(), economy)
	var assignments: Array[Dictionary] = plan["assignments"]
	assert_eq(assignments.size(), 2)
	for entry: Dictionary in assignments:
		assert_true(int(entry["slot"]) != 0)


func test_replanning_keeps_the_same_candidates() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var config: AiConfig = _research_config()
	var before: Dictionary = AiResearchPlanner.plan(config, economy)
	var second: Dictionary = AiResearchPlanner.plan(config, economy)
	assert_eq(before["candidates"], second["candidates"])
	assert_eq(second["assignments"], [] as Array[Dictionary], "no empty slots left")


func test_a_commodity_shortfall_raises_the_tech_that_caps_it() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var config: AiConfig = _research_config()
	economy.stockpile["timber"] = 0
	var saw: int = AiResearchScores.score_for(config, economy, "saw_mill", false)
	var crop: int = AiResearchScores.score_for(config, economy, "crop_rotation", false)
	assert_true(saw > crop, "timber cap beats a tech with no cap")


func test_war_adds_the_registry_bonus_to_military_and_naval_tech() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var config: AiConfig = _research_config()
	var peace: int = AiResearchScores.score_for(
		config, economy, "organised_regiments", false
	)
	var war: int = AiResearchScores.score_for(
		config, economy, "organised_regiments", true
	)
	assert_eq(war - peace, config.parameter("research.war_bonus"))
	var gathering: int = AiResearchScores.score_for(
		config, economy, "crop_rotation", true
	)
	assert_eq(
		gathering,
		AiResearchScores.score_for(config, economy, "crop_rotation", false),
		"war never speeds the counting house"
	)


## The door the court walked up to is a gate, not a preference: the study that
## opens the next link of a chain with a charted Tribe is taken first, and the
## ordinary ranking stands when there is no door (DR-20261114-05).
func test_the_door_the_court_walked_up_to_is_studied_first() -> void:
	var config: AiConfig = _research_config()
	var plan: Dictionary = AiResearchPlanner.plan(
		config, PlayerEconomy.starting(), {"door": "diplomatic_expertise"}
	)
	assert_false(plan["assignments"].is_empty(), "the court has a slot to fill")
	assert_eq(
		String(plan["assignments"][0]["tech"]), "diplomatic_expertise",
		"the door is taken first"
	)
	var plain: Dictionary = AiResearchPlanner.plan(config, PlayerEconomy.starting())
	assert_ne(
		String(plain["assignments"][0]["tech"]), "diplomatic_expertise",
		"without a door the ordinary ranking stands"
	)


## Issue #1126: while the yard banks for a hull, the study ladder prices its
## preset for the whole slot row — three slots at Low took 150 ducats from a
## chest that had 66 spare, and the hull the court had saved for never left the
## slip. Every other court keeps the published single-slot ladder.
func test_the_ladder_prices_the_whole_slot_row() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = _purse(5566)
	assert_eq(economy.research.slots.size(), 3, "the fixture's slot row")
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy,
		{
			"treasury_floor": 5500, "cash_floor": 500, "defer_standing": true,
			"navy_reserve": 5500,
		}
	)
	assert_false(plan["assignments"].is_empty(), "the slots are still planned")
	var paid: int = 0
	for row: Dictionary in plan["assignments"]:
		paid += ResearchFunding.gold(String(row["funding"]))
	assert_true(paid <= 66, "the row never pays more ducats than the spare")

	# A court still filling the chest keeps the published ladder, so the door
	# that opens the hull is never held back by the chest it is saving for.
	var filling: PlayerEconomy = _purse(5400)
	var early: Dictionary = AiResearchPlanner.plan(
		config, filling,
		{
			"treasury_floor": 4500, "cash_floor": 500, "defer_standing": true,
			"navy_reserve": 5500,
		}
	)
	var early_paid: int = 0
	for row: Dictionary in early["assignments"]:
		early_paid += ResearchFunding.gold(String(row["funding"]))
	assert_true(early_paid > 66, "the saving court still studies as published")


## Issue #1126: the row-priced ladder is the hull chest's reading only — a court
## that banks nothing keeps the published single-slot preset.
func test_other_courts_keep_the_single_slot_ladder() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = _purse(5566)
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy,
		{"treasury_floor": 5500, "cash_floor": 500, "defer_standing": true}
	)
	var paid: int = 0
	for row: Dictionary in plan["assignments"]:
		paid += ResearchFunding.gold(String(row["funding"]))
	assert_eq(paid, 150, "three slots at the single-slot preset, as published")


## Issue #484: while the navy chest is the money-goal reserve, the standing
## study must not drip 50 ducats a turn — that income has to reach the yard.
func test_a_navy_chest_defers_the_standing_study() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = _purse(400)
	# An empty slot + a purse parked under the surplus ladder: without deferral
	# the standing study still fills it at the cheapest preset (#490).
	var without: Dictionary = AiResearchPlanner.plan(
		config, economy, {"treasury_floor": 5500, "cash_floor": 500}
	)
	assert_false(without["assignments"].is_empty(), "standing study fills a slot")
	assert_eq(
		String(without["assignments"][0]["funding"]),
		AiResearchPlanner.STANDING_FUNDING
	)
	var with_hull: Dictionary = AiResearchPlanner.plan(
		config, economy, {
			"treasury_floor": 5500, "cash_floor": 500, "defer_standing": true
		}
	)
	assert_true(
		with_hull["assignments"].is_empty(),
		"the navy chest pays no standing study — every ducat waits for the yard"
	)


## Issue #484: a due navy that cannot yet lay a hull studies the unlock first —
## the same door pattern a Tribe chain uses, so the chest fills for a hull the
## yard will actually accept.
func test_a_due_navy_studies_the_unlock_before_other_branches() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var door: String = AiNavy.unlock_tech(economy)
	assert_eq(door, "superior_hull_design", "the first door on the path to a sloop")
	var plan: Dictionary = AiResearchPlanner.plan(config, economy, {"door": door})
	assert_false(plan["assignments"].is_empty())
	assert_eq(
		String(plan["assignments"][0]["tech"]), door,
		"the navy door is taken first"
	)
	economy.tech_unlocked[door] = true
	assert_eq(AiNavy.unlock_tech(economy), ShipEconomy.tech_for("sloop"))
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	assert_eq(AiNavy.unlock_tech(economy), "", "open, so no navy door remains")


func test_research_personality_weights_steer_the_branch() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var soldier: AiConfig = _research_config({"military": 3, "economy": 1})
	var trader: AiConfig = _research_config({"military": 1, "economy": 3})
	assert_true(
		AiResearchScores.score_for(soldier, economy, "organised_regiments", false)
		> AiResearchScores.score_for(soldier, economy, "crop_rotation", false)
	)
	assert_true(
		AiResearchScores.score_for(trader, economy, "crop_rotation", false)
		> AiResearchScores.score_for(trader, economy, "organised_regiments", false)
	)


func test_techs_already_at_their_cap_are_not_candidates() -> void:
	assert_false(
		AiResearchScores.can_teach("saw_mill", {"saw_mill": true}),
		"a cap already granted teaches nothing"
	)
	assert_true(AiResearchScores.can_teach("saw_mill", {}))
	assert_true(AiResearchScores.can_teach("printing_press", {}))


## The scoring home ranks the college and lifts the door's study; the pick
## loop asks it for one row and walks past what it has already taken.
func test_the_scoring_home_ranks_the_college_and_picks_one_row() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var config: AiConfig = _research_config()
	var ranked: Array[Dictionary] = AiResearchScores.candidates(config, economy, false)
	assert_gt(ranked.size(), 1, "a fresh court can open several studies")
	for index in range(1, ranked.size()):
		assert_true(
			int(ranked[index - 1]["score"]) >= int(ranked[index]["score"]),
			"the ranking never puts a weaker study ahead"
		)
	var door: String = String(ranked[ranked.size() - 1]["tech"])
	var lifted: Array[Dictionary] = AiResearchScores.candidates(
		config, economy, false, door
	)
	assert_eq(String(lifted[0]["tech"]), door, "the door's study takes the head")
	var best: Dictionary = AiResearchScores.pick(config, economy, false)
	assert_eq(
		String(best["tech"]), String(ranked[0]["tech"]),
		"the best-ranked study is the first pick"
	)
	var taken: Dictionary = {door: true}
	var next: Dictionary = AiResearchScores.pick(config, economy, true, door, taken)
	assert_eq(
		String(next["tech"]), String(ranked[0]["tech"]),
		"a taken door falls back to the ranked head"
	)


func test_discovery_techs_wait_for_an_explorer() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var config: AiConfig = _research_config()
	var plan: Dictionary = AiResearchPlanner.plan(config, economy)
	assert_false(_has_tech(plan["candidates"], "discovery_of_sugar"))
	economy.research.set_revealed({"sugarCane": true})
	plan = AiResearchPlanner.plan(config, economy)
	assert_true(_has_tech(plan["candidates"], "discovery_of_sugar"))


func test_planned_slots_actually_research_through_the_shared_turn() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var plan: Dictionary = AiResearchPlanner.plan(_research_config(), economy)
	var slot: int = int((plan["assignments"] as Array)[0]["slot"])
	var tech: String = String((plan["assignments"] as Array)[0]["tech"])
	# Plenty of gold so the other two slots never starve the one under test.
	economy.treasury = 20000
	var turns: int = ceili(float(TechCatalog.cost(tech)) / 300.0)
	var market: WorldMarket = WorldMarket.with_default_prices()
	for _turn in turns:
		EconomyTurn.resolve(economy, market, {}, 0)
	assert_eq(economy.research.tech_at(slot), ResearchState.EMPTY_TECH)
	assert_true(economy.research.is_unlocked(tech), "medium funding buys the tech")


func test_a_null_court_plans_no_research() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(
		AiResearchPlanner.plan(null, economy)["assignments"], [] as Array[Dictionary]
	)
	assert_eq(
		AiResearchPlanner.plan(_research_config(), null)["assignments"],
		[] as Array[Dictionary]
	)


func test_the_research_funding_knob_reads_the_registry() -> void:
	assert_eq(AiResearchPlanner.funding_for(_research_config()), "medium")
	assert_eq(AiResearchPlanner.funding_for(_research_config({"research": 3})), "high")
	assert_eq(AiResearchPlanner.funding_for(_research_config({"research": 1})), "low")
	assert_eq(AiParameterRegistry.default_of("research.funding_index"), 2)
	assert_true(
		AiParameterRegistry.validate({"research.funding_index": 5}).get("ok", false) == false
	)


func test_research_funding_steps_down_to_what_the_purse_can_carry() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 2500
	assert_eq(AiResearchPlanner.funding_for(config, economy), "medium")
	economy.treasury = 100
	assert_eq(AiResearchPlanner.funding_for(config, economy), "low", "150 does not fit")
	economy.treasury = 20
	assert_eq(AiResearchPlanner.funding_for(config, economy), "none", "50 does not fit")
	assert_eq(AiResearchPlanner.funding_for(config), "medium", "no purse, published preset")


func test_research_funding_never_spends_the_reserve_the_court_must_hold() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 2000
	assert_eq(AiResearchPlanner.funding_for(config, economy, 1000), "medium")
	assert_eq(
		AiResearchPlanner.funding_for(config, economy, 1860), "low",
		"140 spare pays the low preset, not the published medium"
	)
	assert_eq(
		AiResearchPlanner.funding_for(config, economy, 1960), "none",
		"the floor is not research's to spend"
	)


func test_a_court_saving_for_its_muster_pays_only_the_standing_study() -> void:
	# The muster needs army.min_treasury (200) after the line's own price, so a
	# court still short of that floor pays no published preset into its slots.
	# The standing study — one slot at the cheapest preset — is the exception
	# that keeps a war-time court learning (issue #490).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 2100
	var floor: int = AiArmyReinforce.muster_floor(config, economy, 1, true)
	var cash: int = AiResearchPlanner.research_floor(config)
	assert_eq(floor, 2200, "200 kept + 2,000 peasant levies")
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy, {"treasury_floor": floor, "cash_floor": cash}
	)
	var paid: int = 0
	for entry: Dictionary in plan["assignments"]:
		if String(entry["funding"]) == "none":
			continue
		paid += 1
		assert_eq(String(entry["funding"]), "low", "only the standing study is paid")
	assert_eq(paid, 1, "one standing study, the war chest stays whole")
	# Parked at the cash floor while the muster is still open: the surplus ladder
	# stays at none, but the standing study still pays (issue #490).
	economy.treasury = 500
	AiResearchPlanner.plan(
		config, economy, {"treasury_floor": floor, "cash_floor": cash}
	)
	var funded: int = 0
	for slot in economy.research.slots.size():
		if economy.research.funding_at(slot) == "none":
			continue
		funded += 1
		assert_eq(economy.research.funding_at(slot), "low")
	assert_eq(funded, 1, "a war chest at the cash floor still studies")
	economy.treasury = 4000
	AiResearchPlanner.plan(
		config, economy, {"treasury_floor": floor, "cash_floor": cash}
	)
	for slot in economy.research.slots.size():
		assert_eq(
			economy.research.funding_at(slot), "medium", "surplus funds the study"
		)


func test_the_research_floor_is_the_cash_floor_not_the_muster_reserve() -> void:
	# The muster reserve is a saving target the army planner enforces at muster
	# time; a study paid against it never happens, because the war chest is never
	# reached (issue #490).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(
		AiResearchPlanner.research_floor(config),
		maxi(int(config.parameter("economy.min_treasury")), 0)
	)
	assert_true(
		AiResearchPlanner.research_floor(config)
			< AiArmyReinforce.muster_floor(config, economy, 1, true),
		"research never waits on the muster"
	)
	assert_eq(AiResearchPlanner.research_floor(null), 0)


func test_a_court_parked_at_its_floor_keeps_one_standing_study() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 500
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy, {"treasury_floor": AiResearchPlanner.research_floor(config)}
	)
	var paid: Array[String] = []
	for entry: Dictionary in plan["assignments"]:
		var funding: String = String(entry["funding"])
		if funding != "none":
			paid.append(funding)
	assert_eq(paid, ["low"] as Array[String], "one slot at the cheapest preset")
	assert_eq(
		economy.research.funding_at(0), "low",
		"the standing study is the first occupied slot"
	)
	for slot in range(1, economy.research.slots.size()):
		assert_eq(economy.research.funding_at(slot), "none", "the rest wait")


## The standing slot carries the ration ladder (issue #1059): a court banking
## for its army moves the cheapest unfinished grain/meat cap study it already
## holds onto the standing slot, so the farms outgrow the mouths while the
## purse sits behind the chest — the food the host eats rides the one preset
## that may dip into the chest (the same provision clause the farm trim and
## the farmhand hire ride).
func test_a_banking_court_studies_the_ration_estates_on_the_standing_slot() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 500
	economy.research.assign("land_enclosure")
	economy.research.assign("saw_mill")
	economy.research.add_progress("land_enclosure", 1100)
	assert_eq(economy.research.tech_at(0), "land_enclosure")
	# The published pick puts a non-ration study first; the planner re-picks
	# each turn, so simulate the shape the probe caught: the ration study
	# parked at `none` on a later slot while a military pick rides the purse.
	_swap_slots(economy.research, 1, 0)
	assert_eq(economy.research.tech_at(0), "saw_mill")
	economy.research.set_funding(0, "low")
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy,
		{
			"treasury_floor": AiArmyReinforce.muster_floor(config, economy, 1, true),
			"cash_floor": AiResearchPlanner.research_floor(config),
			"conquest_bank": true,
		}
	)
	assert_eq(
		economy.research.tech_at(0), "land_enclosure",
		"the ration study rides the standing slot"
	)
	assert_eq(economy.research.funding_at(0), "low", "the standing preset pays it")
	assert_eq(
		economy.research.tech_at(1), "saw_mill",
		"the displaced study keeps its slot and its progress"
	)
	# A cap the techs already lift reads no lift: the study the court holds
	# stays put (the ladder seeds the standing slot; it never evicts).
	economy.tech_unlocked["land_enclosure"] = true
	AiResearchPlanner.plan(
		config, economy,
		{
			"treasury_floor": AiArmyReinforce.muster_floor(config, economy, 1, true),
			"cash_floor": AiResearchPlanner.research_floor(config),
			"conquest_bank": true,
		}
	)
	assert_eq(
		economy.research.tech_at(0), "land_enclosure",
		"the granted cap stops the lift; no study is evicted"
	)


## A court not banking keeps the published pick: the standing study stays
## whatever the planner seeded, and the ration ladder waits for the bank.
func test_an_unbanked_court_keeps_the_published_standing_pick() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 500
	economy.research.assign("land_enclosure")
	economy.research.assign("saw_mill")
	_swap_slots(economy.research, 1, 0)
	economy.research.set_funding(0, "low")
	AiResearchPlanner.plan(
		config, economy,
		{"treasury_floor": AiArmyReinforce.muster_floor(config, economy, 1, true)}
	)
	assert_eq(
		economy.research.tech_at(0), "saw_mill",
		"no bank, no ration ladder on the standing slot"
	)


func test_a_broke_court_keeps_no_standing_study() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 40
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy, {"treasury_floor": AiResearchPlanner.research_floor(config)}
	)
	for entry: Dictionary in plan["assignments"]:
		assert_eq(String(entry["funding"]), "none", "40 ducats pays nothing")


func test_the_standing_study_helper_reads_the_same_purse_as_the_planner() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 500
	assert_eq(AiResearchPlanner.standing_funding(config, economy), "low")
	economy.treasury = 40
	assert_eq(AiResearchPlanner.standing_funding(config, economy), "")
	economy.treasury = 3000
	assert_eq(
		AiResearchPlanner.standing_funding(config, economy), "",
		"the surplus preset pays; there is no standing study to price"
	)


func test_the_ledger_helper_prices_the_study_the_planner_pays() -> void:
	# The helper reads the same reserve the planner's ladder does: at war a
	# purse above half the cash floor but under the muster pays the standing
	# study, and the ledger must price it, not read a 0-gold row (issue #590).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var muster: int = AiArmyReinforce.muster_floor(config, economy, 1, true)
	economy.treasury = 600
	assert_true(muster > 600, "600 sits under the war chest")
	assert_eq(
		AiResearchPlanner.standing_funding(config, economy, muster), "low",
		"the standing study the planner pays is the one the ledger prices"
	)


func test_the_refusal_names_the_bar_a_broke_court_cannot_clear() -> void:
	# The ledger's blocked reading for a study the planner will not pay (#590).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var muster: int = AiArmyReinforce.muster_floor(config, economy, 1, true)

	economy.treasury = 40
	assert_eq(
		AiResearchPlanner.standing_refusal(config, economy, muster),
		"purse under half the cash floor",
		"under half the floor no study is paid"
	)
	economy.treasury = muster - 1
	assert_eq(
		AiResearchPlanner.standing_refusal(config, economy, muster),
		"saving for its reserve",
		"the last payment of a war chest stays in it"
	)
	economy.treasury = 3000
	assert_eq(
		AiResearchPlanner.standing_refusal(config, economy, muster), "",
		"the surplus ladder pays; there is no refusal to name"
	)


func test_the_standing_study_stops_at_half_the_floor() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 299
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy, {"treasury_floor": 500}
	)
	for entry: Dictionary in plan["assignments"]:
		assert_eq(
			String(entry["funding"]), "none",
			"below half the cash floor nothing is paid"
		)
	economy.treasury = 300
	plan = AiResearchPlanner.plan(config, economy, {"treasury_floor": 500})
	var funded: int = 0
	for slot in economy.research.slots.size():
		if economy.research.funding_at(slot) != "none":
			funded += 1
	assert_eq(funded, 1, "300 is the floor for the standing study")


func test_a_court_one_payment_short_of_its_muster_keeps_that_payment() -> void:
	# A court at war that holds all but one study payment of its muster must not
	# pay the study: the purse would sit one regiment short forever (issue #474).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var muster: int = AiArmyReinforce.muster_floor(config, economy, 1, true)
	assert_true(muster > 0, "a court at war under target saves for a muster")
	economy.treasury = muster - 1
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy,
		{
			"treasury_floor": muster,
			"cash_floor": AiResearchPlanner.research_floor(config),
		}
	)
	for entry: Dictionary in plan["assignments"]:
		assert_eq(
			String(entry["funding"]), "none",
			"the last payment stays in the war chest"
		)
	assert_eq(
		AiResearchPlanner.standing_funding(config, economy, muster), "",
		"the ledger prices no study the planner will not pay"
	)


func test_a_court_far_from_its_muster_still_learns() -> void:
	# The standing study survives for a court that cannot reach its muster yet:
	# only the last payment is protected (issue #490, #474).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var muster: int = AiArmyReinforce.muster_floor(config, economy, 1, true)
	economy.treasury = 500
	assert_true(
		economy.treasury
			< muster - ResearchFunding.gold(AiResearchPlanner.STANDING_FUNDING),
		"500 is far from the muster"
	)
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy,
		{
			"treasury_floor": muster,
			"cash_floor": AiResearchPlanner.research_floor(config),
		}
	)
	var paid: Array[String] = []
	for entry: Dictionary in plan["assignments"]:
		var funding: String = String(entry["funding"])
		if funding != "none":
			paid.append(funding)
	assert_eq(paid, ["low"] as Array[String], "one slot at the cheapest preset")
	assert_eq(AiResearchPlanner.standing_funding(config, economy, muster), "low")


func test_a_peaceful_court_keeps_its_standing_study() -> void:
	# At peace the reserve is the cash floor alone, so the guard never fires and
	# a court that is not fighting still learns (DR-20261113-22).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var floor: int = AiResearchPlanner.research_floor(config)
	economy.treasury = floor
	assert_eq(AiResearchPlanner.standing_funding(config, economy, floor), "low")


func test_the_standing_study_never_undercuts_a_published_preset() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	# 3,000 ducats clears the medium preset; the standing study must not demote
	# any slot to the cheapest preset when the purse carries the published one.
	var plan: Dictionary = AiResearchPlanner.plan(
		config, economy, {"treasury_floor": AiResearchPlanner.research_floor(config)}
	)
	for entry: Dictionary in plan["assignments"]:
		assert_eq(String(entry["funding"]), "medium")


func test_an_occupied_slot_follows_the_purse() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(economy.research.assign("crop_rotation", "high", 0)["ok"]))
	economy.treasury = 40
	AiResearchPlanner.plan(config, economy)
	assert_eq(
		economy.research.funding_at(0), "none",
		"an underway study is not paid from ducats the court does not have"
	)


func test_the_muster_floor_closes_at_target_and_without_workers() -> void:
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var target: int = config.parameter("army.regiment_target")
	assert_eq(
		AiArmyReinforce.muster_floor(config, economy, target, false), 0,
		"at peace and at target: nothing to save for"
	)
	assert_eq(
		AiArmyReinforce.muster_floor(config, economy, target - 1, true),
		2200,
		"under the war target: keep the price of the cheapest line"
	)
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	assert_eq(
		AiArmyReinforce.muster_floor(config, economy, 0, true), 0,
		"no peasant to spare: no muster to save for"
	)

# --- from test_ai_phase_rules.gd ---
## A rival court's war footing and its money goal.
## A rival court's war footing (wiki: phase-planner-architecture,
## phase-planner-dispatch § Playable slice; DR-20261113-15) and its money goal
## (wiki: ai-architecture § Money first; DR-20261113-19): the phase and goal each
## court reads before its planners run, and the dispatches they open — no new
## colonisation voyage on a war footing unless the court is on earn, and a white
## peace taken by a court that fights two fronts.


const PHASE_OWNER: int = 0
const PHASE_RIVAL: int = 1
const PHASE_THIRD: int = 2
const PHASE_MINOR: int = 6
const PHASE_SEED: int = 1500


func _phase_config(faction: int = PHASE_OWNER) -> AiConfig:
	return AiConfig.build(faction, PHASE_SEED)


func _phase_court() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(PHASE_OWNER, PHASE_RIVAL, 1)
	state.ensure_relation(PHASE_OWNER, PHASE_THIRD, 1)
	return state


func _phase_war(state: DiplomacyState, target: int) -> void:
	assert_true(bool(DiplomacyRules.declare_war(state, PHASE_OWNER, target)["ok"]))


# --- phase selection ---------------------------------------------------------


func test_a_court_at_peace_reads_the_published_behaviour() -> void:
	var plan: Dictionary = AiPhasePlanner.plan(_phase_config(), _phase_court())

	assert_eq(String(plan["phase"]), AiPhasePlanner.PHASE_PEACE)
	assert_eq(AiPhasePlanner.label(String(plan["phase"])), "at peace")
	assert_eq(int(plan["factors"]["great_power_wars"]), 0)
	assert_false(AiPhasePlanner.is_war_footing(AiPhasePlanner.PHASE_PEACE))
	assert_false(AiPhasePlanner.takes_any_peace(AiPhasePlanner.PHASE_PEACE))


func test_one_great_power_war_is_a_war_footing() -> void:
	var state: DiplomacyState = _phase_court()
	_phase_war(state, PHASE_RIVAL)
	var plan: Dictionary = AiPhasePlanner.plan(_phase_config(), state)

	assert_eq(String(plan["phase"]), AiPhasePlanner.PHASE_WAR)
	assert_eq(AiPhasePlanner.label(String(plan["phase"])), "at war")
	assert_eq(int(plan["factors"]["great_power_wars"]), 1)
	assert_true(AiPhasePlanner.is_war_footing(String(plan["phase"])))
	assert_false(AiPhasePlanner.takes_any_peace(String(plan["phase"])))


func test_two_great_power_wars_are_an_overstretched_court() -> void:
	var state: DiplomacyState = _phase_court()
	_phase_war(state, PHASE_RIVAL)
	_phase_war(state, PHASE_THIRD)
	var plan: Dictionary = AiPhasePlanner.plan(_phase_config(), state)

	assert_eq(String(plan["phase"]), AiPhasePlanner.PHASE_FRONTS)
	assert_eq(AiPhasePlanner.label(String(plan["phase"])), "overstretched")
	assert_eq(int(plan["factors"]["great_power_wars"]), 2)
	assert_true(AiPhasePlanner.is_war_footing(String(plan["phase"])))
	assert_true(AiPhasePlanner.takes_any_peace(String(plan["phase"])))


func test_the_front_threshold_is_a_registry_knob() -> void:
	var state: DiplomacyState = _phase_court()
	_phase_war(state, PHASE_RIVAL)

	assert_eq(AiParameterRegistry.default_of("phase.overstretch_fronts"), 2)
	assert_eq(
		String(AiPhasePlanner.phase_for(_phase_config(), state)),
		AiPhasePlanner.PHASE_WAR,
		"one war is under the published threshold"
	)
	assert_eq(
		AiParameterRegistry.resolve(
			"phase.overstretch_fronts", {"phase.overstretch_fronts": 1}
		),
		1,
		"a profile may tighten the threshold to a single front"
	)
	assert_false(
		bool(AiParameterRegistry.validate({"phase.overstretch_fronts": 0})["ok"]),
		"no court is overstretched at zero fronts"
	)
	assert_false(
		bool(AiParameterRegistry.validate({"phase.overstretch_fronts": 7})["ok"]),
		"the catalog holds at most six Great Power rivals"
	)


func test_a_colonial_war_leaves_the_court_at_peace() -> void:
	var state: DiplomacyState = _phase_court()
	var minor: DiplomacyRelation = state.ensure_relation(PHASE_OWNER, PHASE_MINOR, 1)
	minor.at_war = true

	assert_eq(
		String(AiPhasePlanner.phase_for(_phase_config(), state)),
		AiPhasePlanner.PHASE_PEACE,
		"a war on a Minor Nation is colonial business, not a fleet war"
	)
	assert_eq(AiPhasePlanner.great_power_wars(state, PHASE_OWNER), 0)


func test_null_inputs_conclude_nothing() -> void:
	assert_eq(
		String(AiPhasePlanner.phase_for(null, _phase_court())), AiPhasePlanner.PHASE_UNKNOWN
	)
	assert_eq(
		String(AiPhasePlanner.phase_for(_phase_config(), null)), AiPhasePlanner.PHASE_UNKNOWN
	)
	assert_eq(AiPhasePlanner.label(AiPhasePlanner.PHASE_UNKNOWN), "—")
	assert_false(AiPhasePlanner.is_war_footing(AiPhasePlanner.PHASE_UNKNOWN))


func test_the_same_state_reads_the_same_footing() -> void:
	var first: Dictionary = AiPhasePlanner.plan(_phase_config(), _phase_court())
	var second: Dictionary = AiPhasePlanner.plan(_phase_config(), _phase_court())

	assert_eq(first, second, "replay-safe: the footing is a pure function")


# --- dispatch: an overstretched court opens no third front -------------------


const PHASE_OTHER: int = 3


## A court at `wars` Great Power fronts beside a crown next door. `peer` puts that
## crown on the court's own power score — a war it could not count on winning —
## while without it the neighbour is the weak one every planner prefers.
## `colonial` adds a Minor Nation next door; `posted` hands the footing in with
## the reading, and a caller that hands in none must read the same footing.
func _front_turn(
	wars: int, peer: bool = false, colonial: bool = false, posted: bool = true,
	powers: bool = true
) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(1)
	var neighbours: Array[int] = [PHASE_RIVAL, PHASE_THIRD, PHASE_OTHER]
	if colonial:
		neighbours.append(PHASE_MINOR)
	for other: int in neighbours:
		state.ensure_relation(PHASE_OWNER, other, 1)
		state.relation(PHASE_OWNER, other).score = 10.0
	for index in wars:
		_phase_war(state, [PHASE_RIVAL, PHASE_THIRD][index])
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var posture: String = AiPhasePlanner.phase_for(config, state)
	var theirs: int = 4 if peer else 1
	var context: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_OTHER: theirs, PHASE_MINOR: 1},
		"regiments": {PHASE_OWNER: 4, PHASE_OTHER: theirs, PHASE_MINOR: 1},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
	}
	if posted:
		context["posture"] = posture
	if not powers:
		context.erase("power")
		context.erase("regiments")
	var world: WorldMap = AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR])
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, AiState.new(), world, 1, context
	)
	return {"plan": plan, "posture": posture, "state": state, "world": world,
		"context": context, "config": config}


## The rival's gates have one home (AiDiplomacyGates): the planner's war and
## peace reads and the offers' pact break all ask it, so a footing, a cooldown
## or a claimed chain can never be read two ways.
func test_the_diplomacy_gates_know_a_pact_break_from_a_blocked_war() -> void:
	var run: Dictionary = _front_turn(2, true)
	var entry: Dictionary = _candidate(run["plan"], PHASE_OTHER)

	assert_eq(
		String(entry.get("blocked", "")), "overstretched: no third front",
		"a peer under an overstretched footing is the war gate's refusal"
	)
	var ranking: Dictionary = entry.get("offer", {})
	var pact: Dictionary = {}
	for candidate: Dictionary in ranking.get("candidates", []):
		if String(candidate.get("kind", "")) == AiDiplomacyOffers.KIND_BREAK_NAP:
			pact = candidate
	assert_false(pact.is_empty(), "the pact break is weighed for the peer")
	assert_false(bool(pact.get("ok", false)))


## The gates answer for a court with nothing to read: no config, no ledger, no
## line to save for. A caller that cannot read the purse keeps the published
## planner instead of inventing a buy-out (issue #975).
func test_the_gates_keep_the_published_planner_with_nothing_to_read() -> void:
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var ai_state := AiState.new()

	assert_false(AiDiplomacyGates.purse_under_muster(null, ai_state, {}))
	assert_false(AiDiplomacyGates.purse_under_muster(config, null, {}))
	assert_false(
		AiDiplomacyGates.purse_under_muster(config, ai_state, {}),
		"a court at target strength saves for no line"
	)
	assert_false(
		AiDiplomacyGates.buys_out(config, ai_state, PHASE_MINOR, {}, AiPhasePlanner.PHASE_WAR),
		"a Minor war is colonial business, never bought out"
	)
	assert_true(
		AiDiplomacyGates.buys_out(
			config, ai_state, PHASE_RIVAL, {}, AiPhasePlanner.PHASE_FRONTS
		),
		"an overstretched court takes any white peace it is offered"
	)
	assert_eq(AiDiplomacyGates.faction_of(null), MapModel.NO_ID)


## A court with a proposal already waiting for the human answers at the court
## queue, so it opens no second front this turn (DR-20261109-07). The refusal
## travels with the ranking, so the turn trace can print it.
func test_a_court_with_a_waiting_proposal_offers_nothing_new() -> void:
	_setup_ai_planner()
	ai_planner_state.human_faction = 1
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 70.0
	ai_planner_state.pending_offers.append(
		{"from": 0, "kind": DiplomacyProposals.KIND_FTP, "stage": "", "turn": 1}
	)
	assert_true(DiplomacyProposals.has_pending(ai_planner_state, 1))
	var ranking: Dictionary = AiDiplomacyOffers.best(
		ai_planner_config, ai_planner_state, ai_planner_ai_state,
		ai_planner_AiFixture.world([0, 1, 1]), 1, 1, 20,
		{"player": 1, "treasury": {0: 500}, "tech": {0: {}}}
	)
	assert_false(bool(ranking.get("ok", false)))
	assert_eq(
		String(ranking.get("blocked", "")),
		"the court is already considering a proposal"
	)
	assert_eq((ranking.get("candidates", []) as Array).size(), 1)


## The court's candidate row for one target in a decide() result.
func _candidate(plan: Dictionary, target: int) -> Dictionary:
	for raw: Variant in plan.get("candidates", []):
		var entry: Dictionary = raw
		if int(entry.get("target", -1)) == target:
			return entry
	return {}


func test_the_footing_opens_only_its_published_slots() -> void:
	assert_true(AiPhasePlanner.opens(AiPhasePlanner.PHASE_PEACE, AiPhasePlanner.SLOT_VOYAGE))
	assert_false(AiPhasePlanner.opens(AiPhasePlanner.PHASE_WAR, AiPhasePlanner.SLOT_VOYAGE))
	assert_false(AiPhasePlanner.opens(AiPhasePlanner.PHASE_FRONTS, AiPhasePlanner.SLOT_VOYAGE))
	assert_true(AiPhasePlanner.opens(AiPhasePlanner.PHASE_PEACE, AiPhasePlanner.SLOT_DECLARE_WAR))
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_WAR, AiPhasePlanner.SLOT_DECLARE_WAR),
		"one front leaves the court free to open a second"
	)
	assert_false(AiPhasePlanner.opens(AiPhasePlanner.PHASE_FRONTS, AiPhasePlanner.SLOT_DECLARE_WAR))
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_UNKNOWN, AiPhasePlanner.SLOT_DECLARE_WAR),
		"a caller with no relations concludes nothing"
	)
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_FRONTS, "diplomacy.pact"),
		"a slot no footing names keeps the dispatch default"
	)
	# The Tribe chain is the third live slot: a Great Power war holds it shut,
	# and a caller with no relations concludes nothing (DR-20261116-11).
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_PEACE, AiPhasePlanner.SLOT_TRIBE_CHAIN)
	)
	assert_false(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_WAR, AiPhasePlanner.SLOT_TRIBE_CHAIN)
	)
	assert_false(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_FRONTS, AiPhasePlanner.SLOT_TRIBE_CHAIN)
	)
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_UNKNOWN, AiPhasePlanner.SLOT_TRIBE_CHAIN)
	)
	# The expansion crews are the fourth live slot: the same war footing that
	# shuts the voyage and the chain shuts the crews that serve them
	# (DR-20261116-15).
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_PEACE, AiPhasePlanner.SLOT_CREWS)
	)
	assert_false(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_WAR, AiPhasePlanner.SLOT_CREWS)
	)
	assert_false(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_FRONTS, AiPhasePlanner.SLOT_CREWS)
	)
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_UNKNOWN, AiPhasePlanner.SLOT_CREWS)
	)
	# The market's speculative top-up is the fifth live slot: the same war
	# footing that spends the coin on the front opens no top-up above the rows
	# the court's commitments already claim (DR-20261117-01).
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_PEACE, AiPhasePlanner.SLOT_MARKET)
	)
	assert_false(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_WAR, AiPhasePlanner.SLOT_MARKET)
	)
	assert_false(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_FRONTS, AiPhasePlanner.SLOT_MARKET)
	)
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_UNKNOWN, AiPhasePlanner.SLOT_MARKET)
	)
	# The naval mission is the sixth: only the overstretched footing shuts it,
	# because a court at one front still works the enemy's trade
	# (DR-20261117-01).
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_PEACE, AiPhasePlanner.SLOT_NAVAL)
	)
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_WAR, AiPhasePlanner.SLOT_NAVAL)
	)
	assert_false(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_FRONTS, AiPhasePlanner.SLOT_NAVAL)
	)
	assert_true(
		AiPhasePlanner.opens(AiPhasePlanner.PHASE_UNKNOWN, AiPhasePlanner.SLOT_NAVAL)
	)


## The trace reading: the slots a footing holds shut, in the table's own order.
func test_the_trace_names_the_slots_a_footing_holds_shut() -> void:
	assert_eq(
		",".join(AiPhasePlanner.closed_slots(AiPhasePlanner.PHASE_PEACE)), "",
		"a court at peace holds nothing shut"
	)
	assert_eq(
		",".join(AiPhasePlanner.closed_slots(AiPhasePlanner.PHASE_WAR)),
		"expansion.voyage,expansion.tribe_chain,expansion.crews,trade.market",
		"one front closes the voyage, the new chain, the crews and the top-up"
	)
	assert_eq(
		",".join(AiPhasePlanner.closed_slots(AiPhasePlanner.PHASE_FRONTS)),
		"expansion.voyage,diplomacy.declare_war,expansion.tribe_chain,"
		+ "expansion.crews,trade.market,navy.missions",
		"an overstretched court holds every named slot shut"
	)
	assert_eq(
		",".join(AiPhasePlanner.closed_slots(AiPhasePlanner.PHASE_UNKNOWN)), "",
		"a caller with no relations closes nothing"
	)


## A court at war opens no **new** Tribe chain: the coin and the envoy's one
## order belong to the front (DR-20261116-11).
func test_a_court_at_war_opens_no_new_tribe_chain() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, tribe, 1).score = 60.0
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var peace: Dictionary = AiTribeColony.ambition(
		state, world, null, 2, tribe, 5000, {}, AiPhasePlanner.PHASE_PEACE
	)
	assert_true(bool(peace["wanted"]), "at peace the chain is open")
	var war: Dictionary = AiTribeColony.ambition(
		state, world, null, 2, tribe, 5000, {}, AiPhasePlanner.PHASE_WAR
	)
	assert_false(bool(war["wanted"]), "a war footing opens no new chain")
	assert_eq(String(war["reason"]), AiTribeColony.REASON_WAR)
	assert_false(bool(war["held"]), "a chain never opened is no stake to keep")
	assert_true(
		AiTribeColony.best(
			state, world, null, 2, 5000, {}, AiPhasePlanner.PHASE_WAR
		).is_empty(),
		"the rank of wanted Tribes is empty on a war footing"
	)
	assert_eq(
		AiTribeColony.closed_reason(AiPhasePlanner.PHASE_WAR), AiTribeColony.REASON_WAR
	)
	assert_eq(AiTribeColony.closed_reason(AiPhasePlanner.PHASE_PEACE), "")
	# The claim reading is what the war gate asks: a footing is one turn's
	# choice, so a closed chain never frees the court to clear it by force.
	assert_true(
		bool(AiTribeColony.ambition(
			state, world, null, 2, tribe, 5000, {}, AiTribeColony.CLAIM_POSTURE
		)["wanted"]),
		"the claim on that Tribe outlives the footing"
	)


## A court at war hires no expansion crew: the Explorer charts the voyage the
## footing holds shut and the Merchant signs the deed the chain it holds shut
## points at, while the front's own staff stays open (DR-20261116-15).
func test_a_court_at_war_hires_no_expansion_crew() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var crews: Dictionary = _civilian_context()
	crews["staff_targets"] = {"builder": 0, "engineer": 0, "explorer": 1, "spy": 0}
	crews["phase"] = AiPhasePlanner.PHASE_PEACE
	var peace: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_true(bool(peace.get("ok", false)), "at peace the court hires its Explorer")
	assert_eq(String(peace["type_id"]), "explorer")
	crews["phase"] = AiPhasePlanner.PHASE_WAR
	var war: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_false(bool(war.get("ok", true)), "a war footing hires no new crew")
	assert_eq(String(war.get("reason", "")), AiCivilianHire.REASON_CREWS)
	# The Merchant is the other expansion crew: the deed it signs is the chain's.
	var deed: Dictionary = _civilian_context()
	deed["staff_targets"] = {
		"builder": 0, "engineer": 0, "explorer": 0, "spy": 0, "merchant": 1,
	}
	deed["tech_unlocked"] = {"merchant_companies": true}
	deed["phase"] = AiPhasePlanner.PHASE_PEACE
	assert_eq(
		String(AiCivilianHire.training_order(config, [], deed)["type_id"]),
		"merchant"
	)
	deed["phase"] = AiPhasePlanner.PHASE_FRONTS
	assert_eq(
		String(AiCivilianHire.training_order(config, [], deed).get("reason", "")),
		AiCivilianHire.REASON_CREWS
	)
	# The front's own staff stays open: the footing closes expansion, not the war.
	var front: Dictionary = _civilian_context()
	front["staff_targets"] = {"builder": 2, "engineer": 0, "explorer": 0, "spy": 0}
	front["phase"] = AiPhasePlanner.PHASE_WAR
	var builder: Dictionary = AiCivilianHire.training_order(config, [], front)
	assert_true(bool(builder.get("ok", false)), "a court at war still raises Builders")
	assert_eq(String(builder["type_id"]), "builder")
	# A caller with no footing (fixtures, the mainline planners) hires as published.
	var unaware: Dictionary = _civilian_context()
	unaware["staff_targets"] = {"builder": 0, "engineer": 0, "explorer": 1, "spy": 0}
	assert_eq(
		String(AiCivilianHire.training_order(config, [], unaware)["type_id"]),
		"explorer",
		"no footing read means the published hire order"
	)


## The stranded claim's own carve-out (issue #1139): the voyage the court paid
## for is ashore with no crown land, and its claim still has a step — the
## Merchant that voyage asks for (#1127) is hired like a provision crew, at war
## or banked. The carve-out is per-claim: the crew the stranded claim asks for,
## not the whole expansion roster.
func test_a_stranded_claims_merchant_is_hired_at_war_and_banked() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var crews: Dictionary = _civilian_context()
	crews["staff_targets"] = {
		"builder": 0, "engineer": 0, "explorer": 0, "spy": 0, "merchant": 1,
	}
	crews["tech_unlocked"] = {"merchant_companies": true}
	crews["voyage_crew_kind"] = "merchant"
	crews["voyage_stranded"] = true
	crews["phase"] = AiPhasePlanner.PHASE_WAR
	var at_war: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_true(
		bool(at_war.get("ok", false)),
		"the stranded claim's Merchant is hired on a war footing"
	)
	assert_eq(String(at_war["type_id"]), "merchant")
	crews["conquest_bank"] = true
	var banked: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_true(
		bool(banked.get("ok", false)),
		"the stranded claim's Merchant is hired while the court banks"
	)
	assert_eq(String(banked["type_id"]), "merchant")
	# Per-claim, not per-roster: the same footing still shuts the Explorer the
	# claim does not ask for, and the bank still shuts the deed Merchant.
	crews["staff_targets"] = {
		"builder": 0, "engineer": 0, "explorer": 1, "spy": 0, "merchant": 0,
	}
	crews["conquest_bank"] = false
	var other: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_false(bool(other.get("ok", false)), "the roster's own crew stays shut")
	assert_eq(String(other.get("reason", "")), AiCivilianHire.REASON_CREWS)
	crews["voyage_crew_kind"] = ""
	var deed_merchant: Dictionary = _civilian_context()
	deed_merchant["staff_targets"] = {
		"builder": 0, "engineer": 0, "explorer": 0, "spy": 0, "merchant": 1,
	}
	deed_merchant["tech_unlocked"] = {"merchant_companies": true}
	deed_merchant["conquest_bank"] = true
	deed_merchant["phase"] = AiPhasePlanner.PHASE_PEACE
	var banked_deed: Dictionary = AiCivilianHire.training_order(
		config, [], deed_merchant
	)
	assert_eq(
		String(banked_deed.get("reason", "")), AiCivilianHire.REASON_BANK,
		"a deed Merchant without a stranded claim stands behind the chest"
	)


## The economy trace names the hire the footing held shut, so a court at war is
## never silent about the crew it did not take (REQ-P5-05; DR-20261116-15).
func test_the_trace_names_the_crew_a_war_footing_held_shut() -> void:
	var merged: Dictionary = {"events": []}
	var court: Dictionary = {"events": [], "actions": {}}
	AiEconomyTrace.record(
		merged, {2: court},
		{"factions": {2: {"civilians": {
			"orders": [], "training": [],
			"training_blocked": AiCivilianHire.REASON_CREWS,
		}}}}
	)
	var text: String = ""
	for entry: Variant in court["events"]:
		text = String(entry)
	assert_true(
		text.contains(AiCivilianHire.REASON_CREWS),
		"the trace names why the yard took no crew"
	)


## The economy trace names the crew a rival musters, and says when the court's
## own archetype asked for it rather than the region's work (REQ-P5-05;
## AiStaffTaste).
func test_the_trace_names_the_crew_a_court_musters() -> void:
	var merged: Dictionary = {"events": []}
	var court: Dictionary = {"events": [], "actions": {}}
	AiEconomyTrace.record(
		merged, {2: court},
		{"factions": {2: {"civilians": {"orders": [], "training": [
			{"type_id": "engineer", "unit": 1, "tile": Vector2i(0, 0), "taste": true},
		]}}}}
	)
	var text: String = ""
	for entry: Variant in court["events"]:
		text = String(entry)
	assert_true(text.contains("an Engineer"), "the trace names the crew it raised")
	assert_true(text.contains("the court's taste"), "and the archetype that asked for it")
	var plain: Dictionary = {"events": [], "actions": {}}
	AiEconomyTrace.record(
		merged, {2: plain},
		{"factions": {2: {"civilians": {"orders": [], "training": [
			{"type_id": "builder", "unit": 2, "tile": Vector2i(0, 0), "taste": false},
		]}}}}
	)
	text = ""
	for entry: Variant in plain["events"]:
		text = String(entry)
	assert_true(text.contains("a Builder"), "the region's own hire is named too")
	assert_false(text.contains("taste"), "nothing claims a taste that was not read")


## A court at war opens no speculative top-up: the coin and the holds belong to
## the front, so it bids only the rows this turn's commitments already claim,
## and food, which is never a speculative buy (DR-20261117-01).
func test_a_court_at_war_opens_no_speculative_bid() -> void:
	var economy: PlayerEconomy = _ai_market_economy({}, 5000)
	var market := WorldMarket.with_default_prices()
	var peace: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 20)
	assert_eq((peace["bids"] as Array).size(), 3, "at peace the court stocks its reserve")
	assert_eq(int(peace["held"]), 0, "nothing is held back at peace")
	# The war footing: no commitment claims a row, so nothing is bid.
	var war: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, market, 20, {}, {}, {}, 0, 0, false, false
	)
	assert_true((war["bids"] as Array).is_empty(), "a war footing opens no top-up")
	assert_eq(int(war["held"]), 6, "every unclaimed build input is held back")
	# The row the next regiment is provisioned with is claimed, so it is bought.
	var claimed: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, market, 20, {}, {"fabric": 5}, {}, 0, 0, false, false
	)
	assert_eq((claimed["bids"] as Array).size(), 1, "the muster's cloth is a commitment")
	assert_eq(String(claimed["bids"][0]["commodity"]), "fabric")
	assert_eq(int(claimed["held"]), 5, "the rest of the warehouse stays empty")
	# Food is never a speculative buy: a starving court still bids its dinner.
	var starving: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, market, 20, {}, {}, {}, 0, 6, false, false
	)
	assert_eq(String((starving["bids"] as Array)[0]["commodity"]), "grain")


## The crew the hire order would take is not the market's to spend: a court at
## its cash floor that has lost a Builder keeps that price back from its bids,
## in the ordinary purse and in the starving lock-recovery purse alike, so the
## food bid and the hire price never share one margin (issue #894).
func test_the_hire_margin_survives_the_food_bid() -> void:
	var market := WorldMarket.with_default_prices()
	var poor: PlayerEconomy = _ai_market_economy({}, 1200)
	var blind: Dictionary = AiMarketPlanner.plan(_ai_market_config(), poor, market, 20)
	assert_true(
		(blind["bids"] as Array).size() > 0, "the bids would otherwise spend the margin"
	)
	var kept: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), poor, market, 20, {}, {}, {}, 0, 0, false, true, -1, 1000
	)
	assert_true(
		(kept["bids"] as Array).is_empty(), "the Builder's price is held back"
	)
	# Lock-recovery bids the whole purse for food; the margin still survives.
	var hungry: PlayerEconomy = _ai_market_economy({}, 250)
	var dinner: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), hungry, market, 20, {}, {}, {}, 0, 6, false, true
	)
	var dinner_kept: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), hungry, market, 20, {}, {}, {}, 0, 6, false, true, -1, 100
	)
	var dinner_bid: Dictionary = (dinner["bids"] as Array)[0]
	var kept_bid: Dictionary = (dinner_kept["bids"] as Array)[0]
	assert_true(int(dinner_bid["quantity"]) > 0, "a starving court bids its dinner")
	assert_true(
		int(kept_bid["quantity"]) < int(dinner_bid["quantity"]),
		"the crew's price survives the food bid"
	)
	assert_true(
		int(kept_bid["quantity"]) * int(kept_bid["unit_price"]) <= 150,
		"the food bid spends only what the margin leaves"
	)


## A starving court whose next crew's price exceeds its whole purse bids the
## purse on food instead: with every hand down it earns nothing, so the bank can
## never grow — a price the purse cannot hold is a court that buys no dinner and
## strikes forever (issue #910; wiki: treasury-planner § Lock-recovery).
func test_the_hire_margin_yields_when_the_purse_cannot_hold_it() -> void:
	var market := WorldMarket.with_default_prices()
	var poor: PlayerEconomy = _ai_market_economy({}, 316)
	var without: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), poor, market, 20, {}, {}, {}, 0, 18, false, true
	)
	var with_margin: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), poor, market, 20, {}, {}, {}, 0, 18, false, true, -1, 1000
	)
	var plain: Dictionary = (without["bids"] as Array)[0]
	var kept: Dictionary = (with_margin["bids"] as Array)[0]
	assert_eq(int(plain["quantity"]), 6, "the whole purse buys what grain it can")
	assert_eq(
		int(kept["quantity"]), int(plain["quantity"]),
		"a crew price the purse cannot hold yields to the ration"
	)


## The hire order names no crew when the court has no config or no staff
## targets: the market must not hold cash for a hire that will never fire
## (issue #894).
func test_next_crew_is_empty_without_a_hire_order() -> void:
	assert_eq(AiCivilianHire.next_crew(null, [], {}), "")
	var config: AiConfig = _ai_market_config()
	assert_eq(AiCivilianHire.next_crew(config, [], {}), "")
	assert_eq(
		AiCivilianHire.next_crew(config, [], {"staff_targets": {}}),
		""
	)
	assert_eq(
		AiCivilianHire.next_crew(
			config, [], {"staff_targets": {"builder": 1, "engineer": 0, "explorer": 0, "spy": 0}}
		),
		"builder"
	)


## The court's hire margin is the home crew's catalogue price: a baseline court
## keeps its published market, a foreign region's plan is skipped, and an empty
## next_crew holds nothing back (issue #894). Lives on MapPlayEconomyCourtBook
## with the rest of the trade book.
func test_the_hire_margin_reads_the_home_crews_price() -> void:
	var court := MapPlayEconomyCourt.new()
	court.faction = 1
	var home: int = FactionCatalog.region_of(1)
	court.kind = AiControl.KIND_BASELINE
	assert_eq(
		MapPlayEconomyCourtBook.hire_margin(court), 0,
		"baseline courts keep their published market"
	)
	court.kind = AiControl.KIND_SUBJECT
	court.plans = [
		{"region": home + 1, "plan": {"next_crew": "explorer"}},
		{"region": home, "plan": {"next_crew": ""}},
	]
	assert_eq(
		MapPlayEconomyCourtBook.hire_margin(court), 0,
		"an empty hire order holds nothing back"
	)
	court.plans = [
		{"region": home + 1, "plan": {"next_crew": "explorer"}},
		{"region": home, "plan": {"next_crew": "builder"}},
	]
	assert_eq(
		MapPlayEconomyCourtBook.hire_margin(court),
		CivilianCatalog.treasury_cost("builder"),
		"the home crew's price is the margin"
	)


## The economy trace names the bid the footing held shut, so a court at war is
## never silent about the stock it did not buy (REQ-P5-05; DR-20261117-01).
func test_the_trace_names_the_bid_a_war_footing_held_shut() -> void:
	var merged: Dictionary = {"events": []}
	var court: Dictionary = {"events": [], "actions": {}}
	AiEconomyTrace.record(
		merged, {2: court},
		{"factions": {2: {"trade": {
			"bids_blocked": AiMarketPlanner.REASON_SPECULATE,
		}}}}
	)
	var text: String = ""
	for entry: Variant in court["events"]:
		text = String(entry)
	assert_true(
		text.contains(AiMarketPlanner.REASON_SPECULATE),
		"the trace names why the court bought nothing above its commitments"
	)


## An overstretched court opens no new commerce station: with no squadron to
## fight it keeps its hulls on its own water, and the order names the raid it
## withheld. A court at one front still works the enemy's trade
## (DR-20261117-01).
func test_an_overstretched_court_opens_no_new_raid() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var fleets: Array[FleetState] = [_squadron(0, 0, 0, "sloop")]
	var one: DiplomacyState = _war_state(0, 1)
	assert_eq(
		AiPhasePlanner.phase_for(config, one), AiPhasePlanner.PHASE_WAR,
		"one Great Power war is the war footing"
	)
	var raid: Dictionary = AiNavalPlanner.orders(
		config, one, model, fleets, null, AiPhasePlanner.PHASE_WAR
	)
	assert_eq(String(raid["orders"][0]["kind"]), AiNavalPlanner.KIND_RAID)
	assert_eq(int(raid["orders"][0]["zone"]), 1, "the water off Coro")
	var two: DiplomacyState = _war_state(0, 1)
	two.ensure_relation(0, 2, 1).at_war = true
	assert_eq(
		AiPhasePlanner.phase_for(config, two), AiPhasePlanner.PHASE_FRONTS,
		"two Great Power wars are the overstretched footing"
	)
	var home: Dictionary = AiNavalPlanner.orders(
		config, two, model, fleets, null, AiPhasePlanner.PHASE_FRONTS
	)
	assert_eq((home["orders"] as Array).size(), 1, "the hull still gets one order")
	assert_eq(
		String(home["orders"][0]["kind"]), AiNavalPlanner.KIND_HOME,
		"no new station: the squadron keeps its own water"
	)
	assert_eq(
		String(home["orders"][0]["reason"]), AiNavalPlanner.REASON_FRONTS,
		"the order names the raid it withheld"
	)


## A chain already opened is a stake: the footing never strands the step the
## court has already paid for (DR-20261116-11).
func test_a_chain_already_opened_keeps_its_step_at_war() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, tribe, 1).score = 60.0
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_CONSULATE)
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var war: Dictionary = AiTribeColony.ambition(
		state, world, null, 2, tribe, 5000, {}, AiPhasePlanner.PHASE_WAR
	)
	assert_true(bool(war["wanted"]), "the held chain keeps its next step")
	assert_true(bool(war["held"]))
	assert_eq(String(war["stage"]), DiplomacyCatalog.STAGE_EMBASSY)


## The study the chain needs is no study the court owes while the footing holds
## the chain shut (DR-20261116-11).
func test_the_door_closes_with_the_chain_at_war() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, tribe, 1).score = 60.0
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(
		AiTribeColony.door(state, world, null, 2, {}, AiPhasePlanner.PHASE_WAR),
		"diplomatic_expertise",
		"a held chain still names the study it walks to"
	)
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_NONE)
	assert_eq(
		AiTribeColony.door(state, world, null, 2, {}, AiPhasePlanner.PHASE_WAR), "",
		"a chain the footing holds shut has no door"
	)
	assert_eq(
		AiTribeColony.door(state, world, null, 2, {}, AiPhasePlanner.PHASE_PEACE),
		"", "the first link needs no study at peace either"
	)


## The ledger names the aim the footing closed instead of dropping the row, so
## the trace reads why the court buys no colony this turn (REQ-P5-05).
func test_the_ledger_names_the_chain_the_footing_holds_shut() -> void:
	var closed: Array[AiObjective] = AiObjectivesPlan.build({
		"tribe_target": -1, "tribe_closed": AiTribeColony.REASON_WAR,
	})
	var row: AiObjective = _objective(closed, "colonise.tribe_chain")
	assert_true(row != null, "the closed aim still prints")
	assert_eq(row.status, AiObjective.STATUS_BLOCKED)
	assert_eq(row.blocked, AiTribeColony.REASON_WAR)
	assert_true(row.cost.is_empty(), "a closed aim claims nothing")
	var open: Array[AiObjective] = AiObjectivesPlan.build({"tribe_target": -1})
	assert_true(
		_objective(open, "colonise.tribe_chain") == null,
		"a footing that opens the slot emits no row"
	)


## The first objective with `id` in a built set, or null.
func _objective(objectives: Array[AiObjective], id: String) -> AiObjective:
	for objective: AiObjective in objectives:
		if objective.id == id:
			return objective
	return null


func test_an_overstretched_court_opens_no_war_on_a_peer() -> void:
	var run: Dictionary = _front_turn(2, true)
	var candidate: Dictionary = _candidate(run["plan"], PHASE_OTHER)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_FRONTS)
	assert_ne(
		String((run["plan"]["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the frontier is full: no third Great Power war on a crown it cannot beat"
	)
	assert_eq(String(candidate.get("blocked", "")), "overstretched: no third front")


func test_an_overstretched_court_still_takes_a_crown_it_outmatches() -> void:
	var run: Dictionary = _front_turn(2)
	var action: Dictionary = run["plan"]["action"]
	var candidate: Dictionary = _candidate(run["plan"], PHASE_OTHER)

	assert_eq(
		String(action.get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the cheap province next door is a war the court can already win"
	)
	assert_eq(int(action.get("target", -1)), PHASE_OTHER)
	assert_eq(String(candidate.get("blocked", "")), "")


## The outmatch read asks the host that marches, not the province count
## (issue #1234): a court under its own muster strength that reads a peer
## fielding more regiments may not open that war, however many provinces the
## published power score counts. The court keeps its one order for the next aim.
func test_an_under_strength_court_opens_no_war_on_a_bigger_host() -> void:
	var run: Dictionary = _front_turn(2)
	# The issue's own reading: a 21-province court with one regiment against a
	# 2-province peer with five — the published score reads the court ahead,
	# the host it can field does not.
	var context: Dictionary = run["context"].duplicate(true)
	context["power"] = {PHASE_OWNER: 240, PHASE_OTHER: 30, PHASE_MINOR: 1}
	context["regiments"] = {PHASE_OWNER: 1, PHASE_OTHER: 5, PHASE_MINOR: 1}
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		run["config"], run["state"], AiState.new(), run["world"], 1, context
	)
	var candidate: Dictionary = _candidate(plan, PHASE_OTHER)

	assert_true(
		AiDiplomacyGates.outmatches(run["config"], PHASE_OTHER, context) == false,
		"the bigger host is a war the court cannot win on the hosts it reads"
	)
	assert_eq(
		String(candidate.get("blocked", "")), "overstretched: no third front",
		"the province count never carries a war the host cannot fight"
	)
	assert_ne(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the one order goes to the next aim"
	)


## A court at its muster target reads the published power score again: the
## province term answers, so a bigger province count is a war it may still open.
func test_a_court_at_strength_reads_the_published_score() -> void:
	var run: Dictionary = _front_turn(2)
	var config: AiConfig = run["config"]
	var context: Dictionary = run["context"].duplicate(true)
	context["power"] = {PHASE_OWNER: 240, PHASE_OTHER: 30, PHASE_MINOR: 1}
	# At its war-target strength the same published score answers: the court
	# outmatches and the cheap province next door stays on the table.
	context["regiments"] = {
		PHASE_OWNER: AiArmyReinforce.desired_regiments(config, true),
		PHASE_OTHER: 5, PHASE_MINOR: 1,
	}
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, run["state"], AiState.new(), run["world"], 1, context
	)

	assert_true(
		AiDiplomacyGates.outmatches(config, PHASE_OTHER, context),
		"at strength the published score answers the pair"
	)
	assert_eq(
		String(_candidate(plan, PHASE_OTHER).get("blocked", "")), "",
		"the cheap province next door stays on the table"
	)


## The read keeps the published planner when the caller hands in no order of
## battle: an unknown host is not a war the court cannot win.
func test_an_outmatch_read_without_a_host_keeps_the_published_score() -> void:
	var run: Dictionary = _front_turn(2)
	var context: Dictionary = run["context"].duplicate(true)
	context.erase("regiments")

	assert_true(
		AiDiplomacyGates.outmatches(run["config"], PHASE_OTHER, context),
		"no host to read: the published planner stands"
	)
	# And the planner never blocks the pair: the cheap province next door opens.
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		run["config"], run["state"], AiState.new(), run["world"], 1, context
	)
	assert_eq(
		String(_candidate(plan, PHASE_OTHER).get("blocked", "")), "",
		"an unknown order of battle is not a war the court cannot win"
	)


func test_a_court_at_one_front_still_opens_its_next_war() -> void:
	var run: Dictionary = _front_turn(1, true)
	var candidate: Dictionary = _candidate(run["plan"], PHASE_OTHER)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_WAR)
	assert_eq(
		String((run["plan"]["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"one front is under the threshold: the published planner declares"
	)
	assert_eq(String(candidate.get("blocked", "")), "")


func test_an_overstretched_court_still_takes_the_cheap_province_next_door() -> void:
	var run: Dictionary = _front_turn(2, true, true)
	var action: Dictionary = run["plan"]["action"]
	var candidate: Dictionary = _candidate(run["plan"], PHASE_MINOR)

	assert_eq(String(action.get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_eq(int(action.get("target", -1)), PHASE_MINOR)
	assert_eq(
		String(candidate.get("blocked", "")), "",
		"a Minor Nation is colonial business, not a Great Power front"
	)


func test_a_caller_with_no_order_of_battle_keeps_the_published_planner() -> void:
	var run: Dictionary = _front_turn(2, true, false, true, false)
	var candidate: Dictionary = _candidate(run["plan"], PHASE_OTHER)

	assert_ne(
		String(candidate.get("blocked", "")), "overstretched: no third front",
		"an unknown order of battle is not a war the court cannot win"
	)


func test_the_planner_reads_the_footing_it_is_not_handed() -> void:
	var run: Dictionary = _front_turn(2, true, false, false)
	var candidate: Dictionary = _candidate(run["plan"], PHASE_OTHER)

	assert_eq(
		String(candidate.get("blocked", "")), "overstretched: no third front",
		"a caller that hands in no posture gets the same reading"
	)


## The `decide` pass reads each relation its own way: the crown war is weighed
## as a peace and the calm court as a war plus its menu of offers, and the one
## order still leaves as a single action (REQ-P2-03).
func test_a_pass_weighs_each_relation_its_own_way() -> void:
	var run: Dictionary = _buyout_turn(1, -1, [PHASE_OTHER])
	var plan: Dictionary = run["plan"]
	var war_row: Dictionary = _candidate(plan, PHASE_RIVAL)
	var calm_row: Dictionary = _candidate(plan, PHASE_OTHER)

	assert_eq((plan["candidates"] as Array).size(), 2)
	assert_true(bool(war_row.get("at_war", false)), "the crown war is a peace row")
	assert_false(bool(calm_row.get("at_war", true)), "the calm court is a war row")
	assert_false(war_row.has("offer"), "a court at war weighs no fresh offer")
	assert_true(calm_row.has("offer"), "the calm row carries its own offers")
	assert_true(
		String((plan["action"] as Dictionary).get("kind", "")).length() > 0,
		"the pass still spends the court's one order"
	)


# --- dispatch: no new voyage on a war footing ---------------------------------


## A court with a harbour at home, an idle Explorer and a squadron in port: the
## published embark step, which the war footing closes.
func _old_world() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(Vector2i(x, y))
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var province := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), PHASE_OWNER, true
	)
	province.capital_tile = Vector2i(0, 0)
	province.port_tile = Vector2i(0, 1)
	province.coastal = true
	model.provinces = [province]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model


func _new_world() -> MapModel:
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = WorldMap.NEW_WORLD
	model.region_key = "new_world"
	for y in 2:
		for x in 4:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	var sea: Array[Vector2i] = []
	for x in 4:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Far Shore", sea, Vector2(1.5, 2.0), 4)]
	return model


func _world() -> WorldMap:
	var map := WorldMap.new()
	map.add_region(_old_world())
	map.add_region(_new_world())
	map.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return map


## The same court and voyage under one footing. `wants_income` is the court's
## money goal (DR-20261113-19).
func _voyage(
	posture: String, embarked: bool = false, wants_income: bool = false
) -> Dictionary:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet := FleetState.in_port(1, PHASE_OWNER, 0)
	var unit := CivilianState.create(1, PHASE_OWNER, "explorer", Vector2i(0, 0))
	if embarked:
		assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	return AiColonisationPlanner.plan(
		_phase_config(), world, 0, old_world, [fleet], [unit], {}, null, posture, wants_income
	)


func test_a_court_at_peace_opens_the_published_voyage() -> void:
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_PEACE).get("kind", "")), "embark"
	)


func test_a_war_footing_closes_a_new_voyage() -> void:
	assert_true(_voyage(AiPhasePlanner.PHASE_WAR).is_empty(), "the hulls stay home")
	assert_true(
		_voyage(AiPhasePlanner.PHASE_FRONTS).is_empty(),
		"two fronts do not free a squadron either"
	)


func test_an_expedition_already_afloat_keeps_sailing() -> void:
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_WAR, true).get("kind", "")), "sail",
		"a voyage under way is not abandoned"
	)


func test_an_earning_court_sails_even_on_a_war_footing() -> void:
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_WAR, false, true).get("kind", "")), "embark",
		"the gold that ends the impasse is overseas (DR-20261113-19)"
	)
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_FRONTS, false, true).get("kind", "")), "embark",
		"two fronts do not close the one voyage that pays for the war"
	)


## One observer session with the crown's harbour, squadron and Explorer. The
## session is rebuilt per case: a voyage moves the roster it is built from.
func _session(diplomacy: DiplomacyState) -> PlaySession:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet := FleetState.in_port(1, PHASE_OWNER, 0)
	var unit := CivilianState.create(1, PHASE_OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = PHASE_RIVAL
	play.region_index = 0
	play.map_seed = PHASE_SEED
	play.world = world
	play.model = old_world
	play.diplomacy = diplomacy
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	# The court's ledger is read for its money goal (DR-20261113-19).
	play.ensure_ai()
	return play


func test_the_map_adapter_keeps_the_earning_court_s_voyage_open() -> void:
	var peace: PlaySession = _session(_phase_court())
	var quiet: Array[Dictionary] = MapPlayColonisationAi.run(peace)
	assert_eq(quiet.size(), 1, "with no war the published voyage opens")
	assert_eq(String(quiet[0]["kind"]), "embark")
	peace.ship_layer.free()
	peace.civilian_layer.free()

	# A court at war with a thin purse is on earn: the gold across the water is
	# the only thing that ends its impasse (DR-20261113-19).
	var war: DiplomacyState = _phase_court()
	_phase_war(war, PHASE_RIVAL)
	var poor: PlaySession = _session(war)
	poor.ai.economy_for(PHASE_OWNER).treasury = 1000
	var earning: Array[Dictionary] = MapPlayColonisationAi.run(poor)
	assert_eq(earning.size(), 1, "a court on earn still reaches for the New World")
	assert_eq(String(earning[0]["kind"]), "embark")
	poor.ship_layer.free()
	poor.civilian_layer.free()


func test_the_map_adapter_closes_the_voyage_of_a_court_that_can_pay() -> void:
	var war: DiplomacyState = _phase_court()
	_phase_war(war, PHASE_RIVAL)
	var play: PlaySession = _session(war)
	play.ensure_ai()
	play.ai.economy_for(PHASE_OWNER).treasury = 20000
	var footing: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_true(footing.is_empty(), "a funded court keeps its hulls for the fleet")
	assert_false(play.civilian_layer.units[0].is_embarked(), "the Explorer stays ashore")
	play.ship_layer.free()
	play.civilian_layer.free()


# --- dispatch: an overstretched court takes the white peace -------------------


## A declaration by the warmonger at one or two Great Power fronts, then a full
## rival pass where the isolationist puts a white peace to it.
func _offer_peace_to(wars: int) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(PHASE_RIVAL, PHASE_OWNER, 1)
	state.relation(PHASE_RIVAL, PHASE_OWNER).score = 35.0
	assert_true(bool(DiplomacyRules.declare_war(state, PHASE_RIVAL, PHASE_OWNER)["ok"]))
	if wars > 1:
		state.ensure_relation(PHASE_RIVAL, PHASE_THIRD, 1)
		assert_true(bool(DiplomacyRules.declare_war(state, PHASE_RIVAL, PHASE_THIRD)["ok"]))
	var ai_state := AiState.new()
	ai_state.agendas[PHASE_RIVAL] = AiAgenda.WARMONGER
	ai_state.agendas[PHASE_OWNER] = AiAgenda.ISOLATIONIST
	# The declarations above bypass the planner, so the pair cooldown the pass
	# would have written is recorded here: a warmonger may not re-declare the war
	# it just signed away (wiki: diplomacy § Cooldowns).
	ai_state.note_war(PHASE_RIVAL, PHASE_OWNER, 1)
	ai_state.note_war(PHASE_RIVAL, PHASE_THIRD, 1)
	var posture: String = AiPhasePlanner.phase_for(_phase_config(PHASE_RIVAL), state)
	var result: Dictionary = AiTurn.run(
		state, AiFixture.world([PHASE_OWNER, PHASE_RIVAL, PHASE_RIVAL, PHASE_RIVAL]), ai_state,
		1, 4, PHASE_SEED, {"regiments": {}, "ships": {}}
	)
	return {"state": state, "posture": posture, "trace": result["trace"]}


## The offering court's record in the turn trace.
func _record(trace: Array, faction: int) -> Dictionary:
	for raw: Dictionary in trace:
		if int(raw.get("faction", -1)) == faction:
			return raw
	return {}


func test_a_court_at_one_front_refuses_the_white_peace() -> void:
	var run: Dictionary = _offer_peace_to(1)
	var record: Dictionary = _record(run["trace"], PHASE_OWNER)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_WAR)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(
		String(record["message"]).contains("refuses a white peace"),
		"a warmonger at one front keeps its war"
	)
	assert_true((run["state"] as DiplomacyState).relation(PHASE_RIVAL, PHASE_OWNER).at_war)


func test_an_overstretched_court_takes_the_white_peace() -> void:
	var run: Dictionary = _offer_peace_to(2)
	var record: Dictionary = _record(run["trace"], PHASE_OWNER)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_FRONTS)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_false(
		(run["state"] as DiplomacyState).relation(PHASE_RIVAL, PHASE_OWNER).at_war,
		"two fronts are one too many: the offer is signed"
	)
	assert_false(
		String(record["message"]).contains("refuses"),
		"the court answers the offer instead of refusing it"
	)


# --- a court that cannot re-arm buys out of its crown wars (issue #975) -------


## One court's planner reading with the purse the doctrine reads: `pursed`
## sets the ledger's treasury (the default leaves the starting purse), `extra`
## names further courts to hold relations with beyond the war targets.
func _buyout_turn(wars: int, pursed: int = -1, extra: Array[int] = []) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(1)
	var held: Array[int] = []
	for index in wars:
		held.append([PHASE_RIVAL, PHASE_THIRD][index])
	for other: int in held + extra:
		state.ensure_relation(PHASE_OWNER, other, 1)
		state.relation(PHASE_OWNER, other).score = 10.0
	for target: int in held:
		_phase_war(state, target)
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var ai_state := AiState.new()
	if pursed >= 0:
		ai_state.economy_for(PHASE_OWNER).treasury = pursed
	var posture: String = AiPhasePlanner.phase_for(config, state)
	var context: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
		"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
		"posture": posture,
	}
	var world: WorldMap = AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR])
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, world, 30, context
	)
	return {
		"plan": plan,
		"state": state,
		"posture": posture,
		"config": config,
		"ai_state": ai_state,
	}


## A standing crown war the press keeps above the bar, on a court whose purse
## is under its muster price: the court puts the white peace to that crown
## itself (issue #975), which the published planner never does.
func test_a_poor_court_buys_out_of_the_crown_war_it_is_fighting() -> void:
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var floor: int = _muster_price(config)
	var run: Dictionary = _buyout_turn(1, floor - 100)
	var action: Dictionary = run["plan"]["action"]
	var rival: Dictionary = _candidate(run["plan"], PHASE_RIVAL)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_WAR)
	assert_true(
		int(rival.get("desire", 0)) >= AiPeaceStance.peace_bar(config),
		"the war still reads worth waging — only the purse answers for it"
	)
	assert_eq(String(action.get("kind", "")), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(action.get("target", -1)), PHASE_RIVAL)
	assert_eq(
		String(rival.get("blocked", "")), "",
		"the purse under the muster price composes the peace the desire bars"
	)


## The re-declaration brake: a court honors the truce its own bought peace
## left, so the peace lasts long enough to matter (issue #975).
func test_a_court_honors_the_truce_its_peace_left() -> void:
	var run: Dictionary = _buyout_turn(0, -1, [PHASE_OTHER])
	var state: DiplomacyState = run["state"]
	var ai_state: AiState = run["ai_state"]
	ai_state.note_war(PHASE_OWNER, PHASE_OTHER, 20)
	ai_state.note_peace(PHASE_OWNER, PHASE_OTHER, 24, true)
	ai_state.note_truce(PHASE_OWNER, PHASE_OTHER, 24)
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var context: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_OTHER: 1},
		"regiments": {PHASE_OWNER: 4, PHASE_OTHER: 1},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
		"posture": AiPhasePlanner.phase_for(config, state),
	}
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state,
		AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR]), 30, context
	)

	assert_eq(
		String(_candidate(plan, PHASE_OTHER).get("blocked", "")),
		"the pair's truce holds: no new war yet",
		"an unfought peace's truce bars the re-declaration for its whole window"
	)


## A Minor Nation is colonial business in its own right — but once the court
## has signed a peace with it, the pair's truce holds there too (issue #1140):
## a peace the court signed is not undone the turn after it was made.
func test_a_truce_holds_a_minor_pair_the_court_peaced() -> void:
	var run: Dictionary = _buyout_turn(0, -1, [PHASE_MINOR])
	var state: DiplomacyState = run["state"]
	var ai_state: AiState = run["ai_state"]
	ai_state.note_war(PHASE_OWNER, PHASE_MINOR, 20)
	ai_state.note_peace(PHASE_OWNER, PHASE_MINOR, 24, true)
	ai_state.note_truce(PHASE_OWNER, PHASE_MINOR, 24)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		run["config"], state, ai_state,
		AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR]), 25,
		{
			"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
			"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
			"ships": {PHASE_OWNER: 2},
			"player": -1,
			"posture": String(run["posture"]),
		}
	)
	assert_eq(
		String(_candidate(plan, PHASE_MINOR).get("blocked", "")),
		"the pair's truce holds: no new war yet",
		"the peace a court signed with a Minor binds its own re-declaration"
	)
	# Past the truce window the colonial business opens again.
	var settled: Dictionary = AiDiplomacyPlanner.decide(
		run["config"], state, ai_state,
		AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR]), 60,
		{
			"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
			"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
			"ships": {PHASE_OWNER: 2},
			"player": -1,
			"posture": String(run["posture"]),
		}
	)
	assert_eq(
		String(_candidate(settled, PHASE_MINOR).get("blocked", "")), "",
		"once the truce lapses, colonial business is legal again"
	)


## The war cooldown runs from the peace, not the declaration: a war declared
## early and peaced late cannot be re-declared the turn after the peace
## (issue #1140).
func test_the_war_cooldown_runs_from_the_peace() -> void:
	var ai_state := AiState.new()
	ai_state.note_war(PHASE_OWNER, PHASE_MINOR, 2)
	ai_state.note_truce(PHASE_OWNER, PHASE_MINOR, 24)
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var cooldown: int = config.parameter("diplomacy.war_cooldown_turns")
	assert_true(
		ai_state.war_on_cooldown(PHASE_OWNER, PHASE_MINOR, 25, cooldown),
		"a t2 war peaced at t24 is still on cooldown at t25"
	)
	assert_false(
		ai_state.war_on_cooldown(PHASE_OWNER, PHASE_MINOR, 28, cooldown),
		"the 4-turn cooldown measured from a t24 peace lapses by t28"
	)
	assert_true(
		ai_state.war_on_cooldown(PHASE_OWNER, PHASE_MINOR, 25, 30),
		"a 30-turn truce keeps the pair barred past the short clock"
	)
	assert_false(
		ai_state.war_on_cooldown(PHASE_OWNER, PHASE_THIRD, 25, cooldown),
		"a pair with no peace and no war reads off the clock"
	)
	# A fresh declaration after the old peace starts a new cooldown; the stale
	# settlement must not waive it.
	ai_state.note_war(PHASE_OWNER, PHASE_MINOR, 30)
	assert_true(
		ai_state.war_on_cooldown(PHASE_OWNER, PHASE_MINOR, 31, cooldown),
		"a t30 war after the t24 peace restarts the clock at t30"
	)
	assert_false(
		ai_state.war_on_cooldown(PHASE_OWNER, PHASE_MINOR, 34, cooldown),
		"the fresh declaration's 4-turn cooldown lapses by t34"
	)


## A purse that can pay for the army keeps the published planner: the war it is
## winning stays worth waging, and the next crown war opens.
func test_a_rich_court_keeps_its_crown_wars() -> void:
	var war_run: Dictionary = _buyout_turn(1)
	var rival: Dictionary = _candidate(war_run["plan"], PHASE_RIVAL)
	var peace_run: Dictionary = _buyout_turn(0, -1, [PHASE_OTHER])
	var action: Dictionary = peace_run["plan"]["action"]

	assert_eq(
		String(rival.get("blocked", "")), "war still worth waging",
		"the starting purse can re-arm: the doctrine stands down"
	)
	assert_eq(
		String((war_run["plan"]["action"] as Dictionary).get("kind", "")), "",
		"no other order competes: the war stands"
	)
	assert_eq(String(action.get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_eq(int(action.get("target", -1)), PHASE_OTHER)


## The doctrine is crown-war business only: a Minor war at the same poor purse
## is never bought out, while the crown war beside it is.
func test_a_minor_war_is_never_bought_out() -> void:
	var floor: int = _muster_price(_phase_config(PHASE_OWNER))
	var state := DiplomacyState.new()
	state.reset(1)
	for other: int in [PHASE_RIVAL, PHASE_MINOR]:
		state.ensure_relation(PHASE_OWNER, other, 1)
		state.relation(PHASE_OWNER, other).score = 10.0
	_phase_war(state, PHASE_RIVAL)
	_phase_war(state, PHASE_MINOR)
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var ai_state := AiState.new()
	ai_state.economy_for(PHASE_OWNER).treasury = floor - 100
	var posture: String = AiPhasePlanner.phase_for(config, state)
	assert_eq(String(posture), AiPhasePlanner.PHASE_WAR, "a colonial war is no front")
	var context: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_MINOR: 1},
		"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_MINOR: 1},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
		"posture": posture,
	}
	var world: WorldMap = AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR])
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, world, 30, context
	)

	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"the crown war is bought out"
	)
	assert_eq(int((plan["action"] as Dictionary).get("target", -1)), PHASE_RIVAL)
	assert_eq(
		String(_candidate(plan, PHASE_MINOR).get("blocked", "")), "war still worth waging",
		"the Minor war is colonial business and stays open"
	)


## The pair's peace-offer cooldown still gates the buy-out: a refused offer is
## not repeated every turn (wiki: diplomacy § Planner selection).
func test_the_buy_out_waits_out_the_peace_cooldown() -> void:
	var floor: int = _muster_price(_phase_config(PHASE_OWNER))
	var run: Dictionary = _buyout_turn(1, floor - 100)
	var state: DiplomacyState = run["state"]
	var ai_state: AiState = run["ai_state"]
	ai_state.note_peace(PHASE_OWNER, PHASE_RIVAL, 29, false)
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var context: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
		"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1, PHASE_OTHER: 1},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
		"posture": AiPhasePlanner.phase_for(config, state),
	}
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state,
		AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR]), 30, context
	)

	assert_true(
		String(_candidate(plan, PHASE_RIVAL).get("blocked", "")).contains("peace cooldown"),
		"the refused buy-out waits out the pair's cooldown"
	)


# --- the war on the court's own border outlives the buy-out (issue #1082) -----


## The frontier crowns: the Great Powers whose Old World land touches the
## court's own — the front a field army can walk to and storm. A strip of
## provinces: the court holds the first two, one crown the next, a second crown
## the two after, a Minor the last.
func test_the_frontier_crowns_are_the_crowns_whose_land_touches_the_court() -> void:
	var world: WorldMap = AiFixture.land_world(
		[PHASE_OWNER, PHASE_OWNER, PHASE_RIVAL, PHASE_THIRD, PHASE_THIRD, PHASE_MINOR]
	)
	var owner: Array[int] = AiFrontier.crowns(world, PHASE_OWNER)
	var rival: Array[int] = AiFrontier.crowns(world, PHASE_RIVAL)

	assert_eq(owner, [PHASE_RIVAL] as Array[int], "only the crown next door is reachable")
	assert_eq(
		rival, [PHASE_OWNER, PHASE_THIRD] as Array[int], "the reading is symmetric along the border"
	)
	assert_eq(
		AiFrontier.crowns(world, PHASE_THIRD), [PHASE_RIVAL] as Array[int],
		"the crown past the neighbour reads its own border"
	)
	assert_eq(
		AiFrontier.crowns(world, PHASE_MINOR), [PHASE_THIRD] as Array[int],
		"a Minor Nation reads the crowns its land touches; the stamp gates who banks on it"
	)
	assert_true(
		AiFrontier.crowns(null, PHASE_OWNER).is_empty(), "no world, no frontier"
	)


## The stamp the shared planners read: a court with no row — a frozen baseline,
## a fixture — keeps the published behaviour.
func test_the_frontier_stamp_reads_only_the_court_that_carries_it() -> void:
	var supplied: Dictionary = {AiFrontier.KEY: {PHASE_OWNER: [PHASE_RIVAL]}}
	var shared: Dictionary = AiTurnRead.context(
		AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR]), supplied, -1
	)

	assert_eq(
		shared.get(AiFrontier.KEY, {}), {PHASE_OWNER: [PHASE_RIVAL]},
		"the shared read carries the stamp the pass supplied"
	)
	assert_true(AiFrontier.holds(PHASE_OWNER, PHASE_RIVAL, shared))
	assert_false(AiFrontier.holds(PHASE_OWNER, PHASE_THIRD, shared))
	assert_false(
		AiFrontier.holds(PHASE_RIVAL, PHASE_OWNER, shared),
		"a court with no row keeps the published planner"
	)
	assert_false(
		AiFrontier.holds(PHASE_OWNER, PHASE_RIVAL, {}),
		"a caller with no stamp keeps the published planner"
	)


## The planner reading for a court at `wars` Great Power fronts with the
## frontier stamp the shared pass hands a conquest-gap court (issue #1082):
## `border` names the crowns whose Old World land touches the court's own. The
## border crown is the stronger one, so only the victory press keeps that war's
## desire above the peace bar; the far weak crown reads the higher desire. The
## published planner settles the lower one first at two fronts — the border
## front, the conquest's own road.
func _border_turn(wars: int, border: Array = [], pursed: int = -1) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(1)
	var held: Array[int] = []
	for index in wars:
		held.append([PHASE_RIVAL, PHASE_THIRD][index])
	for other: int in held:
		state.ensure_relation(PHASE_OWNER, other, 1)
		state.relation(PHASE_OWNER, other).score = 10.0
	for target: int in held:
		_phase_war(state, target)
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var ai_state := AiState.new()
	if pursed >= 0:
		ai_state.economy_for(PHASE_OWNER).treasury = pursed
	var posture: String = AiPhasePlanner.phase_for(config, state)
	var context: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 9, PHASE_OTHER: 1},
		"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 9, PHASE_OTHER: 1},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
		"posture": posture,
		"victory_press": {PHASE_OWNER: 40},
	}
	if not border.is_empty():
		context[AiFrontier.KEY] = {PHASE_OWNER: border}
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state,
		AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_THIRD, PHASE_MINOR]), 30, context
	)
	return {"plan": plan, "posture": posture}


## An overstretched court settles the border war like any other when it carries
## no stamp — the published planner stands.
func test_an_unstamped_court_settles_the_border_war_at_two_fronts() -> void:
	var run: Dictionary = _border_turn(2)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_FRONTS)
	assert_eq(
		String((run["plan"]["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_OFFER_PEACE
	)
	assert_eq(
		int((run["plan"]["action"] as Dictionary).get("target", -1)), PHASE_THIRD,
		"the published planner settles the war it wants least — the border crown"
	)


## The border war outlives the `fronts` buy-out (issue #1082): the overstretched
## court keeps the one war its field army can march on and settles the other.
func test_the_border_war_outlives_the_fronts_buy_out() -> void:
	var run: Dictionary = _border_turn(2, [PHASE_THIRD])
	var third: Dictionary = _candidate(run["plan"], PHASE_THIRD)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_FRONTS)
	assert_eq(
		int(third.get("desire", 0)) < int(_candidate(run["plan"], PHASE_RIVAL).get("desire", 0)),
		true,
		"the border war is the one the published planner would settle"
	)
	assert_eq(
		String((run["plan"]["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_OFFER_PEACE
	)
	assert_eq(
		int((run["plan"]["action"] as Dictionary).get("target", -1)), PHASE_RIVAL,
		"the peace goes to the war on the far crown, not the border front"
	)
	assert_eq(
		String(third.get("blocked", "")), "war still worth waging",
		"the front the army can walk to stays open"
	)


## The border war outlives the purse leg too (issue #975's doctrine): a banking
## court keeps the war its conquest needs while it saves for the army.
func test_the_border_war_outlives_the_purse_leg() -> void:
	var floor: int = _muster_price(_phase_config(PHASE_OWNER))
	var published: Dictionary = _border_turn(1, [], floor - 100)
	var stamped: Dictionary = _border_turn(1, [PHASE_RIVAL], floor - 100)

	assert_eq(
		String((published["plan"]["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"the published poor court buys out of its only crown war"
	)
	assert_eq(
		int((published["plan"]["action"] as Dictionary).get("target", -1)), PHASE_RIVAL
	)
	assert_true(
		(stamped["plan"]["action"] as Dictionary).is_empty(),
		"a banking court keeps the border war: no peace, no new front"
	)
	assert_eq(
		String(_candidate(stamped["plan"], PHASE_RIVAL).get("blocked", "")),
		"war still worth waging",
		"the front the army can walk to is not for sale"
	)


## The answering half: an overstretched court takes any white peace it is
## offered — except the one that closes its border front (issue #1082).
func test_an_overstretched_court_answers_its_border_crown_from_its_own_stance() -> void:
	var state := DiplomacyState.new()
	state.reset(1)
	for other: int in [PHASE_RIVAL, PHASE_THIRD]:
		state.ensure_relation(PHASE_OWNER, other, 1)
		state.relation(PHASE_OWNER, other).score = 10.0
		_phase_war(state, other)
	var ai_state := AiState.new()
	var world: WorldMap = AiFixture.world([PHASE_OWNER, PHASE_OWNER, PHASE_OTHER, PHASE_MINOR])
	var shared: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 9},
		"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 9},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
		AiFrontier.KEY: {PHASE_OWNER: [PHASE_RIVAL]},
	}

	assert_eq(
		AiTurnApply.peace_answer(
			state, world, ai_state, PHASE_RIVAL, PHASE_OWNER, 10, PHASE_SEED, shared
		),
		DiplomacyRules.DECISION_REFUSE,
		"the border front is the one war the overstretched court keeps"
	)
	assert_eq(
		AiTurnApply.peace_answer(
			state, world, ai_state, PHASE_THIRD, PHASE_OWNER, 10, PHASE_SEED, shared
		),
		DiplomacyRules.DECISION_AUTO,
		"a far crown's peace is still taken at two fronts"
	)
	shared.erase(AiFrontier.KEY)
	assert_eq(
		AiTurnApply.peace_answer(
			state, world, ai_state, PHASE_RIVAL, PHASE_OWNER, 10, PHASE_SEED, shared
		),
		DiplomacyRules.DECISION_AUTO,
		"an unstamped court keeps the published answer"
	)


## The price of the line a court saving under its war target would buy — the
## purse leg the buy-out reads (issue #975).
func _muster_price(config: AiConfig) -> int:
	return maxi(config.parameter("army.min_treasury"), 0) + AiArmyReinforce.cheapest_line_price(_purse(0))


# --- the front the army can march on (issue #995) -----------------------------


## The border read itself: a crown's land touches the court's own frontier on
## the map, and nothing else counts — not the court with itself, not a crown
## held off behind another's land, not a caller with no world to read.
func test_the_border_read_names_the_front_the_army_can_walk() -> void:
	var side: WorldMap = AiFixture.land_world(
		[PHASE_OWNER, PHASE_OWNER, PHASE_RIVAL, PHASE_MINOR]
	)
	var apart: WorldMap = AiFixture.land_world(
		[PHASE_OWNER, PHASE_MINOR, PHASE_MINOR, PHASE_RIVAL]
	)

	assert_true(
		AiBorderFronts.marches_on(side, PHASE_OWNER, PHASE_RIVAL),
		"a crown next door is a front the field army can storm"
	)
	assert_false(
		AiBorderFronts.marches_on(apart, PHASE_OWNER, PHASE_RIVAL),
		"a crown behind another's land is a war the army cannot reach"
	)
	assert_false(
		AiBorderFronts.marches_on(side, PHASE_OWNER, PHASE_OWNER),
		"a court does not border itself"
	)
	assert_false(AiBorderFronts.marches_on(null, PHASE_OWNER, PHASE_RIVAL))
	assert_false(AiBorderFronts.marches_on(side, -1, PHASE_RIVAL))
	assert_false(AiBorderFronts.marches_on(side, PHASE_OWNER, -1))
	# A world the map pass handed a region that never loaded: the read skips it
	# and still names the border the loaded ground holds.
	var partial := WorldMap.new()
	partial.add_region(null)
	partial.add_region(side.region(0))
	assert_true(
		AiBorderFronts.marches_on(partial, PHASE_OWNER, PHASE_RIVAL),
		"a region that never loaded is skipped, never read"
	)


## The one war-border pass both planners read: the hostile provinces touching
## the court's land, and the own provinces that stage the storm, so the land
## policy and the overseas crossing can never disagree about the border.
func test_the_war_border_names_the_ground_and_its_staging() -> void:
	var model: MapModel = AiFixture.land_world([PHASE_OWNER, PHASE_RIVAL]).region(0)
	var state := _war_state(PHASE_OWNER, PHASE_RIVAL)
	var read: Dictionary = AiBorderFronts.war_border(model, PHASE_OWNER, state)
	var hostile: Array[int] = []
	hostile.assign(read["hostile"])
	var staging: Array[int] = []
	staging.assign(read["staging"])
	assert_eq(hostile, [1] as Array[int], "the rival province beside the court is the front")
	assert_eq(staging, [0] as Array[int], "the court's own province beside it stages")
	assert_eq(
		AiMilitaryPlanner.frontier_hostile(model, PHASE_OWNER, state), hostile,
		"the land planner names the same hostile ground"
	)
	var peace := _peace_state(PHASE_OWNER, PHASE_RIVAL)
	var quiet: Dictionary = AiBorderFronts.war_border(model, PHASE_OWNER, peace)
	assert_true((quiet["hostile"] as Array).is_empty(), "peace reads no hostile ground")
	assert_true((quiet["staging"] as Array).is_empty(), "peace stages nowhere")
	var none: Dictionary = AiBorderFronts.war_border(null, PHASE_OWNER, state)
	assert_true((none["hostile"] as Array).is_empty(), "no map reads no front")
	assert_true((none["staging"] as Array).is_empty(), "no map stages nowhere")


## The footing's word on the pair: an overstretched court keeps the border front
## and takes any other peace, and no lighter footing changes at all (issue #995).
func test_the_overstretched_court_keeps_the_border_front() -> void:
	assert_true(
		AiPhasePlanner.keeps_the_border_front(AiPhasePlanner.PHASE_FRONTS, true)
	)
	assert_false(
		AiPhasePlanner.keeps_the_border_front(AiPhasePlanner.PHASE_FRONTS, false)
	)
	assert_false(
		AiPhasePlanner.keeps_the_border_front(AiPhasePlanner.PHASE_WAR, true),
		"one front is not overstretch: the published stance already refuses"
	)
	assert_false(
		AiPhasePlanner.keeps_the_border_front(AiPhasePlanner.PHASE_PEACE, true)
	)
	assert_true(AiPhasePlanner.takes_peace(AiPhasePlanner.PHASE_FRONTS, false))
	assert_false(AiPhasePlanner.takes_peace(AiPhasePlanner.PHASE_FRONTS, true))
	assert_false(AiPhasePlanner.takes_peace(AiPhasePlanner.PHASE_WAR, true))
	assert_false(AiPhasePlanner.takes_peace(AiPhasePlanner.PHASE_PEACE, false))


## The buy-out stands down on the border front and nowhere else (issue #995):
## both legs of the doctrine — the footing and the purse under the muster price.
func test_the_gates_do_not_buy_out_of_the_border_front() -> void:
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var ai_state := AiState.new()

	assert_false(
		AiDiplomacyGates.buys_out(
			config, ai_state, PHASE_RIVAL, {}, AiPhasePlanner.PHASE_FRONTS, true
		),
		"the border front is the one war an overstretched court keeps"
	)
	assert_true(
		AiDiplomacyGates.buys_out(
			config, ai_state, PHASE_RIVAL, {}, AiPhasePlanner.PHASE_FRONTS, false
		),
		"a front the army cannot reach is still sold"
	)
	ai_state.economy_for(PHASE_OWNER).treasury = _muster_price(config) - 100
	assert_false(
		AiDiplomacyGates.buys_out(
			config, ai_state, PHASE_RIVAL,
			{"regiments": {PHASE_OWNER: 1}}, AiPhasePlanner.PHASE_FRONTS, true
		),
		"the purse leg stands down too: the army it banks for storms next door"
	)


## A poor court at two crown wars: `borders` puts the crown it means to fight
## (`PHASE_RIVAL`) on its own frontier, and without it that crown sits behind
## another's land. The purse is under the muster price either way.
func _border_front_turn(borders: bool) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(1)
	for other: int in [PHASE_RIVAL, PHASE_THIRD]:
		state.ensure_relation(PHASE_OWNER, other, 1)
		state.relation(PHASE_OWNER, other).score = 10.0
		_phase_war(state, other)
	var config: AiConfig = _phase_config(PHASE_OWNER)
	var ai_state := AiState.new()
	ai_state.economy_for(PHASE_OWNER).treasury = _muster_price(config) - 100
	var posture: String = AiPhasePlanner.phase_for(config, state)
	var context: Dictionary = {
		"power": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1},
		"regiments": {PHASE_OWNER: 4, PHASE_RIVAL: 1, PHASE_THIRD: 1},
		"ships": {PHASE_OWNER: 2},
		"player": -1,
		"posture": posture,
	}
	var owners: Array[int] = [PHASE_OWNER, PHASE_OWNER, PHASE_RIVAL, PHASE_MINOR]
	if not borders:
		owners = [PHASE_OWNER, PHASE_MINOR, PHASE_MINOR, PHASE_RIVAL]
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, AiFixture.land_world(owners), 30, context
	)
	return {"plan": plan, "posture": posture, "state": state, "config": config}


## The planner's own reading: an overstretched court short of its muster keeps
## the crown on its frontier — the war its field army can prosecute — and puts
## the white peace to the front it cannot reach instead (issue #995).
func test_an_overstretched_court_keeps_the_front_it_can_march_on() -> void:
	var near: Dictionary = _border_front_turn(true)
	var far: Dictionary = _border_front_turn(false)
	var kept: Dictionary = _candidate(near["plan"], PHASE_RIVAL)
	var sold: Dictionary = _candidate(far["plan"], PHASE_RIVAL)

	assert_eq(String(near["posture"]), AiPhasePlanner.PHASE_FRONTS)
	assert_true(bool(kept.get("border_front", false)))
	assert_eq(
		String(kept.get("blocked", "")), "war still worth waging",
		"the border front is not bought out: the army storms next door"
	)
	assert_false(
		String(far["posture"]) != AiPhasePlanner.PHASE_FRONTS
		or bool(sold.get("border_front", false)),
		"the far world keeps the same footing with no border to keep"
	)
	assert_eq(
		String(sold.get("blocked", "")), "",
		"a crown behind another's land is still sold"
	)
	assert_eq(
		int((far["plan"]["action"] as Dictionary).get("target", -1)), PHASE_RIVAL,
		"the peace goes to the front the court cannot reach"
	)
	assert_false(
		int((near["plan"]["action"] as Dictionary).get("target", -1)) == PHASE_RIVAL,
		"the kept front is never the pair the court sues"
	)


## The answering half: the same overstretched court signs a white peace from a
## crown it cannot reach, and answers the crown on its own frontier with its
## stance instead (issue #995). A refusal is the court's own word, never a rule.
func test_the_overstretched_answer_keeps_the_border_front() -> void:
	var near: Dictionary = _border_front_turn(true)
	var far: Dictionary = _border_front_turn(false)
	var ai_state := AiState.new()
	# The answering court is the war it declared: one agenda for both worlds, so
	# only the border read can tell the two answers apart.
	ai_state.agendas[PHASE_OWNER] = AiAgenda.WARMONGER

	assert_eq(
		AiTurnApply.peace_answer(
			near["state"], _border_front_world(true), ai_state,
			PHASE_RIVAL, PHASE_OWNER, 30, PHASE_SEED, {}
		),
		DiplomacyRules.DECISION_REFUSE,
		"the crown next door is answered by the stance, never signed away"
	)
	assert_eq(
		AiTurnApply.peace_answer(
			far["state"], _border_front_world(false), ai_state,
			PHASE_RIVAL, PHASE_OWNER, 30, PHASE_SEED, {}
		),
		DiplomacyRules.DECISION_AUTO,
		"the front the army cannot reach is taken as published"
	)


## The two worlds `_border_front_turn` reads, kept in one place so the planner
## and the answering pass cannot test different maps.
func _border_front_world(borders: bool) -> WorldMap:
	if borders:
		return AiFixture.land_world(
			[PHASE_OWNER, PHASE_OWNER, PHASE_RIVAL, PHASE_MINOR]
		)
	return AiFixture.land_world([PHASE_OWNER, PHASE_MINOR, PHASE_MINOR, PHASE_RIVAL])


# --- money first: the goal a court reads before its planners ------------------


## The court's purse at one balance; `PlayerEconomy.starting()` carries the
## workers and stores a running court has.
func _purse(treasury: int) -> PlayerEconomy:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


func test_a_court_short_of_its_muster_reads_earn() -> void:
	var config: AiConfig = _phase_config()
	var thin: PlayerEconomy = _purse(1200)
	var plan: Dictionary = AiIncome.plan(config, thin, true, 1)

	assert_eq(String(plan["goal"]), AiIncome.GOAL_EARN)
	assert_eq(
		int(plan["reserve"]), AiArmyReinforce.muster_floor(config, thin, 1, true),
		"the reserve is the muster the court is saving for"
	)
	assert_eq(int(plan["treasury"]), 1200)
	assert_eq(int(plan["regiments"]), 1)
	assert_eq(AiIncome.label(String(plan["goal"])), "earning")
	assert_true(AiIncome.wants_income(config, thin, true, 1))


func test_a_court_that_can_pay_plays_as_published() -> void:
	var config: AiConfig = _phase_config()
	var rich: PlayerEconomy = _purse(8000)

	assert_eq(AiIncome.goal_for(config, rich, true, 1), AiIncome.GOAL_SPEND)
	assert_eq(AiIncome.label(AiIncome.GOAL_SPEND), "spending")
	assert_false(AiIncome.wants_income(config, rich, true, 1))


func test_a_court_at_peace_keeps_only_its_cash_floor() -> void:
	# The bench measured the peace-time muster reserve: it traded 23 provinces
	# for a standing army (DR-20261113-22), so only a war holds the war chest.
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(1000)
	var target: int = config.parameter("army.regiment_target")

	assert_eq(
		AiIncome.reserve(config, economy, false, 0),
		config.parameter("economy.min_treasury"),
		"a court at peace grows: only its own floor is held back"
	)
	assert_eq(
		AiIncome.reserve(config, economy, false, target),
		config.parameter("economy.min_treasury")
	)
	assert_eq(
		AiIncome.goal_for(config, economy, false, 0), AiIncome.GOAL_SPEND,
		"a thin purse at peace still spends"
	)


func test_a_stalled_war_chest_re_routes_the_reserve() -> void:
	# The deferred-aim escalation (#603): a muster the court has stalled on for
	# the escalation bar's turns drops the war chest out of the reserve, so the
	# court's own income planners lead again instead of freezing behind a chest
	# it cannot reach. Below the bar the chest stands as published.
	var config: AiConfig = _phase_config()
	var thin: PlayerEconomy = _purse(300)
	var floor: int = config.parameter("economy.min_treasury")
	var bar: int = config.parameter("ledger.escalate_turns")
	var chest: int = AiArmyReinforce.muster_floor(config, thin, 1, true)
	assert_true(chest > floor, "the war chest is the muster the court saves for")

	assert_eq(
		AiIncome.reserve(config, thin, true, 1), chest,
		"below the bar the court still banks for its regiment"
	)
	assert_eq(
		AiIncome.reserve(config, thin, true, 1, 0, -1, bar - 1), chest,
		"one turn short of the bar changes nothing"
	)
	assert_eq(
		AiIncome.reserve(config, thin, true, 1, 0, -1, bar), floor,
		"a stalled chest re-routes to the cash floor"
	)
	assert_eq(
		String(AiIncome.plan(config, thin, true, 1, 0, -1, bar)["goal"]),
		AiIncome.GOAL_EARN,
		"the re-routed court still reads its own purse first"
	)


func test_a_stalled_chest_keeps_the_hull_chest_it_can_fill() -> void:
	# The hull chest keeps its own reach rule (#591) through the re-route: a
	# chest the purse already fills is the fleet's, one it cannot fill waits
	# behind the army (issue #484, #603).
	var config: AiConfig = _phase_config()
	var bar: int = config.parameter("ledger.escalate_turns")
	var rich: PlayerEconomy = _purse(6000)
	var thin: PlayerEconomy = _purse(300)
	var tech: String = ShipEconomy.tech_for("sloop")
	rich.tech_unlocked[tech] = true
	thin.tech_unlocked[tech] = true
	var chest: int = AiNavy.price(rich)
	assert_true(chest > 0, "the yard price is real")

	assert_eq(
		AiIncome.reserve(config, rich, true, 1, chest, -1, bar), chest,
		"a reachable hull chest survives the re-route"
	)
	assert_eq(
		AiIncome.reserve(config, thin, true, 1, chest, -1, bar),
		config.parameter("economy.min_treasury"),
		"an unreachable hull chest never outmuscles the cash floor"
	)


func test_a_peaceful_court_in_reach_banks_its_war_chest() -> void:
	# At peace the war chest is kept only once the purse already holds the
	# cheapest line's own price (wiki: ai-architecture § Land reinforcement):
	# a poorer court grows, and a court in reach banks the last of the chest
	# instead of auctioning it away the turn peace opens (issue #603).
	var config: AiConfig = _phase_config()
	var floor: int = config.parameter("economy.min_treasury")
	var price: int = AiArmyReinforce.cheapest_line_price(_purse(0))
	assert_true(price > 0, "the techs open a line to save for")

	assert_eq(
		AiIncome.reserve(config, _purse(price - 1), false, 1), floor,
		"below the line's own price the court grows"
	)
	assert_eq(
		AiIncome.reserve(config, _purse(price), false, 1),
		AiArmyReinforce.muster_floor(config, _purse(price), 1, false),
		"in reach the chest stands: the last ducats are not auctioned"
	)


func test_a_court_short_of_the_bar_banks_at_peace() -> void:
	# The bank-then-blitz lever (issue #995): while a court stands short of
	# the bar with an army still under target, the conquest shortfall — not
	# the war — keeps the muster chest in the reserve, so a court the buy-out
	# (#975) has left at peace still banks for the army that takes the
	# provinces it needs. The estates and the mines it raises on `earn` keep
	# the food and the income engine running while the purse fills.
	var config: AiConfig = _phase_config()
	var floor: int = config.parameter("economy.min_treasury")
	var chest: int = AiArmyReinforce.muster_floor(config, _purse(300), 1, true)
	var price: int = AiArmyReinforce.cheapest_line_price(_purse(0))
	assert_true(chest > floor and chest > price, "the chest is the war-target line")

	assert_eq(
		AiIncome.reserve(config, _purse(300), false, 1, 0, -1, 0, true), chest,
		"short of the bar the chest stands at peace, war or no war"
	)
	assert_eq(
		String(AiIncome.plan(config, _purse(300), false, 1, 0, -1, 0, true)["goal"]),
		AiIncome.GOAL_EARN,
		"the peaceful court banks instead of building behind a purse that never arms"
	)
	assert_eq(
		AiIncome.reserve(config, _purse(300), false, 1, 0, -1, 0, false), floor,
		"a court that has cleared the bar keeps the published peace"
	)
	assert_eq(
		AiIncome.reserve(
			config, _purse(300), false, config.parameter("army.regiment_target"),
			0, -1, 0, true
		), chest,
		"the bank holds past the peace target: the reserve prices the war chest"
	)
	assert_eq(
		AiIncome.reserve(
			config, _purse(300), false,
			config.parameter("army.regiment_target") + config.parameter("army.war_extra"),
			0, -1, 0, true
		), floor,
		"the bank ends at the war target: no muster due, no chest"
	)


func test_the_escalation_valve_still_re_routes_the_bank() -> void:
	# The #603 safety valve survives the bank untouched (issue #995's own
	# acceptance line): a stalled war chest still re-routes to the cash floor
	# so the court's income planners lead again — and the bar reads two turns
	# so a fill that reaches new lows every turn never counts as a stall.
	var config: AiConfig = _phase_config()
	var floor: int = config.parameter("economy.min_treasury")
	var bar: int = config.parameter("ledger.escalate_turns")
	var chest: int = AiArmyReinforce.muster_floor(config, _purse(300), 1, true)

	assert_eq(
		AiIncome.reserve(config, _purse(300), false, 1, 0, -1, bar - 1, true), chest,
		"a bank that is still moving keeps its chest"
	)
	assert_eq(
		AiIncome.reserve(config, _purse(300), true, 1, 0, -1, bar, false), floor,
		"a stalled chest at no gap still re-routes to the cash floor"
	)


func test_below_bar_reads_the_win_bar() -> void:
	# The gap the bank rides on (issue #995) is `VictoryRules`' own bar: the
	# published 31 Old World provinces, whatever the court's footing is.
	assert_true(
		AiVictoryPressure.below_bar(
			AiFixture.world(_owners(PHASE_OWNER, 15)), PHASE_OWNER, MapModel.NO_ID
		),
		"a court short of the bar carries the gap"
	)
	assert_false(
		AiVictoryPressure.below_bar(
			AiFixture.world(_owners(PHASE_OWNER, VictoryRules.MILITARY_THRESHOLD)),
			PHASE_OWNER, MapModel.NO_ID
		),
		"a court at the bar carries none"
	)
	assert_false(
		AiVictoryPressure.below_bar(null, PHASE_OWNER, MapModel.NO_ID),
		"a session with no world reads no gap"
	)


func test_the_bank_read_is_the_gap_the_host_and_the_purse() -> void:
	# The conquest bank's canonical read (issue #995): the win-bar gap, the
	# host under the war-time target, and the purse one line-cycle short of
	# the chest — never the money goal, which wobbles on the re-route cycle.
	var config: AiConfig = _phase_config()
	var state := AiState.new()
	var row: Dictionary = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	assert_true(
		AiIncome.banking(config, state, row),
		"short of the bar, under host, one cycle short of the chest"
	)
	row["treasury"] = 5000
	assert_false(AiIncome.banking(config, state, row), "a purse past the cycle spends as published")
	row["treasury"] = 600
	row["conquest_gap"] = false
	assert_false(AiIncome.banking(config, state, row), "a court at the bar banks no bank")
	row["conquest_gap"] = true
	row["regiments"] = (
		config.parameter("army.regiment_target") + config.parameter("army.war_extra")
	)
	assert_false(AiIncome.banking(config, state, row), "a court at host strength banks no bank")
	# The bank reads the chest the income row stamps, never the wobbling goal
	# reserve (issue #995): the #603 valve re-routes the goal's own reserve to
	# the cash floor while the fill stands still, and a bank that released at
	# the peak of its own fill unpinned the college and burned the margin it
	# was holding for — the row's canonical chest keeps the bank through the
	# wobble, exactly as the DR's own "never the wobbling money goal" promises.
	var price: int = AiArmyReinforce.cheapest_line_price(state.economy_for(0))
	var wobbled: Dictionary = {
		"goal": AiIncome.GOAL_SPEND, "reserve": 500, "bank_chest": 2200,
		"treasury": 500 + price - 1, "regiments": 1, "conquest_gap": true,
	}
	assert_true(
		AiIncome.banking(config, state, wobbled),
		"a purse the wobbling goal calls spare still banks against the chest"
	)
	wobbled["treasury"] = 2200 + price
	assert_false(
		AiIncome.banking(config, state, wobbled),
		"a purse past the chest and the line spends as published"
	)
	assert_eq(
		int(
			AiIncome.plan(
				config, _purse(300), false, 1, 0, -1, config.parameter(
					"ledger.escalate_turns"
				), true
			)["bank_chest"]
		),
		AiIncome.reserve(config, _purse(300), false, 1, 0, -1, 0, true),
		"the row stamps the canonical chest beside the re-routed goal"
	)


func test_a_court_with_no_ledger_keeps_the_published_behaviour() -> void:
	assert_eq(AiIncome.reserve(_phase_config(), null, true, 0), 0)
	assert_eq(AiIncome.goal_for(_phase_config(), null, true, 0), AiIncome.GOAL_SPEND)
	assert_eq(AiIncome.label(""), "spending", "an unknown goal reads as the published one")


func test_an_earning_court_funds_no_study() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(1200)
	var reserve: int = AiIncome.reserve(config, economy, true, 1)

	assert_eq(AiResearchPlanner.funding_for(config, economy, reserve), "none")
	assert_ne(
		AiResearchPlanner.funding_for(config, _purse(reserve + 1000), reserve), "none",
		"the surplus above the reserve funds the study"
	)


func test_an_earning_court_bids_no_imports() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(1200)
	var reserve: int = AiIncome.reserve(config, economy, true, 1)
	var market := WorldMarket.with_default_prices()

	assert_true(reserve > economy.treasury, "the purse is short of the reserve")
	var plan: Dictionary = AiMarketPlanner.plan(
		config, economy, market, 6, {}, {}, {}, reserve
	)
	assert_true((plan["bids"] as Array).is_empty(), "the reserve is not the auction's to spend")


## The build inputs are a saving court's own works provisioning, not a
## deferrable import: they bid out of the works purse (the cash the court's
## cash floor leaves), so a court saving for a muster or a yard still raises
## the estates its cash floor can pay for — the wiki's own words for a poorer
## court: it keeps its ordinary cash floor and grows, research and works first
## (ai-architecture § Land reinforcement; #878).
func test_a_saving_court_bids_its_works_feedstock() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0, "steel": 0, "bronze": 0},
		3000
	)
	var market := WorldMarket.with_default_prices()
	var chest: int = 2400
	var works_floor: int = config.parameter("economy.min_treasury")

	var plan: Dictionary = AiMarketPlanner.plan(
		config, economy, market, 20, {}, {"lumber": 4}, {}, chest, 0, true, true,
		works_floor
	)
	var bought: Array = plan["bids"]
	assert_true(bought.size() >= 1, "the works feedstock is bid for")
	var spend: int = 0
	var feedstock: bool = false
	for raw: Variant in bought:
		var bid: Dictionary = raw
		spend += int(bid["quantity"]) * int(market.price(String(bid["commodity"])))
		feedstock = feedstock or String(bid["commodity"]) == "castIron"
	assert_true(feedstock, "the feedstock the estates spend is among the bids")
	assert_true(
		spend <= economy.treasury - works_floor,
		"the works purse never dips past the cash floor"
	)


## The war footing's slot keeps the feedstock: a saving court at war bids the
## build inputs beside the rows its commitments claim, because without them the
## estates never rise and the chest is never filled (DR-20261117-01; #878).
func test_a_saving_court_at_war_bids_its_feedstock() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(1200)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		config, economy, market, 20, {}, {}, {}, 2400, 0, true, false,
		config.parameter("economy.min_treasury")
	)
	assert_true(
		(plan["bids"] as Array).size() >= 1,
		"the works feedstock is one of the commitments the slot keeps"
	)
	var rich: Dictionary = AiMarketPlanner.plan(
		config, _purse(6000), market, 20, {}, {}, {}, 2400, 0, false, false
	)
	assert_true(
		(rich["bids"] as Array).is_empty(),
		"a spending court still buys only what its commitments claim"
	)


# --- the fleet claim: the hull a court saves for (issue #484) ----------------


## A court with no fighting hull, or one outmatched at sea, means to lay one
## down; a fleet that matches its enemies has nothing to save for.
func test_the_fleet_claim_reads_the_war_and_the_odds_at_sea() -> void:
	var economy: PlayerEconomy = _purse(0)
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true

	assert_true(AiNavy.due(false, 0, 5), "no fighting hull: rebuild even at peace")
	assert_true(AiNavy.due(true, 0, 0), "a court at war with no fighting hull wants one")
	assert_true(AiNavy.due(true, 1, 2), "outmatched at sea, it wants one too")
	assert_false(AiNavy.due(true, 2, 2), "a fleet that matches its enemies holds")
	assert_false(AiNavy.due(false, 2, 5), "at peace with hulls, no yard claim")
	assert_eq(AiNavy.chest(true, 2, 2, economy), 0, "and reserves nothing for the yard")
	assert_eq(
		AiNavy.chest(false, 0, 3, economy), ShipEconomy.treasury_cost("sloop"),
		"peace still reserves the yard when no fighting hull remains"
	)


## Issue #484: a court that already flies a sloop may rebuild it without
## Navigation — the craft is aboard — so the chest opens at once.
func test_a_court_that_flies_a_sloop_can_rebuild_it_without_navigation() -> void:
	var economy: PlayerEconomy = _purse(0)
	var flown: Array[String] = ["sloop"]
	assert_eq(AiNavy.saving_type(economy, flown), "sloop")
	assert_eq(AiNavy.unlock_tech(economy, flown), "", "already flown, no door")
	assert_eq(
		AiNavy.chest(true, 0, 1, economy, flown), ShipEconomy.treasury_cost("sloop"),
		"the chest opens without the tech unlock"
	)
	assert_true(ShipEconomy.buildable("sloop", {}, flown))


## Issue #484: shipcraft remembers a lost last sloop so the yard stays open.
func test_shipcraft_remembers_a_lost_sloop() -> void:
	var economy: PlayerEconomy = _purse(0)
	economy.note_shipcraft(["sloop"])
	assert_true(economy.shipcraft.has("sloop"))
	assert_true(ShipEconomy.buildable("sloop", {}, economy.shipcraft))
	assert_eq(AiNavy.unlock_tech(economy, economy.shipcraft), "")
	assert_eq(
		AiNavy.chest(false, 0, 0, economy, economy.shipcraft),
		ShipEconomy.treasury_cost("sloop")
	)


## The chest is the yard row of the cheapest warship: a type the court's techs
## already open, else the catalog's cheapest so the court saves while it studies
## the unlock (issue #484).
func test_the_yard_price_is_the_cheapest_warship_the_techs_open() -> void:
	var economy: PlayerEconomy = _purse(0)

	assert_eq(AiNavy.saving_type(economy), "sloop", "the catalog names the hull it means to lay")
	assert_eq(AiNavy.price(economy), ShipEconomy.treasury_cost("sloop"))
	assert_eq(
		AiNavy.chest(true, 0, 1, economy), 0,
		"no chest while the unlock is still shut — research must be able to pay"
	)
	assert_eq(
		AiNavy.unlock_tech(economy), "superior_hull_design",
		"Navigation's prerequisite is the first door"
	)

	economy.tech_unlocked["superior_hull_design"] = true
	assert_eq(AiNavy.unlock_tech(economy), ShipEconomy.tech_for("sloop"))
	assert_eq(AiNavy.chest(true, 0, 1, economy), 0, "still shut until Navigation lands")
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	assert_eq(AiNavy.saving_type(economy), "sloop")
	assert_eq(AiNavy.unlock_tech(economy), "", "open, so research walks no navy door")
	assert_eq(AiNavy.chest(true, 0, 1, economy), ShipEconomy.treasury_cost("sloop"))

	economy.tech_unlocked[ShipEconomy.tech_for("frigate")] = true
	assert_eq(AiNavy.saving_type(economy), "sloop", "the cheapest row is the one it saves for")


## A hull the court can already pay for outranks the muster: the purse is the
## fleet's, the army waits (issue #484). A ducat short with fighting hulls still
## afloat, the unaffordable chest yields to the muster (#591).
func test_a_court_saving_for_a_hull_reserves_the_yard_price() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(4600)
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var chest: int = AiNavy.chest(true, 1, 2, economy)
	var muster: int = AiArmyReinforce.muster_floor(config, economy, 1, true)

	assert_true(chest > muster, "the hull is the larger commitment")
	var plan: Dictionary = AiIncome.plan(config, _purse(chest), true, 1, chest, 1)
	assert_eq(String(plan["goal"]), AiIncome.GOAL_SPEND, "the chest is in hand: it may spend")
	assert_eq(int(plan["reserve"]), chest, "the reserve is the hull, not the muster")
	assert_eq(int(plan["hull_chest"]), chest)
	var short: Dictionary = AiIncome.plan(config, _purse(chest - 1), true, 1, chest, 1)
	assert_eq(int(short["reserve"]), muster, "a ducat short, the yard's price is not the reserve")
	assert_eq(String(short["goal"]), AiIncome.GOAL_SPEND, "so the court is not frozen on earn")
	assert_eq(
		AiIncome.reserve(config, economy, true, 1), muster,
		"with no fleet claim the muster is the whole reserve"
	)


## Issue #591: an outmatched court that still has a fighting hull does not freeze
## the purse on an unaffordable yard price — the muster it can pay for leads.
func test_a_chest_the_court_cannot_fill_waits_behind_the_muster() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(4600)
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var chest: int = AiNavy.chest(true, 1, 2, economy)
	var muster: int = AiArmyReinforce.muster_floor(config, economy, 1, true)

	assert_eq(AiIncome.hull_held(config, economy, true, 1, chest, 1), 0, "the yard holds nothing")
	assert_eq(
		AiIncome.reserve(config, economy, true, 1, chest, 1), muster,
		"a court under its target saves for the regiment it can raise"
	)
	var plan: Dictionary = AiIncome.plan(config, economy, true, 1, chest, 1)
	assert_eq(int(plan["reserve"]), muster)
	assert_eq(int(plan["hull_chest"]), chest, "the yard's price is still the reading")

	# Once the line stands at target the yard takes the purse back, even though
	# the chest is still out of reach: there is no regiment left to starve.
	var at_target: int = config.parameter("army.regiment_target") + config.parameter(
		"army.war_extra"
	)
	assert_eq(
		AiIncome.hull_held(config, economy, true, at_target, chest, 1), chest,
		"a court at target saves for its hull again"
	)
	# A hull its techs never open is no claim at all.
	assert_eq(AiIncome.hull_held(config, economy, true, 1, 0, 1), 0)
	assert_eq(AiIncome.hull_held(null, economy, true, 1, chest, 1), chest, "no config, no claim")
	# Fleetless rebuild holds the chest even under the muster (#484).
	assert_eq(AiIncome.hull_held(config, economy, true, 1, chest, 0), chest)
	assert_eq(
		AiIncome.reserve(config, economy, false, 1, chest, 0), chest,
		"at peace a lost last sloop still reserves the yard"
	)


## The muster reads the same rule: a chest it cannot fill is not the army's
## ceiling when fighting hulls remain, so the regiment it can pay for is raised
## (issue #591).
func test_the_muster_spends_a_chest_it_cannot_fill() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(4600)
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var chest: int = AiNavy.chest(true, 1, 2, economy)
	var plan: Dictionary = AiArmyReinforce.plan(config, economy, 1, true, 0, -1, chest)

	assert_eq(
		String(plan["muster"]), AiArmyReinforce.saving_type(config, economy),
		"the line the court can pay for is raised"
	)
	assert_false((plan["reasons"] as Array).has("saving for a hull"))


## Issue #603: the yard's chest re-routes like the war chest. A court that has
## stalled on `navy.build` past the escalation bar while a regiment is due and
## its chest is already in hand stops holding the purse for a hull it never
## lays — the measured deadlock is a court 98 ducats short of a sloop that
## cannot buy the 320-ducat row of the regiment whose chest sits inside that
## same purse.
func test_a_stalled_yard_chest_yields_to_the_muster() -> void:
	var economy: PlayerEconomy = _purse(0)
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var price: int = ShipEconomy.treasury_cost("sloop")

	# Fleetless: the #484 rebuild chest, held while the yard is still moving.
	assert_eq(AiNavy.chest(true, 0, 1, economy), price)
	assert_eq(AiNavy.chest(true, 0, 1, economy, [], false), price, "the yard still leads")
	# Stalled past the bar with the regiment's chest in hand: it stands down.
	assert_eq(AiNavy.chest(true, 0, 1, economy, [], true), 0)
	# A court with fighting hulls keeps the published reading either way.
	assert_eq(AiNavy.chest(true, 2, 2, economy, [], true), 0, "no hull due at all")


## Issue #1275: the yield valve is not one-way. A line the court no longer
## owes — no spare hand, so the muster prices no row — releases the chest:
## the fill the stand-down freed has closed the muster, and the yard reads as
## published. A fill the court is winning (the shortfall below the stall's
## own best gap) keeps its chest reachable too — the wiki's "the shortfall
## shrinking resumes it".
func test_the_yard_chest_resumes_when_the_line_closes() -> void:
	var play: PlaySession = _objective_session(_court())
	var ledger: PlayerEconomy = play.ledger_for(0)
	ledger.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var price: int = ShipEconomy.treasury_cost("sloop")
	# A fill standing still at war, a regiment due (the ledger keeps a spare
	# hand for the levy): the chest stands down. Two notes: the stall counts
	# its turns, and the bar reads two.
	var rows: Array = [{"id": "navy.build", "status": AiObjective.STATUS_DEFERRED,
		"shortfall": {"treasury": price}}]
	play.ai.note_objectives(0, {"objectives": rows}, play.turn)
	play.ai.note_objectives(0, {"objectives": rows}, play.turn + 1)
	ledger.treasury = 0
	assert_eq(MapPlayCourt.navy_chest(play, 0), 0, "a stalled fill behind a due line yields")

	# The line closes (no spare hand prices a row): the chest resumes.
	ledger.workers = WorkerPool.make(0)
	assert_eq(
		MapPlayCourt.navy_chest(play, 0), price,
		"the line is no longer due: the yard banks again"
	)

	# A fill the court is winning — the shortfall below the stall's best gap —
	# keeps its chest reachable even while a line stands due.
	ledger.workers = WorkerPool.make(6)
	rows[0]["shortfall"] = {"treasury": price - 1}
	play.ai.note_objectives(0, {"objectives": rows}, play.turn + 1)
	assert_eq(
		MapPlayCourt.navy_chest(play, 0), price,
		"a shrinking shortfall is not a stall — the chest stays reachable"
	)
	play.ship_layer.free()
	play.civilian_layer.free()




# --- victory pressure --------------------------------------------------------
## A court that can see the bar presses for it (wiki: ai-architecture § Notable
## strategic policies; DR-20261114-04): the reading, the thinner storm margin
## and the weight it puts on the war domains.


## `count` Old World provinces all held by `owner`.
func _owners(owner: int, count: int) -> Array[int]:
	var owners: Array[int] = []
	for _index in count:
		owners.append(owner)
	return owners


func test_a_court_far_from_the_bar_keeps_the_published_margin() -> void:
	var config: AiConfig = _phase_config()
	var read: Dictionary = AiVictoryPressure.read(
		AiFixture.world(_owners(PHASE_OWNER, 5)), PHASE_OWNER, MapModel.NO_ID, Difficulty.DEFAULT, config
	)

	assert_eq(String(read["stage"]), AiVictoryPressure.STAGE_FAR)
	assert_eq(int(read["holdings"]), 5)
	assert_eq(int(read["bar"]), VictoryRules.MILITARY_THRESHOLD)
	assert_eq(int(read["need"]), 26)
	assert_eq(int(read["share_mille"]), 161)
	assert_eq(
		int(read["extra_regiments"]), 0,
		"a court that cannot see the bar arms up as published"
	)
	assert_eq(int(read["boost_mille"]), AiVictoryPressure.NEUTRAL)
	assert_false(AiVictoryPressure.presses(String(read["stage"])))


func test_a_court_that_can_see_the_bar_presses_its_war() -> void:
	var config: AiConfig = _phase_config()
	var read: Dictionary = AiVictoryPressure.read(
		AiFixture.world(_owners(PHASE_OWNER, 21)), PHASE_OWNER, MapModel.NO_ID, Difficulty.DEFAULT, config
	)

	assert_eq(String(read["stage"]), AiVictoryPressure.STAGE_NEAR)
	assert_eq(int(read["share_mille"]), 677)
	assert_eq(int(read["need"]), 10)
	assert_eq(
		int(read["extra_regiments"]), config.parameter("victory.pressure_regiments"),
		"the endgame court arms up for the finish"
	)
	assert_eq(int(read["boost_mille"]), config.parameter("victory.pressure_boost"))
	assert_true(AiVictoryPressure.presses(String(read["stage"])))
	assert_eq(AiVictoryPressure.label(String(read["stage"])), "pressing for the bar")


func test_a_court_at_the_bar_reads_at_bar() -> void:
	var read: Dictionary = AiVictoryPressure.read(
		AiFixture.world(_owners(PHASE_OWNER, VictoryRules.MILITARY_THRESHOLD)),
		PHASE_OWNER, MapModel.NO_ID, Difficulty.DEFAULT, _phase_config()
	)

	assert_eq(String(read["stage"]), AiVictoryPressure.STAGE_AT_BAR)
	assert_eq(int(read["need"]), 0)
	assert_eq(int(read["share_mille"]), AiVictoryPressure.NEUTRAL)
	assert_true(AiVictoryPressure.presses(String(read["stage"])))


func test_the_press_reaches_the_war_aim_only_from_near_the_bar() -> void:
	var config: AiConfig = _phase_config()
	assert_eq(
		AiVictoryPressure.war_press(AiVictoryPressure.STAGE_FAR, config), 0,
		"a court that cannot see the bar wants no war for it"
	)
	assert_eq(
		AiVictoryPressure.war_press(AiVictoryPressure.STAGE_NEAR, config),
		config.parameter("victory.pressure_war")
	)
	assert_eq(
		AiVictoryPressure.war_press(AiVictoryPressure.STAGE_AT_BAR, config),
		config.parameter("victory.pressure_war")
	)
	assert_eq(AiVictoryPressure.war_press(AiVictoryPressure.STAGE_NEAR, null), 0)
	var read: Dictionary = AiVictoryPressure.read(
		AiFixture.world(_owners(PHASE_OWNER, 21)), PHASE_OWNER, MapModel.NO_ID,
		Difficulty.DEFAULT, config
	)
	assert_eq(
		int(read["war_press"]), config.parameter("victory.pressure_war"),
		"the reading hands the planner the press"
	)


## The press must reach the order, not only the score (issue #601): a court
## that does not outmatch the crown holding its land prices 25 against the
## declaration minimum of 51 and opens nothing, while the same pair with the
## press (30) clears the minimum and declares the war it needs.
func test_a_pressing_court_declares_the_war_it_needs() -> void:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(PHASE_OWNER, PHASE_RIVAL, 1)
	state.relation(PHASE_OWNER, PHASE_RIVAL).score = 40.0
	var world: WorldMap = AiFixture.world([PHASE_OWNER, PHASE_RIVAL])
	var context: Dictionary = {
		"power": {PHASE_OWNER: 84, PHASE_RIVAL: 100},
		"regiments": {PHASE_OWNER: 1, PHASE_RIVAL: 2},
		"ships": {PHASE_OWNER: 1, PHASE_RIVAL: 2},
		"player": -1,
	}
	var calm: Dictionary = AiDiplomacyPlanner.decide(
		_phase_config(), state, AiState.new(), world, 1, context
	)
	assert_eq(String(calm["candidates"][0]["blocked"]), "war desire too low")
	assert_ne(
		String((calm["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"a court far from the bar opens no finish it cannot reach"
	)
	var pressed_context: Dictionary = context.duplicate(true)
	pressed_context["victory_press"] = 30
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		_phase_config(), state, AiState.new(), world, 1, pressed_context
	)
	assert_eq(
		String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the press reaches the order that takes the land"
	)
	assert_eq(int(plan["action"]["target"]), PHASE_RIVAL)
	assert_eq(int(plan["candidates"][0]["factors"]["victory_press"]), 30)


func test_the_pressure_threshold_is_a_registry_knob() -> void:
	assert_eq(
		AiVictoryPressure.stage_for(21, 31, 677, 500), AiVictoryPressure.STAGE_NEAR
	)
	assert_eq(
		AiVictoryPressure.stage_for(21, 31, 677, 1000), AiVictoryPressure.STAGE_FAR,
		"a higher start holds the court off the bar"
	)
	assert_eq(AiVictoryPressure.stage_for(31, 31, 1000, 1000), AiVictoryPressure.STAGE_AT_BAR)
	assert_eq(AiVictoryPressure.share_mille(0, 0), 0, "no bar, no share")
	assert_eq(AiVictoryPressure.share_mille(40, 31), 1000, "a share never passes the whole")


func test_the_crown_reads_its_own_bar() -> void:
	var read: Dictionary = AiVictoryPressure.read(
		AiFixture.world(_owners(PHASE_OWNER, 21)), PHASE_OWNER, PHASE_OWNER, "hard", _phase_config()
	)

	assert_eq(int(read["bar"]), VictoryRules.crown_threshold("hard"))
	assert_eq(
		int(read["bar"]), VictoryRules.threshold_for(PHASE_OWNER, PHASE_OWNER, "hard"),
		"the human crown's bar carries the level"
	)


func test_a_session_with_no_world_reads_far() -> void:
	var read: Dictionary = AiVictoryPressure.read(
		null, PHASE_OWNER, MapModel.NO_ID, Difficulty.DEFAULT, _phase_config()
	)

	assert_eq(String(read["stage"]), AiVictoryPressure.STAGE_FAR)
	assert_eq(int(read["holdings"]), 0)
	assert_eq(int(read["bar"]), VictoryRules.MILITARY_THRESHOLD)
	assert_eq(int(read["extra_regiments"]), 0, "no world, no extra muster")


func test_the_pressure_scales_the_war_domains_only() -> void:
	var config: AiConfig = _phase_config()
	var phase: String = AiPhasePlanner.PHASE_PEACE
	var calm: Dictionary = AiPosture.modifiers(phase, config)
	var pressed: Dictionary = AiPosture.modifiers(
		phase, config, config.parameter("victory.pressure_boost")
	)

	assert_true(int(pressed["military"]) > int(calm["military"]), "the army leads")
	assert_true(int(pressed["naval"]) > int(calm["naval"]), "and the fleet with it")
	assert_true(int(pressed["expansion"]) > int(calm["expansion"]), "and the land it takes")
	assert_eq(int(pressed["economy"]), int(calm["economy"]), "the ledger keeps its weight")
	assert_eq(int(pressed["research"]), int(calm["research"]), "and so does the study")
	assert_eq(
		int(AiPosture.modifiers(phase, config, AiVictoryPressure.NEUTRAL)["military"]),
		int(calm["military"]), "a neutral boost changes nothing"
	)

# --- from test_ai_work_rules.gd ---
## Rival Builders, Engineers and the civilian dispatch.
## Rival Builders finish province towns that pay a manufacturing bonus, priced on
## the raw the crown actually gathers (wiki: extraction-and-improvements
## § Town manufacturing bonus; civilian-work-planner § Builders).
##
## The fixture is a colony of one town tile and two rail-linked timber estates:
## the estates are already fully improved, so the only legal work left is the
## town, and the whole question is whether the planner values it.
## Consolidated rulebook: AiBuilderWork + AiEngineerWork + AiCivilianDispatch
## + AiHospitalWork + AiTownRoads + AiArmyReinforce (one Godot boot per domain).

const TOWN: Vector2i = Vector2i(0, 0)
const TIMBER: Vector2i = Vector2i(1, 0)
const TIMBER_FAR: Vector2i = Vector2i(2, 0)


func _work_model(level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [TOWN, TIMBER, TIMBER_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Plantation", tiles, Vector2.ZERO, 3, 1)
	province.town_tile = TOWN
	province.town_development = level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [TIMBER, TIMBER_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model


func _work_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, TOWN)
	for tile: Vector2i in [TIMBER, TIMBER_FAR]:
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works


func _stockpile() -> Dictionary:
	return {"timber": 200, "lumber": 40, "castIron": 40}


func _plan(model: MapModel, context: Dictionary = {}) -> Dictionary:
	var builder: CivilianState = CivilianState.create(1, 1, "builder", TIMBER)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _work_works(model), _stockpile(),
		{"timber": 4}, {"national_bureaucracy": true}, context
	)


## The estates are finished, so the town is the only order left; a level-1 town
## that would pay 4 lumber a turn is worth more than idling the Builder.
func test_a_developing_town_becomes_the_builders_order() -> void:
	var plan: Dictionary = _plan(_work_model(1))
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), TOWN)


## An overseas province is priced on the tons the holds landed, not on the far
## shore's harvest: with nothing delivered the town pays nothing and is left.
func test_an_overseas_town_with_nothing_landed_is_left_alone() -> void:
	var plan: Dictionary = _plan(_work_model(1), {"delivered_raw": {}})

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())


func test_an_overseas_town_is_upgraded_from_the_tons_that_landed() -> void:
	var plan: Dictionary = _plan(_work_model(1), {"delivered_raw": {0: {"timber": 8}}})
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")


func test_a_finished_town_is_left_alone() -> void:
	assert_true((_plan(_work_model(CivilianWorkPlan.MAX_TOWN))["orders"] as Array).is_empty())


func test_the_bureaucracy_gate_still_refuses_the_order() -> void:
	var model: MapModel = _work_model(1)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", TIMBER)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _work_works(model), _stockpile(),
		{"timber": 4}, {}, {}
	)

	assert_true((plan["orders"] as Array).is_empty(), "no national_bureaucracy")


# --- a capital province, where the town caps its estates ----------------------

## A Great Power seat: the town's development caps what its estates may gather,
## so a Builder that raises an estate past the cap spends lumber and cast iron
## for nothing until the town rises (wiki: capital-and-connectivity § Town rule).
const SEAT: Vector2i = Vector2i(0, 0)
const SEAT_ESTATE: Vector2i = Vector2i(1, 0)
const SEAT_ESTATE_FAR: Vector2i = Vector2i(2, 0)


func _seat_model(town_level: int, estate_level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [SEAT, SEAT_ESTATE, SEAT_ESTATE_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Seat", tiles, Vector2.ZERO, 3, 1, true)
	province.town_tile = SEAT
	province.capital_tile = SEAT
	province.town_development = town_level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [SEAT_ESTATE, SEAT_ESTATE_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model


func _seat_works(model: MapModel, estate_level: int) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, SEAT)
	for tile: Vector2i in [SEAT_ESTATE, SEAT_ESTATE_FAR]:
		if estate_level > 0:
			works.set_improvement(model, tile, estate_level)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works


func _seat_plan(town_level: int, estate_level: int) -> Dictionary:
	var model: MapModel = _seat_model(town_level, estate_level)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", SEAT_ESTATE)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _seat_works(model, estate_level),
		{"timber": 2, "lumber": 40, "castIron": 40}, {"timber": 4},
		{"national_bureaucracy": true}
	)


## Stores are short of timber, but a level-1 estate in a level-1 seat gathers
## nothing more at level 2: the town is the order that pays, so the Builder
## raises the town instead of buying a dead estate level.
func test_a_town_capping_its_estates_is_raised_before_the_estate() -> void:
	var plan: Dictionary = _seat_plan(1, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT)


## Once the estate is fully improved the town is the only order left, and it is
## raised even though its manufactures are still short of one four-ton run: the
## estate levels it unlocks are what the Builder is buying.
func test_a_town_is_raised_for_the_estate_levels_it_unlocks() -> void:
	var plan: Dictionary = _seat_plan(1, LandWorks.MAX_IMPROVEMENT)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT)


## A developed town no longer caps its estates, so the Builder raises the estate
## at once — the cap read must not idle a court that can gather.
func test_a_developed_town_frees_the_estate_order() -> void:
	var plan: Dictionary = _seat_plan(CivilianWorkPlan.MAX_TOWN, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_improvement")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT_ESTATE)


## An estate held back by the town cap earns no shortage premium: an estate the
## crown can gather from wins the Builder even when its commodity is abundant.
func test_a_capped_estate_earns_no_shortage_premium() -> void:
	var row: Dictionary = {
		"tile": SEAT_ESTATE, "province": 0, "commodity": "timber", "level": 1,
		"tech_cap": 4, "terrain_cap": 4, "transport": 4, "town_cap": 1,
		"output": 1, "connected": true,
	}
	var open_row: Dictionary = row.duplicate()
	open_row["town_cap"] = 4
	open_row["output"] = 1

	assert_eq(AiBuilderWork.paid_gain(row), 0, "the town cap pays nothing more")
	assert_eq(AiBuilderWork.paid_gain(open_row), 1, "the next level pays")
	assert_eq(AiBuilderWork.town_unlocks([row], 0), 1, "the town unlocks one level")
	assert_eq(AiBuilderWork.town_unlocks([open_row], 0), 0, "a free estate unlocks nothing")


## The provision premium (issue #807): a court whose muster is due while its
## harvest cannot carry the mouths it has leads its Builders to the ration
## estates — the planner-level case below pins the split.


func test_a_muster_due_court_provisions_the_ration_estates() -> void:
	# Two transport-capped estates that read identically (zero gain, equal
	# shortage), one wool at the seat and one grain across the map: the tie
	# ranks the seat first, so only the premium moves the grain estate up.
	var model: MapModel = _hospital_model()
	model.resource[model.index_of(3, 1)] = 5
	model.resource[model.index_of(OUTER_TOWN.x, OUTER_TOWN.y)] = 4
	var works := LandWorks.new()
	for x in 5:
		works.set_transport(model, Vector2i(x, 1), LandWorks.TRANSPORT_ROAD)
	# Two level-1 estates the road's own transport caps: zero gain, so only the
	# provision premium can split them.
	works.set_improvement(model, Vector2i(3, 1), 1)
	works.set_improvement(model, OUTER_TOWN, 1)
	var unit: CivilianState = CivilianState.create(1, 0, "builder", CAPITAL)
	var provision: Dictionary = {"provision_food": true, "capital_tile": CAPITAL}
	var plain: Dictionary = {"capital_tile": CAPITAL}
	var stock: Dictionary = {"fabric": 10, "lumber": 20, "castIron": 20}
	var rationed: Dictionary = AiBuilderWork.best_candidate(
		AiWorkQuery.make(
			AiConfig.build(WORK_OWNER, 1500), model, unit, [unit], works, stock,
			{"grain": 2, "wool": 2}, {"land_enclosure": true}, provision, {}
		), {}, []
	)
	assert_eq(
		Vector2i(rationed["tile"]), OUTER_TOWN,
		"the ration estate leads the provision walk"
	)
	var seat: Dictionary = AiBuilderWork.best_candidate(
		AiWorkQuery.make(
			AiConfig.build(WORK_OWNER, 1500), model, unit, [unit], works, stock,
			{"grain": 2, "wool": 2}, {"land_enclosure": true}, plain, {}
		), {}, []
	)
	assert_eq(
		Vector2i(seat["tile"]), Vector2i(3, 1),
		"the flag off keeps the published order (the lower tile ranks first)"
	)


## The works' own feedstock (issue #878): every raise spends a lumber and a
## cast iron, and the manufactures are made from the raw the land yields. While
## the cast iron cannot pay the next raise, the iron estate that refills it
## leads the Builder — a court that spends its last cast iron on farms and
## never mines the iron freezes every estate it owns from then on.
func test_the_feedstock_source_leads_while_the_manufacture_is_short() -> void:
	var model: MapModel = _hospital_model()
	model.resource[model.index_of(3, 1)] = 4
	model.resource[model.index_of(OUTER_TOWN.x, OUTER_TOWN.y)] = 1
	var works := LandWorks.new()
	for x in 5:
		works.set_transport(model, Vector2i(x, 1), LandWorks.TRANSPORT_ROAD)
	works.set_prospected(0, model, OUTER_TOWN)
	var unit: CivilianState = CivilianState.create(1, 0, "builder", CAPITAL)
	var context: Dictionary = {"capital_tile": CAPITAL}
	var caps: Dictionary = {"grain": 2, "wool": 2, "iron": 2, "timber": 2}
	var fat: Dictionary = {"fabric": 10, "lumber": 20, "castIron": 20}
	var short: Dictionary = {"fabric": 10, "lumber": 20, "castIron": 1}

	var farm: Dictionary = AiBuilderWork.best_candidate(
		AiWorkQuery.make(
			AiConfig.build(WORK_OWNER, 1500), model, unit, [unit], works, fat,
			caps, {"land_enclosure": true, "iron_mining": true}, context, {}
		), {}, []
	)
	assert_eq(
		Vector2i(farm["tile"]), Vector2i(3, 1),
		"a fed cast-iron store leaves the published order"
	)
	var mine: Dictionary = AiBuilderWork.best_candidate(
		AiWorkQuery.make(
			AiConfig.build(WORK_OWNER, 1500), model, unit, [unit], works, short,
			caps, {"land_enclosure": true, "iron_mining": true}, context, {}
		), {}, []
	)
	assert_eq(
		Vector2i(mine["tile"]), OUTER_TOWN,
		"the iron estate leads while the cast iron cannot pay the next raise"
	)


## Riches clear straight to the treasury, so a worked mine is the income the
## workshop's crops cannot bring: a mine leads a crop nobody is short of, and a
## raw the workshop wants still leads the mine (wiki: commodity-catalog
## § Riches and treasury; issue #1382).
func test_a_mine_leads_a_crop_nobody_is_short_of() -> void:
	var model: MapModel = _hospital_model()
	model.resource[model.index_of(3, 1)] = 4
	model.resource[model.index_of(OUTER_TOWN.x, OUTER_TOWN.y)] = 3
	var works := LandWorks.new()
	for x in 5:
		works.set_transport(model, Vector2i(x, 1), LandWorks.TRANSPORT_ROAD)
	works.set_prospected(0, model, OUTER_TOWN)
	var unit: CivilianState = CivilianState.create(1, 0, "builder", CAPITAL)
	var context: Dictionary = {"capital_tile": CAPITAL}
	var caps: Dictionary = {"grain": 2, "wool": 2, "gold": 2, "timber": 2}
	var fed: Dictionary = {"fabric": 10, "lumber": 20, "castIron": 20, "grain": 20}

	var mine: Dictionary = AiBuilderWork.best_candidate(
		AiWorkQuery.make(
			AiConfig.build(WORK_OWNER, 1500), model, unit, [unit], works, fed,
			caps, {"land_enclosure": true, "gold_mining": true}, context, {}
		), {}, []
	)
	assert_eq(
		Vector2i(mine["tile"]), OUTER_TOWN,
		"the mine leads a crop nobody is short of"
	)
	var short: Dictionary = {"fabric": 10, "lumber": 20, "castIron": 20, "grain": 0}
	var farm: Dictionary = AiBuilderWork.best_candidate(
		AiWorkQuery.make(
			AiConfig.build(WORK_OWNER, 1500), model, unit, [unit], works, short,
			caps, {"land_enclosure": true, "gold_mining": true}, context, {}
		), {}, []
	)
	assert_eq(
		Vector2i(farm["tile"]), Vector2i(3, 1),
		"a raw the workshop is short of still leads the mine"
	)


## Rival Engineer policy after it left the civilian dispatcher
## (wiki: civilian-work-planner § Engineer; capital-and-connectivity;
## civilian-units § Engineer, § Rail Builder). These cases pin the split: the
## Engineer module owns the roads, the harbour and the wartime fort, while a
## rail is the Rail Builder's own work.

const Engineer = preload("res://scripts/ai/ai_engineer_work.gd")

const BARE: Vector2i = Vector2i(0, 0)


func _context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": BARE,
		"at_war": at_war,
	}


func _engineer_order(model: MapModel, works: LandWorks, at_war: bool = false) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", BARE)
	return Engineer.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, {}, _context(at_war), {}
	))


## Every owned tile improved and ported, so the only work left is transport.
func _engineer_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	return works


func test_a_road_still_reaches_a_resource_without_one() -> void:
	var model: MapModel = CivilianFixture.build()
	var order: Dictionary = _engineer_order(model, _engineer_works(model))
	assert_eq(String(order.get("action", "")), "build_road")
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_ne(model.resource_at(tile.x, tile.y), MapModel.NO_ID, "the road reaches a resource")


func test_a_coastal_province_without_a_port_gets_one() -> void:
	var model: MapModel = CivilianFixture.build()
	for tile: Vector2i in model.provinces[0].tiles:
		model.resource[model.index_of(tile.x, tile.y)] = MapModel.NO_ID
	var order: Dictionary = _engineer_order(model, LandWorks.new())
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_eq(String(order.get("action", "")), "build_port")
	assert_true(MapGeo.is_coastal_tile(model, tile.x, tile.y), "a port only rises on the coast")


func test_an_invaded_court_prices_its_fort_with_wartime_urgency() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", BARE)
	var fort: Dictionary = Engineer.fort_candidate(_work_query(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, {}, _context(true), {}
	))
	var road: Dictionary = _engineer_order(model, works)
	assert_eq(String(fort.get("action", "")), "build_fort")
	assert_eq(Vector2i(fort["tile"]), FortRules.site_tile(model, CivilianFixture.PLAYER_PROVINCE))
	# An invaded court prices its fort above its other works as a floor: the fort
	# weight plus the wartime urgency, whatever the hinterland still owes.
	var weight: int = AiConfig.build(0, 1500).parameter("civilian.fort_weight")
	assert_true(int(fort["score"]) >= weight + 50, "the fort carries its wartime urgency")
	assert_eq(String(road.get("action", "")), "build_road")


func test_the_engineer_never_offers_a_rail() -> void:
	var model: MapModel = CivilianFixture.build()
	var works: LandWorks = _engineer_works(model)
	works.set_transport(model, CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	for at_war: bool in [false, true]:
		var order: Dictionary = _engineer_order(model, works, at_war)
		assert_ne(String(order.get("action", "")), "build_rail", "a rail is the Rail Builder's work")


func test_no_engineer_work_without_a_config() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", BARE)
	assert_true(Engineer.best_candidate(_work_query(
		null, model, unit, [unit] as Array, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context(), {}
	)).is_empty())


## The civilian dispatcher after the Engineer policy left it
## (wiki: civilian-work-planner). These cases pin the seam: a Rail Builder is
## routed to the Engineer module, and a rail is only offered once its crown can
## lay one, so every action the dispatcher emits is one the unit may work.

const Planner = preload("res://scripts/ai/ai_civilian_planner.gd")

const DISPATCH_BARE: Vector2i = Vector2i(0, 0)
const RAIL_TECHS: Dictionary = {"early_steam_engine": true}


func _dispatch_context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": DISPATCH_BARE,
		"at_war": at_war,
	}


func _dispatch_plan(model: MapModel, unit: CivilianState, works: LandWorks) -> Dictionary:
	return Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, RAIL_TECHS, _dispatch_context()
	)


func _roaded_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	works.set_transport(model, CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	return works


func test_a_rail_builder_lays_a_rail_on_an_existing_road() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = _dispatch_plan(model, unit, _roaded_works(model))
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1, "the Engineer policy answers for a Rail Builder")
	assert_eq(String(orders[0]["action"]), "build_rail")
	assert_eq(Vector2i(orders[0]["tile"]), CivilianFixture.TIMBER_TILE)


func test_a_rival_without_steam_never_orders_a_rail() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, _roaded_works(model),
		CivilianFixture.stockpile(), {}, {}, _dispatch_context()
	)
	for order: Dictionary in plan["orders"]:
		assert_ne(String(order["action"]), "build_rail", "no rail without its tech")


func test_every_dispatched_order_is_a_work_the_unit_may_do() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for type_id: String in ["builder", "engineer", "explorer", "rail_builder"]:
		var unit: CivilianState = CivilianState.create(1, 0, type_id, DISPATCH_BARE)
		for order: Dictionary in _dispatch_plan(model, unit, works)["orders"]:
			assert_true(
				CivilianCatalog.works(type_id).has(String(order["action"])),
				"%s may work %s" % [type_id, order["action"]]
			)


## Rival engineers raise province hospitals (wiki: combat § Regiment condition;
## civilian-work-planner § Playable slice; DR-20261111-16). The scorer offers
## the seat first, then the best-developed town, and the planner keeps that
## build over the town sweep only while the court is at war.

const CAPITAL: Vector2i = Vector2i(0, 1)
const OUTER_TOWN: Vector2i = Vector2i(4, 1)
const CAPITAL_PROVINCE: int = 0
const OUTER_PROVINCE: int = 1

const TECH: Dictionary = {
	"organised_regiments": true,
	"modern_military_funding": true,
}


## A capital province with a seat and a second owned town province; no resource
## tiles and no coast, so an Engineer's only other work is the town sweep.
func _hospital_model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var capital_tiles: Array[Vector2i] = []
	var outer_tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 3:
				model.province[model.index_of(x, y)] = CAPITAL_PROVINCE
				capital_tiles.append(tile)
			else:
				model.province[model.index_of(x, y)] = OUTER_PROVINCE
				outer_tiles.append(tile)
	var capital := ProvinceState.create(
		CAPITAL_PROVINCE, "Cádiz", capital_tiles, Vector2(1.0, 1.0),
		capital_tiles.size(), 0, true
	)
	capital.capital_tile = CAPITAL
	capital.town_tile = CAPITAL
	var outer := ProvinceState.create(
		OUTER_PROVINCE, "Coro", outer_tiles, Vector2(4.0, 1.0),
		outer_tiles.size(), 0, false
	)
	outer.town_tile = OUTER_TOWN
	model.provinces = [capital, outer]
	return model


func _hospital_stockpile() -> Dictionary:
	return {"lumber": 20, "fabric": 20, "steel": 20, "castIron": 20}


func _hospital_context(at_war: bool = true) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CAPITAL_PROVINCE,
		"capital_tile": CAPITAL,
		"at_war": at_war,
	}


## One work reading for the suites, in the order the civilian pass builds it.
func _work_query(
	config: AiConfig, model: MapModel, unit: CivilianState, units: Array,
	works: LandWorks, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> AiWorkQuery:
	return AiWorkQuery.make(
		config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
		context, reserved
	)


func _best(
	model: MapModel, tech_unlocked: Dictionary = TECH, reserved: Dictionary = {}
) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	return AiHospitalWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, unit, [unit], LandWorks.new(),
		_hospital_stockpile(), {}, tech_unlocked, _hospital_context(), reserved
	))


func test_the_seat_raises_the_first_hospital() -> void:
	var best: Dictionary = _best(_hospital_model())
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("lumber", 0)), 3)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("fabric", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 1, "a field hospital takes one turn")


func test_the_seat_is_upgraded_before_a_new_province() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = _best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("steel", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 2, "a general hospital takes two turns")


func test_a_field_hospital_waits_while_its_tech_is_unknown() -> void:
	var best: Dictionary = _best(_hospital_model(), {})
	assert_true(best.is_empty(), "Organised Regiments gates the first hospital")


func test_a_general_hospital_waits_for_its_own_tech() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = _best(model, {"organised_regiments": true})
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN,
		"the gated upgrade gives way to a field hospital elsewhere"
	)


func test_a_second_province_follows_the_seat() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var best: Dictionary = _best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN)


func test_a_reserved_town_waits_its_turn() -> void:
	var model: MapModel = _hospital_model()
	var reserved: Dictionary = {CAPITAL: true}
	var best: Dictionary = _best(model, TECH, reserved)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN)


func test_a_built_out_court_raises_no_more() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(OUTER_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	assert_true(_best(model).is_empty())


func test_a_townless_province_is_skipped() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var bare := ProvinceState.create(
		2, "Wilds", [Vector2i(2, 2)] as Array[Vector2i], Vector2(2.0, 2.0),
		1, 0, false
	)
	model.provinces.append(bare)
	var best: Dictionary = _best(model)
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN,
		"only the province with a town can host a hospital"
	)


func test_another_courts_province_is_never_planned() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(OUTER_PROVINCE).owner = 1
	assert_true(_best(model).is_empty())


func test_the_engineer_planner_raises_a_hospital_at_war() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _hospital_stockpile(),
		{}, TECH, _hospital_context(true)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_hospital")
	assert_eq(Vector2i(orders[0]["tile"]), CAPITAL)


## The ward's ration is priced against the larder that must carry it: a court
## whose harvest leaves less than one ward's ration after every mouth it feeds
## raises no ward, or it strikes itself into a famine its own works made
## (wiki: civilian-work-planner § Playable slice; issue #807).
func test_a_strapped_larder_raises_no_ward() -> void:
	var context: Dictionary = _hospital_context()
	context["larder_slack"] = HospitalRules.RATION_PER_LEVEL - 1
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	assert_true(AiHospitalWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), _hospital_model(), unit, [unit], LandWorks.new(),
		_hospital_stockpile(), {}, TECH, context, {}
	)).is_empty(), "a ward is a permanent two-food mouth the larder cannot carry")


func test_a_larder_with_a_wards_ration_still_raises_one() -> void:
	var context: Dictionary = _hospital_context()
	context["larder_slack"] = HospitalRules.RATION_PER_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	assert_eq(
		String(AiHospitalWork.best_candidate(_work_query(
			AiConfig.build(0, 1500), _hospital_model(), unit, [unit], LandWorks.new(),
			_hospital_stockpile(), {}, TECH, context, {}
		)).get("action", "")),
		"build_hospital"
	)


func test_a_caller_that_cannot_read_the_larder_keeps_the_old_reading() -> void:
	assert_eq(String(_best(_hospital_model()).get("action", "")), "build_hospital")


func test_peace_leaves_the_town_sweep_first() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _hospital_stockpile(),
		{}, TECH, _hospital_context(false)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")


func test_nothing_is_planned_without_a_world() -> void:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	assert_true(AiHospitalWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), null, unit, [unit], null, _hospital_stockpile(),
		{}, TECH, _hospital_context(), {}
	)).is_empty())


func test_a_fort_always_holds_over_the_town_sweep() -> void:
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_fort"}, _hospital_context(false)
	))
	assert_false(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _hospital_context(false)
	))
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _hospital_context(true)
	))
	assert_false(AiHospitalWork.holds_over_town_link({}, _hospital_context(true)))


func test_the_tie_break_is_row_major_then_action_name() -> void:
	var upper: Dictionary = {"action": "build_hospital", "tile": Vector2i(1, 2), "score": 40}
	var lower: Dictionary = {"action": "build_hospital", "tile": Vector2i(4, 3), "score": 40}
	var left: Dictionary = {"action": "build_hospital", "tile": Vector2i(2, 3), "score": 40}
	var early: Dictionary = {"action": "build_fort", "tile": Vector2i(1, 2), "score": 40}
	assert_eq(Vector2i(AiCivilianCandidate.better(lower, upper)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiCivilianCandidate.better(upper, lower)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiCivilianCandidate.better(lower, left)["tile"]), Vector2i(2, 3))
	assert_eq(Vector2i(AiCivilianCandidate.better(left, lower)["tile"]), Vector2i(2, 3))
	assert_eq(String(AiCivilianCandidate.better(upper, early)["action"]), "build_fort")
	assert_eq(String(AiCivilianCandidate.better(early, upper)["action"]), "build_fort")
	assert_eq(String(AiCivilianCandidate.better({}, upper)["action"]), "build_hospital")
	assert_eq(String(AiCivilianCandidate.better(upper, {})["action"]), "build_hospital")


## AI engineers connect every province town to the capital network (wiki:
## capital-and-connectivity § Town per province; civilian-work-planner).

const ROAD_CAPITAL: Vector2i = Vector2i(0, 1)
const ROAD_TOWN: Vector2i = Vector2i(4, 1)


func _road_model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
	var province := ProvinceState.create(
		0, "Townshire", tiles, Vector2(2.0, 1.0), tiles.size(), 1, true
	)
	province.capital_tile = ROAD_CAPITAL
	province.town_tile = ROAD_TOWN
	model.provinces = [province]
	return model


func _road_stockpile() -> Dictionary:
	return {"lumber": 20, "castIron": 20}


func _connected(model: MapModel, tiles: Array[Vector2i]) -> Dictionary:
	var seen: Dictionary = {}
	for tile: Vector2i in tiles:
		seen[model.index_of(tile.x, tile.y)] = true
	return seen


func test_an_unconnected_town_targets_its_own_tile_first() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], works, _road_stockpile(), {}, {}, {},
		{}
	), _connected(model, [ROAD_CAPITAL]))
	assert_eq(String(best.get("action", "")), "build_road")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ROAD_TOWN)


func test_the_next_step_follows_the_shortest_owned_path() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	works.set_transport(model, ROAD_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], works, _road_stockpile(), {}, {}, {},
		{}
	), _connected(model, [ROAD_CAPITAL]))
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), Vector2i(3, 1))


func test_a_connected_town_is_left_alone() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(), _road_stockpile(),
		{}, {}, {}, {}
	), _connected(model, [ROAD_CAPITAL, ROAD_TOWN]))
	assert_true(best.is_empty())


func test_the_engineer_planner_emits_the_town_road_order() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], works, _road_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ROAD_CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		model.resource_at(Vector2i(orders[0]["tile"]).x, Vector2i(orders[0]["tile"]).y),
		MapModel.NO_ID
	)


func test_without_a_capital_network_no_order_is_offered() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(), _road_stockpile(),
		{}, {}, {}, {}
	), {}).is_empty())


func test_a_reserved_town_is_left_for_another_crew() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(), _road_stockpile(),
		{}, {}, {}, {ROAD_TOWN: true}
	), _connected(model, [ROAD_CAPITAL])).is_empty())


func test_a_foreign_town_is_ignored() -> void:
	var model: MapModel = _road_model()
	model.provinces[0].owner = 2
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(), _road_stockpile(),
		{}, {}, {}, {}
	), _connected(model, [ROAD_CAPITAL])).is_empty())


func test_missing_inputs_are_guarded() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		null, model, unit, [unit], LandWorks.new(), _road_stockpile(), {}, {}, {}, {}
	), _connected(model, [ROAD_CAPITAL])).is_empty())


func test_a_reserved_path_tile_is_left_alone() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	works.set_transport(model, ROAD_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], works, _road_stockpile(), {}, {}, {},
		{Vector2i(3, 1): true}
	), _connected(model, [ROAD_CAPITAL])).is_empty())


func test_a_working_engineer_gets_no_second_order() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	unit.start_work("build_road", ROAD_TOWN, 1)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(), _road_stockpile(),
		{}, {}, {}, {}
	), _connected(model, [ROAD_CAPITAL])).is_empty())


## Wiki: ai-architecture § Town-per-province roads — a town road outranks
## incidental works, so a resource road next to the capital never pre-empts the
## link that lets the Town rule connect the province's estates.
func test_a_town_road_outranks_an_incidental_resource_road() -> void:
	var model: MapModel = _road_model()
	var grain: Vector2i = Vector2i(1, 1)
	model.resource[model.index_of(grain.x, grain.y)] = 4
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(), _road_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ROAD_CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		Vector2i(orders[0]["tile"]), ROAD_TOWN, "the town link comes before an incidental road"
	)


## Wiki: ai-architecture § Town-per-province roads — the court's own fort still
## comes first when it is invaded. The fort stands on the province's own site
## (CivilianWork sites it on the town), so this pins the choice, not the seat.
func test_an_invaded_court_raises_its_fort_before_a_town_road() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(),
		{"lumber": 20, "castIron": 20, "bronze": 20}, {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ROAD_CAPITAL,
			"at_war": true,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_fort")
	assert_eq(
		Vector2i(orders[0]["tile"]),
		FortRules.site_tile(model, 0),
		"the fort stands where the rules site it"
	)


## Rival land reinforcement (wiki: ai-architecture § Land reinforcement,
## growth-stage-planner § Recruitment modulation; DR-20261111-04). A rival court
## raises a line regiment from its own ledger through the same muster the human
## drill yard uses — one a turn, the strongest legal pattern, and only while its
## economy can carry the price (REQ-P2-03, REQ-P3-03).

const WORK_OWNER: int = 2
const WORK_HUMAN: int = 1



func _work_config() -> AiConfig:
	return AiConfig.build(WORK_OWNER, 1500)


## A court with its own ledger: treasury and the opening stock of fabric and
## cast iron the line rows need.
func _work_economy(treasury: int = 12000, peasants: int = 6) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.workers = WorkerPool.make(peasants)
	return economy


# --- planner ----------------------------------------------------------------


func test_a_rival_musters_the_strongest_line_it_can_pay_for() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(), 3, false)

	assert_eq(String(plan["muster"]), "arquebusiers", "the strongest era-1 line")
	var candidates: Array = plan["candidates"]
	assert_true(candidates.size() > 0)
	assert_eq(String(candidates[0]["type_id"]), "arquebusiers")
	for entry: Dictionary in candidates:
		assert_true(
			RegimentCatalog.category(String(entry["type_id"]))
			in AiArmyReinforceLine.LINE_CATEGORIES,
			"a mustered regiment is a line regiment"
		)


func test_the_war_chest_keeps_the_court_from_overspending() -> void:
	# 4,000 ducats covers a pike, but that would empty the purse; the 2,000 levy
	# is the only line that leaves the court's thousand-ducat floor in the bank.
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(4000), 3, false)

	assert_eq(String(plan["muster"]), "peasant_levies")
	var priced: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(1500), 3, false)
	assert_eq(String(priced["muster"]), "", "nothing payable leaves the floor alone")
	assert_true((priced["reasons"] as Array).has("nothing payable"))


func test_a_court_at_target_strength_waits_and_a_war_lifts_the_target() -> void:
	var config: AiConfig = _work_config()
	var peace_target: int = config.parameter("army.regiment_target")
	var war_target: int = peace_target + config.parameter("army.war_extra")
	var peace: Dictionary = AiArmyReinforce.plan(config, _work_economy(), peace_target, false)
	assert_eq(String(peace["muster"]), "", "at the peace target the court waits")
	assert_eq(int(peace["target"]), peace_target)

	var war: Dictionary = AiArmyReinforce.plan(config, _work_economy(), peace_target, true)
	assert_eq(int(war["target"]), war_target, "the war footing raises the target")
	assert_eq(String(war["muster"]), "arquebusiers", "a court at war arms up")

	var full: Dictionary = AiArmyReinforce.plan(config, _work_economy(), war_target, true)
	assert_eq(String(full["muster"]), "", "the war target is a ceiling too")


## The levy's own hand (issue #1355): `army.min_peasants` names the free hands
## the levy draws from, so a court at war with one free peasant raises its levy,
## and the reservation and the war chest read the same floor.
func test_the_levy_draws_the_floors_own_hand() -> void:
	var config: AiConfig = _work_config()
	assert_true(
		AiArmyReinforceLine.labour_floor_ok(config, _work_economy(12000, 1)),
		"one free peasant is the floor the levy draws from"
	)
	assert_false(
		AiArmyReinforceLine.labour_floor_ok(config, _work_economy(12000, 0)),
		"an empty pool holds the floor"
	)
	var muster: Dictionary = AiArmyReinforce.plan(config, _work_economy(12000, 1), 3, true)
	assert_eq(String(muster["muster"]), "arquebusiers", "a war-time court with one free hand arms up")
	# The reservation keeps a head above the floor so a levy that drew the pool
	# to its head would not strand the next muster with an empty pool.
	var economy: PlayerEconomy = _work_economy(12000, 1)
	economy.stockpile = {"fabric": 10, "castIron": 10, "lumber": 10}
	assert_eq(
		AiArmyReinforce.muster_hands(config, economy, 0, true),
		config.parameter("army.min_peasants") + 1,
		"the fields keep the floor plus the levy's hand"
	)
	assert_true(
		AiArmyReinforce.muster_floor(config, _work_economy(12000, 1), 3, true) > 0,
		"the war chest reads the same floor"
	)


func test_a_thin_labour_pool_stops_the_muster() -> void:
	# The retuned floor is 1 free hand (issue #1314 companion; issue #1355): the
	# floor names the hands the levy draws, so a pool of one raises the levy and
	# an empty pool is where the labour floor holds.
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(12000, 1), 3, false)

	assert_eq(String(plan["muster"]), "arquebusiers", "the levy's own hand is drawn")
	# An empty pool and the muster fires nothing — the floor holds.
	var empty: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(12000, 0), 3, false)
	assert_eq(String(empty["muster"]), "", "no hand, no levy")
	assert_true((empty["reasons"] as Array).has("labour floor"))


func test_a_researched_pattern_is_the_one_that_musters() -> void:
	var economy: PlayerEconomy = _work_economy()
	economy.tech_unlocked["weapon_craftsmanship"] = true
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), economy, 3, false)

	assert_eq(String(plan["muster"]), "musketeers", "the newest legal line wins")


# --- provisioning ------------------------------------------------------------


## A court arms itself before it can pay: an empty store still names the line its
## treasury and labour pool open, so the cloth can be kept back and bought rather
## than sold (wiki: growth-stage-planner § Recruitment modulation; the muster
## itself still needs the materials it does not hold).
func test_a_court_provisions_the_regiment_it_means_to_raise() -> void:
	var economy: PlayerEconomy = _work_economy()
	economy.stockpile = {}

	assert_eq(
		AiArmyReinforce.next_type(_work_config(), economy),
		"arquebusiers",
		"the strongest line the purse and the fields open, materials aside"
	)
	assert_eq(
		String(AiArmyReinforce.plan(_work_config(), economy, 3, false)["muster"]), "",
		"an empty store still musters nothing"
	)
	var reserve: Dictionary = AiArmyReinforce.muster_reserve(_work_config(), economy, 3, false)
	assert_eq(
		reserve, RegimentEconomy.training_inputs("arquebusiers"),
		"the reserve is the whole input row of the pattern it would raise"
	)


## Nothing is held back for a court that is not arming: at its target or at a
## labour floor it provisions nothing, and its stock goes to market as before.
## A thin purse is different: the row of the line it can actually pay for is
## kept, because a court that only stocked up once the muster was legal would
## starve that muster with a full war chest (issue #474).
func test_a_court_that_is_not_arming_provisions_nothing() -> void:
	var config: AiConfig = _work_config()
	var peace_target: int = config.parameter("army.regiment_target")
	var target: Dictionary = AiArmyReinforce.muster_reserve(config, _work_economy(), peace_target, false)
	assert_true(target.is_empty(), "at the peace target the court provisions nothing")

	var war: Dictionary = AiArmyReinforce.muster_reserve(config, _work_economy(), peace_target, true)
	assert_false(war.is_empty(), "a war lifts the target and the court arms up")

	var thin: Dictionary = AiArmyReinforce.muster_reserve(
		_work_config(), _work_economy(12000, 3), 5, false
	)
	assert_true(thin.is_empty(), "the fields keep their hands")

	var poor: Dictionary = AiArmyReinforce.muster_reserve(_work_config(), _work_economy(1500), 3, false)
	assert_eq(
		poor, RegimentEconomy.training_inputs("peasant_levies"),
		"a purse under the levy price still keeps the levy's row for the muster it is saving for"
	)


## A court saving for its first line provisions the cheapest pattern it can
## actually pay for, not a stronger one its purse will never reach: the cloth a
## levy needs is what the market is bid for (issue #474).
func test_a_court_saving_for_its_muster_provisions_the_cheapest_line() -> void:
	var economy: PlayerEconomy = _work_economy(1500)
	economy.stockpile = {}

	assert_eq(AiArmyReinforce.saving_type(_work_config(), economy), "peasant_levies")
	assert_eq(
		AiArmyReinforce.muster_reserve(_work_config(), economy, 3, false),
		RegimentEconomy.training_inputs("peasant_levies"),
		"one fabric, the whole row of the levy"
	)


## The reserve follows the pattern the court has actually researched, so a new
## line's row is what gets kept.
func test_the_reserve_follows_the_researched_pattern() -> void:
	var economy: PlayerEconomy = _work_economy()
	economy.tech_unlocked["weapon_craftsmanship"] = true

	assert_eq(AiArmyReinforce.next_type(_work_config(), economy), "musketeers")
	assert_eq(
		AiArmyReinforce.muster_reserve(_work_config(), economy, 3, false),
		RegimentEconomy.training_inputs("musketeers")
	)


## The seat invariant the muster depends on: a reassigned seat takes the Home
## Army with it, and a court whose guard died with the old seat reforms one at
## the new, because the standard is never deleted (wiki: military-armies
## § Home Army; issue #474).
func test_a_moved_seat_takes_the_home_army_and_a_lost_one_reforms() -> void:
	var armies: Array[ArmyState] = [
		ArmyState.muster(2, WORK_OWNER, 1, true, ["peasant_levies"] as Array[String], 101),
	]

	var settled: Dictionary = ArmyTraining.settle_seat(armies, WORK_OWNER, 7, 9)

	assert_eq((settled["army"] as ArmyState).province, 7, "the guard follows the court")
	assert_false(bool(settled["minted"]), "the same standard moved, no new one minted")

	var emptied: Array[ArmyState] = []
	var reformed: Dictionary = ArmyTraining.settle_seat(emptied, WORK_OWNER, 7, 9)

	assert_true(bool(reformed["minted"]), "a court with no Home Army reforms one")
	assert_eq(emptied.size(), 1)
	assert_eq((reformed["army"] as ArmyState).province, 7)
	assert_true((reformed["army"] as ArmyState).is_home_army())
	assert_eq((reformed["army"] as ArmyState).owner, WORK_OWNER)

	var missing: Dictionary = ArmyTraining.settle_seat(emptied, WORK_OWNER, -1, 9)
	assert_eq(missing["army"], null, "no seat, no Home Army to settle")


# --- map adapter ------------------------------------------------------------


## One peace-time world: England's seat at province 0, France's at province 1,
## with a rival ledger already resolved for France.
func _play(treasury: int = 12000, with_ledger: bool = true) -> PlaySession:
	var world: WorldMap = AiFixture.land_world([WORK_HUMAN, WORK_OWNER], {0: true, 1: true})
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, WORK_HUMAN, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(
			2, WORK_OWNER, 1, true, ["peasant_levies", "peasant_levies"] as Array[String], 101
		),
	]
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.next_regiment = 1000
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = WORK_HUMAN
	play.world = world
	play.model = model
	var court := DiplomacyState.new()
	court.reset(WORK_HUMAN)
	court.ensure_relation(WORK_HUMAN, WORK_OWNER, 1)
	play.diplomacy = court
	play.army_layer = layer
	play.map_seed = 1500
	if with_ledger:
		play.ai = AiState.new()
		play.ai.economies[WORK_OWNER] = _work_economy(treasury)
	return play


func test_the_map_pass_musters_a_rival_from_its_own_ledger() -> void:
	var play: PlaySession = _play(12000)
	var economy: PlayerEconomy = play.ai.economies[WORK_OWNER]
	var before: int = play.army_layer.regiment_count_all(WORK_OWNER)
	var peasants: int = economy.available_peasants()

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 1, "a muster and nothing else in peace")
	assert_eq(String(trace[0]["kind"]), MapPlayArmyMusterAi.KIND_REINFORCE)
	assert_eq(String(trace[0]["type"]), "arquebusiers")
	assert_eq(play.army_layer.regiment_count_all(WORK_OWNER), before + 1)
	assert_eq(economy.available_peasants(), peasants - 1, "one peasant joins the colours")
	assert_true(
		economy.treasury < 12000, "the court's own purse pays, never the crown's"
	)
	var home: ArmyState = ArmyTraining.home_army(play.army_layer.armies, WORK_OWNER)
	assert_not_null(home)
	assert_true(
		home.regiments.has(String(trace[0]["regiment"])),
		"the new regiment wears France's colours in the Home Army"
	)
	play.army_layer.free()


## A court whose seat moved musters again: the reassignment keeps the Home Army
## on the new seat, and the next land pass raises its regiment there (issue
## #474). Without the recall the capital guard blocks every muster for the rest
## of the campaign.
func test_a_moved_seat_still_musters_at_the_new_capital() -> void:
	var world: WorldMap = AiFixture.land_world([WORK_HUMAN, WORK_OWNER, WORK_OWNER], {0: true, 1: true})
	var model: MapModel = world.region(0)
	# The old seat falls; the court's other province becomes the seat.
	model.province_data(1).capital = false
	model.province_data(2).capital = true
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, WORK_HUMAN, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(2, WORK_OWNER, 1, true, ["peasant_levies"] as Array[String], 101),
	]
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.next_regiment = 1000
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = WORK_HUMAN
	play.world = world
	play.model = model
	var court := DiplomacyState.new()
	court.reset(WORK_HUMAN)
	court.ensure_relation(WORK_HUMAN, WORK_OWNER, 1)
	play.diplomacy = court
	play.army_layer = layer
	play.map_seed = 1500
	play.ai = AiState.new()
	play.ai.economies[WORK_OWNER] = _work_economy(12000)

	ArmyTraining.settle_seat(armies, WORK_OWNER, 2, layer.next_army)
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 1, "the court raises its regiment again")
	assert_eq(String(trace[0]["kind"]), MapPlayArmyMusterAi.KIND_REINFORCE)
	assert_eq(int(trace[0]["province"]), 2, "the regiment musters at the new seat")
	play.army_layer.free()


func test_the_human_crown_is_never_mustered_for() -> void:
	var play: PlaySession = _play(12000)
	var before: int = play.army_layer.regiment_count_all(WORK_HUMAN)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(play.army_layer.regiment_count_all(WORK_HUMAN), before)
	for record: Dictionary in trace:
		assert_eq(int(record["faction"]), WORK_OWNER, "the crown musters its own men")
	play.army_layer.free()


func test_a_court_without_a_ledger_never_musters() -> void:
	var play: PlaySession = _play(12000, false)
	var before: int = play.army_layer.regiment_count_all(WORK_OWNER)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 0, "no ledger, no muster")
	assert_eq(play.army_layer.regiment_count_all(WORK_OWNER), before)
	play.army_layer.free()


func test_the_observer_log_reads_the_muster() -> void:
	var play: PlaySession = _play(12000)
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	var merged: Dictionary = AiTurnLog.record(play, trace, [], {})
	var record: Dictionary = merged["factions"][WORK_OWNER]
	assert_eq(int(record["actions"].get("reinforce", 0)), 1, "one regiment raised")
	var lines: Array = record["events"]
	assert_true(lines.size() > 0, "the event list names the pattern")
	play.army_layer.free()


# --- famine: shed the force a court cannot feed (issue #489) -----------------


func test_fed_slack_reads_the_ration_after_army_and_navy() -> void:
	var economy: PlayerEconomy = _work_economy(12000, 4)
	economy.stockpile["grain"] = 10
	economy.stockpile["meat"] = 0

	# 10 grain − 3 army − 2 navy (one hull) − 4 peasants
	assert_eq(AiArmyReinforce.fed_slack(economy, 3, 1), 1)
	assert_true(not AiArmyReinforce.starving(economy, 3, 1))


func test_a_short_worker_ration_is_a_strike() -> void:
	var economy: PlayerEconomy = _work_economy(12000, 4)
	economy.stockpile["grain"] = 5
	economy.stockpile["meat"] = 0

	assert_eq(AiArmyReinforce.fed_slack(economy, 3, 0), -2)
	assert_true(AiArmyReinforce.starving(economy, 3, 0))


## The muster gate is the Consumption phase's own larder reading, so the court
## arms no man the phase would starve and the crown's ledger line, the strike
## rule and the AI never name two totals (issue #489; REQ-P2-03).
func test_the_muster_slack_is_the_consumption_reading() -> void:
	var economy: PlayerEconomy = _work_economy(12000, 4)
	economy.stockpile["grain"] = 10
	economy.stockpile["meat"] = 0
	var fed: Dictionary = LarderRead.reading(
		economy.workers, economy.stockpile, {"army": 3, "ships": 1}
	)
	assert_eq(AiArmyReinforce.fed_slack(economy, 3, 1), 1)
	assert_eq(int(fed["store_short"]), 0, "the phase covers every mouth the muster counts")
	assert_true(not AiArmyReinforce.starving(economy, 3, 1))

	economy.stockpile["grain"] = 2
	var hungry: Dictionary = LarderRead.reading(
		economy.workers, economy.stockpile, {"army": 3, "ships": 0}
	)
	assert_true(int(hungry["store_short"]) > 0, "the phase reads the larder short")
	assert_true(AiArmyReinforce.starving(economy, 3, 0), "and the muster reads the same")


func test_a_court_striking_for_food_musters_nothing() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 0
	)

	assert_eq(String(plan["muster"]), "")
	assert_true((plan["reasons"] as Array).has("striking for food"))


## The growth gate plans with the harvest, not the pantry: a court whose own
## ration harvest cannot carry one more ration arms no further, even while the
## store could still pay for the mouth — the army it desires is provisioned
## before it is raised (issue #807; the fallback trim's measured lesson: a
## store-runway overshoot arms the court past its land).
func test_a_court_whose_harvest_cannot_carry_one_more_ration_waits() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 1, 0, {}, -1, 0
	)

	assert_eq(String(plan["muster"]), "")
	assert_true(
		(plan["reasons"] as Array).has("the harvest cannot carry one more ration")
	)


func test_a_harvest_with_one_free_ration_raises_the_line() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 1, 0, {}, -1, 1
	)

	assert_eq(String(plan["muster"]), "arquebusiers")


func test_a_court_with_no_harvest_reading_keeps_the_store_gate() -> void:
	var starved: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 0, 0, {}, -1, -2
	)
	assert_true((starved["reasons"] as Array).has("striking for food"))
	var fed: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 1, 0, {}, -1, -2
	)
	assert_eq(String(fed["muster"]), "arquebusiers", "no reading, no gate")


func test_a_harvest_one_ration_short_also_waits() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 1, 0, {}, -1, -1
	)

	assert_eq(String(plan["muster"]), "")
	assert_true(
		(plan["reasons"] as Array).has("the harvest cannot carry one more ration")
	)


func test_a_court_with_room_for_one_more_ration_musters() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 1
	)

	assert_eq(String(plan["muster"]), "arquebusiers")


## The economy pass notes the harvest slack each turn and the army pass reads
## it back the next; a fresh load has no reading and the gate stands down
## (issue #807).
func test_the_harvest_slack_is_noted_and_read_per_court() -> void:
	var state := AiState.new()
	assert_false(state.food_slack.has(WORK_OWNER), "no reading, no gate")
	state.note_food_slack(WORK_OWNER, 3)
	state.note_food_slack(WORK_OWNER + 1, -2)
	assert_eq(int(state.food_slack[WORK_OWNER]), 3)
	assert_eq(int(state.food_slack[WORK_OWNER + 1]), -2)


func test_a_court_hires_no_mouth_it_cannot_feed() -> void:
	var economy: PlayerEconomy = _work_economy(12000, 4)

	var starved: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		_work_config(), economy, 0, 0
	)
	var fed: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
		_work_config(), economy, 0, 1
	)

	assert_eq(starved.size(), 0, "no ration, no hire")
	assert_eq(fed.size(), 1, "one mouth the larder can feed, and no more")


# --- a land march (AiLandRoute, shared by the rival civilians) ---------------

## The same walk the Explorer, Merchant and Spy planners ask for: one legal land
## tile toward a goal, a field step for a Spy, and the nearest goal of a list
## (wiki: civilian-work-planner § Relations; the land counterpart of AiSeaRoute).


## A goal pulls the walk closer, the step is on land, and it names the unit it
## belongs to so any planner's order reads the same.
func test_a_land_step_closes_on_its_goal() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(1, 0, "explorer", Vector2i(0, 0))
	var step: Dictionary = AiLandRoute.step_toward(model, unit, Vector2i(2, 2))
	var tile: Vector2i = step.get("tile", CivilianState.NO_TILE)

	assert_eq(String(step.get("kind", "")), AiLandRoute.KIND_MOVE)
	assert_eq(int(step.get("unit_id", -1)), 1)
	assert_eq(
		AiLandRoute.manhattan(tile, Vector2i(2, 2)),
		AiLandRoute.manhattan(unit.tile, Vector2i(2, 2)) - 1,
		"one tile nearer"
	)
	assert_true(model.is_land(tile.x, tile.y), "a civilian never walks onto water")


## A march with no goal, no unit or no chart offers nothing rather than a
## plausible-looking tile.
func test_a_land_step_needs_a_goal_and_a_unit() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(1, 0, "explorer", Vector2i(0, 0))

	assert_true(AiLandRoute.step_toward(model, unit, CivilianState.NO_TILE).is_empty())
	assert_true(AiLandRoute.step_toward(null, unit, Vector2i(1, 1)).is_empty())
	assert_true(AiLandRoute.step_toward(model, null, Vector2i(1, 1)).is_empty())


## A Spy walks its own distance field: the step must be one the field reaches
## cheaply, and a field that reaches nothing this turn offers no march.
func test_a_field_step_takes_only_a_reachable_tile() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(1, 0, "spy", Vector2i(1, 1))

	var reachable: Dictionary = AiLandRoute.step_by_field(
		model, unit, {Vector2i(2, 1): 3}
	)
	assert_eq(Vector2i(reachable.get("tile", CivilianState.NO_TILE)), Vector2i(2, 1))
	assert_eq(int(reachable.get("distance", -1)), 3)

	assert_true(
		AiLandRoute.step_by_field(model, unit, {Vector2i(0, 3): 0}).is_empty(),
		"a field that reaches no neighbouring tile is no march"
	)
	assert_true(AiLandRoute.step_by_field(model, unit, {}).is_empty())
	assert_true(AiLandRoute.step_by_field(null, unit, {Vector2i(2, 1): 0}).is_empty())


## The nearest goal of a list, with the lower tile breaking a tie so the same
## state always picks the same goal; an empty list has none.
func test_the_nearest_goal_wins_a_tie_by_its_lower_tile() -> void:
	var goals: Array[Vector2i] = [Vector2i(3, 1), Vector2i(1, 1)]

	assert_eq(AiLandRoute.nearest(goals, Vector2i(2, 2)), Vector2i(1, 1))
	assert_eq(AiLandRoute.nearest([] as Array[Vector2i], Vector2i(2, 2)), CivilianState.NO_TILE)


## A Spy's field counts land tiles away from its targets and leaves open water
## with no entry, so a BFS never pretends a hull's route is a walk.
func test_the_land_distance_field_counts_land_and_leaves_water_out() -> void:
	var model: MapModel = CivilianFixture.build()
	var water: Vector2i = Vector2i(1, 4)
	var field: Dictionary = AiLandRoute.distance_field(
		model, [CivilianFixture.BARE_TILE, water, CivilianFixture.BARE_TILE]
	)

	assert_eq(int(field.get(CivilianFixture.BARE_TILE, -1)), 0)
	assert_eq(int(field.get(Vector2i(1, 0), -1)), 1)
	assert_eq(int(field.get(Vector2i(2, 0), -1)), 2)
	assert_false(field.has(water), "water is not a step")

# --- ai ledger coverage (#605) ---

## Shipped-rule → order-row coverage checklist (issue #605): every rule the full-AI
## observer's per-turn records prove a court exercised, every rule they prove it never did,
## and the ledger's word on a rule whose aim was ranked but never funded. Pure: synthetic
## records, no map (REQ-P3-03).

func _records() -> Array[Dictionary]:
	# Two resolved turns, two crowns: Portugal declares war and musters, Spain
	# spends the second turn pitching a train.
	return [
		{
			"turn": 2,
			"rows": [
				{
					"faction": 0,
					"last":
					{
						"actions": {"war": 1, "reinforce": 2},
						"objectives": {"rows": []},
					},
				},
			],
		},
		{
			"turn": 3,
			"rows": [
				{
					"faction": 0,
					"last": {"actions": {"war": 2}, "objectives": {"rows": []}},
				},
				{
					"faction": 1,
					"last":
					{
						"actions": {"hospital": 1},
						"objectives":
						{
							"rows":
							[
								{"id": "navy.build", "status": AiObjective.STATUS_DEFERRED},
							],
						},
					},
				},
			],
		},
	]


func _row(rows: Array[Dictionary], id: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row["id"]) == id:
			return row
	return {}


func test_every_shipped_rule_gets_a_row_even_on_an_empty_run() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan([])
	assert_eq(rows.size(), AiCoverage.RULES.size(), "one row per catalogued rule")
	for row: Dictionary in rows:
		assert_eq(int(row["count"]), 0, "an empty run exercises nothing")
		assert_eq(int(row["first"]), -1, "no window on an empty run")


func test_a_row_counts_every_order_across_the_whole_run() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	var war: Dictionary = _row(rows, "war.declare")
	assert_eq(int(war["count"]), 3, "every declaration in every turn is counted")
	assert_eq(int(war["first"]), 2, "the first turn it fired")
	assert_eq(int(war["last"]), 3, "the last turn it fired")
	assert_eq((war["courts"] as Array).size(), 1, "one crown issued them all")


## A fallen crown's rows are dropped: a dead court can no longer make a rule
## read as exercised (issue #1136).
func test_a_dead_courts_rows_never_count_toward_coverage() -> void:
	var records: Array[Dictionary] = _records()
	# Crown 0 issues all three war rows; its second turn is a dead one.
	(records[1]["rows"][0] as Dictionary)["alive"] = false
	# Crown 1 (the hospital train) is given an explicit living reading.
	(records[1]["rows"][1] as Dictionary)["alive"] = true
	var rows: Array[Dictionary] = AiCoverage.scan(records)
	assert_eq(
		int(_row(rows, "war.declare")["count"]), 1,
		"only the turn the crown still lived counts"
	)
	assert_eq(int(_row(rows, "army.hospital")["count"]), 1, "the living crown's train counts")
	# A record with no `alive` reading (an older exporter) keeps every row.
	(records[1]["rows"][0] as Dictionary).erase("alive")
	var unread: Array[Dictionary] = AiCoverage.scan(records)
	assert_eq(
		int(_row(unread, "war.declare")["count"]), 3,
		"a row without the alive reading is read as a living court"
	)


func test_a_rule_with_no_order_row_reads_never_exercised() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	assert_eq(int(_row(rows, "navy.launch")["count"]), 0, "no hull was laid")
	assert_true(
		AiCoverage.missing_major(rows).has("navy.launch"),
		"a major row at zero fails the checklist",
	)
	assert_true(
		not AiCoverage.missing_major(rows).has("army.hospital"),
		"a policy-gated row never fails the checklist",
	)
	assert_true(
		AiCoverage.report(rows).contains("never-exercised major"),
		"the report names the count",
	)


## The naval rows' own gates (issue #1357): the seed-1500 batch never meets
## either — the opening raids and battles take every court's hulls by t20 and
## the frozen pool rebuilds none, so no port warship has a hostile squadron in
## reach and nothing is afloat to bring home. Both rows name the gate that held
## every court instead of failing the checklist as defects.
func test_the_naval_rows_name_the_gate_that_holds_them() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	var sortie: Dictionary = _row(rows, "navy.sortie")
	assert_false(bool(sortie["major"]), "the sortie is gated, not a defect")
	assert_eq(int(sortie["count"]), 0, "no port squadron sortied")
	assert_true(
		String(sortie["gate"]).contains("hostile squadron"),
		"the sortie names the gate that held every court",
	)
	var home: Dictionary = _row(rows, "navy.home")
	assert_false(bool(home["major"]), "the homeward leg is gated, not a defect")
	assert_eq(int(home["count"]), 0, "no squadron came home")
	assert_true(
		String(home["gate"]).contains("harbour to reach"),
		"the homeward leg names the gate that held every court",
	)
	assert_true(
		not AiCoverage.missing_major(rows).has("navy.sortie"),
		"a gated sortie never fails the checklist",
	)
	assert_true(
		not AiCoverage.missing_major(rows).has("navy.home"),
		"a gated homeward leg never fails the checklist",
	)


func test_an_aim_ranked_but_never_funded_reads_starved() -> void:
	var fixed: Array[Dictionary] = _records()
	var court: Dictionary = fixed[1]["rows"][1]
	var aim: Dictionary = (court["last"]["objectives"]["rows"] as Array)[0]
	aim["status"] = AiObjective.STATUS_FUNDED
	var funded: Array[Dictionary] = AiCoverage.scan(fixed)
	var build: Dictionary = _row(funded, "navy.launch")
	assert_eq(int(build["aims_ranked"]), 1, "the aim was ranked once")
	assert_eq(int(build["aims_funded"]), 1, "the ledger funded it once")
	assert_true(
		not AiCoverage.starved(funded).has("navy.launch"),
		"a funded aim is not starved",
	)
	aim["status"] = AiObjective.STATUS_BLOCKED
	var blocked: Array[Dictionary] = AiCoverage.scan(fixed)
	assert_eq(int(_row(blocked, "navy.launch")["aims_funded"]), 0, "blocked funds nothing")
	assert_true(
		AiCoverage.starved(blocked).has("navy.launch"),
		"a ranked aim nobody funds is the under-use the run proves",
	)


func test_a_second_run_merges_into_one_checklist() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	var before: int = int(_row(rows, "war.declare")["count"])
	AiCoverage.merge(rows, AiCoverage.scan(_records()))
	assert_eq(int(_row(rows, "war.declare")["count"]), before * 2, "counts add")
	assert_eq((_row(rows, "war.declare")["courts"] as Array).size(), 1, "crowns are a set")
	assert_eq(int(_row(rows, "war.declare")["runs"]), 4, "runs add, 2 per scan")


func test_merge_takes_the_earliest_window_and_ignores_a_nameless_court() -> void:
	# A run whose only declaration is on t1, written by a record with no crown
	# id: the merged window starts before the first scan's and no phantom crown
	# joins the set.
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	var early: Array[Dictionary] = AiCoverage.scan(
		[{"turn": 1, "rows": [{"last": {"actions": {"war": 1}, "objectives": {"rows": []}}}]}]
	)
	AiCoverage.merge(rows, early)
	var war: Dictionary = _row(rows, "war.declare")
	assert_eq(int(war["count"]), 4, "the earlier run is counted")
	assert_eq(int(war["first"]), 1, "the window starts at the earliest turn")
	assert_eq(int(war["last"]), 3, "and ends at the latest")
	assert_eq((war["courts"] as Array).size(), 1, "a nameless record names no crown")


func test_merge_into_an_empty_checklist_adopts_the_run() -> void:
	# A second crown declaring war joins the set, and a checklist that has run
	# nothing yet takes the window whole.
	var rows: Array[Dictionary] = AiCoverage.scan([])
	AiCoverage.merge(rows, AiCoverage.scan(_records()))
	var war: Dictionary = _row(rows, "war.declare")
	assert_eq(int(war["first"]), 2, "an empty checklist adopts the first turn")
	var second: Array[Dictionary] = AiCoverage.scan(
		[{"turn": 4, "rows": [{"faction": 2, "last": {"actions": {"war": 1}, "objectives": {"rows": []}}}]}]
	)
	AiCoverage.merge(rows, second)
	assert_eq((_row(rows, "war.declare")["courts"] as Array).size(), 2, "a new crown joins")
	assert_eq(int(_row(rows, "war.declare")["last"]), 4, "the window widens")


func test_a_checklist_with_no_rows_reports_a_clean_zero() -> void:
	# `report` on no rows still prints its one summary line, so a caller that
	# scanned nothing reads "0 of 0" rather than a blank table.
	var text: String = AiCoverage.report([])
	assert_true(text.contains("Exercised 0 of 0"), "the summary still prints")
	assert_true(not text.contains("never-exercised major 1"), "and names no defect")

# --- rival world-market participation ---

## Rival world-market participation (wiki: world-market; docs/ai.md). Sells above the
## reserve and production inputs, bids with free holds, and keeps each crown's cargo
## separate. Consolidated rulebook: AiMarket + AiMerchant + AiCargo (one Godot boot per
## domain).

const CONFIG_FACTION: int = 1
const MapFixture = preload("res://tests/map_fixture.gd")
## A Tribe a rival crown has colonised, and the crown that colonised it: the pair
## a colonial boycott bars (wiki: diplomacy § GP–Tribe — Boycott, R6).
const BOYCOTTED_COLONY_TRIBE: int = 9
const BOYCOTT_ISSUER: int = 2


func _config() -> AiConfig:
	return AiConfig.build(CONFIG_FACTION, 1500)


func _economy(stock: Dictionary, treasury: int = 5000) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.stockpile = stock.duplicate()
	return economy


## The units of one commodity a plan offers, or 0 when it offers none.
func _offered(plan: Dictionary, id: String) -> int:
	for raw: Variant in plan.get("offers", []):
		var offer: Dictionary = raw
		if String(offer["commodity"]) == id:
			return int(offer["quantity"])
	return 0


func test_a_court_sells_surplus_above_the_reserve() -> void:
	var economy: PlayerEconomy = _economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 0)
	var offers: Array = plan["offers"]
	assert_eq(offers.size(), 1)
	assert_eq(String(offers[0]["commodity"]), "grain")
	assert_eq(int(offers[0]["quantity"]), 10, "market.max_offer_units caps the lot")
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 1)
	assert_eq((result["bought"] as Array).size(), 0, "no holds means no imports")
	assert_eq(economy.quantity("grain"), 90)
	assert_true(economy.treasury > 5000)


## The rations are grain or meat, and the larder eats grain first: a court whose
## larder is meat must not sell the food its regiments and staffs eat this turn
## (wiki: workers-and-population § Consumption "Total food demand = workers +
## navy + army + hospital staffs"; DR-20261112-04: "the AI's market planner
## reserves the rations before it sells food").
func test_a_meat_larder_keeps_the_rations_the_court_eats() -> void:
	var meat: PlayerEconomy = _economy({"meat": 100})
	var reserved: Dictionary = MapPlayEconomyLarder.reserved_inputs({}, 85, meat)
	assert_eq(int(reserved.get("meat", 0)), 85, "the meat larder holds the whole ration")
	assert_eq(int(reserved.get("grain", 0)), 0, "an empty granary reserves nothing")
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), meat, WorldMarket.with_default_prices(), 0, {}, reserved
	)
	assert_eq((plan["offers"] as Array).size(), 0, "no ration goes to market")

	# Grain still goes first, and the rest of the ration rests on meat.
	var mixed: PlayerEconomy = _economy({"grain": 20, "meat": 100})
	var both: Dictionary = MapPlayEconomyLarder.reserved_inputs({}, 85, mixed)
	assert_eq(int(both.get("grain", 0)), 20)
	assert_eq(int(both.get("meat", 0)), 65)

	# A full granary reserves grain alone, and the surplus above it still sells.
	var grain: PlayerEconomy = _economy({"grain": 200})
	var fed: Dictionary = MapPlayEconomyLarder.reserved_inputs({}, 85, grain)
	assert_eq(int(fed.get("grain", 0)), 85)
	assert_eq(int(fed.get("meat", 0)), 0)


## The ledger side of the economy turn is one home (`MapPlayEconomyLarder`) for
## the rival pass, one court's turn and the crown's picks: its reads keep their
## shape when the session carries no ledger or army layer, and two material rows
## add up (REQ-P3-01, REQ-P3-02).
func test_the_larder_reads_carry_their_shape_for_the_pass_and_the_picks() -> void:
	var empty := PlaySession.new()
	assert_true(
		MapPlayEconomyLarder.market(empty).prices.size() > 0,
		"a session with no ledger still plans against the published prices"
	)
	assert_eq(MapPlayEconomyLarder.army_food(empty, 1), 0, "no army layer eats nothing")
	assert_eq(
		MapPlayEconomyLarder.reserved_inputs({}, 85, _economy({})).size(), 0,
		"a court with no ration in hand reserves no row"
	)
	var merged: Dictionary = MapPlayEconomyLarder.merge_rows({"cloth": 2}, {"cloth": 3})
	assert_eq(int(merged["cloth"]), 5, "the muster's cloth and the hull's add up")
	assert_eq(MapPlayEconomyLarder.merge_rows({"cloth": 2}, {}).size(), 1, "an empty row adds nothing")


## The hire's slack and the flow gate read one home: a session with no planner
## has no note (the `-2` sentinel), a noted slack is read back as it stands, and a
## court with no harvest in hand falls back to the pass's own note. The court's
## turn and the WORKERS tab's counsel read the same two figures (REQ-P3-01,
## REQ-P3-02; DR-20261122-01).
func test_the_larder_owns_the_hire_slack_it_reads() -> void:
	var empty := PlaySession.new()
	assert_eq(MapPlayEconomyLarder.noted_slack(empty, 1), -2, "no pass, no note")
	assert_eq(MapPlayEconomyLarder.noted_slack(null, 1), -2, "no session, no note")
	var court := MapPlayEconomyCourt.new()
	court.play = empty
	court.faction = 1
	court.overseas = {}
	assert_eq(
		MapPlayEconomyLarder.harvest_reading(court), -2,
		"no harvest and no note, no reading"
	)
	court.play.ensure_ai().note_food_slack(1, 4)
	assert_eq(
		MapPlayEconomyLarder.noted_slack(empty, 1), 4, "the pass's note is the reading"
	)
	assert_eq(
		MapPlayEconomyLarder.harvest_reading(court), 4,
		"a court with no harvest hires against the note"
	)


## The chest the muster and the hull claim is the larder's row: a court with no
## yard chest claims no hull, and the merged row keeps the muster's own cloth
## (issue #484, #878).
func test_the_larder_owns_the_chest_rows_the_plan_reads() -> void:
	var economy: PlayerEconomy = _economy({"fabric": 8})
	var chest: Dictionary = MapPlayEconomyLarder.chest_rows(
		PlaySession.new(), CONFIG_FACTION, AiControl.KIND_SUBJECT, _config(),
		economy, true, 2, 0, 0, 0
	)
	assert_false((chest["muster_row"] as Dictionary).is_empty(), "the muster names its row")
	assert_eq((chest["navy_row"] as Dictionary).size(), 0, "no chest, no hull row")
	assert_eq(
		(chest["held"] as Dictionary), (chest["muster_row"] as Dictionary),
		"with no hull the held row is the muster's own"
	)


func test_production_inputs_are_never_sold_under_the_court() -> void:
	var economy: PlayerEconomy = _economy({"lumber": 30, "grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 0, {}, {"lumber": 20}
	)
	for raw: Variant in plan["offers"]:
		var offer: Dictionary = raw
		assert_ne(String(offer["commodity"]), "lumber")


## The cloth the next regiment needs is kept back: the muster's row is withheld
## from the offer and only the stock above it is sold (wiki: growth-stage-planner
## § Recruitment modulation — "military fabric reservation holds inputs for
## upcoming recruits").
func test_a_court_keeps_the_cloth_its_next_regiment_needs() -> void:
	var economy: PlayerEconomy = _economy({"fabric": 22, "grain": 100})
	var market := WorldMarket.with_default_prices()
	var plain: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 0)
	assert_eq(_offered(plain, "fabric"), 2, "the surplus above the reserve sells")

	var kept: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 0, {}, {}, {"fabric": 1}
	)
	assert_eq(_offered(kept, "fabric"), 1, "one bolt is the regiment's, the rest sells")


## A regiment's input leads the bid list even when its shortfall is the smallest,
## so the bid-type cap cannot starve the muster.
func test_the_regiments_input_leads_the_bids() -> void:
	var economy: PlayerEconomy = _economy({"fabric": 15}, 5000)
	var market := WorldMarket.with_default_prices()
	var plain: Array = AiMarketPlanner.plan(_config(), economy, market, 20)["bids"]
	assert_ne(String(plain[0]["commodity"]), "fabric", "the largest shortfall leads")

	var need: Array = AiMarketPlanner.plan(
		_config(), economy, market, 20, {}, {}, {"fabric": 1}
	)["bids"]
	assert_eq(
		String(need[0]["commodity"]), "fabric",
		"the cloth the muster needs is bid for first"
	)


## Lumber for the works and cloth for the regiment are both kept: the muster's
## claim is added to the production reservation rather than replacing it.
func test_the_muster_reservation_adds_to_the_production_one() -> void:
	var economy: PlayerEconomy = _economy({"fabric": 4, "timber": 40})
	var reserved: Dictionary = MapPlayEconomyLarder.reserved_inputs(
		{"assignments": [{"recipe": "lumber", "units": 2}]}, 0, economy, {"fabric": 1}
	)
	assert_eq(int(reserved.get("fabric", 0)), 1, "the regiment's bolt is held")
	assert_eq(int(reserved.get("timber", 0)), 4, "the sawmill's timber still is too")


## The materials a crew's planned work will spend are read from the same rows
## the assignment pays: a level-1 estate is a timber and a cast iron, a survey
## is free (wiki: civilian-units § Work Order Summary; economy-planner
## § Reservations).
func test_the_works_reservation_is_the_row_the_crew_will_pay() -> void:
	var model: MapModel = Fixture.build()
	var works := LandWorks.new()
	var builder: Array = [CivilianState.create(1, 0, "builder", Fixture.BARE_TILE)]
	var orders: Array = _market_plan(model, builder, null, works)["orders"]
	assert_eq(orders.size(), 1, "the fixture's builder raises its estate")
	MapPlayCivilianPlan.price(orders, model, works, Fixture.stockpile())
	var rows: Dictionary = MapPlayCivilianPlan.work_rows([{"plan": {"orders": orders}}])
	assert_eq(int(rows.get("lumber", 0)), 1, "the level-1 estate's timber")
	assert_eq(int(rows.get("castIron", 0)), 1, "and its cast iron")

	var explorer: Array = [CivilianState.create(2, 0, "explorer", Fixture.IRON_TILE)]
	var survey: Array = _market_plan(model, explorer, null, works)["orders"]
	MapPlayCivilianPlan.price(survey, model, works, Fixture.stockpile())
	assert_true(
		MapPlayCivilianPlan.work_rows([{"plan": {"orders": survey}}]).is_empty(),
		"a survey costs no material, so it reserves none"
	)


## The market cannot sell the timber and iron the crew's estate is about to
## spend, so build, work and trade never use one commodity twice (wiki:
## economy-planner § Reservations; DR-20261113-08's fabric row is the same
## rule for the muster).
func test_a_court_keeps_the_materials_its_works_will_spend() -> void:
	var economy: PlayerEconomy = _economy({"lumber": 25, "castIron": 25, "grain": 100})
	var market := WorldMarket.with_default_prices()
	var plain: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 0)
	assert_eq(_offered(plain, "lumber"), 5, "the surplus above the reserve sells")
	assert_eq(_offered(plain, "castIron"), 5)

	var rows: Dictionary = {"lumber": 5, "castIron": 5}
	var reserved: Dictionary = MapPlayEconomyLarder.reserved_inputs({}, 0, economy, {}, rows)
	assert_eq(int(reserved.get("lumber", 0)), 5, "the estate's timber is held")
	assert_eq(int(reserved.get("castIron", 0)), 5, "and its iron")
	var kept: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 0, {}, reserved
	)
	assert_eq(_offered(kept, "lumber"), 0, "no timber goes to market")
	assert_eq(_offered(kept, "castIron"), 0, "no iron either")

	var partly: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 0, {}, {"lumber": 2}
	)
	assert_eq(_offered(partly, "lumber"), 3, "only the row the work needs is held")


func test_bids_short_build_inputs_with_free_holds_and_the_purse() -> void:
	var economy: PlayerEconomy = _economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
	var bids: Array = plan["bids"]
	assert_eq(bids.size(), 3, "baseline bid-type cap")
	for raw: Variant in bids:
		var bid: Dictionary = raw
		assert_true(int(bid["quantity"]) <= 5)
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["bought"] as Array).size(), 3)
	assert_true(economy.quantity("bronze") > 0)


func test_no_bid_can_break_the_minimum_treasury() -> void:
	var economy: PlayerEconomy = _economy({"lumber": 0, "castIron": 0}, 520)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
	var spend: int = 0
	for raw: Variant in plan["bids"]:
		var bid: Dictionary = raw
		spend += int(bid["quantity"]) * int(market.price(String(bid["commodity"])))
	assert_true(spend <= 20, "only the £20 above the floor may be bid")
	assert_true(economy.treasury - spend >= 500 - 1)


func test_trade_fairs_raise_the_bid_type_cap_to_six() -> void:
	var economy: PlayerEconomy = _economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0, "steel": 0, "bronze": 0},
		100000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 100, {"trade_fairs": true}
	)
	assert_eq((plan["bids"] as Array).size(), 6)


func test_a_buyer_spends_only_its_own_holds() -> void:
	var economy: PlayerEconomy = _economy({}, 5000)
	var market := WorldMarket.with_default_prices()
	assert_true(bool(market.buy(economy, "grain", 2, 1)["ok"]))
	assert_eq(market.bought_units_for(1), 2)
	assert_eq(market.bought_units_for(0), 0)
	assert_eq(market.bought_units(), 2, "the price book still sees the tonnage")
	assert_true(bool(market.buy(economy, "grain", 1)["ok"]))
	assert_eq(market.bought_units_for(0), 1)
	assert_eq(TradeCargo.used(market, 1), 2)
	assert_eq(TradeCargo.used(market, 0), 1)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.bought_units_for(1), 2)
	assert_eq(restored.bought_units_for(0), 1)


func test_missing_inputs_make_the_plan_empty() -> void:
	var economy: PlayerEconomy = _economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	assert_true((AiMarketPlanner.plan(null, economy, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_config(), null, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_config(), economy, null, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.apply(null, null, {})["sold"] as Array).is_empty())


func test_offers_stop_at_the_type_cap() -> void:
	var economy: PlayerEconomy = _economy({
		"grain": 100, "timber": 100, "iron": 100, "wool": 100,
	})
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, WorldMarket.with_default_prices(), 0
	)
	assert_eq((plan["offers"] as Array).size(), 3)


func test_a_refused_trade_is_reported_not_swallowed() -> void:
	var economy: PlayerEconomy = _economy({"grain": 0}, 0)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = {
		"offers": [{"commodity": "grain", "quantity": 5}],
		"bids": [{"commodity": "lumber", "quantity": 5, "unit_price": 60}],
	}
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 0)
	assert_eq((result["bought"] as Array).size(), 0)
	assert_eq((result["refused"] as Array).size(), 2)


func test_price_falls_back_to_the_catalog_and_zero_sales_are_refused() -> void:
	var market := WorldMarket.with_default_prices()
	market.prices.erase("grain")
	assert_eq(market.price("grain"), CommodityCatalog.base_price("grain"))
	var economy: PlayerEconomy = _economy({"grain": 4})
	assert_false(bool(market.sell(economy, "grain", 0)["ok"]))


func test_a_legacy_book_attributes_bids_to_the_player() -> void:
	var market: WorldMarket = WorldMarket.from_dict({"bids": {"grain": 3}})
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 0)
	var economy: PlayerEconomy = _economy({}, 5000)
	assert_true(bool(market.buy(economy, "grain", 1, 1)["ok"]))
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 1)


func test_a_plan_stages_orders_for_the_turn_end_auction() -> void:
	var economy: PlayerEconomy = _economy(
		{"grain": 100, "lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
	plan["free_holds"] = 20
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, CONFIG_FACTION, {}
	)
	assert_eq((result["refused"] as Array).size(), 0)
	assert_gt((result["staged"] as Array).size(), 0)
	assert_eq(economy.quantity("grain"), 100, "nothing moves before the clearing")
	assert_gt(market.book.pending_buy_units(CONFIG_FACTION), 0)
	var cleared: Dictionary = MarketClearing.clear(
		market, WorldMap.new(), {CONFIG_FACTION: economy}, {CONFIG_FACTION: 20}
	)
	assert_gt((cleared["deals"] as Array).size(), 0)
	assert_gt(economy.total_units(), 100)


func test_a_stage_refuses_what_the_book_cannot_cover() -> void:
	var economy: PlayerEconomy = _economy({"grain": 0}, 10)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = {
		"free_holds": 0,
		"offers": [{"commodity": "grain", "quantity": 5}],
		"bids": [{"commodity": "timber", "quantity": 5}],
	}
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, CONFIG_FACTION, {}
	)
	assert_eq((result["staged"] as Array).size(), 0)
	assert_eq((result["refused"] as Array).size(), 2)


## Rival Merchants buy Minor and Tribe land (wiki: civilian-units § Merchant,
## § Work Order Summary; civilian-work-planner § Merchant tasks). The court
## answers the same gates as the player — embassy, no war, prospected minerals,
## 15 x base price — and the deed is charged to its own ledger, never the human
## crown's (REQ-P2-03, REQ-P3-03).

const Fixture = preload("res://tests/civilian_fixture.gd")

const GRAIN: Vector2i = Vector2i(3, 1)
const IRON: Vector2i = Vector2i(2, 1)
const AWAY: Vector2i = Vector2i(1, 1)
const MINOR: int = 6
## The second Minor Nation the deed-targeting cases pair with Genoa: a dearer
## iron deed, so the cheapest offer names one seller and not the other
## (issue #841).
const DEED_MINOR: int = 6
const DEAR_MINOR: int = 7


func test_a_merchant_on_a_genoese_grain_tile_signs_the_deed() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant: CivilianState = _merchant(GRAIN)
	var plan: Dictionary = _market_plan(model, [merchant])

	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), "purchase_land")
	assert_eq(Vector2i(plan["orders"][0]["tile"]), GRAIN)
	assert_true((plan["moves"] as Array).is_empty(), "standing on the tile, it works")


func test_a_merchant_away_from_the_offer_walks_toward_it() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant: CivilianState = _merchant(AWAY)
	var plan: Dictionary = _market_plan(model, [merchant])

	assert_true((plan["orders"] as Array).is_empty(), "the tile is out of reach")
	var moves: Array = plan["moves"]
	assert_eq(moves.size(), 1)
	var move_tile: Vector2i = moves[0]["tile"]
	assert_eq(move_tile, IRON, "one step into the Minor's land")


func test_without_an_embassy_the_merchant_stays_home() -> void:
	var model: MapModel = Fixture.build_minor()
	var court := DiplomacyState.new()
	court.initialize(1)
	court.ensure_relation(0, MINOR, 1)
	var plan: Dictionary = _market_plan(model, [_merchant(GRAIN)], court)

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())


func test_a_war_with_the_seller_closes_the_market() -> void:
	var model: MapModel = Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var court: DiplomacyState = Fixture.merchant_court()
	assert_true(
		bool(DiplomacyRules.declare_war(court, 0, MINOR, true, world).get("ok", false))
	)
	var plan: Dictionary = _market_plan(model, [_merchant(GRAIN)], court)

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())


func test_a_deeded_tile_is_offered_to_nobody_again() -> void:
	var model: MapModel = Fixture.build_minor()
	assert_true(model.purchase_tile(GRAIN, 1), "a rival's deed")
	var plan: Dictionary = _market_plan(model, [_merchant(GRAIN)])

	assert_true((plan["orders"] as Array).is_empty())
	assert_true(
		(plan["moves"] as Array).is_empty(),
		"the only other offer needs a prospect, so the merchant idles"
	)


func test_a_mineral_waits_for_the_explorers_prospect() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant: CivilianState = _merchant(IRON)
	var plan: Dictionary = _market_plan(model, [merchant])

	assert_true((plan["orders"] as Array).is_empty(), "iron is not prospected yet")
	var move_tile: Vector2i = (plan["moves"] as Array)[0]["tile"]
	assert_eq(move_tile, GRAIN, "the grain deed wins")

	works.set_prospected(0, model, IRON)
	var ready: Dictionary = _market_plan(model, [merchant], null, works)
	assert_eq((ready["orders"] as Array).size(), 1)
	assert_eq(Vector2i(ready["orders"][0]["tile"]), IRON)


func test_a_court_with_a_deed_on_offer_trains_one_merchant() -> void:
	var model: MapModel = Fixture.build_minor()
	var roster: Array = _staffed_roster()
	var context: Dictionary = _market_context(model, Fixture.merchant_court())
	var plan: Dictionary = _market_plan(model, roster, Fixture.merchant_court(), null, context)

	assert_true(bool(plan["training"].get("ok", false)))
	assert_eq(String(plan["training"]["type_id"]), "merchant")

	var techless: Dictionary = _market_context(model, Fixture.merchant_court())
	techless["tech_unlocked"] = {}
	var plain: Dictionary = _market_plan(model, roster, Fixture.merchant_court(), null, techless)
	assert_true(
		(plain["training"] as Dictionary).is_empty(),
		"no merchant companies and the staff is already at target"
	)


func test_one_merchant_is_enough() -> void:
	var model: MapModel = Fixture.build_minor()
	var roster: Array = _staffed_roster()
	roster.append(CivilianState.create(9, 0, "merchant", Vector2i(0, 2)))
	var plan: Dictionary = _market_plan(model, roster)

	assert_true(
		(plan["training"] as Dictionary).is_empty(),
		"one merchant fills the deed slot; the college trains nothing more"
	)


## The Build/Work pass answers each owner with its own ledger: the rival's deed
## debits the rival, and the human crown's purse is untouched (wiki:
## civilian-units § Merchant — "debit at completion").
func test_a_rivals_deed_is_charged_to_the_rival_ledger() -> void:
	var model: MapModel = Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var merchant: CivilianState = layer.add_unit(1, "merchant", GRAIN)
	var court: DiplomacyState = Fixture.merchant_court()
	court.ensure_relation(1, MINOR, 1)
	court.set_overture(1, MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	var units: Array[CivilianState] = [merchant]
	var context: Dictionary = {"treasury": 5000, "diplomacy": court}
	var check: Dictionary = CivilianWork.assign(
		model, merchant, "purchase_land", layer.works, units, Fixture.stockpile(),
		null, GRAIN, {}, {}, context
	)
	assert_true(bool(check.get("ok", false)), String(check.get("reason", "")))

	var human: PlayerEconomy = _ledger(5000)
	var rival: PlayerEconomy = _ledger(5000)
	var reports: Array[Dictionary] = CivilianTurnPass.resolve(
		layer, world, null, {0: human, 1: rival}
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(rival.treasury, 4250, "the rival paid the price")
	assert_eq(human.treasury, 5000, "the human purse is untouched")
	assert_true(model.is_purchased_tile(GRAIN))
	assert_eq(model.owner_at(GRAIN.x, GRAIN.y), 1)
	layer.free()


## A deed is never recorded without a purse to close it (wiki: § Merchant —
## the price is debited when the work completes).
func test_a_deed_without_a_ledger_is_not_signed() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant: CivilianState = _merchant(GRAIN)
	var units: Array[CivilianState] = [merchant]
	var context: Dictionary = {"treasury": 5000, "diplomacy": Fixture.merchant_court()}
	assert_true(bool(CivilianWork.assign(
		model, merchant, "purchase_land", works, units, Fixture.stockpile(), null,
		GRAIN, {}, {}, context
	).get("ok", false)))

	var reports: Array[Dictionary] = CivilianWork.resolve_turn(model, units, works)
	assert_true(bool(reports[0]["completed"]))
	assert_false(model.is_purchased_tile(GRAIN), "no ledger, no deed")
	assert_false(LandPurchase.complete(model, GRAIN, 0, null))


## The whole rival pass: the economy adapter musters the order for a court that
## already holds the embassy and the tech, and the next Build/Work signs it from
## that court's own purse (wiki: civilian-units § Merchant; docs/ai.md).
func test_the_rival_turn_signs_the_deed_for_its_own_crown() -> void:
	var model: MapModel = Fixture.build_minor()
	model.provinces[0].owner = 1
	model.faction_ids.append(1)
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var merchant: CivilianState = layer.add_unit(1, "merchant", GRAIN)
	# `spawn(place_units=false)` prepares the works only; the adapter walks the
	# region table, so the roster must be registered like a mustered crew.
	layer.regions.set_region(model.region_id, layer.units)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.civilian_layer = layer
	play.map_seed = 1500
	play.ai = AiState.new()
	play.diplomacy = Fixture.merchant_court()
	play.diplomacy.ensure_relation(1, MINOR, 1)
	play.diplomacy.set_overture(1, MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	var ledger: PlayerEconomy = play.ai.economy_for(1)
	ledger.tech_unlocked["merchant_companies"] = true
	ledger.treasury = 5000

	MapPlayEconomyAi.run(play)
	assert_true(merchant.is_working(), "the rival turn musters the purchase")
	assert_eq(merchant.work_action(), "purchase_land")
	assert_eq(merchant.work_tile(), GRAIN)

	var purse: int = ledger.treasury
	CivilianTurnPass.resolve(layer, world, null, {1: ledger})
	assert_true(model.is_purchased_tile(GRAIN), "the deed is signed next turn")
	assert_eq(ledger.treasury, purse - 750, "the buyer's own purse paid")


## Only a Merchant carries the order, and a tile another crew already holds is
## not offered twice (wiki: civilian-units § Per-player tile exclusivity).
func test_only_a_merchant_and_an_unreserved_tile_get_the_order() -> void:
	var model: MapModel = Fixture.build_minor()
	var context: Dictionary = _market_context(model, Fixture.merchant_court())
	var builder: CivilianState = CivilianState.create(1, 0, "builder", GRAIN)
	var none: Dictionary = AiMerchantWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, builder, [builder], LandWorks.new(),
		Fixture.stockpile(), {}, {}, context, {}
	))
	assert_true(none.is_empty(), "a builder cannot buy land")
	var merchant: CivilianState = _merchant(GRAIN)
	var taken: Dictionary = AiMerchantWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, merchant, [merchant], LandWorks.new(),
		Fixture.stockpile(), {}, {}, context, {GRAIN: true}
	))
	assert_true(taken.is_empty(), "another crew already has this tile")


## An empty purse or an unaffordable price leaves nothing on offer, and a deed
## is never a Great Power's to sell (wiki: civilian-units § Merchant).
func test_an_empty_purse_and_a_great_power_land_offer_nothing() -> void:
	var model: MapModel = Fixture.build_minor()
	var court: DiplomacyState = Fixture.merchant_court()
	assert_true(
		AiMerchantWork.buyable_tiles(model, 0, LandWorks.new(), {
			"treasury": 0, "diplomacy": court,
		}).is_empty(),
		"no treasury, no offer"
	)
	var gp: MapModel = Fixture.build()
	var gp_court := DiplomacyState.new()
	gp_court.initialize(1)
	gp_court.ensure_relation(0, 1, 1)
	gp_court.set_overture(0, 1, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(
		AiMerchantWork.buyable_tiles(gp, 0, LandWorks.new(), {
			"treasury": 5000, "diplomacy": gp_court,
		}).is_empty(),
		"only Minor Nations and Tribes sell land"
	)
	assert_eq(AiMerchantWork.cheapest_offer(gp, 0, 1, 5000), 0)
	assert_true(AiMerchantWork.best_move(gp, _merchant(GRAIN), LandWorks.new()).is_empty())


## A boycott leaves the rival merchant no deed to walk to: the rules would refuse
## every purchase from the issuer's colony, so the planner must not name one
## (wiki: diplomacy § GP–Tribe — Boycott, R6; REQ-P2-03).
func test_a_boycott_leaves_the_rival_merchant_no_deed_to_walk_to() -> void:
	var model: MapModel = Fixture.build_minor()
	model.provinces[1].owner = BOYCOTTED_COLONY_TRIBE
	var court := DiplomacyState.new()
	court.initialize(1)
	court.ensure_relation(0, BOYCOTTED_COLONY_TRIBE, 1)
	court.set_overture(0, BOYCOTTED_COLONY_TRIBE, DiplomacyCatalog.STAGE_EMBASSY)
	court.set_colony(BOYCOTTED_COLONY_TRIBE, BOYCOTT_ISSUER)
	court.ensure_relation(BOYCOTT_ISSUER, 0, 1)
	assert_true(bool(DiplomacyTrade.boycott(court, BOYCOTT_ISSUER, 0)["ok"]))
	var context: Dictionary = _market_context(model, court)
	assert_true(
		AiMerchantWork.buyable_tiles(model, 0, LandWorks.new(), context).is_empty(),
		"no deed is on offer across the boycott"
	)
	assert_true(
		AiMerchantWork.best_move(model, _merchant(GRAIN), LandWorks.new(), context).is_empty(),
		"and the merchant has nowhere to march"
	)
	court.end_turn()
	assert_true(bool(DiplomacyTrade.revoke_boycott(court, BOYCOTT_ISSUER, 0)["ok"]))
	assert_false(
		AiMerchantWork.buyable_tiles(model, 0, LandWorks.new(), context).is_empty(),
		"lifting the boycott puts the deed back on offer"
	)


# --- the Merchant's deed ground is the Explorer's to read (issue #1383) -------


## A rival Explorer reads the Minor's unsurveyed hills when its court could sign
## the deed that ground is sold by, and leaves them alone with no embassy: the
## deposit is never named, only the ground is dug (issue #1383; wiki:
## civilian-units § Merchant; fog-and-exploration § Prospect-Required Resources).
func test_a_rival_explorer_digs_the_ground_its_merchant_could_buy() -> void:
	var model: MapModel = Fixture.build_minor()
	var iron: Vector2i = Vector2i(2, 1)
	var unit: CivilianState = CivilianState.create(1, 0, "explorer", iron)
	var work: Dictionary = AiExplorerWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, unit, [unit], LandWorks.new(),
		Fixture.stockpile(), {}, {}, _deed_context(Fixture.merchant_court()), {}
	))
	assert_eq(String(work.get("action", "")), "prospect", "the embassy opens the Minor's ground")
	assert_eq(Vector2i(work.get("tile", CivilianState.NO_TILE)), iron)
	assert_true(
		AiExplorerWork.best_candidate(_work_query(
			AiConfig.build(0, 1500), model, unit, [unit], LandWorks.new(),
			Fixture.stockpile(), {}, {},
			_deed_context(Fixture.merchant_court_unembarked()), {}
		)).is_empty(),
		"a court with no embassy reads no foreign ground"
	)


## And it walks there: the deed ground joins the crown's own tiles on the survey
## walk, so the rich tile is charted before the Merchant can sign it (issue
## #1383).
func test_a_rival_explorer_walks_to_the_ground_its_deed_covers() -> void:
	var model: MapModel = Fixture.build_minor()
	var unit: CivilianState = CivilianState.create(1, 0, "explorer", Vector2i(1, 1))
	var march: Dictionary = AiExplorerWork.best_move(
		model, unit, LandWorks.new(), _deed_context(Fixture.merchant_court())
	)
	assert_eq(String(march.get("kind", "")), "move", "the Minor's hills are a survey step away")
	assert_eq(Vector2i(march.get("tile", CivilianState.NO_TILE)), Vector2i(2, 1))
	assert_true(
		AiExplorerWork.best_move(
			model, unit, LandWorks.new(), _deed_context(Fixture.merchant_court_unembarked())
		).is_empty(),
		"with no deed to sign the crown's own land is all it reads"
	)


## War and the absence of a court close the ground, exactly as they close the
## deed (issue #1383; wiki: civilian-units § Merchant).
func test_war_shuts_the_miners_ground_to_the_survey() -> void:
	var model: MapModel = Fixture.build_minor()
	var iron: Vector2i = Vector2i(2, 1)
	var court: DiplomacyState = Fixture.merchant_court()
	assert_true(
		AiExplorerWork.deed_ground(model, 0, iron, {"diplomacy": court}),
		"the standing embassy opens the ground"
	)
	var world := WorldMap.new()
	world.add_region(model)
	assert_true(bool(DiplomacyRules.declare_war(court, 0, MINOR, true, world).get("ok", false)))
	assert_false(
		AiExplorerWork.deed_ground(model, 0, iron, {"diplomacy": court}),
		"a war closes the deed, so it closes the survey"
	)
	assert_false(
		AiExplorerWork.deed_ground(model, 0, iron, {}),
		"no court published, no foreign ground read"
	)
	assert_false(
		AiExplorerWork.deed_ground(model, 0, Vector2i(0, 0), {"diplomacy": court}),
		"a crown's own ground is not a deed"
	)


## A deed that clears to the treasury outranks a crop deed of the same published
## price: spices (50) and grain (50) both cost 750, and the rich tile scores the
## cash it pays beside the want of it (issue #1383, #1382).
func test_a_riches_deed_outranks_a_crop_deed_of_the_same_price() -> void:
	var model: MapModel = Fixture.build_minor()
	var spice_tile: Vector2i = Vector2i(2, 2)
	model.resource[model.index_of(spice_tile.x, spice_tile.y)] = 17
	assert_eq(LandPurchase.cost(model, GRAIN), LandPurchase.cost(model, spice_tile))
	var context: Dictionary = _deed_context(Fixture.merchant_court())
	var grain: Dictionary = AiMerchantWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, _merchant(GRAIN), [_merchant(GRAIN)],
		LandWorks.new(), Fixture.stockpile(), {}, {}, context, {}
	))
	var spice: Dictionary = AiMerchantWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, _merchant(spice_tile), [_merchant(spice_tile)],
		LandWorks.new(), Fixture.stockpile(), {}, {}, context, {}
	))
	assert_eq(String(grain.get("action", "")), "purchase_land", "the crop deed is on offer")
	assert_eq(String(spice.get("action", "")), "purchase_land", "the rich deed is on offer")
	assert_true(
		int(spice.get("score", 0)) > int(grain.get("score", 0)),
		"the same price, and the rich tile wins"
	)


# --- fixtures ----------------------------------------------------------------

func _merchant(tile: Vector2i, owner: int = 0) -> CivilianState:
	return CivilianState.create(1, owner, "merchant", tile)


func _ledger(treasury: int) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


## Two builders, an engineer, an explorer and a spy: every earlier training slot
## is filled, so the merchant is the next craft the court would want.
## Builders, engineer_target, explorer_target and a spy: every earlier training
## slot is filled, so a deed on offer makes the merchant the next craft.
func _staffed_roster() -> Array:
	return [
		CivilianState.create(1, 0, "builder", Vector2i(0, 0)),
		CivilianState.create(2, 0, "builder", Vector2i(1, 0)),
		CivilianState.create(3, 0, "engineer", Vector2i(0, 1)),
		CivilianState.create(6, 0, "engineer", Vector2i(1, 2)),
		CivilianState.create(4, 0, "explorer", Vector2i(1, 1)),
		CivilianState.create(7, 0, "explorer", Vector2i(0, 0)),
		CivilianState.create(8, 0, "explorer", Vector2i(1, 0)),
		CivilianState.create(5, 0, "spy", Vector2i(0, 2)),
	]


func _market_context(
	model: MapModel, court: DiplomacyState, treasury: int = 5000
) -> Dictionary:
	return {
		"treasury": treasury,
		"paper": 8,
		"capital_province": 0,
		"capital_tile": Vector2i(0, 0),
		"at_war": false,
		"diplomacy": court,
		"tech_unlocked": {"merchant_companies": true},
		"visibility": Fixture.visibility(model),
	}


## The reading the deed gate takes (issue #1383): a purse, a court and no chart,
## so the published every-tile-charted fixture reading stands and only the bond
## decides.
func _deed_context(court: DiplomacyState, treasury: int = 5000) -> Dictionary:
	return {"treasury": treasury, "diplomacy": court, "at_war": false}


## The deed door's own reading: the court is neutral here, so the staff targets
## are the region's own work and the archetype's extra crew cannot colour a
## merchant test (AiStaffTaste has its own cases).
func _market_plan(
	model: MapModel,
	units: Array,
	court: DiplomacyState = null,
	works: LandWorks = null,
	context: Dictionary = {}
) -> Dictionary:
	var diplomacy: DiplomacyState = court if court != null else Fixture.merchant_court()
	var config: AiConfig = AiConfig.build(0, 1500)
	config.personality = AiPersonality.NEUTRAL
	return AiCivilianPlanner.plan(
		config, model, units, works if works != null else LandWorks.new(),
		Fixture.stockpile(), {}, {"merchant_companies": true},
		context if not context.is_empty() else _market_context(model, diplomacy)
	)


## The purse does not price the chain: the Merchant tech is the buyer the chain
## serves, and the envoy takes turns to walk while the purse refills, so a charted
## deed opens it even on this turn's floor (issue #724 task 2).
func test_the_envoy_chain_stays_legal_on_a_thin_purse() -> void:
	var model: MapModel = Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var state := DiplomacyState.new()
	state.initialize(1)
	var config: AiConfig = AiConfig.build(0, 1500)
	config.personality = AiPersonality.NEUTRAL
	config.agenda_traits = AiAgenda.NEUTRAL

	var broke: Dictionary = _overture(world, state, config, {
		"merchant_companies": true,
	}, DiplomacyCatalog.CONSULATE_COST)
	var paid: Dictionary = _overture(world, state, config, {
		"merchant_companies": true,
	})
	assert_true(
		bool(broke.get("ok", false)),
		"the chain is legal on a purse that covers the Consulate alone"
	)
	assert_eq(
		int(broke["utility"]), int(paid["utility"]),
		"a priced deed opens the chain at any purse the stage fits"
	)


func _overture(
	world: WorldMap, state: DiplomacyState, config: AiConfig, tech: Dictionary,
	treasury: int = 5000, target: int = MINOR
) -> Dictionary:
	var context: Dictionary = {
		"treasury": {config.faction: treasury},
		"tech": {config.faction: tech},
		"player": -1,
	}
	var entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		config, state, AiState.new(), world, 1, target, 50, context
	)
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) == AiDiplomacyOffers.KIND_OVERTURE:
			return entry
	return {}


## Rival cargo routes (wiki: economy-planner § Cargo; DR-20261110-26): idle
## merchant squadrons sail home so their holds count at the seat, and a court
## whose colonial tonnage and trade holds outrun the berths lays down one more
## hull through the same yard and movement gates the human uses.

const OWNER: int = 1


func _market_old_world() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0 if x < 4 else 1
			if x < 4:
				tiles.append(tile)
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var province := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), OWNER, true
	)
	province.capital_tile = Vector2i(0, 0)
	province.port_tile = Vector2i(0, 1)
	province.coastal = true
	var harbour: Array[Vector2i] = [Vector2i(4, 0), Vector2i(4, 1)]
	var outport := ProvinceState.create(
		1, "Outport", harbour, Vector2(4.0, 0.5), harbour.size(), OWNER, false
	)
	outport.port_tile = Vector2i(4, 1)
	outport.coastal = true
	model.provinces = [province, outport]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model


func _cargo_config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)


func _cargo_economy(treasury: int = 2500) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


func _merchant_fleet(fleet_id: int, type_id: String = "carrack") -> FleetState:
	var hull_id: String = "hull_%d" % fleet_id
	return FleetState.at_sea(fleet_id, OWNER, 0, [hull_id], {hull_id: type_id})


func test_an_idle_merchant_squadron_is_walked_home_and_docks() -> void:
	var model: MapModel = _market_old_world()
	var fleet: FleetState = _merchant_fleet(1)
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1, "one idle merchant squadron is ordered home")
	assert_true(bool(routes[0]["dock"]), "the seat's harbour borders the zone")
	var moved: Dictionary = AiCargoPlanner.apply_route(model, fleet, routes[0])
	assert_true(bool(moved["ok"]))
	assert_true(fleet.is_in_port())
	assert_eq(fleet.province, 0, "it berths at the crown's seat")
	assert_eq(int(plan["holds"]), 0, "the holds did not count afloat")
	assert_eq(int(plan["projected"]), 3, "the projected berths count its cargo")


func test_a_warship_is_never_a_cargo_route() -> void:
	var model: MapModel = _market_old_world()
	var sloop := FleetState.at_sea(2, OWNER, 0, ["hull_2"], {"hull_2": "sloop"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [sloop], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty(), "no purse for a hull yet")


func test_a_merchant_in_another_port_puts_to_sea_toward_the_seat() -> void:
	var model: MapModel = _market_old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1)
	assert_true(not bool(routes[0]["dock"]), "the outport is not the seat")
	assert_eq(int(routes[0]["zone"]), 0, "it puts to sea into the seat's water")


func test_hostile_water_holds_a_merchant_in_port() -> void:
	var model: MapModel = _market_old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5, {0: true}
	)
	assert_true((plan["routes"] as Array).is_empty(), "it waits for safer water")


func test_berths_at_the_seat_already_cover_the_need() -> void:
	var model: MapModel = _market_old_world()
	var fluyte := FleetState.in_port(3, OWNER, 0, ["hull_3"], {"hull_3": "fluyte"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(20000), model, [fluyte], 0, 4
	)
	assert_eq(int(plan["holds"]), 4, "a fluyte's four holds are home cargo")
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty())


func test_a_shortfall_that_pays_lays_down_a_merchant_hull() -> void:
	var model: MapModel = _market_old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(20000), model, [], 0, 10
	)
	var launch: Dictionary = plan["launch"]
	assert_eq(String(launch.get("kind", "")), "launch")
	assert_eq(String(launch.get("type_id", "")), "carrack", "the only buildable hull")
	assert_eq(int(launch.get("cargo", 0)), 3)


func test_the_better_merchant_wins_on_cargo_then_price() -> void:
	var model: MapModel = _market_old_world()
	var economy: PlayerEconomy = _cargo_economy(20000)
	economy.tech_unlocked["superior_hull_design"] = true
	var plan: Dictionary = AiCargoPlanner.plan(_cargo_config(), economy, model, [], 0, 10)
	assert_eq(
		String(plan["launch"].get("type_id", "")), "fluyte",
		"four holds for less money beats three"
	)


func test_the_purse_floor_keeps_the_yard_shut() -> void:
	var model: MapModel = _market_old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(9000), model, [], 0, 10
	)
	assert_true((plan["launch"] as Dictionary).is_empty(), "£1,000 left is not enough")


func test_a_squadron_carrying_an_expedition_keeps_its_course() -> void:
	var model: MapModel = _market_old_world()
	var fleet: FleetState = _merchant_fleet(4)
	fleet.embarked_army = 7
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())


func test_cargo_missing_inputs_make_the_plan_empty() -> void:
	var model: MapModel = _market_old_world()
	assert_true((AiCargoPlanner.plan(null, _cargo_economy(), model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_cargo_config(), null, model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_cargo_config(), _cargo_economy(), null, [], 0, 5)["routes"] as Array).is_empty())
	assert_true(not bool(AiCargoPlanner.apply_route(model, null, {})["ok"]))


# --- applied orders (MapPlayCargoAi) ----------------------------------------


func _market_session(model: MapModel, fleets: Array[FleetState]) -> Dictionary:
	var play := PlaySession.new()
	play.map_seed = 1
	play.player_faction = 0
	var world := WorldMap.new()
	world.add_region(model)
	play.world = world
	var ships := ShipLayer.new()
	ships.player_faction = 0
	ships.regions.set_region(model.region_id, fleets)
	play.ship_layer = ships
	return {"play": play, "ships": ships, "model": model}


func test_the_adapter_docks_a_rival_squadron_and_its_holds_count() -> void:
	var model: MapModel = _market_old_world()
	var fleet: FleetState = _merchant_fleet(1)
	var built: Dictionary = _market_session(model, [fleet])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _cargo_economy()
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, economy, {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_in_port())
	assert_eq(
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), OWNER),
		3, "the docked hull's three holds now count"
	)
	(built["ships"] as Node).free()


## A merchant coming home folds into the home fleet as she docks: the cargo pass
## only moves hulls, so without the fold the seat would end the order holding two
## squadrons (wiki: ships-and-naval § Home Fleet — "any naval move that docks at
## the capital resolves by merging").
func test_the_adapter_folds_a_merchant_docking_at_the_seat_into_the_home_fleet() -> void:
	var model: MapModel = _market_old_world()
	var home := FleetState.in_port(2, OWNER, 0, ["hull_home"], {"hull_home": "fluyte"})
	var merchant: FleetState = _merchant_fleet(1)
	var built: Dictionary = _market_session(model, [home, merchant])
	var play: PlaySession = built["play"]
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, _cargo_economy(), {"used": 0, "left_total": 6}
	)
	assert_eq((report["routes"] as Array).size(), 1, "the merchant is walked home")
	var roster: Array = play.ship_layer.regions.value(model.region_id, [])
	assert_false(roster.has(merchant), "the docked squadron joins the home fleet")
	assert_true(home.hulls.has("hull_1"), "the hull keeps its instance id")
	var at_seat: int = 0
	for fleet: FleetState in roster:
		if fleet.is_in_port() and fleet.province == 0:
			at_seat += 1
	assert_eq(at_seat, 1, "one squadron in port at the seat")
	(built["ships"] as Node).free()


func test_the_adapter_puts_a_merchant_to_sea_for_the_crossing() -> void:
	var model: MapModel = _market_old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var built: Dictionary = _market_session(model, [fleet])
	var play: PlaySession = built["play"]
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, _cargo_economy(), {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_at_sea(), "the outport merchant puts to sea")
	assert_eq(fleet.sea_zone, 0)
	(built["ships"] as Node).free()


func test_the_adapter_keeps_a_merchant_out_of_hostile_water() -> void:
	var model: MapModel = _market_old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var player := FleetState.at_sea(9, 0, 0, ["hull_9"], {"hull_9": "carrack"})
	var built: Dictionary = _market_session(model, [fleet, player])
	var play: PlaySession = built["play"]
	var state := DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(OWNER, 0, 1)
	assert_true(bool(DiplomacyRules.declare_war(state, OWNER, 0)["ok"]))
	play.diplomacy = state
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, _cargo_economy(), {"used": 0, "left_total": 2}
	)
	assert_true((report["routes"] as Array).is_empty())
	assert_true(fleet.is_in_port(), "the merchant never enters the hostile zone")
	(built["ships"] as Node).free()


func test_the_adapter_founds_a_slip_when_no_squadron_is_in_port() -> void:
	var model: MapModel = _market_old_world()
	var built: Dictionary = _market_session(model, [])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _cargo_economy(20000)
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, economy, {"used": 0, "left_total": 8}
	)
	var launch: Dictionary = report["launch"]
	assert_eq(String(launch.get("type_id", "")), "carrack")
	assert_true(bool(launch.get("founded", false)), "the yard founds the home squadron")
	var roster: Array = play.ship_layer.regions.value(model.region_id, [])
	assert_eq(roster.size(), 1)
	var fleet: FleetState = roster[0]
	assert_true(fleet.is_in_port() and fleet.province == 0)
	assert_eq(economy.treasury, 12000, "the yard took its published price")
	(built["ships"] as Node).free()


func test_a_court_saving_for_its_muster_never_bids_the_war_chest_away() -> void:
	# 3,000 treasury bids freely against the published £500 floor; with the
	# muster price held back (1,000 kept + 2,000 levies) it may bid nothing.
	var stock: Dictionary = {"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}
	var economy: PlayerEconomy = _economy(stock, 3000)
	var market := WorldMarket.with_default_prices()
	assert_true(
		(AiMarketPlanner.plan(_config(), economy, market, 20)["bids"] as Array).size() > 0,
		"a free purse buys its short inputs"
	)
	assert_eq(
		AiMarketPlanner.plan(_config(), economy, market, 20, {}, {}, {}, 3000)["bids"],
		[] as Array[Dictionary],
		"the muster comes before the market"
	)
	economy.treasury = 3600
	assert_true(
		(AiMarketPlanner.plan(_config(), economy, market, 20, {}, {}, {}, 3000)["bids"]
			as Array).size() > 0,
		"only the surplus above the war chest is bid"
	)


## Pocket Old World for the rival-blockade harvest case: England seat and a
## coastal estate separated by ocean so the harbour is the only road home. A
## full MapFixture chart + WorldBootstrap made two `MapPlayEconomyLarder.overseas`
## walks pay ~18 s
## under coverage (docs/testing.md § Tiny fixture).
func _blockade_play() -> PlaySession:
	var rival: int = 1
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = FactionCatalog.OLD_WORLD
	model.terrain.fill(MapModel.Terrain.PLAINS)
	# Column 0 = seat; column 2 = coastal estate; columns 1 and 3 = sea.
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(0, 1)]:
		model.province[model.index_of(tile.x, tile.y)] = 0
	for tile: Vector2i in [Vector2i(2, 0), Vector2i(2, 1)]:
		model.province[model.index_of(tile.x, tile.y)] = 1
	model.resource[model.index_of(2, 0)] = WorldBootstrap.GRAIN_RESOURCE
	var seat_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	var coast_tiles: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1)]
	var seat := ProvinceState.create(
		0, "Seat", seat_tiles, Vector2(0.0, 0.5), 2, rival, true
	)
	seat.capital_tile = Vector2i(0, 0)
	var coast := ProvinceState.create(
		1, "Harbour", coast_tiles, Vector2(2.0, 0.5), 2, rival, false
	)
	coast.coastal = true
	coast.resource = WorldBootstrap.GRAIN_RESOURCE
	coast.resource_tile = Vector2i(2, 0)
	model.provinces = [seat, coast]
	model.faction_ids = [rival] as Array[int]
	var sea_tiles: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2),
		Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2),
		Vector2i(0, 2), Vector2i(2, 2),
	]
	for tile: Vector2i in sea_tiles:
		var index: int = model.index_of(tile.x, tile.y)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
		model.province[index] = MapModel.NO_ID
	model.sea_zones = [
		SeaZoneState.create(0, "Channel", sea_tiles, Vector2(2.0, 2.0), sea_tiles.size())
	]
	var world := WorldMap.new()
	world.add_region(model)
	var play := PlaySession.new()
	play.player_faction = FactionCatalog.PLAYER_FACTION
	play.world = world
	play.region_index = 0
	play.model = model
	play.turn = 1
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = model
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = model
	play.civilian_layer.viewer_faction = play.player_faction
	play.civilian_layer.works_regions.set_region(0, LandWorks.new())
	play.civilian_layer.regions.set_region(0, [])
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.human_faction = play.player_faction
	play.ensure_ai()
	return play


## A rival's home harvest is priced against its own sealed ports, exactly as the
## crown's is (wiki: capital-and-connectivity § Blockade — "rival ledgers take
## the same reading so a crown's own blockade bites on both sides"; REQ-P2-03).
## The seat's own ground still yields: a blockade severs the sea, not the land.
func test_a_rivals_home_harvest_reads_its_own_blockade() -> void:
	var play: PlaySession = _blockade_play()
	var rival: int = 1
	var economy: PlayerEconomy = play.ledger_for(rival)
	var home: int = FactionCatalog.region_of(rival)
	var model: MapModel = play.world.region(home)
	var works: LandWorks = play.civilian_layer.works_regions.value(home, null)
	var seat: int = int(WorldBootstrap.capital_seat(model, rival)["province"])
	assert_eq(seat, 0, "pocket chart seats England at province 0")
	# Wire the coastal estate by sea alone: its harvest reaches the crown through
	# its harbour and nothing else.
	var target: int = 1
	var zone: int = 0
	assert_true(
		NavalMovement.provinces_by_zone(model, zone).has(target),
		"the harbour faces the pocket sea zone"
	)
	var chosen: ProvinceState = model.province_data(target)
	for tile: Vector2i in chosen.tiles:
		works.set_transport(model, tile, 1)
		if model.resource_at(tile.x, tile.y) >= 0:
			works.set_improvement(model, tile, 1)
	works.add_port(model, chosen.tiles[0])
	var before: Dictionary = MapPlayEconomyLarder.overseas(play, rival, economy)["extraction"]
	play.diplomacy.ensure_relation(play.player_faction, rival, play.turn)
	DiplomacyRules.declare_war(play.diplomacy, play.player_faction, rival)
	var fleet := FleetState.at_sea(999, play.player_faction, zone)
	fleet.mission = FleetState.Mission.BLOCKADE
	fleet.blockade_province = target
	play.ship_layer.regions.value(home, []).append(fleet)
	var after: Dictionary = MapPlayEconomyLarder.overseas(play, rival, economy)["extraction"]
	assert_ne(before, after, "the sealed harbour's estates leave the rival's harvest")
	assert_true(
		int(after.get("grain", 0)) >= Extraction.CAPITAL_GRAIN_BONUS,
		"the seat's own ground still yields: a blockade severs the sea, not the land"
	)
	play.ship_layer.free()
	play.civilian_layer.free()

# ==== merged from test_ai_campaign_rules.gd (one coverage boot; docs/testing.md § Speed rules) ====
## One boot for the rival campaign plans: invasion, colonisation, court offers and
## the planner that orders them (docs/ai.md).

## Merged from test_ai_invasion, test_ai_colonisation, test_ai_diplomacy_offers,
## test_ai_planner, test_ai_war_memory.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const campaign_NavalFixture = preload("res://tests/naval_fixture.gd")
const campaign_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const ai_diplomacy_offers_AiFixture = preload("res://tests/ai_fixture.gd")
const ai_planner_AiFixture = preload("res://tests/ai_fixture.gd")
const army_AiFixture = preload("res://tests/ai_fixture.gd")

const campaign_OWNER: int = 1
const RIVAL: int = 2
const TRIBE: int = 9
const HULLS: Array[String] = ["h1", "h2"]
const HULL_TYPES: Dictionary = {"h1": "carrack", "h2": "carrack"}
const ai_colonisation_OWNER: int = 1

var ai_diplomacy_offers_state: DiplomacyState
var ai_diplomacy_offers_config: AiConfig
var ai_diplomacy_offers_ai_state: AiState
var ai_planner_state: DiplomacyState
var ai_planner_config: AiConfig
var ai_planner_ai_state: AiState

var _suite_setup: String = ""

func _setup_ai_diplomacy_offers() -> void:
	_suite_setup = "ai_diplomacy_offers"
	ai_diplomacy_offers_state = DiplomacyState.new()
	ai_diplomacy_offers_state.reset(1)
	ai_diplomacy_offers_state.human_faction = 0
	ai_diplomacy_offers_config = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_diplomacy_offers_config.personality = AiPersonality.NEUTRAL
	ai_diplomacy_offers_config.agenda_traits = AiAgenda.NEUTRAL
	ai_diplomacy_offers_ai_state = AiState.new()

func _setup_ai_planner() -> void:
	_suite_setup = "ai_planner"
	ai_planner_state = DiplomacyState.new()
	ai_planner_state.reset(1)
	ai_planner_config = AiConfig.build(FactionCatalog.PLAYER_FACTION, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_ai_state = AiState.new()

# --- test_ai_invasion ---

## `enemy_border` puts a hostile province on the seat's land border, so the
## court has a land war and no reason to sail.
func campaign__old_world(enemy_border: bool = false) -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0 if x < 3 or not enemy_border else 1
			if x < 3 or not enemy_border:
				tiles.append(Vector2i(x, y))
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var seat := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), campaign_OWNER, true
	)
	seat.capital_tile = Vector2i(0, 0)
	seat.port_tile = Vector2i(0, 1)
	seat.coastal = true
	model.provinces = [seat]
	if enemy_border:
		var border_tiles: Array[Vector2i] = []
		for y in 2:
			for x in range(3, 5):
				border_tiles.append(Vector2i(x, y))
		var border := ProvinceState.create(
			1, "Border", border_tiles, Vector2(4.0, 0.5), border_tiles.size(), RIVAL, false
		)
		model.provinces.append(border)
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model

## New World: the enemy coast (province 0) and an own colony (province 1), both
## on the same sea zone so a landing is one step from the crossing.
func campaign__new_world(own_colony: bool = true) -> MapModel:
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = WorldMap.NEW_WORLD
	model.region_key = "new_world"
	for y in 2:
		for x in 4:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		model.province[model.index_of(tile.x, tile.y)] = 0
	if own_colony:
		for tile: Vector2i in [Vector2i(3, 0), Vector2i(3, 1)]:
			model.province[model.index_of(tile.x, tile.y)] = 1
	for x in 4:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var coast_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var coast := ProvinceState.create(0, "Coast", coast_tiles, Vector2(0.5, 0.5), 4, TRIBE, false)
	coast.coastal = true
	model.provinces = [coast]
	if own_colony:
		var colony_tiles: Array[Vector2i] = [Vector2i(3, 0), Vector2i(3, 1)]
		var colony := ProvinceState.create(
			1, "Colony", colony_tiles, Vector2(3.0, 0.5), 3, campaign_OWNER, false
		)
		colony.coastal = true
		model.provinces.append(colony)
	var sea: Array[Vector2i] = []
	for x in 4:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Far Shore", sea, Vector2(1.5, 2.0), 4)]
	return model

func campaign__world(own_colony: bool = true) -> WorldMap:
	var map := WorldMap.new()
	map.add_region(campaign__old_world())
	map.add_region(campaign__new_world(own_colony))
	map.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return map

func campaign__config() -> AiConfig:
	return AiConfig.build(campaign_OWNER, 1500)

func _war(target: int = RIVAL) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(campaign_OWNER, target, 1)
	state.relation(campaign_OWNER, target).at_war = true
	return state

func _peace(target: int = RIVAL) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(campaign_OWNER, target, 1)
	return state

func _home_army(regiments: Array[String] = ["peasant_levies", "pikemen", "squires"]) -> ArmyState:
	return ArmyState.muster(1, campaign_OWNER, 0, true, regiments, 1)

func _field_army(
	regiments: Array[String] = ["pikemen", "squires"], province: int = 0
) -> ArmyState:
	return ArmyState.muster(2, campaign_OWNER, province, false, regiments, 10)

func campaign__squadron(id: int = 1, owner: int = campaign_OWNER, zone: int = 0) -> FleetState:
	return FleetState.at_sea(id, owner, zone, HULLS, HULL_TYPES)

## The seat moves when the old capital is taken; the Home Army must follow it or
## the court can never muster again (issue #474).
func test_a_moved_seat_recalls_the_home_army() -> void:
	assert_eq(AiArmyReinforce.recall_target(14, 20), 20, "the army marches to the new seat")
	assert_eq(AiArmyReinforce.recall_target(20, 20), -1, "an army already home is left alone")
	assert_eq(AiArmyReinforce.recall_target(3, -1), -1, "no seat, no recall")


## The recall itself: a Home Army standing off its seat marches one hop home and
## the pass reports it, so the trace explains why no regiment was raised
## (issue #474).
func test_the_recall_marches_the_home_army_to_the_new_seat() -> void:
	var world: WorldMap = army_AiFixture.land_world([campaign_OWNER, campaign_OWNER], {0: true})
	var model: MapModel = world.region(0)
	var play := PlaySession.new()
	play.world = world
	var home: ArmyState = ArmyState.muster(1, campaign_OWNER, 1, true, ["peasant_levies"], 1)
	var trace: Array[Dictionary] = []

	assert_true(MapPlayArmyMusterAi._recall(play, model, home, campaign_OWNER, 0, trace))
	assert_eq(home.province, 0, "the garrison re-forms at the seat")
	assert_eq(trace.size(), 1)
	assert_eq(String(trace[0]["kind"]), MapPlayArmyMusterAi.KIND_RECALL)
	assert_false(
		MapPlayArmyMusterAi._recall(play, model, home, campaign_OWNER, 0, trace),
		"an army already home is not marched again"
	)


func test_a_war_across_the_water_detaches_a_crossing_army() -> void:
	var world: WorldMap = campaign__world()
	var actions: Array[Dictionary] = AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()], [_home_army()]
	)
	assert_eq(actions.size(), 1)
	assert_eq(String(actions[0]["kind"]), AiInvasionPlanner.KIND_SPLIT)
	assert_eq(int(actions[0]["regiments"].size()), 2, "one regiment keeps the seat")

func test_a_war_on_the_court_s_own_border_stays_a_land_war() -> void:
	var world: WorldMap = _border_world()
	assert_true(AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()], [_home_army()]
	).is_empty(), "the field army is needed on the border")

## The Passage map with a hostile province on the seat's land border.
func _border_world() -> WorldMap:
	var world := WorldMap.new()
	world.add_region(campaign__old_world(true))
	world.add_region(campaign__new_world())
	world.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return world

## The money goal lifts the frontier guard: a court on **earn** sends its spare
## regiments across the Passage even while a war sits on its border, because the
## gold that ends the impasse is overseas (DR-20261113-19).
func test_an_earning_court_sails_into_a_border_war() -> void:
	var world: WorldMap = _border_world()
	var armies: Array = [_home_army()]
	assert_true(AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()], armies
	).is_empty(), "the published rule keeps the army home")
	var earning: Array[Dictionary] = AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()], armies, null, true
	)
	assert_eq(earning.size(), 1, "a court on earn sails for the far coast")
	assert_eq(
		int(earning[0]["regiments"].size()), 2,
		"one regiment always keeps the seat"
	)

## The bar's land comes before the far gold: once the court presses for the bar
## it must clear, the earn lift no longer sails its host away from the land the
## bar counts, so the field army stays where the victory is (issue #995). A court
## far from the bar keeps the published lift (the case above).
func test_a_court_pressing_for_the_bar_keeps_its_host_at_home() -> void:
	var world: WorldMap = _border_world()
	# Grow the court's Old World land into the press band (`victory.pressure_start`
	# of the 31 every rival's bar holds).
	var old: MapModel = world.region(0)
	for index in 8:
		old.provinces.append(ProvinceState.create(
			100 + index, "Extra %d" % index, [] as Array[Vector2i], Vector2.ZERO,
			0, campaign_OWNER, false
		))
	var actions: Array[Dictionary] = AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, old, [campaign__squadron()],
		[_home_army()], null, true
	)
	assert_true(actions.is_empty(), "the pressing court's host stays on the bar's land")

## The defence guard survives the goal: a hostile host already standing on the
## court's own soil is never left behind (DR-20261113-19).
func test_a_hostile_host_on_the_court_s_soil_keeps_the_army_home() -> void:
	var world: WorldMap = _border_world()
	var invader: ArmyState = ArmyState.muster(9, RIVAL, 0, false, ["pikemen"], 5)
	assert_true(AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()],
		[_home_army(), invader], null, true
	).is_empty(), "a war on its own soil comes before a voyage")

func test_only_a_declared_enemy_or_a_tribe_may_be_invaded() -> void:
	assert_true(DiplomacyRules.invadable(_peace(), campaign_OWNER, TRIBE), "tribes need no declaration")
	assert_false(DiplomacyRules.invadable(_peace(), campaign_OWNER, RIVAL), "peace holds with a crown")
	assert_true(DiplomacyRules.invadable(_war(), campaign_OWNER, RIVAL))

func test_a_tribe_coast_is_a_lawful_target_without_a_declaration() -> void:
	var world: WorldMap = campaign__world()
	var actions: Array[Dictionary] = AiInvasionPlanner.split_orders(
		campaign__config(), _peace(), world, world.region(0), [campaign__squadron()], [_home_army()]
	)
	assert_eq(actions.size(), 1, "the New World is open to a crown at peace")

func test_no_detachment_without_a_shore_across_the_water() -> void:
	# A war with a crown holding no New World coast, and no tribe, is a land war.
	var home_only := WorldMap.new()
	home_only.add_region(campaign__old_world())
	var coastless: MapModel = campaign__new_world(false)
	coastless.provinces[0].owner = campaign_OWNER
	home_only.add_region(coastless)
	home_only.warp_links = [{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0}]
	assert_true(AiInvasionPlanner.split_orders(
		campaign__config(), _war(), home_only, home_only.region(0), [campaign__squadron()], [_home_army()]
	).is_empty())

func test_the_landing_targets_a_tribe_coast_without_a_war() -> void:
	var world: WorldMap = campaign__world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _peace(), world, 1, new_world, [fleet], [army]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(int(order.get("province", -1)), 0)

func test_a_field_army_already_afield_is_not_split_again() -> void:
	var world: WorldMap = campaign__world()
	assert_true(AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()],
		[_home_army(), _field_army()]
	).is_empty())

## One hull carries one regiment (wiki: ships-and-naval § Naval transport), so a
## field army too large for the only squadron is cut down to the hulls: a court
## with two hulls still lands a two-regiment beachhead instead of keeping the
## whole host at home.
func test_a_field_army_too_large_for_the_squadron_is_cut_to_the_hulls() -> void:
	var world: WorldMap = campaign__world()
	var field: ArmyState = _field_army(
		["pikemen", "squires", "peasant_levies", "musketeers"]
	)
	var actions: Array[Dictionary] = AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()], [field]
	)
	assert_eq(actions.size(), 1)
	assert_eq(String(actions[0]["kind"]), AiInvasionPlanner.KIND_SPLIT)
	assert_eq(int(actions[0]["army_id"]), field.id, "the field army is cut, not the seat")
	assert_eq(int(actions[0]["regiments"].size()), 2, "two hulls carry two regiments")

## The boarding step takes the force the hulls can hold, not the first army in
## the list.
func test_the_boarding_step_takes_the_force_that_fits() -> void:
	var world: WorldMap = campaign__world()
	var big: ArmyState = _field_army(["pikemen", "squires", "peasant_levies"], 0)
	var small: ArmyState = ArmyState.muster(3, campaign_OWNER, 0, false, ["pikemen", "squires"], 11)
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 0, HULLS, HULL_TYPES)
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 0, world.region(0), [fleet],
		[_home_army(), big, small]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_EMBARK)
	assert_eq(int(order.get("army", -1)), 3, "the two-regiment force fits two hulls")

## The crossing force reads the rosters: a moved, laden or foreign squadron is
## no crossing, and the Home Army, an army too large and an army inland all stay
## behind.
func test_the_crossing_force_reads_the_rosters() -> void:
	var world: WorldMap = campaign__world()
	var model: MapModel = world.region(0)
	var busy: FleetState = FleetState.in_port(2, campaign_OWNER, 0, HULLS, HULL_TYPES)
	busy.moved = true
	var laden: FleetState = FleetState.in_port(3, campaign_OWNER, 0, HULLS, HULL_TYPES)
	laden.add_civilian(99)
	var foreign: FleetState = FleetState.in_port(4, RIVAL, 0, HULLS, HULL_TYPES)
	assert_true(
		AiCrossingForce.fleet([busy, laden, foreign], campaign_OWNER) == null,
		"a moved, laden or foreign squadron is no crossing"
	)
	var free: FleetState = FleetState.in_port(5, campaign_OWNER, 0, HULLS, HULL_TYPES)
	assert_eq(AiCrossingForce.fleet([busy, laden, foreign, free], campaign_OWNER).id, 5)
	var home: ArmyState = _home_army()
	var big: ArmyState = _field_army(["pikemen", "squires", "peasant_levies"], 0)
	var inland: ArmyState = ArmyState.muster(4, campaign_OWNER, 1, false, ["pikemen"], 12)
	assert_true(
		AiCrossingForce.army(model, [home, big, inland], campaign_OWNER, 2) == null,
		"the Home Army, an army too large and an army inland all stay"
	)
	var fits: ArmyState = _field_army(["pikemen", "squires"], 0)
	assert_eq(AiCrossingForce.army(model, [home, big, inland, fits], campaign_OWNER, 2).id, fits.id)
	assert_false(AiCrossingForce.may_sail(model, inland, campaign_OWNER), "no harbour, no crossing")
	assert_true(AiCrossingForce.may_sail(model, fits, campaign_OWNER))

func test_an_idle_squadron_docks_for_the_crossing_army() -> void:
	var world: WorldMap = campaign__world()
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 0, world.region(0), [campaign__squadron()], [_home_army(), _field_army()]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_DOCK)
	assert_eq(int(order.get("province", -1)), 0)

func test_a_docked_squadron_takes_the_army_aboard() -> void:
	var world: WorldMap = campaign__world()
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 0, HULLS, HULL_TYPES)
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 0, world.region(0), [fleet],
		[_home_army(), _field_army()]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_EMBARK)
	assert_eq(int(order.get("army", -1)), 2)

func test_a_squadron_with_no_room_takes_no_troops() -> void:
	var world: WorldMap = campaign__world()
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 0, ["h1"] as Array[String], {"h1": "sloop"})
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 0, world.region(0), [fleet],
		[_home_army(), _field_army()]
	)
	assert_true(order.is_empty(), "one hull cannot carry two regiments")

func test_an_expedition_crosses_then_marks_the_enemy_coast() -> void:
	var world: WorldMap = campaign__world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 0, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army()
	assert_true(bool(NavalTransport.embark(old_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var cross: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 0, old_world, [fleet], [army]
	)
	assert_eq(String(cross.get("kind", "")), AiInvasionPlanner.KIND_CROSS)
	var mark: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 1, new_world, [fleet], [army]
	)
	assert_eq(String(mark.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(int(mark.get("province", -1)), 0)

func test_a_ready_beachhead_lands_the_army_the_next_turn() -> void:
	var world: WorldMap = campaign__world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_true(bool(NavalTransport.establish_beachhead(
		new_world, fleet, 0, 1, Callable()
	)["ok"]))
	var waiting: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 1, new_world, [fleet], [army], 1
	)
	assert_true(waiting.is_empty(), "the landing opens the turn after the marker")
	var land: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 1, new_world, [fleet], [army], 2
	)
	assert_eq(String(land.get("kind", "")), AiInvasionPlanner.KIND_LAND)
	assert_eq(int(land.get("province", -1)), 0)

## A site marked in good faith lapses when the war ends before the landing: the
## rules refuse it, so the court must not order it and lose the turn — it brings
## the troops ashore on an own coast instead (wiki: ships-and-naval § Missions
## and Movement).
func test_a_lapsed_beachhead_is_not_ordered_as_a_landing() -> void:
	var world: WorldMap = campaign__world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	new_world.provinces[0].owner = RIVAL
	assert_true(bool(NavalTransport.establish_beachhead(
		new_world, fleet, 0, 1, Callable()
	)["ok"]))
	# Peace is signed before the site opens, so the marked shore is no enemy's.
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _peace(), world, 1, new_world, [fleet], [army], 2
	)
	assert_true(
		String(order.get("kind", "")) != AiInvasionPlanner.KIND_LAND
		or int(order.get("province", -1)) != 0,
		"the lapsed site is never ordered as a landing"
	)
	assert_eq(
		int(order.get("province", -1)), 1,
		"the troops go ashore on the crown's own coast"
	)


## A site that lapsed while another hostile coast lies in the same water is
## replaced in the same turn: the expedition marks a fresh shore instead of
## spending the turn on a landing the rules refuse.
func test_a_lapsed_beachhead_is_replaced_by_a_fresh_coast() -> void:
	var world: WorldMap = campaign__world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	new_world.provinces[0].owner = RIVAL
	assert_true(bool(NavalTransport.establish_beachhead(
		new_world, fleet, 0, 1, Callable()
	)["ok"]))
	# A second hostile shore on the same water: a Tribe coast beside the colony.
	var tiles: Array[Vector2i] = [Vector2i(2, 1)]
	new_world.province[new_world.index_of(2, 1)] = 2
	var extra := ProvinceState.create(2, "Second Coast", tiles, Vector2(2.0, 1.0), 1, TRIBE, false)
	extra.coastal = true
	new_world.provinces.append(extra)
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _peace(), world, 1, new_world, [fleet], [army], 2
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(int(order.get("province", -1)), 2, "a fresh coast is marked this turn")


func test_a_coast_the_army_cannot_storm_sends_it_home() -> void:
	var world: WorldMap = campaign__world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["peasant_levies"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var guards: ArmyState = ArmyState.muster(9, TRIBE, 0, false, [
		"guards", "guards", "guards",
	], 20)
	var order: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _war(), world, 1, new_world, [fleet], [army, guards]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_LAND)
	assert_eq(int(order.get("province", -1)), 1, "the army goes ashore on its own colony")

func test_the_observer_counts_an_expedition_and_its_landing() -> void:
	var play := PlaySession.new()
	play.turn = 3
	var trace: Array[Dictionary] = [
		{"faction": campaign_OWNER, "kind": AiInvasionPlanner.KIND_SPLIT, "province": 0},
		{"faction": campaign_OWNER, "kind": AiInvasionPlanner.KIND_EMBARK},
		{"faction": campaign_OWNER, "kind": AiInvasionPlanner.KIND_CROSS},
		{"faction": campaign_OWNER, "kind": AiInvasionPlanner.KIND_LAND, "province_name": "Coast"},
	]
	var record: Dictionary = AiTurnLog.record(play, [], [], {}, trace)
	var actions: Dictionary = record["factions"][campaign_OWNER]["actions"]
	assert_eq(int(actions.get("split", 0)), 1)
	assert_eq(int(actions.get("invade", 0)), 3)
	var court: Dictionary = record["factions"][campaign_OWNER]
	assert_true(AiTurnLog.headline(court).contains("landings"))

func test_the_observer_counts_a_colony_voyage() -> void:
	var play := PlaySession.new()
	play.turn = 3
	var trace: Array[Dictionary] = [
		{"faction": campaign_OWNER, "kind": "embark", "province_name": "Seat"},
		{"faction": campaign_OWNER, "kind": "sail", "zone": 0},
		{"faction": campaign_OWNER, "kind": "cross"},
		{"faction": campaign_OWNER, "kind": "land", "province_name": "Coast"},
	]
	var record: Dictionary = AiTurnLog.record(play, [], [], {}, [], trace)
	var actions: Dictionary = record["factions"][campaign_OWNER]["actions"]
	assert_eq(int(actions.get("voyage", 0)), 4, "every applied step is a voyage order")
	assert_eq(int(actions.get("colony", 0)), 1, "only the landing is a colony landing")
	var court: Dictionary = record["factions"][campaign_OWNER]
	var line: String = AiTurnLog.headline(court)
	assert_true(line.contains("voyage orders"), line)
	assert_true(line.contains("colony landings"), line)
	var texts: PackedStringArray = []
	for event: Dictionary in record["events"]:
		texts.append(String(event["text"]))
	var joined: String = " · ".join(texts)
	assert_true(joined.contains("boards at Seat"), joined)
	assert_true(joined.contains("crosses the Passage"), joined)
	assert_true(joined.contains("lands at Coast"), joined)

## The voyage line names the crew that sailed: a claim's Merchant reads as a
## Merchant, not as the Explorer that charted before it (#1127).
func test_the_voyage_line_names_the_crew_that_sailed() -> void:
	var who: String = FactionCatalog.name_of(campaign_OWNER)
	var rows: Array[Dictionary] = AiExpeditionLog.rows([], [
		{"faction": campaign_OWNER, "kind": "embark", "province_name": "Seat", "crew": "merchant"},
		{"faction": campaign_OWNER, "kind": "land", "province_name": "Coast", "crew": "merchant"},
		{"faction": campaign_OWNER, "kind": "land", "province_name": "Coast"},
	])
	assert_eq(
		String(rows[0].get("event", "")), "%s's Merchant boards at Seat." % who,
		"the boarding line names the claim crew"
	)
	assert_eq(
		String(rows[1].get("event", "")), "%s's Merchant lands at Coast." % who,
		"the landing line names it too"
	)
	assert_eq(
		String(rows[3].get("event", "")), "%s's Explorer lands at Coast." % who,
		"a trace with no crew keeps the published Explorer line"
	)


func test_the_expedition_log_reads_both_traces() -> void:
	var rows: Array[Dictionary] = AiExpeditionLog.rows(
		[{"faction": campaign_OWNER, "kind": AiInvasionPlanner.KIND_LAND, "province_name": ""}],
		[
			{"faction": campaign_OWNER, "kind": "sail", "zone": 2},
			{"faction": campaign_OWNER, "kind": "land"},
		]
	)
	assert_eq(rows.size(), 4, "a landing is a voyage order and a colony landing")
	assert_eq(String(rows[0]["action"]), "invade")
	assert_eq(String(rows[0].get("event", "")), "", "no place name, no line")
	assert_eq(String(rows[1]["action"]), "voyage")
	assert_eq(String(rows[1].get("event", "")), "", "a sail carries no line")
	assert_eq(String(rows[2]["action"]), "voyage")
	assert_eq(String(rows[3]["action"]), "colony")

func test_the_naval_planner_leaves_a_troop_ship_to_its_expedition() -> void:
	var model: MapModel = campaign_NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, 1, 1)
	state.relation(2, 1).at_war = true
	var troop: FleetState = FleetState.at_sea(1, 2, 0, HULLS, HULL_TYPES)
	troop.embarked_army = 7
	var plan: Dictionary = AiNavalPlanner.orders(config, state, model, [troop])
	assert_true(plan["orders"].is_empty(), "the expedition keeps its course")

func test_the_adapter_detaches_the_crossing_army_first() -> void:
	var world: WorldMap = campaign__world()
	var old_world: MapModel = world.region(0)
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.turn = 0
	play.world = world
	play.model = old_world
	play.diplomacy = _war()
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [campaign__squadron()])
	play.ship_layer.regions.set_region(1, [])
	play.army_layer = ArmyLayer.new()
	play.army_layer.model = old_world
	play.army_layer.armies = [_home_army()]
	play.army_layer.next_army = 2
	play.army_layer.next_regiment = 10
	play.army_layer.regions.set_region(0, play.army_layer.armies)
	play.army_layer.regions.set_region(1, [])
	var trace: Array[Dictionary] = MapPlayInvasionAi.run(play)
	assert_eq(String(trace[0]["kind"]), AiInvasionPlanner.KIND_SPLIT)
	assert_eq(String(trace[1]["kind"]), AiInvasionPlanner.KIND_DOCK)
	var roster: Array = play.army_layer.regions.value(0, [])
	assert_eq(roster.size(), 2, "a field army joins the Home Army at the seat")
	assert_eq((roster[1] as ArmyState).count(), 2)
	play.ship_layer.free()
	play.army_layer.free()

func test_the_map_adapter_runs_the_whole_expedition() -> void:
	var world: WorldMap = campaign__world()
	var old_world: MapModel = world.region(0)
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.turn = 0
	play.world = world
	play.model = old_world
	play.diplomacy = _war()
	var fleet: FleetState = campaign__squadron()
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	var army: ArmyState = _field_army()
	play.army_layer = ArmyLayer.new()
	play.army_layer.model = old_world
	play.army_layer.armies = [army]
	play.army_layer.next_army = 3
	play.army_layer.next_regiment = 30
	play.army_layer.regions.set_region(0, play.army_layer.armies)
	play.army_layer.regions.set_region(1, [])
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_DOCK)
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_EMBARK)
	assert_true(army.is_embarked())
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_SAIL)
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_CROSS)
	assert_true(play.ship_layer.regions.value(0, []).is_empty(), "the squadron left the Old World")
	assert_eq(play.ship_layer.regions.value(1, []).size(), 1)
	assert_eq(play.army_layer.regions.value(1, []).size(), 1, "the army crossed with it")
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(fleet.beachhead_province, 0)
	play.turn = 1
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_LAND)
	assert_eq(army.province, 0)
	assert_eq(fleet.embarked_army, -1)
	play.ship_layer.free()
	play.army_layer.free()

## A court does not sail an army at a shore it has never charted: the New World
## starts unknown, so the crossing waits for a sighting (wiki: fog-and-exploration;
## DR-20261110-21).
func test_an_uncharted_coast_is_not_worth_a_crossing() -> void:
	var world: WorldMap = campaign__world()
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	assert_true(AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()], [_home_army()], charts
	).is_empty(), "no hostile coast is charted across the water")
	charts.reveal_sea_zone(campaign_OWNER, 1, 0)
	assert_eq(AiInvasionPlanner.split_orders(
		campaign__config(), _war(), world, world.region(0), [campaign__squadron()], [_home_army()], charts
	).size(), 1, "the charted coast is a war worth a fleet")

func test_a_charted_coast_is_the_only_landing_target() -> void:
	var world: WorldMap = campaign__world()
	var new_world: MapModel = world.region(1)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	var fleet: FleetState = FleetState.in_port(1, campaign_OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var blind: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _peace(), world, 1, new_world, [fleet], [army], 0, charts
	)
	assert_true(
		String(blind.get("kind", "")) != AiInvasionPlanner.KIND_BEACHHEAD,
		"an uncharted beach is no target"
	)
	charts.reveal_sea_zone(campaign_OWNER, 1, 0)
	var ready: Dictionary = AiInvasionPlanner.plan(
		campaign__config(), _peace(), world, 1, new_world, [fleet], [army], 0, charts
	)
	assert_eq(String(ready.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(int(ready.get("province", -1)), 0)

# --- test_ai_colonisation ---

func _ai_colonisation_old_world() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var province := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), ai_colonisation_OWNER, true
	)
	province.capital_tile = Vector2i(0, 0)
	province.port_tile = Vector2i(0, 1)
	province.coastal = true
	model.provinces = [province]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model

func _ai_colonisation_new_world() -> MapModel:
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = WorldMap.NEW_WORLD
	model.region_key = "new_world"
	for y in 2:
		for x in 4:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	for x in 4:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var sea: Array[Vector2i] = []
	for x in 4:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Far Shore", sea, Vector2(1.5, 2.0), 4)]
	return model

func _ai_colonisation_world() -> WorldMap:
	var map := WorldMap.new()
	map.add_region(_ai_colonisation_old_world())
	map.add_region(_ai_colonisation_new_world())
	map.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return map

func _ai_colonisation_config() -> AiConfig:
	return AiConfig.build(ai_colonisation_OWNER, 1500)

func test_an_idle_explorer_boards_a_squadron_in_port() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 1)

func test_a_passenger_sails_crosses_and_lands() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	var sail: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(sail.get("kind", "")), "sail")
	assert_eq(int(sail.get("zone", -1)), 0)
	assert_true(
		bool(FleetSortie.apply(old_world, fleet, 0)["ok"]),
		"a squadron in port at its own capital sorties"
	)
	fleet.moved = false
	var cross: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(cross.get("kind", "")), "cross")
	var crossed: Dictionary = WarpTravel.apply_crossing(world, 0, fleet)
	assert_true(bool(crossed["ok"]))
	fleet.moved = false
	var land: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {}
	)
	assert_eq(String(land.get("kind", "")), "land")
	assert_eq(Vector2i(land.get("tile", Vector2i(-1, -1))), Vector2i(0, 1))


## The landing is the one ground a court takes overseas, so it is the ground its
## own workshop feeds: with sugar cane in the new world's plain and the refinery
## hungry for it, the colonist marches to that coast instead of the compass's
## north-easternmost tile (wiki: civilian-units § Overseas deployment;
## DR-20261119-05). A caller with no appetite keeps the published order.
func test_a_colonist_lands_on_the_ground_its_workshop_feeds() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(
		1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0)
	)
	assert_true(bool(CivilianVoyage.embark(world.region(0), unit, fleet)["ok"]))
	assert_eq(
		String(AiColonisationPlanner.plan(
			_ai_colonisation_config(), world, 0, world.region(0), [fleet], [unit], {}
		).get("kind", "")),
		"sail"
	)
	assert_true(bool(FleetSortie.apply(world.region(0), fleet, 0)["ok"]))
	fleet.moved = false
	assert_true(bool(WarpTravel.apply_crossing(world, 0, fleet)["ok"]))
	fleet.moved = false
	# Sugar cane on the far end of the plain: the published walk would take the
	# near tile, the workshop's appetite takes the crop.
	new_world.resource[new_world.index_of(3, 1)] = 13
	var plain: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {}
	)
	assert_eq(
		Vector2i(plain.get("tile", Vector2i(-1, -1))), Vector2i(0, 1),
		"an empty appetite keeps the published compass order"
	)
	var fed: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {},
		null, AiPhasePlanner.PHASE_PEACE, false, {"sugarCane": 4}
	)
	assert_eq(
		Vector2i(fed.get("tile", Vector2i(-1, -1))), Vector2i(3, 1),
		"the crop the workshop turns is worth the landing"
	)
	# A raw the chart cannot show unprospected is no ground the court can read:
	# the appetite names only raws its open recipes turn (DR-20261111-26).
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var minerals: Dictionary = AiEconomyPlanner.ground_appetite(
		_ai_colonisation_config(), economy, 4
	)
	assert_true(
		int(minerals.get("sugarCane", 0)) > 0,
		"a court with no sugar cane wants a plantation"
	)
	assert_false(minerals.has("iron"), "a mineral is no appetite: the chart hides it")
	economy.stockpile["sugarCane"] = 40
	assert_false(
		AiEconomyPlanner.ground_appetite(_ai_colonisation_config(), economy, 4).has("sugarCane"),
		"a raw already in store is no reason to cross"
	)


## A court on **earn** sails for cash, and the New World ground that clears to
## the treasury is a deposit no chart shows until an Explorer digs it. So its
## Explorer's landing prefers ground worth surveying — and weighs every
## prospectable tile the same, because the chart cannot say which deposit lies
## under it (wiki: fog-and-exploration § Prospect-Required Resources; issue
## #1382). A raw the workshop is short of still leads the bet.
func test_an_earn_crowns_explorer_lands_on_ground_worth_surveying() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(
		1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0)
	)
	assert_true(bool(CivilianVoyage.embark(world.region(0), unit, fleet)["ok"]))
	assert_true(bool(FleetSortie.apply(world.region(0), fleet, 0)["ok"]))
	fleet.moved = false
	assert_true(bool(WarpTravel.apply_crossing(world, 0, fleet)["ok"]))
	fleet.moved = false
	# A hill hiding gold and a peak hiding gems, both uncharted deposits: the
	# compass order reaches the hill first, so a landing at the peak would mean
	# the planner had read a mineral the court has not surveyed.
	new_world.terrain[new_world.index_of(1, 1)] = MapModel.Terrain.HILLS
	new_world.terrain[new_world.index_of(2, 1)] = MapModel.Terrain.MOUNTAINS
	new_world.resource[new_world.index_of(1, 1)] = 3
	new_world.resource[new_world.index_of(2, 1)] = 11
	var plain: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {},
		null, AiPhasePlanner.PHASE_PEACE, false, {}
	)
	assert_eq(
		Vector2i(plain.get("tile", Vector2i(-1, -1))), Vector2i(0, 1),
		"a court that does not sail for income keeps the published compass order"
	)
	var earning: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {},
		null, AiPhasePlanner.PHASE_PEACE, true, {}
	)
	assert_eq(
		Vector2i(earning.get("tile", Vector2i(-1, -1))), Vector2i(1, 1),
		"an earn court's Explorer lands on ground worth surveying"
	)
	new_world.resource[new_world.index_of(3, 1)] = 13
	var fed: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {},
		null, AiPhasePlanner.PHASE_PEACE, true, {"sugarCane": 4}
	)
	assert_eq(
		Vector2i(fed.get("tile", Vector2i(-1, -1))), Vector2i(3, 1),
		"a raw the workshop wants still leads the bet on the ground"
	)


func test_no_second_expedition_when_a_colonist_is_already_abroad() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {"explorer": 1}
	)
	assert_true(order.is_empty())


## The Explorer ashore is the chart, not the colony: the next voyage carries the
## Merchant whose deeds found it, so a court whose charting crew landed is not
## shut out of the New World for the rest of the campaign (#1127).
func test_a_merchant_boards_when_the_explorer_is_already_ashore() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var explorer: CivilianState = CivilianState.create(
		1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0)
	)
	var merchant: CivilianState = CivilianState.create(
		2, ai_colonisation_OWNER, "merchant", Vector2i(1, 0)
	)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [merchant],
		{"explorer": 1}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 2, "the claim crew boards, not the charting one")

	# One claim at a time: with a Merchant already across the water the court
	# sends no second one, and its Explorer stays on the home survey.
	var second: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [explorer, merchant],
		{"explorer": 1, "merchant": 1}
	)
	assert_true(second.is_empty(), "the claim has already sailed")


## A deed the Merchant signed is crown land for the landing rule, so the Builder
## sails for it even though the province still answers to its Tribe (#1127;
## wiki: civilian-units § Overseas deployment).
func test_a_builder_sails_for_a_deed_in_the_new_world() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			tiles.append(Vector2i(x, y))
			new_world.province[new_world.index_of(x, y)] = 0
	var tribe := ProvinceState.create(
		0, "Tribe", tiles, Vector2(1.5, 0.5), tiles.size(), ai_colonisation_OWNER + 1, false
	)
	new_world.provinces = [tribe]
	assert_true(
		new_world.purchase_tile(Vector2i(1, 0), ai_colonisation_OWNER),
		"the Merchant's deed"
	)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var builder: CivilianState = CivilianState.create(
		3, ai_colonisation_OWNER, "builder", Vector2i(0, 0)
	)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [builder],
		{"explorer": 1, "merchant": 1}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 3, "crown ground, a Builder works it")

func test_the_map_adapter_embarks_and_sails_the_rival() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	var first: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(first.size(), 1)
	assert_eq(String(first[0]["kind"]), "embark")
	assert_eq(String(first[0].get("province_name", "")), "Seat")
	assert_true(unit.is_embarked())
	assert_eq(fleet.civilian_count(), 1)
	var second: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(second.size(), 1)
	assert_eq(String(second[0]["kind"]), "sail")
	assert_true(fleet.is_at_sea())
	play.ship_layer.free()
	play.civilian_layer.free()

func test_a_squadron_at_sea_docks_for_its_colonist() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "dock")
	assert_eq(int(order.get("province", -1)), 0)

func test_a_builder_boards_when_the_crown_owns_overseas_land() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			tiles.append(Vector2i(x, y))
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, ai_colonisation_OWNER, false)
	colony.town_tile = Vector2i(0, 0)
	new_world.provinces = [colony]
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "builder", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 1)

func test_a_docked_passenger_lands_without_sailing_first() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			var tile := Vector2i(x, y)
			tiles.append(tile)
			new_world.province[new_world.index_of(x, y)] = 0
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, ai_colonisation_OWNER, false)
	colony.port_tile = Vector2i(0, 1)
	colony.coastal = true
	new_world.provinces = [colony]
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "builder", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(new_world, unit, fleet)["ok"]))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "land")

func test_the_map_adapter_crosses_and_lands() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "embark")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "sail")
	fleet.moved = false
	var crossed: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(crossed[0]["kind"]), "cross")
	assert_true((play.ship_layer.regions.value(0, []) as Array).is_empty())
	assert_eq((play.ship_layer.regions.value(1, []) as Array).size(), 1)
	fleet.moved = false
	var landed: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(landed[0]["kind"]), "land")
	assert_false(unit.is_embarked())
	assert_true(unit.tile.y <= 1)
	play.ship_layer.free()
	play.civilian_layer.free()

func test_the_planner_guards_empty_inputs() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	assert_true(AiColonisationPlanner.plan(null, world, 0, old_world, [], []).is_empty())
	assert_true(AiColonisationPlanner.plan(_ai_colonisation_config(), null, 0, old_world, [], []).is_empty())
	assert_true(AiColonisationPlanner.plan(_ai_colonisation_config(), world, 0, null, [], []).is_empty())
	assert_true(
		AiColonisationPlanner.plan(
			AiConfig.build(99, 1500), world, 0, old_world, [], []
		).is_empty(),
		"an unknown court has no home region"
	)
	assert_true(
		AiColonisationPlanner.plan(
			AiConfig.build(9, 1500), world, 1, world.region(1), [], []
		).is_empty(),
		"a New World court with no Old World land has nowhere to sail"
	)

func test_a_carrying_fleet_without_its_civilian_is_ignored() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	fleet.add_civilian(77)
	assert_true(
		AiColonisationPlanner.plan(_ai_colonisation_config(), world, 0, old_world, [fleet], []).is_empty()
	)

func test_a_working_builder_falls_back_to_an_idle_explorer() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			tiles.append(Vector2i(x, y))
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, ai_colonisation_OWNER, false)
	new_world.provinces = [colony]
	var builder: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "builder", Vector2i(0, 0))
	builder.start_work("build_improvement", Vector2i(0, 0), 2)
	var explorer: CivilianState = CivilianState.create(2, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [builder, explorer], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 2)

func test_the_lowest_idle_squadron_is_chosen() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var moved: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	moved.moved = true
	var troop_carrier: FleetState = FleetState.at_sea(2, ai_colonisation_OWNER, 0)
	troop_carrier.embarked_army = 9
	var ready: FleetState = FleetState.at_sea(3, ai_colonisation_OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [moved, troop_carrier, ready], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "dock")
	assert_eq(int(order.get("fleet", -1)), 3)

func test_a_moved_carrying_fleet_does_not_sail_twice() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var first: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var second: CivilianState = CivilianState.create(2, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var moved: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	moved.add_civilian(1)
	moved.moved = true
	var ready: FleetState = FleetState.in_port(2, ai_colonisation_OWNER, 0)
	ready.add_civilian(2)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [moved, ready], [first, second], {}
	)
	assert_eq(String(order.get("kind", "")), "sail")
	assert_eq(int(order.get("fleet", -1)), 2)

func test_board_refusals_without_a_reachable_port() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var elsewhere: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 1)
	assert_true(
		AiColonisationPlanner.plan(
			_ai_colonisation_config(), world, 0, old_world, [elsewhere], [unit], {}
		).is_empty(),
		"a squadron in another port cannot take this colonist"
	)
	var stray: CivilianState = CivilianState.create(9, ai_colonisation_OWNER, "explorer", Vector2i(9, 9))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [FleetState.at_sea(1, ai_colonisation_OWNER, 0)], [stray], {}
	)
	assert_eq(
		String(order.get("kind", "")), "dock",
		"the squadron musters at the crown's harbour, not on the colonist's tile"
	)
	assert_eq(int(order.get("province", -1)), 0)

## A court with no harbour of its own cannot start an expedition, however many
## colonists and hulls it has (wiki: ships-and-naval § Home Fleet).
func test_no_owned_harbour_means_no_voyage() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	old_world.provinces[0].port_tile = Vector2i(-1, -1)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	assert_eq(AiColonisationPlanner.harbour(old_world, ai_colonisation_OWNER), MapModel.NO_ID)
	assert_true(
		AiColonisationPlanner.plan(
			_ai_colonisation_config(), world, 0, old_world, [FleetState.at_sea(1, ai_colonisation_OWNER, 0)], [unit], {}
		).is_empty(),
		"a crown with no port has nowhere to take a colonist aboard"
	)

## The court's seat, when it has a port, is the muster harbour even if another
## owned province has a lower id.
func test_the_seat_is_the_muster_harbour() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var seat: ProvinceState = old_world.provinces[0]
	seat.capital = false
	var coast: ProvinceState = ProvinceState.create(
		0, "Anchorage", seat.tiles.duplicate(), Vector2(2.0, 0.5), 10, ai_colonisation_OWNER, true
	)
	coast.port_tile = Vector2i(1, 0)
	old_world.provinces = [coast, seat]
	assert_eq(
		AiColonisationPlanner.harbour(old_world, ai_colonisation_OWNER), 0,
		"the seat outranks a lower-id anchorage"
	)

## An Explorer with a voyage ahead waits at its crown's harbour and marches home
## when something has carried it off, so the boarding step always finds it there
## (wiki: civilian-units § Overseas deployment; DR-20261111-05).
func test_an_explorer_musters_at_the_crowns_harbour() -> void:
	var model: MapModel = campaign_CivilianFixture.build()
	var port: Vector2i = campaign_CivilianFixture.COAST_TILE
	var here: CivilianState = CivilianState.create(1, 0, "explorer", campaign_CivilianFixture.BARE_TILE)
	var away: CivilianState = CivilianState.create(2, 0, "explorer", campaign_CivilianFixture.RIVAL_GRAIN_TILE)
	var context: Dictionary = {"muster_port": port}
	assert_true(
		AiExplorerWork.best_move(model, here, LandWorks.new(), context).is_empty(),
		"an Explorer in the harbour province waits for its voyage"
	)
	var march: Dictionary = AiExplorerWork.best_move(model, away, LandWorks.new(), context)
	assert_eq(String(march.get("kind", "")), "move")
	var before: int = absi(away.tile.x - port.x) + absi(away.tile.y - port.y)
	var step: Vector2i = march.get("tile", CivilianState.NO_TILE)
	assert_true(
		absi(step.x - port.x) + absi(step.y - port.y) < before,
		"the march closes on the harbour"
	)
	assert_true(
		AiExplorerWork.best_candidate(_work_query(
			AiConfig.build(0, 1500), model, away, [away], LandWorks.new(),
			campaign_CivilianFixture.stockpile(), {}, {}, context, {}
		)).is_empty(),
		"a colonist on the way to its port takes no survey work"
	)

## The muster stands while a crew is still to send and a squadron is free to
## carry it. Once the Explorer has landed the harbour musters the Merchant whose
## deeds found the colony, and it shuts again when that claim has sailed too
## (#1127): a court is not left with no expedition because its charting crew is
## ashore.
func test_the_muster_port_needs_a_crew_to_send_and_a_free_squadron() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.regions.set_region(0, [FleetState.at_sea(1, ai_colonisation_OWNER, 0)])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = []
	play.civilian_layer.regions.set_region(0, [])
	play.civilian_layer.regions.set_region(1, [])
	assert_eq(
		CivilianMuster.muster_port(play, ai_colonisation_OWNER, 0, old_world), Vector2i(0, 1),
		"a court with a free squadron musters at its seat's port"
	)
	assert_eq(
		CivilianMuster.voyage_kind(play, ai_colonisation_OWNER, 0), "explorer",
		"nobody has landed: the Explorer charts"
	)
	var abroad: CivilianState = CivilianState.create(7, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	play.civilian_layer.regions.set_region(1, [abroad])
	assert_eq(
		CivilianMuster.voyage_kind(play, ai_colonisation_OWNER, 0), "merchant",
		"the Explorer ashore is the chart: the Merchant claims"
	)
	assert_eq(
		CivilianMuster.muster_port(play, ai_colonisation_OWNER, 0, old_world), Vector2i(0, 1),
		"the claim crew still musters after the charting crew landed"
	)
	play.civilian_layer.regions.set_region(1, [
		abroad, CivilianState.create(8, ai_colonisation_OWNER, "merchant", Vector2i(0, 0)),
	])
	assert_eq(
		CivilianMuster.muster_port(play, ai_colonisation_OWNER, 0, old_world), CivilianState.NO_TILE,
		"the claim has sailed: no third expedition of that kind"
	)
	play.civilian_layer.regions.set_region(1, [])
	play.ship_layer.regions.set_region(0, [])
	assert_eq(
		CivilianMuster.muster_port(play, ai_colonisation_OWNER, 0, old_world), CivilianState.NO_TILE,
		"no squadron, no muster"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## The claim crew waits at the harbour instead of marching off to sign a deed,
## and the vessel it boards is found there: the Merchant is held by the same
## reading the Explorer is (issue #894; #1127).
func test_the_muster_holds_the_claim_crew_at_the_harbour() -> void:
	var model: MapModel = campaign_CivilianFixture.build()
	var port: Vector2i = campaign_CivilianFixture.COAST_TILE
	var here: CivilianState = CivilianState.create(1, 0, "merchant", campaign_CivilianFixture.BARE_TILE)
	var away: CivilianState = CivilianState.create(2, 0, "merchant", campaign_CivilianFixture.RIVAL_GRAIN_TILE)
	var other: CivilianState = CivilianState.create(3, 0, "merchant", campaign_CivilianFixture.BARE_TILE)
	var context: Dictionary = {"muster_port": port, "muster_unit": here.id}
	assert_true(CivilianMuster.held_for_voyage(here, context))
	assert_false(CivilianMuster.held_for_voyage(other, context), "only the picked crew waits")
	assert_true(
		AiMerchantWork.best_move(model, here, LandWorks.new(), context).is_empty(),
		"a Merchant in the harbour province waits for its voyage"
	)
	assert_true(
		AiMerchantWork.best_candidate(_work_query(
			AiConfig.build(0, 1500), model, here, [here], LandWorks.new(),
			campaign_CivilianFixture.stockpile(), {}, {}, context, {}
		)).is_empty(),
		"the claim crew takes no deed while it musters"
	)
	var march: Dictionary = CivilianMuster.muster_move(model, away, context)
	assert_eq(String(march.get("kind", "")), "move")
	var before: int = absi(away.tile.x - port.x) + absi(away.tile.y - port.y)
	var step: Vector2i = march.get("tile", CivilianState.NO_TILE)
	assert_true(
		absi(step.x - port.x) + absi(step.y - port.y) < before,
		"the march closes on the harbour"
	)


## A crown whose own land still holds unsurveyed ground takes the second Explorer
## before the estate queue, so the colony sails with a prospector left behind
## (issue #894; wiki: fog-and-exploration § Prospecting).
func test_a_court_takes_the_voyage_crew_before_the_estate_queue() -> void:
	var play: PlaySession = _muster_play()
	var model: MapModel = play.world.region(0)
	var one: Array[CivilianState] = [
		CivilianState.create(1, 0, "explorer", CivilianFixture.BARE_TILE)
	]
	play.civilian_layer.regions.set_region(0, one)
	assert_true(
		CivilianMuster.needs_voyage_crew(play, 0, 0, model),
		"the last Explorer would sail with the voyage"
	)
	var two: Array[CivilianState] = one.duplicate()
	two.append(CivilianState.create(2, 0, "explorer", CivilianFixture.HILLS_TILE))
	play.civilian_layer.regions.set_region(0, two)
	assert_false(
		CivilianMuster.needs_voyage_crew(play, 0, 0, model),
		"a second Explorer already stays behind"
	)
	# The hire order takes the Explorer ahead of the Builder the estate queue
	# wants, so the voyage is not held up for want of a prospector.
	var context: Dictionary = _civilian_context()
	context["voyage_crew"] = true
	var order: Dictionary = AiCivilianHire.training_order(
		AiConfig.build(0, 1500), one, context
	)
	assert_eq(String(order.get("type_id", "")), "explorer")
	context.erase("voyage_crew")
	var published: Dictionary = AiCivilianHire.training_order(
		AiConfig.build(0, 1500), one, context
	)
	assert_eq(
		String(published.get("type_id", "")), "builder",
		"without the voyage reading the published order stands"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## Only the crew the voyage will board waits at the harbour: a crown's other
## Explorers keep prospecting the home ground while a colony sails (issue #894).
func test_only_the_mustering_explorer_waits_at_the_harbour() -> void:
	var model: MapModel = CivilianFixture.build()
	var pick: CivilianState = CivilianState.create(1, 0, "explorer", CivilianFixture.BARE_TILE)
	var other: CivilianState = CivilianState.create(2, 0, "explorer", CivilianFixture.HILLS_TILE)
	var context: Dictionary = {
		"muster_port": CivilianFixture.COAST_TILE, "muster_unit": pick.id,
	}
	assert_true(
		AiExplorerWork.best_candidate(_work_query(
			AiConfig.build(0, 1500), model, pick, [pick, other], LandWorks.new(),
			CivilianFixture.stockpile(), {}, {}, context, {}
		)).is_empty(),
		"the crew the voyage boards takes no work"
	)
	var work: Dictionary = AiExplorerWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, other, [pick, other], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context, {}
	))
	assert_eq(
		String(work.get("action", "")), "prospect",
		"the crown's other Explorer keeps working the home ground"
	)


## The muster fixture: a two-region world whose home province is the civilian
## fixture's own (hills to prospect, a seat with a port) and a free squadron.
func _muster_play() -> PlaySession:
	var world := WorldMap.new()
	world.add_region(CivilianFixture.build())
	world.add_region(_ai_colonisation_new_world())
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.world = world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = world.region(0)
	play.ship_layer.regions.set_region(0, [FleetState.in_port(1, 0, 0)])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = world.region(0)
	play.civilian_layer.units = []
	play.civilian_layer.regions.set_region(0, [])
	play.civilian_layer.regions.set_region(1, [])
	play.civilian_layer.works_regions.set_region(0, LandWorks.new())
	return play

func test_region_helpers_pick_the_opposite_map() -> void:
	var world: WorldMap = _ai_colonisation_world()
	assert_eq(AiColonisationPlanner._target_region(world, WorldMap.OLD_WORLD, ai_colonisation_OWNER), WorldMap.NEW_WORLD)
	assert_eq(AiColonisationPlanner._target_region(world, WorldMap.NEW_WORLD, ai_colonisation_OWNER), WorldMap.OLD_WORLD)
	assert_false(VoyageRead.owns_land_in(world, 9, ai_colonisation_OWNER))

func test_no_passage_keeps_a_carrying_squadron_home() -> void:
	var world: WorldMap = _ai_colonisation_world()
	world.warp_links = []
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	assert_true(
		AiColonisationPlanner.plan(
			_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
		).is_empty()
	)

func test_a_multi_zone_crossing_steps_toward_the_far_coast() -> void:
	var model := MapModel.new()
	model.setup(6, 2)
	model.region_id = WorldMap.NEW_WORLD
	for x in 6:
		var y0: int = model.index_of(x, 0)
		model.terrain[y0] = MapModel.Terrain.PLAINS if x >= 4 else MapModel.Terrain.OCEAN
		var y1: int = model.index_of(x, 1)
		model.terrain[y1] = MapModel.Terrain.OCEAN
		model.sea_zone[y1] = 0 if x < 2 else (1 if x < 4 else 2)
	var zones: Array[SeaZoneState] = []
	for zone_id in 3:
		var tiles: Array[Vector2i] = []
		for x in range(zone_id * 2, zone_id * 2 + 2):
			tiles.append(Vector2i(x, 1))
		zones.append(SeaZoneState.create(zone_id, "Z%d" % zone_id, tiles, Vector2.ZERO, 2))
	model.sea_zones = zones
	var world := WorldMap.new()
	world.add_region(_ai_colonisation_old_world())
	world.add_region(model)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	unit.embark_on(fleet.id)
	fleet.add_civilian(unit.id)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, model, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "sail")
	assert_eq(int(order.get("zone", -1)), 1)
	assert_eq(AiSeaRoute.step_toward(model, 0, [0]), -1)
	assert_eq(AiColonisationPlanner._carried_id(FleetState.in_port(9, ai_colonisation_OWNER, 0)), -1)

## A court lands only on a coast it has charted (wiki: fog-and-exploration;
## DR-20261110-21).
func test_an_uncharted_coast_is_not_a_landing_ground() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	assert_true(
		AiColonisationPlanner._landing_zones(new_world, "explorer", ai_colonisation_OWNER, charts).is_empty(),
		"the New World water is unknown"
	)
	charts.reveal_sea_zone(ai_colonisation_OWNER, 1, 0)
	var zones: Array[int] = AiColonisationPlanner._landing_zones(
		new_world, "explorer", ai_colonisation_OWNER, charts
	)
	var expected: Array[int] = [0]
	assert_eq(zones, expected, "the charted coast opens the landing")
	assert_true(
		AiColonisationPlanner._landing_zones(new_world, "explorer", ai_colonisation_OWNER).size() == 1,
		"without a chart the fixture reading keeps every coast"
	)

## The map adapter charts the water a rival enters, so a crossing opens the far
## coast for that court alone — the player's fog stays untouched.
func test_the_adapter_charts_the_coast_its_squadron_crosses_to() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	MapPlayCourtFog.build(play)
	assert_false(play.court_charts.knows_zone(ai_colonisation_OWNER, 1, 0), "the far water is unknown")
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "embark")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "sail")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "cross")
	assert_true(
		play.court_charts.knows_zone(ai_colonisation_OWNER, 1, 0),
		"the entered zone is charted for the rival"
	)
	fleet.moved = false
	var landed: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(landed[0]["kind"]), "land", "the charted coast takes the colonist")
	assert_true(play.court_charts.regions_of(0).is_empty(), "the player charts nothing")
	play.ship_layer.free()
	play.civilian_layer.free()

func test_the_adapter_docks_and_refuses_illegal_orders() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	var docked: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(docked[0]["kind"]), "dock")
	assert_true(fleet.is_in_port())
	assert_true(MapPlayColonisationAi.run(null).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world, {"kind": "bogus", "fleet": fleet.id}
	).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world, {"kind": "sail", "fleet": fleet.id, "zone": 99}
	).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world, {"kind": "cross", "fleet": fleet.id}
	).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world,
		{"kind": "land", "fleet": fleet.id, "unit": 999, "tile": Vector2i(0, 0)}
	).is_empty())
	play.ship_layer.free()
	play.civilian_layer.free()

## A squadron left across the water with nothing aboard sails home, so the
## court's hulls are not stranded there for the rest of the campaign: they carry
## the next voyage and an overseas invasion.
func test_a_stranded_squadron_sails_home() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [], {}
	)
	assert_eq(String(order.get("kind", "")), "cross", "the empty squadron crosses home")

## The home squadron is the naval planner's: the colonisation pass never sends a
## court's own water home.
func test_a_squadron_at_home_is_not_sent_home() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [], {}
	)
	assert_true(order.is_empty(), "the home squadron is the naval planner's")

## A squadron that already sailed this turn waits for the next one.
func test_a_squadron_that_already_sailed_waits() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	fleet.moved = true
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [], {}
	)
	assert_true(order.is_empty(), "one crossing a turn")

# --- test_ai_diplomacy_offers ---

func test_every_court_menu_order_has_a_rival_policy() -> void:
	_setup_ai_diplomacy_offers()
	var menu: Array[String] = [
		DiplomacyOrders.KIND_WAR,
		DiplomacyOrders.KIND_PEACE,
		DiplomacyOrders.KIND_ALLIANCE,
		DiplomacyOrders.KIND_BREAK,
		DiplomacyOrders.KIND_BREAK_NAP,
		DiplomacyOrders.KIND_OVERTURE,
		DiplomacyOrders.KIND_AID,
		DiplomacyOrders.KIND_SUBSIDY,
		DiplomacyOrders.KIND_CANCEL_SUBSIDY,
		DiplomacyOrders.KIND_FTP,
		DiplomacyOrders.KIND_REVOKE_FTP,
		DiplomacyOrders.KIND_BOYCOTT,
		DiplomacyOrders.KIND_REVOKE_BOYCOTT,
	]
	var planned: Array[String] = AiDiplomacyPlanner.kinds()
	assert_eq(planned.size(), menu.size(), "no order kind is left out of the rival menu")
	for kind: String in menu:
		assert_true(planned.has(kind), "%s has a rival policy" % kind)

func test_a_warm_rival_signs_a_trade_pact_with_a_fellow_court() -> void:
	_setup_ai_diplomacy_offers()
	# Turn one takes the free Non-Aggression Pact; Join Empire stays closed to a
	# Great Power still holding four provinces, so the next turn spends its one
	# order on the favoured trading pact (wiki: world-market § FTP).
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 70.0
	_stage(2, 3, DiplomacyCatalog.STAGE_EMBASSY)
	var world: Array[int] = [0, 2, 3, 3, 3, 3]
	var first: Dictionary = campaign__run(world, [[2, 3, 70.0]], 1)
	assert_eq(String(_action(first, 2)["kind"]), AiDiplomacyOffers.KIND_OVERTURE)
	assert_eq(String(_action(first, 2)["stage"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(ai_diplomacy_offers_state.overture(2, 3), DiplomacyCatalog.STAGE_NAP, "a fellow court answers")
	# The warmer court, acting later in the same pass, spends its one order on
	# the trade pact the treaty just unlocked.
	assert_eq(String(_action(first, 3)["kind"]), AiDiplomacyOffers.KIND_FTP)
	assert_true(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 2, 3), "the pact is signed at once")
	assert_true(String(campaign__record(first, 3)["message"]).contains("favoured trading pact"))

func test_a_warm_rival_sends_aid_and_pays_from_its_own_purse() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	# A purse that stands above the chest it would bank: a court short of the
	# bar banks at peace now (issue #995), so the gift is the spending court's
	# — the purse above the war chest it is not saving for (#603).
	var chest: int = (
		ai_diplomacy_offers_config.parameter("army.min_treasury")
		+ AiArmyReinforce.cheapest_line_price(
			ai_diplomacy_offers_ai_state.economy_for(2)
		)
	)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = chest + 1000
	# The pairing keeps neither crown stronger than the other, so the binding
	# pact still serves both ends and the gift goes out (issue #752).
	var result: Dictionary = campaign__run([0, 2, 2, 3, 3], [], 1)
	var action: Dictionary = _action(result, 2)
	assert_eq(String(action["kind"]), AiDiplomacyOffers.KIND_AID)
	assert_eq(int(action["amount"]), DiplomacyCatalog.GRANT_AID_STEP)
	assert_eq(int(action["target"]), 3)
	assert_true(ai_diplomacy_offers_state.relation(2, 3).score > 60.0, "the court remembers the gift")
	assert_true(_event("grantAid"), "the shared aid rules made the transfer")

func test_aid_stops_when_the_purse_cannot_cover_it() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state, ai_diplomacy_offers_AiFixture.world([0, 2, 3, 3, 3, 3]), 1,
		campaign__context({2: 10, 3: 40})
	)
	assert_true((plan["action"] as Dictionary).is_empty())
	assert_eq(_offer_blocked(plan, AiDiplomacyOffers.KIND_AID), "The treasury cannot cover that aid.")

func test_a_saving_rival_grants_no_aid_and_names_the_reserve_it_keeps() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	# The purse is under the court's own cash floor, so it reads `earn` and every
	# spender that can wait stands down (wiki: treasury-planner § Priority; #580).
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 10
	var result: Dictionary = campaign__run([0, 2, 3, 3, 3, 3], [], 1)
	assert_false(_event("grantAid"), "a saving court gifts nothing")
	assert_ne(String(_action(result, 2).get("kind", "")), AiDiplomacyOffers.KIND_AID)
	var reserve: int = int(campaign__record(result, 2)["income"]["reserve"])
	assert_true(reserve > 10, "the court reads earn below its reserve")
	assert_eq(
		_offer_blocked(campaign__record(result, 2), AiDiplomacyOffers.KIND_AID),
		"the court is saving for its reserve (%d)" % reserve,
		"the refusal names the reserve the court keeps",
	)


## A fleetless court saving for its yard does not gift the chest as aid — the
## diplomacy pass reads the same hull claim the money goal reserves (#484, #580).
func test_a_fleetless_court_saving_for_a_hull_grants_no_aid() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	var economy: PlayerEconomy = ai_diplomacy_offers_ai_state.economy_for(2)
	economy.treasury = 4000
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var chest: int = ShipEconomy.treasury_cost("sloop")
	var result: Dictionary = campaign__run(
		[0, 2, 3, 3, 3, 3], [], 1, {}, {2: chest}, {2: 0}
	)
	assert_false(_event("grantAid"), "the yard chest is not gifted away")
	assert_ne(String(_action(result, 2).get("kind", "")), AiDiplomacyOffers.KIND_AID)
	assert_eq(int(campaign__record(result, 2)["income"]["reserve"]), chest)
	assert_eq(
		_offer_blocked(campaign__record(result, 2), AiDiplomacyOffers.KIND_AID),
		"the court is saving for its reserve (%d)" % chest,
	)

func test_a_saving_rival_sets_no_subsidy() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 6, 1)
	ai_diplomacy_offers_state.relation(2, 6).score = 70.0
	_stage(2, 6, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 10
	var result: Dictionary = campaign__run([0, 0, 0, 2, 6], [], 1)
	assert_eq(ai_diplomacy_offers_state.subsidy(2, 6), 0, "no subsidy is set")
	var reserve: int = int(campaign__record(result, 2)["income"]["reserve"])
	assert_eq(
		_offer_blocked(campaign__record(result, 2), AiDiplomacyOffers.KIND_SUBSIDY),
		"the court is saving for its reserve (%d)" % reserve,
	)

func test_a_gift_that_would_break_the_reserve_is_refused() -> void:
	# A court above its reserve may still not gift itself back under it: the
	# reserve is the purse the muster is waiting for (wiki: treasury-planner
	# § Priority; #580).
	var income: Dictionary = {"goal": "spend", "reserve": 2400, "treasury": 3000}
	assert_eq(
		AiIncome.saving_reason(income, 1000),
		"the court is saving for its reserve (2400)",
	)
	assert_eq(AiIncome.saving_reason(income, 0), "", "a subsidy takes nothing today")
	income["treasury"] = 3400
	assert_eq(AiIncome.saving_reason(income, 1000), "", "the gift leaves the reserve whole")
	assert_eq(
		AiIncome.saving_reason({"goal": "earn", "reserve": 500, "treasury": 900}),
		"the court is saving for its reserve (500)",
	)

func test_a_rival_subsidises_a_minor_it_wants_close() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 6, 1)
	ai_diplomacy_offers_state.relation(2, 6).score = 70.0
	_stage(2, 6, DiplomacyCatalog.STAGE_NAP)
	# The colony door (Join Empire) is worth more than a subsidy while the purse
	# covers it (DR-20261114-02), so the court that wants this Minor close but
	# cannot buy it takes the free warm step instead.
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 4500
	var result: Dictionary = campaign__run([0, 0, 0, 2, 6], [], 1)
	var action: Dictionary = _action(result, 2)
	assert_eq(String(action["kind"]), AiDiplomacyOffers.KIND_SUBSIDY)
	assert_eq(int(ai_diplomacy_offers_state.subsidy(2, 6)), int(action["amount"]))
	assert_eq(int(ai_diplomacy_offers_state.subsidy(2, 6)), DiplomacyCatalog.SUBSIDY_MIN)

func test_a_rival_ends_a_subsidy_once_the_friendship_cools() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 6, 1)
	ai_diplomacy_offers_state.relation(2, 6).score = 40.0
	# The pair holds no pact, so the cooled friendship only ends the subsidy:
	# a court that wants the war a pact would ban breaks the pact first
	# (wiki: diplomacy § Breaking a pact; issue #752).
	_stage(2, 6, DiplomacyCatalog.STAGE_EMBASSY)
	ai_diplomacy_offers_state.set_subsidy(2, 6, 10)
	ai_diplomacy_offers_ai_state.note_war(2, 6, 1)
	var result: Dictionary = campaign__run([0, 0, 0, 2, 6], [], 2, {2: 3})
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_CANCEL_SUBSIDY)
	assert_eq(ai_diplomacy_offers_state.subsidy(2, 6), 0, "the shared rules end the subsidy")

func test_a_rival_too_weak_to_fight_boycotts_a_rival_it_has_fallen_out_with() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 30.0
	ai_diplomacy_offers_state.set_colony(9, 2)
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 0
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = campaign__run([0, 2, 3, 3, 3, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_BOYCOTT)
	assert_true(DiplomacyTrade.is_boycotting(ai_diplomacy_offers_state, 2, 3), "the colonies close at once")
	assert_true(String(campaign__record(result, 2)["message"]).contains("closes its colonies"))

func test_a_recovered_standing_lifts_the_boycott() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 65.0
	ai_diplomacy_offers_state.set_colony(9, 2)
	ai_diplomacy_offers_state.boycotts["2>3"] = 1
	ai_diplomacy_offers_state.ftps[ai_diplomacy_offers_state.pair_key(2, 3)] = 1
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 0
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = campaign__run([0, 2, 3, 3, 3, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_REVOKE_BOYCOTT)
	assert_false(DiplomacyTrade.is_boycotting(ai_diplomacy_offers_state, 2, 3))

func test_a_pact_that_no_longer_matches_the_standing_is_revoked() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 30.0
	ai_diplomacy_offers_state.ftps[ai_diplomacy_offers_state.pair_key(2, 3)] = 1
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 0
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = campaign__run([0, 2, 3, 3, 3, 3], [], 2)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_REVOKE_FTP)
	assert_false(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 2, 3))

func test_an_alliance_the_court_no_longer_means_is_broken() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	ai_diplomacy_offers_state.relation(2, 3).formal_alliance = true
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = campaign__run([0, 2, 2, 2, 2, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_BREAK)
	assert_false(ai_diplomacy_offers_state.relation(2, 3).formal_alliance, "the treaty is dissolved")
	assert_true(String(campaign__record(result, 2)["message"]).contains("breaks its alliance"))

func test_a_trade_pact_offer_to_the_human_court_waits_for_the_answer() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(0, 2, 1)
	ai_diplomacy_offers_state.relation(0, 2).score = 70.0
	_stage(0, 2, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = campaign__run([0, 0, 0, 0, 2, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_FTP)
	assert_true(bool(_action(result, 2)["propose"]), "the human keeps consent")
	assert_false(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 0, 2), "nothing is signed yet")
	assert_eq(ai_diplomacy_offers_state.pending_offers.size(), 1)
	assert_eq(String(ai_diplomacy_offers_state.pending_offers[0]["kind"]), DiplomacyProposals.KIND_FTP)
	assert_true(String(campaign__record(result, 2)["message"]).contains("favoured trading pact"))
	var answer: Dictionary = DiplomacyProposals.resolve_human(ai_diplomacy_offers_state, null, true)
	assert_true(bool(answer.get("accepted", false)), answer.get("reason", ""))
	assert_true(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 0, 2), "the court's answer signs the pact")

func test_one_sided_acts_and_consent_offers_are_told_apart() -> void:
	_setup_ai_diplomacy_offers()
	# A new order kind must reach the rival courts the turn it reaches the panel:
	# either through the court queue or as a one-sided act.
	var one_sided: Array[String] = [
		DiplomacyOrders.KIND_AID,
		DiplomacyOrders.KIND_BOYCOTT,
		DiplomacyOrders.KIND_REVOKE_BOYCOTT,
		DiplomacyOrders.KIND_SUBSIDY,
		DiplomacyOrders.KIND_CANCEL_SUBSIDY,
		DiplomacyOrders.KIND_REVOKE_FTP,
		DiplomacyOrders.KIND_BREAK,
		DiplomacyOrders.KIND_BREAK_NAP,
	]
	for kind: String in AiDiplomacyOffers.KINDS:
		var queued: bool = DiplomacyProposals.knows(kind)
		assert_true(queued or one_sided.has(kind), "%s has a path to the human court" % kind)
	for kind: String in one_sided:
		assert_false(
			DiplomacyProposals.knows(kind),
			"%s needs no consent, so it never blocks the court" % kind
		)

func test_an_isolationist_values_a_trade_pact_less() -> void:
	_setup_ai_diplomacy_offers()
	# Same warm standing, same one order: the isolationist prices the pact 20
	# lower, so it keeps to the overture chain where a plain court would trade
	# (wiki: hidden-agendas — minimal trade; DR-20261111-27).
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 75.0
	_stage(2, 3, DiplomacyCatalog.STAGE_EMBASSY)
	var context: Dictionary = campaign__context({2: 100, 3: 100})
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, 3, 3, 3, 3])
	var plain_entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state, world, 1, 3, 20, context
	)
	var loner: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ISOLATIONIST)
	loner.personality = AiPersonality.NEUTRAL
	var loner_entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		loner, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state, world, 1, 3, 20, context
	)
	var plain_pact: int = _utility_of(plain_entries, AiDiplomacyOffers.KIND_FTP)
	assert_true(plain_pact > 0, "the pact is legal at a warm standing")
	assert_eq(plain_pact, _utility_of(loner_entries, AiDiplomacyOffers.KIND_FTP) + 20)
	assert_eq(
		_utility_of(plain_entries, AiDiplomacyOffers.KIND_OVERTURE),
		_utility_of(loner_entries, AiDiplomacyOffers.KIND_OVERTURE),
		"the envoy chain is untouched"
	)

## A rival opens an envoy chain to a Minor or Tribe because it has seen land worth
## buying there; a province it has never charted buys no nudge at all, so the
## overture stays closed while the court is in no mood to improve relations
## (wiki: civilian-units § Merchant, fog-and-exploration § Visibility Levels;
## DR-20261113-03).
func test_a_banking_court_waits_with_its_envoy_rungs() -> void:
	# The conquest bank (issue #995): a paid envoy rung is a deferrable
	# purchase, and a court one line-cycle short of its chest buys the line
	# first — the measured bench had a −883 embassy rung eat the fill the turn
	# the purse peaked. The chain the deed serves walks again the turn the
	# host stands.
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 75.0
	_stage(2, 3, DiplomacyCatalog.STAGE_EMBASSY)
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, 3, 3, 3, 3])
	var context: Dictionary = campaign__context({2: 100, 3: 100})
	context["income"] = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	context["regiments"] = {2: 1}
	var entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, 3, 20, context
	)
	assert_true(
		_offer_blocked_kind(entries, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"a banking court signs no paid rung, and the trace names the host line"
	)
	# The published rung stands for a court that is not banking.
	context["income"] = {
		"goal": AiIncome.GOAL_SPEND, "reserve": 500, "treasury": 5000,
		"regiments": 9, "conquest_gap": true,
	}
	var published: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, 3, 20, context
	)
	assert_false(
		_offer_blocked_kind(published, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"a court with its host standing walks its chain"
	)


## The army outranks the funded chain while the conquest bank is engaged (issue
## #1135's bypass learned the price of a rung): a paid embassy ate the chest the
## muster was filling, so the line stayed unfunded for the campaign (bench run
## 2026-11-22: 16 provinces and one regiment, then 31 provinces and eight
## regiments once the rung waited). The chain walks again the turn the host
## stands.
func test_a_banking_court_waits_its_funded_chain_behind_the_army() -> void:
	_setup_ai_diplomacy_offers()
	var tribe: int = FactionCatalog.tribe_ids()[0]
	ai_diplomacy_offers_state.ensure_relation(2, tribe, 1)
	ai_diplomacy_offers_state.relation(2, tribe).score = 60.0
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var context: Dictionary = campaign__context({2: 100, 3: 100})
	context["treasury"] = {2: 1000, 3: 100}
	# The Tribe is on the court's own map at a warm standing: the colony
	# ambition prices its 500-cost rung against the purse (a chain the court
	# funds), and the bank's face steps aside.
	context["income"] = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	context["regiments"] = {2: 1}
	var entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, tribe, 20, context
	)
	assert_true(
		_offer_blocked_kind(entries, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"the funded chain waits while the army banks"
	)
	# The host stands: the bank lets go and the same chain walks.
	context["income"] = {
		"goal": AiIncome.GOAL_SPEND, "reserve": 500, "treasury": 5000,
		"regiments": 9, "conquest_gap": true,
	}
	var standing: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, tribe, 20, context
	)
	assert_false(
		_offer_blocked_kind(standing, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"a court whose host stands walks its funded chain"
	)
	context["income"] = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	# A court with no chain (no charted Tribe beside it) still waits behind the
	# bank: the aim the ledger funds here is the army's.
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	var other: Dictionary = campaign__context({2: 100, 3: 100})
	other["income"] = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	other["regiments"] = {2: 1}
	var other_entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, 3, 20, other
	)
	assert_true(
		_offer_blocked_kind(other_entries, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"a court with no funded chain keeps the bank's face"
	)


## The deed's chain waits behind the army too: a court that is short of the bar
## and one line-cycle short of its chest buys the line first, the paid rung
## after. The chain walks the turn the host stands, so the Merchant's purchase
## still finds its embassy.
func test_a_banking_court_waits_a_minor_deeds_chain() -> void:
	_setup_ai_diplomacy_offers()
	var minor: int = FactionCatalog.minor_ids()[0]
	ai_diplomacy_offers_state.ensure_relation(2, minor, 1)
	ai_diplomacy_offers_state.relation(2, minor).score = 60.0
	# A Minor on a priced deed: the headline resource tile set on the model grid
	# and the province, at the published 15 x base price.
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([2, minor])
	var model: MapModel = world.region(0)
	model.resource[model.index_of(1, 0)] = 0
	var seller: ProvinceState = model.provinces[1]
	seller.resource = 0
	seller.resource_tile = Vector2i(1, 0)
	var context: Dictionary = campaign__context({2: 100, 3: 100})
	context["treasury"] = {2: 1000, 3: 100}
	context["income"] = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	context["regiments"] = {2: 1}
	var entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, minor, 20, context
	)
	assert_true(
		_offer_blocked_kind(entries, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"a Minor deed's chain waits while the court banks"
	)
	# The host stands: the same chain walks to its embassy.
	var standing_income: Dictionary = {
		"goal": AiIncome.GOAL_SPEND, "reserve": 500, "treasury": 5000,
		"regiments": 9, "conquest_gap": true,
	}
	context["income"] = standing_income
	var standing: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, minor, 20, context
	)
	assert_false(
		_offer_blocked_kind(standing, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"a court whose host stands walks its deed chain"
	)
	context["income"] = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	# Without a priced deed on the seller's chart the bank's face stands.
	var bare_world: WorldMap = ai_diplomacy_offers_AiFixture.world([2, minor])
	var bare_entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, bare_world, 1, minor, 20, context
	)
	assert_true(
		_offer_blocked_kind(bare_entries, AiDiplomacyOffers.KIND_OVERTURE).begins_with(
			"the court is banking for its army"
		),
		"no priced deed, no deed chain: the bank's face stands"
	)


## The deed Merchant is hired while the court banks, once the court's own ledger
## funds a priced, openable deed (#1135): the bank holds the roster, not the one
## crew the ledger is saving toward.
func test_a_deed_merchant_is_hired_while_the_court_banks() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var crews: Dictionary = _civilian_context()
	crews["staff_targets"] = {
		"builder": 0, "engineer": 0, "explorer": 0, "spy": 0, "merchant": 1,
	}
	crews["tech_unlocked"] = {"merchant_companies": true}
	crews["merchant_targets"] = 1
	crews["deed_price"] = 900
	crews["conquest_bank"] = true
	crews["phase"] = AiPhasePlanner.PHASE_PEACE
	var hired: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_true(
		bool(hired.get("ok", false)),
		"the ledger funds a priced deed, so its Merchant is hired"
	)
	assert_eq(String(hired["type_id"]), "merchant")
	# Without a priced deed on the chart the bank still holds the purse.
	crews["deed_price"] = 0
	var unfunded: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_eq(
		String(unfunded.get("reason", "")), AiCivilianHire.REASON_BANK,
		"a court with no deed on offer keeps its purse for the army"
	)


## The deed Merchant's hire is payable while the court banks (issue #1225): the
## carve-out opened the gate, and the works purse — the same purse the deed's
## own purchase prices against (`LandPurchase.check`) — pays the crew that walks
## through it. A court whose standing spendable purse is a few hundred ducats
## still musters the Merchant its priced deed waits on, at peace or at war on a
## stranded claim (#1139), and a works purse short of the catalogue's price
## still takes no Merchant.
func test_a_banked_court_pays_the_deed_merchant_from_the_works_purse() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var crews: Dictionary = _civilian_context()
	crews["staff_targets"] = {
		"builder": 0, "engineer": 0, "explorer": 0, "spy": 0, "merchant": 1,
	}
	crews["tech_unlocked"] = {"merchant_companies": true}
	crews["merchant_targets"] = 1
	crews["deed_price"] = 900
	crews["conquest_bank"] = true
	crews["phase"] = AiPhasePlanner.PHASE_PEACE
	crews["earn"] = true
	# The banked purse: the standing spendable purse is a few hundred ducats,
	# the works purse the deed's purchase draws on covers the hire.
	crews["hire_treasury"] = 300
	var hired: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_true(
		bool(hired.get("ok", false)),
		"the works purse pays the Merchant the priced deed waits on"
	)
	assert_eq(String(hired["type_id"]), "merchant")
	# The stranded claim's Merchant rides the same purse at war (#1139's
	# acceptance half: the hire shows while the court banks on a war footing).
	crews["voyage_crew_kind"] = "merchant"
	crews["voyage_stranded"] = true
	crews["phase"] = AiPhasePlanner.PHASE_WAR
	crews["at_war"] = true
	var claim: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_true(
		bool(claim.get("ok", false)),
		"the stranded claim's Merchant is payable at war and banked"
	)
	assert_eq(String(claim["type_id"]), "merchant")
	# A works purse short of the catalogue's price takes no Merchant: the gate
	# is open, the purse is not.
	crews["voyage_crew_kind"] = ""
	crews["voyage_stranded"] = false
	crews["phase"] = AiPhasePlanner.PHASE_PEACE
	crews["at_war"] = false
	crews["treasury"] = 1200
	var short: Dictionary = AiCivilianHire.training_order(config, [], crews)
	assert_false(
		bool(short.get("ok", false)), "a short works purse hires no Merchant"
	)
	# The ride is the Merchant's alone: while the deed stands, the spy keeps
	# the standing purse and the bank's face.
	crews["treasury"] = 2500
	var spy_court: Dictionary = crews.duplicate()
	spy_court["staff_targets"] = {
		"builder": 0, "engineer": 0, "explorer": 0, "spy": 1, "merchant": 0,
	}
	var spy: Dictionary = AiCivilianHire.training_order(config, [], spy_court)
	assert_eq(
		String(spy.get("reason", "")), AiCivilianHire.REASON_BANK,
		"the deed's purse is the Merchant's, not the college's"
	)


## The study door the deed opens is the buyer's own tech, and it stays shut for
## a court that already holds it or has no priced deed on its chart (issue
## #841; wiki: civilian-units § Merchant).
func test_the_deed_door_studies_merchant_companies_when_a_deed_is_priced() -> void:
	var world: WorldMap = _two_minor_world()
	var state := DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, DEED_MINOR, 1)
	state.ensure_relation(0, DEAR_MINOR, 1)
	assert_eq(
		AiMerchantWork.deed_door(world, 0, null, state, {}), "merchant_companies",
		"a priced deed opens the study door"
	)
	assert_eq(
		AiMerchantWork.deed_door(
			world, 0, null, state, {"merchant_companies": true}
		),
		"", "the court already holds the buyer's tech"
	)
	var bare := DiplomacyState.new()
	bare.initialize(1)
	bare.ensure_relation(0, DEED_MINOR, 1)
	# Both deeds signed: the door shuts with the last priced offer.
	var deeded: WorldMap = _two_minor_world()
	var region: MapModel = deeded.region(WorldMap.OLD_WORLD)
	for tile: Vector2i in [Vector2i(2, 0), Vector2i(5, 0)]:
		region.purchase_tile(tile, 0)
	assert_eq(
		AiMerchantWork.deed_door(deeded, 0, null, bare, {}), "",
		"a court with no deed on offer studies something else"
	)
	# And the door is the one the research planner takes first.
	var config: AiConfig = _research_config()
	var plan: Dictionary = AiResearchPlanner.plan(
		config, PlayerEconomy.starting(),
		{"door": AiMerchantWork.deed_door(world, 0, null, state, {})}
	)
	assert_eq(
		String(plan["assignments"][0]["tech"]), "merchant_companies",
		"the deed door is taken first"
	)


## The warmth that prices a deed is the warmth that bars a declaration, so the
## seller scan names one deed partner per court: warming every charted Minor
## closed the conquest path outright (issue #724 round 3), and the owner's call
## on #840 is one targeted seller per court (issue #841). The planner's own
## warming read is retired; the merchant module keeps the scan the courts share.
func test_the_deed_seller_scan_names_one_seller() -> void:
	var world: WorldMap = _two_minor_world()
	var state := DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, DEED_MINOR, 1)
	state.ensure_relation(0, DEAR_MINOR, 1)
	assert_eq(
		AiMerchantWork.deed_seller(world, 0, null, state), DEED_MINOR,
		"the cheaper deed names the court's one seller"
	)
	# A war with the seller leaves no deed to price, so nothing to warm.
	var war_court := DiplomacyState.new()
	war_court.initialize(1)
	war_court.ensure_relation(0, DEED_MINOR, 1)
	war_court.ensure_relation(0, DEAR_MINOR, 1)
	assert_true(
		bool(DiplomacyRules.declare_war(war_court, 0, DEED_MINOR, true, world).get("ok", false))
	)
	assert_eq(
		AiMerchantWork.deed_seller(world, 0, null, war_court), DEAR_MINOR,
		"the war closes the cheap seller and the next offer names the other"
	)


## The turn pass names the court's one deed partner before the planner runs: the
## trace carries the seller so a warm Minor reads as the deed partner and not as
## a conquest (issue #841). A court with no Merchant Companies names none — it
## has no chain to open and pays for no scan.
func test_the_turn_pass_names_the_deed_seller_for_the_planner() -> void:
	_setup_ai_diplomacy_offers()
	var world: WorldMap = _two_minor_world(2)
	ai_diplomacy_offers_state.ensure_relation(2, DEED_MINOR, 1)
	ai_diplomacy_offers_state.ensure_relation(2, DEAR_MINOR, 1)
	ai_diplomacy_offers_state.relation(2, DEED_MINOR).score = 50.0
	ai_diplomacy_offers_state.relation(2, DEAR_MINOR).score = 50.0
	var context: Dictionary = {"regiments": {}, "ships": {}}
	var techless: Dictionary = AiTurn.run(
		ai_diplomacy_offers_state, world, ai_diplomacy_offers_ai_state, 1, 0, 1500, context
	)
	assert_eq(
		_trace_deed_seller(techless, 2), -1,
		"no Merchant Companies, no chain to warm"
	)
	ai_diplomacy_offers_ai_state.economy_for(2).tech_unlocked["merchant_companies"] = true
	var result: Dictionary = AiTurn.run(
		ai_diplomacy_offers_state, world, ai_diplomacy_offers_ai_state, 1, 0, 1500, context
	)
	assert_eq(
		_trace_deed_seller(result, 2), DEED_MINOR,
		"the pass names the cheapest deed partner"
	)


## The deed partner the turn trace recorded for one court, or -1.
func _trace_deed_seller(result: Dictionary, faction: int) -> int:
	for record: Dictionary in result.get("trace", []):
		if int(record.get("faction", -1)) == faction:
			return int(record.get("deed_seller", -1))
	return -1


## Two Minor Nations beside one crown, each with a priced resource tile: the
## cheap grain deed names one seller and the dear iron deed the other, so the
## warmth a court spends on a deed can be aimed at one partner (issue #841).
func _two_minor_world(crown: int = 0) -> WorldMap:
	var model := MapModel.new()
	model.setup(6, 2)
	var crown_tiles: Array[Vector2i] = []
	var cheap_tiles: Array[Vector2i] = []
	var dear_tiles: Array[Vector2i] = []
	for y in 2:
		for x in 6:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 2:
				model.province[model.index_of(x, y)] = 0
				crown_tiles.append(tile)
			elif x < 4:
				model.province[model.index_of(x, y)] = 1
				cheap_tiles.append(tile)
			else:
				model.province[model.index_of(x, y)] = 2
				dear_tiles.append(tile)
	model.resource[model.index_of(2, 0)] = 4
	model.terrain[model.index_of(5, 0)] = MapModel.Terrain.HILLS
	model.resource[model.index_of(5, 0)] = 1
	var seat := ProvinceState.create(
		0, "Cádiz", crown_tiles, Vector2(0.5, 1.0), crown_tiles.size(), crown, true
	)
	seat.capital_tile = Vector2i(0, 0)
	var cheap := ProvinceState.create(
		1, "Genoa", cheap_tiles, Vector2(2.5, 1.0), cheap_tiles.size(), DEED_MINOR, false
	)
	cheap.capital_tile = Vector2i(2, 0)
	cheap.resource = 4
	cheap.resource_tile = Vector2i(2, 0)
	var dear := ProvinceState.create(
		2, "Venice", dear_tiles, Vector2(4.5, 1.0), dear_tiles.size(), DEAR_MINOR, false
	)
	dear.capital_tile = Vector2i(4, 0)
	dear.resource = 1
	dear.resource_tile = Vector2i(5, 0)
	model.provinces = [seat, cheap, dear]
	var world := WorldMap.new()
	world.add_region(model)
	return world


## The refusal an offers candidate list recorded for one order kind ("" when the
## candidate was legal).
func _offer_blocked_kind(entries: Array[Dictionary], kind: String) -> String:
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) == kind and not bool(entry.get("ok", false)):
			return String(entry.get("blocked", ""))
	return ""


## The legal candidate's utility for one kind, or -1 when it was refused.
func _utility_of(entries: Array[Dictionary], kind: String) -> int:
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) != kind:
			continue
		assert_true(
			bool(entry.get("ok", false)),
			"%s is legal: %s" % [kind, String(entry.get("blocked", ""))]
		)
		return int(entry.get("utility", -1))
	return -1

## Opens the turn pass with the given relation scores applied (default 50).
func campaign__run(
	world: Array[int], scores: Array, turn: int, regiments: Dictionary = {},
	hull_chests: Dictionary = {}, warships: Dictionary = {}
) -> Dictionary:
	for entry: Array in scores:
		ai_diplomacy_offers_state.ensure_relation(int(entry[0]), int(entry[1]), turn)
		ai_diplomacy_offers_state.relation(int(entry[0]), int(entry[1])).score = float(entry[2])
	return AiTurn.run(
		ai_diplomacy_offers_state, ai_diplomacy_offers_AiFixture.world(world), ai_diplomacy_offers_ai_state, turn, 0, 1500,
		{
			"regiments": regiments, "ships": {},
			"hull_chests": hull_chests, "warships": warships,
		}
	)

## A New World region (every tile unknown at setup) holding one Tribe province
## with a timber tile, so only a court that charts it can price the land or the
## commodity (wiki: fog-and-exploration § Visibility Levels; DR-20261113-03).
func _uncharted_tribe_world(owner: int = TRIBE) -> WorldMap:
	var model := MapModel.new()
	model.setup(3, 2)
	model.region_id = FactionCatalog.NEW_WORLD
	model.region_key = "new_world"
	model.faction_ids = [owner]
	var tiles: Array[Vector2i] = []
	for x in 3:
		model.terrain[model.index_of(x, 0)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(x, 0)] = 0
		tiles.append(Vector2i(x, 0))
	model.resource[model.index_of(0, 0)] = 0
	var province := ProvinceState.create(
		0, "P0", tiles, Vector2(0.0, 0.0), 3, owner, false
	)
	province.resource = 0
	province.resource_tile = Vector2i(0, 0)
	model.provinces.append(province)
	var world := WorldMap.new()
	world.add_region(model)
	return world


## Charts cut from `world`. `human` is a court the tests never read as, so every
## reader gets its own rival grid (the human's table stays empty).
func _charts(world: WorldMap, human: int = 7) -> CourtCharts:
	var charts := CourtCharts.new()
	charts.setup(world, human, {})
	return charts


func campaign__context(power: Dictionary) -> Dictionary:
	var context: Dictionary = ai_diplomacy_offers_AiFixture.context(power)
	context["treasury"] = {}
	context["tech"] = {}
	context["player"] = 0
	return context

## Both directions at one stage, as a signed overture lands.
func _stage(a: int, b: int, stage: String) -> void:
	ai_diplomacy_offers_state.set_overture(a, b, stage)
	ai_diplomacy_offers_state.set_overture(b, a, stage)

## The refusal the offers module recorded for one order kind.
func _offer_blocked(plan: Dictionary, kind: String) -> String:
	var offer: Dictionary = plan["candidates"][0].get("offer", {})
	for entry: Dictionary in offer.get("candidates", []):
		if String(entry.get("kind", "")) == kind:
			return String(entry.get("blocked", ""))
	return ""

func _action(run: Dictionary, faction: int) -> Dictionary:
	return campaign__record(run, faction).get("action", {})

func campaign__record(run: Dictionary, faction: int) -> Dictionary:
	for record: Dictionary in run["trace"]:
		if int(record["faction"]) == faction:
			return record
	return {}

func _event(kind: String) -> bool:
	for entry: Dictionary in ai_diplomacy_offers_state.events:
		if String(entry.get("kind", "")) == kind:
			return true
	return false

## A Tribe the court has charted and can still buy is drawn into the empire
## before it is fought: the declaration would clear the chain, and its provinces
## never count toward victory (wiki: factions § Tribe; DR-20261114-02).
func test_a_charted_tribe_is_bought_before_it_is_fought() -> void:
	_setup_ai_diplomacy_offers()
	var tribe: int = FactionCatalog.tribe_ids()[0]
	ai_diplomacy_offers_state.ensure_relation(2, tribe, 1)
	ai_diplomacy_offers_state.relation(2, tribe).score = 40.0
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1,
		_tribe_context({2: 120, tribe: 20}, {2: 5000})
	)
	var action: Dictionary = plan["action"]
	assert_eq(String(action["kind"]), AiDiplomacyOffers.KIND_OVERTURE)
	assert_eq(String(action["stage"]), DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(bool(action.get("tribe_colony", false)), "the colony ambition raised the envoy offer")


## The same court with no money to buy the colony still fights: the ambition
## lowers no legality, it only says what the court wants (REQ-P2-03).
func test_a_poor_court_still_fights_a_tribe_it_cannot_buy() -> void:
	_setup_ai_diplomacy_offers()
	var tribe: int = FactionCatalog.tribe_ids()[0]
	ai_diplomacy_offers_state.ensure_relation(2, tribe, 1)
	ai_diplomacy_offers_state.relation(2, tribe).score = 40.0
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1,
		_tribe_context({2: 120, tribe: 20}, {2: 100})
	)
	assert_eq(String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)


## A chain already opened is a stake: a court that has paid a Consulate does not
## clear it by declaring because the Embassy is out of reach this turn.
func test_a_chain_already_opened_is_not_cleared_by_a_war() -> void:
	_setup_ai_diplomacy_offers()
	var tribe: int = FactionCatalog.tribe_ids()[0]
	ai_diplomacy_offers_state.ensure_relation(2, tribe, 1)
	ai_diplomacy_offers_state.relation(2, tribe).score = 40.0
	_stage(2, tribe, DiplomacyCatalog.STAGE_CONSULATE)
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1,
		_tribe_context({2: 120, tribe: 20}, {2: 100})
	)
	assert_true((plan["action"] as Dictionary).is_empty(), "the chain holds the court")
	assert_eq(
		ai_diplomacy_offers_state.overture(2, tribe),
		DiplomacyCatalog.STAGE_CONSULATE,
		"no declaration cleared the chain"
	)


## A Tribe the court has never charted is no colony in reach: the published map
## is not a chart, and the offer stands down as before (DR-20261113-03).
func test_an_uncharted_tribe_is_not_a_colony_in_reach() -> void:
	_setup_ai_diplomacy_offers()
	var tribe: int = FactionCatalog.tribe_ids()[0]
	ai_diplomacy_offers_state.ensure_relation(2, tribe, 1)
	ai_diplomacy_offers_state.relation(2, tribe).score = 40.0
	var world: WorldMap = _uncharted_tribe_world()
	var goal: Dictionary = AiTribeColony.ambition(
		ai_diplomacy_offers_state, world, _charts(world), 2, tribe, 5000, {}
	)
	assert_false(bool(goal["wanted"]), "an uncharted shore offers nothing it can price")
	assert_eq(String(goal["reason"]), "the court has not charted that shore")
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1,
		_tribe_context({2: 120, tribe: 20}, {2: 5000}, _charts(world))
	)
	assert_eq(String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)


## The Tribe nearest the colony wins the court's ambition: the furthest overture
## stage, then the warmer herald, then the lower id (REQ-P2-03).
func test_the_tribe_furthest_along_the_chain_is_the_one_wanted() -> void:
	var first: int = FactionCatalog.tribe_ids()[0]
	var second: int = FactionCatalog.tribe_ids()[1]
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, first, 1).score = 70.0
	state.ensure_relation(2, second, 1).score = 55.0
	state.set_overture(2, first, DiplomacyCatalog.STAGE_CONSULATE)
	state.set_overture(2, second, DiplomacyCatalog.STAGE_EMBASSY)
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, first, second])
	var best: Dictionary = AiTribeColony.best(state, world, null, 2, 5000, {})
	assert_eq(int(best["target"]), second, "the embassy is nearer the colony than the consulate")
	assert_eq(String(best["stage"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(int(best["bonus"]), AiTribeColony.BONUS)
	# Another crown's colony is closed to this one, so the consulate stands in.
	state.set_colony(second, 3)
	var fallback: Dictionary = AiTribeColony.best(state, world, null, 2, 5000, {})
	assert_eq(int(fallback["target"]), first)
	assert_eq(String(fallback["stage"]), DiplomacyCatalog.STAGE_EMBASSY)


## The step that founds the colony is worth more than the steps before it.
func test_the_join_empire_is_the_prize_the_chain_is_walking_to() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, tribe, 1).score = 60.0
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_NAP)
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var goal: Dictionary = AiTribeColony.ambition(state, world, null, 2, tribe, 12000, {})
	assert_true(bool(goal["wanted"]))
	assert_eq(String(goal["stage"]), DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	assert_eq(int(goal["bonus"]), AiTribeColony.BONUS + AiTribeColony.JOIN_BONUS)
	assert_eq(int(goal["cost"]), DiplomacyCatalog.stage_cost(
		DiplomacyCatalog.STAGE_JOIN_EMPIRE, DiplomacyRules.provinces_owned(world, tribe)
	))


## Every refusal names its own reason, so a trace or a test never guesses why a
## Tribe was passed over (wiki: turn-trace-interpretation).
func test_the_ambition_names_why_a_tribe_is_out_of_reach() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	var none: Dictionary = AiTribeColony.ambition(null, world, null, 2, tribe, 5000, {})
	assert_eq(String(none["reason"]), "no tribal court")
	var minor: int = FactionCatalog.minor_ids()[0]
	var state := DiplomacyState.new()
	state.reset(1)
	assert_eq(
		String(AiTribeColony.ambition(state, world, null, 2, minor, 5000, {})["reason"]),
		"not a tribe"
	)
	assert_eq(
		String(AiTribeColony.ambition(state, world, null, 2, tribe, 5000, {})["reason"]),
		"no envoy has reached that court"
	)
	state.ensure_relation(2, tribe, 1).at_war = true
	assert_eq(
		String(AiTribeColony.ambition(state, world, null, 2, tribe, 5000, {})["reason"]),
		"at war with the tribal court"
	)
	state.relation(2, tribe).at_war = false
	state.set_colony(tribe, 2)
	assert_eq(
		String(AiTribeColony.ambition(state, world, null, 2, tribe, 5000, {})["reason"]),
		"already a colony of this crown"
	)
	state.set_colony(tribe, 3)
	assert_eq(
		String(AiTribeColony.ambition(state, world, null, 2, tribe, 5000, {})["reason"]),
		"another crown's colony"
	)
	state.colonies.clear()
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	assert_eq(
		String(AiTribeColony.ambition(state, world, null, 2, tribe, 5000, {})["reason"]),
		"the envoy chain is complete"
	)
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_NONE)
	assert_eq(
		String(AiTribeColony.ambition(state, world, null, 2, tribe, 100, {})["reason"]),
		"the treasury cannot cover the Trade Consulate"
	)


## The door the court is walking to: a chain with a charted Tribe is only as open
## as its next stage, so the tech that stage needs is the study the court owes
## (wiki: diplomacy § GP–Tribe Rules; DR-20261114-05).
func test_the_door_names_the_study_the_chain_needs() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, tribe, 1).score = 60.0
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, tribe, tribe])
	# The Consulate needs no study, so the first link has no door.
	assert_eq(AiTribeColony.door(state, world, null, 2, {}), "")
	# The Embassy does: a court that never studies it leaves the chain dead.
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(
		AiTribeColony.door(state, world, null, 2, {}), "diplomatic_expertise"
	)
	assert_eq(
		AiTribeColony.door(state, world, null, 2, {"diplomatic_expertise": true}), "",
		"the study is already held"
	)
	# A war clears the chain, so there is no door to walk to.
	state.relation(2, tribe).at_war = true
	assert_eq(AiTribeColony.door(state, world, null, 2, {}), "")
	state.relation(2, tribe).at_war = false
	# Another crown's colony is closed to this one.
	state.set_colony(tribe, 3)
	assert_eq(AiTribeColony.door(state, world, null, 2, {}), "")
	state.colonies.clear()
	# An uncharted shore is not a chain the court is buying (DR-20261113-03).
	var uncharted: WorldMap = _uncharted_tribe_world()
	assert_eq(AiTribeColony.door(state, uncharted, _charts(uncharted), 2, {}), "")
	# A chain already complete has no next link.
	state.set_overture(2, tribe, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	assert_eq(AiTribeColony.door(state, world, null, 2, {}), "")


## A court's own ledger read for the ambition tests: the treasury it must pay
## from and the chart it priced the shore on.
func _tribe_context(
	power: Dictionary, treasury: Dictionary, charts: CourtCharts = null
) -> Dictionary:
	var context: Dictionary = ai_diplomacy_offers_AiFixture.context(
		power, {power.keys()[0]: 10}
	)
	context["treasury"] = treasury
	context["tech"] = {}
	context["player"] = 0
	if charts != null:
		context["charts"] = charts
	return context


# --- test_ai_planner ---
func test_desire_starts_at_the_base_and_adds_power_and_relation() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var desire: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 1]), 0, 1,
		ai_planner_AiFixture.context({0: 100, 1: 100})
	)
	assert_eq(int(desire["score"]), 35, "50 base + 5 even power - 20 neutral relations")
	var factors: Dictionary = desire["factors"]
	assert_eq(int(factors["base"]), 50)
	assert_eq(int(factors["relative_power"]), 5)
	assert_eq(int(factors["relation"]), -20)
	assert_eq(int(factors["personality"]), 0)

func test_relative_power_dominates_the_score() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var strong: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, ai_planner_AiFixture.context({0: 135, 1: 100})
	)
	assert_eq(int(strong["score"]), 60, "50 + 30 strong - 20 neutral")
	var weak: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, ai_planner_AiFixture.context({0: 84, 1: 100})
	)
	assert_eq(int(weak["score"]), 5, "50 - 25 weak - 20 neutral")

func test_a_pressing_court_prices_the_war_that_takes_its_land() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var calm: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	var pressed: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	pressed["victory_press"] = 30
	var before: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, calm
	)
	var after: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, pressed
	)
	assert_eq(int(before["score"]), 35, "a court far from the bar keeps the published score")
	assert_eq(int(after["score"]), 65, "the press reaches the war aim")
	assert_eq(int((after["factors"] as Dictionary)["victory_press"]), 30)
	assert_false(
		(before["factors"] as Dictionary).has("victory_press"),
		"no press, no factor"
	)

func test_the_press_is_read_per_court_from_the_map_pass() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["victory_press"] = {0: 30, 1: 0}
	var mine: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, context
	)
	var theirs: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 1, 0, context
	)
	assert_eq(int(mine["score"]), 65, "the pressing court prices its own finish")
	assert_eq(int(theirs["score"]), 35, "a neighbour's press arms nothing")

func test_the_press_ignores_a_target_with_no_old_world_land() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0])
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["victory_press"] = 30
	var desire: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, context
	)
	assert_eq(
		int(desire["score"]), 35,
		"the bar counts Old World land, and this court holds none"
	)
	assert_false((desire["factors"] as Dictionary).has("victory_press"))

func test_relation_pressure_bands() -> void:
	_setup_ai_planner()
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 25.0
	assert_eq(int(AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)["score"]), 65)
	ai_planner_state.relation(0, 1).score = 40.0
	assert_eq(int(AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)["score"]), 55)
	ai_planner_state.relation(0, 1).score = 75.0
	assert_eq(int(AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)["score"]), 15)

func test_minor_targets_pay_the_invasion_capacity_cost() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 6])
	var weak: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 6, ai_planner_AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(weak["score"]), 15, "no regiments is -20")
	var ready: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 6, ai_planner_AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	)
	assert_eq(int(ready["score"]), 45, "superior regiments is +10")

func test_two_active_wars_add_the_multi_war_penalty() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	ai_planner_state.ensure_relation(0, 7, 1)
	ai_planner_state.ensure_relation(0, 8, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 7)
	DiplomacyRules.declare_war(ai_planner_state, 0, 8)
	var desire: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 6]), 0, 6,
		ai_planner_AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	)
	assert_eq(int(desire["factors"]["wars"]), -15)
	assert_eq(int(desire["score"]), 30)

func test_missing_stockpiles_are_scored_against_the_target() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 6, 6, 6, 6], {1: 0, 2: 1, 3: 2, 4: 3})
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 6: 100})
	context["stockpiles"] = {0: {}}
	var need: Dictionary = AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(need["factors"]["resource_need"]), 15, "four missing resources cap at +15")
	context["stockpiles"] = {0: {"timber": 4, "iron": 4, "coal": 4}}
	var partly: Dictionary = AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(partly["factors"]["resource_need"]), 5)

## The commodity term reads only land the court has charted: a province it has
## never sailed past adds nothing to its war desire, and charting it restores the
## bonus (wiki: fog-and-exploration § Visibility Levels; DR-20261113-03).
func test_the_resource_need_counts_only_charted_land() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, TRIBE, 1)
	var world: WorldMap = _uncharted_tribe_world()
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, TRIBE: 100})
	context["stockpiles"] = {0: {}}
	var published: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, TRIBE, context
	)
	assert_eq(
		int(published["factors"]["resource_need"]), 5, "no chart still reads the published map"
	)
	var charts: CourtCharts = _charts(world)
	context["charts"] = charts
	var blind: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, TRIBE, context
	)
	assert_eq(int(blind["factors"]["resource_need"]), 0, "unseen land offers no commodity")
	charts.reveal_province(0, 0, 0)
	var seen: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, world, 0, TRIBE, context
	)
	assert_eq(int(seen["factors"]["resource_need"]), 5, "charted ground prices the commodity")
	assert_eq(
		int(seen["score"]),
		int(blind["score"]),
		"the chart moved the one term the fog reaches, not the whole formula"
	)

func test_rival_embassies_add_the_intervention_risk_penalty() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	ai_planner_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	ai_planner_state.set_overture(2, 6, DiplomacyCatalog.STAGE_EMBASSY)
	ai_planner_state.set_overture(3, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var desire: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 6]), 0, 6,
		ai_planner_AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(desire["factors"]["intervention"]), -24, "three embassies cap at -24")
	ai_planner_state.set_overture(2, 6, DiplomacyCatalog.STAGE_NONE)
	ai_planner_state.set_overture(3, 6, DiplomacyCatalog.STAGE_NONE)
	var single: Dictionary = AiDiplomacyDesire.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 6]), 0, 6,
		ai_planner_AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(single["factors"]["intervention"]), -8)

## A deed is protection in the attacker's eyes too: a rival's purchased land in
## the minor's provinces is a Great Power the declaration would call to the
## victim's aid, so it costs the same -8 as an embassy (wiki: diplomacy
## § Intervention "investment protection"; DR-20261110-20).
func test_a_rival_deed_in_the_minors_land_adds_the_intervention_risk_penalty() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 6])
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	var bare: Dictionary = AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(bare["factors"]["intervention"]), 0, "no one would answer")
	var model: MapModel = world.region(0)
	assert_true(model.ownership.purchase(model.index_of(1, 0), 1), "a rival buys land")
	var bought: Dictionary = AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(bought["factors"]["intervention"]), -8, "the deed holder answers")
	assert_true(
		int(bought["score"]) < int(bare["score"]),
		"the protected minor is the harder war"
	)

func test_declares_war_when_strong_and_relations_are_cool() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1, 1]), 1,
		ai_planner_AiFixture.context({0: 200, 1: 100})
	)
	var action: Dictionary = plan["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_eq(int(action["target"]), 1)
	assert_eq(int(action["desired_territory"]), 2, "clamp(round(75/25), 1, 2)")

# --- the binding-treaty AI (issue #752) ---

func test_a_pacted_rival_breaks_the_pact_instead_of_the_illegal_war() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1, 1]), 1,
		ai_planner_AiFixture.context({0: 200, 1: 100})
	)
	# The war is banned, so the court's highest act is the pact break that opens
	# it (wiki: diplomacy § Breaking a pact; issue #752).
	assert_true(
		String(plan["candidates"][0]["blocked"]).contains("non-aggression pact"),
		String(plan["candidates"][0]["blocked"]),
	)
	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyOffers.KIND_BREAK_NAP,
	)
	assert_eq(int(plan["action"]["target"]), 1)
	# The break is priced at `warDesireScore − 10`, the published worth of a
	# blocked war (wiki: diplomacy § Planner selection; issue #752).
	var desire: int = int((plan["candidates"] as Array)[0]["desire"])
	assert_eq(
		int(((plan["candidates"] as Array)[0]["offer"] as Dictionary)["utility"]),
		desire - 10,
	)

## The published price holds through the band where the break is closest to
## losing its slot: at war desire 60–70 the `warDesireScore − 10` break must
## still outrank every other peaceful order the court could spend its one order
## on, so a dearer cut hands the turn to an overture or retaliation and stalls
## the war the break exists to open (wiki: diplomacy § Planner selection;
## issue #752).
func test_the_pact_break_keeps_the_peaceful_slot_in_the_60_to_70_desire_band() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	# A cold standing: the relation pull is the hostile +10, the lowest desire
	# that still clears the declare bar once a pact stands.
	ai_planner_state.relation(0, 1).score = 20.0
	ai_planner_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	# Even powers put the desire inside the band under test: 50 base + 5 even
	# band + 10 cold standing.
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1, 1]), 1,
		ai_planner_AiFixture.context({0: 100, 1: 100})
	)
	var entry: Dictionary = (plan["candidates"] as Array)[0]
	var desire: int = int(entry["desire"])
	assert_true(desire >= 60 and desire <= 70, "desire %d is the band under test" % desire)
	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyOffers.KIND_BREAK_NAP,
	)
	var offer: Dictionary = entry["offer"]
	assert_eq(int(offer["utility"]), desire - 10, "the published break price")
	# The band leaves no slack for a dearer cut: the break is the best peaceful
	# order, not merely a legal one.
	for candidate: Dictionary in offer["candidates"]:
		if not bool(candidate.get("ok", false)):
			continue
		if String(candidate["kind"]) == AiDiplomacyOffers.KIND_BREAK_NAP:
			continue
		assert_true(
			int(candidate["utility"]) < int(offer["utility"]),
			"%s at %d must not outrank the break at %d" % [
				String(candidate["kind"]), int(candidate["utility"]),
				int(offer["utility"]),
			],
		)

func test_after_the_break_the_next_turn_declares_the_war() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var first: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1, 1]), 1,
		ai_planner_AiFixture.context({0: 200, 1: 100})
	)
	assert_eq(String(first["action"]["kind"]), AiDiplomacyOffers.KIND_BREAK_NAP)
	assert_true(
		bool(
			AiTurnApply.apply_order(
				ai_planner_state, ai_planner_AiFixture.world([0, 1, 1]),
				ai_planner_ai_state, 0, first["action"]
			)["result"]["ok"]
		),
	)
	ai_planner_state.end_turn()
	# The lock has elapsed and the break's price dropped the standing below the
	# ceiling, so the war is declared on the next free order (issue #752).
	var second: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1, 1]), 2,
		ai_planner_AiFixture.context({0: 200, 1: 100})
	)
	assert_eq(String(second["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_eq(int(second["action"]["target"]), 1)


## The pact break waits behind the bank and then leads the order (issue #995):
## the pact the court signed as a peace lock is the wall its conquest must
## outgrow. While the court still banks, the break is not spent — the war could
## not follow it — and the trace names the gate. Once the host stands, the break
## takes the one order before any petty war beside it: the war ban lifts the next
## turn, and the banked host marches on the big holder behind it. A Great Power
## war that needs no break still leads, and a court with no gap to clear keeps
## the published order.
func test_the_pact_break_waits_for_the_bank_then_leads_the_order() -> void:
	_setup_ai_planner()
	var minor: int = FactionCatalog.minor_ids()[0]
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.ensure_relation(0, minor, 1)
	ai_planner_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var world: WorldMap = ai_planner_AiFixture.world([0, 1, minor])
	var context: Dictionary = ai_planner_AiFixture.context(
		{0: 200, 1: 100, minor: 50}, {0: 9}
	)
	# The published order: the petty war is legal and pre-empts the break
	# (the stall the issue measured — the pact wall).
	context["income"] = {}
	var published: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 1, context
	)
	assert_eq(
		String(published["action"].get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the published planner takes the legal petty war"
	)
	assert_eq(int(published["action"]["target"]), minor)
	# While the court banks, the break waits — the war could not follow it —
	# while the published petty declaration stands (the opening army storms the
	# minors it can already beat; the bank gates its own deferrable purchases,
	# not the war the score rides on).
	context["income"] = {
		"goal": AiIncome.GOAL_EARN, "reserve": 2200, "treasury": 600,
		"regiments": 1, "conquest_gap": true,
	}
	var banking: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 1, context
	)
	assert_ne(
		String(banking["action"].get("kind", "")), AiDiplomacyOffers.KIND_BREAK_NAP,
		"a banking court breaks no pact it cannot yet march on"
	)
	var blocked_break: String = ""
	for candidate: Dictionary in banking["candidates"]:
		if int(candidate["target"]) == 1:
			blocked_break = _offer_blocked_kind(
				candidate["offer"]["candidates"], AiDiplomacyOffers.KIND_BREAK_NAP
			)
	assert_true(
		blocked_break.begins_with("the court is banking for its army"),
		"the trace names the gate that holds the break, and the aim it waits on"
	)
	# The host stands: the break leads, and the petty war waits a turn.
	context["income"] = {
		"goal": AiIncome.GOAL_SPEND, "reserve": 500, "treasury": 5000,
		"regiments": 9, "conquest_gap": true,
	}
	var led: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 1, context
	)
	assert_eq(
		String(led["action"].get("kind", "")), AiDiplomacyOffers.KIND_BREAK_NAP,
		"the pact the court means to march on breaks before the petty war"
	)
	assert_eq(int(led["action"]["target"]), 1)
	# A court that has cleared the bar keeps the published order: the gap the
	# lever rides on is gone, and the petty war wins again.
	context["income"] = {
		"goal": AiIncome.GOAL_SPEND, "reserve": 500, "treasury": 5000,
		"regiments": 9, "conquest_gap": false,
	}
	var at_bar: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 1, context
	)
	assert_eq(
		String(at_bar["action"].get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"a court at the bar keeps the published planner"
	)


## Only the big holder's pact leads the order (issue #995): a Great Power war
## that needs no break still outranks it, and a Minor's pact is not the wall
## the conquest waits on — the petty war beside it wins as published. The lead
## is for the pact-bound Great Powers whose Old World land the bar counts.
func test_only_the_big_holders_pact_leads_the_order() -> void:
	_setup_ai_planner()
	var first_minor: int = FactionCatalog.minor_ids()[0]
	var second_minor: int = FactionCatalog.minor_ids()[1]
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var host: Dictionary = {
		"goal": AiIncome.GOAL_SPEND, "reserve": 500, "treasury": 5000,
		"regiments": 9, "conquest_gap": true,
	}
	# A legal Great Power war on an unpacted peer outranks the break: the
	# declaration needs no pact cleared first.
	ai_planner_state.ensure_relation(0, 3, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 1, 3])
	var context: Dictionary = ai_planner_AiFixture.context(
		{0: 200, 1: 100, 3: 100}, {0: 9}
	)
	context["income"] = host
	var great: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 1, context
	)
	assert_eq(
		String(great["action"].get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"a Great Power war that needs no break still leads"
	)
	assert_eq(int(great["action"]["target"]), 3)
	# A Minor's pact is not the wall the conquest waits on: the break on it
	# stays an ordinary offer, so the petty war beside it wins as published.
	var minor: int = first_minor
	var petty: int = second_minor
	ai_planner_state.ensure_relation(0, minor, 1)
	ai_planner_state.ensure_relation(0, petty, 1)
	ai_planner_state.set_overture(0, minor, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(minor, 0, DiplomacyCatalog.STAGE_NAP)
	var minor_world: WorldMap = ai_planner_AiFixture.world([0, minor, petty])
	var minor_context: Dictionary = ai_planner_AiFixture.context(
		{0: 200, minor: 50, petty: 50}, {0: 9}
	)
	minor_context["income"] = host
	var colonial: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, minor_world, 1,
		minor_context
	)
	assert_eq(
		String(colonial["action"].get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"a Minor's pact break never leads over the petty war"
	)
	assert_eq(int(colonial["action"]["target"]), petty)

func test_a_pacted_rival_with_an_alliance_breaks_the_pact_once() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).formal_alliance = true
	ai_planner_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1, 1]), 1,
		ai_planner_AiFixture.context({0: 200, 1: 100})
	)
	# One stroke clears both treaties, so the alliance-only break would waste
	# the turn (issue #752).
	assert_eq(String((plan["action"] as Dictionary).get("kind", "")), AiDiplomacyOffers.KIND_BREAK_NAP)
	assert_eq(
		String(_planner_offer_block(plan, 0, AiDiplomacyOffers.KIND_BREAK)),
		"the pact break clears the alliance too",
	)

func test_join_empire_is_scored_by_the_targets_answer() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 30000
	ai_diplomacy_offers_ai_state.economy_for(2).tech_unlocked["empire_building"] = true
	# The target holds four provinces (never nearly defeated) and outpowers the
	# offerer: the offer would only burn the turn (issue #752).
	var unlikely: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state,
		ai_diplomacy_offers_AiFixture.world([0, 2, 2, 3, 3, 3, 3]), 1, 3, 45,
		campaign__context({2: 20, 3: 40})
	)
	assert_eq(
		_offer_blocked_kind(unlikely, AiDiplomacyOffers.KIND_OVERTURE),
		"the crown would refuse absorption",
	)
	# A crown the offerer so far outpowers that standing alone is hopeless
	# accepts: the rung carries the absorption bonus (issue #752).
	var likely_context: Dictionary = campaign__context({2: 100, 3: 20})
	likely_context["treasury"] = {2: 30000}
	likely_context["tech"] = {2: {"empire_building": true}}
	var likely: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state,
		ai_diplomacy_offers_AiFixture.world([0, 2, 2, 3, 3, 3, 3]), 1, 3, 45,
		likely_context
	)
	assert_eq(
		_utility_of(likely, AiDiplomacyOffers.KIND_OVERTURE),
		55 + AiDiplomacyTreaties.JOIN_EMPIRE_ACCEPT_BONUS,
	)

func _planner_offer_block(plan: Dictionary, index: int, kind: String) -> String:
	var offer: Dictionary = plan["candidates"][index].get("offer", {})
	for entry: Dictionary in offer.get("candidates", []):
		if String(entry.get("kind", "")) == kind:
			return String(entry.get("blocked", ""))
	return ""

func test_friendly_relations_block_war_even_when_desire_is_high() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 70.0
	var purse: Dictionary = ai_planner_AiFixture.context({0: 400, 1: 100})
	purse["treasury"] = {0: 2000}
	var warm: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 1,
		purse
	)
	assert_eq(String(warm["candidates"][0]["blocked"]), "relations too warm")
	# The standing earns its next treaty instead of the war (issue #750).
	assert_eq(
		String((warm["action"] as Dictionary).get("kind", "")),
		AiDiplomacyOffers.KIND_OVERTURE,
		"the court works for the chain the standing earns"
	)
	assert_eq(String(warm["action"].get("stage", "")), DiplomacyCatalog.STAGE_CONSULATE)
	# With the pact standing the pair locks: the war is banned and the Allied
	# band takes the formal alliance (wiki: diplomacy § Alliances; issue #752).
	ai_planner_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	ai_planner_state.relation(0, 1).score = 80.0
	var pacted: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 1,
		ai_planner_AiFixture.context({0: 400, 1: 100})
	)
	assert_true(
		String(pacted["candidates"][0]["blocked"]).contains("non-aggression pact"),
		String(pacted["candidates"][0]["blocked"]),
	)
	assert_eq(
		String((pacted["action"] as Dictionary).get("kind", "")),
		AiDiplomacyOffers.KIND_ALLIANCE,
		"the court works for the treaty the standing already earns"
	)

func test_war_cooldown_blocks_the_pair_for_four_turns() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_ai_state.note_war(0, 1, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 200, 1: 100})
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var cooling: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_true((cooling["action"] as Dictionary).is_empty())
	assert_eq(String(cooling["candidates"][0]["blocked"]), "war cooldown")
	var ready: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 5, context)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)

func test_war_desire_below_the_minimum_blocks_war() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 45.0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 1,
		ai_planner_AiFixture.context({0: 84, 1: 100})
	)
	assert_true((plan["action"] as Dictionary).is_empty())
	assert_eq(String(plan["candidates"][0]["blocked"]), "war desire too low")

func test_peace_is_offered_when_the_war_stops_being_worth_it() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 2, context
	)
	assert_eq(String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(plan["action"]["target"]), 1)

## The other half of the exchange: a court still wants the war it declared, so
## the defender's white peace is refused and the war reaches Movement (wiki:
## diplomacy § Planner selection; hidden-agendas — a warmonger keeps the war
## alive; DR-20261111-27). The observer run showed the opposite: every rival war
## was dissolved in the phase it was declared.
func test_a_warmonger_refuses_the_peace_offered_in_the_phase_it_declared() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(1, 2, 1)
	ai_planner_state.relation(1, 2).score = 35.0
	var war: Dictionary = DiplomacyRules.declare_war(ai_planner_state, 1, 2)
	assert_true(bool(war["ok"]), "the declaration stands")
	ai_planner_ai_state.agendas[1] = AiAgenda.WARMONGER
	ai_planner_ai_state.agendas[2] = AiAgenda.ISOLATIONIST
	var result: Dictionary = AiTurn.run(
		ai_planner_state,
		ai_planner_AiFixture.world([1, 1, 1, 1, 2]),
		ai_planner_ai_state,
		1,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _campaign_record_for(result["trace"], 2)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(
		ai_planner_state.relation(1, 2).at_war,
		"the war it declared still stands after the defender's offer"
	)
	assert_true(String(record["message"]).contains("refuses a white peace"))
	assert_true(
		ai_planner_ai_state.peace_on_cooldown(2, 1, 2, 3),
		"the refusal starts the pair's peace-offer cooldown"
	)

## A refused white peace is not put again the next turn: the pair waits out the
## cooldown (wiki: diplomacy § Planner selection — either answer starts it, so a
## court does not ask again every turn; DR-20261109-07).
func test_a_refused_peace_waits_out_the_pair_cooldown() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(1, 2, 1)
	ai_planner_state.relation(1, 2).score = 35.0
	DiplomacyRules.declare_war(ai_planner_state, 1, 2)
	ai_planner_ai_state.agendas[1] = AiAgenda.WARMONGER
	ai_planner_ai_state.agendas[2] = AiAgenda.ISOLATIONIST
	var world: WorldMap = ai_planner_AiFixture.world([1, 1, 1, 1, 2])
	AiTurn.run(
		ai_planner_state, world, ai_planner_ai_state, 1, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var cooling: Dictionary = AiTurn.run(
		ai_planner_state, world, ai_planner_ai_state, 2, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var cooling_record: Dictionary = _campaign_record_for(cooling["trace"], 2)
	assert_true(
		cooling_record["action"].is_empty(),
		"a refused peace is not offered again the next turn"
	)
	assert_eq(
		_campaign_blocked(cooling_record, 1), "peace cooldown, refused 1× (6 turns)",
		"the trace explains the wait, and the refusal doubled it (DR-20261115-01)"
	)
	var ready: Dictionary = AiTurn.run(
		ai_planner_state, world, ai_planner_ai_state, 7, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var ready_record: Dictionary = _campaign_record_for(ready["trace"], 2)
	assert_eq(String(ready_record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(ai_planner_state.relation(1, 2).at_war, "the warmonger still refuses")

## The trace row one court recorded for its target ("{}" when it did nothing).
func _campaign_record_for(trace: Array, faction: int) -> Dictionary:
	for record: Dictionary in trace:
		if int(record["faction"]) == faction:
			return record
	return {}

## The reason the planner recorded against one target ("" when it was legal).
func _campaign_blocked(record: Dictionary, target: int) -> String:
	for row: Dictionary in record.get("candidates", []):
		if int(row.get("target", -1)) == target:
			return String(row.get("blocked", ""))
	return ""

func test_peace_with_the_human_is_proposed_and_waits_for_the_player() -> void:
	_setup_ai_planner()
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(ai_planner_state, 2, 0)
	var context: Dictionary = ai_planner_AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 2, context
	)
	var action: Dictionary = plan["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(action["target"]), 0)
	assert_true(bool(action.get("propose", false)), "the human court answers the offer")
	assert_true(ai_planner_state.relation(0, 2).at_war, "nothing is signed before the answer")

func test_a_refused_peace_waits_the_peace_cooldown() -> void:
	_setup_ai_planner()
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(ai_planner_state, 2, 0)
	ai_planner_ai_state.note_peace(2, 0, 2)
	var context: Dictionary = ai_planner_AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var cooling: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 3, context
	)
	assert_true((cooling["action"] as Dictionary).is_empty())
	assert_eq(String(cooling["candidates"][0]["blocked"]), "peace cooldown")
	var ready: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 5, context
	)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)

func test_a_refused_peace_widens_the_wait() -> void:
	_setup_ai_planner()
	# A refusal is information: after one no the pair waits twice the published
	# base clock, so a court is not asking the same question every third turn
	# (wiki: diplomacy § Cooldowns; DR-20261115-01). Base 3, so 6 after one.
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(ai_planner_state, 2, 0)
	ai_planner_ai_state.note_peace(2, 0, 2, false)
	assert_eq(ai_planner_ai_state.peace_refusals_for(2, 0), 1, "the no is remembered")
	var context: Dictionary = ai_planner_AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var waiting: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 6, context
	)
	assert_true((waiting["action"] as Dictionary).is_empty(), "the widened wait holds")
	assert_eq(
		String(waiting["candidates"][0]["blocked"]),
		"peace cooldown, refused 1× (6 turns)"
	)
	var ready: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 8, context
	)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)

func test_the_refusal_wait_is_capped() -> void:
	_setup_ai_planner()
	# Six refusals double the base clock out to 96 turns; the registry caps the
	# wait at 24 so a court at war is still asking within a generation
	# (DR-20261115-01).
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(ai_planner_state, 2, 0)
	for turn in [2, 3, 4, 5, 6, 7]:
		ai_planner_ai_state.note_peace(2, 0, turn, false)
	assert_eq(ai_planner_ai_state.peace_refusals_for(2, 0), 6)
	var context: Dictionary = ai_planner_AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var waiting: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 30, context
	)
	assert_eq(
		String(waiting["candidates"][0]["blocked"]),
		"peace cooldown, refused 6× (24 turns)"
	)
	var ready: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 31, context
	)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)

func test_a_signed_peace_and_a_new_war_clear_the_refusal_book() -> void:
	_setup_ai_planner()
	# The war is over, so the next war's first ask waits the published base
	# clock rather than the last war's doubled wait (DR-20261115-01).
	ai_planner_ai_state.note_peace(2, 0, 2, false)
	ai_planner_ai_state.note_peace(2, 0, 4, false)
	assert_eq(ai_planner_ai_state.peace_refusals_for(2, 0), 2)
	ai_planner_ai_state.note_truce(2, 0, 9)
	assert_eq(ai_planner_ai_state.peace_refusals_for(2, 0), 0, "the peace spent the refusals")
	ai_planner_ai_state.note_peace(2, 0, 12, false)
	ai_planner_ai_state.note_war(2, 0, 20)
	assert_eq(
		ai_planner_ai_state.peace_refusals_for(2, 0), 0,
		"a new war is a new question"
	)

func test_a_recent_war_declaration_does_not_silence_a_peace_offer() -> void:
	_setup_ai_planner()
	# The 4-turn war cooldown gates another Declare War on that pair, never the
	# peace leg of the same pair (wiki: diplomacy § Configurable Values —
	# "Applies to AI-initiated Declare War re-attempts"; DR-20261108-01).
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	ai_planner_ai_state.note_war(0, 1, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 2, context
	)
	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"a war that stopped being worth waging still offers peace after declaring"
	)
	assert_eq(int((plan["action"] as Dictionary).get("target", -1)), 1)

func test_war_goal_clamps_to_the_target_province_count() -> void:
	_setup_ai_planner()
	assert_eq(AiDiplomacyGates.desired_territory(75, 5), 3)
	assert_eq(AiDiplomacyGates.desired_territory(75, 2), 2)
	assert_eq(AiDiplomacyGates.desired_territory(12, 3), 1)
	assert_eq(AiDiplomacyGates.desired_territory(100, 0), 1)

func test_a_peacemaker_offers_peace_where_a_plain_court_fights_on() -> void:
	_setup_ai_planner()
	# Same war, same standing: the dove's peace bar sits 15 higher, so a war it
	# no longer means is put to its enemy a turn earlier (wiki: hidden-agendas —
	# peacemaker early peace).
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	ai_planner_state.relation(0, 1).score = 40.0
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var plain: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_eq(String(plain["candidates"][0]["blocked"]), "war still worth waging")
	var dove: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.PEACEMAKER)
	var peace: Dictionary = AiDiplomacyPlanner.decide(dove, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_eq(String(peace["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(peace["action"]["target"]), 1)

func test_a_warmonger_keeps_a_war_a_plain_court_would_end() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	ai_planner_state.relation(0, 1).score = 60.0
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var plain: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_eq(String(plain["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	var hawk: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.WARMONGER)
	var keep: Dictionary = AiDiplomacyPlanner.decide(hawk, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_true((keep["action"] as Dictionary).is_empty(), "the war is still worth waging")
	assert_eq(String(keep["candidates"][0]["blocked"]), "war still worth waging")

func test_a_backstabber_breaks_an_alliance_it_would_otherwise_keep() -> void:
	_setup_ai_planner()
	# A formal ally that is weaker than the court: the treaty still serves an
	# honest court, but the backstabber's desire against its own ally clears the
	# break bar (wiki: hidden-agendas — hits allies when weak).
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 70.0
	ai_planner_state.relation(0, 1).formal_alliance = true
	var context: Dictionary = ai_planner_AiFixture.context({0: 135, 1: 100})
	context["player"] = 5
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var honest: Dictionary = AiDiplomacyDesire.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)
	assert_false((honest["factors"] as Dictionary).has("betrayal"))
	assert_eq(int(honest["score"]), 40, "50 + 30 strong - 40 allied")
	var snake: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.BACKSTABBER)
	var snake_desire: Dictionary = AiDiplomacyDesire.war_desire(snake, ai_planner_state, world, 0, 1, context)
	assert_eq(int(snake_desire["factors"]["betrayal"]), 25)
	var keep: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 1, context)
	assert_true(
		String((keep["action"] as Dictionary).get("kind", "")) != AiDiplomacyOffers.KIND_BREAK,
		"an honest court keeps the treaty its standing earned"
	)
	var betray: Dictionary = AiDiplomacyPlanner.decide(snake, ai_planner_state, ai_planner_ai_state, world, 1, context)
	assert_eq(String(betray["action"]["kind"]), AiDiplomacyOffers.KIND_BREAK)
	assert_true(ai_planner_state.relation(0, 1).formal_alliance, "the planner only plans the break")

func test_an_envious_court_resents_a_human_crown_that_pulled_ahead() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 2, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 135, 2: 100})
	context["player"] = 0
	var world: WorldMap = ai_planner_AiFixture.world([0, 2, 2])
	var plain_config: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	var plain: Dictionary = AiDiplomacyDesire.war_desire(plain_config, ai_planner_state, world, 2, 0, context)
	assert_false((plain["factors"] as Dictionary).has("rival"))
	var jealous: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ENVY)
	var envy: Dictionary = AiDiplomacyDesire.war_desire(jealous, ai_planner_state, world, 2, 0, context)
	assert_eq(int(envy["factors"]["rival"]), 20)
	assert_eq(
		int(envy["score"]) - int(plain["score"]), 25,
		"20 rival_bias + 5 war_bias"
	)
	assert_true(int(envy["score"]) > int(plain["score"]), "the lead is felt")

func test_an_envious_court_does_not_resent_a_crown_that_trails_it() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 2, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 2: 135})
	context["player"] = 0
	var jealous: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ENVY)
	var desire: Dictionary = AiDiplomacyDesire.war_desire(
		jealous, ai_planner_state, ai_planner_AiFixture.world([0, 2, 2]), 2, 0, context
	)
	assert_false((desire["factors"] as Dictionary).has("rival"), "envy is not a grudge")
	# Nor is it a grudge against another rival: the pull is for the human crown.
	var other: Dictionary = AiDiplomacyDesire.war_desire(
		jealous, ai_planner_state, ai_planner_AiFixture.world([0, 1, 2]), 2, 1, context
	)
	assert_false((other["factors"] as Dictionary).has("rival"))

# --- from test_ai_war_memory.gd ---
## War memory: an unfought war wears the attacker down.
## War memory (wiki: diplomacy § Cooldowns, § War goals and in-war reassessment;
## issue #475): a war that takes nothing wears the attacker down, and a peace
## that ends an unfought war holds the pair below the declaration bar past the
## 4-turn cooldown — so a crown stops re-declaring on the same enemy forever.

const campaign_AiFixture = preload("res://tests/ai_fixture.gd")

const WAR_OWNER: int = 0
const WAR_RIVAL: int = 1
const WAR_TRIBE: int = 11
const WAR_SEED: int = 1500


func _war_config(faction: int = WAR_RIVAL, agenda: String = AiAgenda.WARMONGER) -> AiConfig:
	return AiConfig.build(faction, WAR_SEED, AiProfile.NORMAL, agenda)


func _war_court() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(WAR_OWNER, WAR_RIVAL, 1)
	return state


# --- the arithmetic ----------------------------------------------------------


func test_a_war_inside_the_grace_carries_no_weariness() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 10)
	var grace: int = config.parameter("diplomacy.war_weariness_grace")

	assert_eq(AiWarMemory.weariness(config, ai_state, 10, WAR_RIVAL, WAR_OWNER), 0)
	assert_eq(AiWarMemory.weariness(config, ai_state, 10 + grace, WAR_RIVAL, WAR_OWNER), 0)
	assert_eq(
		AiWarMemory.weariness(config, ai_state, 10 + grace + 1, WAR_RIVAL, WAR_OWNER),
		config.parameter("diplomacy.war_weariness"),
		"the first turn beyond the grace costs one step"
	)


func test_weariness_grows_turn_by_turn_and_stops_at_the_scale() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 0)
	var grace: int = config.parameter("diplomacy.war_weariness_grace")
	var step: int = config.parameter("diplomacy.war_weariness")

	assert_eq(AiWarMemory.weariness(config, ai_state, grace + 3, WAR_RIVAL, WAR_OWNER), step * 3)
	assert_eq(AiWarMemory.weariness(config, ai_state, 400, WAR_RIVAL, WAR_OWNER), 100, "capped at the scale")


func test_a_truce_holds_the_pair_and_then_expires() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 10)  # a two-turn war: unfought
	ai_state.note_truce(WAR_RIVAL, WAR_OWNER, 12)
	var turns: int = config.parameter("diplomacy.truce_turns")

	assert_eq(
		AiWarMemory.truce(config, ai_state, 12, WAR_RIVAL, WAR_OWNER),
		config.parameter("diplomacy.truce_penalty")
	)
	assert_eq(AiWarMemory.truce(config, ai_state, 12 + turns - 1, WAR_RIVAL, WAR_OWNER),
		config.parameter("diplomacy.truce_penalty"))
	assert_eq(AiWarMemory.truce(config, ai_state, 12 + turns, WAR_RIVAL, WAR_OWNER), 0)


func test_the_penalty_reads_the_right_memory_for_the_footing() -> void:
	var config: AiConfig = _war_config()
	var at_war := AiState.new()
	at_war.note_war(WAR_RIVAL, WAR_OWNER, 0)
	var peaceful := AiState.new()
	peaceful.note_war(WAR_RIVAL, WAR_OWNER, 0)
	peaceful.note_truce(WAR_RIVAL, WAR_OWNER, 1)
	var fought: int = config.parameter("diplomacy.war_weariness_grace") + 2
	var later: int = config.parameter("diplomacy.truce_turns") + 1

	assert_true(
		AiWarMemory.penalty(config, at_war, fought, WAR_RIVAL, WAR_OWNER, true) > 0,
		"at war the court reads its weariness"
	)
	assert_eq(
		AiWarMemory.penalty(config, peaceful, 1, WAR_RIVAL, WAR_OWNER, false),
		config.parameter("diplomacy.truce_penalty"),
		"at peace inside the truce an unfought war left it carries the truce"
	)
	assert_eq(
		AiWarMemory.penalty(config, peaceful, later, WAR_RIVAL, WAR_OWNER, false), 0,
		"past the truce a peace carries nothing"
	)
	assert_eq(AiWarMemory.penalty(null, at_war, fought, WAR_RIVAL, WAR_OWNER, true), 0)
	assert_eq(AiWarMemory.penalty(config, null, fought, WAR_RIVAL, WAR_OWNER, true), 0)
	# Each reading has its own empty guard, so a caller may ask it directly.
	assert_eq(AiWarMemory.weariness(null, at_war, fought, WAR_RIVAL, WAR_OWNER), 0)
	assert_eq(AiWarMemory.truce(null, peaceful, 1, WAR_RIVAL, WAR_OWNER), 0)


# --- the planner -------------------------------------------------------------


## One decision by the warmonger against a relation at war. The declaration is
## recorded so the weariness clock has a start; `attack` notes the turn the
## court last attacked the enemy's ground (issue #999).
func _decide(at_war: bool, turn: int, truce: int = -1, power: int = 10, attack: int = -1) -> Dictionary:
	var state: DiplomacyState = _war_court()
	var ai_state := AiState.new()
	ai_state.agendas[WAR_RIVAL] = AiAgenda.WARMONGER
	if at_war:
		assert_true(bool(DiplomacyRules.declare_war(state, WAR_RIVAL, WAR_OWNER)["ok"]))
		ai_state.note_war(WAR_RIVAL, WAR_OWNER, 1)
	if attack >= 0:
		AiWarMemory.note_attack(ai_state, WAR_RIVAL, WAR_OWNER, attack)
	if truce >= 0:
		ai_state.note_truce(WAR_RIVAL, WAR_OWNER, truce)
	return AiDiplomacyPlanner.decide(
		_war_config(), state, ai_state, campaign_AiFixture.world([WAR_OWNER, WAR_RIVAL, WAR_RIVAL, WAR_RIVAL]),
		turn, {
			"regiments": {}, "ships": {}, "player": WAR_OWNER,
			"power": {WAR_RIVAL: power, WAR_OWNER: 10},
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
	# The war it is winning is the war it wants: no weariness, no white peace —
	# while it is prosecuting that war (issue #999).
	var plan: Dictionary = _decide(true, 200, -1, 90, 199)
	assert_true(
		String(plan["action"].get("kind", "")) != AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"a stronger court prosecutes its war"
	)


func test_a_stronger_court_that_prosecutes_nothing_tires_like_any_other() -> void:
	# Outmatching a victim is not itself a benefit: a stronger court stuck in a
	# war that takes nothing reads the pointless erosion and puts peace to it
	# (issue #999).
	var plan: Dictionary = _decide(true, 200, -1, 90)
	assert_eq(
		String(plan["action"].get("kind", "")), AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"a yieldless war ends even for the stronger court"
	)
	var candidate: Dictionary = (plan["candidates"] as Array)[0]
	assert_true(
		int(candidate["factors"].get("pointless", 0)) < 0,
		"the trace names the pointless war"
	)


func test_a_pointless_war_turns_to_peace_a_few_turns_after_the_read() -> void:
	var config: AiConfig = _war_config()
	var grace: int = config.parameter("diplomacy.war_weariness_grace")
	var window: int = config.parameter("diplomacy.pointless_window")
	# Inside the grace the warmonger keeps the war it declared.
	var fresh: Dictionary = _decide(true, grace)
	assert_true(
		String(fresh["action"].get("kind", "")) != AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"a war inside the grace stands"
	)
	# A handful of quiet turns after the read fires, the peace is composed.
	var ending: Dictionary = _decide(true, grace + window + 4)
	assert_eq(
		String(ending["action"].get("kind", "")), AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"the pointless war ends within a few turns of the read firing"
	)


func test_a_war_that_takes_nothing_erodes_past_the_window() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 0)
	var grace: int = config.parameter("diplomacy.war_weariness_grace")
	var window: int = config.parameter("diplomacy.pointless_window")
	var step: int = config.parameter("diplomacy.pointless_step")

	assert_eq(
		AiWarMemory.pointless(config, ai_state, grace + window, WAR_RIVAL, WAR_OWNER), 0,
		"the window is quiet before the read fires"
	)
	assert_eq(
		AiWarMemory.pointless(config, ai_state, grace + window + 1, WAR_RIVAL, WAR_OWNER),
		step,
		"the first quiet turn past the window costs one step"
	)
	assert_eq(
		AiWarMemory.pointless(config, ai_state, grace + window + 3, WAR_RIVAL, WAR_OWNER),
		step * 3
	)
	assert_eq(
		AiWarMemory.pointless(config, ai_state, 400, WAR_RIVAL, WAR_OWNER), 100,
		"capped at the scale"
	)
	assert_eq(
		AiWarMemory.pointless(config, ai_state, grace, WAR_RIVAL, WAR_OWNER), 0,
		"the grace is the march's, not the window's"
	)


func test_a_prosecuted_war_carries_no_pointless_erosion() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 0)
	var grace: int = config.parameter("diplomacy.war_weariness_grace")
	var window: int = config.parameter("diplomacy.pointless_window")
	var step: int = config.parameter("diplomacy.pointless_step")
	var attack: int = grace + window + 4
	AiWarMemory.note_attack(ai_state, WAR_RIVAL, WAR_OWNER, attack)

	assert_true(
		AiWarMemory.prosecuted(config, ai_state, attack, WAR_RIVAL, WAR_OWNER),
		"an attack inside the window is prosecution"
	)
	assert_eq(
		AiWarMemory.pointless(config, ai_state, attack + 1, WAR_RIVAL, WAR_OWNER), 0,
		"a prosecuted war yields something"
	)
	assert_eq(
		AiWarMemory.pointless(config, ai_state, attack + window + 1, WAR_RIVAL, WAR_OWNER),
		step,
		"the clock restarts at the attack"
	)


## The front read the market's speculative top-up honors (issue #995): a war
## inside its grace or under attack is a front, a war past both with no attack
## holds none, and a caller with no state to read keeps the published footing.
## Colonial wars never held the footing, so they hold none here either.
func test_a_phoney_war_holds_no_front_the_market_honors() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 0)
	var state: DiplomacyState = _war_court()
	assert_true(bool(DiplomacyRules.declare_war(state, WAR_RIVAL, WAR_OWNER)["ok"]))
	var grace: int = config.parameter("diplomacy.war_weariness_grace")
	var window: int = config.parameter("diplomacy.pointless_window")

	assert_true(
		AiWarMemory.holds_front(config, ai_state, state, grace, WAR_RIVAL),
		"a war inside its grace is a front the court may still march"
	)
	var attack: int = grace + window
	AiWarMemory.note_attack(ai_state, WAR_RIVAL, WAR_OWNER, attack)
	assert_true(
		AiWarMemory.holds_front(config, ai_state, state, attack, WAR_RIVAL),
		"a war attacked inside the window is a front"
	)
	assert_false(
		AiWarMemory.holds_front(
			config, ai_state, state, attack + window + 1, WAR_RIVAL
		),
		"a war past its window with no attack holds no coin back"
	)
	assert_true(
		AiWarMemory.holds_front(config, ai_state, null, 400, WAR_RIVAL),
		"a caller with no state keeps the published footing"
	)
	# A colonial war never held the footing, so it holds no market either.
	var colonial: DiplomacyState = DiplomacyState.new()
	colonial.reset(1)
	colonial.ensure_relation(WAR_RIVAL, WAR_TRIBE, 1)
	colonial.relation(WAR_RIVAL, WAR_TRIBE).at_war = true
	assert_false(
		AiWarMemory.holds_front(config, ai_state, colonial, 400, WAR_RIVAL),
		"a war on a Tribe is colonial business, never a front"
	)
	assert_false(
		AiWarMemory.prosecuted(config, ai_state, attack, WAR_OWNER, WAR_RIVAL),
		"the enemy's attacks are not this court's benefit"
	)


func test_the_attack_note_resets_with_a_new_war_and_rides_a_save() -> void:
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 10)
	AiWarMemory.note_attack(ai_state, WAR_RIVAL, WAR_OWNER, 14)
	assert_eq(AiWarMemory.attack_turn(ai_state, WAR_RIVAL, WAR_OWNER), 14)
	var kept: AiState = AiState.from_dict(ai_state.to_dict())
	assert_eq(
		AiWarMemory.attack_turn(kept, WAR_RIVAL, WAR_OWNER), 14,
		"the prosecution clock rides the save"
	)
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 40)
	assert_eq(
		AiWarMemory.attack_turn(ai_state, WAR_RIVAL, WAR_OWNER), -1,
		"a fresh war starts the prosecution clock again"
	)


func test_a_truce_keeps_the_pair_below_the_declaration_bar() -> void:
	var barred: Dictionary = _decide(false, 8, 4)
	assert_true(
		String(barred["action"].get("kind", "")) != AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the 4-turn cooldown alone no longer re-opens the war"
	)
	var candidate: Dictionary = (barred["candidates"] as Array)[0]
	assert_eq(
		String(candidate["blocked"]), "the pair's truce holds: no new war yet",
		"the truce bars the re-declaration outright (issue #975) before desire is read"
	)
	assert_eq(
		int(candidate["factors"].get("memory", 0)),
		-_war_config().parameter("diplomacy.truce_penalty"),
		"the trace names the truce"
	)


func test_the_declaration_returns_once_the_truce_expires() -> void:
	var turn: int = 4 + _war_config().parameter("diplomacy.truce_turns")
	var freed: Dictionary = _decide(false, turn, 4, 90)
	assert_eq(
		String(freed["action"].get("kind", "")), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the war may be declared again after the truce"
	)


func test_a_peace_concludes_and_records_the_truce() -> void:
	# The warmonger is worn past its bar, so the target takes the white peace the
	# planning pass offers; the pair then carries a truce.
	var state: DiplomacyState = _war_court()
	state.human_faction = -1
	assert_true(bool(DiplomacyRules.declare_war(state, WAR_RIVAL, WAR_OWNER)["ok"]))
	var ai_state := AiState.new()
	ai_state.agendas[WAR_RIVAL] = AiAgenda.WARMONGER
	ai_state.agendas[WAR_OWNER] = AiAgenda.WARMONGER
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 1)
	var run: Dictionary = AiTurn.run(
		state, campaign_AiFixture.world([WAR_OWNER, WAR_RIVAL]), ai_state,
		200, 4, WAR_SEED, {"regiments": {}, "ships": {}}
	)

	assert_true(
		ai_state.last_truce_turn.has(AiState.pair_key(WAR_OWNER, WAR_RIVAL)),
		"a concluded peace starts the truce"
	)
	assert_false((state.relation(WAR_RIVAL, WAR_OWNER) as DiplomacyRelation).at_war)
	assert_true(run.has("trace"))


func test_a_peace_offered_to_the_human_starts_the_truce_too() -> void:
	# The worn warmonger puts the white peace to the human court instead of
	# signing it: the offer alone ends its appetite, so a refusal does not hand
	# the court a fresh war at the cooldown (issue #475).
	var state: DiplomacyState = _war_court()
	state.human_faction = WAR_OWNER
	assert_true(bool(DiplomacyRules.declare_war(state, WAR_RIVAL, WAR_OWNER)["ok"]))
	var ai_state := AiState.new()
	ai_state.agendas[WAR_RIVAL] = AiAgenda.WARMONGER
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 1)
	AiTurn.run(
		state, campaign_AiFixture.world([WAR_OWNER, WAR_RIVAL]), ai_state,
		200, 4, WAR_SEED, {"regiments": {}, "ships": {}}
	)

	assert_true(
		ai_state.last_truce_turn.has(AiState.pair_key(WAR_OWNER, WAR_RIVAL)),
		"the offer starts the truce"
	)


func test_a_colonial_war_carries_the_truce() -> void:
	# A war on a Minor Nation or Tribe is still a war: the peace that ended an
	# unfought one holds the pair below the declaration bar (issue #511).
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	var minor: int = 6
	ai_state.note_war(WAR_RIVAL, minor, 0)
	ai_state.note_truce(WAR_RIVAL, minor, 4)

	assert_eq(
		AiWarMemory.truce(config, ai_state, 5, WAR_RIVAL, minor),
		config.parameter("diplomacy.truce_penalty"),
		"a colonial peace leaves the same truce a crown one does"
	)
	assert_eq(
		AiWarMemory.truce(config, ai_state, 4 + config.parameter("diplomacy.truce_turns"), WAR_RIVAL, minor),
		0,
		"and it expires on the same clock"
	)


func test_a_colonial_war_wears_the_attacker_down() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	var tribe: int = 11
	ai_state.note_war(WAR_RIVAL, tribe, 0)
	var grace: int = config.parameter("diplomacy.war_weariness_grace")
	var step: int = config.parameter("diplomacy.war_weariness")

	assert_eq(AiWarMemory.weariness(config, ai_state, grace, WAR_RIVAL, tribe), 0)
	assert_eq(
		AiWarMemory.weariness(config, ai_state, grace + 2, WAR_RIVAL, tribe), step * 2,
		"a colonial war that takes nothing tires the court too"
	)


## One decision by the warmonger against a Tribe. `power` is the court's own
## reading of the balance against it.
func _decide_colonial(
	at_war: bool, turn: int, truce: int = -1, power: int = 10
) -> Dictionary:
	var state: DiplomacyState = _war_court()
	state.ensure_relation(WAR_RIVAL, WAR_TRIBE, 1)
	var ai_state := AiState.new()
	ai_state.agendas[WAR_RIVAL] = AiAgenda.WARMONGER
	if at_war:
		assert_true(bool(DiplomacyRules.declare_war(state, WAR_RIVAL, WAR_TRIBE)["ok"]))
		ai_state.note_war(WAR_RIVAL, WAR_TRIBE, 1)
	if truce >= 0:
		ai_state.note_truce(WAR_RIVAL, WAR_TRIBE, truce)
	return AiDiplomacyPlanner.decide(
		_war_config(), state, ai_state,
		campaign_AiFixture.world([WAR_OWNER, WAR_RIVAL, WAR_RIVAL, WAR_RIVAL, WAR_TRIBE]), turn, {
			"regiments": {}, "ships": {}, "player": WAR_OWNER,
			"power": {WAR_RIVAL: power, WAR_TRIBE: 1},
		}
	)


func campaign__candidate(plan: Dictionary, target: int) -> Dictionary:
	for raw: Variant in plan.get("candidates", []):
		var entry: Dictionary = raw
		if int(entry.get("target", -1)) == target:
			return entry
	return {}


func test_a_colonial_truce_keeps_the_tribe_below_the_declaration_bar() -> void:
	# The carousel #511 measured: declare, white peace in the same phase, and
	# re-declare at the 4-turn cooldown. The truce now holds the pair outright.
	var barred: Dictionary = _decide_colonial(false, 8, 4)
	var entry: Dictionary = campaign__candidate(barred, WAR_TRIBE)

	assert_eq(
		String(entry.get("blocked", "")), "the pair's truce holds: no new war yet",
		"the truce bars the colonial re-declaration outright (issue #1140)"
	)
	assert_eq(
		int((entry.get("factors", {}) as Dictionary).get("memory", 0)),
		-_war_config().parameter("diplomacy.truce_penalty"),
		"the trace names the colonial truce"
	)


func test_a_court_that_outmatches_a_tribe_still_tires() -> void:
	# Strength against a Tribe is the precondition for a landing, not proof of
	# one, so the peer-only exemption does not cover a colonial war (#511).
	var plan: Dictionary = _decide_colonial(true, 200, -1, 90)
	var entry: Dictionary = campaign__candidate(plan, WAR_TRIBE)

	assert_eq(
		int((entry.get("factors", {}) as Dictionary).get("memory", 0)), -100,
		"a colonial war that takes nothing wears the court to the scale"
	)


func test_a_fought_war_leaves_no_truce() -> void:
	var config: AiConfig = _war_config()
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 4)
	ai_state.note_truce(WAR_RIVAL, WAR_OWNER, 20)  # a 16-turn war: prosecuted

	assert_eq(
		AiWarMemory.truce(config, ai_state, 21, WAR_RIVAL, WAR_OWNER), 0,
		"a war that was fought ends in a real settlement"
	)


func test_a_save_round_trips_the_truce() -> void:
	var ai_state := AiState.new()
	ai_state.note_war(WAR_RIVAL, WAR_OWNER, 16)
	ai_state.note_truce(WAR_RIVAL, WAR_OWNER, 17)
	var restored := AiState.from_dict(ai_state.to_dict())

	assert_eq(
		AiWarMemory.truce(_war_config(), restored, 18, WAR_RIVAL, WAR_OWNER),
		_war_config().parameter("diplomacy.truce_penalty")
	)

# ==== merged from test_ai_planner_rules.gd (one coverage boot; docs/testing.md § Speed rules) ====
## One boot for the rival planners: cargo, market, merchant, army reinforcement
## and the civilian work planners (wiki: civilian-units; docs/ai.md).

## Merged from test_ai_cargo, test_ai_market, test_ai_merchant,
## test_ai_army_reinforce, test_ai_builder_work, test_ai_engineer_work,
## test_ai_hospital_work, test_ai_town_roads, test_ai_civilian_dispatch,
## test_ai_objective_rules.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const planner_Fixture = preload("res://tests/civilian_fixture.gd")
const planner_AiFixture = preload("res://tests/ai_fixture.gd")
const ai_engineer_work_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const planner_Engineer = preload("res://scripts/ai/ai_engineer_work.gd")
const ai_civilian_dispatch_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const planner_Planner = preload("res://scripts/ai/ai_civilian_planner.gd")

const planner_OWNER: int = 1
const planner_CONFIG_FACTION: int = 1
const planner_GRAIN: Vector2i = Vector2i(3, 1)
const planner_IRON: Vector2i = Vector2i(2, 1)
const planner_AWAY: Vector2i = Vector2i(1, 1)
const planner_MINOR: int = 6
const ai_army_reinforce_OWNER: int = 2
const HUMAN: int = 1
const ai_builder_work_TOWN: Vector2i = Vector2i(0, 0)
const planner_TIMBER: Vector2i = Vector2i(1, 0)
const planner_TIMBER_FAR: Vector2i = Vector2i(2, 0)
const planner_SEAT: Vector2i = Vector2i(0, 0)
const planner_SEAT_ESTATE: Vector2i = Vector2i(1, 0)
const planner_SEAT_ESTATE_FAR: Vector2i = Vector2i(2, 0)
const ai_engineer_work_BARE: Vector2i = Vector2i(0, 0)
const ai_hospital_work_CAPITAL: Vector2i = Vector2i(0, 1)
const planner_OUTER_TOWN: Vector2i = Vector2i(4, 1)
const planner_CAPITAL_PROVINCE: int = 0
const planner_OUTER_PROVINCE: int = 1
const planner_TECH: Dictionary = {
	"organised_regiments": true,
	"modern_military_funding": true,
}
const ai_town_roads_CAPITAL: Vector2i = Vector2i(0, 1)
const ai_town_roads_TOWN: Vector2i = Vector2i(4, 1)
const ai_civilian_dispatch_BARE: Vector2i = Vector2i(0, 0)
const planner_RAIL_TECHS: Dictionary = {"early_steam_engine": true}

# --- test_ai_cargo ---

func planner__old_world() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0 if x < 4 else 1
			if x < 4:
				tiles.append(tile)
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var province := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), planner_OWNER, true
	)
	province.capital_tile = Vector2i(0, 0)
	province.port_tile = Vector2i(0, 1)
	province.coastal = true
	var harbour: Array[Vector2i] = [Vector2i(4, 0), Vector2i(4, 1)]
	var outport := ProvinceState.create(
		1, "Outport", harbour, Vector2(4.0, 0.5), harbour.size(), planner_OWNER, false
	)
	outport.port_tile = Vector2i(4, 1)
	outport.coastal = true
	model.provinces = [province, outport]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model

func planner__config() -> AiConfig:
	return AiConfig.build(planner_OWNER, 1500)

func planner__economy(treasury: int = 2500) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy

func planner__merchant(fleet_id: int, type_id: String = "carrack") -> FleetState:
	var hull_id: String = "hull_%d" % fleet_id
	return FleetState.at_sea(fleet_id, planner_OWNER, 0, [hull_id], {hull_id: type_id})

func test_planner_an_idle_merchant_squadron_is_walked_home_and_docks() -> void:
	var model: MapModel = planner__old_world()
	var fleet: FleetState = planner__merchant(1)
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1, "one idle merchant squadron is ordered home")
	assert_true(bool(routes[0]["dock"]), "the seat's harbour borders the zone")
	var moved: Dictionary = AiCargoPlanner.apply_route(model, fleet, routes[0])
	assert_true(bool(moved["ok"]))
	assert_true(fleet.is_in_port())
	assert_eq(fleet.province, 0, "it berths at the crown's seat")
	assert_eq(int(plan["holds"]), 0, "the holds did not count afloat")
	assert_eq(int(plan["projected"]), 3, "the projected berths count its cargo")

func test_planner_a_warship_is_never_a_cargo_route() -> void:
	var model: MapModel = planner__old_world()
	var sloop := FleetState.at_sea(2, planner_OWNER, 0, ["hull_2"], {"hull_2": "sloop"})
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(), model, [sloop], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty(), "no purse for a hull yet")

func test_planner_a_merchant_in_another_port_puts_to_sea_toward_the_seat() -> void:
	var model: MapModel = planner__old_world()
	var fleet := FleetState.in_port(5, planner_OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1)
	assert_true(not bool(routes[0]["dock"]), "the outport is not the seat")
	assert_eq(int(routes[0]["zone"]), 0, "it puts to sea into the seat's water")

func test_planner_hostile_water_holds_a_merchant_in_port() -> void:
	var model: MapModel = planner__old_world()
	var fleet := FleetState.in_port(5, planner_OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(), model, [fleet], 0, 5, {0: true}
	)
	assert_true((plan["routes"] as Array).is_empty(), "it waits for safer water")

func test_planner_berths_at_the_seat_already_cover_the_need() -> void:
	var model: MapModel = planner__old_world()
	var fluyte := FleetState.in_port(3, planner_OWNER, 0, ["hull_3"], {"hull_3": "fluyte"})
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(20000), model, [fluyte], 0, 4
	)
	assert_eq(int(plan["holds"]), 4, "a fluyte's four holds are home cargo")
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty())

func test_planner_a_shortfall_that_pays_lays_down_a_merchant_hull() -> void:
	var model: MapModel = planner__old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(20000), model, [], 0, 10
	)
	var launch: Dictionary = plan["launch"]
	assert_eq(String(launch.get("kind", "")), "launch")
	assert_eq(String(launch.get("type_id", "")), "carrack", "the only buildable hull")
	assert_eq(int(launch.get("cargo", 0)), 3)

func test_planner_the_better_merchant_wins_on_cargo_then_price() -> void:
	var model: MapModel = planner__old_world()
	var economy: PlayerEconomy = planner__economy(20000)
	economy.tech_unlocked["superior_hull_design"] = true
	var plan: Dictionary = AiCargoPlanner.plan(planner__config(), economy, model, [], 0, 10)
	assert_eq(
		String(plan["launch"].get("type_id", "")), "fluyte",
		"four holds for less money beats three"
	)

func test_planner_the_purse_floor_keeps_the_yard_shut() -> void:
	var model: MapModel = planner__old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(9000), model, [], 0, 10
	)
	assert_true((plan["launch"] as Dictionary).is_empty(), "£1,000 left is not enough")

func test_planner_a_squadron_carrying_an_expedition_keeps_its_course() -> void:
	var model: MapModel = planner__old_world()
	var fleet: FleetState = planner__merchant(4)
	fleet.embarked_army = 7
	var plan: Dictionary = AiCargoPlanner.plan(
		planner__config(), planner__economy(), model, [fleet], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())

func test_planner_missing_inputs_make_the_plan_empty() -> void:
	var model: MapModel = planner__old_world()
	assert_true((AiCargoPlanner.plan(null, planner__economy(), model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(planner__config(), null, model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(planner__config(), planner__economy(), null, [], 0, 5)["routes"] as Array).is_empty())
	assert_true(not bool(AiCargoPlanner.apply_route(model, null, {})["ok"]))

func planner__session(model: MapModel, fleets: Array[FleetState]) -> Dictionary:
	var play := PlaySession.new()
	play.map_seed = 1
	play.player_faction = 0
	var world := WorldMap.new()
	world.add_region(model)
	play.world = world
	var ships := ShipLayer.new()
	ships.player_faction = 0
	ships.regions.set_region(model.region_id, fleets)
	play.ship_layer = ships
	return {"play": play, "ships": ships, "model": model}

func test_planner_the_adapter_docks_a_rival_squadron_and_its_holds_count() -> void:
	var model: MapModel = planner__old_world()
	var fleet: FleetState = planner__merchant(1)
	var built: Dictionary = planner__session(model, [fleet])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = planner__economy()
	var report: Dictionary = MapPlayCargoAi.run(
		play, planner_OWNER, economy, {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_in_port())
	assert_eq(
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), planner_OWNER),
		3, "the docked hull's three holds now count"
	)
	(built["ships"] as Node).free()

func test_planner_the_adapter_puts_a_merchant_to_sea_for_the_crossing() -> void:
	var model: MapModel = planner__old_world()
	var fleet := FleetState.in_port(5, planner_OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var built: Dictionary = planner__session(model, [fleet])
	var play: PlaySession = built["play"]
	var report: Dictionary = MapPlayCargoAi.run(
		play, planner_OWNER, planner__economy(), {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_at_sea(), "the outport merchant puts to sea")
	assert_eq(fleet.sea_zone, 0)
	(built["ships"] as Node).free()

func test_planner_the_adapter_keeps_a_merchant_out_of_hostile_water() -> void:
	var model: MapModel = planner__old_world()
	var fleet := FleetState.in_port(5, planner_OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var player := FleetState.at_sea(9, 0, 0, ["hull_9"], {"hull_9": "carrack"})
	var built: Dictionary = planner__session(model, [fleet, player])
	var play: PlaySession = built["play"]
	var state := DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(planner_OWNER, 0, 1)
	assert_true(bool(DiplomacyRules.declare_war(state, planner_OWNER, 0)["ok"]))
	play.diplomacy = state
	var report: Dictionary = MapPlayCargoAi.run(
		play, planner_OWNER, planner__economy(), {"used": 0, "left_total": 2}
	)
	assert_true((report["routes"] as Array).is_empty())
	assert_true(fleet.is_in_port(), "the merchant never enters the hostile zone")
	(built["ships"] as Node).free()

func test_planner_the_adapter_founds_a_slip_when_no_squadron_is_in_port() -> void:
	var model: MapModel = planner__old_world()
	var built: Dictionary = planner__session(model, [])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = planner__economy(20000)
	var report: Dictionary = MapPlayCargoAi.run(
		play, planner_OWNER, economy, {"used": 0, "left_total": 8}
	)
	var launch: Dictionary = report["launch"]
	assert_eq(String(launch.get("type_id", "")), "carrack")
	assert_true(bool(launch.get("founded", false)), "the yard founds the home squadron")
	var roster: Array = play.ship_layer.regions.value(model.region_id, [])
	assert_eq(roster.size(), 1)
	var fleet: FleetState = roster[0]
	assert_true(fleet.is_in_port() and fleet.province == 0)
	assert_eq(economy.treasury, 12000, "the yard took its published price")
	(built["ships"] as Node).free()

# --- test_ai_market ---

func _ai_market_config() -> AiConfig:
	return AiConfig.build(planner_CONFIG_FACTION, 1500)

func _ai_market_economy(stock: Dictionary, treasury: int = 5000) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.stockpile = stock.duplicate()
	return economy

func test_planner_a_court_sells_surplus_above_the_reserve() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 0)
	var offers: Array = plan["offers"]
	assert_eq(offers.size(), 1)
	assert_eq(String(offers[0]["commodity"]), "grain")
	assert_eq(int(offers[0]["quantity"]), 10, "market.max_offer_units caps the lot")
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, planner_CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 1)
	assert_eq((result["bought"] as Array).size(), 0, "no holds means no imports")
	assert_eq(economy.quantity("grain"), 90)
	assert_true(economy.treasury > 5000)

func test_planner_production_inputs_are_never_sold_under_the_court() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"lumber": 30, "grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, market, 0, {}, {"lumber": 20}
	)
	for raw: Variant in plan["offers"]:
		var offer: Dictionary = raw
		assert_ne(String(offer["commodity"]), "lumber")

func test_planner_bids_short_build_inputs_with_free_holds_and_the_purse() -> void:
	var economy: PlayerEconomy = _ai_market_economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 20)
	var bids: Array = plan["bids"]
	assert_eq(bids.size(), 3, "baseline bid-type cap")
	for raw: Variant in bids:
		var bid: Dictionary = raw
		assert_true(int(bid["quantity"]) <= 5)
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, planner_CONFIG_FACTION)
	assert_eq((result["bought"] as Array).size(), 3)
	assert_true(economy.quantity("bronze") > 0)

func test_planner_no_bid_can_break_the_minimum_treasury() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"lumber": 0, "castIron": 0}, 520)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 20)
	var spend: int = 0
	for raw: Variant in plan["bids"]:
		var bid: Dictionary = raw
		spend += int(bid["quantity"]) * int(market.price(String(bid["commodity"])))
	assert_true(spend <= 20, "only the £20 above the floor may be bid")
	assert_true(economy.treasury - spend >= 500 - 1)

func test_planner_trade_fairs_raise_the_bid_type_cap_to_six() -> void:
	var economy: PlayerEconomy = _ai_market_economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0, "steel": 0, "bronze": 0},
		100000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, market, 100, {"trade_fairs": true}
	)
	assert_eq((plan["bids"] as Array).size(), 6)

func test_planner_a_buyer_spends_only_its_own_holds() -> void:
	var economy: PlayerEconomy = _ai_market_economy({}, 5000)
	var market := WorldMarket.with_default_prices()
	assert_true(bool(market.buy(economy, "grain", 2, 1)["ok"]))
	assert_eq(market.bought_units_for(1), 2)
	assert_eq(market.bought_units_for(0), 0)
	assert_eq(market.bought_units(), 2, "the price book still sees the tonnage")
	assert_true(bool(market.buy(economy, "grain", 1)["ok"]))
	assert_eq(market.bought_units_for(0), 1)
	assert_eq(TradeCargo.used(market, 1), 2)
	assert_eq(TradeCargo.used(market, 0), 1)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.bought_units_for(1), 2)
	assert_eq(restored.bought_units_for(0), 1)

func test_missing_inputs_make_the_plan_empty_ai_market() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	assert_true((AiMarketPlanner.plan(null, economy, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_ai_market_config(), null, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_ai_market_config(), economy, null, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.apply(null, null, {})["sold"] as Array).is_empty())

func test_planner_offers_stop_at_the_type_cap() -> void:
	var economy: PlayerEconomy = _ai_market_economy({
		"grain": 100, "timber": 100, "iron": 100, "wool": 100,
	})
	var plan: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, WorldMarket.with_default_prices(), 0
	)
	assert_eq((plan["offers"] as Array).size(), 3)

func test_planner_a_refused_trade_is_reported_not_swallowed() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 0}, 0)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = {
		"offers": [{"commodity": "grain", "quantity": 5}],
		"bids": [{"commodity": "lumber", "quantity": 5, "unit_price": 60}],
	}
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, planner_CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 0)
	assert_eq((result["bought"] as Array).size(), 0)
	assert_eq((result["refused"] as Array).size(), 2)

func test_planner_price_falls_back_to_the_catalog_and_zero_sales_are_refused() -> void:
	var market := WorldMarket.with_default_prices()
	market.prices.erase("grain")
	assert_eq(market.price("grain"), CommodityCatalog.base_price("grain"))
	var economy: PlayerEconomy = _ai_market_economy({"grain": 4})
	assert_false(bool(market.sell(economy, "grain", 0)["ok"]))

func test_planner_a_legacy_book_attributes_bids_to_the_player() -> void:
	var market: WorldMarket = WorldMarket.from_dict({"bids": {"grain": 3}})
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 0)
	var economy: PlayerEconomy = _ai_market_economy({}, 5000)
	assert_true(bool(market.buy(economy, "grain", 1, 1)["ok"]))
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 1)

func test_planner_a_plan_stages_orders_for_the_turn_end_auction() -> void:
	var economy: PlayerEconomy = _ai_market_economy(
		{"grain": 100, "lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 20)
	plan["free_holds"] = 20
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, planner_CONFIG_FACTION, {}
	)
	assert_eq((result["refused"] as Array).size(), 0)
	assert_gt((result["staged"] as Array).size(), 0)
	assert_eq(economy.quantity("grain"), 100, "nothing moves before the clearing")
	assert_gt(market.book.pending_buy_units(planner_CONFIG_FACTION), 0)
	var cleared: Dictionary = MarketClearing.clear(
		market, WorldMap.new(), {planner_CONFIG_FACTION: economy}, {planner_CONFIG_FACTION: 20}
	)
	assert_gt((cleared["deals"] as Array).size(), 0)
	assert_gt(economy.total_units(), 100)

func test_planner_a_stage_refuses_what_the_book_cannot_cover() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 0}, 10)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = {
		"free_holds": 0,
		"offers": [{"commodity": "grain", "quantity": 5}],
		"bids": [{"commodity": "timber", "quantity": 5}],
	}
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, planner_CONFIG_FACTION, {}
	)
	assert_eq((result["staged"] as Array).size(), 0)
	assert_eq((result["refused"] as Array).size(), 2)

# --- test_ai_merchant ---

func test_planner_a_merchant_on_a_genoese_grain_tile_signs_the_deed() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var merchant: CivilianState = _ai_merchant_merchant(planner_GRAIN)
	var plan: Dictionary = _ai_merchant_plan(model, [merchant])

	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), "purchase_land")
	assert_eq(Vector2i(plan["orders"][0]["tile"]), planner_GRAIN)
	assert_true((plan["moves"] as Array).is_empty(), "standing on the tile, it works")

func test_planner_a_merchant_away_from_the_offer_walks_toward_it() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var merchant: CivilianState = _ai_merchant_merchant(planner_AWAY)
	var plan: Dictionary = _ai_merchant_plan(model, [merchant])

	assert_true((plan["orders"] as Array).is_empty(), "the tile is out of reach")
	var moves: Array = plan["moves"]
	assert_eq(moves.size(), 1)
	var move_tile: Vector2i = moves[0]["tile"]
	assert_eq(move_tile, planner_IRON, "one step into the Minor's land")

func test_planner_without_an_embassy_the_merchant_stays_home() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var court := DiplomacyState.new()
	court.initialize(1)
	court.ensure_relation(0, planner_MINOR, 1)
	var plan: Dictionary = _ai_merchant_plan(model, [_ai_merchant_merchant(planner_GRAIN)], court)

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())

func test_planner_a_war_with_the_seller_closes_the_market() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var court: DiplomacyState = planner_Fixture.merchant_court()
	assert_true(
		bool(DiplomacyRules.declare_war(court, 0, planner_MINOR, true, world).get("ok", false))
	)
	var plan: Dictionary = _ai_merchant_plan(model, [_ai_merchant_merchant(planner_GRAIN)], court)

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())

func test_planner_a_deeded_tile_is_offered_to_nobody_again() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	assert_true(model.purchase_tile(planner_GRAIN, 1), "a rival's deed")
	var plan: Dictionary = _ai_merchant_plan(model, [_ai_merchant_merchant(planner_GRAIN)])

	assert_true((plan["orders"] as Array).is_empty())
	assert_true(
		(plan["moves"] as Array).is_empty(),
		"the only other offer needs a prospect, so the merchant idles"
	)

func test_planner_a_mineral_waits_for_the_explorers_prospect() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var works := LandWorks.new()
	var merchant: CivilianState = _ai_merchant_merchant(planner_IRON)
	var plan: Dictionary = _ai_merchant_plan(model, [merchant])

	assert_true((plan["orders"] as Array).is_empty(), "iron is not prospected yet")
	var move_tile: Vector2i = (plan["moves"] as Array)[0]["tile"]
	assert_eq(move_tile, planner_GRAIN, "the grain deed wins")

	works.set_prospected(0, model, planner_IRON)
	var ready: Dictionary = _ai_merchant_plan(model, [merchant], null, works)
	assert_eq((ready["orders"] as Array).size(), 1)
	assert_eq(Vector2i(ready["orders"][0]["tile"]), planner_IRON)

func test_planner_a_court_with_a_deed_on_offer_trains_one_merchant() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var roster: Array = planner__staffed_roster()
	var context: Dictionary = _ai_merchant_context(model, planner_Fixture.merchant_court())
	var plan: Dictionary = _ai_merchant_plan(model, roster, planner_Fixture.merchant_court(), null, context)

	assert_true(bool(plan["training"].get("ok", false)))
	assert_eq(String(plan["training"]["type_id"]), "merchant")

	var techless: Dictionary = _ai_merchant_context(model, planner_Fixture.merchant_court())
	techless["tech_unlocked"] = {}
	var plain: Dictionary = _ai_merchant_plan(model, roster, planner_Fixture.merchant_court(), null, techless)
	assert_true(
		(plain["training"] as Dictionary).is_empty(),
		"no merchant companies and the staff is already at target"
	)

## The merchant follows the door, not just the deed: with no embassy yet but a
## priced deed from a charted Minor, the staff target still names one Merchant —
## the embassy waits on the merchant, so the hire cannot wait on the embassy
## (issue #724; wiki: civilian-units § Merchant).
func test_an_openable_chain_trains_one_merchant() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var court := DiplomacyState.new()
	court.initialize(1)
	court.ensure_relation(0, planner_MINOR, 1)
	var roster: Array = planner__staffed_roster()
	var plan: Dictionary = _ai_merchant_plan(model, roster, court)

	assert_true(bool(plan["training"].get("ok", false)))
	assert_eq(String(plan["training"]["type_id"]), "merchant")

func test_the_openable_chain_needs_peace_charting_and_an_unsigned_deed() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var view: VisibilityModel = planner_Fixture.visibility(model)
	# An open court with no embassy, at any purse: the chain is openable.
	var open: Dictionary = {"diplomacy": planner_Fixture.merchant_court_unembarked(), "visibility": view}
	assert_true(
		AiMerchantWork.chain_openable(model, 0, open),
		"no embassy, peace, a priced deed: the chain is openable"
	)
	var poor: Dictionary = {"treasury": 0, "diplomacy": open["diplomacy"], "visibility": view}
	assert_true(
		AiMerchantWork.chain_openable(model, 0, poor),
		"the chain opens before the deed is affordable"
	)
	# An embassy already stands: the deed must be affordable to matter.
	var walked: Dictionary = {"diplomacy": planner_Fixture.merchant_court(), "visibility": view}
	assert_false(
		AiMerchantWork.chain_openable(model, 0, walked),
		"the embassy stands, so the chain is walked"
	)
	# A war with the seller closes it.
	var world := WorldMap.new()
	world.add_region(model)
	var war_court: DiplomacyState = planner_Fixture.merchant_court_unembarked()
	assert_true(
		bool(DiplomacyRules.declare_war(war_court, 0, planner_MINOR, true, world).get("ok", false))
	)
	var war: Dictionary = {"diplomacy": war_court, "visibility": view}
	assert_false(
		AiMerchantWork.chain_openable(model, 0, war),
		"a war with the seller closes the chain"
	)
	# The deed is already signed: nothing is left to open the door for.
	model.purchase_tile(planner_GRAIN, 1)
	var deeded: Dictionary = {"diplomacy": planner_Fixture.merchant_court_unembarked(), "visibility": view}
	assert_false(
		AiMerchantWork.chain_openable(model, 0, deeded),
		"a signed deed leaves no chain to open"
	)

## The deed the ledger prices is the cheapest one the court could sign — with or
## without the embassy — and it is priced before the purse can cover it, so a
## court saving toward it has a row to read (issue #724 task 3).
func test_the_openable_deed_prices_the_cheapest_signature() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var view: VisibilityModel = planner_Fixture.visibility(model)
	var open: Dictionary = {
		"diplomacy": planner_Fixture.merchant_court_unembarked(), "visibility": view,
	}
	var deed: Dictionary = AiMerchantWork.openable_deed(model, 0, open)
	assert_eq(int(deed.get("price", 0)), 750, "the published 15 x base price")
	assert_eq(int(deed.get("seller", -1)), planner_MINOR)
	# The embassy already stands: the same deed is still the one to sign.
	var walked: Dictionary = {"diplomacy": planner_Fixture.merchant_court(), "visibility": view}
	assert_eq(int(AiMerchantWork.openable_deed(model, 0, walked).get("price", 0)), 750)
	# The chain's own read is the rung it still has to walk.
	assert_true(
		AiMerchantWork.openable_deed(model, 0, walked, true).is_empty(),
		"an embassy already standing leaves no rung to walk"
	)
	# A war with the seller leaves nothing to price.
	var world := WorldMap.new()
	world.add_region(model)
	var war_court: DiplomacyState = planner_Fixture.merchant_court_unembarked()
	DiplomacyRules.declare_war(war_court, 0, planner_MINOR, true, world)
	assert_true(
		AiMerchantWork.openable_deed(
			model, 0, {"diplomacy": war_court, "visibility": view}
		).is_empty(),
		"a war with the seller leaves no deed to price"
	)

func test_planner_one_merchant_is_enough() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var roster: Array = planner__staffed_roster()
	roster.append(CivilianState.create(9, 0, "merchant", Vector2i(0, 2)))
	var plan: Dictionary = _ai_merchant_plan(model, roster)

	assert_true(
		(plan["training"] as Dictionary).is_empty(),
		"one merchant fills the deed slot; the college trains nothing more"
	)

## The Build/Work pass answers each owner with its own ledger: the rival's deed
## debits the rival, and the human crown's purse is untouched (wiki:
## civilian-units § Merchant — "debit at completion").
func test_planner_a_rivals_deed_is_charged_to_the_rival_ledger() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var merchant: CivilianState = layer.add_unit(1, "merchant", planner_GRAIN)
	var court: DiplomacyState = planner_Fixture.merchant_court()
	court.ensure_relation(1, planner_MINOR, 1)
	court.set_overture(1, planner_MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	var units: Array[CivilianState] = [merchant]
	var context: Dictionary = {"treasury": 5000, "diplomacy": court}
	var check: Dictionary = CivilianWork.assign(
		model, merchant, "purchase_land", layer.works, units, planner_Fixture.stockpile(),
		null, planner_GRAIN, {}, {}, context
	)
	assert_true(bool(check.get("ok", false)), String(check.get("reason", "")))

	var human: PlayerEconomy = planner__ledger(5000)
	var rival: PlayerEconomy = planner__ledger(5000)
	var reports: Array[Dictionary] = CivilianTurnPass.resolve(
		layer, world, null, {0: human, 1: rival}
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(rival.treasury, 4250, "the rival paid the price")
	assert_eq(human.treasury, 5000, "the human purse is untouched")
	assert_true(model.is_purchased_tile(planner_GRAIN))
	assert_eq(model.owner_at(planner_GRAIN.x, planner_GRAIN.y), 1)
	layer.free()

## A deed is never recorded without a purse to close it (wiki: § Merchant —
## the price is debited when the work completes).
func test_planner_a_deed_without_a_ledger_is_not_signed() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var works := LandWorks.new()
	var merchant: CivilianState = _ai_merchant_merchant(planner_GRAIN)
	var units: Array[CivilianState] = [merchant]
	var context: Dictionary = {"treasury": 5000, "diplomacy": planner_Fixture.merchant_court()}
	assert_true(bool(CivilianWork.assign(
		model, merchant, "purchase_land", works, units, planner_Fixture.stockpile(), null,
		planner_GRAIN, {}, {}, context
	).get("ok", false)))

	var reports: Array[Dictionary] = CivilianWork.resolve_turn(model, units, works)
	assert_true(bool(reports[0]["completed"]))
	assert_false(model.is_purchased_tile(planner_GRAIN), "no ledger, no deed")
	assert_false(LandPurchase.complete(model, planner_GRAIN, 0, null))

## The whole rival pass: the economy adapter musters the order for a court that
## already holds the embassy and the tech, and the next Build/Work signs it from
## that court's own purse (wiki: civilian-units § Merchant; docs/ai.md).
func test_planner_the_rival_turn_signs_the_deed_for_its_own_crown() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	model.provinces[0].owner = 1
	model.faction_ids.append(1)
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var merchant: CivilianState = layer.add_unit(1, "merchant", planner_GRAIN)
	# `spawn(place_units=false)` prepares the works only; the adapter walks the
	# region table, so the roster must be registered like a mustered crew.
	layer.regions.set_region(model.region_id, layer.units)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.civilian_layer = layer
	play.map_seed = 1500
	play.ai = AiState.new()
	play.diplomacy = planner_Fixture.merchant_court()
	play.diplomacy.ensure_relation(1, planner_MINOR, 1)
	play.diplomacy.set_overture(1, planner_MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	var ledger: PlayerEconomy = play.ai.economy_for(1)
	ledger.tech_unlocked["merchant_companies"] = true
	ledger.treasury = 5000

	MapPlayEconomyAi.run(play)
	assert_true(merchant.is_working(), "the rival turn musters the purchase")
	assert_eq(merchant.work_action(), "purchase_land")
	assert_eq(merchant.work_tile(), planner_GRAIN)

	var purse: int = ledger.treasury
	CivilianTurnPass.resolve(layer, world, null, {1: ledger})
	assert_true(model.is_purchased_tile(planner_GRAIN), "the deed is signed next turn")
	assert_eq(ledger.treasury, purse - 750, "the buyer's own purse paid")

## Only a Merchant carries the order, and a tile another crew already holds is
## not offered twice (wiki: civilian-units § Per-player tile exclusivity).
func test_planner_only_a_merchant_and_an_unreserved_tile_get_the_order() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var context: Dictionary = _ai_merchant_context(model, planner_Fixture.merchant_court())
	var builder: CivilianState = CivilianState.create(1, 0, "builder", planner_GRAIN)
	var none: Dictionary = AiMerchantWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, builder, [builder], LandWorks.new(),
		planner_Fixture.stockpile(), {}, {}, context, {}
	))
	assert_true(none.is_empty(), "a builder cannot buy land")
	var merchant: CivilianState = _ai_merchant_merchant(planner_GRAIN)
	var taken: Dictionary = AiMerchantWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, merchant, [merchant], LandWorks.new(),
		planner_Fixture.stockpile(), {}, {}, context, {planner_GRAIN: true}
	))
	assert_true(taken.is_empty(), "another crew already has this tile")

## An empty purse or an unaffordable price leaves nothing on offer, and a deed
## is never a Great Power's to sell (wiki: civilian-units § Merchant).
func test_planner_an_empty_purse_and_a_great_power_land_offer_nothing() -> void:
	var model: MapModel = planner_Fixture.build_minor()
	var court: DiplomacyState = planner_Fixture.merchant_court()
	assert_true(
		AiMerchantWork.buyable_tiles(model, 0, LandWorks.new(), {
			"treasury": 0, "diplomacy": court,
		}).is_empty(),
		"no treasury, no offer"
	)
	var gp: MapModel = planner_Fixture.build()
	var gp_court := DiplomacyState.new()
	gp_court.initialize(1)
	gp_court.ensure_relation(0, 1, 1)
	gp_court.set_overture(0, 1, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(
		AiMerchantWork.buyable_tiles(gp, 0, LandWorks.new(), {
			"treasury": 5000, "diplomacy": gp_court,
		}).is_empty(),
		"only Minor Nations and Tribes sell land"
	)
	assert_eq(AiMerchantWork.cheapest_offer(gp, 0, 1, 5000), 0)
	assert_true(AiMerchantWork.best_move(gp, _ai_merchant_merchant(planner_GRAIN), LandWorks.new()).is_empty())
	# The priced read lifts no treasury bar: the deed has a published price even
	# when this turn's floor cannot cover it (issue #724).
	assert_eq(AiMerchantWork.priced_offer(model, 0, planner_MINOR, null), 750)
	assert_eq(
		AiMerchantWork.cheapest_offer(model, 0, planner_MINOR, 0), 0,
		"this turn's floor still bars the signature"
	)

func _ai_merchant_merchant(tile: Vector2i, owner: int = 0) -> CivilianState:
	return CivilianState.create(1, owner, "merchant", tile)

func planner__ledger(treasury: int) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy

## Builders, engineer_target, explorer_target and a spy: every earlier training
## slot is filled, so a deed on offer makes the merchant the next craft.
func planner__staffed_roster() -> Array:
	return [
		CivilianState.create(1, 0, "builder", Vector2i(0, 0)),
		CivilianState.create(2, 0, "builder", Vector2i(1, 0)),
		CivilianState.create(3, 0, "engineer", Vector2i(0, 1)),
		CivilianState.create(6, 0, "engineer", Vector2i(1, 2)),
		CivilianState.create(4, 0, "explorer", Vector2i(1, 1)),
		CivilianState.create(7, 0, "explorer", Vector2i(0, 0)),
		CivilianState.create(8, 0, "explorer", Vector2i(1, 0)),
		CivilianState.create(5, 0, "spy", Vector2i(0, 2)),
	]

func _ai_merchant_context(
	model: MapModel, court: DiplomacyState, treasury: int = 5000
) -> Dictionary:
	return {
		"treasury": treasury,
		"paper": 8,
		"capital_province": 0,
		"capital_tile": Vector2i(0, 0),
		"at_war": false,
		"diplomacy": court,
		"tech_unlocked": {"merchant_companies": true},
		"visibility": planner_Fixture.visibility(model),
	}

## Neutral court for the same reason as `_market_plan`: these cases prove the
## deed door and the merchant's slot, not the archetype's extra crew.
func _ai_merchant_plan(
	model: MapModel,
	units: Array,
	court: DiplomacyState = null,
	works: LandWorks = null,
	context: Dictionary = {}
) -> Dictionary:
	var diplomacy: DiplomacyState = court if court != null else planner_Fixture.merchant_court()
	var config: AiConfig = AiConfig.build(0, 1500)
	config.personality = AiPersonality.NEUTRAL
	return AiCivilianPlanner.plan(
		config, model, units, works if works != null else LandWorks.new(),
		planner_Fixture.stockpile(), {}, {"merchant_companies": true},
		context if not context.is_empty() else _ai_merchant_context(model, diplomacy)
	)

func planner__overture(
	world: WorldMap, state: DiplomacyState, config: AiConfig, tech: Dictionary
) -> Dictionary:
	var context: Dictionary = {
		"treasury": {config.faction: 5000},
		"tech": {config.faction: tech},
		"player": -1,
	}
	var entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		config, state, AiState.new(), world, 1, planner_MINOR, 50, context
	)
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) == AiDiplomacyOffers.KIND_OVERTURE:
			return entry
	return {}

# --- test_ai_army_reinforce ---

func _ai_army_reinforce_config() -> AiConfig:
	return AiConfig.build(ai_army_reinforce_OWNER, 1500)

## A court with its own ledger: treasury and the opening stock of fabric and
## cast iron the line rows need.
func _ai_army_reinforce_economy(treasury: int = 12000, peasants: int = 6) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.workers = WorkerPool.make(peasants)
	return economy

func test_planner_a_rival_musters_the_strongest_line_it_can_pay_for() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(), 3, false)

	assert_eq(String(plan["muster"]), "arquebusiers", "the strongest era-1 line")
	var candidates: Array = plan["candidates"]
	assert_true(candidates.size() > 0)
	assert_eq(String(candidates[0]["type_id"]), "arquebusiers")
	for entry: Dictionary in candidates:
		assert_true(
			RegimentCatalog.category(String(entry["type_id"]))
			in AiArmyReinforceLine.LINE_CATEGORIES,
			"a mustered regiment is a line regiment"
		)

func test_planner_the_war_chest_keeps_the_court_from_overspending() -> void:
	# 4,000 ducats covers a pike, but that would empty the purse; the 2,000 levy
	# is the only line that leaves the court's thousand-ducat floor in the bank.
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(4000), 3, false)

	assert_eq(String(plan["muster"]), "peasant_levies")
	var priced: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(1500), 3, false)
	assert_eq(String(priced["muster"]), "", "nothing payable leaves the floor alone")
	assert_true((priced["reasons"] as Array).has("nothing payable"))


## The hull the court is saving for outranks the next regiment once it can fill
## the chest: a muster spends only what stands above it, so the yard's price
## survives the army's turn and the hull is actually laid (issue #484). A chest
## the court cannot fill yet is not held back at all (issue #591).
func test_the_muster_waits_for_the_hull_it_is_saving_for() -> void:
	var config: AiConfig = _ai_army_reinforce_config()
	var economy: PlayerEconomy = _ai_army_reinforce_economy(4600)
	var free: Dictionary = AiArmyReinforce.plan(config, economy, 3, true)
	assert_ne(String(free["muster"]), "", "with no fleet claim the court arms up")

	# 4,600 ducats is short of the 5,500 yard: the army it can pay for is raised.
	var short: Dictionary = AiArmyReinforce.plan(config, economy, 3, true, 0, -1, 5500)
	assert_ne(String(short["muster"]), "", "a chest it cannot fill is not the army's ceiling")
	assert_false((short["reasons"] as Array).has("saving for a hull"))

	# With the chest in hand the fleet's claim comes first again.
	var held: Dictionary = AiArmyReinforce.plan(
		config, _ai_army_reinforce_economy(5500), 5, true, 0, -1, 5500
	)
	assert_eq(String(held["muster"]), "", "the hull's chest is not the army's to spend")
	assert_true(
		(held["reasons"] as Array).has("saving for a hull"),
		"and the trace says which claim held it back"
	)

	# Once the purse covers the chest and the line, the muster resumes.
	var rich: Dictionary = AiArmyReinforce.plan(
		config, _ai_army_reinforce_economy(9000), 5, true, 0, -1, 5500
	)
	assert_ne(String(rich["muster"]), "", "a purse above the chest may arm up again")

func test_the_muster_trace_names_the_row_that_blocks_it() -> void:
	# A court holding its whole war chest and no fabric musters nothing; the
	# trace must say which row is missing, not only `nothing payable` (#474).
	var economy: PlayerEconomy = _ai_army_reinforce_economy(12000)
	economy.stockpile["fabric"] = 0
	var plan: Dictionary = AiArmyReinforce.plan(
		_ai_army_reinforce_config(), economy, 5, true
	)
	assert_eq(String(plan["muster"]), "", "no line is payable without fabric")
	var reasons: Array = plan["reasons"]
	assert_true(reasons.has("nothing payable"))
	assert_true(reasons.has("missing fabric 1"), "the trace names the row")


## Issue #484: once the chest is full the hull's row is the fleet's too. A court
## that wove one cloth a turn and mustered it away could never lay the hull it
## had already paid for, so the muster spends only the cloth above that row.
func test_the_muster_yields_the_hull_s_row_once_the_chest_is_full() -> void:
	var config: AiConfig = _ai_army_reinforce_config()
	var economy: PlayerEconomy = _ai_army_reinforce_economy(9000)
	economy.stockpile["fabric"] = 1
	var row: Dictionary = {"lumber": 1, "fabric": 1}
	var held: Dictionary = AiArmyReinforce.plan(
		config, economy, 5, true, 0, -1, 5500, row
	)
	assert_eq(String(held["muster"]), "", "the last cloth is the hull's")
	assert_true(
		(held["reasons"] as Array).has("missing fabric 1"),
		"and the trace names the row the fleet holds"
	)
	# One cloth above the row is the army's again.
	economy.stockpile["fabric"] = 2
	var spare: Dictionary = AiArmyReinforce.plan(
		config, economy, 5, true, 0, -1, 5500, row
	)
	assert_ne(String(spare["muster"]), "", "the surplus above the row may be spent")
	# With no hull due the row is not held at all.
	var free: Dictionary = AiArmyReinforce.plan(config, economy, 3, true, 0, -1, 5500)
	assert_ne(String(free["muster"]), "", "no fleet claim, no held row")


func test_planner_a_court_at_target_strength_waits_and_a_war_lifts_the_target() -> void:
	var config: AiConfig = _ai_army_reinforce_config()
	var peace_target: int = config.parameter("army.regiment_target")
	var war_target: int = peace_target + config.parameter("army.war_extra")
	var peace: Dictionary = AiArmyReinforce.plan(config, _ai_army_reinforce_economy(), peace_target, false)
	assert_eq(String(peace["muster"]), "", "at the peace target the court waits")
	assert_eq(int(peace["target"]), peace_target)

	var war: Dictionary = AiArmyReinforce.plan(config, _ai_army_reinforce_economy(), peace_target, true)
	assert_eq(int(war["target"]), war_target, "the war footing raises the target")
	assert_eq(String(war["muster"]), "arquebusiers", "a court at war arms up")

	var full: Dictionary = AiArmyReinforce.plan(config, _ai_army_reinforce_economy(), war_target, true)
	assert_eq(String(full["muster"]), "", "the war target is a ceiling too")

## A court that can see the bar arms up for the finish (DR-20261114-04): the
## target rises by the pressure extra, so a court already at its published
## target keeps mustering, and the price rules are unchanged.
func test_the_victory_pressure_raises_the_muster_target() -> void:
	var config: AiConfig = _ai_army_reinforce_config()
	var economy: PlayerEconomy = _ai_army_reinforce_economy()
	var at: int = config.parameter("army.regiment_target")
	var peace: Dictionary = AiArmyReinforce.plan(config, economy, at, false)
	var extra: int = config.parameter("victory.pressure_regiments")
	var pressed: Dictionary = AiArmyReinforce.plan(config, economy, at, false, extra)

	assert_eq(int(peace["target"]), at)
	assert_eq(int(pressed["target"]), at + extra, "the pressing court aims higher")
	assert_eq(String(peace["muster"]), "", "at the published target")
	assert_eq(String(pressed["muster"]), "arquebusiers", "the pressing court keeps arming")
	assert_true(
		AiArmyReinforce.muster_reserve(config, economy, at, false).is_empty(),
		"a court at its published target reserves no more cloth"
	)
	assert_false(
		AiArmyReinforce.muster_reserve(config, economy, at, false, extra).is_empty(),
		"the pressing court provisions for the bigger army"
	)


func test_planner_a_thin_labour_pool_stops_the_muster() -> void:
	# The retuned floor is 1 free hand (issue #1314 companion; issue #1355): a
	# pool of one draws the levy, an empty pool is where the floor holds.
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(12000, 1), 3, false)

	assert_eq(String(plan["muster"]), "arquebusiers", "the levy's own hand is drawn")
	var empty: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(12000, 0), 3, false)
	assert_eq(String(empty["muster"]), "", "no hand, no levy")
	assert_true((empty["reasons"] as Array).has("labour floor"))

func test_planner_a_researched_pattern_is_the_one_that_musters() -> void:
	var economy: PlayerEconomy = _ai_army_reinforce_economy()
	economy.tech_unlocked["weapon_craftsmanship"] = true
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), economy, 3, false)

	assert_eq(String(plan["muster"]), "musketeers", "the newest legal line wins")

## One peace-time world: England's seat at province 0, France's at province 1,
## with a rival ledger already resolved for France. `extra` appends the caller's
## field armies to the region roster.
func planner__play(
	treasury: int = 12000, with_ledger: bool = true, extra: Array[ArmyState] = []
) -> PlaySession:
	var world: WorldMap = planner_AiFixture.land_world([HUMAN, ai_army_reinforce_OWNER], {0: true, 1: true})
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, HUMAN, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(
			2, ai_army_reinforce_OWNER, 1, true, ["peasant_levies", "peasant_levies"] as Array[String], 101
		),
	]
	armies.append_array(extra)
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.next_regiment = 1000
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = HUMAN
	play.world = world
	play.model = model
	var court := DiplomacyState.new()
	court.reset(HUMAN)
	court.ensure_relation(HUMAN, ai_army_reinforce_OWNER, 1)
	play.diplomacy = court
	play.army_layer = layer
	play.map_seed = 1500
	if with_ledger:
		play.ai = AiState.new()
		play.ai.economies[ai_army_reinforce_OWNER] = _ai_army_reinforce_economy(treasury)
	return play

func test_planner_the_map_pass_musters_a_rival_from_its_own_ledger() -> void:
	var play: PlaySession = planner__play(12000)
	var economy: PlayerEconomy = play.ai.economies[ai_army_reinforce_OWNER]
	var before: int = play.army_layer.regiment_count_all(ai_army_reinforce_OWNER)
	var peasants: int = economy.available_peasants()

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 1, "a muster and nothing else in peace")
	assert_eq(String(trace[0]["kind"]), MapPlayArmyMusterAi.KIND_REINFORCE)
	assert_eq(String(trace[0]["type"]), "arquebusiers")
	assert_eq(play.army_layer.regiment_count_all(ai_army_reinforce_OWNER), before + 1)
	assert_eq(economy.available_peasants(), peasants - 1, "one peasant joins the colours")
	assert_true(
		economy.treasury < 12000, "the court's own purse pays, never the crown's"
	)
	var home: ArmyState = ArmyTraining.home_army(play.army_layer.armies, ai_army_reinforce_OWNER)
	assert_not_null(home)
	assert_true(
		home.regiments.has(String(trace[0]["regiment"])),
		"the new regiment wears France's colours in the Home Army"
	)
	play.army_layer.free()

func test_planner_the_human_crown_is_never_mustered_for() -> void:
	var play: PlaySession = planner__play(12000)
	var before: int = play.army_layer.regiment_count_all(HUMAN)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(play.army_layer.regiment_count_all(HUMAN), before)
	for record: Dictionary in trace:
		assert_eq(int(record["faction"]), ai_army_reinforce_OWNER, "the crown musters its own men")
	play.army_layer.free()

func test_planner_a_court_without_a_ledger_never_musters() -> void:
	var play: PlaySession = planner__play(12000, false)
	var before: int = play.army_layer.regiment_count_all(ai_army_reinforce_OWNER)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 0, "no ledger, no muster")
	assert_eq(play.army_layer.regiment_count_all(ai_army_reinforce_OWNER), before)
	play.army_layer.free()

func test_planner_the_observer_log_reads_the_muster() -> void:
	var play: PlaySession = planner__play(12000)
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	var merged: Dictionary = AiTurnLog.record(play, trace, [], {})
	var record: Dictionary = merged["factions"][ai_army_reinforce_OWNER]
	assert_eq(int(record["actions"].get("reinforce", 0)), 1, "one regiment raised")
	var lines: Array = record["events"]
	assert_true(lines.size() > 0, "the event list names the pattern")
	play.army_layer.free()

# --- test_ai_hospital_train_work ---

## France's ledger at war: enough lumber and cloth for a train and a yard's work
## behind it, Organised Regiments, and three peasants — so the fields keep their
## hands and the muster stays silent in these tests.
func _train_economy(lumber: int = 40, fabric: int = 12, tech: bool = true) -> PlayerEconomy:
	var economy: PlayerEconomy = _ai_army_reinforce_economy()
	economy.stockpile["lumber"] = lumber
	economy.stockpile["fabric"] = fabric
	economy.workers = WorkerPool.make(3)
	if tech:
		economy.tech_unlocked["organised_regiments"] = true
	return economy


## A worn field army of France's standing on France's own ground, and a war on.
## `extra` adds more field armies for the one-train-a-turn case.
func _train_play(
	worn_health: int = 12, war: bool = true, extra: Array[ArmyState] = []
) -> PlaySession:
	var field := ArmyState.muster(
		3, ai_army_reinforce_OWNER, 1, false,
		["peasant_levies", "peasant_levies"] as Array[String], 201
	)
	for regiment_id: String in field.regiments:
		field.regiment_health[regiment_id] = worn_health
	## It has marched already, so the turn's trace carries the surgeons alone.
	field.moved = true
	var armies: Array[ArmyState] = [field]
	armies.append_array(extra)
	var play: PlaySession = planner__play(12000, true, armies)
	play.ai.economies[ai_army_reinforce_OWNER] = _train_economy()
	if war:
		DiplomacyRules.declare_war(play.diplomacy, ai_army_reinforce_OWNER, HUMAN)
	return play


func _train_ledger(play: PlaySession) -> PlayerEconomy:
	return play.ai.economies[ai_army_reinforce_OWNER]


func _train_roster(play: PlaySession) -> Array[ArmyState]:
	var roster: Array[ArmyState] = []
	roster.assign(play.army_layer.regions.value(0, []))
	return roster


func _chosen(play: PlaySession, at_war: bool = true) -> ArmyState:
	return AiHospitalTrainWork.best_army(
		play.model, _train_roster(play), ai_army_reinforce_OWNER, _train_ledger(play), at_war
	)


func test_a_worn_field_army_gets_the_rivals_surgeons() -> void:
	var play: PlaySession = _train_play()
	var chosen: ArmyState = _chosen(play)

	assert_not_null(chosen, "a court at war will not leave a mauled host in the field")
	if chosen != null:
		assert_eq(chosen.id, 3, "the field army, not the Home Army at its seat")
		assert_true(
			AiHospitalTrainWork.worn(chosen) < AiHospitalTrainWork.WORN_SHARE,
			"one wound short of a rest is all the policy asks",
		)
	play.army_layer.free()


func test_peace_leaves_the_tents_in_the_wagon() -> void:
	var play: PlaySession = _train_play(12, false)

	assert_true(_chosen(play, false) == null, "nurses eat: no tents are pitched in peace")
	play.army_layer.free()


func test_a_fresh_army_needs_no_surgeon() -> void:
	var play: PlaySession = _train_play(9999)

	assert_true(_chosen(play) == null, "an unwounded host has nothing to mend")
	play.army_layer.free()


func test_a_province_ward_beats_the_train() -> void:
	var play: PlaySession = _train_play()
	for province: ProvinceState in play.model.provinces:
		if province.owner == ai_army_reinforce_OWNER:
			province.hospital_level = HospitalRules.MAX_LEVEL

	assert_true(_chosen(play) == null, "a General hospital already heals better")
	play.army_layer.free()


func test_the_train_waits_for_organised_regiments() -> void:
	var play: PlaySession = _train_play()
	_train_ledger(play).tech_unlocked.erase("organised_regiments")

	assert_true(_chosen(play) == null, "the rule's tech gate is the planner's too")
	play.army_layer.free()


func test_the_yard_keeps_its_timber() -> void:
	var play: PlaySession = _train_play()
	_train_ledger(play).stockpile["lumber"] = 3

	assert_true(_chosen(play) == null, "the price must leave a working stock behind")
	play.army_layer.free()


func test_the_map_pass_pitches_the_rivals_train() -> void:
	var play: PlaySession = _train_play()
	var economy: PlayerEconomy = _train_ledger(play)
	var lumber: int = economy.quantity("lumber")
	var fabric: int = economy.quantity("fabric")

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	var hops: Array[Dictionary] = []
	for record: Dictionary in trace:
		if String(record["kind"]) == MapPlayArmyMusterAi.KIND_HOSPITAL:
			hops.append(record)
	assert_eq(hops.size(), 1, "one train in the turn")
	assert_eq(int(hops[0]["faction"]), ai_army_reinforce_OWNER)
	assert_eq(int(hops[0]["army"]), 3)
	assert_true(
		planner__field_army(play).field_hospital,
		"the standard carries the tents from now on"
	)
	assert_eq(economy.quantity("lumber"), lumber - 2, "the court's own timber pays")
	# The retuned labour floor (1 spare hand, #1314 companion) also lets this
	# court's levy fire the same turn, so a second fabric row may stand beside
	# the train's own: the train's fabric is paid either way.
	var fabric_spent: int = fabric - int(economy.quantity("fabric"))
	assert_true(fabric_spent >= 1, "the train's cloth is paid")
	play.army_layer.free()


## Two equally worn hosts: the lowest army id carries the tents, so a given
## roster always answers the same way.
func test_a_tie_goes_to_the_lowest_army_id() -> void:
	var twin := ArmyState.muster(
		4, ai_army_reinforce_OWNER, 1, false,
		["peasant_levies", "peasant_levies"] as Array[String], 301
	)
	for regiment_id: String in twin.regiments:
		twin.regiment_health[regiment_id] = 12
	twin.moved = true
	var play: PlaySession = _train_play(12, true, [twin] as Array[ArmyState])
	var chosen: ArmyState = _chosen(play)

	assert_not_null(chosen)
	if chosen != null:
		assert_eq(chosen.id, 3, "army 3 and army 4 are worn alike; the lower id wins")
	play.army_layer.free()


func test_the_court_brings_one_train_a_turn() -> void:
	var second := ArmyState.muster(
		4, ai_army_reinforce_OWNER, 1, false,
		["peasant_levies", "peasant_levies"] as Array[String], 301
	)
	for regiment_id: String in second.regiments:
		second.regiment_health[regiment_id] = 12
	second.moved = true
	var play: PlaySession = _train_play(12, true, [second] as Array[ArmyState])

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	var trained: int = 0
	for record: Dictionary in trace:
		if String(record["kind"]) == MapPlayArmyMusterAi.KIND_HOSPITAL:
			trained += 1
	assert_eq(trained, 1, "a court equips one train a turn")
	var carrying: int = 0
	for army: ArmyState in _train_roster(play):
		if army != null and army.field_hospital:
			carrying += 1
	assert_eq(carrying, 1)
	play.army_layer.free()


func test_the_observer_log_reads_the_train() -> void:
	var play: PlaySession = _train_play()
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	var merged: Dictionary = AiTurnLog.record(play, trace, [], {})
	var record: Dictionary = merged["factions"][ai_army_reinforce_OWNER]

	assert_eq(int(record["actions"].get("hospital", 0)), 1, "the train is its own act")
	assert_eq(int(record["actions"].get("march", 0)), 0, "never miscounted as a march")
	var named: bool = false
	for line: Dictionary in merged["events"]:
		if String(line.get("text", "")).contains("field hospital train"):
			named = true
	assert_true(named, "the log names the train and the ground")
	assert_true(
		AiTurnLog.headline(record).contains("field hospitals ×1"),
		"the observer panel headline counts the train",
	)
	play.army_layer.free()


func planner__field_army(play: PlaySession) -> ArmyState:
	for army: ArmyState in _train_roster(play):
		if army != null and army.id == 3:
			return army
	return null

# --- test_ai_builder_work ---

func _ai_builder_work_model(level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [ai_builder_work_TOWN, planner_TIMBER, planner_TIMBER_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Plantation", tiles, Vector2.ZERO, 3, 1)
	province.town_tile = ai_builder_work_TOWN
	province.town_development = level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [planner_TIMBER, planner_TIMBER_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model

func _ai_builder_work_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, ai_builder_work_TOWN)
	for tile: Vector2i in [planner_TIMBER, planner_TIMBER_FAR]:
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works

func _ai_builder_work_stockpile() -> Dictionary:
	return {"timber": 200, "lumber": 40, "castIron": 40}

func _ai_builder_work_plan(model: MapModel, context: Dictionary = {}) -> Dictionary:
	var builder: CivilianState = CivilianState.create(1, 1, "builder", planner_TIMBER)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _ai_builder_work_works(model), _ai_builder_work_stockpile(),
		{"timber": 4}, {"national_bureaucracy": true}, context
	)

## The estates are finished, so the town is the only order left; a level-1 town
## that would pay 4 lumber a turn is worth more than idling the Builder.
func test_planner_a_developing_town_becomes_the_builders_order() -> void:
	var plan: Dictionary = _ai_builder_work_plan(_ai_builder_work_model(1))
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), ai_builder_work_TOWN)

## An overseas province is priced on the tons the holds landed, not on the far
## shore's harvest: with nothing delivered the town pays nothing and is left.
func test_planner_an_overseas_town_with_nothing_landed_is_left_alone() -> void:
	var plan: Dictionary = _ai_builder_work_plan(_ai_builder_work_model(1), {"delivered_raw": {}})

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())

func test_planner_an_overseas_town_is_upgraded_from_the_tons_that_landed() -> void:
	var plan: Dictionary = _ai_builder_work_plan(_ai_builder_work_model(1), {"delivered_raw": {0: {"timber": 8}}})
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")

func test_planner_a_finished_town_is_left_alone() -> void:
	assert_true((_ai_builder_work_plan(_ai_builder_work_model(CivilianWorkPlan.MAX_TOWN))["orders"] as Array).is_empty())

func test_planner_the_bureaucracy_gate_still_refuses_the_order() -> void:
	var model: MapModel = _ai_builder_work_model(1)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", planner_TIMBER)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _ai_builder_work_works(model), _ai_builder_work_stockpile(),
		{"timber": 4}, {}, {}
	)

	assert_true((plan["orders"] as Array).is_empty(), "no national_bureaucracy")

func planner__seat_model(town_level: int, estate_level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [planner_SEAT, planner_SEAT_ESTATE, planner_SEAT_ESTATE_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Seat", tiles, Vector2.ZERO, 3, 1, true)
	province.town_tile = planner_SEAT
	province.capital_tile = planner_SEAT
	province.town_development = town_level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [planner_SEAT_ESTATE, planner_SEAT_ESTATE_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model

func planner__seat_works(model: MapModel, estate_level: int) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, planner_SEAT)
	for tile: Vector2i in [planner_SEAT_ESTATE, planner_SEAT_ESTATE_FAR]:
		if estate_level > 0:
			works.set_improvement(model, tile, estate_level)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works

func planner__seat_plan(town_level: int, estate_level: int) -> Dictionary:
	var model: MapModel = planner__seat_model(town_level, estate_level)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", planner_SEAT_ESTATE)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], planner__seat_works(model, estate_level),
		{"timber": 2, "lumber": 40, "castIron": 40}, {"timber": 4},
		{"national_bureaucracy": true}
	)

## Stores are short of timber, but a level-1 estate in a level-1 seat gathers
## nothing more at level 2: the town is the order that pays, so the Builder
## raises the town instead of buying a dead estate level.
func test_planner_a_town_capping_its_estates_is_raised_before_the_estate() -> void:
	var plan: Dictionary = planner__seat_plan(1, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), planner_SEAT)

## Once the estate is fully improved the town is the only order left, and it is
## raised even though its manufactures are still short of one four-ton run: the
## estate levels it unlocks are what the Builder is buying.
func test_planner_a_town_is_raised_for_the_estate_levels_it_unlocks() -> void:
	var plan: Dictionary = planner__seat_plan(1, LandWorks.MAX_IMPROVEMENT)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), planner_SEAT)

## A developed town no longer caps its estates, so the Builder raises the estate
## at once — the cap read must not idle a court that can gather.
func test_planner_a_developed_town_frees_the_estate_order() -> void:
	var plan: Dictionary = planner__seat_plan(CivilianWorkPlan.MAX_TOWN, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_improvement")
	assert_eq(Vector2i(orders[0]["tile"]), planner_SEAT_ESTATE)

## An estate held back by the town cap earns no shortage premium: an estate the
## crown can gather from wins the Builder even when its commodity is abundant.
func test_planner_a_capped_estate_earns_no_shortage_premium() -> void:
	var row: Dictionary = {
		"tile": planner_SEAT_ESTATE, "province": 0, "commodity": "timber", "level": 1,
		"tech_cap": 4, "terrain_cap": 4, "transport": 4, "town_cap": 1,
		"output": 1, "connected": true,
	}
	var open_row: Dictionary = row.duplicate()
	open_row["town_cap"] = 4
	open_row["output"] = 1

	assert_eq(AiBuilderWork.paid_gain(row), 0, "the town cap pays nothing more")
	assert_eq(AiBuilderWork.paid_gain(open_row), 1, "the next level pays")
	assert_eq(AiBuilderWork.town_unlocks([row], 0), 1, "the town unlocks one level")
	assert_eq(AiBuilderWork.town_unlocks([open_row], 0), 0, "a free estate unlocks nothing")

# --- test_ai_engineer_work ---

func _ai_engineer_work_context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": ai_engineer_work_CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": ai_engineer_work_BARE,
		"at_war": at_war,
	}

func planner__engineer_order(model: MapModel, works: LandWorks, at_war: bool = false) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_engineer_work_BARE)
	return planner_Engineer.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		ai_engineer_work_CivilianFixture.stockpile(), {}, {},
		_ai_engineer_work_context(at_war), {}
	))

## Every owned tile improved and ported, so the only work left is transport.
func _ai_engineer_work_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, ai_engineer_work_CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	return works

func test_planner_a_road_still_reaches_a_resource_without_one() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var order: Dictionary = planner__engineer_order(model, _ai_engineer_work_works(model))
	assert_eq(String(order.get("action", "")), "build_road")
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_ne(model.resource_at(tile.x, tile.y), MapModel.NO_ID, "the road reaches a resource")

func test_planner_a_coastal_province_without_a_port_gets_one() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	for tile: Vector2i in model.provinces[0].tiles:
		model.resource[model.index_of(tile.x, tile.y)] = MapModel.NO_ID
	var order: Dictionary = planner__engineer_order(model, LandWorks.new())
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_eq(String(order.get("action", "")), "build_port")
	assert_true(MapGeo.is_coastal_tile(model, tile.x, tile.y), "a port only rises on the coast")

func test_planner_an_invaded_court_prices_its_fort_with_wartime_urgency() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, ai_engineer_work_CivilianFixture.COAST_TILE)
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_engineer_work_BARE)
	var fort: Dictionary = planner_Engineer.fort_candidate(_work_query(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		ai_engineer_work_CivilianFixture.stockpile(), {}, {},
		_ai_engineer_work_context(true), {}
	))
	var road: Dictionary = planner__engineer_order(model, works)
	assert_eq(String(fort.get("action", "")), "build_fort")
	assert_eq(Vector2i(fort["tile"]), FortRules.site_tile(model, ai_engineer_work_CivilianFixture.PLAYER_PROVINCE))
	# An invaded court prices its fort above its other works as a floor: the fort
	# weight plus the wartime urgency, whatever the hinterland still owes.
	var weight: int = AiConfig.build(0, 1500).parameter("civilian.fort_weight")
	assert_true(int(fort["score"]) >= weight + 50, "the fort carries its wartime urgency")
	assert_eq(String(road.get("action", "")), "build_road")

func test_planner_the_engineer_never_offers_a_rail() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var works: LandWorks = _ai_engineer_work_works(model)
	works.set_transport(model, ai_engineer_work_CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	for at_war: bool in [false, true]:
		var order: Dictionary = planner__engineer_order(model, works, at_war)
		assert_ne(String(order.get("action", "")), "build_rail", "a rail is the Rail Builder's work")

func test_planner_no_engineer_work_without_a_config() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_engineer_work_BARE)
	assert_true(planner_Engineer.best_candidate(_work_query(
		null, model, unit, [unit] as Array, LandWorks.new(),
		ai_engineer_work_CivilianFixture.stockpile(), {}, {},
		_ai_engineer_work_context(), {}
	)).is_empty())

# --- test_ai_hospital_work ---

## A capital province with a seat and a second owned town province; no resource
## tiles and no coast, so an planner_Engineer's only other work is the town sweep.
func _ai_hospital_work_model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var capital_tiles: Array[Vector2i] = []
	var outer_tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 3:
				model.province[model.index_of(x, y)] = planner_CAPITAL_PROVINCE
				capital_tiles.append(tile)
			else:
				model.province[model.index_of(x, y)] = planner_OUTER_PROVINCE
				outer_tiles.append(tile)
	var capital := ProvinceState.create(
		planner_CAPITAL_PROVINCE, "Cádiz", capital_tiles, Vector2(1.0, 1.0),
		capital_tiles.size(), 0, true
	)
	capital.capital_tile = ai_hospital_work_CAPITAL
	capital.town_tile = ai_hospital_work_CAPITAL
	var outer := ProvinceState.create(
		planner_OUTER_PROVINCE, "Coro", outer_tiles, Vector2(4.0, 1.0),
		outer_tiles.size(), 0, false
	)
	outer.town_tile = planner_OUTER_TOWN
	model.provinces = [capital, outer]
	return model

func _ai_hospital_work_stockpile() -> Dictionary:
	return {"lumber": 20, "fabric": 20, "steel": 20, "castIron": 20}

func _ai_hospital_work_context(at_war: bool = true) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": planner_CAPITAL_PROVINCE,
		"capital_tile": ai_hospital_work_CAPITAL,
		"at_war": at_war,
	}

func planner__best(
	model: MapModel, tech_unlocked: Dictionary = planner_TECH, reserved: Dictionary = {}
) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	return AiHospitalWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), model, unit, [unit], LandWorks.new(),
		_ai_hospital_work_stockpile(), {}, tech_unlocked,
		_ai_hospital_work_context(), reserved
	))

func test_planner_the_seat_raises_the_first_hospital() -> void:
	var best: Dictionary = planner__best(_ai_hospital_work_model())
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ai_hospital_work_CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("lumber", 0)), 3)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("fabric", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 1, "a field hospital takes one turn")

func test_planner_the_seat_is_upgraded_before_a_new_province() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = planner__best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ai_hospital_work_CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("steel", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 2, "a general hospital takes two turns")

func test_planner_a_field_hospital_waits_while_its_tech_is_unknown() -> void:
	var best: Dictionary = planner__best(_ai_hospital_work_model(), {})
	assert_true(best.is_empty(), "Organised Regiments gates the first hospital")

func test_planner_a_general_hospital_waits_for_its_own_tech() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = planner__best(model, {"organised_regiments": true})
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), planner_OUTER_TOWN,
		"the gated upgrade gives way to a field hospital elsewhere"
	)

func test_planner_a_second_province_follows_the_seat() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var best: Dictionary = planner__best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), planner_OUTER_TOWN)

func test_planner_a_reserved_town_waits_its_turn() -> void:
	var model: MapModel = _ai_hospital_work_model()
	var reserved: Dictionary = {ai_hospital_work_CAPITAL: true}
	var best: Dictionary = planner__best(model, planner_TECH, reserved)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), planner_OUTER_TOWN)

func test_planner_a_built_out_court_raises_no_more() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(planner_OUTER_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	assert_true(planner__best(model).is_empty())

func test_planner_a_townless_province_is_skipped() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var bare := ProvinceState.create(
		2, "Wilds", [Vector2i(2, 2)] as Array[Vector2i], Vector2(2.0, 2.0),
		1, 0, false
	)
	model.provinces.append(bare)
	var best: Dictionary = planner__best(model)
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), planner_OUTER_TOWN,
		"only the province with a town can host a hospital"
	)

func test_planner_another_courts_province_is_never_planned() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(planner_OUTER_PROVINCE).owner = 1
	assert_true(planner__best(model).is_empty())

func test_planner_the_engineer_planner_raises_a_hospital_at_war() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _ai_hospital_work_stockpile(),
		{}, planner_TECH, _ai_hospital_work_context(true)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_hospital")
	assert_eq(Vector2i(orders[0]["tile"]), ai_hospital_work_CAPITAL)

func test_planner_peace_leaves_the_town_sweep_first() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(planner_CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _ai_hospital_work_stockpile(),
		{}, planner_TECH, _ai_hospital_work_context(false)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")

func test_planner_nothing_is_planned_without_a_world() -> void:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	assert_true(AiHospitalWork.best_candidate(_work_query(
		AiConfig.build(0, 1500), null, unit, [unit], null,
		_ai_hospital_work_stockpile(), {}, planner_TECH,
		_ai_hospital_work_context(), {}
	)).is_empty())

func test_planner_a_fort_always_holds_over_the_town_sweep() -> void:
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_fort"}, _ai_hospital_work_context(false)
	))
	assert_false(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _ai_hospital_work_context(false)
	))
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _ai_hospital_work_context(true)
	))
	assert_false(AiHospitalWork.holds_over_town_link({}, _ai_hospital_work_context(true)))

func test_planner_the_tie_break_is_row_major_then_action_name() -> void:
	var upper: Dictionary = {"action": "build_hospital", "tile": Vector2i(1, 2), "score": 40}
	var lower: Dictionary = {"action": "build_hospital", "tile": Vector2i(4, 3), "score": 40}
	var left: Dictionary = {"action": "build_hospital", "tile": Vector2i(2, 3), "score": 40}
	var early: Dictionary = {"action": "build_fort", "tile": Vector2i(1, 2), "score": 40}
	assert_eq(Vector2i(AiCivilianCandidate.better(lower, upper)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiCivilianCandidate.better(upper, lower)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiCivilianCandidate.better(lower, left)["tile"]), Vector2i(2, 3))
	assert_eq(Vector2i(AiCivilianCandidate.better(left, lower)["tile"]), Vector2i(2, 3))
	assert_eq(String(AiCivilianCandidate.better(upper, early)["action"]), "build_fort")
	assert_eq(String(AiCivilianCandidate.better(early, upper)["action"]), "build_fort")
	assert_eq(String(AiCivilianCandidate.better({}, upper)["action"]), "build_hospital")
	assert_eq(String(AiCivilianCandidate.better(upper, {})["action"]), "build_hospital")

# --- test_ai_town_roads ---

func _ai_town_roads_model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
	var province := ProvinceState.create(
		0, "Townshire", tiles, Vector2(2.0, 1.0), tiles.size(), 1, true
	)
	province.capital_tile = ai_town_roads_CAPITAL
	province.town_tile = ai_town_roads_TOWN
	model.provinces = [province]
	return model

func _ai_town_roads_stockpile() -> Dictionary:
	return {"lumber": 20, "castIron": 20}

func planner__connected(model: MapModel, tiles: Array[Vector2i]) -> Dictionary:
	var seen: Dictionary = {}
	for tile: Vector2i in tiles:
		seen[model.index_of(tile.x, tile.y)] = true
	return seen

func test_planner_an_unconnected_town_targets_its_own_tile_first() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], works, _ai_town_roads_stockpile(),
		{}, {}, {}, {}
	), planner__connected(model, [ai_town_roads_CAPITAL]))
	assert_eq(String(best.get("action", "")), "build_road")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ai_town_roads_TOWN)

func test_planner_the_next_step_follows_the_shortest_owned_path() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	works.set_transport(model, ai_town_roads_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], works, _ai_town_roads_stockpile(),
		{}, {}, {}, {}
	), planner__connected(model, [ai_town_roads_CAPITAL]))
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), Vector2i(3, 1))

func test_planner_a_connected_town_is_left_alone() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(),
		_ai_town_roads_stockpile(), {}, {}, {}, {}
	), planner__connected(model, [ai_town_roads_CAPITAL, ai_town_roads_TOWN]))
	assert_true(best.is_empty())

func test_planner_the_engineer_planner_emits_the_town_road_order() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], works, _ai_town_roads_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ai_town_roads_CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		model.resource_at(Vector2i(orders[0]["tile"]).x, Vector2i(orders[0]["tile"]).y),
		MapModel.NO_ID
	)

func test_planner_without_a_capital_network_no_order_is_offered() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(),
		_ai_town_roads_stockpile(), {}, {}, {}, {}
	), {}).is_empty())

func test_planner_a_reserved_town_is_left_for_another_crew() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(),
		_ai_town_roads_stockpile(), {}, {}, {}, {ai_town_roads_TOWN: true}
	), planner__connected(model, [ai_town_roads_CAPITAL])).is_empty())

func test_planner_a_foreign_town_is_ignored() -> void:
	var model: MapModel = _ai_town_roads_model()
	model.provinces[0].owner = 2
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(),
		_ai_town_roads_stockpile(), {}, {}, {}, {}
	), planner__connected(model, [ai_town_roads_CAPITAL])).is_empty())

func test_planner_missing_inputs_are_guarded() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		null, model, unit, [unit], LandWorks.new(), _ai_town_roads_stockpile(), {}, {}, {},
		{}
	), planner__connected(model, [ai_town_roads_CAPITAL])).is_empty())

func test_planner_a_reserved_path_tile_is_left_alone() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	works.set_transport(model, ai_town_roads_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], works, _ai_town_roads_stockpile(),
		{}, {}, {}, {Vector2i(3, 1): true}
	), planner__connected(model, [ai_town_roads_CAPITAL])).is_empty())

func test_planner_a_working_engineer_gets_no_second_order() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	unit.start_work("build_road", ai_town_roads_TOWN, 1)
	assert_true(AiTownRoads.best_candidate(_work_query(
		AiConfig.build(1, 1500), model, unit, [unit], LandWorks.new(),
		_ai_town_roads_stockpile(), {}, {}, {}, {}
	), planner__connected(model, [ai_town_roads_CAPITAL])).is_empty())

## Wiki: ai-architecture § Town-per-province roads — a town road outranks
## incidental works, so a resource road next to the capital never pre-empts the
## link that lets the Town rule connect the province's estates.
func test_planner_a_town_road_outranks_an_incidental_resource_road() -> void:
	var model: MapModel = _ai_town_roads_model()
	var grain: Vector2i = Vector2i(1, 1)
	model.resource[model.index_of(grain.x, grain.y)] = 4
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(), _ai_town_roads_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ai_town_roads_CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		Vector2i(orders[0]["tile"]), ai_town_roads_TOWN, "the town link comes before an incidental road"
	)

## Wiki: ai-architecture § Town-per-province roads — the court's own fort still
## comes first when it is invaded. The fort stands on the province's own site
## (CivilianWork sites it on the town), so this pins the choice, not the seat.
func test_planner_an_invaded_court_raises_its_fort_before_a_town_road() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(),
		{"lumber": 20, "castIron": 20, "bronze": 20}, {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ai_town_roads_CAPITAL,
			"at_war": true,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_fort")
	assert_eq(
		Vector2i(orders[0]["tile"]),
		FortRules.site_tile(model, 0),
		"the fort stands where the rules site it"
	)

# --- test_ai_civilian_dispatch ---

func _ai_civilian_dispatch_context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": ai_civilian_dispatch_CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": ai_civilian_dispatch_BARE,
		"at_war": at_war,
	}

func _ai_civilian_dispatch_plan(model: MapModel, unit: CivilianState, works: LandWorks) -> Dictionary:
	return planner_Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, works,
		ai_civilian_dispatch_CivilianFixture.stockpile(), {}, planner_RAIL_TECHS, _ai_civilian_dispatch_context()
	)

func planner__roaded_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, ai_civilian_dispatch_CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	works.set_transport(model, ai_civilian_dispatch_CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	return works

func test_planner_a_rail_builder_lays_a_rail_on_an_existing_road() -> void:
	var model: MapModel = ai_civilian_dispatch_CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", ai_civilian_dispatch_CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = _ai_civilian_dispatch_plan(model, unit, planner__roaded_works(model))
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1, "the planner_Engineer policy answers for a Rail Builder")
	assert_eq(String(orders[0]["action"]), "build_rail")
	assert_eq(Vector2i(orders[0]["tile"]), ai_civilian_dispatch_CivilianFixture.TIMBER_TILE)

func test_planner_a_rival_without_steam_never_orders_a_rail() -> void:
	var model: MapModel = ai_civilian_dispatch_CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", ai_civilian_dispatch_CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = planner_Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, planner__roaded_works(model),
		ai_civilian_dispatch_CivilianFixture.stockpile(), {}, {}, _ai_civilian_dispatch_context()
	)
	for order: Dictionary in plan["orders"]:
		assert_ne(String(order["action"]), "build_rail", "no rail without its tech")

func test_planner_every_dispatched_order_is_a_work_the_unit_may_do() -> void:
	var model: MapModel = ai_civilian_dispatch_CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, ai_civilian_dispatch_CivilianFixture.COAST_TILE)
	for type_id: String in ["builder", "engineer", "explorer", "rail_builder"]:
		var unit: CivilianState = CivilianState.create(1, 0, type_id, ai_civilian_dispatch_BARE)
		for order: Dictionary in _ai_civilian_dispatch_plan(model, unit, works)["orders"]:
			assert_true(
				CivilianCatalog.works(type_id).has(String(order["action"])),
				"%s may work %s" % [type_id, order["action"]]
			)

# --- from test_ai_objective_rules.gd ---
## The rival objective ledger.
## The rival objective ledger (docs/ai.md; issue #491 T1): one 0–100 currency,
## a rank pass and an allocate pass, the claims a court keeps, and the trace
## rows that explain a starved objective instead of hiding it.

const OBJ_OWNER: int = 0
const OBJ_RIVAL: int = 1
const OBJ_SEED: int = 1500


func _objective_config(faction: int = OBJ_OWNER) -> AiConfig:
	return AiConfig.build(faction, OBJ_SEED)


# --- the one currency --------------------------------------------------------


func test_every_planner_scale_normalizes_into_the_same_currency() -> void:
	assert_eq(AiUtility.clamp_utility(-10), 0)
	assert_eq(AiUtility.clamp_utility(140), 100)
	assert_eq(AiUtility.scale(50, 0, 100), 50)
	assert_eq(AiUtility.scale(0, 50, 150), 0)
	assert_eq(AiUtility.scale(150, 50, 150), 100)
	assert_eq(AiUtility.scale(7, 5, 5), 100, "a flat band tops out")
	assert_eq(AiUtility.ratio(1, 2), 50)
	assert_eq(AiUtility.ratio(3, 2), 100, "a ratio above the whole is clamped")
	assert_eq(AiUtility.ratio(0, 0), 0)
	assert_eq(AiUtility.ratio(2, 0), 100, "strength against nothing reads full")


func test_the_rank_modifier_is_per_mille_and_clamped() -> void:
	assert_eq(AiUtility.modified(80, 1000), 80)
	assert_eq(AiUtility.modified(80, 600), 48, "a war footing scales a voyage down")
	assert_eq(AiUtility.modified(80, 1500), 100, "a boost never passes the scale")
	assert_eq(AiUtility.modified(80, 0), 0)


# --- the allocate pass -------------------------------------------------------


func _hull_objective(objective_id: String, utility: int, hulls: int = 1) -> AiObjective:
	return AiObjective.create(objective_id, "expansion", utility, {"hull": hulls})


func test_claims_follow_rank_order() -> void:
	var top: AiObjective = _hull_objective("colonise.a", 80)
	var bottom: AiObjective = _hull_objective("colonise.b", 40)
	var report: Dictionary = AiObjectiveLedger.run([bottom, top], {"hull": 1})

	assert_eq(int(report["ranked"]), 2)
	assert_eq(int(report["funded"]), 1, "one hull funds exactly one voyage")
	assert_eq(top.status, AiObjective.STATUS_FUNDED)
	assert_eq(bottom.status, AiObjective.STATUS_DEFERRED)
	assert_eq(int(bottom.claim["hull"]), 0)
	assert_eq(int(bottom.shortfall()["hull"]), 1, "the shortfall is named")
	assert_eq(int(report["pools"]["hull"]), 0, "a grant spends the pool")


func test_a_deferred_objective_names_its_shortfall_in_the_line() -> void:
	var objective: AiObjective = AiObjective.create(
		"colonise.new_world", "expansion", 50, {"hull": 1, "civilian": 1}
	)
	var report: Dictionary = AiObjectiveLedger.run([objective], {"hull": 0, "civilian": 1})

	assert_eq(objective.status, AiObjective.STATUS_DEFERRED)
	assert_true(String(report["lines"][0]).contains("hull 0/1"))
	assert_true(String(report["lines"][0]).contains("civilian 1/1"))
	assert_eq(String(report["lines"][0]), "colonise.new_world u50 hull 0/1, civilian 1/1 deferred")


func test_a_blocked_objective_claims_nothing_and_keeps_its_reason() -> void:
	var pools: Dictionary = {"hull": 2}
	var blocked: AiObjective = _hull_objective("colonise.new_world", 50).block("no harbour")
	var report: Dictionary = AiObjectiveLedger.run([blocked], pools)

	assert_eq(blocked.status, AiObjective.STATUS_BLOCKED)
	assert_eq(int(report["blocked"]), 1)
	assert_eq(int(report["funded"]), 0)
	assert_eq(int(pools["hull"]), 2, "a blocked aim spends nothing")
	assert_eq(String(report["lines"][0]), "colonise.new_world u50 hull 0/1 blocked (no harbour)")


func test_children_are_walked_after_their_parent() -> void:
	var child: AiObjective = _hull_objective("expedition.hull", 60)
	var parent: AiObjective = AiObjective.create(
		"colonise.new_world", "expansion", 80, {"hull": 1}
	).with_child(child)
	var order: Array[AiObjective] = AiObjectiveLedger.walk([parent])

	assert_eq(order.size(), 2)
	assert_eq(order[0].id, "colonise.new_world")
	assert_eq(order[1].id, "expedition.hull")


func test_the_same_state_ranks_the_same_way() -> void:
	var first: Array[AiObjective] = [
		_hull_objective("b", 50), _hull_objective("a", 50), _hull_objective("c", 90),
	]
	var second: Array[AiObjective] = [
		_hull_objective("c", 90), _hull_objective("b", 50), _hull_objective("a", 50),
	]
	var left: Array[AiObjective] = AiObjectiveLedger.rank(first)
	var right: Array[AiObjective] = AiObjectiveLedger.rank(second)

	assert_eq(left[0].id, "c")
	assert_eq(left[1].id, "a", "the id breaks a utility tie")
	assert_eq(left[2].id, "b")
	assert_eq(left[1].id, right[1].id, "order of emission never decides the rank")


func test_a_modifier_reorders_the_rank_without_deleting_an_objective() -> void:
	var colony: AiObjective = _hull_objective("colonise.new_world", 50)
	var fleet: AiObjective = AiObjective.create("navy.sortie", "naval", 60, {"hull": 1})
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank(
		[colony, fleet], {"expansion": 600, "naval": 1400}
	)

	assert_eq(ranked[0].id, "navy.sortie", "the war footing lifts the fleet")
	assert_eq(ranked[1].id, "colonise.new_world", "the voyage stays ranked, only cheaper")


# --- the emitter -------------------------------------------------------------


func _readings() -> Dictionary:
	return {
		"posture": AiPhasePlanner.PHASE_PEACE,
		"at_war": false,
		"war_desire": 40,
		"regiments": 1,
		"muster_due": true,
		"muster_floor": 300,
		"ships": 2,
		"warships": 4,
		"warship_price": 5500,
		"warship_open": true,
		"hostile_ships": 0,
		"hostile_warships": 0,
		"treasury": 2000,
		"reserve": 500,
		"goal": AiIncome.GOAL_SPEND,
		"colony_target": true,
		"harbour": true,
		"idle_hulls": 1,
		"explorer_ready": true,
		"voyage_afloat": false,
		"cargo_shortfall": 0,
		"research_slots": 1,
		"research_funding": 2,
		"research_cost": 150,
	}


## Walks the ledger tree: T2 prices the expedition on its children.
func _by_id(objectives: Array[AiObjective], objective_id: String) -> AiObjective:
	for objective: AiObjective in objectives:
		if objective.id == objective_id:
			return objective
		var found: AiObjective = _by_id(objective.children, objective_id)
		if found != null:
			return found
	return null


## Flattens the trace rows to id → status.
func _statuses(rows: Variant, out: Dictionary) -> void:
	for raw: Variant in rows:
		var row: Dictionary = raw
		out[String(row["id"])] = String(row["status"])
		_statuses(row.get("children", []), out)


func _child_ids(objective: AiObjective) -> Array[String]:
	var ids: Array[String] = []
	for child: AiObjective in objective.children:
		ids.append(child.id)
	return ids


func test_the_plan_prices_the_expedition_the_muster_and_the_order() -> void:
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(_readings())

	var colony: AiObjective = _by_id(objectives, "colonise.new_world")
	assert_true(colony != null, "the expedition is always priced while it has a target")
	assert_eq(int(colony.utility), AiObjectivesPlan.W_PROVINCES_NEW)
	assert_eq(_child_ids(colony), ["expedition.hull", "expedition.explorer"])
	assert_eq(int(_by_id(objectives, "expedition.hull").cost["hull"]), 1)
	assert_eq(int(_by_id(objectives, "expedition.explorer").cost["civilian"]), 1)
	assert_eq(_by_id(objectives, "muster.line").cost["regiment"], 1)
	assert_eq(int(_by_id(objectives, "war.declare").cost["orders"]), 1)
	assert_eq(int(_by_id(objectives, "research.study").utility), 55, "the funding step lifts the study")


## The #474 clause-1 un-latch (issue #807): while a line is due the seat guard
## claims no regiment slot — the muster's regiment *is* the Home Army — so the
## muster's own claim prices the seat's garrison instead of a phantom 90-point
## claim holding it shut every warring turn.
func test_the_seat_guard_stands_down_while_a_line_is_due() -> void:
	var defend: AiObjective = _by_id(AiObjectivesPlan.build(_readings()), "defend.seat")
	assert_true(
		defend.cost.is_empty(),
		"a due line takes the seat's own regiment slot"
	)
	var standing: Dictionary = _readings()
	standing["at_war"] = true
	standing["muster_due"] = false
	defend = _by_id(AiObjectivesPlan.build(standing), "defend.seat")
	assert_eq(
		int(defend.cost.get("regiment", 0)), 1,
		"at war with no line due the guard still holds the seat"
	)


func test_a_charted_tribe_prices_the_envoy_chain_it_is_buying() -> void:
	var readings: Dictionary = _readings()
	readings["tribe_target"] = FactionCatalog.tribe_ids()[0]
	readings["tribe_stage"] = DiplomacyCatalog.STAGE_EMBASSY
	readings["tribe_stage_cost"] = DiplomacyCatalog.EMBASSY_COST
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)
	var chain: AiObjective = _by_id(objectives, "colonise.tribe_chain")

	assert_true(chain != null, "a colony in reach is a priced aim")
	assert_eq(int(chain.utility), AiObjectiveExpeditionPlan.W_TRIBE_COLONY)
	assert_eq(int(chain.cost["treasury"]), DiplomacyCatalog.EMBASSY_COST)
	assert_eq(int(chain.cost["orders"]), 1, "the chain spends the court's one order")
	var report: Dictionary = AiObjectiveLedger.run(
		objectives, {"treasury": 5000, "hull": 1, "civilian": 1, "orders": 1}
	)
	assert_true(chain.status == AiObjective.STATUS_FUNDED, "the purse can buy this step")
	assert_eq(
		_by_id(objectives, "war.declare").status, AiObjective.STATUS_DEFERRED,
		"the envoy chain outranks a war the court does not need"
	)
	var line: String = ""
	for raw: String in report["lines"]:
		if raw.begins_with("colonise.tribe_chain"):
			line = raw
	assert_true(line.ends_with("funded"), "the trace says the chain is bought")


func test_a_court_with_no_charted_tribe_prices_no_chain() -> void:
	assert_eq(_by_id(AiObjectivesPlan.build(_readings()), "colonise.tribe_chain"), null)


## The deed is an aim in the ledger: priced on the purse it must hold, ranked
## below every other treasury claim so it never takes the chest the muster, the
## yard or a study is saving for (issue #724 task 3).
func test_the_deed_the_court_saves_for_is_a_priced_aim() -> void:
	var readings: Dictionary = _readings()
	readings["deed_price"] = 750
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)
	var deed: AiObjective = _by_id(objectives, "market.deed")

	assert_true(deed != null, "a priced deed is an aim")
	assert_eq(int(deed.utility), AiObjectiveTreasuryPlan.W_DEED)
	assert_eq(int(deed.cost["treasury"]), 750, "the published 15 x base price")
	AiObjectiveLedger.run(
		objectives,
		{"treasury": 500, "regiment": 1, "labour": 1, "orders": 1, "civilian": 1, "hull": 1}
	)
	assert_true(
		_by_id(objectives, "muster.line").status == AiObjective.STATUS_FUNDED,
		"the deed never takes the purse the muster is saving for"
	)
	assert_true(deed.status == AiObjective.STATUS_DEFERRED, "the purse is short of it")
	assert_true(int(deed.shortfall().get("treasury", 0)) > 0, "the row names the gap")


## A deed the court has stalled on past the blocked bar names the stall instead
## of saving in silence (issue #724 task 3, #603).
func test_a_deed_stalled_past_the_blocked_bar_names_its_stall() -> void:
	var readings: Dictionary = _readings()
	readings["deed_price"] = 750
	readings["blockings"] = {"market.deed": 41}
	var deed: AiObjective = _by_id(AiObjectivesPlan.build(readings), "market.deed")

	assert_true(deed.status == AiObjective.STATUS_BLOCKED)
	assert_eq(String(deed.blocked), "the deed is out of reach 41 turns")


func test_a_court_with_no_charted_deed_prices_no_aim() -> void:
	assert_eq(_by_id(AiObjectivesPlan.build(_readings()), "market.deed"), null)


# --- the deferred-aim escalation (issue #603) --------------------------------


func planner__row(id: String, status: String, shortfall: Dictionary = {}) -> Dictionary:
	var row: Dictionary = {"id": id, "status": status}
	if not shortfall.is_empty():
		row["shortfall"] = shortfall
	return row


func test_a_stalled_aim_counts_its_deferred_turns() -> void:
	var records: Dictionary = AiDeferral.note(
		{}, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})]
	)
	assert_eq(AiDeferral.stall(records, "muster.line"), 1)
	# Standing still is the same stall — and so is falling further behind: the
	# count only restarts when the shortfall actually shrinks (issue #603).
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})]
	)
	assert_eq(AiDeferral.stall(records, "muster.line"), 2)
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2200})]
	)
	assert_eq(AiDeferral.stall(records, "muster.line"), 3)


func test_an_aim_that_closes_its_shortfall_restarts_the_stall() -> void:
	var records: Dictionary = AiDeferral.note(
		{}, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})]
	)
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})]
	)
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2000})]
	)
	assert_eq(
		AiDeferral.stall(records, "muster.line"), 1,
		"progress is not a stall: the count restarts"
	)


## A shortfall that wobbles above the best gap the stall has seen is no
## progress: one ducat of noise must not reset the escalation bar forever, or
## a court whose chest oscillates never escalates and its worker training
## freezes for the rest of the campaign (issue #603, the 2026-11-15 full-AI
## measurement).
func test_a_wobble_above_the_best_gap_is_still_a_stall() -> void:
	var records: Dictionary = AiDeferral.note(
		{}, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2400})]
	)
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2300})]
	)
	assert_eq(AiDeferral.stall(records, "muster.line"), 1, "a new low is progress")
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2450})]
	)
	assert_eq(
		AiDeferral.stall(records, "muster.line"), 2,
		"the wobble is above the best gap: the count continues"
	)
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2350})]
	)
	assert_eq(
		AiDeferral.stall(records, "muster.line"), 3,
		"a shrink that stops above the best gap is still the stall"
	)
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2200})]
	)
	assert_eq(
		AiDeferral.stall(records, "muster.line"), 1,
		"a shortfall below the best the stall has seen restarts it"
	)


func test_a_funded_or_absent_aim_clears_its_stall() -> void:
	var records: Dictionary = AiDeferral.note(
		{}, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})]
	)
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_FUNDED, {"treasury": 0})]
	)
	assert_eq(AiDeferral.stall(records, "muster.line"), 0, "funded ends the stall")
	records = AiDeferral.note(
		records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})]
	)
	# The note rebuilds from this turn's rows, so an aim the court no longer
	# emits (at target, say) leaves no record behind.
	records = AiDeferral.note(records, [])
	assert_eq(AiDeferral.stall(records, "muster.line"), 0)


func test_a_starved_parent_carries_no_stall_of_its_own() -> void:
	# The parent names the child that starved it; the child's shortfall is the
	# stall the tracker follows, so the parent's empty shortfall counts nothing.
	var parent: Dictionary = planner__row("colonise.new_world", AiObjective.STATUS_DEFERRED)
	parent["children"] = [
		planner__row("expedition.hull", AiObjective.STATUS_DEFERRED, {"hull": 1}),
	]
	var records: Dictionary = AiDeferral.note({}, [parent])
	assert_eq(AiDeferral.stall(records, "colonise.new_world"), 0)
	assert_eq(AiDeferral.stall(records, "expedition.hull"), 1)


func test_a_blocked_aim_keeps_the_stall_its_reason_names() -> void:
	# An escalation-blocked reading keeps the count (so the escalation stays
	# applied while the aim stays out of reach); a rule-blocked aim never had a
	# record to keep.
	var records: Dictionary = AiDeferral.note(
		{}, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})]
	)
	records = AiDeferral.note(records, [planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100})])
	records = AiDeferral.note(records, [planner__row("muster.line", AiObjective.STATUS_BLOCKED)])
	assert_eq(
		AiDeferral.stall(records, "muster.line"), 2,
		"blocked keeps the stall it names"
	)
	records = AiDeferral.note({}, [planner__row("expedition.hull", AiObjective.STATUS_BLOCKED)])
	assert_eq(AiDeferral.stall(records, "expedition.hull"), 0)


func test_the_escalated_map_names_the_aims_past_the_bar() -> void:
	var records: Dictionary = {}
	var rows: Array = []
	for turn in 12:
		rows.append(planner__row("muster.line", AiObjective.STATUS_DEFERRED, {"treasury": 2100}))
		records = AiDeferral.note(records, rows)
	var escalated: Dictionary = AiDeferral.escalated(records, 10)
	assert_true(escalated.has("muster.line"), "a 12-turn stall escalates")
	assert_eq(int(escalated["muster.line"]), 12)
	assert_true(AiDeferral.escalated(records, 13).is_empty(), "13 turns would not")
	assert_true(
		AiDeferral.escalated(records, 1).has("muster.line"),
		"every recorded stall is at least 1"
	)


func test_a_muster_stalled_past_the_blocked_bar_names_its_reason() -> void:
	# The escalation's explicit terminal reading: a stall past the blocked bar
	# is a blocked row with its reason, never another silent deferred line.
	var readings: Dictionary = _readings()
	readings["blockings"] = {"muster.line": 41}
	var muster: AiObjective = _by_id(AiObjectivesPlan.build(readings), "muster.line")
	assert_eq(muster.status, AiObjective.STATUS_BLOCKED)
	assert_true(String(muster.blocked).contains("41"), "the stall length is named")
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), {"treasury": 2000, "regiment": 1, "labour": 1, "orders": 1}
	)
	assert_eq(int(report["blocked"]), 1, "a blocked muster claims nothing")

	readings["blockings"] = {}
	assert_eq(
		String(_by_id(AiObjectivesPlan.build(readings), "muster.line").blocked), "",
		"a stall below the bar stays a deferred row"
	)


func test_a_yard_stalled_past_the_blocked_bar_names_its_reason() -> void:
	# A warship build the court cannot reach names the stall (issue #603);
	# the chest keeps its own reach rule and the launch its own gate.
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["posture"] = AiPhasePlanner.PHASE_WAR
	readings["war_desire"] = 60
	readings["warships"] = 0
	readings["warship_price"] = 5500
	readings["warship_open"] = true
	readings["hostile_ships"] = 3
	readings["hostile_warships"] = 2
	readings["blockings"] = {"navy.build": 45}
	var build: AiObjective = _by_id(AiObjectivesPlan.build(readings), "navy.build")
	assert_ne(build, null)
	assert_eq(build.status, AiObjective.STATUS_BLOCKED)
	assert_true(String(build.blocked).contains("45"), "the stall length is named")

	readings["blockings"] = {}
	assert_eq(
		String(_by_id(AiObjectivesPlan.build(readings), "navy.build").blocked), "",
		"a stall below the bar stays a deferred row"
	)

	# The naming rides the chest's own valve (issue #1275): a line no longer
	# due — the fill the stand-down freed has closed the muster — reads the
	# bank again, the frozen stall its history.
	readings["blockings"] = {"navy.build": 45}
	readings["muster_due"] = false
	assert_eq(
		String(_by_id(AiObjectivesPlan.build(readings), "navy.build").blocked), "",
		"the line closed: the resumed bank is named, not the old stall"
	)


func test_an_unpayable_study_reads_blocked_not_funded() -> void:
	# A study the purse cannot fund must never read `funded` at zero gold: the
	# refusal the planner made is the row's reason (issue #590).
	var readings: Dictionary = _readings()
	readings["research_cost"] = 50
	readings["research_refusal"] = "purse under half the cash floor"
	var study: AiObjective = _by_id(AiObjectivesPlan.build(readings), "research.study")
	assert_eq(study.status, AiObjective.STATUS_BLOCKED)
	assert_eq(String(study.blocked), "purse under half the cash floor")
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), {"treasury": 40, "orders": 1, "hull": 1, "civilian": 1}
	)
	assert_eq(String(study.status), AiObjective.STATUS_BLOCKED, "a blocked study funds nothing")
	assert_true((study.claim as Dictionary).is_empty(), "a blocked study claims nothing")



func test_a_war_footing_prices_the_peace_window_and_the_sortie() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["posture"] = AiPhasePlanner.PHASE_WAR
	readings["war_desire"] = 70
	readings["hostile_ships"] = 3
	readings["hostile_warships"] = 3
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)

	assert_eq(int(_by_id(objectives, "peace.window").utility), 30)
	assert_true(
		_by_id(objectives, "colonise.new_world").requires.has("peace.window"),
		"the expedition waits on the court's one peace window, not a second order"
	)
	assert_true(_by_id(objectives, "navy.sortie") != null)
	assert_eq(_by_id(objectives, "navy.build"), null, "a court with hulls sorties instead of building")


func test_a_court_with_no_harbour_blocks_the_hull_with_a_reason() -> void:
	var readings: Dictionary = _readings()
	readings["harbour"] = false
	var hull: AiObjective = _by_id(AiObjectivesPlan.build(readings), "expedition.hull")

	assert_eq(hull.status, AiObjective.STATUS_BLOCKED)
	assert_eq(hull.blocked, "no harbour")


func test_a_starved_expedition_names_the_child_it_lacks() -> void:
	# No squadron to spare: the hull child defers and the trace says so, instead
	# of the voyage vanishing without a word (issue #476, #497).
	var readings: Dictionary = _readings()
	readings["idle_hulls"] = 0
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), {"hull": 0, "civilian": 1, "orders": 1}
	)
	var line: String = ""
	for raw: Variant in report["lines"]:
		if String(raw).begins_with("expedition.hull"):
			line = String(raw)

	assert_true(line.contains("deferred"), "the starved hull is reported: %s" % line)
	assert_true(line.contains("hull 0/1"), "with its shortfall: %s" % line)


func test_a_court_with_no_fighting_hull_lays_one_down() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["warships"] = 0
	readings["hostile_warships"] = 2
	readings["treasury"] = 5500
	var build: AiObjective = _by_id(AiObjectivesPlan.build(readings), "navy.build")

	assert_true(build != null, "a court at war with no fighting hull builds one")
	assert_eq(int(build.utility), AiObjectiveNavyPlan.W_NAVY_BUILD, "the yard leads")
	assert_eq(int(build.cost["treasury"]), 5500, "priced at the cheapest warship")
	assert_false(
		(build.cost as Dictionary).has("hull"),
		"the yard founds its own slip, so the build claims no idle hull (#484)"
	)


## Issue #591: a chest the court has not reached yet yields to the muster in the
## ledger too, so the purse the yard's phantom price pinned goes to the line the
## court can actually raise. A court that still has a fighting hull is the case;
## a fleetless rebuild keeps the yard ahead (#484).
func test_a_yard_price_out_of_reach_ranks_below_the_muster() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["warships"] = 1
	readings["hostile_warships"] = 2
	readings["treasury"] = 5342
	readings["muster_floor"] = 2400
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)
	var build: AiObjective = _by_id(objectives, "navy.build")
	var muster: AiObjective = _by_id(objectives, "muster.line")

	assert_true(build != null, "the yard is still the court's aim")
	assert_eq(
		int(build.utility), AiObjectiveNavyPlan.W_NAVY_BUILD_WAITING,
		"but the yard waits behind the army it would starve"
	)
	assert_true(
		int(muster.utility) > int(build.utility),
		"so the ledger funds the regiment first"
	)
	var report: Dictionary = AiObjectiveLedger.run(
		objectives,
		{"treasury": 5342, "regiment": 2, "labour": 3, "hull": 1, "civilian": 1, "orders": 1}
	)
	var statuses: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		statuses[String(row["id"])] = String(row["status"])
	assert_eq(String(statuses["muster.line"]), AiObjective.STATUS_FUNDED, "the line musters")
	assert_eq(
		String(statuses["navy.build"]), AiObjective.STATUS_DEFERRED,
		"and the hull it cannot fill declares its shortfall instead"
	)

	# A court that already holds the yard's price is no longer beyond reach.
	readings["treasury"] = 5500
	assert_true(
		int(_by_id(AiObjectivesPlan.build(readings), "navy.build").utility)
		> AiObjectiveNavyPlan.W_NAVY_BUILD_WAITING,
		"the chest is in hand: the yard is no longer parked behind the line"
	)
	# Fleetless rebuild never yields the yard to the muster (#484).
	readings["warships"] = 0
	readings["treasury"] = 5342
	assert_eq(
		int(_by_id(AiObjectivesPlan.build(readings), "navy.build").utility),
		AiObjectiveNavyPlan.W_NAVY_BUILD,
		"a lost last sloop keeps the yard ahead of the line"
	)


## Issue #474 clause 2 / #1143: the muster's cloth stays on `reserve.muster` —
## the ranked claim the market keeps stocked — so the ledger aim prices the
## purse, the hand and the regiment and funds on a full purse even while the
## store is short of cloth (a banked court cannot buy feedstock, and a whole
## line starved thirty turns behind its own cloth row). The muster's own gate
## still refuses a raise the stores cannot pay, so a funded aim is never a
## false 'raised' reading.
func test_the_muster_aim_funds_on_a_full_purse_without_cloth() -> void:
	var readings: Dictionary = _readings()
	readings["muster_row"] = {"fabric": 1}
	readings["muster_floor"] = 2400
	readings["treasury"] = 5000
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)
	var muster: AiObjective = _by_id(objectives, "muster.line")

	assert_eq(int(muster.cost["treasury"]), 2400, "the ledger prices the war chest")
	assert_false(
		(muster.cost as Dictionary).has("fabric"),
		"the pattern's row is reserve.muster's claim, not the aim's blocker"
	)
	AiObjectiveLedger.run(
		objectives, {"treasury": 5000, "regiment": 2, "labour": 3, "fabric": 0}
	)
	assert_eq(
		muster.status, AiObjective.STATUS_FUNDED,
		"a full purse funds the line; the muster gate refuses a clothless raise"
	)


## A court standing under its target whose muster row is closed by the muster's
## own gate still prints the aim — blocked with the gate's words — so a silent
## absence beside the navy chest cannot hide the starvation (issue #1143).
func test_a_gated_muster_row_names_its_gate() -> void:
	var readings: Dictionary = _readings()
	readings["muster_due"] = false
	readings["muster_gate"] = "the labour floor holds: no spare hand for the levy"
	var blocked: AiObjective = _by_id(AiObjectivesPlan.build(readings), "muster.line")
	assert_true(blocked != null, "the aim is printed, not silent")
	assert_eq(blocked.status, AiObjective.STATUS_BLOCKED)
	assert_eq(
		blocked.blocked, "the labour floor holds: no spare hand for the levy",
		"the trace names the gate that closed the row"
	)
	# At target (no gate named) the row is genuinely quiet.
	var settled: Dictionary = _readings()
	settled["muster_due"] = false
	settled["muster_gate"] = ""
	assert_true(
		_by_id(AiObjectivesPlan.build(settled), "muster.line") == null,
		"at target the muster is quiet"
	)


## A court whose techs open no warship says so instead of claiming a hull it can
## never lay — the trace used to read `funded` forever (issue #484). The chest
## is still priced so the money goal can save while research opens the door.
func test_a_court_with_no_warship_open_blocks_the_build() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["warships"] = 0
	readings["hostile_warships"] = 2
	readings["warship_price"] = 5500
	readings["warship_open"] = false
	var build: AiObjective = _by_id(AiObjectivesPlan.build(readings), "navy.build")

	assert_true(build != null, "the yard is still the court's aim")
	assert_eq(build.status, AiObjective.STATUS_BLOCKED)
	assert_eq(build.blocked, "no warship its techs open")


func test_a_court_outmatched_on_its_own_coast_replaces_before_it_expands() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["warships"] = 1
	readings["hostile_warships"] = 3
	var build: AiObjective = _by_id(AiObjectivesPlan.build(readings), "navy.build")

	assert_true(build != null, "outmatched, the court replaces its hulls")
	assert_true(
		int(build.utility) > int(AiObjectiveNavyPlan.W_NAVY),
		"and the replacement outranks a sortie"
	)


func test_a_court_at_peace_with_no_fighting_hull_still_rebuilds() -> void:
	var readings: Dictionary = _readings()
	readings["warships"] = 0
	readings["warship_open"] = true
	var build: AiObjective = _by_id(AiObjectivesPlan.build(readings), "navy.build")
	assert_true(build != null, "a lost last warship is replaced even at peace")


func test_a_court_at_peace_with_hulls_lays_down_nothing() -> void:
	var readings: Dictionary = _readings()
	readings["warships"] = 2
	assert_eq(_by_id(AiObjectivesPlan.build(readings), "navy.build"), null)


## A colonist already on the far shore is the voyage's progress, not a missing
## Explorer: the child that musters a new one is not blocked, and the parent
## prices the protected voyage instead (#497).
func test_a_colonist_ashore_is_the_voyage_in_progress() -> void:
	var readings: Dictionary = _readings()
	readings["explorer_ready"] = false
	readings["voyage_abroad"] = true
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)
	var colony: AiObjective = _by_id(objectives, "colonise.new_world")

	assert_eq(
		_child_ids(colony), ["expedition.hull", "expedition.explorer", "expedition.voyage"],
		"the landed colonist keeps the voyage priced"
	)
	assert_eq(_by_id(objectives, "expedition.explorer").status, AiObjective.STATUS_RANKED)
	var report: Dictionary = AiObjectiveLedger.run(objectives, {"hull": 1, "civilian": 1})
	assert_eq(
		_by_id(objectives, "colonise.new_world").status, AiObjective.STATUS_FUNDED,
		"a funded hull and a landed colonist leave nothing deferred"
	)


## An Explorer ashore where the crown owns no land cannot found a province (a
## Builder needs crown land) and cannot board again (docking needs a crown port),
## so the expedition is over: the aim is blocked with the reason instead of
## pricing a voyage that will never sail (issue #602).
func test_a_stranded_explorer_blocks_the_expedition() -> void:
	var readings: Dictionary = _readings()
	readings["voyage_abroad"] = true
	readings["voyage_stranded"] = true
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)
	var colony: AiObjective = _by_id(objectives, "colonise.new_world")

	assert_eq(colony.status, AiObjective.STATUS_BLOCKED)
	assert_eq(colony.blocked, "the Explorer is ashore with no crown land")
	assert_eq(_child_ids(colony).size(), 0, "no hull and no colonist are wanted")
	var report: Dictionary = AiObjectiveLedger.run(objectives, {"hull": 1, "civilian": 1})
	assert_eq(
		_by_id(objectives, "colonise.new_world").status, AiObjective.STATUS_BLOCKED,
		"the allocate pass leaves the reason in place"
	)
	var named: bool = false
	for line: Variant in report["lines"]:
		if String(line).contains("no crown land"):
			named = true
	assert_true(named, "the trace names the strand")


## The adapter reads an Explorer ashore where the crown owns nothing as a
## stranded expedition (issue #602), not as a voyage under way (#497).
func test_the_adapter_reads_a_stranded_explorer() -> void:
	var play: PlaySession = _objective_session(_court())
	play.civilian_layer.units.clear()
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	play.civilian_layer.regions.set_region(
		1, [CivilianState.create(2, OBJ_OWNER, "explorer", Vector2i(0, 0))]
	)
	var report: Dictionary = MapPlayObjectivesAi.run(play)[OBJ_OWNER]
	var colony: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.new_world":
			colony = row
	assert_false(colony.is_empty(), "the court still prices its expedition")
	assert_eq(String(colony["status"]), AiObjective.STATUS_BLOCKED)
	assert_eq(
		String(colony.get("blocked", "")), "the Explorer is ashore with no crown land",
		"the aim names the strand"
	)
	assert_eq((colony.get("children", []) as Array).size(), 0, "no sailing is priced")
	play.ship_layer.free()
	play.civilian_layer.free()


## A claim crew waiting at home keeps the expedition alive: the Merchant sails
## after the Explorer, so an Explorer ashore with no crown land is not a strand
## while that crew stands ready (#1127).
func test_the_adapter_keeps_the_expedition_alive_for_the_claim_crew() -> void:
	var play: PlaySession = _objective_session(_court())
	play.civilian_layer.units.clear()
	play.civilian_layer.units.append(
		CivilianState.create(4, OBJ_OWNER, "merchant", Vector2i(0, 0))
	)
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	play.civilian_layer.regions.set_region(
		1, [CivilianState.create(2, OBJ_OWNER, "explorer", Vector2i(0, 0))]
	)
	var report: Dictionary = MapPlayObjectivesAi.run(play)[OBJ_OWNER]
	var colony: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.new_world":
			colony = row
	assert_false(colony.is_empty(), "the court still prices its expedition")
	assert_eq(
		String(colony["status"]), AiObjective.STATUS_FUNDED,
		"the claim crew still has a voyage to sail"
	)
	# The claim has sailed and another Merchant idles at home: one of each kind
	# afloat, so no third voyage is priced and the strand is named again (#602).
	play.civilian_layer.regions.set_region(1, [
		CivilianState.create(2, OBJ_OWNER, "explorer", Vector2i(0, 0)),
		CivilianState.create(3, OBJ_OWNER, "merchant", Vector2i(0, 0)),
	])
	play.civilian_layer.units.clear()
	play.civilian_layer.units.append(
		CivilianState.create(5, OBJ_OWNER, "merchant", Vector2i(0, 0))
	)
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	report = MapPlayObjectivesAi.run(play)[OBJ_OWNER]
	colony = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.new_world":
			colony = row
	assert_eq(
		String(colony["status"]), AiObjective.STATUS_BLOCKED,
		"a claim already ashore strands the expedition"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## A Merchant ashore is still the voyage's progress (#497): the deeds it buys
## are what founds the colony, so the expedition stays funded.
func test_the_adapter_reads_the_merchant_ashore_as_progress() -> void:
	var play: PlaySession = _objective_session(_court())
	play.civilian_layer.units.clear()
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	play.civilian_layer.regions.set_region(
		1, [CivilianState.create(3, OBJ_OWNER, "merchant", Vector2i(0, 0))]
	)
	var report: Dictionary = MapPlayObjectivesAi.run(play)[OBJ_OWNER]
	var colony: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.new_world":
			colony = row
	assert_false(colony.is_empty(), "the court still prices its expedition")
	assert_eq(String(colony["status"]), AiObjective.STATUS_FUNDED)
	var voyage: bool = false
	for child: Dictionary in colony.get("children", []):
		if String(child["id"]) == "expedition.voyage":
			voyage = true
	assert_true(voyage, "the voyage child stands in for the landed colonist")
	play.ship_layer.free()
	play.civilian_layer.free()


## The adapter prices the Tribe the court is drawing in: a charted shore and a
## purse that covers the next envoy step put the chain in the ledger
## (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
func test_the_adapter_reads_a_charted_tribe_as_a_colony_in_reach() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var state: DiplomacyState = _court()
	state.ensure_relation(OBJ_OWNER, tribe, 1).score = 55.0
	state.set_overture(OBJ_OWNER, tribe, DiplomacyCatalog.STAGE_CONSULATE)
	var play: PlaySession = _objective_session(state)
	play.ai.economy_for(OBJ_OWNER).treasury = 20000
	var new_world: MapModel = play.world.region(WorldMap.NEW_WORLD)
	var shore: Array[Vector2i] = [Vector2i(0, 0)]
	new_world.provinces = [
		ProvinceState.create(0, "Shore", shore, Vector2.ZERO, 1, tribe, false)
	]
	var report: Dictionary = MapPlayObjectivesAi.run(play)[OBJ_OWNER]
	var chain: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.tribe_chain":
			chain = row
	assert_false(chain.is_empty(), "the envoy chain is priced")
	assert_eq(int(chain["utility"]), AiObjectiveExpeditionPlan.W_TRIBE_COLONY)
	assert_eq(int(chain["cost"]["treasury"]), DiplomacyCatalog.EMBASSY_COST)
	assert_ne(String(chain["status"]), AiObjective.STATUS_BLOCKED, "the shore and the purse both stand")
	play.ship_layer.free()
	play.civilian_layer.free()


# --- the adapter and the trace ----------------------------------------------

func _court() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(OBJ_OWNER, OBJ_RIVAL, 1)
	return state


func _objective_session(diplomacy: DiplomacyState) -> PlaySession:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(Vector2i(x, y))
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var province := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), OBJ_OWNER, true
	)
	province.capital_tile = Vector2i(0, 0)
	province.port_tile = Vector2i(0, 1)
	province.coastal = true
	model.provinces = [province]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	var new_world := MapModel.new()
	new_world.setup(3, 2)
	new_world.region_id = WorldMap.NEW_WORLD
	new_world.region_key = "new_world"
	var world := WorldMap.new()
	world.add_region(model)
	world.add_region(new_world)
	var play := PlaySession.new()
	play.player_faction = OBJ_RIVAL
	play.map_seed = OBJ_SEED
	play.world = world
	play.model = model
	play.diplomacy = diplomacy
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = model
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [FleetState.in_port(1, OBJ_OWNER, 0)])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = model
	play.civilian_layer.units = [CivilianState.create(1, OBJ_OWNER, "explorer", Vector2i(0, 0))]
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	play.civilian_layer.regions.set_region(1, [])
	play.ensure_ai()
	return play


func test_the_adapter_stamps_a_ledger_for_every_planning_court() -> void:
	var play: PlaySession = _objective_session(_court())
	var ledgers: Dictionary = MapPlayObjectivesAi.run(play)

	assert_true(ledgers.has(OBJ_OWNER))
	var report: Dictionary = ledgers[OBJ_OWNER]
	assert_true(int(report["ranked"]) > 0)
	assert_true((report["lines"] as Array).size() >= int(report["ranked"]))
	var colony: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.new_world":
			colony = row
	assert_false(colony.is_empty(), "the court with a harbour prices the expedition")
	assert_eq(String(colony["status"]), AiObjective.STATUS_FUNDED)
	var claim: Dictionary = play.ai.objectives_for(OBJ_OWNER)
	assert_eq(int(claim["turn"]), play.turn, "the claim is kept on the court's state")
	assert_eq(int(claim["ranked"]), int(report["ranked"]))
	play.ship_layer.free()
	play.civilian_layer.free()


## The reading pass is one module, one reading per domain: force, navy, purse,
## study, court and voyage all stand, and the pools it hands the allocate pass
## are those readings bounded by the store (REQ-P3-01; issue #484).
func test_the_reading_pass_names_every_domain() -> void:
	var play: PlaySession = _objective_session(_court())
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	var config: AiConfig = AiConfig.build(OBJ_OWNER, play.map_seed)
	var phase: Dictionary = AiPhasePlanner.plan(config, play.diplomacy)
	var readings: Dictionary = MapPlayObjectiveReadings.readings(
		play, OBJ_OWNER, config, economy, phase
	)

	for key: String in [
		"at_war", "war_desire", "regiments", "muster_floor", "muster_due",
		"muster_row", "muster_gate", "escalations", "blockings",
		"ships", "warships", "warship_price", "warship_row", "warship_open",
		"warship_refusal", "warship_hands",
		"navy_due", "hostile_ships", "hostile_warships",
		"treasury", "reserve", "goal",
		"research_slots", "research_funding", "research_cost",
		"standing_study", "research_refusal",
		"posture", "colony_target", "harbour", "tribe_target",
		"tribe_stage_cost", "deed_price", "tribe_door", "tribe_closed",
		"idle_hulls", "explorer_ready", "voyage_afloat", "voyage_abroad",
		"voyage_stranded",
	]:
		assert_true(readings.has(key), "the reading pass names %s" % key)
	var pools: Dictionary = MapPlayObjectivesAi.pools(economy, readings)
	assert_eq(
		int(pools["hull"]), int(readings["idle_hulls"]),
		"the hull pool is the reading, not a second count"
	)
	assert_eq(int(pools["treasury"]), maxi(economy.treasury, 0))
	play.ship_layer.free()
	play.civilian_layer.free()


func test_the_turn_trace_carries_every_objective() -> void:
	var play: PlaySession = _objective_session(_court())
	var ledgers: Dictionary = MapPlayObjectivesAi.run(play)
	var merged: Dictionary = AiTurnLog.record(
		play, [], [], {"factions": {}}, [], [], ledgers
	)
	var bucket: Dictionary = (merged["factions"] as Dictionary)[OBJ_OWNER]

	assert_eq(String(bucket["phase"]), AiPhasePlanner.PHASE_PEACE)
	assert_eq(String(bucket["goal"]), AiIncome.GOAL_SPEND)
	var ledger: Dictionary = bucket["objectives"]
	assert_eq(int(ledger["ranked"]), int((ledgers[OBJ_OWNER] as Dictionary)["ranked"]))
	for row: Dictionary in ledger["rows"]:
		assert_true(row.has("utility"), "every row carries its utility")
		assert_true(row.has("cost"), "every row carries its cost")
		assert_true(row.has("claim"), "every row carries its claim")
		assert_true(row.has("status"), "every row carries its status")
	play.ship_layer.free()
	play.civilian_layer.free()


func test_the_ledger_prices_the_standing_study_not_the_war_chest() -> void:
	# The surplus ladder reads the money-goal reserve, so at war no slot pays the
	# published preset; the one standing study at Low is what the court actually
	# spends, and the ledger must name that figure — beside the chest the muster
	# claims, not against the purse the chest consumes (issues #490, #590).
	var court: DiplomacyState = _court()
	court.relation(OBJ_OWNER, OBJ_RIVAL).at_war = true
	var play: PlaySession = _objective_session(court)
	play.ai.economy_for(OBJ_OWNER).treasury = 500
	var report: Dictionary = MapPlayObjectivesAi.court(play, OBJ_OWNER)
	var study: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "research.study":
			study = row
	assert_false(study.is_empty(), "the study is priced")
	assert_eq(int((study["cost"] as Dictionary).get("standing", 0)), 1,
		"one standing study at Low, priced on its own budget")
	assert_eq(
		String(study["status"]), AiObjective.STATUS_FUNDED,
		"the bounded exception funds even under the chest claim"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


func test_a_broke_court_reads_a_blocked_study_not_a_funded_zero() -> void:
	# A purse under half the cash floor funds no study; the ledger says so
	# instead of reading a 0-gold study as funded for 200 turns (issue #590).
	var play: PlaySession = _objective_session(_court())
	play.ai.economy_for(OBJ_OWNER).treasury = 40
	var report: Dictionary = MapPlayObjectivesAi.court(play, OBJ_OWNER)
	var study: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "research.study":
			study = row
	assert_eq(String(study["status"]), AiObjective.STATUS_BLOCKED)
	assert_eq(String(study["blocked"]), "purse under half the cash floor")
	play.ship_layer.free()
	play.civilian_layer.free()


func test_planner_a_stalled_war_chest_re_routes_the_reserve() -> void:
	# The escalation's acting lever (issue #603): a muster deferred past the
	# escalation bar with its shortfall standing still drops the war chest out
	# of the reserve, so every spend floor that reads it opens. The muster row
	# itself stays deferred (the blocked bar is farther out), and the report
	# names the escalation.
	var court: DiplomacyState = _court()
	court.relation(OBJ_OWNER, OBJ_RIVAL).at_war = true
	var play: PlaySession = _objective_session(court)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = 300
	var rows: Array = []
	var stall: Dictionary = {}
	for turn in 12:
		rows = [{
			"id": "muster.line", "status": AiObjective.STATUS_DEFERRED,
			"shortfall": {"treasury": 2100},
		}]
		stall = {"objectives": rows}
		play.ai.note_objectives(OBJ_OWNER, stall, play.turn)
	var report: Dictionary = MapPlayObjectivesAi.court(play, OBJ_OWNER)
	var floor: int = AiConfig.build(OBJ_OWNER, OBJ_SEED).parameter("economy.min_treasury")
	assert_eq(
		int(report["reserve"]), floor,
		"a stalled chest re-routes to the cash floor"
	)
	var escalations: Dictionary = report["escalations"]
	assert_true(escalations.has("muster.line"), "the escalation rides the report")
	assert_eq(int(escalations["muster.line"]), 12)
	play.ship_layer.free()
	play.civilian_layer.free()



## The voyage musters behind the ledger's claim (issue #491 T2): a funded hull
## opens the harbour gate, a deferred one leaves the Explorer ashore.
func test_the_muster_gate_reads_the_ledger_hull_claim() -> void:
	var play: PlaySession = _objective_session(_court())
	MapPlayObjectivesAi.run(play)
	var claim: Dictionary = play.ai.objectives_for(OBJ_OWNER)
	assert_true((claim["funded_ids"] as Array).has("expedition.hull"))
	var open_port: Vector2i = CivilianMuster.muster_port(
		play, OBJ_OWNER, play.model.region_id, play.model
	)
	assert_true(open_port.x >= 0, "a funded hull opens the muster")

	# The same ledger with the hull starved: the gate stays shut.
	play.ai.note_objectives(OBJ_OWNER, {
		"phase": AiPhasePlanner.PHASE_PEACE, "ranked": 1, "funded": 0, "lines": [],
		"objectives": [{"id": "expedition.hull", "status": AiObjective.STATUS_DEFERRED}],
	}, play.turn)
	var shut: Vector2i = CivilianMuster.muster_port(
		play, OBJ_OWNER, play.model.region_id, play.model
	)
	assert_eq(shut, CivilianState.NO_TILE, "a deferred hull keeps the Explorer ashore")
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #497's scripted case: a court at peace, with a harbour, a free hull and
## an Explorer, issues its colonisation order on the turn the ledger funds the
## claim — no 200 turns of luck.
func test_a_peaceful_court_with_a_funded_claim_issues_the_voyage() -> void:
	var play: PlaySession = _objective_session(_court())
	MapPlayObjectivesAi.run(play)
	var trace: Array[Dictionary] = MapPlayColonisationAi.run(play)

	assert_eq(trace.size(), 1, "the court under way gets one step")
	assert_eq(String(trace[0]["kind"]), "embark")
	assert_eq(int(trace[0]["faction"]), OBJ_OWNER)
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #500: a court at war with a hostile squadron and a funded build aim
## lays a warship down through the yard, not just on paper.
func test_a_funded_navy_build_lays_a_warship_down() -> void:
	var war: DiplomacyState = _court()
	war.relation(OBJ_OWNER, OBJ_RIVAL).at_war = true
	var play: PlaySession = _objective_session(war)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = 20000
	economy.stockpile["lumber"] = 10
	economy.stockpile["fabric"] = 10
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var report: Dictionary = MapPlayObjectivesAi.run(play)
	assert_true(
		((report[OBJ_OWNER] as Dictionary)["lines"] as Array).any(
			func(line: Variant) -> bool: return String(line).begins_with("navy.build")
		),
		"the court at war prices its yard"
	)
	assert_true(
		(play.ai.objectives_for(OBJ_OWNER)["funded_ids"] as Array).has("navy.build"),
		"a rich court funds it"
	)
	var cargo: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)
	assert_false((cargo.get("warship", {}) as Dictionary).is_empty(), "the hull is laid down")
	assert_eq(
		String((cargo["warship"] as Dictionary)["type_id"]), "sloop",
		"the cheapest warship its techs open"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #484: the purse a court held for its hull is the fleet's, even though a
## war footing clamps the yard and the muster to the same ceiling. The unmodified
## utility breaks the tie, so the chest funds the hull and the army keeps saving.
func test_the_chest_funds_the_hull_before_the_next_muster() -> void:
	var war: DiplomacyState = _court()
	war.relation(OBJ_OWNER, OBJ_RIVAL).at_war = true
	var play: PlaySession = _objective_session(war)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = ShipEconomy.treasury_cost("sloop")
	economy.stockpile["lumber"] = 10
	economy.stockpile["fabric"] = 10
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	MapPlayObjectivesAi.run(play)
	var claim: Dictionary = play.ai.objectives_for(OBJ_OWNER)

	assert_true(
		(claim["funded_ids"] as Array).has("navy.build"),
		"the chest is the fleet's, not the army's"
	)
	assert_false(
		(claim["funded_ids"] as Array).has("muster.line"),
		"the muster it outranks waits its turn"
	)
	var cargo: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)
	var warship: Dictionary = cargo.get("warship", {})
	assert_false(warship.is_empty(), "the hull the court saved for is laid down")
	assert_eq(int(warship.get("price", 0)), ShipEconomy.treasury_cost("sloop"))
	assert_eq(
		int(warship.get("chest", 0)), ShipEconomy.treasury_cost("sloop"),
		"the launch names the chest that allowed it"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #1233: the reading turns into an order — a food-gated court with an
## idle home pair breaks one hull up through the yard, the rations leave the
## larder's `wanted`, and the trace names the freed grain.
func test_a_food_gated_court_breaks_up_its_idle_home_hull() -> void:
	var play: PlaySession = _objective_session(_court())
	var fleet: FleetState = (play.ship_layer.regions.value(0, []) as Array)[0]
	fleet.set_hulls(["h0", "h1"], {"h0": "sloop", "h1": "sloop"})
	play.ai.note_food_slack(OBJ_OWNER, 0)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	# A flat purse: the pass buys no merchant hull beside the break-up, so the
	# yard's own peasant is the only hand that moves.
	economy.treasury = 0
	var peasants: int = economy.workers.count(WorkerPool.Tier.PEASANT)

	var cargo: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)

	var scrapped: Dictionary = cargo.get("scrap", {})
	assert_false(scrapped.is_empty(), "the food gate names the idle hull")
	assert_eq(String(scrapped["type_id"]), "sloop")
	assert_eq(int(scrapped["rations"]), ShipEconomy.food_upkeep_per_ship())
	assert_false(fleet.hulls.has("h0"), "one hull of the pair is broken up")
	assert_true(fleet.hulls.has("h1"), "her last hull keeps her squadron")
	assert_eq(
		economy.workers.count(WorkerPool.Tier.PEASANT), peasants + 1,
		"the hull's own hand returns to the pool"
	)
	var fed: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)
	assert_true(
		(fed.get("scrap", {}) as Dictionary).is_empty(),
		"a squadron of one hull keeps her — no break-up a second time"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## The yard's arm stays sheathed while the fleet earns its keep: a fed muster
## funds no break-up even beside an idle pair (issue #1233).
func test_a_fed_muster_does_not_break_its_fleet_up() -> void:
	var play: PlaySession = _objective_session(_court())
	var fleet: FleetState = (play.ship_layer.regions.value(0, []) as Array)[0]
	fleet.set_hulls(["h0", "h1"], {"h0": "sloop", "h1": "sloop"})
	play.ai.note_food_slack(OBJ_OWNER, 1)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = 0

	var cargo: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)

	assert_true(
		(cargo.get("scrap", {}) as Dictionary).is_empty(),
		"the harvest carries one more ration: the fleet keeps her hulls"
	)
	assert_eq(fleet.hulls.size(), 2, "the seat's pair stands unbroken")
	play.ship_layer.free()
	play.civilian_layer.free()


## The larder's own reading is the hallmark (issue #1233): a court with no
## reading yet — the `-2` sentinel the fresh session carries — gates nothing,
## and the break-up waits for the pass's note.
func test_a_court_with_no_larder_reading_keeps_the_fleet() -> void:
	var play: PlaySession = _objective_session(_court())
	var fleet: FleetState = (play.ship_layer.regions.value(0, []) as Array)[0]
	fleet.set_hulls(["h0", "h1"], {"h0": "sloop", "h1": "sloop"})
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = 0

	var cargo: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)

	assert_true(
		(cargo.get("scrap", {}) as Dictionary).is_empty(),
		"no note, no gate — the fresh session breaks nothing up"
	)
	assert_eq(fleet.hulls.size(), 2)
	play.ship_layer.free()
	play.civilian_layer.free()


## A yard-refused reading changes nothing: a hull the rules will not break
## (a loaded transport, say) leaves the reading's own caller silent (issue
## #1233).
func test_a_refused_break_up_leaves_the_fleet_standing() -> void:
	var play: PlaySession = _objective_session(_court())
	var fleet: FleetState = (play.ship_layer.regions.value(0, []) as Array)[0]
	fleet.set_hulls(["h0", "h1"], {"h0": "sloop", "h1": "sloop"})
	fleet.embarked_army = 3
	play.ai.note_food_slack(OBJ_OWNER, 0)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = 0
	var cargo: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)
	assert_true((cargo.get("scrap", {}) as Dictionary).is_empty())
	assert_eq(fleet.hulls.size(), 2, "the loaded hull keeps her squadron")
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #484: the fleet claim holds the hull's material row the way the muster
## holds its own — the cloth and lumber the yard wants, read off the catalog for
## the cheapest warship (open, or the one the court is studying toward).
func test_the_fleet_claim_knows_the_hull_s_material_row() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(
		AiNavy.saving_row(economy), ShipEconomy.build_inputs("sloop"),
		"the row is reserved while the unlock is still shut"
	)
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	assert_eq(
		AiNavy.saving_row(economy), ShipEconomy.build_inputs("sloop"),
		"the row the yard charges for the hull it is saving for"
	)
	assert_eq(
		AiNavy.due_row(false, 0, 3, economy), ShipEconomy.build_inputs("sloop"),
		"no fighting hull: the row is held even at peace"
	)
	assert_true(
		AiNavy.due_row(false, 2, 3, economy).is_empty(),
		"at peace with hulls, no fleet claim"
	)
	assert_eq(
		AiNavy.due_row(true, 0, 3, economy), ShipEconomy.build_inputs("sloop"),
		"a court at war with no warship holds the row"
	)


## Issue #484: a court that saved the whole chest but sold its cloth still
## funds the treasury claim (cloth stays on AiClaims.NAVY, not double-booked on
## the objective), yet the yard refuses the launch without fabric.
func test_a_fleet_claim_short_of_cloth_does_not_launch() -> void:
	var war: DiplomacyState = _court()
	war.relation(OBJ_OWNER, OBJ_RIVAL).at_war = true
	var play: PlaySession = _objective_session(war)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = 20000
	economy.stockpile["lumber"] = 10
	economy.stockpile["fabric"] = 0
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	MapPlayObjectivesAi.run(play)
	assert_true(
		(play.ai.objectives_for(OBJ_OWNER)["funded_ids"] as Array).has("navy.build"),
		"the chest claim funds without double-booking cloth"
	)
	assert_true(
		(MapPlayCargoAi.run(play, OBJ_OWNER, economy).get("warship", {}) as Dictionary).is_empty(),
		"the yard still refuses without fabric"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #1126: the yard's own gate is the one read the ledger, the cargo pass
## and the trace share — what it would lay today, or why it will not.
func test_the_yard_gate_names_the_hull_it_would_lay_or_the_refusal() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 20000
	economy.stockpile["lumber"] = 10
	economy.stockpile["fabric"] = 10
	economy.tech_unlocked[ShipEconomy.tech_for("frigate")] = true
	var lay: Dictionary = AiNavy.laying(economy, [])
	assert_eq(String(lay["type_id"]), "frigate", "the strongest hull its techs open")
	assert_eq(String(lay["reason"]), "", "a payable hull names no gate")

	# England's published case (issue #1126): the purse and the cloth are there,
	# no hand is free.
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	lay = AiNavy.laying(economy, [])
	assert_eq(String(lay["type_id"]), "", "no hand, no hull")
	assert_eq(String(lay["reason"]), "Insufficient workers", "the yard's own words")

	economy.workers.set_count(WorkerPool.Tier.PEASANT, 4)
	economy.stockpile["fabric"] = 0
	lay = AiNavy.laying(economy, [])
	assert_eq(String(lay["reason"]), "Insufficient materials", "and its own cloth gate")


## Issue #1126: a funded claim the yard refuses reads the gate instead of
## vanishing — the report carries the yard's words and lays no hull.
func test_a_funded_hull_the_yard_refuses_names_the_gate() -> void:
	var war: DiplomacyState = _court()
	war.relation(OBJ_OWNER, OBJ_RIVAL).at_war = true
	var play: PlaySession = _objective_session(war)
	var economy: PlayerEconomy = play.ai.economy_for(OBJ_OWNER)
	economy.treasury = 20000
	economy.stockpile["lumber"] = 10
	economy.stockpile["fabric"] = 10
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	MapPlayObjectivesAi.run(play)
	assert_true(
		(play.ai.objectives_for(OBJ_OWNER)["funded_ids"] as Array).has("navy.build"),
		"the chest funds the hull"
	)
	# No hand to crew her: one peasant leaves the pool at launch.
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	var cargo: Dictionary = MapPlayCargoAi.run(play, OBJ_OWNER, economy)
	assert_true(
		(cargo.get("warship", {}) as Dictionary).is_empty(), "no hull is laid down"
	)
	assert_eq(
		String((cargo.get("warship_refused", {}) as Dictionary).get("refused", "")),
		"Insufficient workers", "the yard's gate reaches the report"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #1126: a court with no free hand funds no hull the yard would refuse.
## The hand is a gate, not a claim: reading it out of the shared labour pool
## starved the production run ranked under the yard.
func test_a_slip_with_no_free_hand_funds_no_hull() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["warships"] = 0
	readings["hostile_warships"] = 2
	readings["warship_hands"] = 0
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)
	var build: AiObjective = _by_id(objectives, "navy.build")
	assert_eq(String(build.blocked), "no free hand for the slip")
	assert_true((build.cost as Dictionary).has("treasury"), "the purse is still priced")
	assert_false((build.cost as Dictionary).has("labour"), "the hand is no pool claim")

	readings["warship_hands"] = ShipEconomy.WORKER_COST
	build = _by_id(AiObjectivesPlan.build(readings), "navy.build")
	assert_eq(String(build.blocked), "", "a hand in the pool opens the yard")


## Issue #1126: while the chest banks for a hull the yard opens and the material
## row is in store, the court keeps one peasant for the slip; a hull with no
## cloth to lay holds no hand.
func test_the_slip_keeps_a_hand_while_the_chest_banks() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["lumber"] = 10
	economy.stockpile["fabric"] = 10
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	economy.treasury = 6000
	assert_eq(
		AiNavy.hands(economy, [], 5500), ShipEconomy.WORKER_COST,
		"the chest is in hand: a hand is kept for the slip"
	)
	economy.treasury = 3000
	assert_eq(AiNavy.hands(economy, [], 5500), 0, "still filling: the court trains")
	assert_eq(AiNavy.hands(economy, [], 0), 0, "no chest, no hand")
	economy.treasury = 6000
	economy.stockpile["fabric"] = 0
	assert_eq(AiNavy.hands(economy, [], 5500), 0, "no cloth to lay: no hand held")


## Issue #484: the economy keeps the hull's row back beside the muster's, so a
## court saving 5,500 ducats does not sell the cloth the yard wants.
func test_the_economy_reserves_the_hull_row_beside_the_muster() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var production: Dictionary = {"assignments": []}
	var rows: Array[Dictionary] = MapPlayEconomyLarder.claim_rows(
		production, 0, economy, {"fabric": 1}, {}, {"lumber": 1, "fabric": 1}
	)
	var reserved: Dictionary = AiClaims.reserve(rows)["reserved"]

	assert_eq(int(reserved["fabric"]), 2, "the muster's cloth plus the hull's")
	assert_eq(int(reserved["lumber"]), 1, "and the hull's timber")
	assert_true(
		(rows as Array).any(
			func(row: Variant) -> bool: return String((row as Dictionary)["id"]) == AiClaims.NAVY
		),
		"the hull's row is its own claim, not the muster's"
	)


func test_a_war_footing_scales_the_military_up_and_the_voyage_down() -> void:
	var config: AiConfig = _objective_config()
	var peace: Dictionary = AiPosture.modifiers(AiPhasePlanner.PHASE_PEACE, config)
	var war: Dictionary = AiPosture.modifiers(AiPhasePlanner.PHASE_WAR, config)
	var fronts: Dictionary = AiPosture.modifiers(AiPhasePlanner.PHASE_FRONTS, config)

	assert_eq(int(peace["military"]), AiPosture.weight_mille(config, "military"))
	assert_true(int(war["military"]) > int(peace["military"]), "the army leads at war")
	assert_true(int(war["expansion"]) < int(peace["expansion"]), "the voyage is cheaper at war")
	assert_true(int(fronts["expansion"]) < int(war["expansion"]), "and cheaper still on two fronts")
	assert_true(int(fronts["expansion"]) >= config.parameter("posture.floor"), "never zeroed")


## DR-20261116-09: treasury recovery reweights the rank. A court that cannot pay
## its way leads with the domains that raise coin and lets the studies and the
## crews it can defer fall behind them — never the army, the fleet or the court.
func test_the_money_goal_leads_with_the_domains_that_pay() -> void:
	var config: AiConfig = _objective_config()
	var phase: String = AiPhasePlanner.PHASE_PEACE
	var spend: Dictionary = AiPosture.modifiers(
		phase, config, AiPosture.NEUTRAL, AiIncome.GOAL_SPEND
	)
	var earn: Dictionary = AiPosture.modifiers(
		phase, config, AiPosture.NEUTRAL, AiIncome.GOAL_EARN
	)

	assert_true(int(earn["economy"]) > int(spend["economy"]), "the works lead while it earns")
	assert_true(int(earn["expansion"]) > int(spend["expansion"]), "and the voyages that sell")
	assert_true(int(earn["research"]) < int(spend["research"]), "the study waits its turn")
	assert_true(int(earn["civilian"]) < int(spend["civilian"]), "and so do the crews")
	assert_eq(int(earn["military"]), int(spend["military"]), "the army keeps its weight")
	assert_eq(int(earn["diplomacy"]), int(spend["diplomacy"]), "and so does the court")
	assert_true(int(earn["research"]) >= config.parameter("posture.floor"), "never zeroed")
	assert_eq(
		int(AiPosture.modifiers(phase, config, AiPosture.NEUTRAL, "")["economy"]),
		int(spend["economy"]), "a caller with no goal read keeps the published weights"
	)
	# The two readings compose: a court at war that cannot pay still arms up and
	# still sails for the far coast, which is the coin it cannot raise at home.
	var armed: Dictionary = AiPosture.modifiers(
		AiPhasePlanner.PHASE_WAR, config, AiPosture.NEUTRAL, AiIncome.GOAL_EARN
	)
	assert_eq(
		int(armed["military"]),
		int(AiPosture.modifiers(AiPhasePlanner.PHASE_WAR, config)["military"]),
		"the footing's war boost stands beside the goal"
	)
	assert_true(
		int(armed["expansion"]) > int(AiPosture.modifiers(AiPhasePlanner.PHASE_WAR, config)["expansion"]),
		"and the voyage the footing closes is the income the goal reopens"
	)
	# The rank pass reads the vector: the same two aims swap on `earn`.
	var study: AiObjective = AiObjective.create("research.study", "research", 45)
	var cargo: AiObjective = AiObjective.create("cargo.route", "economy", 40)
	var calm_order: Array[AiObjective] = AiObjectiveLedger.rank([study, cargo], spend)
	var earn_order: Array[AiObjective] = AiObjectiveLedger.rank([study, cargo], earn)

	assert_eq(String(calm_order[0].id), "research.study", "a spending court studies first")
	assert_eq(String(earn_order[0].id), "cargo.route", "an earning one sells first")
	assert_eq(String(earn_order[1].id), "research.study", "and the study waits behind it")


func test_the_leader_s_weights_reorder_the_rank() -> void:
	var napoleon: AiConfig = AiConfig.build(OBJ_OWNER, OBJ_SEED, AiProfile.NORMAL, AiAgenda.WARMONGER)
	napoleon.personality = AiPersonality.resolve("napoleon")
	var victoria: AiConfig = AiConfig.build(OBJ_OWNER, OBJ_SEED, AiProfile.NORMAL, AiAgenda.ISOLATIONIST)
	victoria.personality = AiPersonality.resolve("victoria")
	var phase: String = AiPhasePlanner.PHASE_WAR

	assert_true(
		int(AiPosture.modifiers(phase, napoleon)["military"])
		> int(AiPosture.modifiers(phase, victoria)["military"]),
		"a soldier ranks the army higher than a trader does"
	)
	assert_true(
		int(AiPosture.modifiers(phase, victoria)["economy"])
		> int(AiPosture.modifiers(phase, napoleon)["economy"]),
		"and a trader ranks the ledger higher"
	)


func test_a_parent_defers_with_the_child_that_starved_it() -> void:
	# At war the expedition needs the court's one order for its peace window; a
	# war it still wants spends that order pressing the war instead.
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["posture"] = AiPhasePlanner.PHASE_WAR
	readings["war_desire"] = 70
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), {"hull": 2, "civilian": 1, "orders": 1}
	)
	var colony: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.new_world":
			colony = row

	assert_false(colony.is_empty(), "the voyage is still ranked at war")
	assert_eq(String(colony["status"]), AiObjective.STATUS_DEFERRED)
	assert_true(
		String(colony.get("blocked", "")).contains("peace.window"),
		"the trace names the aim the voyage waited on"
	)
	var line: String = ""
	for raw: Variant in report["lines"]:
		if String(raw).begins_with("colonise.new_world"):
			line = String(raw)
	assert_true(line.contains("deferred"), "and the line says so: %s" % line)


func test_a_won_peace_window_opens_the_voyage_at_war() -> void:
	# A court that wants peace more than it wants the war spends its order on
	# the window, so the expedition funds and the muster gate opens (issue #497).
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["posture"] = AiPhasePlanner.PHASE_WAR
	readings["war_desire"] = 20
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), {"hull": 2, "civilian": 1, "orders": 1}
	)
	var status: Dictionary = {}
	_statuses(report["objectives"], status)
	assert_eq(String(status["peace.window"]), AiObjective.STATUS_FUNDED)
	assert_eq(String(status["colonise.new_world"]), AiObjective.STATUS_FUNDED)


# --- commodity claims: the reservations (issue #498) -------------------------


func test_a_commodity_claim_reads_after_the_named_resources() -> void:
	var objective: AiObjective = AiObjective.create(
		"reserve.muster", "economy", 90, {"fabric": 1, "treasury": 400, "grain": 2}
	)

	assert_eq(
		String(objective.line()),
		"reserve.muster u90 treasury 0/400, fabric 0/1, grain 0/2 ranked",
		"named resources first, commodities sorted after them"
	)


func test_the_reservation_rows_merge_into_one_claim_set() -> void:
	var rows: Array[Dictionary] = AiClaims.sources({
		AiClaims.RATIONS: {"grain": 5},
		AiClaims.MUSTER: {"fabric": 1, "grain": 2},
		AiClaims.WORKS: {"lumber": 3},
	})
	var report: Dictionary = AiClaims.reserve(rows)
	var reserved: Dictionary = report["reserved"]

	assert_eq(int(reserved["grain"]), 7, "the rows add up")
	assert_eq(int(reserved["fabric"]), 1)
	assert_eq(int(reserved["lumber"]), 3)
	assert_eq((report["lines"] as Array).size(), 3, "every reservation is a claim line")
	assert_true(
		String((report["lines"] as Array)[0]).begins_with(AiClaims.RATIONS),
		"rations outrank the rest"
	)


func test_a_pool_short_of_a_commodity_defers_the_rest() -> void:
	var rows: Array[Dictionary] = AiClaims.sources({
		AiClaims.RATIONS: {"grain": 3},
		AiClaims.MUSTER: {"grain": 4},
	})
	var report: Dictionary = AiClaims.reserve(rows, {"grain": 3})

	assert_eq(int((report["reserved"] as Dictionary)["grain"]), 3, "only what is held")
	var second: Dictionary = (report["rows"] as Array)[1]
	assert_eq(String(second["status"]), AiObjective.STATUS_DEFERRED)
	assert_eq(int((second["shortfall"] as Dictionary)["grain"]), 4)


func test_the_civilian_purse_is_one_treasury_claim() -> void:
	assert_eq(int(AiClaims.purse(2000, 500)["treasury"]), 1500)
	assert_eq(int(AiClaims.purse(400, 500).get("treasury", 0)), 0, "no purse below its floor")
	assert_eq(int(AiClaims.purse(500, 500).get("treasury", 0)), 0)


func test_the_routes_of_the_economy_pass_are_the_same_reservation() -> void:
	# The parity invariant: the claim set merges to the dictionary the market has
	# always read, so no sale, bid or work changes (issue #498).
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var production: Dictionary = {
		"assignments": [{"recipe": ProductionRecipes.ids()[0], "units": 2}],
	}
	var muster: Dictionary = {"fabric": 1}
	var works: Dictionary = {"lumber": 2}
	var rows: Array[Dictionary] = MapPlayEconomyLarder.claim_rows(
		production, 4, economy, muster, works
	)
	var merged: Dictionary = AiClaims.reserve(rows)["reserved"]
	var published: Dictionary = MapPlayEconomyLarder.reserved_inputs(
		production, 4, economy, muster, works
	)

	assert_eq(merged, published, "one primitive, the same floor")
	var ids: Array[String] = []
	for row: Dictionary in rows:
		ids.append(String(row["id"]))
	assert_true(ids.has(AiClaims.RATIONS) and ids.has(AiClaims.WORKS))


# --- the save round-trip -----------------------------------------------------


func test_a_save_round_trips_the_ledger() -> void:
	var state := AiState.new()
	state.note_objectives(
		OBJ_OWNER,
		{
			"phase": AiPhasePlanner.PHASE_WAR, "ranked": 4, "funded": 3,
			"lines": ["colonise.new_world u50 hull 0/1 deferred"],
		},
		7
	)
	var restored := AiState.from_dict(state.to_dict())
	var claim: Dictionary = restored.objectives_for(OBJ_OWNER)

	assert_eq(int(claim["turn"]), 7)
	assert_eq(String(claim["phase"]), AiPhasePlanner.PHASE_WAR)
	assert_eq(int(claim["ranked"]), 4)
	assert_eq(int(claim["funded"]), 3)
	assert_eq(String((claim["lines"] as Array)[0]), "colonise.new_world u50 hull 0/1 deferred")


func test_a_save_round_trips_the_deferral_stalls() -> void:
	# The escalation's records ride the save, so a stalled war chest survives a
	# load instead of restarting its count (issue #603).
	var state := AiState.new()
	var rows: Array = []
	for turn in 3:
		rows = [{
			"id": "muster.line", "status": AiObjective.STATUS_DEFERRED,
			"shortfall": {"treasury": 2100},
		}]
		state.note_objectives(OBJ_OWNER, {"objectives": rows}, turn)
	assert_eq(
		AiDeferral.stall(AiDeferral.records_for(state.deferrals, OBJ_OWNER), "muster.line"), 3,
	)
	var restored := AiState.from_dict(state.to_dict())
	assert_eq(
		AiDeferral.stall(AiDeferral.records_for(restored.deferrals, OBJ_OWNER), "muster.line"), 3,
		"the stall count carries the load"
	)
	# A funded aim leaves no record, so a fresh campaign reads none either.
	assert_true(
		AiDeferral.records_for(restored.deferrals, OBJ_RIVAL).is_empty(),
		"other courts read empty"
	)


func test_an_old_save_reads_an_empty_ledger() -> void:
	var restored := AiState.from_dict({"difficulty": Difficulty.DEFAULT})

	assert_true(restored.objectives_for(OBJ_OWNER).is_empty(), "an old save simply has no ledger")
	assert_eq(int(restored.to_dict().get("objective_claims", {}).size()), 0)
	assert_true(
		AiDeferral.records_for(restored.deferrals, OBJ_OWNER).is_empty(),
		"and no stall records"
	)


## The absorption answer a rival prices its Join Empire rung with is the rule's
## own call — the same one the court answers with — so the AI never prices a
## yes the rule refuses, and a no with no power map is still a no (REQ-P3-01).
func test_a_treaty_rung_reads_the_rules_own_absorption_answer() -> void:
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 1, 1, 1, 1, 1])
	var state := DiplomacyState.new()
	state.initialize(2)
	state.ensure_relation(2, 1, 1)
	# Warm, but short of the alliance clamp: the next rung is the one priced.
	state.relation(2, 1).score = 55.0
	state.set_overture(2, 1, DiplomacyCatalog.STAGE_NAP)
	var charts: CourtCharts = _charts(world)
	var config: AiConfig = AiConfig.build(2, 30000)
	var ai_state := AiState.new()
	ai_state.economy_for(2).treasury = 30000
	var told_yes: Dictionary = AiDiplomacyTreaties.best(
		config, state, ai_state, world, 1, 1, 45, 0, 30000,
		{"empire_building": true}, {"charts": charts, "power": {2: 100, 1: 20}}
	)
	assert_true(bool(told_yes.get("ok", false)), String(told_yes.get("blocked", "")))
	assert_eq(String(told_yes.get("kind", "")), AiDiplomacyOffers.KIND_OVERTURE)
	assert_eq(String(told_yes.get("stage", "")), DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	var told_no: Dictionary = AiDiplomacyTreaties.best(
		config, state, ai_state, world, 1, 1, 45, 0, 30000,
		{"empire_building": true}, {"charts": charts, "power": {2: 20, 1: 60}}
	)
	assert_false(bool(told_no.get("ok", true)), "a refused crown is not worth the order")
	assert_eq(String(told_no.get("blocked", "")), "the crown would refuse absorption")
	assert_eq(String(told_no.get("kind", "")), AiDiplomacyOffers.KIND_OVERTURE)


# --- the idle home hull (issue #1233) ----------------------------------------


## A court whose harvest cannot carry one more ration frees the rations an idle
## home fleet eats: the reading names one hull of the seat's squadron, its two
## rations leave the larder's `wanted` and its peasant returns to the pool the
## levy needs (wiki: ships-and-naval § Ship food upkeep, § breaker's yard;
## ai-architecture § Land reinforcement).
func test_a_food_gated_court_names_an_idle_home_hull_to_break_up() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var economy: PlayerEconomy = _purse(4000)
	var home: FleetState = FleetState.in_port(
		0, 0, 0, ["h0", "h1"] as Array[String],
		{"h0": "sloop", "h1": "sloop"}
	)
	var idle: Dictionary = AiNavy.idle_hull(config, economy, [home], 0, 0)

	assert_false(idle.is_empty(), "the fleet holds idle cargo the war does not use")
	assert_eq(int(idle["fleet_id"]), 0)
	assert_eq(String(idle["hull"]), "h0", "the lowest id goes first, the yard's order")
	assert_eq(int(idle["rations"]), ShipEconomy.food_upkeep_per_ship())

	var peasants: int = economy.available_peasants()
	var result: Dictionary = FleetYard.scrap(economy, home, String(idle["hull"]))
	assert_true(bool(result["ok"]))
	assert_eq(home.hulls, ["h1"], "one hull of the pair is broken up")
	assert_eq(economy.available_peasants(), peasants + 1, "the hull's hand returns")
	assert_false(bool(result["retired"]), "the last hull keeps her squadron")
	assert_true(
		AiNavy.idle_hull(config, economy, [home], 0, 0).is_empty(),
		"a squadron of one hull keeps her"
	)


## A hull carries a regiment or a colonist — she is not idle cargo, and the
## break-up would strand her passengers. The fleet that sailed this turn is in
## the war's use, and a court with no larder reading has no gate at all.
func test_a_carrier_a_sailing_fleet_and_no_reading_keep_the_hulls() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var economy: PlayerEconomy = _purse(4000)
	var laden: FleetState = FleetState.in_port(
		0, 0, 0, ["h0", "h1"] as Array[String],
		{"h0": "sloop", "h1": "sloop"}
	)
	laden.embarked_army = 3

	assert_true(
		AiNavy.idle_hull(config, economy, [laden], 0, 0).is_empty(),
		"the hull that carries the regiment stays"
	)
	laden.embarked_army = -1
	laden.embarked_civilians = [7]
	assert_true(
		AiNavy.idle_hull(config, economy, [laden], 0, 0).is_empty(),
		"the hull that carries the colonist stays"
	)
	laden.embarked_civilians.clear()
	laden.moved = true
	assert_true(
		AiNavy.idle_hull(config, economy, [laden], 0, 0).is_empty(),
		"a fleet that sailed this turn is not idle"
	)
	laden.moved = false
	assert_false(
		AiNavy.idle_hull(config, economy, [laden], 0, 0).is_empty(),
		"the hull came home and reads idle again"
	)
	assert_true(
		AiNavy.idle_hull(config, economy, [laden], 0, -2).is_empty(),
		"no larder reading, no gate"
	)


## A station-holding squadron earns its keep: the war's own watch is a use, so
## the reading keeps her hulls afloat. A fleet whose harvest still carries one
## more ration keeps them too (wiki: ai-architecture § Naval policy — the
## station pass posts the blockade the raid needs).
func test_a_stationed_fleet_and_a_fed_muster_keep_the_fleet() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var economy: PlayerEconomy = _purse(4000)
	var watch: FleetState = FleetState.in_port(
		0, 0, 0, ["h0"] as Array[String], {"h0": "sloop"}
	)
	watch.mission = FleetState.Mission.DEFEND

	assert_true(
		AiNavy.idle_hull(config, economy, [watch], 0, 1).is_empty(),
		"a hull with room for one more ration is not idle cargo"
	)
	watch.mission = FleetState.Mission.NONE
	assert_true(
		AiNavy.idle_hull(config, economy, [watch], 0, 0).is_empty(),
		"a squadron of one hull keeps her whatever the larder reads"
	)


## The economy trace names the break-up the cargo pass booked — the court, the
## hull type and the rations freed for the levy (issue #1233).
func test_the_trace_names_the_idle_hull_the_court_breaks_up() -> void:
	var merged: Dictionary = {"events": []}
	var court: Dictionary = {"events": [], "actions": {}}
	AiEconomyTrace.record(
		merged, {0: court},
		{"factions": {0: {"cargo": {
			"scrap": {"type_id": "sloop", "rations": ShipEconomy.food_upkeep_per_ship()},
		}}}}
	)
	var text: String = ""
	for entry: Variant in court["events"]:
		text += String(entry)
	assert_true(text.contains("breaks up"), "the trace names the break-up")
	assert_true(text.contains("rations freed"), "and the rations it freed")


## Idle-hull gates the reading itself refuses: no config, no purse, no seat, a
## foreign squadron, a hull away from the seat, and a sister that already sailed.
func test_idle_hull_gates_refuse_what_the_larder_cannot_claim() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var economy: PlayerEconomy = _purse(4000)
	var home: FleetState = FleetState.in_port(
		0, 0, 0, ["h0", "h1"] as Array[String],
		{"h0": "sloop", "h1": "sloop"}
	)
	assert_true(AiNavy.idle_hull(null, economy, [home], 0, 0).is_empty())
	assert_true(AiNavy.idle_hull(config, null, [home], 0, 0).is_empty())
	assert_true(AiNavy.idle_hull(config, economy, [home], -1, 0).is_empty())
	var foreign: FleetState = FleetState.in_port(
		1, 1, 0, ["f0", "f1"] as Array[String],
		{"f0": "sloop", "f1": "sloop"}
	)
	assert_true(
		AiNavy.idle_hull(config, economy, [null, foreign], 0, 0).is_empty(),
		"a foreign squadron is not this court's idle cargo"
	)
	var afar: FleetState = FleetState.in_port(
		2, 0, 1, ["a0", "a1"] as Array[String],
		{"a0": "sloop", "a1": "sloop"}
	)
	assert_true(
		AiNavy.idle_hull(config, economy, [afar], 0, 0).is_empty(),
		"a hull in another province is not the seat's idle cargo"
	)
	var sailed: FleetState = FleetState.in_port(
		3, 0, 0, ["s0"] as Array[String], {"s0": "sloop"}
	)
	sailed.moved = true
	assert_true(
		AiNavy.idle_hull(config, economy, [home, sailed], 0, 0).is_empty(),
		"a sister that sailed this turn keeps the whole fleet"
	)
	assert_true(AiNavy.fleets_sailing([home, sailed], 0))
	assert_false(AiNavy.fleets_sailing([home], 0))
	# The yard's own spare-hull gate: two hulls that still carry two mouths keep
	# both — breaking one would strand a passenger.
	var packed: FleetState = FleetState.in_port(
		4, 0, 0, ["p0", "p1"] as Array[String],
		{"p0": "sloop", "p1": "sloop"}
	)
	packed.embarked_civilians = [7, 8]
	assert_eq(AiNavy._idle_hull_id(packed), "")
	packed.embarked_civilians = [7]
	packed.embarked_army = 3
	assert_eq(AiNavy._idle_hull_id(packed), "")


## Storm sizing (issue #1314): every Old World province starts behind a wall,
## and the storm ladder prices wall + battery, so the muster has to read the
## wall it faces — never a host that ties the threshold, never one the court
## already fields. The battery is the **defender's** line, which the muster
## cannot read, so it prices the top of the ladder (Siege Guns, 19): a host it
## sizes clears the wall whatever battery the province mounts.
func test_the_storm_host_clears_the_wall_it_faces() -> void:
	assert_almost_eq(FortRules.storm_ceiling(1), 59.0, 0.001,
		"a Wood wall at its heaviest battery is 40 + 19")
	assert_eq(
		AiStormGate.regiments_for(FortRules.storm_ceiling(1), 6.0), 12,
		"a 40+19 wall wants twelve 6-strength men: ten clear it, two spare"
	)
	assert_true(
		FortRules.storm_ceiling(1) > FortRules.storm_threshold({}, 1),
		"the floor battery under-prices the wall the gate must clear"
	)
	assert_eq(AiStormGate.regiments_for(0.0, 6.0), 0, "open ground asks for no host")
	assert_eq(AiStormGate.regiments_for(59.0, 0.0), 0, "a line of no strength weighs nothing")
	var model: MapModel = _walk_chart(
		[[0, 1], [2, 3]], {1: 2, 2: 1, 3: 1}, {1: 1}
	)
	model.provinces[0].fort_level = 1
	model.provinces[2].fort_level = 2
	model.provinces[3].fort_level = 0
	assert_eq(
		MapPlayArmyMusterAi.thinnest_wall(model, 1),
		FortRules.storm_ceiling(1),
		"the court reads the lowest wall it must cross, not its own L2 one"
	)
	var strength: float = float(RegimentCatalog.strength(
		AiArmyReinforceLine.strongest_line({})
	))
	assert_true(strength > 0.0, "the opening techs open a line")
	var want: int = AiStormGate.regiments_for(FortRules.storm_ceiling(2), strength)
	assert_eq(
		int(AiStormGate.extra(FortRules.storm_ceiling(2), strength, 1, 1)["extra"]),
		want - 1,
		"the gate asks for the host between the court's guard and the wall"
	)
	assert_eq(
		int(AiStormGate.extra(FortRules.storm_ceiling(2), strength, want, want)["extra"]), 0,
		"a court already at the wall's host asks for nothing"
	)
	assert_eq(int(AiStormGate.extra(0.0, strength, 1, 1)["extra"]), 0, "open ground asks for no host")
	var open: MapModel = _walk_chart([[0], [1]], {1: 2, 2: 1})
	open.provinces[0].fort_level = 0
	open.provinces[1].fort_level = 0
	assert_eq(
		MapPlayArmyMusterAi.thinnest_wall(open, 1), 0.0,
		"open ground in front of the court reads no wall"
	)


## The one storm gate the two war planners read (issue #1314): an empty open
## province admits any host, an empty walled one only a host that clears the top
## of the emplaced line, and a caller with no host or no map admits nothing.
func test_one_storm_gate_reads_for_the_land_and_the_landing() -> void:
	var model: MapModel = AiFixture.land_world([PHASE_OWNER, PHASE_RIVAL]).region(0)
	var config := AiConfig.build(PHASE_OWNER, 1500)
	var weak: ArmyState = ArmyState.muster(
		1, PHASE_OWNER, 0, false, ["peasant_levies"] as Array[String], 1
	)
	model.provinces[1].fort_level = 0
	assert_true(
		AiStormGate.admits(config, model, [weak], weak, 1),
		"an empty open province admits any host"
	)
	model.provinces[1].fort_level = 1
	assert_false(
		AiStormGate.admits(config, model, [weak], weak, 1),
		"an empty walled province wants a host that clears the top battery"
	)
	var line: int = RegimentCatalog.strength("peasant_levies")
	var want: int = int(ceil(FortRules.storm_ceiling(1) / float(line))) + 1
	var types: Array[String] = []
	for index in want:
		types.append("peasant_levies")
	var host: ArmyState = ArmyState.muster(2, PHASE_OWNER, 0, false, types, 101)
	assert_true(
		AiStormGate.admits(config, model, [host], host, 1),
		"a host sized past the wall is admitted"
	)
	assert_false(AiStormGate.admits(config, model, [weak], null, 1))
	assert_false(AiStormGate.admits(null, model, [weak], weak, 1))
	assert_false(AiStormGate.admits(config, null, [weak], weak, 1))


## The wall reading rides the court's own target (issue #1314): the muster, its
## labour floor and the chest all ask for the same host, and a court with no
## reading keeps the published target.
func test_the_wall_raises_the_musters_own_target() -> void:
	var config := AiConfig.build(0, 1500)
	var guard: int = AiArmyReinforce.guard_regiments(config, true)
	assert_eq(AiArmyReinforce.desired_regiments(config, true), guard, "no reading keeps the target")
	assert_eq(
		AiArmyReinforce.desired_regiments(config, false),
		AiArmyReinforce.guard_regiments(config, false),
		"peace keeps the published peace target"
	)
	config.storm_read = {"want": guard + 3, "extra": 3}
	assert_eq(
		AiArmyReinforce.desired_regiments(config, true), guard + 3,
		"at war the court arms for the wall in front of it"
	)
	assert_true(
		config.storm_read.get("extra", 0) > 0,
		"the reading is the one the target raised the guard by"
	)
	assert_eq(
		AiArmyReinforce.desired_regiments(config, false),
		AiArmyReinforce.guard_regiments(config, false),
		"peace musters the published target"
	)


## The config every reader shares (issue #1356): the state builds it once per
## court and hands the same instance back, so the reading one pass notes on it
## — the storm read — is the reading the next reader sees, not a fresh build
## that forgot it.
func test_the_courts_config_is_one_instance_for_every_reader() -> void:
	var state := AiState.new()
	var first: Variant = state.court_config(
		AiControl.KIND_SUBJECT, 1, 1500, AiProfile.roster()
	)
	assert_true(first is AiConfig, "the bind builds the court's run config")
	var second: Variant = state.court_config(
		AiControl.KIND_SUBJECT, 1, 1500, AiProfile.roster()
	)
	assert_true(first == second, "the second read is the same config, not a new build")
	var guard: int = AiArmyReinforce.guard_regiments(first, true)
	(first as AiConfig).storm_read = {"want": guard + 3, "extra": 3}
	assert_eq(
		AiArmyReinforce.desired_regiments(second, true), guard + 3,
		"the reading the pass noted is the target the next reader sees"
	)
	assert_eq(
		AiArmyReinforce.desired_regiments(first, true), guard + 3,
		"and the pass's own target is the same host"
	)


## The court read opens the same shared config the pass reads (issue #1356): a
## second `AiControl.court` in one turn reads the storm reading the muster pass
## set, so the counsel and the pass cannot name two hosts.
##
## Without a materialized `scripts/ai_mainline/` (CI and a plain checkout) the
## bind falls back to the submission profile builder, so a baseline court gets
## the same shared host as any other. The frozen mainline path is exercised by
## the bench, not here: asserting it would only pass on a synced tree.
func test_a_court_read_back_hands_the_same_config() -> void:
	var state := AiState.new()
	var mainline: Variant = state.court_config(
		AiControl.KIND_BASELINE, 1, 1500, AiProfile.roster()
	)
	assert_true(mainline is AiConfig, "the bind falls back to the profile builder")
	assert_true(mainline == state.court_config(
		AiControl.KIND_BASELINE, 1, 1500, AiProfile.roster()
	), "a baseline court hands back the one config it built")
