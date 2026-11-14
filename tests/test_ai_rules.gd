extends GdToolsTest
## Pure AI contracts: power bands, parameters, personalities and turn records,
## the war-footing phase and the civilian work planners.
## Merged from test_ai_phase_rules and test_ai_work_rules so coverage pays a
## single Godot boot per theme (docs/testing.md speed rules).

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
	var context: Dictionary = AiTurn._context(
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
	var context: Dictionary = AiTurn._context(
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
	var context: Dictionary = AiTurn._context(
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
	var reading: Dictionary = AiTurn._reading(context, 0)
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
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_province_weight"), 10)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_regiment_weight"), 1)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_ship_weight"), 5)
	assert_eq(AiParameterRegistry.default_of("military.attack_margin_pct"), 110)
	assert_eq(AiParameterRegistry.default_of("military.defence_weight"), 500)
	assert_eq(AiParameterRegistry.default_of("victory.pressure_start"), 500)
	assert_eq(AiParameterRegistry.default_of("victory.pressure_regiments"), 2)
	assert_eq(AiParameterRegistry.default_of("victory.pressure_boost"), 1250)
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
		_squadron(0, 2, 1, "galleon"),
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
	var moored := FleetState.in_port(0, 2, 0, ["h0"] as Array[String], {"h0": "galleon"})
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
		_squadron(0, 2, 1, "galleon"),
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
	var home := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "galleon"})
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
		_squadron(0, 2, 1, "galleon"),
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
	MapPlayFleetAi._station_orders(play, model, roster, 2)
	assert_eq(fleet.mission, FleetState.Mission.NONE, "no blockade on uncharted water")
	fleet.mission = FleetState.Mission.BLOCKADE
	fleet.blockade_province = 1
	MapPlayFleetAi._station_orders(play, model, roster, 2)
	assert_eq(fleet.mission, FleetState.Mission.NONE, "the blockade lapses there")
	play.court_charts.reveal_sea_zone(2, 1, 1)
	MapPlayFleetAi._station_orders(play, model, roster, 2)
	assert_eq(fleet.mission, FleetState.Mission.BLOCKADE, "charted water takes the station")
	assert_eq(fleet.blockade_province, 1)


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
	var ai: FleetState = _squadron(0, 2, 1, "galleon")
	var human: FleetState = _squadron(1, 1, 0, "sloop")
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [ai, human]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _war_state(2, 1)
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1, "one rival order")
	assert_eq(String(trace[0]["kind"]), AiNavalPlanner.KIND_PURSUE)
	assert_eq(ai.sea_zone, 0, "the rival standard now shares the human's zone")
	assert_true(ai.moved)
	assert_eq(human.sea_zone, 0, "the human squadron is never planned")
	var battles: Array[Dictionary] = layer.resolve_battles(
		world, func(a: int, b: int) -> bool: return a != b
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
	var ai: FleetState = _squadron(0, 2, 1, "galleon")
	var human: FleetState = _squadron(1, 1, 0, "sloop")
	var layer := ShipLayer.new()
	layer.model = model
	var roster: Array[FleetState] = [ai, human]
	layer.regions.set_region(0, roster)
	layer.fleets = roster
	var play := _naval_play(world, model, layer)
	play.diplomacy = _war_state(2, 1)
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
	var order: Dictionary = AiCivilianPlanner.training_order(config, [], rich)
	assert_true(bool(order.get("ok", false)))
	assert_eq(String(order["type_id"]), "builder")
	var poor: Dictionary = _civilian_context()
	poor["treasury"] = 0
	assert_false(bool(AiCivilianPlanner.training_order(config, [], poor).get("ok", false)))
	poor["capital_province"] = -1
	poor["treasury"] = 2500
	assert_false(bool(AiCivilianPlanner.training_order(config, [], poor).get("ok", false)))


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
		layer.unit_count_all(1) <= 6,
		"rival training respects civilian.max_civilians"
	)
	layer.free()


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
		MapPlayCivilianAi._mustering_tile(null, -1, []),
		CivilianState.NO_TILE
	)
	assert_eq(MapPlayCivilianAi._unit_by_id([], 99), null)
	var play := PlaySession.new()
	play.world = AiFixture.land_world([0], {0: true})
	play.model = play.world.region(0)
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.spawn(play.model, 1, 0, [], false)
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.treasury = 100
	assert_true(
		MapPlayCivilianAi._train(
			play, play.model.region_id, [], 1, economy, {}, {"capital_province": 0}
		).is_empty(),
		"training with no type_id pays nothing"
	)
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

	var without_holds: Dictionary = MapPlayEconomyAi._overseas(play, 1, economy)["extraction"]
	assert_eq(_tons(without_holds), 5, "the rival's home yield needs no hold")
	assert_eq(int(MapPlayEconomyAi._overseas(play, 1, economy)["extraction"]["grain"]), 5)

	var ships := ShipLayer.new()
	var home: FleetState = FleetState.in_port(
		1, 1, 1, ["a"], {"a": "fluyte"}
	)
	ships.regions.set_region(WorldMap.OLD_WORLD, [home] as Array[FleetState])
	play.ship_layer = ships
	var with_holds: Dictionary = MapPlayEconomyAi._overseas(play, 1, economy)["extraction"]
	assert_eq(_tons(with_holds), 6, "one hold carries the colony's ton")
	ships.free()
	layer.free()


