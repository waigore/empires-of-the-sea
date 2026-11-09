extends GdToolsTest
## Pure battle contracts: army modifiers, army state, battle reports, naval
## combat and generals.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const Fixture = preload("res://tests/army_fixture.gd")
const FACTIONS: Array[String] = ["España", "England", "France", "Portugal"]

# --- from test_army_modifiers.gd ---
## Combat modifiers: feeding, medals, deployment, terrain and leaders
## (wiki: combat § Modifiers and configurable values, military-generals § Medals).


func test_feeding_bands_follow_the_published_table() -> void:
	assert_almost_eq(ArmyModifiers.feeding_multiplier(1.0), 1.0, 0.001)
	assert_almost_eq(ArmyModifiers.feeding_multiplier(0.75), 0.75, 0.001)
	assert_almost_eq(ArmyModifiers.feeding_multiplier(0.5), 0.75, 0.001)
	assert_almost_eq(ArmyModifiers.feeding_multiplier(0.49), 0.5, 0.001)


func test_medal_aura_is_five_percent_per_medal_capped_at_twenty() -> void:
	assert_almost_eq(ArmyModifiers.medal_aura(0), 1.0, 0.001)
	assert_almost_eq(ArmyModifiers.medal_aura(2), 1.1, 0.001)
	assert_almost_eq(ArmyModifiers.medal_aura(4), 1.2, 0.001)
	assert_almost_eq(ArmyModifiers.medal_aura(9), 1.2, 0.001)


func test_deployment_limit_grows_with_medals_and_nationalism() -> void:
	assert_eq(ArmyModifiers.deployment_limit(0, false), 10)
	assert_eq(ArmyModifiers.deployment_limit(2, false), 12)
	assert_eq(ArmyModifiers.deployment_limit(0, true), 12)
	assert_eq(ArmyModifiers.deployment_limit(4, true), 16)


func test_terrain_uses_the_dominant_type_and_favours_the_defender() -> void:
	var model := Fixture.build()
	for tile: Vector2i in model.province_data(2).tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HILLS
	assert_eq(ArmyModifiers.terrain_for(model, 2), MapModel.Terrain.HILLS)
	assert_almost_eq(ArmyModifiers.terrain_multiplier(MapModel.Terrain.HILLS), 1.15, 0.001)
	assert_almost_eq(ArmyModifiers.terrain_multiplier(MapModel.Terrain.PLAINS), 1.0, 0.001)


func test_leader_keys_match_exact_and_variant_ids() -> void:
	assert_almost_eq(ArmyModifiers.leader_multiplier("napoleon"), 1.25, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier("france_napoleon_leader"), 1.25, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier("frederick"), 1.15, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier(""), 1.0, 0.001)
	assert_eq(ArmyModifiers.fallback_medals("napoleon"), 4)
	assert_eq(ArmyModifiers.fallback_medals("frederick"), 2)
	assert_eq(ArmyModifiers.fallback_medals(""), 0)


func test_deployed_keeps_the_strongest_regiments() -> void:
	var types: Array[String] = ["guards"]
	for _index in 11:
		types.append("peasant_levies")
	var side: Array[ArmyState] = [Fixture.army(1, 0, 2, types)]
	var deployed: Array[Dictionary] = ArmyModifiers.deployed(side, 10)

	assert_eq(deployed.size(), 10)
	var guards: int = 0
	for entry: Dictionary in deployed:
		var army: ArmyState = entry["army"]
		if army.type_of(String(entry["id"])) == "guards":
			guards += 1
	assert_eq(guards, 1, "the strongest regiment stays deployed")


func test_strength_scales_the_deployed_slice() -> void:
	var side: Array[ArmyState] = [Fixture.army(1, 0, 2, ["pikemen", "pikemen"])]
	assert_almost_eq(ArmyModifiers.strength(side, 10, 1.2), 12.0, 0.001)


