extends GdToolsTest
## Combat modifiers: feeding, medals, deployment, terrain and leaders
## (wiki: combat § Modifiers and configurable values, military-generals § Medals).

const Fixture = preload("res://tests/army_fixture.gd")


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