func _tons(totals: Dictionary) -> int:
	var total: int = 0
	for raw: Variant in totals.values():
		total += int(raw)
	return total


## A rival's finished work is announced with its crown: with rivals building every
## turn, an unlabelled line reads as the player's own crew.
func test_rival_civilian_completion_names_its_crown() -> void:
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
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(
		play.hud.toasts[0].begins_with("%s's " % FactionCatalog.name_of(1)),
		"the crown is named, never left to look like the player's work"
	)
	play.hud.toasts.clear()
	var own: CivilianState = CivilianState.create(
		8, 0, "explorer", CivilianFixture.BARE_TILE
	)
	own.start_work("explore", CivilianFixture.BARE_TILE, 1)
	layer.units.append(own)
	MapPlayCivilians.resolve_work(play)
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(
		play.hud.toasts[0].begins_with("Explorer "),
		"the player's own completion keeps its plain wording"
	)
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
	var saw: int = AiResearchPlanner.score_for(config, economy, "saw_mill", false)
	var crop: int = AiResearchPlanner.score_for(config, economy, "crop_rotation", false)
	assert_true(saw > crop, "timber cap beats a tech with no cap")


func test_war_adds_the_registry_bonus_to_military_and_naval_tech() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var config: AiConfig = _research_config()
	var peace: int = AiResearchPlanner.score_for(
		config, economy, "organised_regiments", false
	)
	var war: int = AiResearchPlanner.score_for(
		config, economy, "organised_regiments", true
	)
	assert_eq(war - peace, config.parameter("research.war_bonus"))
	var gathering: int = AiResearchPlanner.score_for(
		config, economy, "crop_rotation", true
	)
	assert_eq(
		gathering,
		AiResearchPlanner.score_for(config, economy, "crop_rotation", false),
		"war never speeds the counting house"
	)


func test_research_personality_weights_steer_the_branch() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var soldier: AiConfig = _research_config({"military": 3, "economy": 1})
	var trader: AiConfig = _research_config({"military": 1, "economy": 3})
	assert_true(
		AiResearchPlanner.score_for(soldier, economy, "organised_regiments", false)
		> AiResearchPlanner.score_for(soldier, economy, "crop_rotation", false)
	)
	assert_true(
		AiResearchPlanner.score_for(trader, economy, "crop_rotation", false)
		> AiResearchPlanner.score_for(trader, economy, "organised_regiments", false)
	)


func test_techs_already_at_their_cap_are_not_candidates() -> void:
	assert_false(
		AiResearchPlanner._can_teach("saw_mill", {"saw_mill": true}),
		"a cap already granted teaches nothing"
	)
	assert_true(AiResearchPlanner._can_teach("saw_mill", {}))
	assert_true(AiResearchPlanner._can_teach("printing_press", {}))


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
	# The muster needs army.min_treasury (400) after the line's own price, so a
	# court still short of that floor pays no published preset into its slots.
	# The standing study — one slot at the cheapest preset — is the exception
	# that keeps a war-time court learning (issue #490).
	var config: AiConfig = _research_config()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 2300
	var floor: int = AiArmyReinforce.muster_floor(config, economy, 1, true)
	var cash: int = AiResearchPlanner.research_floor(config)
	assert_eq(floor, 2400, "400 kept + 2,000 peasant levies")
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
		2400,
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


# --- the fleet claim: the hull a court saves for (issue #484) ----------------


## A court at war with no fighting hull, or one outmatched at sea, means to lay
## one down; a fleet that matches its enemies has nothing to save for.
func test_the_fleet_claim_reads_the_war_and_the_odds_at_sea() -> void:
	var economy: PlayerEconomy = _purse(0)

	assert_false(AiNavy.due(false, 0, 5), "a court at peace lays down no hull")
	assert_true(AiNavy.due(true, 0, 0), "a court at war with no fighting hull wants one")
	assert_true(AiNavy.due(true, 1, 2), "outmatched at sea, it wants one too")
	assert_false(AiNavy.due(true, 2, 2), "a fleet that matches its enemies holds")
	assert_eq(AiNavy.chest(true, 2, 2, economy), 0, "and reserves nothing for the yard")
	assert_eq(AiNavy.chest(false, 0, 3, economy), 0, "peace reserves nothing either")


