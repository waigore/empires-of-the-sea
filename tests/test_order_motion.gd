extends GdToolsTest
## The chart's order language (issue #1198; REQ-P1-04, REQ-P5-05): own crews,
## standards and squadrons paint a loop while they hold an order — a march leans
## and churns a wake, work and a station breathe in place — while idle own units
## and every rival stay as they were.

const Fixture = preload("res://tests/map_fixture.gd")

## One mounted screen for the whole suite: a mount costs ~0.5 s under coverage
## and a re-seat ~0.15 s, so live cases share the chart and reset the session
## instead of remounting (`Fixture.suite_reset`). Pure OrderMotion / bare-marker
## cases never touch `_screen`, so they skip the re-seat (docs/testing.md).
var mounted: MapScreen = null
var pristine: Dictionary = {}
## The shared world as generated; non-underscore so before_all copies it onto
## each case (gd-tools clones the case instance).
var pristine_map: Array = []
## Set when this case has paid for a pristine re-seat; cleared in `before_each`.
var _chart_bound: bool = false


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)
	Fixture.park_screen(mounted)


func before_each() -> void:
	_chart_bound = false
	Fixture.park_screen(mounted)


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	pristine = {}


## Live cases reach the chart through `_screen` / `_attach()`; pure beat /
## marker cases that never ask never pay `suite_reset`.
func _attach() -> MapScreen:
	if _chart_bound and is_instance_valid(mounted):
		return mounted
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine, Fixture.world())
	_chart_bound = true
	return mounted


var _screen: MapScreen:
	get:
		return _attach()


## Wait until a busy loop settles instead of sleeping past the tween
## (docs/testing.md § Speed rules — no create_timer padding under coverage).
func _await_idle(order_of: Callable, frames: int = 90) -> void:
	for _frame in frames:
		if int(order_of.call()) == OrderMotion.Order.NONE:
			return
		await get_tree().process_frame
	assert_eq(int(order_of.call()), OrderMotion.Order.NONE, "the busy loop settled")


## --- the shared loop ---------------------------------------------------------

func test_an_idle_marker_never_beats() -> void:
	assert_eq(OrderMotion.beat(OrderMotion.Order.NONE, 1.3, 0.0), 0.0)
	assert_eq(
		OrderMotion.drift(OrderMotion.Order.NONE, 1.3, 0.0, Vector2.RIGHT), Vector2.ZERO
	)


func test_a_march_beats_and_leans_along_its_heading() -> void:
	var leaned: Vector2 = Vector2.ZERO
	for frame in 24:
		var moment: float = float(frame) * 0.1
		assert_between(OrderMotion.beat(OrderMotion.Order.MOVE, moment, 0.0), 0.0, 1.0)
		leaned = OrderMotion.drift(OrderMotion.Order.MOVE, moment, 0.0, Vector2.DOWN)
		assert_almost_eq(leaned.x, 0.0, 0.0001, "a march leans only along its heading")
		assert_gte(leaned.y, 0.0)
	assert_gt(leaned.y, 0.0, "the step is forward, never astern")
	# No heading named: nothing to lean along.
	assert_eq(
		OrderMotion.drift(OrderMotion.Order.MOVE, 0.4, 0.0, Vector2.ZERO), Vector2.ZERO
	)


func test_work_breathes_in_place_on_a_slower_time() -> void:
	assert_between(OrderMotion.beat(OrderMotion.Order.WORK, 0.7, 0.0), 0.0, 1.0)
	assert_eq(
		OrderMotion.drift(OrderMotion.Order.WORK, 0.7, 0.0, Vector2.RIGHT), Vector2.ZERO
	)
	assert_lt(OrderMotion.WORK_RATE, OrderMotion.MOVE_RATE, "work keeps a slower beat")


