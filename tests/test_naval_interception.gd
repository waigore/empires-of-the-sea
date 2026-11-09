extends GdToolsTest
## Patrol/blockade interception (wiki: ships-and-naval § Naval Interception
## Probability; DR-20261109-16).

const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = NavalFixture.build()


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


func test_interception_chance_follows_the_wiki_formula() -> void:
	var sloop := _squadron(1, 0, 0, "sloop", 1)
	var fluyte := _squadron(2, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance([sloop], [fluyte], FleetState.Mission.PATROL),
		0.5 * 4.0 / 7.0,
		0.0001
	)
	assert_almost_eq(
		NavalInterception.chance([sloop], [fluyte], FleetState.Mission.BLOCKADE),
		0.9 * 4.0 / 7.0,
		0.0001
	)
	assert_eq(
		NavalInterception.chance([], [fluyte], FleetState.Mission.PATROL), 0.0
	)
	assert_eq(
		NavalInterception.chance([sloop], [], FleetState.Mission.PATROL), 0.0
	)


func test_interception_chance_is_clamped() -> void:
	var sloop := _squadron(1, 0, 0, "sloop", 1)
	var many_fluytes := _squadron(2, 1, 0, "fluyte", 30)
	assert_almost_eq(
		NavalInterception.chance([sloop], [many_fluytes], FleetState.Mission.PATROL),
		NavalInterception.MIN_CHANCE,
		0.0001
	)
	var raiders := _squadron(3, 0, 0, "raider", 20)
	var one_fluyte := _squadron(4, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance([raiders], [one_fluyte], FleetState.Mission.BLOCKADE),
		NavalInterception.MAX_CHANCE,
		0.0001
	)


func test_the_roll_is_deterministic_and_in_range() -> void:
	var first: float = NavalInterception.roll(1500, 4, 2, 0, 1)
	assert_almost_eq(first, NavalInterception.roll(1500, 4, 2, 0, 1), 0.0001)
	assert_gte(first, 0.0)
	assert_lt(first, 1.0)
	assert_ne(first, NavalInterception.roll(1501, 4, 2, 0, 1))


func test_attempts_follow_the_roll() -> void:
	var sloop := _squadron(1, 0, 0, "sloop", 1)
	var fluyte := _squadron(2, 1, 0, "fluyte", 1)
	var hit: Dictionary = NavalInterception.attempt(
		0, [sloop], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.0
	)
	var miss: Dictionary = NavalInterception.attempt(
		0, [sloop], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.99
	)
	assert_true(bool(hit["ok"]))
	assert_false(bool(miss["ok"]))
	assert_true(bool(NavalInterception.attempt(
		0, [], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.0
	)["ok"]) == false)


func test_a_successful_patrol_interception_makes_the_patroller_attacker() -> void:
	var patrol := _squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var mover := _squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, mover], Callable(), {"interception_roll": 0.0}
	)
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 0)
	assert_true(bool(battles[0]["intercepted"]))
	assert_almost_eq(
		float(battles[0]["interception_chance"]), 0.5 * 4.0 / 7.0, 0.0001
	)


func test_a_failed_interception_leaves_the_mover_as_attacker() -> void:
	var patrol := _squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var mover := _squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, mover], Callable(), {"interception_roll": 0.99}
	)
	assert_eq(int(battles[0]["attacker"]), 1)
	assert_false(bool(battles[0]["intercepted"]))


func test_a_blockade_intercepts_on_the_higher_factor() -> void:
	var blockader := _squadron(1, 0, 1, "sloop", 1)
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var mover := _squadron(2, 1, 1, "fluyte", 1)
	mover.moved = true
	var context: Dictionary = {"model": _model, "interception_roll": 0.45}
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[blockader, mover], Callable(), context
	)
	assert_true(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 0)
	# The same roll misses a patrol's lower chance in the same waters.
	var patrol := _squadron(3, 0, 1, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var other := _squadron(4, 1, 1, "fluyte", 1)
	other.moved = true
	var misses: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, other], Callable(), context
	)
	assert_false(bool(misses[0]["intercepted"]))
	assert_eq(int(misses[0]["attacker"]), 1)