func test_modifiers_compose_terrain_feeding_and_leader() -> void:
	var model := Fixture.build()
	for tile: Vector2i in model.province_data(2).tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HILLS
	var context: Dictionary = {
		"feeding": {1: 0.5},
		"leaders": {1: "napoleon"},
	}
	var defender: Dictionary = ArmyModifiers.modifiers(context, 0, true, model, 2, 1)
	assert_almost_eq(float(defender["multiplier"]), 0.75 * 1.25 * 1.15, 0.001)
	var attacker: Dictionary = ArmyModifiers.modifiers(context, 0, false, model, 2, 1)
	assert_almost_eq(float(attacker["multiplier"]), 0.75 * 1.25, 0.001)

	var nationalism: Dictionary = {"tech": {1: {"nationalism": true}}}
	var limit: int = int(ArmyModifiers.modifiers(nationalism, 2, false, model, 2, 1)["limit"])
	assert_eq(limit, 14)

# --- from test_army_state.gd ---
## Army containers: composition, split, combine and the Home Army invariant
## (wiki: military-armies).


func test_muster_mints_stable_regiment_instances() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen", "squires", "pikemen"], true)
	assert_eq(army.count(), 3)
	assert_true(army.is_home_army())
	assert_eq(army.type_of("unit_101"), "pikemen")
	assert_eq(army.type_of("unit_102"), "squires")
	assert_eq(army.count_of_type("pikemen"), 2)
	assert_almost_eq(army.strength(), 14.0, 0.001)
	assert_almost_eq(army.cavalry_share(), 1.0 / 3.0, 0.001)
	assert_eq(army.composition_text(), "2 Pikemen · Squires")


func test_unknown_regiment_types_fall_back_to_the_default() -> void:
	var army := ArmyState.create(1, 0, 0, false, ["unit_1"], {"unit_1": "dragoons"})
	assert_eq(army.type_of("unit_1"), RegimentCatalog.DEFAULT_TYPE)
	assert_eq(army.type_of("missing"), RegimentCatalog.DEFAULT_TYPE)


func test_split_moves_only_the_chosen_instances() -> void:
	var army := Fixture.army(1, 0, 0, ["peasant_levies", "pikemen", "guards"], true)
	army.moved = true
	var armies: Array[ArmyState] = [army]
	var ids: Array[String] = ["unit_102"]

	var result: Dictionary = ArmyState.split(armies, army, ids, 2)

	assert_true(bool(result["ok"]))
	assert_eq(armies.size(), 2)
	assert_eq(army.count(), 2)
	assert_false(army.regiments.has("unit_102"))
	var field: ArmyState = result["army"] as ArmyState
	assert_eq(field.count(), 1)
	assert_eq(field.type_of("unit_102"), "pikemen")
	assert_eq(field.province, army.province)
	assert_eq(field.owner, army.owner)
	assert_false(field.is_home_army())
	assert_true(field.moved)


func test_split_rejects_unknown_or_empty_selections() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"], true)
	var armies: Array[ArmyState] = [army]
	var none: Array[String] = []
	assert_false(bool(ArmyState.split(armies, army, none, 2)["ok"]))
	var foreign: Array[String] = ["unit_999"]
	assert_false(bool(ArmyState.split(armies, army, foreign, 2)["ok"]))
	assert_eq(army.count(), 1)


func test_emptying_a_field_army_removes_it_but_the_home_army_persists() -> void:
	var home := Fixture.army(1, 0, 0, ["pikemen"], true)
	var field := Fixture.army(2, 0, 1, ["pikemen"])
	var armies: Array[ArmyState] = [home, field]
	var home_ids: Array[String] = ["unit_101"]
	var field_ids: Array[String] = ["unit_201"]

	ArmyState.split(armies, field, field_ids, 3)
	ArmyState.split(armies, home, home_ids, 4)

	assert_false(armies.has(field))
	assert_true(armies.has(home))
	assert_true(home.is_empty())


