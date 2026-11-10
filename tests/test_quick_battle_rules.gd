extends GdToolsTest
## Quick Battle contracts (wiki: quick-battle): three rounds, a player plan,
## deterministic casualties, the same ownership pipeline as auto-resolve, and
## virtual emplaced guns for sieges.

const Fixture = preload("res://tests/army_fixture.gd")


func test_quick_battle_is_deterministic_for_a_fixed_seed() -> void:
	var first: Dictionary = _fight("balanced", _guards(6), _pikes(4))
	var second: Dictionary = _fight("balanced", _guards(6), _pikes(4))

	assert_eq(int(first["outcome"]), int(second["outcome"]))
	assert_eq(
		(first["attacker_lost"] as Array).size(),
		(second["attacker_lost"] as Array).size()
	)
	assert_eq(
		(first["defender_lost"] as Array).size(),
		(second["defender_lost"] as Array).size()
	)
	assert_eq(_round_count(first), _round_count(second))


func test_quick_battle_runs_at_most_three_rounds() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _pikes(6))
	var rounds: int = _round_count(battle)
	assert_true(rounds >= 1)
	assert_true(rounds <= QuickBattle.MAX_ROUNDS)


func test_the_players_plan_drives_the_action_script() -> void:
	var aggressive: Dictionary = _fight("aggressive", _guards(6), _pikes(4))
	var defensive: Dictionary = _fight("defensive", _guards(6), _pikes(4))
	assert_eq(String(aggressive["quick"]["plan"]), "aggressive")
	assert_eq(String(defensive["quick"]["plan"]), "defensive")


func test_quick_battle_removes_casualties_from_the_armies() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var before: int = ArmyCombat.side_regiments(armies)

	ArmyCombat.resolve_turn(model, armies, _context("balanced"))

	assert_true(ArmyCombat.side_regiments(armies) < before)


func test_a_siege_fields_virtual_guns_and_downgrades_the_fort() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, _guards(20))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context("balanced"))
	var battle: Dictionary = reports[0]

	assert_eq(String(battle["battle_mode"]), "siege")
	assert_eq(int(battle["quick"]["guns_start"]), 1)
	assert_true(bool(battle["quick"]["fort_downgraded"]))
	assert_eq(int(battle["quick"]["guns_lost"]), 1, "the battery is silenced")
	assert_eq(String(battle["quick"]["gun_type"]), "royal_artillery")
	assert_eq(int(battle["quick"]["fort_after"]), 0)
	assert_eq(model.province_data(2).fort_level, 0)


## The wall lanes are recorded for the despatch: infantry man the parapet, the
## battery and horse shelter behind it (wiki: siege-mechanics).
func test_a_siege_records_the_wall_lanes() -> void:
	var battle: Dictionary = _fight(
		"balanced", _guards(8), ["pikemen", "musketeers", "culverin"], 2
	)
	var lanes: Dictionary = battle["quick"]["lanes"]

	assert_eq(int(lanes["wall"]), 2, "two infantry regiments hold the wall")
	assert_eq(int(lanes["behind"]), 1, "the gun waits behind the parapet")


## Melee-only regiments cannot attack a wall or anything inside it; they need
## firearms or guns (wiki: siege-mechanics § Damage Reduction).
func test_melee_only_besiegers_are_turned_away() -> void:
	var battle: Dictionary = _fight("balanced", _pikes(8), ["peasant_levies"], 1)

	assert_eq((battle["defender_lost"] as Array).size(), 0, "the garrison is untouched")
	assert_eq(int(battle["quick"]["guns_lost"]), 0, "pikes cannot silence the battery")
	var turned: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if int(action["turned"]) > 0:
				turned = true
	assert_true(turned, "the despatch says the wall turned the blow aside")


## A garrison that leaves the wall to sortie can hit back with every regiment,
## which is how a pike garrison hurts a siege at all.
func test_a_sortie_lets_a_pike_garrison_fight() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 2
	var defender := Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var context: Dictionary = _context("aggressive")
	context["player_faction"] = 1
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_true(int(reports[0]["quick"]["sorties"]) > 0, "the defender chose to sortie")
	assert_true(
		(reports[0]["attacker_lost"] as Array).size() > 0,
		"outside the wall the pikes can reach the besiegers"
	)


