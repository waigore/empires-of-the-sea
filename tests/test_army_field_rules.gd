extends GdToolsTest
## Army marches, battles and unopposed capture on the shared army fixture.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const Fixture = preload("res://tests/army_fixture.gd")
var _model: MapModel = null

func before_each() -> void:
	_model = Fixture.build()

# --- from test_army_movement.gd ---
## Army marches: interior lines, adjacent hostile land, Home Army immobility
## (wiki: military-armies § Movement and attacks).

func test_owned_provinces_are_reachable_and_enemy_land_must_border() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var expected: Array[int] = [1, 2, 6]
	assert_eq(ArmyMovement.destinations(_model, army), expected)


func test_owned_island_across_water_is_not_a_land_destination() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var destinations: Array[int] = ArmyMovement.destinations(_model, army)
	assert_false(destinations.has(5))
	var check: Dictionary = ArmyMovement.can_move(_model, army, 5)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("water"))
	assert_false(ArmyMovement.land_reachable(_model, 0, 0).has(5))
	assert_true(ArmyMovement.land_reachable(_model, 0, 0).has(1))


func test_destinations_from_the_far_colony_reach_both_neighbours() -> void:
	var army := Fixture.army(1, 0, 1, ["pikemen"])
	var expected: Array[int] = [0, 3, 4, 6]
	assert_eq(ArmyMovement.destinations(_model, army), expected)


func test_the_home_army_never_marches() -> void:
	var home := Fixture.army(1, 0, 0, ["pikemen"], true)
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_model, home), none)
	var check: Dictionary = ArmyMovement.can_move(_model, home, 1)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Home Army"))


func test_a_moved_army_has_no_march_left() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	army.moved = true
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_model, army), none)
	assert_false(bool(ArmyMovement.can_move(_model, army, 1)["ok"]))


func test_empty_armies_cannot_march() -> void:
	var none: Array[String] = []
	var army := Fixture.army(1, 0, 0, none)
	assert_false(bool(ArmyMovement.can_move(_model, army, 1)["ok"]))


func test_owned_destination_anywhere_is_legal_even_without_adjacency() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	assert_true(bool(ArmyMovement.can_move(_model, army, 1)["ok"]))


func test_neutral_or_enemy_land_far_away_is_refused() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	assert_false(bool(ArmyMovement.can_move(_model, army, 3)["ok"]))
	assert_true(bool(ArmyMovement.can_move(_model, army, 2)["ok"]))


func test_foreign_land_needs_war_but_wilderness_does_not() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var refused: Dictionary = ArmyMovement.can_move(_model, army, 2, false)
	assert_false(bool(refused["ok"]), "province 2 belongs to faction 1")
	assert_true(String(refused["reason"]).contains("declare war"))
	assert_true(bool(ArmyMovement.can_move(_model, army, 2, true)["ok"]))
	var colonist := Fixture.army(2, 0, 1, ["pikemen"])
	assert_true(
		bool(ArmyMovement.can_move(_model, colonist, 3, false)["ok"]),
		"unowned wilderness beside the colony is not an invasion"
	)
	var march: Dictionary = ArmyMovement.apply_move(_model, army, 2, false)
	assert_false(bool(march["ok"]))
	assert_eq(army.province, 0)
	assert_false(army.moved)


func test_invalid_and_current_provinces_are_refused() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	assert_false(bool(ArmyMovement.can_move(_model, army, 0)["ok"]))
	assert_false(bool(ArmyMovement.can_move(_model, army, 99)["ok"]))
	assert_false(bool(ArmyMovement.can_move(_model, null, 1)["ok"]))


func test_apply_move_reports_an_attack_and_spends_the_turn() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var result: Dictionary = ArmyMovement.apply_move(_model, army, 2)
	assert_true(bool(result["ok"]))
	assert_true(bool(result["attacked"]))
	assert_eq(army.province, 2)
	assert_true(army.moved)


func test_apply_move_into_own_land_is_not_an_attack() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var result: Dictionary = ArmyMovement.apply_move(_model, army, 1)
	assert_true(bool(result["ok"]))
	assert_false(bool(result["attacked"]))


func test_begin_turn_restores_one_march() -> void:
	var first := Fixture.army(1, 0, 0, ["pikemen"])
	var second := Fixture.army(2, 0, 1, ["pikemen"])
	first.moved = true
	second.moved = true
	var armies: Array[ArmyState] = [first, second]
	ArmyMovement.begin_turn(armies)
	assert_false(first.moved)
	assert_false(second.moved)

# --- from test_army_combat.gd ---
## Land battles and unopposed capture (wiki: combat, military-armies § Combat
## and province loss).

