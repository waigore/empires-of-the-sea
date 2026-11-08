extends GdToolsTest
## Army marches: interior lines, adjacent hostile land, Home Army immobility
## (wiki: military-armies § Movement and attacks).

const Fixture = preload("res://tests/army_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = Fixture.build()


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