## The three markers draw every loop on their own, so a missing rules state can
## never crash a repaint.
func test_each_marker_paints_its_loop() -> void:
	var crew := CivilianMarker.new()
	add_child(crew)
	crew.set_order(OrderMotion.Order.WORK)
	assert_eq(crew.order, OrderMotion.Order.WORK)
	crew.set_order(OrderMotion.Order.MOVE, Vector2.RIGHT)
	assert_eq(crew.heading, Vector2.RIGHT)

	var standard := ArmyMarker.new()
	add_child(standard)
	standard.refresh(3, true)
	standard.set_order(OrderMotion.Order.MOVE, Vector2.DOWN)
	assert_eq(standard.heading, Vector2.DOWN)

	var hull := Ship.new()
	add_child(hull)
	hull.set_squadron(2, 4.0)
	assert_eq(hull.busy_order(), OrderMotion.Order.NONE)
	hull.set_station(true)
	assert_eq(hull.busy_order(), OrderMotion.Order.WORK)
	hull.set_order(OrderMotion.Order.MOVE, Vector2.RIGHT)
	assert_eq(hull.busy_order(), OrderMotion.Order.MOVE, "a sail outranks a station")

	await get_tree().process_frame
	await get_tree().process_frame
	crew.queue_free()
	standard.queue_free()
	hull.queue_free()


## --- own crews --------------------------------------------------------------

func test_an_own_crew_reads_busy_while_it_works() -> void:
	var layer: CivilianLayer = _screen.civilian_layer
	layer.viewer_faction = MapScreen.PLAYER_FACTION
	var unit: CivilianState = _own_crew(layer)
	assert_not_null(unit)
	unit.start_work("survey", unit.tile, 2)
	layer.sync()
	var marker: CivilianMarker = layer.marker_for(unit)
	assert_eq(marker.order, OrderMotion.Order.WORK, "a working crew reads busy")

	unit.clear_work()
	layer.sync()
	assert_eq(marker.order, OrderMotion.Order.NONE, "an idle crew stays still")


func test_a_crew_marching_shows_the_leaving_loop() -> void:
	var layer: CivilianLayer = _screen.civilian_layer
	layer.viewer_faction = MapScreen.PLAYER_FACTION
	var unit: CivilianState = _own_crew(layer)
	var marker: CivilianMarker = layer.marker_for(unit)
	var destinations: Array[Vector2i] = CivilianMovement.valid_tiles(_screen.model, unit)
	assert_false(destinations.is_empty(), "the crew has ground to walk")
	layer.apply_move(unit, destinations[0])
	assert_eq(marker.order, OrderMotion.Order.MOVE, "a marching crew reads busy")
	await _await_idle(func() -> int: return marker.order)
	assert_eq(marker.order, OrderMotion.Order.NONE, "the walk settles to idle")


func test_a_rival_crew_never_borrows_the_loop() -> void:
	var layer: CivilianLayer = _screen.civilian_layer
	layer.viewer_faction = MapScreen.PLAYER_FACTION
	var rival: int = _rival_owner()
	assert_true(rival != MapModel.NO_ID, "the chart holds a rival court")
	var unit: CivilianState = layer.add_unit(rival, "builder", _screen.capital_tile)
	unit.start_work("build_improvement", unit.tile, 2)
	layer.sync()
	var marker: CivilianMarker = layer.marker_for(unit)
	assert_true(marker.visible)
	assert_eq(marker.order, OrderMotion.Order.NONE, "a rival's crew paints nothing")


## --- own standards ----------------------------------------------------------

func test_a_march_lifts_an_own_standard_then_settles_it() -> void:
	var layer: ArmyLayer = _screen.army_layer
	layer.viewer_faction = MapScreen.PLAYER_FACTION
	var field: ArmyState = _detach()
	assert_not_null(field)
	var marker: ArmyMarker = layer.marker_for(field)
	var destinations: Array[int] = ArmyMovement.destinations(_screen.model, field)
	assert_false(destinations.is_empty(), "the field army has ground to march")
	layer.order(field, destinations[0])
	assert_eq(marker.order, OrderMotion.Order.MOVE, "a marching standard reads busy")
	await _await_idle(func() -> int: return marker.order)
	assert_eq(marker.order, OrderMotion.Order.NONE, "an idle standard stays still")