func test_side_strength_aggregates_fpn_and_fpm() -> void:
	var first := Fixture.army(1, 0, 0, ["pikemen", "pikemen"])
	var second := Fixture.army(2, 0, 0, ["squires"])
	var side: Array[ArmyState] = [first, second]
	assert_almost_eq(ArmyCombat.side_strength(side), 14.0, 0.001)
	assert_eq(ArmyCombat.side_regiments(side), 3)
	assert_almost_eq(ArmyCombat.initiative(side), 50.0 / 3.0, 0.001)


func test_contested_provinces_need_a_great_power_mover() -> void:
	var attacker := Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var minor := Fixture.army(2, 6, 2, ["pikemen"])
	minor.moved = true
	var idle := Fixture.army(3, 0, 3, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, minor, idle]
	var expected: Array[int] = [2]
	assert_eq(ArmyCombat.contested_provinces(_model, armies), expected)


func test_unopposed_capture_flips_the_province() -> void:
	var attacker := Fixture.army(1, 0, 2, ["peasant_levies", "pikemen"])
	attacker.moved = true
	var armies: Array[ArmyState] = [attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.CAPTURE)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_model.province_owner(2), 0)
	assert_eq(attacker.count(), 2)


func test_a_third_faction_blocks_an_unopposed_capture() -> void:
	var attacker := Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var third := Fixture.army(2, 2, 2, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, third]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(reports.size(), 0)
	assert_eq(_model.province_owner(2), 1)


func test_attacker_victory_eliminates_the_home_army_and_flips() -> void:
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_model.province_owner(2), 0)
	assert_eq(defender.count(), 0)
	assert_true(armies.has(defender))
	assert_gt(attacker.count(), 0)


func test_defender_victory_wipes_the_attacker_without_a_flip() -> void:
	var defender := Fixture.army(1, 1, 2, ["guards", "guards", "guards", "guards", "guards"])
	var attacker := Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(_model.province_owner(2), 1)
	assert_false(armies.has(attacker))
	assert_gt(defender.count(), 0)


func test_matched_large_armies_stalemate() -> void:
	var defender := Fixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := Fixture.army(2, 0, 2, _repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_eq(_model.province_owner(2), 1)
	assert_gt(defender.count(), 0)
	assert_gt(attacker.count(), 0)


func test_defending_armies_share_one_side() -> void:
	var first := Fixture.army(1, 1, 2, ["peasant_levies", "peasant_levies"])
	var second := Fixture.army(2, 1, 2, ["peasant_levies", "peasant_levies"])
	var side: Array[ArmyState] = ArmyCombat.armies_of([first, second], 2, 1)
	assert_almost_eq(ArmyCombat.side_strength(side), 12.0, 0.001)
	assert_eq(ArmyCombat.side_regiments(side), 4)


func test_cavalry_wins_the_initiative_order() -> void:
	var foot := Fixture.army(1, 1, 3, ["peasant_levies"])
	foot.moved = true
	var horse := Fixture.army(2, 2, 3, ["squires"])
	horse.moved = true
	var armies: Array[ArmyState] = [foot, horse]
	var expected: Array[int] = [2, 1]
	assert_eq(ArmyCombat.ordered_attackers(armies, 3, MapModel.NO_ID), expected)


func test_equal_initiative_is_broken_by_a_seeded_battle_roll() -> void:
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"])
	var lower := Fixture.army(2, 2, 2, ["pikemen"])
	lower.moved = true
	var higher := Fixture.army(3, 0, 2, ["pikemen"])
	higher.moved = true
	var armies: Array[ArmyState] = [defender, lower, higher]

	# Same initiative: the wiki wants one deterministic roll per battle context,
	# not the lexical faction id (combat § Initiative, § Multi-Attacker Chain).
	var first: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 0})
	var again: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 0})
	var other: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 1})

	assert_eq(first, again, "identical state reproduces the same chain order")
	assert_eq(first, [2, 0], "the seeded roll, not faction id, decides the tie")
	assert_eq(other, [0, 2], "a different combat seed may flip the tied order")
	assert_eq(ArmyCombat.ordered_attackers(armies, 2, 1), first, "the default seed is 0")


func test_general_medals_add_to_initiative() -> void:
	var horse: Array[ArmyState] = [Fixture.army(1, 0, 3, ["squires"])]
	assert_almost_eq(ArmyCombat.initiative(horse), 50.0, 0.001)
	assert_almost_eq(ArmyCombat.initiative(horse, 2), 70.0, 0.001)


func test_medal_aura_redistributes_casualties() -> void:
	var defender := Fixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := Fixture.army(2, 0, 2, _repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 4:
		roster.award(0, "general_1")
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies, context)

	assert_eq(int(reports[0]["attacker_medals"]), 4)
	assert_gt(
		(reports[0]["defender_lost"] as Array).size(),
		(reports[0]["attacker_lost"] as Array).size()
	)