## The chest is the yard row of the cheapest warship the court's techs open: the
## price a saving court must hold, not the one it could pay today.
func test_the_yard_price_is_the_cheapest_warship_the_techs_open() -> void:
	var economy: PlayerEconomy = _purse(0)

	assert_eq(AiNavy.saving_type(economy), "", "no naval tech opens no warship")
	assert_eq(AiNavy.price(economy), 0)
	assert_eq(AiNavy.chest(true, 0, 1, economy), 0, "so the court saves for nothing")

	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	assert_eq(AiNavy.saving_type(economy), "sloop")
	assert_eq(AiNavy.price(economy), ShipEconomy.treasury_cost("sloop"))
	assert_eq(AiNavy.chest(true, 0, 1, economy), ShipEconomy.treasury_cost("sloop"))

	economy.tech_unlocked[ShipEconomy.tech_for("frigate")] = true
	assert_eq(AiNavy.saving_type(economy), "sloop", "the cheapest row is the one it saves for")


## The hull outranks the muster: a court holding a purse that would raise a
## regiment reads `earn` until the yard's price is in hand (issue #484).
func test_a_court_saving_for_a_hull_reserves_the_yard_price() -> void:
	var config: AiConfig = _phase_config()
	var economy: PlayerEconomy = _purse(4600)
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var chest: int = AiNavy.chest(true, 0, 1, economy)
	var muster: int = AiArmyReinforce.muster_floor(config, economy, 1, true)

	assert_true(chest > muster, "the hull is the larger commitment")
	var plan: Dictionary = AiIncome.plan(config, economy, true, 1, chest)
	assert_eq(String(plan["goal"]), AiIncome.GOAL_EARN, "4,600 ducats is short of the yard")
	assert_eq(int(plan["reserve"]), chest, "the reserve is the hull, not the muster")
	assert_eq(int(plan["hull_chest"]), chest)
	assert_true(AiIncome.wants_income(config, economy, true, 1, chest))

	var paid: Dictionary = AiIncome.plan(config, _purse(chest), true, 1, chest)
	assert_eq(String(paid["goal"]), AiIncome.GOAL_SPEND, "the chest is in hand: it may spend")
	assert_eq(
		AiIncome.reserve(config, economy, true, 1), muster,
		"with no fleet claim the muster is the whole reserve"
	)




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
	return Engineer.best_candidate(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, {}, _context(at_war), {}
	)


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
	var fort: Dictionary = Engineer.fort_candidate(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, {}, _context(true)
	)
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
	assert_true(Engineer.best_candidate(
		null, model, unit, [unit] as Array, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context(), {}
	).is_empty())


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


func _best(
	model: MapModel, tech_unlocked: Dictionary = TECH, reserved: Dictionary = {}
) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	return AiHospitalWork.best_candidate(
		AiConfig.build(0, 1500), model, unit, [unit], LandWorks.new(),
		_hospital_stockpile(), {}, tech_unlocked, _hospital_context(), reserved
	)


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
	assert_true(AiHospitalWork.best_candidate(
		AiConfig.build(0, 1500), null, unit, [unit], null, _hospital_stockpile(), {},
		TECH, _hospital_context(), {}
	).is_empty())


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
	assert_eq(Vector2i(AiHospitalWork._better(lower, upper)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiHospitalWork._better(upper, lower)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiHospitalWork._better(lower, left)["tile"]), Vector2i(2, 3))
	assert_eq(Vector2i(AiHospitalWork._better(left, lower)["tile"]), Vector2i(2, 3))
	assert_eq(String(AiHospitalWork._better(upper, early)["action"]), "build_fort")
	assert_eq(String(AiHospitalWork._better(early, upper)["action"]), "build_fort")
	assert_eq(String(AiHospitalWork._better({}, upper)["action"]), "build_hospital")
	assert_eq(String(AiHospitalWork._better(upper, {})["action"]), "build_hospital")


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
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _road_stockpile(),
		{}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	)
	assert_eq(String(best.get("action", "")), "build_road")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ROAD_TOWN)


func test_the_next_step_follows_the_shortest_owned_path() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	works.set_transport(model, ROAD_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _road_stockpile(),
		{}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), Vector2i(3, 1))


func test_a_connected_town_is_left_alone() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {},
		_connected(model, [ROAD_CAPITAL, ROAD_TOWN]), {}
	)
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
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, {}, {}
	).is_empty())


func test_a_reserved_town_is_left_for_another_crew() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, _connected(model, [ROAD_CAPITAL]), {ROAD_TOWN: true}
	).is_empty())


