extends GdToolsTest
## Sea-going fleet movement and docking (wiki: ships-and-naval, map-topology).

const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = NavalFixture.build()


func test_province_sea_zones_lists_adjacent_water() -> void:
	assert_eq(NavalMovement.province_sea_zones(_model, 0), [0])
	assert_eq(NavalMovement.province_sea_zones(_model, 1), [1])
	assert_eq(NavalMovement.province_sea_zones(_model, 99), [])


func test_owned_provinces_by_zone() -> void:
	assert_eq(NavalMovement.owned_provinces_by_zone(_model, 0, 0), [0])
	assert_eq(NavalMovement.owned_provinces_by_zone(_model, 1, 0), [])
	assert_eq(NavalMovement.owned_provinces_by_zone(_model, 0, 1), [])


func test_sea_fleet_moves_one_adjacent_zone() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(NavalMovement.destination_zones(_model, fleet), [1])

	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.AT_SEA, 1
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["entered_zone"]), 1)
	assert_eq(fleet.sea_zone, 1)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved)


func test_same_zone_is_not_a_move() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_false(bool(result["ok"]))
	assert_eq(fleet.sea_zone, 0)
	assert_false(fleet.moved)


func test_fleet_may_move_only_once_per_turn() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	NavalMovement.apply_move(_model, fleet, FleetState.Location.AT_SEA, 1)
	var second: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_false(bool(second["ok"]))
	assert_eq(fleet.sea_zone, 1)
	assert_true(String(second["reason"]).contains("already moved"))


func test_begin_turn_restores_the_move() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	NavalMovement.apply_move(_model, fleet, FleetState.Location.AT_SEA, 1)
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved)
	var check: Dictionary = NavalMovement.can_move(
		_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_true(bool(check["ok"]))


func test_docking_requires_ownership() -> void:
	var fleet := FleetState.at_sea(1, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.IN_PORT, 1
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("owns"))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)


func test_docking_requires_adjacent_coast() -> void:
	var fleet := FleetState.at_sea(1, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.IN_PORT, 0
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("border"))


func test_fleet_docks_at_a_harbour() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(NavalMovement.dockable_provinces(_model, fleet), [0])

	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.IN_PORT, 0
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["entered_zone"]), -1)
	assert_eq(fleet.location, FleetState.Location.IN_PORT)
	assert_eq(fleet.province, 0)
	assert_eq(fleet.sea_zone, MapModel.NO_ID)


func test_port_fleet_undocks_into_adjacent_zone() -> void:
	# Province 1 is a non-capital port, so this is a sea-going squadron.
	var fleet := FleetState.in_port(2, 0, 1)
	assert_eq(NavalMovement.destination_zones(_model, fleet), [1])

	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.AT_SEA, 1
	)

	assert_true(bool(result["ok"]))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)
	assert_eq(fleet.sea_zone, 1)
	assert_eq(fleet.province, MapModel.NO_ID)


func test_port_fleet_cannot_move_to_another_port() -> void:
	var fleet := FleetState.in_port(2, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.IN_PORT, 1
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("already in port"))


func test_province_without_a_harbour_cannot_be_entered() -> void:
	_model.provinces[0].port_tile = Vector2i(-1, -1)
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_false(NavalMovement.has_harbour(_model, 0))
	assert_eq(NavalMovement.dockable_provinces(_model, fleet), [])

	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.IN_PORT, 0
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("harbour"))


func test_unknown_zone_is_rejected() -> void:
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = NavalMovement.apply_move(
		_model, fleet, FleetState.Location.AT_SEA, 99
	)
	assert_false(bool(result["ok"]))
	assert_eq(fleet.sea_zone, 0)


func test_valid_destinations_match_the_location() -> void:
	var sea: Dictionary = NavalMovement.valid_destinations(
		_model, FleetState.at_sea(1, 0, 0)
	)
	assert_eq(sea["sea_zones"], [1])
	assert_eq(sea["provinces"], [0])

	var port: Dictionary = NavalMovement.valid_destinations(
		_model, FleetState.in_port(2, 0, 1)
	)
	assert_eq(port["sea_zones"], [1])
	assert_eq(port["provinces"], [])