func test_combine_uses_the_home_army_as_the_target() -> void:
	var field := Fixture.army(1, 0, 0, ["pikemen"])
	var home := Fixture.army(2, 0, 0, ["squires"], true)
	var armies: Array[ArmyState] = [field, home]
	var selected: Array[ArmyState] = [field, home]

	var result: Dictionary = ArmyState.combine(armies, selected)

	assert_true(bool(result["ok"]))
	assert_eq(armies.size(), 1)
	assert_true(armies[0].is_home_army())
	assert_eq(armies[0].count(), 2)
	assert_eq(armies[0].count_of_type("pikemen"), 1)
	assert_eq(armies[0].count_of_type("squires"), 1)


func test_combine_keeps_the_first_army_when_no_home_army_is_present() -> void:
	var first := Fixture.army(1, 0, 0, ["pikemen"])
	var second := Fixture.army(2, 0, 0, ["squires"])
	var armies: Array[ArmyState] = [first, second]
	var selected: Array[ArmyState] = [first, second]

	var result: Dictionary = ArmyState.combine(armies, selected)

	assert_true(bool(result["ok"]))
	assert_eq(result["army"], first)
	assert_eq(first.count(), 2)
	assert_false(armies.has(second))


func test_combine_rejects_armies_in_different_provinces() -> void:
	var here := Fixture.army(1, 0, 0, ["pikemen"])
	var there := Fixture.army(2, 0, 1, ["pikemen"])
	var armies: Array[ArmyState] = [here, there]
	var selected: Array[ArmyState] = [here, there]

	var result: Dictionary = ArmyState.combine(armies, selected)

	assert_false(bool(result["ok"]))
	assert_eq(armies.size(), 2)
	assert_eq(here.count(), 1)
	assert_eq(there.count(), 1)


func test_combine_requires_two_armies() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var armies: Array[ArmyState] = [army]
	var selected: Array[ArmyState] = [army]
	assert_false(bool(ArmyState.combine(armies, selected)["ok"]))


func test_prune_drops_empty_field_armies_only() -> void:
	var none: Array[String] = []
	var home := Fixture.army(1, 0, 0, none, true)
	var field := Fixture.army(2, 0, 1, none)
	var armies: Array[ArmyState] = [home, field]
	ArmyState.prune(armies)
	assert_eq(armies.size(), 1)
	assert_true(armies.has(home))

# --- from test_battle_report.gd ---
## Despatch wording for resolved battles (moved out of the screen controller).


func test_a_side_one_victory_reads_as_a_held_zone() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["a", "b"],
	}
	assert_eq(BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"España holds the Windward Passage — England loses 2 ships")


func test_a_side_two_victory_reads_as_a_repulse() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 2,
		"outcome": NavalCombat.Outcome.SIDE2_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": [],
	}
	assert_eq(BattleReport.describe(battle, "Gulf of Darién", FACTIONS),
		"France repels England in the Gulf of Darién — 1 ships lost")


func test_a_stalemate_reads_as_a_withdrawal() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 3,
		"outcome": NavalCombat.Outcome.STALEMATE,
		"attacker_lost": [],
		"defender_lost": [],
	}
	assert_eq(BattleReport.describe(battle, "Azores", FACTIONS),
		"España and Portugal trade broadsides in the Azores and withdraw")


func test_unknown_flags_do_not_crash_the_despatch() -> void:
	var battle: Dictionary = {
		"attacker": 9,
		"defender": -1,
		"outcome": NavalCombat.Outcome.STALEMATE,
	}
	var text: String = BattleReport.describe(battle, "Nowhere", FACTIONS)
	assert_true(text.contains("An unknown flag"))


func test_a_land_victory_reads_as_a_capture() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": ["b", "c"],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Flanders", FACTIONS),
		"España takes Flanders — England loses 2 regiments"
	)