## Regiment detail: the report counts the losses by regiment type, so the
## despatch can name them.
func test_the_report_tallies_losses_by_regiment_type() -> void:
	var battle: Dictionary = _fight("balanced", _guards(10), ["peasant_levies", "pikemen"], 1)
	var detail: Dictionary = battle["defender_detail"]
	var counted: int = 0
	for type_id: Variant in detail.keys():
		counted += int(detail[type_id])
		assert_true(RegimentCatalog.has_type(String(type_id)))

	assert_eq(counted, (battle["defender_lost"] as Array).size())
	assert_false(RegimentCatalog.detail_text(detail).is_empty())


func test_rival_battles_keep_the_aggregate_path() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(3), true)
	var attacker := Fixture.army(2, 0, 2, _guards(5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = _context("balanced")
	context["player_faction"] = 2

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_false(reports[0].has("quick"), "a rival battle stays auto-resolve")


func test_a_weak_attacker_is_repulsed() -> void:
	var battle: Dictionary = _fight("balanced", _pikes(2), _guards(8))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)


func test_a_quick_battle_win_awards_the_general() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = _context("balanced")
	context["roster"] = roster
	context["army_general"] = {attacker.id: "general_1"}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(int(reports[0]["medal_owner"]), 0)


func test_a_siege_battery_fires_while_guns_stand() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _pikes(8), 3)
	assert_eq(int(battle["quick"]["guns_start"]), 3)
	assert_true(int(battle["quick"]["guns_left"]) < 3)
	var fired: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if String(action["action"]) == "battery":
				fired = true
	assert_true(fired, "the emplaced battery answers the assault")


## The despatch copy reads `defender_lost` on an attacker's action as losses it
## inflicted and `attacker_lost` as its own cost, so the report must add up that
## way round: every loss a side suffered is either inflicted by the enemy or paid
## by its own action.
func test_round_despatches_add_up_to_each_sides_losses() -> void:
	var battle: Dictionary = _fight("aggressive", _guards(6), _pikes(8), 2)
	var quick: Dictionary = battle["quick"]
	var atk_inflicted: int = 0
	var atk_own: int = 0
	var def_inflicted: int = 0
	var def_own: int = 0
	for round: Dictionary in quick["rounds"]:
		for action: Dictionary in round["actions"]:
			var entry: Dictionary = action as Dictionary
			if int(entry["side"]) == int(battle["attacker"]):
				atk_inflicted += int(entry["defender_lost"])
				atk_own += int(entry["attacker_lost"])
			else:
				def_inflicted += int(entry["attacker_lost"])
				def_own += int(entry["defender_lost"])
	assert_eq(
		def_inflicted + atk_own,
		int(quick["attacker_start"]) - int(quick["attacker_left"]),
		"every attacker loss is a despatch number"
	)
	assert_eq(
		atk_inflicted + def_own,
		int(quick["defender_start"]) - int(quick["defender_left"]),
		"every defender loss is a despatch number"
	)


func _fight(
	plan: String, attacker_types: Array[String], defender_types: Array[String],
	fort: int = 0
) -> Dictionary:
	var model := Fixture.build()
	model.province_data(2).fort_level = fort
	var defender := Fixture.army(1, 1, 2, defender_types, true)
	var attacker := Fixture.army(2, 0, 2, attacker_types)
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context(plan))
	return reports[0]


func _context(plan: String) -> Dictionary:
	return {
		"quick_battle": true,
		"player_faction": 0,
		"battle_plan": plan,
		"seed": 11,
	}


func _round_count(battle: Dictionary) -> int:
	return (battle["quick"]["rounds"] as Array).size()


