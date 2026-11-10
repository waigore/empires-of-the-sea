extends GdToolsTest
## Siege lane contracts (wiki: siege-mechanics § Damage Reduction (Tactical
## Combat), quick-battle § Emplaced fort artillery): the wall shelters the
## garrison, only artillery reaches behind it, melee cannot touch a wall, and a
## sortie trades shelter for fire.

const Fixture = preload("res://tests/army_fixture.gd")
const FORT: int = 2


func test_the_garrison_splits_into_wall_and_behind() -> void:
	var side: Array[ArmyState] = _side(["pikemen", "musketeers", "squires", "culverin"], 1)

	assert_eq(SiegeLanes.wall_ids(side).size(), 2, "infantry man the wall")
	assert_eq(SiegeLanes.behind_ids(side).size(), 2, "horse and guns wait behind")
	assert_true(SiegeLanes.is_wall_type("guards"))
	assert_false(SiegeLanes.is_wall_type("squires"))
	assert_false(SiegeLanes.is_wall_type("culverin"))
	assert_eq(SiegeLanes.describe(side), "2 on the wall · 2 behind")


func test_melee_only_besiegers_cannot_touch_a_wall() -> void:
	var attacker: Array[ArmyState] = _side(["pikemen", "knights"], 2)
	var defender: Array[ArmyState] = _side(["peasant_levies"], 1)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var wanted: int = 3

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defender, wanted, 10, FORT, false)

	assert_eq(int(split["turned"]), wanted, "the wall turns the pikes aside")
	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq(defender[0].count(), 1, "nobody on the wall is hurt")


func test_firearms_hit_the_wall_and_the_fort_blunts_the_blow() -> void:
	var open_field: int = _struck_losses(FORT - 2, 4)
	var stone: int = _struck_losses(FORT, 4)

	assert_eq(open_field, 4, "an open field takes the whole blow")
	assert_eq(stone, ceili(4.0 * FortRules.loss_scale(FORT)), "the wall spares a share")
	assert_true(stone < open_field)


func test_only_artillery_reaches_behind_the_wall() -> void:
	var muskets: Array[ArmyState] = _side(["musketeers", "musketeers"], 2)
	var guns: Array[ArmyState] = _side(["musketeers", "musketeers", "culverin"], 2)
	var defender: Array[ArmyState] = _side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var armies: Array[ArmyState] = _joined(guns, defender)

	assert_false(SiegeLanes.can_reach_behind(muskets), "small arms stay outside")
	var shot: Dictionary = SiegeLanes.strike(armies, guns, defender, 4, 10, FORT, false)

	assert_true((shot["behind"] as Array).size() > 0, "guns drop shot over the parapet")
	assert_true((shot["wall"] as Array).size() > 0)

	var walls_only: Array[ArmyState] = _side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var field_only: Array[ArmyState] = _joined(muskets, walls_only)
	var small: Dictionary = SiegeLanes.strike(field_only, muskets, walls_only, 4, 10, FORT, false)
	assert_eq((small["behind"] as Array).size(), 0, "only artillery can hit behind")


func test_a_sortie_sheds_the_walls_protection() -> void:
	var sheltered: int = _struck_losses(FORT, 6, false)
	var sortied: int = _struck_losses(FORT, 6, true)

	assert_eq(sheltered, ceili(6.0 * FortRules.loss_scale(FORT)))
	assert_eq(sortied, 6, "outside the wall the garrison takes the whole blow")
	assert_true(sortied > sheltered)


func test_return_fire_follows_the_garrisons_range() -> void:
	var pikes: Array[ArmyState] = _side(["pikemen", "pikemen"], 1)
	var muskets: Array[ArmyState] = _side(["musketeers", "musketeers"], 1)
	var mixed: Array[ArmyState] = _side(["pikemen", "pikemen", "musketeers", "musketeers"], 1)

	assert_almost_eq(SiegeLanes.return_fire_share(pikes), 0.0, 0.001, "pikes cannot shoot")
	assert_almost_eq(SiegeLanes.return_fire_share(muskets), 1.0, 0.001)
	assert_almost_eq(SiegeLanes.return_fire_share(mixed), 0.5, 0.001)


func test_an_empty_garrison_absorbs_nothing() -> void:
	var attacker: Array[ArmyState] = _side(["musketeers"], 2)
	var defender: Array[ArmyState] = []
	var split: Dictionary = SiegeLanes.strike(
		attacker, attacker, defender, 3, 10, FORT, false
	)

	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq((split["behind"] as Array).size(), 0)
	assert_eq(int(split["turned"]), 0)


func _struck_losses(fort: int, wanted: int, exposed: bool = false) -> int:
	var attacker: Array[ArmyState] = _side(["musketeers", "musketeers", "musketeers"], 2)
	var defender: Array[ArmyState] = _side(
		["peasant_levies", "peasant_levies", "peasant_levies", "peasant_levies",
		"peasant_levies", "peasant_levies"], 1
	)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defender, wanted, 10, fort, exposed
	)
	return (split["wall"] as Array).size() + (split["behind"] as Array).size()


func _side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(Fixture.army(10 + owner, owner, 2, types, true))
	return side


func _joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all