func test_a_land_repulse_reads_as_a_hold() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 2,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": [],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Burgundy", FACTIONS),
		"France holds Burgundy — England loses 1 regiments"
	)


func test_mutual_annihilation_reports_the_reformed_garrison() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		"garrison": 1,
		"recovered_type": "guards",
	}
	assert_eq(
		BattleReport.describe_land(battle, "Artois", FACTIONS),
		"España and England destroy each other at Artois — a Guards garrison reforms"
	)


func test_mutual_annihilation_without_a_garrison_reads_empty() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		"garrison": 0,
	}
	assert_eq(
		BattleReport.describe_land(battle, "Artois", FACTIONS),
		"España and England destroy each other at Artois — the province stands empty"
	)


func test_an_unopposed_capture_and_a_stalemate_read_plainly() -> void:
	var capture: Dictionary = {
		"attacker": 0,
		"defender": 3,
		"outcome": ArmyCombat.Outcome.CAPTURE,
	}
	assert_eq(
		BattleReport.describe_land(capture, "Algarve", FACTIONS),
		"España occupies Algarve unopposed"
	)
	var standoff: Dictionary = {
		"attacker": 0,
		"defender": 2,
		"outcome": ArmyCombat.Outcome.STALEMATE,
	}
	assert_eq(
		BattleReport.describe_land(standoff, "Picardy", FACTIONS),
		"España and France stand off at Picardy"
	)

# --- from test_naval_combat.gd ---
## Sea-zone combat (wiki: ships-and-naval § Naval Combat).


func _fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet


func _squadron(id: int, owner: int, zone: int, type_id: String, count: int) -> FleetState:
	var types: Array = []
	for _index in count:
		types.append(type_id)
	return _fleet(id, owner, zone, types)


func test_side_strength_and_durability_aggregate_every_hull() -> void:
	var fleet: FleetState = _fleet(1, 0, 3, ["carrack", "sloop"])
	assert_almost_eq(NavalCombat.side_strength([fleet]), 6.0, 0.0001)
	assert_almost_eq(NavalCombat.side_durability([fleet]), 4.4, 0.0001)
	assert_eq(NavalCombat.side_hull_count([fleet]), 2)


func test_contested_zones_need_two_factions_at_sea() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var dutch: FleetState = _squadron(2, 1, 2, "fluyte", 1)
	var ally: FleetState = _squadron(3, 0, 2, "sloop", 1)
	assert_eq(NavalCombat.contested_zones([spanish, dutch, ally]), [2])


func test_single_faction_or_port_fleets_do_not_fight() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 1)
	var consort: FleetState = _squadron(2, 0, 2, "carrack", 1)
	var docked: FleetState = FleetState.in_port(3, 1, 0)
	assert_eq(NavalCombat.contested_zones([spanish, consort, docked]), [])


func test_peaceful_fleets_do_not_contest_a_zone() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var dutch: FleetState = _squadron(2, 1, 2, "fluyte", 1)
	var peace := func(_a: int, _b: int) -> bool: return false
	var war := func(_a: int, _b: int) -> bool: return true
	assert_eq(NavalCombat.contested_zones([spanish, dutch], peace), [])
	assert_true(NavalCombat.resolve_turn([spanish, dutch], peace).is_empty())
	assert_eq(NavalCombat.contested_zones([spanish, dutch], war), [2])


func test_a_third_party_at_peace_stays_out_of_a_war() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 3)
	var dutch: FleetState = _squadron(2, 1, 2, "fluyte", 1)
	var swede: FleetState = _squadron(3, 5, 2, "carrack", 1)
	var only_dutch_at_war := func(a: int, b: int) -> bool:
		return (a == 0 and b == 1) or (a == 1 and b == 0)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[spanish, dutch, swede], only_dutch_at_war
	)
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["defender"]), 1)
	assert_eq(swede.ship_count(), 1, "a neutral fleet is untouched")