func test_the_home_fleet_never_sails() -> void:
	var home := FleetState.in_port(2, 0, 0)
	assert_true(NavalMovement.is_home_fleet(_model, home))
	assert_eq(NavalMovement.destination_zones(_model, home), [])

	var result: Dictionary = NavalMovement.apply_move(
		_model, home, FleetState.Location.AT_SEA, 0
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("home fleet"))
	assert_eq(home.location, FleetState.Location.IN_PORT)
	assert_eq(home.province, 0)


func test_docking_at_the_capital_merges_into_the_home_fleet() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "sloop"})
	var roster: Array[FleetState] = [home, incoming]

	var dock: Dictionary = NavalMovement.apply_move(
		_model, incoming, FleetState.Location.IN_PORT, 0
	)
	var merge: Dictionary = NavalMovement.merge_into_home(_model, roster, incoming)
	var merged: FleetState = merge.get("fleet") as FleetState

	assert_true(bool(dock["ok"]))
	assert_eq(merged, home)
	assert_eq(roster.size(), 1)
	assert_eq(home.hulls, ["ship_a", "ship_b"], "instance ids survive in order")
	assert_eq(home.type_of("ship_b"), "sloop")


func test_merging_never_duplicates_a_hull_instance() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_a", "ship_b"], {"ship_b": "fluyte"})
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_model, incoming, FleetState.Location.IN_PORT, 0)
	NavalMovement.merge_into_home(_model, roster, incoming)

	assert_eq(home.hulls, ["ship_a", "ship_b"])
	assert_eq(home.count_of_type("carrack"), 1)


func test_docking_at_a_non_capital_port_does_not_merge() -> void:
	_model.provinces[1].owner = 0
	var home := FleetState.in_port(2, 0, 0)
	var incoming := FleetState.at_sea(3, 0, 1)
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_model, incoming, FleetState.Location.IN_PORT, 1)

	assert_false(NavalMovement.is_home_fleet(_model, incoming))
	var merge: Dictionary = NavalMovement.merge_into_home(_model, roster, incoming)
	assert_null(merge.get("fleet"))
	assert_eq(roster.size(), 2)


func test_fleet_state_defaults_to_one_hull() -> void:
	var sea := FleetState.at_sea(4, 2, 0)
	assert_eq(sea.ship_count(), 1)
	assert_eq(sea.hulls, ["ship_4"])
	assert_true(sea.is_at_sea())

	var port := FleetState.in_port(5, 1, 0, ["ship_a", "ship_b"])
	assert_eq(port.ship_count(), 2)
	assert_true(port.is_in_port())
	assert_false(port.moved)


func test_fleet_hulls_keep_their_catalog_types() -> void:
	var fleet := FleetState.at_sea(6, 0, 0, ["ship_6"], {"ship_6": "sloop"})
	assert_eq(fleet.type_of("ship_6"), "sloop")
	# Unmapped and unknown hulls count as the default carrack.
	assert_eq(fleet.type_of("ship_unknown"), "carrack")
	var legacy := FleetState.in_port(7, 0, 0, ["ship_7"])
	assert_eq(legacy.type_of("ship_7"), "carrack")
	assert_eq(legacy.count_of_type("carrack"), 1)


func test_fleet_hulls_can_be_added_removed_and_summarised() -> void:
	var fleet := FleetState.at_sea(8, 0, 0, ["ship_8"], {"ship_8": "carrack"})
	fleet.add_hull("ship_9", "galleon")
	fleet.add_hull("ship_9", "sloop")
	assert_eq(fleet.ship_count(), 2)
	assert_eq(fleet.count_of_type("galleon"), 1)
	assert_eq(fleet.hull_summary(), "1 Carrack · 1 Galleon")
	assert_true(fleet.remove_hull("ship_8"))
	assert_false(fleet.remove_hull("ship_8"))
	assert_eq(fleet.hull_summary(), "1 Galleon")
	assert_true(fleet.is_afloat())
	fleet.remove_hull("ship_9")
	assert_false(fleet.is_afloat())


# --- naval transport (wiki: ships-and-naval § Naval transport) ----------------