func test_a_foreign_town_is_ignored() -> void:
	var model: MapModel = _road_model()
	model.provinces[0].owner = 2
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	).is_empty())


func test_missing_inputs_are_guarded() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		null, model, unit, LandWorks.new(), [unit], _road_stockpile(), {}, {}, {},
		_connected(model, [ROAD_CAPITAL]), {}
	).is_empty())


func test_a_reserved_path_tile_is_left_alone() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	works.set_transport(model, ROAD_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _road_stockpile(),
		{}, {}, {}, _connected(model, [ROAD_CAPITAL]), {Vector2i(3, 1): true}
	).is_empty())


func test_a_working_engineer_gets_no_second_order() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	unit.start_work("build_road", ROAD_TOWN, 1)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	).is_empty())


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
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(), 5, false)

	assert_eq(String(plan["muster"]), "arquebusiers", "the strongest era-1 line")
	var candidates: Array = plan["candidates"]
	assert_true(candidates.size() > 0)
	assert_eq(String(candidates[0]["type_id"]), "arquebusiers")
	for entry: Dictionary in candidates:
		assert_true(
			RegimentCatalog.category(String(entry["type_id"]))
			in AiArmyReinforce.LINE_CATEGORIES,
			"a mustered regiment is a line regiment"
		)


func test_the_war_chest_keeps_the_court_from_overspending() -> void:
	# 4,000 ducats covers a pike, but that would empty the purse; the 2,000 levy
	# is the only line that leaves the court's thousand-ducat floor in the bank.
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(4000), 5, false)

	assert_eq(String(plan["muster"]), "peasant_levies")
	var priced: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(1500), 5, false)
	assert_eq(String(priced["muster"]), "", "nothing payable leaves the floor alone")
	assert_true((priced["reasons"] as Array).has("nothing payable"))


func test_a_court_at_target_strength_waits_and_a_war_lifts_the_target() -> void:
	var peace: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(), 8, false)
	assert_eq(String(peace["muster"]), "", "eight regiments is the peace target")
	assert_eq(int(peace["target"]), 8)

	var war: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(), 8, true)
	assert_eq(int(war["target"]), 12, "the war footing raises the target by four")
	assert_eq(String(war["muster"]), "arquebusiers", "a court at war arms up")

	var full: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(), 12, true)
	assert_eq(String(full["muster"]), "", "the war target is a ceiling too")


func test_a_thin_labour_pool_stops_the_muster() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), _work_economy(12000, 3), 5, false)

	assert_eq(String(plan["muster"]), "", "the fields keep their hands")
	assert_true((plan["reasons"] as Array).has("labour floor"))


func test_a_researched_pattern_is_the_one_that_musters() -> void:
	var economy: PlayerEconomy = _work_economy()
	economy.tech_unlocked["weapon_craftsmanship"] = true
	var plan: Dictionary = AiArmyReinforce.plan(_work_config(), economy, 5, false)

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
		String(AiArmyReinforce.plan(_work_config(), economy, 5, false)["muster"]), "",
		"an empty store still musters nothing"
	)
	var reserve: Dictionary = AiArmyReinforce.muster_reserve(_work_config(), economy, 5, false)
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
	var target: Dictionary = AiArmyReinforce.muster_reserve(_work_config(), _work_economy(), 8, false)
	assert_true(target.is_empty(), "eight regiments is the peace target")

	var war: Dictionary = AiArmyReinforce.muster_reserve(_work_config(), _work_economy(), 8, true)
	assert_false(war.is_empty(), "a war lifts the target and the court arms up")

	var thin: Dictionary = AiArmyReinforce.muster_reserve(
		_work_config(), _work_economy(12000, 3), 5, false
	)
	assert_true(thin.is_empty(), "the fields keep their hands")

	var poor: Dictionary = AiArmyReinforce.muster_reserve(_work_config(), _work_economy(1500), 5, false)
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
		AiArmyReinforce.muster_reserve(_work_config(), economy, 5, false),
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
		AiArmyReinforce.muster_reserve(_work_config(), economy, 5, false),
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
	assert_eq(String(trace[0]["kind"]), MapPlayArmyAi.KIND_REINFORCE)
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
	assert_eq(String(trace[0]["kind"]), MapPlayArmyAi.KIND_REINFORCE)
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


func test_a_court_striking_for_food_musters_nothing() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 0
	)

	assert_eq(String(plan["muster"]), "")
	assert_true((plan["reasons"] as Array).has("striking for food"))


func test_a_court_with_room_for_one_more_ration_musters() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(
		_work_config(), _work_economy(), 1, false, 0, 1
	)

	assert_eq(String(plan["muster"]), "arquebusiers")


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