func test_the_moved_fleet_attacks() -> void:
	var defender: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var attacker: FleetState = _squadron(2, 1, 2, "sloop", 2)
	attacker.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([defender, attacker])
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 1)
	assert_eq(int(battles[0]["defender"]), 0)


func test_without_a_mover_the_lowest_owner_takes_the_initiative() -> void:
	var first: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var second: FleetState = _squadron(2, 2, 2, "fluyte", 1)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([second, first])
	assert_eq(int(battles[0]["attacker"]), 0)


func test_matched_squadrons_stalemate_without_losses() -> void:
	var first: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var second: FleetState = _squadron(2, 1, 2, "carrack", 2)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([first, second])
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.STALEMATE)
	assert_eq(first.ship_count(), 2)
	assert_eq(second.ship_count(), 2)
	assert_eq(NavalCombat.outcome_label(int(battles[0]["outcome"])), "stalemate")


## Wiki: share > 0.53 wins for the attacker and share < 0.47 wins for the
## defender — 0.53 exactly is still a stalemate (§ Naval Combat Resolution).
func test_a_share_of_exactly_fifty_three_percent_is_a_stalemate() -> void:
	var attacker: FleetState = _fleet(
		1, 0, 9, _types("carrack", 4) + _types("fluyte", 24)
	)
	var defender: FleetState = _fleet(
		2, 1, 9, _types("carrack", 5) + _types("fluyte", 19)
	)
	attacker.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([attacker, defender])
	assert_eq(battles.size(), 1)
	assert_almost_eq(float(battles[0]["attacker_strength"]), 53.0, 0.0001)
	assert_almost_eq(float(battles[0]["defender_strength"]), 47.0, 0.0001)
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.STALEMATE)
	assert_eq(attacker.ship_count(), 28)
	assert_eq(defender.ship_count(), 24)


func _types(type_id: String, count: int) -> Array:
	var out: Array = []
	for _index in count:
		out.append(type_id)
	return out


func test_stronger_side_breaks_the_weaker_squadron() -> void:
	var strong: FleetState = _squadron(1, 0, 2, "carrack", 3)
	var weak: FleetState = _squadron(2, 1, 2, "carrack", 1)
	strong.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.SIDE1_VICTORY)
	assert_eq(weak.ship_count(), 0)
	assert_false(weak.is_afloat())
	assert_eq(int((battles[0]["defender_lost"] as Array).size()), 1)


func test_the_victor_pays_for_its_win() -> void:
	var strong: FleetState = _squadron(1, 0, 2, "carrack", 3)
	var frigate: FleetState = _fleet(2, 1, 2, ["frigate"])
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, frigate])
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.SIDE1_VICTORY)
	assert_eq(frigate.ship_count(), 0)
	# 5.8 strength * 0.5 damage covers one 2.2-durability carrack, not two.
	assert_eq(int((battles[0]["attacker_lost"] as Array).size()), 1)
	assert_eq(strong.ship_count(), 2)


func test_attacking_into_a_stronger_fleet_loses_the_attackers() -> void:
	var attacker: FleetState = _squadron(1, 1, 4, "fluyte", 1)
	attacker.moved = true
	var defender: FleetState = _squadron(2, 0, 4, "frigate", 2)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([attacker, defender])
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.SIDE2_VICTORY)
	assert_eq(attacker.ship_count(), 0)
	assert_eq(defender.ship_count(), 2)
	assert_eq(NavalCombat.outcome_label(int(battles[0]["outcome"])), "defender victory")


func test_multi_faction_zone_resolves_one_engagement_per_defender() -> void:
	var host: FleetState = _squadron(1, 0, 5, "carrack", 4)
	var first: FleetState = _squadron(2, 1, 5, "fluyte", 1)
	var second: FleetState = _squadron(3, 2, 5, "fluyte", 1)
	host.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([host, second, first])
	assert_eq(battles.size(), 2)
	assert_eq(int(battles[0]["defender"]), 1)
	assert_eq(int(battles[1]["defender"]), 2)
	assert_eq(first.ship_count(), 0)
	assert_eq(second.ship_count(), 0)
	assert_gt(host.ship_count(), 0)


