extends GdToolsTest
## Difficulty layer: the setup choice, the rival opening stores and the rival
## strength it scales in the field and at sea (wiki: ruleset-config § Layers;
## combat § Modifiers; ships-and-naval § Naval Combat Resolution;
## ai-architecture. DR-20261110-12, DR-20261111-24).

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
	var context: Dictionary = MapPlayLandTurn.battle_context(play)
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


func test_the_naval_layer_scales_every_rival_and_never_the_crown() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "hard"
	var factors: Dictionary = MapPlayNavalTurn.strength_multipliers(play)
	assert_false(factors.has(2), "the crown's hulls keep the published maths")
	assert_almost_eq(float(factors[1]), 1.15, 0.001)
	assert_almost_eq(float(factors[0]), float(factors[4]), 0.001,
		"every rival sails under one factor")


func test_a_dead_even_squadron_action_turns_on_the_level() -> void:
	assert_eq(_engagement({}), NavalCombat.Outcome.STALEMATE,
		"equal hulls draw on the published maths")
	assert_eq(_engagement({1: 0.85}), NavalCombat.Outcome.SIDE2_VICTORY,
		"the eased rival is repelled")
	assert_eq(_engagement({1: 1.3}), NavalCombat.Outcome.SIDE1_VICTORY,
		"the risen rival holds the water")


func test_the_resolved_despatch_carries_the_scaled_strength() -> void:
	var raw_rival: float = NavalCombat.side_strength([_rival_squadron(1)])
	assert_almost_eq(_engagement_record({1: 1.3})["attacker_strength"],
		raw_rival * 1.3, 0.001)
	assert_almost_eq(_engagement_record({1: 1.3})["defender_strength"],
		NavalCombat.side_strength([_crown_squadron()]), 0.001,
		"the human side is never scaled")


func test_the_dossier_odds_read_the_same_factor() -> void:
	var fleets: Array = [_crown_squadron(), _rival_squadron(4)]
	var published: Dictionary = NavalStrength.zone(fleets, fleets[0])
	var hard: Dictionary = NavalStrength.zone(
		fleets, fleets[0], Callable(), {4: 1.3})
	assert_almost_eq(float(hard["foe"]), float(published["foe"]) * 1.3, 0.001)
	assert_lt(float(hard["share"]), float(published["share"]),
		"a stronger rival takes more of the zone")


func test_two_rivals_share_one_factor_so_their_ratio_stays_published() -> void:
	var fleets: Array = [_rival_squadron(1), _rival_squadron(4)]
	var published: Dictionary = NavalStrength.zone(fleets, fleets[0])
	var scaled: Dictionary = NavalStrength.zone(
		fleets, fleets[0], Callable(), {1: 1.3, 4: 1.3})
	assert_almost_eq(float(scaled["share"]), float(published["share"]), 0.0001,
		"the factor cancels between two rivals")


## One squadron of the human crown and one rival frigate pair, both afloat in
## zone 0; the rival carries the lower owner id, so it takes the initiative.
func _crown_squadron() -> FleetState:
	return FleetState.at_sea(
		10, 2, 0, ["h1", "h2"], {"h1": "frigate", "h2": "frigate"}
	)


func _rival_squadron(owner: int) -> FleetState:
	return FleetState.at_sea(
		10 + owner, owner, 0, ["r1", "r2"], {"r1": "frigate", "r2": "frigate"}
	)


func _engagement(factors: Dictionary) -> int:
	return int(_engagement_record(factors).get("outcome", NavalCombat.Outcome.NONE))


func _engagement_record(factors: Dictionary) -> Dictionary:
	var context: Dictionary = {}
	if not factors.is_empty():
		context["difficulty"] = factors
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[_crown_squadron(), _rival_squadron(1)], Callable(), context
	)
	assert_eq(battles.size(), 1, "one engagement in zone 0")
	return battles[0] if not battles.is_empty() else {}


