extends GdToolsTest
## Army containers: composition, split, combine and the Home Army invariant
## (wiki: military-armies).

const Fixture = preload("res://tests/army_fixture.gd")


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
