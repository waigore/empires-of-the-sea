extends GdToolsTest
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