func test_resolution_is_deterministic() -> void:
	var first: FleetState = _squadron(1, 0, 7, "carrack", 3)
	var second: FleetState = _squadron(2, 1, 7, "sloop", 2)
	var once: Array[Dictionary] = NavalCombat.resolve_turn([first, second])
	var first_again: FleetState = _squadron(1, 0, 7, "carrack", 3)
	var second_again: FleetState = _squadron(2, 1, 7, "sloop", 2)
	var twice: Array[Dictionary] = NavalCombat.resolve_turn([first_again, second_again])
	assert_eq(once, twice)
	assert_eq(first.hulls, first_again.hulls)
	assert_eq(second.hulls, second_again.hulls)


func test_battle_report_fields_describe_the_sides() -> void:
	var strong: FleetState = _squadron(1, 0, 8, "carrack", 3)
	var weak: FleetState = _squadron(2, 1, 8, "carrack", 1)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	var battle: Dictionary = battles[0]
	assert_eq(int(battle["zone"]), 8)
	assert_eq(int(battle["attacker_before"]), 3)
	assert_eq(int(battle["defender_before"]), 1)
	assert_almost_eq(float(battle["attacker_strength"]), 8.25, 0.0001)
	assert_almost_eq(float(battle["defender_strength"]), 2.75, 0.0001)

# --- from test_generals.gd ---
## General pool, tech-gated cap, pre-Combat binding and medals
## (wiki: military-generals § Generals).


func test_cap_follows_the_tech_floors_without_stacking() -> void:
	assert_eq(GeneralRoster.cap_for({}), 1)
	assert_eq(GeneralRoster.cap_for({"organised_regiments": true}), 2)
	assert_eq(
		GeneralRoster.cap_for({"organised_regiments": true, "national_bureaucracy": true}),
		3
	)
	assert_eq(
		GeneralRoster.cap_for(
			{"national_bureaucracy": true, "improved_infantry_tactics": true}
		),
		3
	)
	assert_eq(GeneralRoster.cap_for({"nationalism": true}), 4)


func test_sync_spawns_to_cap_and_never_trims() -> void:
	var roster := GeneralRoster.new()
	assert_eq(roster.sync(0, {}), 1)
	assert_eq(roster.sync(0, {"organised_regiments": true}), 2)
	assert_eq(roster.medals(0, "general_2"), 0)
	assert_eq(roster.sync(0, {}), 2, "above-cap rosters are tolerated")
	assert_eq(roster.ids(0).size(), 2)


func test_medals_gain_one_per_win_and_cap_at_four() -> void:
	var roster := GeneralRoster.new()
	roster.pool(0)
	for expected: int in [1, 2, 3, 4, 4]:
		assert_eq(roster.award(0, "general_1"), expected)
	assert_eq(roster.summary(0), "1 general · 4 medals")


func test_save_dict_round_trip_keeps_pools_and_medals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(0, {"nationalism": true})
	roster.sync(1, {"organised_regiments": true})
	roster.award(0, "general_1")
	roster.award(0, "general_1")
	roster.award(0, "general_3")

	# The save store keeps typed variants, but string keys must also restore.
	var restored: GeneralRoster = GeneralRoster.from_dict(roster.to_dict())
	var from_text: GeneralRoster = GeneralRoster.from_dict({
		"pools": {"0": [{"id": "general_1", "medals": 2}]}
	})

	assert_eq(restored.count(0), 4, "the persisted cap is the pool size")
	assert_eq(restored.medals(0, "general_1"), 2, "earned medals survive")
	assert_eq(restored.medals(0, "general_3"), 1)
	assert_eq(restored.medals(0, "general_2"), 0)
	assert_eq(restored.count(1), 2)
	assert_eq(from_text.count(0), 1, "string keys rebuild the pool")
	assert_eq(from_text.medals(0, "general_1"), 2)