func _transport_pair() -> Array:
	var fleet := FleetState.in_port(3, 0, 0, ["ship_3"])
	var army := ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	return [army, fleet]


func test_one_hull_carries_one_regiment() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	assert_eq(NavalTransport.capacity(fleet), 1)
	assert_true(bool(NavalTransport.can_embark(_model, army, fleet)["ok"]))
	assert_true(bool(NavalTransport.embark(_model, army, fleet)["ok"]))
	assert_eq(army.province, MapModel.NO_ID)
	assert_true(army.moved)
	assert_eq(army.embarked_fleet, fleet.id)
	assert_eq(fleet.embarked_army, army.id)


func test_transport_capacity_refuses_an_army_larger_than_the_squadron() -> void:
	var pair: Array = _transport_pair()
	var fleet: FleetState = pair[1]
	var army := ArmyState.muster(8, 0, 0, false, ["pikemen", "pikemen"], 800)
	var check: Dictionary = NavalTransport.can_embark(_model, army, fleet)
	assert_false(bool(check["ok"]))
	assert_eq(
		String(check["reason"]),
		"The squadron has 1 hull and cannot carry 2 regiments.",
		"one hull reads singular"
	)


func test_the_home_army_never_boards() -> void:
	var pair: Array = _transport_pair()
	var fleet: FleetState = pair[1]
	var home := ArmyState.muster(8, 0, 0, true, ["pikemen"], 800)
	var check: Dictionary = NavalTransport.can_embark(_model, home, fleet)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Home Army"))


func test_boarding_needs_a_fleet_in_this_port() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var elsewhere := FleetState.in_port(4, 0, 1, ["ship_4"])
	var check: Dictionary = NavalTransport.can_embark(_model, army, elsewhere)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("not in this port"))


func test_an_embarked_army_lands_on_an_owned_coast() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_true(bool(NavalTransport.disembark(_model, army, fleet, 0)["ok"]))
	assert_eq(army.province, 0)
	assert_eq(army.embarked_fleet, -1)
	assert_eq(fleet.embarked_army, -1)
	assert_true(army.moved)


func test_a_hostile_landing_needs_a_beachhead() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	var check: Dictionary = NavalTransport.disembark(_model, army, fleet, 1)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("beachhead"))


## A marked beachhead opens the hostile coast on the following turn only, and
## the landing consumes it (wiki: ships-and-naval § Missions and Movement).
func test_beachhead_opens_a_hostile_coast_on_the_following_turn() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_eq(NavalTransport.hostile_coasts(_model, fleet), [1])
	var marked: Dictionary = NavalTransport.establish_beachhead(_model, fleet, 1, 5)
	assert_true(bool(marked["ok"]))
	assert_true(fleet.moved)
	assert_eq(fleet.beachhead_province, 1)
	assert_eq(fleet.beachhead_turn, 5)
	assert_false(bool(NavalTransport.beachhead_ready(fleet, 5)))
	assert_true(bool(NavalTransport.beachhead_ready(fleet, 6)))
	assert_eq(NavalTransport.landing_provinces(_model, fleet, 5), [])
	assert_eq(NavalTransport.landing_provinces(_model, fleet, 6), [1])
	assert_false(bool(NavalTransport.disembark(_model, army, fleet, 1, 5)["ok"]))
	assert_true(bool(NavalTransport.disembark(_model, army, fleet, 1, 6)["ok"]))
	assert_eq(army.province, 1)
	assert_eq(army.embarked_fleet, -1)
	assert_true(army.moved)
	assert_false(fleet.has_beachhead())
	# The landing is an invasion: the army is a contestant in the province.
	var armies: Array[ArmyState] = [army]
	assert_eq(ArmyCombat.contested_provinces(_model, armies), [1])


func test_beachhead_lasts_one_full_turn_then_expires() -> void:
	var fleet := FleetState.at_sea(3, 0, 1, ["ship_3"])
	fleet.moved = false
	assert_true(bool(NavalTransport.establish_beachhead(_model, fleet, 1, 5)["ok"]))
	var fleets: Array[FleetState] = [fleet]
	NavalTransport.expire_beachheads(fleets, 5)
	assert_true(fleet.has_beachhead())
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved)
	assert_true(bool(NavalTransport.beachhead_ready(fleet, 6)))
	NavalTransport.expire_beachheads(fleets, 6)
	assert_false(fleet.has_beachhead())