func _guards(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	return types


func _pikes(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("pikemen")
	return types

# --- Siege lanes (wiki: siege-mechanics § Quick Battle lanes) ---


func test_the_garrison_splits_into_wall_and_behind() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen", "musketeers", "squires", "culverin"], 1)

	assert_eq(SiegeLanes.wall_ids(side).size(), 2, "infantry man the wall")
	assert_eq(SiegeLanes.behind_ids(side).size(), 2, "horse and guns wait behind")
	assert_true(SiegeLanes.is_wall_type("guards"))
	assert_false(SiegeLanes.is_wall_type("squires"))
	assert_false(SiegeLanes.is_wall_type("culverin"))
	assert_eq(SiegeLanes.describe(side), "2 on the wall · 2 behind")


func test_melee_only_besiegers_cannot_touch_a_wall() -> void:
	var attacker: Array[ArmyState] = _lane_side(["pikemen", "knights"], 2)
	var defender: Array[ArmyState] = _lane_side(["peasant_levies"], 1)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var wanted: int = 3

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defender, wanted, 10, 2, false)

	assert_eq(int(split["turned"]), wanted, "the wall turns the pikes aside")
	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq(defender[0].count(), 1, "nobody on the wall is hurt")


func test_firearms_hit_the_wall_and_the_fort_blunts_the_blow() -> void:
	var open_field: int = _struck_lane_losses(2 - 2, 4)
	var stone: int = _struck_lane_losses(2, 4)

	assert_eq(open_field, 4, "an open field takes the whole blow")
	assert_eq(stone, ceili(4.0 * FortRules.loss_scale(2)), "the wall spares a share")
	assert_true(stone < open_field)


func test_only_artillery_reaches_behind_the_wall() -> void:
	var muskets: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 2)
	var guns: Array[ArmyState] = _lane_side(["musketeers", "musketeers", "culverin"], 2)
	var defender: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var armies: Array[ArmyState] = _lane_joined(guns, defender)

	assert_false(SiegeLanes.can_reach_behind(muskets), "small arms stay outside")
	var shot: Dictionary = SiegeLanes.strike(armies, guns, defender, 4, 10, 2, false)

	assert_true((shot["behind"] as Array).size() > 0, "guns drop shot over the parapet")
	assert_true((shot["wall"] as Array).size() > 0)

	var walls_only: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var field_only: Array[ArmyState] = _lane_joined(muskets, walls_only)
	var small: Dictionary = SiegeLanes.strike(field_only, muskets, walls_only, 4, 10, 2, false)
	assert_eq((small["behind"] as Array).size(), 0, "only artillery can hit behind")


func test_a_sortie_sheds_the_walls_protection() -> void:
	var sheltered: int = _struck_lane_losses(2, 6, false)
	var sortied: int = _struck_lane_losses(2, 6, true)

	assert_eq(sheltered, ceili(6.0 * FortRules.loss_scale(2)))
	assert_eq(sortied, 6, "outside the wall the garrison takes the whole blow")
	assert_true(sortied > sheltered)


func test_return_fire_follows_the_garrisons_range() -> void:
	var pikes: Array[ArmyState] = _lane_side(["pikemen", "pikemen"], 1)
	var muskets: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 1)
	var mixed: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "musketeers", "musketeers"], 1)

	assert_almost_eq(SiegeLanes.return_fire_share(pikes), 0.0, 0.001, "pikes cannot shoot")
	assert_almost_eq(SiegeLanes.return_fire_share(muskets), 1.0, 0.001)
	assert_almost_eq(SiegeLanes.return_fire_share(mixed), 0.5, 0.001)


func test_an_empty_garrison_absorbs_nothing() -> void:
	var attacker: Array[ArmyState] = _lane_side(["musketeers"], 2)
	var defender: Array[ArmyState] = []
	var split: Dictionary = SiegeLanes.strike(
		attacker, attacker, defender, 3, 10, 2, false
	)

	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq((split["behind"] as Array).size(), 0)
	assert_eq(int(split["turned"]), 0)
	assert_almost_eq(SiegeLanes.return_fire_share(defender), 0.0, 0.001)
	assert_false(SiegeLanes.can_reach_wall(defender))
	assert_eq(SiegeLanes.describe(defender), "0 on the wall · 0 behind")


## A hole in an army list (a pruned army) is skipped, never crashed on.
func test_a_null_army_is_skipped() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen"], 1)
	side.append(null)

	assert_eq(SiegeLanes.wall_ids(side).size(), 1)
	assert_false(SiegeLanes.behind_ids(side).size() > 0)
	assert_true(SiegeLanes.can_reach_wall(_lane_side(["musketeers"], 2)))
	assert_false(SiegeLanes.can_reach_behind(side))


func _struck_lane_losses(fort: int, wanted: int, exposed: bool = false) -> int:
	var attacker: Array[ArmyState] = _lane_side(["musketeers", "musketeers", "musketeers"], 2)
	var defender: Array[ArmyState] = _lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies", "peasant_levies",
		"peasant_levies", "peasant_levies"], 1
	)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defender, wanted, 10, fort, exposed
	)
	return (split["wall"] as Array).size() + (split["behind"] as Array).size()


func _lane_side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(Fixture.army(10 + owner, owner, 2, types, true))
	return side


func _lane_joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all
