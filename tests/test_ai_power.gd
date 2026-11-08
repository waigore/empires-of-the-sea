extends GdToolsTest

const AiFixture = preload("res://tests/ai_fixture.gd")
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
