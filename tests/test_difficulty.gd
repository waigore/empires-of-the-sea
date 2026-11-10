extends GdToolsTest
## Difficulty layer: the setup choice, the rival opening stores and the rival
## land strength it scales (wiki: ruleset-config § Layers; combat § Modifiers;
## ai-architecture. DR-20261110-12).

const Fixture = preload("res://tests/army_fixture.gd")


func test_ids_are_ordered_easiest_first_and_unknown_ids_fall_back() -> void:
	assert_eq(Difficulty.IDS.size(), 4)
	assert_eq(String(Difficulty.IDS[0]), "introductory")
	assert_eq(String(Difficulty.IDS[3]), "impossible")
	assert_eq(Difficulty.normalize(""), Difficulty.DEFAULT)
	assert_eq(Difficulty.normalize("Napoleon"), Difficulty.DEFAULT)
	assert_eq(Difficulty.normalize("  Hard "), "hard")
	assert_eq(Difficulty.index_of("hard"), 2)
	assert_eq(Difficulty.label("impossible"), "Impossible")


func test_percentages_rise_with_difficulty_and_normal_is_the_published_row() -> void:
	var previous_start: int = 0
	var previous_combat: int = 0
	for id: String in Difficulty.IDS:
		assert_gte(Difficulty.ai_start_percent(id), previous_start)
		assert_gte(Difficulty.ai_combat_percent(id), previous_combat)
		previous_start = Difficulty.ai_start_percent(id)
		previous_combat = Difficulty.ai_combat_percent(id)
	assert_eq(Difficulty.ai_start_percent(Difficulty.DEFAULT), 100)
	assert_eq(Difficulty.ai_combat_percent(Difficulty.DEFAULT), 100)
	assert_eq(Difficulty.ai_start_percent("introductory"), 60)
	assert_eq(Difficulty.ai_start_percent("impossible"), 180)
	assert_eq(Difficulty.ai_combat_percent("impossible"), 130)


func test_every_level_states_its_effect_in_plain_words() -> void:
	for id: String in Difficulty.IDS:
		assert_gt(Difficulty.hint(id).length(), 20, "%s needs a hint" % id)
	assert_true(Difficulty.hint("hard").contains("140%"))
	assert_true(Difficulty.hint("normal").contains("alike"))
	assert_ne(Difficulty.hint("hard"), Difficulty.hint("impossible"))


func test_start_quantities_scale_by_percent_and_floor_at_zero() -> void:
	assert_eq(Difficulty.scaled(2500, 140), 3500)
	assert_eq(Difficulty.scaled(6, 85), 5)
	assert_eq(Difficulty.scaled(0, 180), 0)
	assert_eq(Difficulty.scaled(-4, 180), 0)


func test_a_rival_ledger_is_founded_at_the_chosen_level_once() -> void:
	var play := PlaySession.new()
	play.difficulty = "hard"
	var ai: AiState = play.ensure_ai()
	assert_eq(ai.difficulty, "hard")
	var rival: PlayerEconomy = ai.economy_for(3)
	assert_eq(rival.treasury, Difficulty.scaled(PlayerEconomy.START_TREASURY, 140))
	assert_eq(rival.quantity("grain"), Difficulty.scaled(
		PlayerEconomy.START_PEASANTS * PlayerEconomy.START_GRAIN_TURNS, 140
	))
	var treasury: int = rival.treasury
	# Reading the same ledger again must not compound the scale.
	assert_eq(ai.economy_for(3).treasury, treasury)
	assert_eq(ai.economy_for(3), rival)


func test_normal_leaves_every_court_on_the_published_start_row() -> void:
	var play := PlaySession.new()
	var rival: PlayerEconomy = play.ensure_ai().economy_for(2)
	assert_eq(play.difficulty, Difficulty.DEFAULT)
	assert_eq(rival.treasury, PlayerEconomy.START_TREASURY)
	assert_eq(rival.quantity("grain"), PlayerEconomy.START_PEASANTS * PlayerEconomy.START_GRAIN_TURNS)
	assert_eq(rival.quantity("wool"), 4)


func test_the_human_crown_is_never_scaled() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "impossible"
	var multipliers: Dictionary = Difficulty.combat_multipliers(
		play.human_faction_id(), play.difficulty, FactionCatalog.great_power_ids()
	)
	assert_false(multipliers.has(2), "the human side keeps the published maths")
	assert_almost_eq(float(multipliers[1]), 1.3, 0.001)


func test_battle_context_carries_the_rival_multiplier_and_skips_the_human() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "introductory"
	var context: Dictionary = MapPlayArmies.battle_context(play)
	var difficulty: Dictionary = context["difficulty"] as Dictionary
	assert_false(difficulty.has(2))
	assert_almost_eq(float(difficulty[0]), 0.85, 0.001)


func test_an_introductory_rival_fails_an_assault_that_wins_at_normal() -> void:
	var normal: Dictionary = _assault({})
	var eased: Dictionary = _assault({1: 0.85})
	assert_true(bool(normal["captured"]), "six regiments carry four at the published maths")
	assert_false(bool(eased["captured"]), "the eased rival is turned back")
	assert_gt(
		int((eased["attacker_lost"] as Array).size()),
		int((normal["attacker_lost"] as Array).size())
	)
	assert_gt(
		int((normal["defender_lost"] as Array).size()),
		int((eased["defender_lost"] as Array).size())
	)


func test_a_hard_rival_holds_its_ground_where_normal_is_driven_off() -> void:
	var normal: Dictionary = _assault({})
	var hard: Dictionary = _assault({1: 1.3})
	assert_true(bool(normal["captured"]))
	assert_true(bool(hard["captured"]), "a stronger attacker still carries the province")
	assert_gte(
		int((hard["defender_lost"] as Array).size()),
		int((normal["defender_lost"] as Array).size())
	)


## Six rival regiments assault four of the human crown's in province 0.
func _assault(difficulty: Dictionary) -> Dictionary:
	var model: MapModel = Fixture.build()
	var defending: Array[ArmyState] = [
		Fixture.army(1, 0, 0, ["pikemen", "pikemen", "pikemen", "pikemen"], true)
	]
	var attacking: Array[ArmyState] = [
		Fixture.army(2, 1, 0, ["pikemen", "pikemen", "pikemen", "pikemen", "pikemen", "pikemen"])
	]
	attacking[0].moved = true
	var armies: Array[ArmyState] = []
	armies.append_array(defending)
	armies.append_array(attacking)
	var context: Dictionary = {"quick_battle": false}
	if not difficulty.is_empty():
		context["difficulty"] = difficulty
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	assert_eq(reports.size(), 1, "one exchange in province 0")
	return reports[0] if not reports.is_empty() else {}