## A marker whose coast changes hands or whose war ends has no hostile landing
## left; the rules gate the landing, so the marker must not promise one.
func test_a_beachhead_target_must_stay_a_hostile_shore() -> void:
	var fleet := FleetState.at_sea(3, 0, 1, ["ship_3"])
	fleet.moved = false
	assert_true(bool(NavalTransport.establish_beachhead(_model, fleet, 1, 5)["ok"]))
	assert_true(NavalTransport.beachhead_target_valid(_model, fleet))
	_model.province_data(1).owner = 0
	assert_false(NavalTransport.beachhead_target_valid(_model, fleet))
	_model.province_data(1).owner = 1
	var peaceful := func(_a: int, _b: int) -> bool: return false
	assert_false(NavalTransport.beachhead_target_valid(_model, fleet, peaceful))
	assert_true(NavalTransport.beachhead_target_valid(_model, fleet))
	fleet.sea_zone = 0
	assert_false(NavalTransport.beachhead_target_valid(_model, fleet))
	assert_false(NavalTransport.beachhead_target_valid(null, fleet))
	assert_false(NavalTransport.beachhead_target_valid(_model, null))


func test_beachhead_refusals_cover_each_gate() -> void:
	var own_coast := FleetState.at_sea(3, 0, 0, ["ship_3"])
	assert_false(bool(NavalTransport.can_establish_beachhead(_model, own_coast, 0)["ok"]))
	var moved := FleetState.at_sea(4, 0, 1, ["ship_4"])
	moved.moved = true
	assert_true(String(
		NavalTransport.can_establish_beachhead(_model, moved, 1)["reason"]
	).contains("already moved"))
	var docked := FleetState.in_port(5, 0, 0, ["ship_5"])
	assert_true(String(
		NavalTransport.can_establish_beachhead(_model, docked, 1)["reason"]
	).contains("at sea"))
	var empty := FleetState.at_sea(6, 0, 1, [] as Array[String])
	empty.hulls = []
	empty.hull_types = {}
	assert_true(String(
		NavalTransport.can_establish_beachhead(_model, empty, 1)["reason"]
	).contains("no hulls"))
	var far := FleetState.at_sea(7, 0, 0, ["ship_7"])
	assert_true(String(
		NavalTransport.can_establish_beachhead(_model, far, 1)["reason"]
	).contains("border"))
	var peaceful := func(_a: int, _b: int) -> bool: return false
	assert_true(String(
		NavalTransport.can_establish_beachhead(_model, own_coast, 1, 0, peaceful)["reason"]
	).contains("declared war"))
	assert_false(bool(NavalTransport.can_establish_beachhead(null, own_coast, 1)["ok"]))
	assert_true(String(
		NavalTransport.can_establish_beachhead(_model, own_coast, 99)["reason"]
	).contains("not a province"))
	assert_false(bool(NavalTransport.establish_beachhead(_model, moved, 1, 0)["ok"]))
	assert_false(bool(NavalTransport.beachhead_ready(null, 0)))
	assert_false(NavalTransport.beachhead_allows(null, null, 1))
	assert_false(NavalTransport.beachhead_allows(_model, null, 1))
	assert_eq(NavalTransport.hostile_coasts(null, own_coast).size(), 0)
	assert_eq(NavalTransport.hostile_coasts(_model, own_coast).size(), 0)
	var own_mark := FleetState.at_sea(8, 0, 0, ["ship_8"])
	own_mark.beachhead_province = 0
	own_mark.beachhead_turn = 4
	assert_false(NavalTransport.beachhead_allows(_model, own_mark, 0, 5))
	var mixed: Array[FleetState] = [null]
	NavalTransport.expire_beachheads(mixed, 5)


func test_landing_requires_the_fleet_to_border_the_coast() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	var check: Dictionary = NavalTransport.disembark(_model, army, fleet, 0)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("border"))


