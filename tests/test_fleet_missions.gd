extends GdToolsTest
## Station orders for sea-going squadrons (wiki: ships-and-naval § Missions and
## Movement; DR-20261109-16).

const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = NavalFixture.build()


func _war(a: int, b: int) -> bool:
	return a != b


func _peace(_a: int, _b: int) -> bool:
	return false


func test_a_patrol_station_spends_the_move_and_persists() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = FleetMissions.assign(_model, fleet, FleetState.Mission.PATROL)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.mission, FleetState.Mission.PATROL)
	assert_true(fleet.moved, "taking a station spends the turn's move")
	assert_true(FleetMissions.status_note(_model, fleet).contains("patrol"))
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved, "the next turn restores the move")
	assert_eq(fleet.mission, FleetState.Mission.PATROL, "the station persists")


func test_the_home_fleet_and_docked_squadrons_cannot_take_a_station() -> void:
	var home := FleetState.in_port(2, 0, 0)
	assert_true(FleetMissions.can_assign(
		_model, home, FleetState.Mission.PATROL
	)["reason"].contains("home fleet"))
	var docked := FleetState.in_port(3, 0, 1)
	assert_true(FleetMissions.can_assign(
		_model, docked, FleetState.Mission.PATROL
	)["reason"].contains("at sea"))
	var moved := FleetState.at_sea(4, 0, 0)
	moved.moved = true
	assert_true(FleetMissions.can_assign(
		_model, moved, FleetState.Mission.PATROL
	)["reason"].contains("already moved"))
	var same := FleetState.at_sea(5, 0, 0)
	same.mission = FleetState.Mission.PATROL
	assert_true(FleetMissions.can_assign(
		_model, same, FleetState.Mission.PATROL
	)["reason"].contains("already holds"))
	var empty := FleetState.at_sea(6, 0, 0)
	empty.hulls = []
	empty.hull_types = {}
	assert_true(FleetMissions.can_assign(
		_model, empty, FleetState.Mission.PATROL
	)["reason"].contains("no hulls"))
	assert_false(bool(FleetMissions.can_assign(null, home, FleetState.Mission.PATROL)["ok"]))
	assert_false(bool(FleetMissions.can_assign(
		_model, home, FleetState.Mission.MOVE
	)["ok"]))


