extends GdToolsTest
## Pure AI contracts: power bands, parameters, personalities and turn records.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const AiFixture = preload("res://tests/ai_fixture.gd")
const NavalFixture = preload("res://tests/naval_fixture.gd")
const CivilianFixture = preload("res://tests/civilian_fixture.gd")


## Collects the sighting lines a rival naval pass emits.
class StubHud extends GameHud:
	var toasts: Array[String] = []

	func toast(text: String) -> void:
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
		AiDiplomacyPlanner.KIND_OVERTURE,
		"a court that cannot fight courts a friend instead"
	)
	assert_eq(String(record["candidates"][0]["blocked"]), "war desire too low")


func test_a_second_turn_does_not_repeat_the_war() -> void:
	# The weak court ends a war it no longer wants (desire 10 < 50), and the
	# stronger one cannot re-declare on the pair until its 4-turn war cooldown
	# ends (wiki: diplomacy § Planner selection, § Cooldowns).
	var run: Dictionary = _run()
	var result: Dictionary = AiTurn.run(
		run["state"], AiFixture.world([2, 2, 2, 2, 1]), run["ai"], 2, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_true((record["action"] as Dictionary).is_empty())
	assert_false((run["state"] as DiplomacyState).relation(1, 2).at_war)
	assert_eq(String(record["candidates"][0]["blocked"]), "war cooldown")


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
	var split: Dictionary = ArmyState.split(armies, armies[1], ids, 10)
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
	var split: Dictionary = ArmyState.split(armies, armies[0], ids, 10)
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
	ArmyState.split(armies, armies[0], ids, 10)
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
	var split: Dictionary = ArmyState.split(armies, armies[0], ids, 10)
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
	var split: Dictionary = ArmyState.split(armies, armies[1], ids, 10)
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


func test_ai_naval_holds_station_at_peace() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 2, 1, "galleon"),
		_squadron(1, 1, 0, "sloop"),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _peace_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_ai_naval_sorties_from_a_port_into_a_hostile_zone() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var moored := FleetState.in_port(0, 2, 0, ["h0"] as Array[String], {"h0": "galleon"})
	var fleets: Array[FleetState] = [moored, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_SORTIE)
	assert_eq(int(plan["orders"][0]["zone"]), 0, "the zone off its own harbour")


func test_ai_naval_never_sorties_the_home_fleet() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(0, 1500)
	var home := FleetState.in_port(0, 0, 0, ["h0"] as Array[String], {"h0": "galleon"})
	var fleets: Array[FleetState] = [home, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(0, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0, "the home fleet holds its capital")
	assert_true(home.is_in_port())


func test_ai_naval_needs_a_hostile_fleet_at_sea() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var fleets: Array[FleetState] = [
		_squadron(0, 2, 1, "galleon"),
		FleetState.in_port(1, 1, 1, ["h1"] as Array[String], {"h1": "sloop"}),
	]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0, "a port fleet is not a target")


func test_ai_naval_skips_a_squadron_that_already_moved() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var spent: FleetState = _squadron(0, 2, 1, "galleon")
	spent.moved = true
	var fleets: Array[FleetState] = [spent, _squadron(1, 1, 0, "sloop")]
	var plan: Dictionary = AiNavalPlanner.orders(config, _war_state(2, 1), model, fleets)
	assert_eq((plan["orders"] as Array).size(), 0)


## A court hunts only water it charts: the New World starts unknown for every
## rival, so a hostile squadron there is invisible until a ship enters the zone
## (wiki: fog-and-exploration; DR-20261110-21).
func test_ai_naval_never_hunts_into_uncharted_water() -> void:
	var model: MapModel = NavalFixture.build()
	model.region_id = WorldMap.NEW_WORLD
	var world := WorldMap.new()
	# A filler region keeps the New World at index 1, its own region id.
	world.add_region(MapModel.new())
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
	assert_eq((blind["orders"] as Array).size(), 0, "the hostile zone is uncharted")
	charts.reveal_sea_zone(2, 1, 0)
	var sighted: Dictionary = AiNavalPlanner.orders(
		config, _war_state(2, 1), model, fleets, charts
	)
	assert_eq((sighted["orders"] as Array).size(), 1, "a charted zone is hunted")
	assert_eq(int(sighted["orders"][0]["zone"]), 0)


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
	economy.set_assignment("lumber", 2)
	var restored: AiState = AiState.from_dict(ai.to_dict())
	var loaded: PlayerEconomy = restored.economy_for(1)
	assert_eq(loaded.quantity("grain"), economy.quantity("grain"))
	assert_eq(loaded.treasury, economy.treasury)
	assert_eq(loaded.assignment_units("lumber"), 2)


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
	for assignment: Dictionary in assignments:
		var recipe: String = String(assignment["recipe"])
		var units: int = int(assignment["units"])
		labour_used += units * ProductionRecipes.labour(recipe)
		timber_used += units * int(ProductionRecipes.inputs(recipe).get("timber", 0))
	assert_eq(labour_used, 6, "the plan spends exactly the available labour")
	assert_true(timber_used <= 10, "the same timber is never promised twice")
	assert_eq(assignments.size(), 2, "wool fabric and lumber fill their deficits")


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


func test_map_phase_resolves_rival_economies_and_civilian_work() -> void:
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
	MapPlayDiplomacy.run_ai(play)
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