func test_mutual_annihilation_recovers_a_garrison_for_the_next_attacker() -> void:
	var defender := Fixture.army(1, 1, 2, ["guards"], true)
	var first := Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), "guards")
	assert_eq(_model.province_owner(2), 1)


func test_mutual_annihilation_without_further_attackers_leaves_the_province_empty() -> void:
	var defender := Fixture.army(1, 1, 2, ["guards"], true)
	var attacker := Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 0)
	assert_eq(_model.province_owner(2), 1)
	assert_eq(defender.count(), 0)


func test_ratio_bands_follow_the_documented_fractions() -> void:
	assert_almost_eq(float(ArmyCombat.band_for(2.0)["attacker"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(2.0)["defender"]), 1.0, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(1.2)["attacker"]), 0.3, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(0.8)["attacker"]), 0.5, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(0.5)["attacker"]), 1.0, 0.001)


func test_the_067_boundary_belongs_to_the_defender_victory_band() -> void:
	# wiki: combat § Auto-resolve ratio bands — `ratio <= 0.67` loses 1.0/0.15,
	# while the `0.67 < ratio < 1.0` row starts strictly above 0.67.
	assert_almost_eq(float(ArmyCombat.band_for(0.67)["attacker"]), 1.0, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(0.67)["defender"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(0.68)["attacker"]), 0.5, 0.001)


func test_great_powers_recover_era_four_infantry() -> void:
	assert_eq(ArmyCombat.era_for(0), ArmyCombat.GREAT_POWER_ERA)
	assert_eq(ArmyCombat.era_for(6), ArmyCombat.MINOR_ERA)
	assert_eq(ArmyCombat.era_for(9), ArmyCombat.MINOR_ERA)


func test_outcome_labels_cover_every_result() -> void:
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.ATTACKER_VICTORY), "attacker victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.DEFENDER_VICTORY), "defender victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.STALEMATE), "stalemate")
	assert_eq(
		ArmyCombat.outcome_label(ArmyCombat.Outcome.MUTUAL_ANNIHILATION),
		"mutual annihilation"
	)
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.CAPTURE), "province captured")


func test_peaceful_factions_do_not_fight() -> void:
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var at_peace := func(_a: int, _b: int) -> bool: return false

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(
		_model, armies, {"hostile": at_peace}
	)

	assert_eq(reports.size(), 0, "peace holds: no battle, no capture")
	assert_eq(_model.province_owner(2), 1)
	assert_eq(attacker.count(), 3)
	assert_eq(defender.count(), 1)
	var at_war := func(_a: int, _b: int) -> bool: return true
	var battles: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies, {"hostile": at_war})
	assert_eq(battles.size(), 1, "declared war fights")
	assert_eq(_model.province_owner(2), 0)


func _repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types

# --- in-place regiment upgrades (DR-20261110-17) -----------------------------
## A Great Power's men re-equip the turn after the unlocking tech lands, keeping
## the regiment instance, army and province (wiki: tech-tree-military § Infantry,
## Cavalry, Artillery — "Improves: <type> upgrade path").


func test_each_military_tech_names_the_type_its_regiment_replaces() -> void:
	var expected: Dictionary = {
		"organised_regiments": ["knights", "lancers"],
		"improved_iron_weapons": ["pikemen", "halberdiers"],
		"improved_infantry_tactics": ["peasant_levies", "calivermen"],
		"bayonet": ["halberdiers", "regulars"],
		"weapon_craftsmanship": ["arquebusiers", "musketeers"],
		"explosives": ["musketeers", "grenadiers"],
		"early_rifles": ["calivermen", "skirmishers"],
		"long_range_rifles": ["skirmishers", "sharpshooters"],
		"needle_guns": ["regulars", "rifle_infantry"],
		"elite_military_training": ["grenadiers", "guards"],
		"recruit_steppe_horsemen": ["squires", "cossacks"],
		"hussars": ["cossacks", "hussars"],
		"scouting": ["hussars", "scouts"],
		"improved_cavalry_weapons": ["harquebusiers", "cuirassiers"],
		"repeating_cavalry_carbine": ["cuirassiers", "carbine_cavalry"],
		"siege_engineering": ["culverin", "royal_artillery"],
		"light_artillery_tactics": ["horse_artillery", "light_artillery"],
		"heavy_artillery": ["royal_artillery", "heavy_artillery"],
		"field_artillery_tactics": ["light_artillery", "field_artillery"],
		"high_grade_steel": ["heavy_artillery", "siege_guns"],
	}
	for tech_id: Variant in expected.keys():
		var path: Dictionary = RegimentUpgrades.path_for(String(tech_id))
		var pair: Array = expected[tech_id]
		assert_eq(String(path.get("from", "")), String(pair[0]), String(tech_id))
		assert_eq(String(path.get("to", "")), String(pair[1]), String(tech_id))
		assert_eq(
			String(path.get("name", "")),
			"%s upgrade path" % RegimentCatalog.display_name(String(pair[0])),
			String(tech_id)
		)