func test_a_blockade_needs_a_hostile_coast_in_the_zone() -> void:
	var fleet := FleetState.at_sea(1, 0, 1)
	assert_eq(FleetMissions.blockade_targets(_model, fleet, _war), [1])
	var result: Dictionary = FleetMissions.assign(
		_model, fleet, FleetState.Mission.BLOCKADE, 1, _war
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.blockade_province, 1)
	assert_true(FleetMissions.is_blockading(_model, fleet, _war))
	assert_false(FleetMissions.is_blockading(_model, fleet, _peace))
	assert_true(FleetMissions.status_note(_model, fleet).contains("Blockading Coro"))
	var far := FleetState.at_sea(2, 0, 0)
	assert_true(FleetMissions.can_assign(
		_model, far, FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("border"))
	var own := FleetState.at_sea(3, 0, 0)
	assert_true(FleetMissions.can_assign(
		_model, own, FleetState.Mission.BLOCKADE, 0, _war
	)["reason"].contains("enemy coast"))
	var missing := FleetState.at_sea(4, 0, 1)
	assert_true(FleetMissions.can_assign(
		_model, missing, FleetState.Mission.BLOCKADE, 99, _war
	)["reason"].contains("enemy province"))
	assert_true(FleetMissions.can_assign(
		_model, FleetState.at_sea(5, 0, 1), FleetState.Mission.BLOCKADE, 1, _peace
	)["reason"].contains("declared war"))
	var same := FleetState.at_sea(6, 0, 1)
	same.mission = FleetState.Mission.BLOCKADE
	same.blockade_province = 1
	assert_true(FleetMissions.can_assign(
		_model, same, FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("already blockades"))
	_model.province_data(1).owner = MapModel.NO_ID
	assert_true(FleetMissions.can_assign(
		_model, FleetState.at_sea(7, 0, 1), FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("no crown"))


func test_blockade_targets_are_the_hostile_coasts_beside_the_zone() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(FleetMissions.blockade_targets(_model, fleet, _war), [])
	assert_eq(FleetMissions.blockade_targets(null, fleet, _war), [])
	var docked := FleetState.in_port(2, 0, 1)
	assert_eq(FleetMissions.blockade_targets(_model, docked, _war), [])


func test_a_normal_move_clears_the_station() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	FleetMissions.assign(_model, fleet, FleetState.Mission.PATROL)
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.AT_SEA, 1
	)
	assert_true(bool(result["ok"]))
	assert_eq(fleet.mission, FleetState.Mission.NONE)
	assert_eq(fleet.blockade_province, MapModel.NO_ID)


func test_the_strongest_station_identifies_a_group() -> void:
	var patrol := FleetState.at_sea(1, 0, 0)
	patrol.mission = FleetState.Mission.PATROL
	var blockade := FleetState.at_sea(2, 0, 1)
	blockade.mission = FleetState.Mission.BLOCKADE
	blockade.blockade_province = 1
	assert_eq(
		FleetMissions.station_mission(_model, [patrol], _war),
		FleetState.Mission.PATROL
	)
	assert_eq(
		FleetMissions.station_mission(_model, [patrol, blockade], _war),
		FleetState.Mission.BLOCKADE
	)
	assert_eq(
		FleetMissions.station_mission(_model, [blockade], _peace),
		FleetState.Mission.NONE
	)


## The station line follows the same gate the interception does: a blockade
## whose coast is ours, or at peace, attempts nothing, so the dossier must not
## claim it does (REQ-P2-03).
func test_a_blockade_note_follows_the_station_gate() -> void:
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	assert_true(FleetMissions.status_note(_model, fleet, _war).contains("Blockading Coro"))
	# The crown takes the coast it was blockading.
	_model.province_data(1).owner = 0
	assert_false(FleetMissions.is_blockading(_model, fleet, _war))
	assert_false(FleetMissions.status_note(_model, fleet, _war).contains("Blockading"))
	assert_true(FleetMissions.status_note(_model, fleet, _war).contains("lapsed"))
	# Peace ends a blockade just as surely as capture.
	_model.province_data(1).owner = 1
	assert_true(FleetMissions.status_note(_model, fleet, _peace).contains("lapsed"))
	assert_true(FleetMissions.status_note(_model, fleet, _war).contains("Blockading"))


func test_station_ids_round_trip_and_labels_read_plainly() -> void:
	assert_eq(FleetMissions.id_of(FleetState.Mission.PATROL), "patrol")
	assert_eq(FleetMissions.from_id("patrol"), FleetState.Mission.PATROL)
	assert_eq(FleetMissions.id_of(FleetState.Mission.BLOCKADE), "blockade")
	assert_eq(FleetMissions.from_id("blockade"), FleetState.Mission.BLOCKADE)
	assert_eq(FleetMissions.id_of(FleetState.Mission.DEFEND), "defend")
	assert_eq(FleetMissions.from_id("defend"), FleetState.Mission.DEFEND)
	assert_eq(FleetMissions.label(FleetState.Mission.BLOCKADE), "Blockade")
	assert_eq(FleetMissions.from_id("nonsense"), FleetState.Mission.NONE)
	assert_eq(FleetMissions.label(FleetState.Mission.NONE), "No station")
	assert_true(FleetMissions.is_stationary(FleetState.Mission.PATROL))
	assert_false(FleetMissions.is_stationary(FleetState.Mission.MOVE))


func test_a_defend_station_holds_and_names_its_orders() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = FleetMissions.assign(
		_model, fleet, FleetState.Mission.DEFEND
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.mission, FleetState.Mission.DEFEND)
	assert_true(fleet.moved)
	assert_true(FleetMissions.status_note(_model, fleet).contains("Holding station"))
	assert_true(String(result["message"]).contains("holds station"))


func test_mission_and_blockade_survive_a_save_round_trip() -> void:
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	var saved: FleetState = FleetState.from_dict(fleet.to_dict())
	assert_eq(saved.mission, FleetState.Mission.BLOCKADE)
	assert_eq(saved.blockade_province, 1)
	var legacy: FleetState = FleetState.from_dict({"id": 9, "owner": 0})
	assert_eq(legacy.mission, FleetState.Mission.NONE)
	assert_eq(legacy.blockade_province, MapModel.NO_ID)


## Marking a landing site spends the move, so the squadron never sailed into
## the zone and cannot seize the initiative from the fleet that did (wiki:
## ships-and-naval § Missions and Movement — Beachhead is stationary).
func test_a_beachhead_squadron_is_stationary() -> void:
	var marker := FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	marker.mission = FleetState.Mission.BEACHHEAD
	marker.beachhead_province = 1
	marker.beachhead_turn = 1
	marker.moved = true
	var mover := FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "carrack"})
	mover.moved = true

	assert_true(FleetMissions.is_stationary(FleetState.Mission.BEACHHEAD))
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[marker, mover], Callable(), {"interception_roll": 0.99}
	)

	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 1, "the squadron that sailed in attacks")