func test_landing_provinces_follow_the_sea_zone() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_eq(NavalTransport.landing_provinces(_model, fleet), [0])
	fleet.sea_zone = 1
	assert_eq(NavalTransport.landing_provinces(_model, fleet), [])


func test_breaking_up_a_hull_cannot_strand_the_troops() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	assert_false(bool(NavalTransport.can_scrap(fleet, army)["ok"]))
	fleet.add_hull("ship_5")
	assert_true(bool(NavalTransport.can_scrap(fleet, army)["ok"]))


func test_transport_state_survives_a_save_round_trip() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	fleet.beachhead_province = 1
	fleet.beachhead_turn = 5
	var saved_army: ArmyState = ArmyState.from_dict(army.to_dict())
	var saved_fleet: FleetState = FleetState.from_dict(fleet.to_dict())
	assert_eq(saved_army.embarked_fleet, fleet.id)
	assert_eq(saved_army.province, MapModel.NO_ID)
	assert_eq(saved_fleet.embarked_army, army.id)
	assert_eq(saved_fleet.beachhead_province, 1)
	assert_eq(saved_fleet.beachhead_turn, 5)


func _transport_layer(army: ArmyState) -> ArmyLayer:
	var layer := ArmyLayer.new()
	layer.model = _model
	var armies: Array[ArmyState] = [army]
	layer.armies = armies
	layer.regions.set_region(_model.region_id, layer.armies)
	return layer


func test_an_embarked_army_follows_its_fleet_between_regions() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	ArmyTransport.move_to_region(layer, army.id, 1)
	assert_eq(layer.armies.size(), 0)
	var destination: Array[ArmyState] = []
	destination.assign(layer.regions.value(1, []))
	assert_eq(destination.size(), 1)
	assert_true(destination[0] == army)
	layer.free()


func test_a_sunk_squadrons_army_leaves_the_roster() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, {})
	assert_eq(lost.size(), 1)
	assert_true(lost[0] == army)
	assert_eq(layer.armies.size(), 0)
	layer.free()


func test_a_live_squadron_keeps_its_army() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	var live: Dictionary = {}
	live[army.id] = fleet.id
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, live)
	assert_eq(lost.size(), 0)
	assert_eq(layer.armies.size(), 1)
	layer.free()


func test_embarkation_refusals_cover_each_gate() -> void:
	var fleet := FleetState.in_port(3, 0, 0, ["ship_3"])
	var army := ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	assert_false(bool(NavalTransport.can_embark(_model, null, fleet)["ok"]))
	assert_false(bool(NavalTransport.can_embark(_model, army, null)["ok"]))
	var foreign := ArmyState.muster(8, 1, 0, false, ["pikemen"], 800)
	assert_false(bool(NavalTransport.can_embark(_model, foreign, fleet)["ok"]))
	var empty := ArmyState.muster(9, 0, 0, false, [], 900)
	assert_false(bool(NavalTransport.can_embark(_model, empty, fleet)["ok"]))
	army.embarked_fleet = 5
	assert_false(bool(NavalTransport.can_embark(_model, army, fleet)["ok"]))
	army.embarked_fleet = -1
	army.moved = true
	assert_false(bool(NavalTransport.can_embark(_model, army, fleet)["ok"]))
	army.moved = false
	fleet.location = FleetState.Location.AT_SEA
	assert_false(bool(NavalTransport.can_embark(_model, army, fleet)["ok"]))
	fleet.location = FleetState.Location.IN_PORT
	fleet.moved = true
	assert_false(bool(NavalTransport.can_embark(_model, army, fleet)["ok"]))
	fleet.moved = false
	fleet.embarked_army = 9
	assert_false(bool(NavalTransport.can_embark(_model, army, fleet)["ok"]))
	fleet.embarked_army = -1
	assert_false(bool(NavalTransport.can_embark(null, army, fleet)["ok"]))