func test_the_first_type_of_a_branch_and_its_dependants_open_no_path() -> void:
	assert_true(RegimentUpgrades.path_for("improved_cavalry_tactics").is_empty())
	assert_true(RegimentUpgrades.path_for("horse_artillery").is_empty())
	assert_true(RegimentUpgrades.path_for("crucible_process").is_empty())
	assert_true(RegimentUpgrades.path_for("modern_forts").is_empty())
	assert_true(RegimentUpgrades.path_for("").is_empty())


func test_bowmen_knights_and_lancers_sit_at_the_top_of_their_ladders() -> void:
	assert_eq(RegimentUpgrades.previous_type("bowmen"), "")
	assert_eq(RegimentUpgrades.previous_type("lancers"), "knights")
	assert_eq(RegimentUpgrades.previous_type("scouts"), "hussars")
	assert_eq(RegimentUpgrades.previous_type("not_a_regiment"), "")


func test_the_newest_buildable_type_in_the_category_wins() -> void:
	assert_eq(RegimentUpgrades.target_type("pikemen", {}), "pikemen")
	assert_eq(
		RegimentUpgrades.target_type("pikemen", {"improved_iron_weapons": true}),
		"halberdiers"
	)
	assert_eq(
		RegimentUpgrades.target_type(
			"pikemen", {"improved_iron_weapons": true, "bayonet": true}
		),
		"regulars",
		"a court never stops at the first rung"
	)
	assert_eq(
		RegimentUpgrades.target_type("squires", {"bayonet": true}),
		"squires",
		"another branch's research never re-equips this one"
	)


func test_apply_re_equips_great_power_regiments_in_place() -> void:
	var power: int = FactionCatalog.PLAYER_FACTION
	var other: int = FactionCatalog.great_power_ids()[1]
	var regions := MapRegionTable.new()
	var army: ArmyState = ArmyState.muster(1, power, 0, true, ["pikemen", "bowmen"], 1)
	var rival: ArmyState = ArmyState.muster(2, other, 0, true, ["squires"], 10)
	regions.set_region(0, [army, rival])

	var pikemen: String = army.regiments[0]
	var bowmen: String = army.regiments[1]
	var squires: String = rival.regiments[0]
	var report: Dictionary = RegimentUpgrades.apply(regions, {
		power: {"improved_iron_weapons": true},
		other: {"recruit_steppe_horsemen": true},
	})

	assert_eq(int(report["count"]), 2)
	assert_eq(int((report["by_faction"] as Dictionary).get(power, 0)), 1)
	assert_eq(army.type_of(pikemen), "halberdiers")
	assert_eq(army.type_of(bowmen), "bowmen", "bowmen have no upgrade path")
	assert_eq(rival.type_of(squires), "cossacks", "rivals re-equip off their own techs")
	assert_eq(army.regiments, [pikemen, bowmen], "instance ids never change")


func test_apply_skips_minors_tribes_and_courts_with_nothing_new() -> void:
	var minor: int = FactionCatalog.minor_ids()[0]
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var power: int = FactionCatalog.PLAYER_FACTION
	var regions := MapRegionTable.new()
	var minor_army: ArmyState = ArmyState.muster(1, minor, 0, true, ["pikemen"], 1)
	var tribe_army: ArmyState = ArmyState.muster(2, tribe, 0, true, ["pikemen"], 10)
	var power_army: ArmyState = ArmyState.muster(3, power, 0, true, ["pikemen"], 20)
	regions.set_region(0, [minor_army, tribe_army, power_army])

	var report: Dictionary = RegimentUpgrades.apply(regions, {
		power: {"bayonet": true},
		minor: {"bayonet": true},
		tribe: {"bayonet": true},
	})

	assert_eq(int(report["count"]), 1)
	assert_eq(power_army.type_of(power_army.regiments[0]), "regulars")
	assert_eq(
		minor_army.type_of(minor_army.regiments[0]), "pikemen",
		"Minors follow the parity pass"
	)
	assert_eq(tribe_army.type_of(tribe_army.regiments[0]), "pikemen")
	assert_eq(int(RegimentUpgrades.apply(null, {})["count"]), 0)