# --- the crown's own victory bar ---------------------------------------------


## The published bar is 31, and the level's published percentage moves it by
## whole provinces: 85 / 100 / 115 / 130 % of 31 (wiki: victory § Military
## victory; ruleset-config § Difficulty; DR-20261111-28).
func test_the_crowns_bar_is_the_published_one_scaled_by_the_level() -> void:
	assert_eq(VictoryRules.crown_threshold("normal"), VictoryRules.MILITARY_THRESHOLD)
	assert_eq(VictoryRules.crown_threshold(""), 31, "a legacy campaign reads as published")
	assert_eq(VictoryRules.crown_threshold("introductory"), 26)
	assert_eq(VictoryRules.crown_threshold("hard"), 36)
	assert_eq(VictoryRules.crown_threshold("impossible"), 40)


## Every rival keeps the published bar at every level, so the layer never
## changes a rival-versus-rival ratio; the observer (no human) is published too.
func test_only_the_human_crowns_bar_moves() -> void:
	for level: String in Difficulty.IDS:
		assert_eq(VictoryRules.threshold_for(1, 2, level), VictoryRules.MILITARY_THRESHOLD)
		assert_eq(
			VictoryRules.threshold_for(2, 2, level),
			VictoryRules.crown_threshold(level),
			"%s moves the crown's own bar" % level
		)
		assert_eq(
			VictoryRules.threshold_for(2, MapModel.NO_ID, level),
			VictoryRules.MILITARY_THRESHOLD,
			"the full-AI observer stays on the published rows"
		)


## 31 provinces win the age at normal and fall short at hard, where the crown
## needs 36; the same 31 still wins for a rival on that level.
func test_the_level_decides_whether_the_crown_has_won_the_age() -> void:
	assert_not_null(VictoryRules.evaluate(_world({2: 31}), 5, 2, "normal"))
	assert_null(VictoryRules.evaluate(_world({2: 31}), 5, 2, "hard"))
	var won: VictoryState = VictoryRules.evaluate(_world({2: 36}), 5, 2, "hard")
	assert_not_null(won)
	assert_eq(won.winner_player_id, 2)
	assert_not_null(
		VictoryRules.evaluate(_world({1: 31}), 5, 2, "hard"),
		"a rival still wins at the published bar"
	)


## An eased campaign asks less of the crown: 26 provinces win at introductory
## where 25 do not.
func test_an_eased_campaign_asks_less_of_the_crown() -> void:
	assert_not_null(VictoryRules.evaluate(_world({2: 26}), 5, 2, "introductory"))
	assert_null(VictoryRules.evaluate(_world({2: 25}), 5, 2, "introductory"))


## The turn reads the session's own level and human slot; an observer passes
## NO_ID and gets the published maths for every crown.
func test_the_turn_reads_the_sessions_level_and_human_slot() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "hard"
	play.world = _world({2: 31})
	assert_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty)
	)
	play.world = _world({2: 36})
	assert_not_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty)
	)
	play.observer_mode = true
	play.world = _world({2: 31})
	assert_not_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty),
		"the observer keeps the published bar for every crown"
	)


## One Old World region holding `counts` provinces per owner.
func _world(counts: Dictionary) -> WorldMap:
	var world := WorldMap.new()
	var model := MapModel.new()
	model.setup(1, 1)
	model.region_id = FactionCatalog.OLD_WORLD
	model.faction_ids = FactionCatalog.ids_in_region(FactionCatalog.OLD_WORLD)
	var next_id: int = 0
	for faction_id: int in counts.keys():
		for _index in int(counts[faction_id]):
			var tiles: Array[Vector2i] = []
			model.provinces.append(
				ProvinceState.create(
					next_id, "Province %d" % next_id, tiles, Vector2.ZERO, 1, faction_id
				)
			)
			next_id += 1
	world.add_region(model)
	return world
