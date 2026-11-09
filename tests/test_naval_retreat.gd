extends GdToolsTest
## Retreat from a lost naval engagement (wiki: ships-and-naval § Naval Retreat
## Formula; DR-20261109-16).

const NavalFixture = preload("res://tests/naval_fixture.gd")
const FACTIONS: Array[String] = ["España", "England", "France", "Portugal"]

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


func test_retreat_chance_follows_the_wiki_formula() -> void:
	var beaten := _squadron(1, 1, 0, "fluyte", 1)
	var victor := _squadron(2, 0, 0, "carrack", 1)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.NONE), 0.6, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.PATROL), 0.5, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.BLOCKADE), 0.4, 0.0001
	)
	var fast := _squadron(3, 1, 0, "sloop", 1)
	assert_almost_eq(
		NavalRetreat.chance([fast], [victor], FleetState.Mission.NONE), 0.7, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([victor], [fast], FleetState.Mission.NONE), 0.5, 0.0001
	)


func test_a_retreat_needs_an_adjacent_friendly_or_neutral_zone() -> void:
	var beaten := _squadron(1, 1, 0, "carrack", 1)
	var victor := _squadron(2, 0, 0, "carrack", 3)
	var hostile := _squadron(3, 2, 1, "carrack", 1)
	var fleets: Array = [victor, beaten, hostile]
	var owners: Array[int] = [1]
	assert_eq(
		NavalRetreat.safe_zones(_model, 0, owners, fleets),
		[] as Array[int],
		"the only neighbouring zone is hostile"
	)
	fleets.erase(hostile)
	assert_eq(
		NavalRetreat.safe_zones(_model, 0, owners, fleets),
		[1] as Array[int]
	)


func test_a_successful_retreat_moves_the_beaten_squadron() -> void:
	var strong := _squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _squadron(2, 1, 0, "carrack", 1)
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _model, "fleets": fleets, "retreat_roll": 0.0}
	)
	var retreat: Dictionary = battles[0]["retreat"]
	assert_true(bool(retreat["success"]))
	assert_eq(int(retreat["zone"]), 1)
	assert_eq(weak.sea_zone, 1)
	assert_eq(weak.ship_count(), 1, "the squadron slips away intact")
	assert_true(weak.moved)
	assert_eq((battles[0]["defender_lost"] as Array).size(), 0)


func test_a_failed_retreat_is_a_rout() -> void:
	var strong := _squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _squadron(2, 1, 0, "carrack", 1)
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _model, "fleets": fleets, "retreat_roll": 0.99}
	)
	var retreat: Dictionary = battles[0]["retreat"]
	assert_false(bool(retreat["success"]))
	assert_eq(weak.ship_count(), 0)
	assert_eq(int((battles[0]["defender_lost"] as Array).size()), 1)


func test_a_retreating_side_abandons_its_station() -> void:
	var strong := _squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _squadron(2, 1, 0, "carrack", 1)
	weak.mission = FleetState.Mission.DEFEND
	weak.beachhead_province = 1
	weak.beachhead_turn = 3
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _model, "fleets": fleets, "retreat_roll": 0.0}
	)
	assert_true(bool((battles[0]["retreat"] as Dictionary)["success"]))
	assert_eq(weak.mission, FleetState.Mission.NONE)
	assert_false(weak.has_beachhead())


func test_without_a_model_the_loser_is_still_routed() -> void:
	var strong := _squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _squadron(2, 1, 0, "carrack", 1)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	assert_eq((battles[0]["retreat"] as Dictionary).size(), 0)
	assert_eq(weak.ship_count(), 0)


func test_the_despatch_names_the_withdrawal() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": [],
		"retreat": {"success": true, "beaten": 1, "zone": 4},
	}
	assert_eq(
		BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"England withdraws from the Windward Passage — España holds the zone"
	)