func test_landing_refusals_cover_each_gate() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	assert_false(bool(NavalTransport.can_disembark(_model, null, fleet, 0)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_model, army, null, 0)["ok"]))
	var outsider := ArmyState.muster(8, 0, 0, false, ["pikemen"], 800)
	assert_false(bool(NavalTransport.can_disembark(_model, outsider, fleet, 0)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_model, army, fleet, 99)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_model, army, fleet, 1)["ok"]))
	_model.province_data(1).owner = 0
	assert_false(bool(NavalTransport.can_disembark(_model, army, fleet, 1)["ok"]))
	_model.province_data(1).owner = 1
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_false(bool(NavalTransport.can_disembark(_model, army, fleet, 0)["ok"]))
	fleet.sea_zone = 0
	assert_true(bool(NavalTransport.can_disembark(_model, army, fleet, 0)["ok"]))


func test_port_landing_and_scrap_gates() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	assert_eq(NavalTransport.landing_provinces(_model, fleet), [0])
	assert_eq(NavalTransport.landing_provinces(_model, null), [])
	assert_eq(NavalTransport.landing_provinces(_model, FleetState.at_sea(4, 0, 0)), [0])
	assert_true(bool(NavalTransport.can_scrap(null, army)["ok"]))
	assert_false(bool(NavalTransport.can_scrap(fleet, null)["ok"]))


func test_transport_layer_lookups_and_refusals() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	var layer: ArmyLayer = _transport_layer(army)
	assert_null(ArmyTransport.army_by_id(layer, -1))
	assert_null(ArmyTransport.army_by_id(layer, 999))
	assert_true(ArmyTransport.army_by_id(layer, army.id) == army)
	assert_eq(ArmyTransport.region_of(layer, army), _model.region_id)
	assert_false(bool(ArmyTransport.embark(layer, army, FleetState.at_sea(3, 0, 0))["ok"]))
	assert_false(bool(ArmyTransport.disembark(layer, null, 0)["ok"]))
	assert_false(bool(ArmyTransport.disembark(layer, fleet, 0)["ok"]))
	ArmyTransport.move_to_region(layer, 999, 1)
	ArmyTransport.remove_from(layer, army, _model.region_id)
	assert_eq(layer.armies.size(), 0)
	layer.free()


func test_transport_layer_same_region_move_is_a_no_op() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	ArmyTransport.move_to_region(layer, army.id, _model.region_id)
	assert_eq(layer.armies.size(), 1)
	ArmyTransport.move_to_region(layer, army.id, 1)
	assert_eq(ArmyTransport.region_of(layer, army), 1)
	layer.free()


func test_drop_lost_leaves_unembarked_armies_alone() -> void:
	var pair: Array = _transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_model, army, fleet)
	var grounded := ArmyState.muster(11, 0, 0, false, ["pikemen"], 1100)
	var layer: ArmyLayer = _transport_layer(army)
	layer.armies.append(grounded)
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, {})
	assert_eq(lost.size(), 1)
	assert_eq(layer.armies.size(), 1)
	assert_true(layer.armies[0] == grounded)
	layer.free()


## The squadron's own roster names the troops it carries; the army's
## back-pointer may lag a merge, and that must not block the landing
## (wiki: ships-and-naval § Naval transport; DR-20261109-17).
func test_an_army_lands_after_its_squadron_was_merged() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	var army := ArmyState.create(7, 0, 0, false, ["unit_7"], {"unit_7": "pikemen"})
	army.embarked_fleet = incoming.id
	incoming.embarked_army = army.id
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_model, roster, incoming)
	var merged: FleetState = merge.get("fleet") as FleetState

	assert_eq(merged.embarked_army, army.id, "the home fleet keeps the troops")
	assert_eq(army.embarked_fleet, incoming.id, "the army's own pointer lags")
	var check: Dictionary = NavalTransport.can_disembark(_model, army, merged, 0)
	assert_true(bool(check.get("ok", false)), String(check.get("reason", "")))


## One squadron carries one army: a merge keeps the target's troops and reports
## the surplus army so the layer can land it at the port (wiki: ships-and-naval
## § Naval transport).
func test_a_merge_keeps_one_army_and_reports_the_other() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	home.embarked_army = 10
	incoming.embarked_army = 11
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_model, roster, incoming)

	assert_eq(home.embarked_army, 10, "the moored army stays aboard")
	assert_eq(int(merge["displaced"]), 11, "the surplus army is reported")
	assert_eq(incoming.embarked_army, -1, "the merged-away squadron is emptied")