func test_from_dict_tolerates_junk_and_caps_medals() -> void:
	var roster: GeneralRoster = GeneralRoster.from_dict({"pools": {
		"2": [{"id": "general_1", "medals": 99}, {"id": ""}, 7],
		3: "nope",
	}})
	assert_eq(roster.count(2), 1, "only usable general rows load")
	assert_eq(roster.medals(2, "general_1"), GeneralRoster.MAX_MEDALS)


func test_binding_gives_one_general_per_attacking_army() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"])
	var first := Fixture.army(2, 0, 2, ["pikemen"])
	first.moved = true
	var second := Fixture.army(3, 0, 2, ["pikemen"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, GeneralRoster.new(), 3
	)["army_general"]

	assert_eq(bindings.size(), 2)
	assert_true(bindings.has(first.id) != bindings.has(second.id))
	assert_true(bindings.has(defender.id), "the defender also gets a commander")


func test_defender_binding_stops_when_the_pool_is_spent() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var first := Fixture.army(1, 1, 2, ["peasant_levies"])
	var second := Fixture.army(2, 1, 2, ["peasant_levies"])
	var attacker := Fixture.army(3, 0, 2, ["guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [first, second, attacker]
	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, GeneralRoster.new(), 5
	)["army_general"]

	assert_eq(bindings.size(), 2)
	assert_true(bindings.has(attacker.id))
	assert_true(bindings.has(first.id) != bindings.has(second.id))


func test_one_general_covers_both_an_attack_and_a_defence() -> void:
	# The attack cap is offensive-only: defender binding draws from generals not
	# bound to another *defending* army, so a cap-1 crown can still command its
	# home battle in the same Combat phase (wiki: military-generals § Assignment).
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var defender_of_two := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacker := Fixture.army(2, 0, 2, ["pikemen"])
	attacker.moved = true
	var invader := Fixture.army(3, 2, 0, ["pikemen"])
	invader.moved = true
	var home_defender := Fixture.army(4, 0, 0, ["peasant_levies"])
	var armies: Array[ArmyState] = [defender_of_two, attacker, invader, home_defender]
	var roster := GeneralRoster.new()
	assert_eq(roster.count(0), 1, "the crown has a single general")

	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, roster, 0
	)["army_general"]

	assert_eq(
		String(bindings.get(attacker.id, "")),
		"general_1",
		"the offensive commitment takes the general"
	)
	assert_eq(
		String(bindings.get(home_defender.id, "")),
		"general_1",
		"the defence still draws the general from its own pool"
	)


func test_unbound_sides_use_the_leader_fallback_medals() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "napoleon"}}), 4)
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "frederick"}}), 2)
	assert_eq(ArmyCommand.medals(side, {}), 0)


func test_the_phase_medal_snapshot_beats_newly_earned_medals() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 3:
		roster.award(0, "general_1")
	var context: Dictionary = {
		"roster": roster,
		"army_general": {army.id: "general_1"},
		"army_medals": {army.id: 1},
	}
	assert_eq(ArmyCommand.medals(side, context), 1)


func test_a_winning_general_earns_a_medal() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(int(reports[0]["medal_owner"]), 0)
	assert_eq(roster.medals(0, "general_1"), 1)


func test_a_four_medal_general_gains_nothing_more() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 4:
		roster.award(0, "general_1")
	var context: Dictionary = {
		"roster": roster,
		"army_general": {attacker.id: "general_1"},
		"army_medals": {attacker.id: 4},
	}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(roster.medals(0, "general_1"), 4)
	assert_eq(String(reports[0]["medal_gain"]), "")


func test_a_losing_general_keeps_his_medals() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["guards", "guards", "guards"])
	var attacker := Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(roster.medals(0, "general_1"), 0)
	assert_eq(String(reports[0]["medal_gain"]), "")