func test_a_defending_squadron_does_not_intercept() -> void:
	var defender := _squadron(1, 0, 0, "sloop", 1)
	defender.mission = FleetState.Mission.DEFEND
	var mover := _squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[defender, mover], Callable(), {"interception_roll": 0.0}
	)
	assert_false(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 1)


## Crown-tech query: `owner` holds Privateering Companies, nobody else does.
func _charter(owner: int) -> Callable:
	return func(crown: int, tech_id: String) -> bool:
		return crown == owner and tech_id == NavalInterception.PRIVATEERING_TECH


func test_privateers_multiply_the_intercept_score() -> void:
	var sloop := _squadron(1, 0, 0, "sloop", 1)
	var fluyte := _squadron(2, 1, 0, "fluyte", 1)
	var plain: float = NavalInterception.chance(
		[sloop], [fluyte], FleetState.Mission.PATROL
	)
	var chartered: float = NavalInterception.chance(
		[sloop], [fluyte], FleetState.Mission.PATROL, _charter(0)
	)
	assert_almost_eq(plain, 0.5 * 4.0 / 7.0, 0.0001)
	# Σintercept 4 × 1.25 = 5 against the same flee score of 3.
	assert_almost_eq(chartered, 0.5 * 5.0 / 8.0, 0.0001)
	assert_gt(chartered, plain)


func test_only_the_interceptors_charter_counts() -> void:
	var sloop := _squadron(1, 0, 0, "sloop", 1)
	var fluyte := _squadron(2, 1, 0, "fluyte", 1)
	# The target's own privateers never help the interceptor.
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, _charter(1)
		),
		0.5 * 4.0 / 7.0,
		0.0001
	)
	# A crown without the tech gets the plain table.
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, _charter(4)
		),
		0.5 * 4.0 / 7.0,
		0.0001
	)


func test_a_privateer_patrol_wins_a_roll_a_plain_one_misses() -> void:
	# 0.30 lies between the plain 4/14 and the chartered 5/16.
	var plain_patrol := _squadron(1, 0, 0, "sloop", 1)
	plain_patrol.mission = FleetState.Mission.PATROL
	var plain_mover := _squadron(2, 1, 0, "fluyte", 1)
	plain_mover.moved = true
	var plain: Array[Dictionary] = NavalCombat.resolve_turn(
		[plain_patrol, plain_mover], Callable(), {"interception_roll": 0.30}
	)
	assert_false(bool(plain[0]["intercepted"]))
	var chartered_patrol := _squadron(3, 0, 0, "sloop", 1)
	chartered_patrol.mission = FleetState.Mission.PATROL
	var chartered_mover := _squadron(4, 1, 0, "fluyte", 1)
	chartered_mover.moved = true
	var chartered: Array[Dictionary] = NavalCombat.resolve_turn(
		[chartered_patrol, chartered_mover],
		Callable(),
		{"interception_roll": 0.30, "has_tech": _charter(0)}
	)
	assert_true(bool(chartered[0]["intercepted"]))
	assert_eq(int(chartered[0]["attacker"]), 0)


func test_the_dossier_reads_the_privateer_charter() -> void:
	var play := PlaySession.new()
	play.player_faction = 0
	play.model = _model
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	var fleet := _squadron(1, 0, 0, "sloop", 1)
	fleet.mission = FleetState.Mission.PATROL
	assert_false(MapPlayFleetMissions.note(play, fleet).contains("Privateers"))
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	var note: String = MapPlayFleetMissions.note(play, fleet)
	assert_true(note.contains("On patrol"))
	assert_true(note.contains("Privateers"))
	assert_true(note.contains("+25%"))
	# A squadron in port can take no station, so the charter is not dangled.
	var docked := FleetState.in_port(2, 0, 0, ["home_1"], {"home_1": "fluyte"})
	assert_false(MapPlayFleetMissions.note(play, docked).contains("Privateers"))
	economy.free()
