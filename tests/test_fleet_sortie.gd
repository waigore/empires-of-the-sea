extends GdToolsTest
## The home squadron puts to sea and gives up the home holds while away
## (wiki: ships-and-naval § Home Fleet; DR-20261109-17).

const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = NavalFixture.build()


func _home() -> FleetState:
	return FleetState.in_port(
		1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"}
	)


func test_the_home_squadron_may_only_sail_from_its_capital() -> void:
	var home: FleetState = _home()
	var at_sea: FleetState = FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	var outside: FleetState = FleetState.in_port(3, 0, 1, ["d"], {"d": "fluyte"})

	assert_true(NavalMovement.is_home_fleet(_model, home))
	assert_eq(FleetSortie.zones(_model, home), [0])
	assert_true(bool(FleetSortie.can_sortie(_model, home, 0)["ok"]))
	assert_false(bool(FleetSortie.can_sortie(_model, at_sea, 0)["ok"]))
	assert_false(bool(FleetSortie.can_sortie(_model, outside, 0)["ok"]))
	assert_eq(FleetSortie.zones(_model, at_sea), [] as Array[int])


func test_a_sortie_needs_a_move_a_hull_and_a_bordering_zone() -> void:
	var home: FleetState = _home()
	home.moved = true
	assert_true(String(FleetSortie.can_sortie(_model, home, 0)["reason"]).contains("already sailed"))

	var empty: FleetState = FleetState.empty_in_port(4, 0, 0)
	assert_true(String(FleetSortie.can_sortie(_model, empty, 0)["reason"]).contains("no hulls"))

	var fresh: FleetState = _home()
	assert_true(String(FleetSortie.can_sortie(_model, fresh, 1)["reason"]).contains("does not border"))
	assert_false(bool(FleetSortie.can_sortie(null, fresh, 0)["ok"]))


func test_the_sortie_spends_the_move_and_turns_home_into_a_normal_squadron() -> void:
	var home: FleetState = _home()
	var result: Dictionary = FleetSortie.apply(_model, home, 0)

	assert_true(bool(result["ok"]))
	assert_true(home.is_at_sea())
	assert_eq(home.sea_zone, 0)
	assert_eq(home.province, MapModel.NO_ID)
	assert_true(home.moved)
	assert_false(NavalMovement.is_home_fleet(_model, home))


func test_the_home_holds_leave_with_the_squadron_and_return_when_it_moors() -> void:
	var world := WorldMap.new()
	world.add_region(_model)
	var home: FleetState = _home()
	var fleets: Dictionary = {0: [home]}

	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)

	FleetSortie.apply(_model, home, 0)
	assert_eq(TradeCargo.capacity(world, fleets, 0), 0, "at sea the holds are away")

	NavalMovement.begin_turn([home])
	assert_true(bool(NavalMovement.apply_move(
		_model, home, FleetState.Location.IN_PORT, 0
	)["ok"]))
	assert_true(NavalMovement.is_home_fleet(_model, home))
	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)


func test_colonists_keep_their_seats_through_a_sortie() -> void:
	var home: FleetState = _home()
	home.add_civilian(11)
	home.add_civilian(12)

	FleetSortie.apply(_model, home, 0)

	assert_eq(home.embarked_civilians, [11, 12])
	assert_eq(home.civilian_count(), 2)


func test_a_squadron_never_breaks_a_hull_out_from_under_its_colonists() -> void:
	var home: FleetState = FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	home.add_civilian(11)
	assert_false(bool(NavalTransport.can_scrap(home, null)["ok"]))
	home.add_hull("b", "carrack")
	assert_true(bool(NavalTransport.can_scrap(home, null)["ok"]))


func test_troops_cannot_board_a_squadron_carrying_colonists() -> void:
	var home: FleetState = _home()
	home.add_civilian(11)
	var army: ArmyState = ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	var result: Dictionary = NavalTransport.can_embark(_model, army, home)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("colonists"))