func test_a_standard_not_the_crowns_never_marches() -> void:
	var layer: ArmyLayer = _screen.army_layer
	var field: ArmyState = _detach()
	assert_not_null(field)
	var marker: ArmyMarker = layer.marker_for(field)
	var destinations: Array[int] = ArmyMovement.destinations(_screen.model, field)
	assert_false(destinations.is_empty(), "the field army has ground to march")
	layer.viewer_faction = _rival_owner()
	layer.order(field, destinations[0])
	assert_eq(marker.order, OrderMotion.Order.NONE, "another court's standard is unchanged")


## --- own squadrons ----------------------------------------------------------

func test_a_station_reads_as_work_only_on_the_crowns_fleet() -> void:
	var layer: ShipLayer = _screen.ship_layer
	var own: FleetState = _own_fleet(layer)
	assert_not_null(own)
	own.mission = FleetState.Mission.PATROL
	MapPlayFleets.show_dossier(_screen.play, own)
	var ship: Ship = layer.ship_for(own)
	assert_true(ship.on_station, "a station at sea reads busy")
	assert_eq(ship.busy_order(), OrderMotion.Order.WORK)

	own.clear_mission()
	layer.station(own)
	assert_false(ship.on_station, "a stand-down settles her")

	var rival: FleetState = _rival_fleet(layer)
	if rival != null:
		rival.mission = FleetState.Mission.PATROL
		layer.station(rival)
		assert_false(layer.ship_for(rival).on_station, "a rival's station is never ours")


func test_a_sail_lifts_the_hull_then_settles_her() -> void:
	var layer: ShipLayer = _screen.ship_layer
	var own: FleetState = _own_fleet(layer)
	var ship: Ship = layer.ship_for(own)
	assert_not_null(ship)
	ShipMarkers.sail(ship, ship.position + Vector2(40, 0))
	assert_eq(ship.order, OrderMotion.Order.MOVE, "a sailing hull reads busy")
	assert_eq(ship.facing, 1.0, "she turns into her course")
	await _await_idle(func() -> int: return ship.order)
	assert_eq(ship.order, OrderMotion.Order.NONE, "a hull at rest stays still")


func test_a_rival_hull_sails_without_the_loop() -> void:
	var ship := Ship.new()
	add_child(ship)
	ShipMarkers.sail(ship, Vector2(60, 0))
	assert_eq(ship.order, OrderMotion.Order.NONE, "a rival's sail is never ours")
	ship.queue_free()


## The roster pass re-reads the crown's flag and the station loop with it.
func test_the_roster_pass_re_reads_the_busy_loop() -> void:
	var layer: ShipLayer = _screen.ship_layer
	var own: FleetState = _own_fleet(layer)
	own.mission = FleetState.Mission.DEFEND
	layer.markers.sync(layer.fleets)
	assert_true(layer.ship_for(own).on_station, "the roster pass reads the station")


## --- helpers ----------------------------------------------------------------

func _own_crew(layer: CivilianLayer) -> CivilianState:
	for unit: CivilianState in layer.units:
		if unit.owner == MapScreen.PLAYER_FACTION and not unit.is_embarked():
			return unit
	return null


## One field army detached from the crown's Home Army: the only standard that
## may march.
func _detach() -> ArmyState:
	for army: ArmyState in _screen.army_layer.armies:
		if army.owner == MapScreen.PLAYER_FACTION and army.is_home_army():
			if army.count() == 0:
				return null
			_screen.army_layer.select(army)
			MapPlayArmies.on_action(_screen.play, "detach:%s" % army.regiments[0])
			return _screen.army_layer.selected_army
	return null


func _own_fleet(layer: ShipLayer) -> FleetState:
	for fleet: FleetState in layer.fleets:
		if fleet.owner == MapScreen.PLAYER_FACTION:
			return fleet
	return null


func _rival_fleet(layer: ShipLayer) -> FleetState:
	for fleet: FleetState in layer.fleets:
		if fleet.owner != MapScreen.PLAYER_FACTION:
			return fleet
	return null


## Any court but the crown's, as the chart's own ownership reads it.
func _rival_owner() -> int:
	var province: int = Fixture.foreign_province(_screen.model)
	if province == MapModel.NO_ID:
		return MapModel.NO_ID
	return _screen.model.province_owner(province)
