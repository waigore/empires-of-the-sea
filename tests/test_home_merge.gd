extends GdToolsTest
## Home-fleet merge (wiki: ships-and-naval § Home Fleet — membership and state):
## the one-tap join a squadron moored at the crown's seat can take, the docking
## absorption it shares, and the dossier row and report the player meets.

const Fixture = preload("res://tests/map_fixture.gd")
const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null
var _screen: MapScreen = null


func before_each() -> void:
	_model = NavalFixture.build()


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


## --- the rules --------------------------------------------------------------


func test_the_home_fleet_is_the_squadron_at_the_seat() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var at_sea := FleetState.at_sea(3, 0, 0)
	var roster: Array[FleetState] = [at_sea, home]

	assert_eq(FleetHomeMerge.home_fleet(_model, roster, 0), home)
	assert_null(FleetHomeMerge.home_fleet(_model, roster, 1), "a rival's port is not a home fleet")


func test_a_moored_squadron_joins_the_home_fleet() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var stray := FleetState.in_port(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	stray.hull_names["ship_b"] = "Santa Ana"
	var roster: Array[FleetState] = [home, stray]

	assert_true(bool(FleetHomeMerge.can_join(_model, roster, stray)["ok"]))
	var joined: Dictionary = FleetHomeMerge.join(_model, roster, stray)

	assert_true(bool(joined["ok"]))
	assert_eq(joined["fleet"], home)
	assert_eq(int(joined["hulls"]), 1)
	assert_eq(roster.size(), 1, "the sea-going squadron leaves the roster")
	assert_eq(home.hulls, ["ship_a", "ship_b"], "instance ids survive in order")
	assert_eq(home.hull_names["ship_b"], "Santa Ana", "a hull keeps the name it flies")
	assert_eq(home.count_of_type("fluyte"), 1)


func test_a_squadron_at_sea_is_told_to_moor_first() -> void:
	var home := FleetState.in_port(2, 0, 0)
	var at_sea := FleetState.at_sea(3, 0, 0)
	var roster: Array[FleetState] = [home, at_sea]

	var check: Dictionary = FleetHomeMerge.can_join(_model, roster, at_sea)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("capital port"))


func test_a_lone_squadron_has_nothing_to_join() -> void:
	var home := FleetState.in_port(2, 0, 0)
	var roster: Array[FleetState] = [home]

	var check: Dictionary = FleetHomeMerge.can_join(_model, roster, home)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("only squadron"))


func test_a_port_that_is_not_the_seat_cannot_join() -> void:
	_model.provinces[1].owner = 0
	var home := FleetState.in_port(2, 0, 0)
	var other := FleetState.in_port(3, 0, 1)
	var roster: Array[FleetState] = [home, other]

	assert_false(bool(FleetHomeMerge.can_join(_model, roster, other)["ok"]))
	assert_eq(roster.size(), 2, "a refusal mutates nothing")


func test_a_second_army_goes_ashore_from_the_merge() -> void:
	var home := FleetState.in_port(2, 0, 0)
	home.embarked_army = 11
	var stray := FleetState.in_port(3, 0, 0)
	stray.embarked_army = 12
	var roster: Array[FleetState] = [home, stray]

	var joined: Dictionary = FleetHomeMerge.join(_model, roster, stray)

	assert_eq(home.embarked_army, 11, "the home fleet keeps its own troops")
	assert_eq(int(joined["displaced"]), 12, "the second army is reported for landing")


func test_the_oldest_squadron_at_the_seat_absorbs_the_rest() -> void:
	var older := FleetState.in_port(4, 0, 0)
	var newer := FleetState.in_port(7, 0, 0)
	var incoming := FleetState.at_sea(9, 0, 0)
	var roster: Array[FleetState] = [newer, incoming, older]

	NavalMovement.apply_move(_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_model, roster, incoming)

	assert_eq(merge.get("fleet"), older, "one home fleet per seat: the oldest")
	assert_eq(roster.size(), 2)


func test_settle_folds_every_extra_squadron_into_the_home_fleet() -> void:
	var home := FleetState.in_port(2, 0, 0)
	var first := FleetState.in_port(3, 0, 0)
	var second := FleetState.in_port(5, 0, 0)
	var roster: Array[FleetState] = [home, first, second]

	var reports: Array[Dictionary] = FleetHomeMerge.settle(_model, roster, 0)

	assert_eq(reports.size(), 2)
	assert_eq(roster.size(), 1, "one squadron per capital port")
	assert_eq(home.ship_count(), 3, "every hull keeps its instance id")
	assert_eq(int(reports[0]["into"]), 2)
	assert_eq(FleetHomeMerge.settle(_model, roster, 0).size(), 0, "the pass is idempotent")


## --- the player's dossier ---------------------------------------------------


func test_the_dossier_offers_a_one_tap_join_at_the_seat() -> void:
	_screen = Fixture.attach_screen(self)
	var stray: FleetState = _stray_at_the_seat()
	_screen.ship_layer.select(_screen.ship_layer.ship_for(stray))

	var row: Dictionary = MapPlayHomeMerge.row(_screen.play, stray)
	var panel: FleetPanel = _screen.hud._fleet_panel

	assert_true(bool(row["ok"]), "a moored squadron can join")
	assert_eq(String(row["label"]), "Join the home fleet")
	assert_true(String(row["note"]).contains("home fleet"))
	assert_true(panel._merge_box.visible, "the dossier shows the row")
	assert_false(panel._yard_button.visible, "the join takes the yard's place, not more height")
	assert_eq(panel._status.text, String(row["note"]), "the note rides the status line")


func test_joining_keeps_the_player_on_the_home_fleet() -> void:
	_screen = Fixture.attach_screen(self)
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var stray: FleetState = _stray_at_the_seat()
	var hulls_before: int = home.ship_count()
	var stray_hulls: int = stray.ship_count()
	_screen.ship_layer.select(_screen.ship_layer.ship_for(stray))

	MapPlayHomeMerge.join(_screen.play)

	assert_false(_screen.ship_layer.fleets.has(stray), "the sea-going squadron is gone")
	assert_null(_screen.ship_layer.ship_for(stray), "its marker leaves the map")
	assert_eq(home.ship_count(), hulls_before + stray_hulls)
	assert_eq(
		_screen.ship_layer.fleet_of(_screen.ship_layer.selected()), home,
		"the dossier follows the hulls"
	)
	assert_eq(_screen.hud._fleet_panel._status.text, "Home fleet")
	assert_true(_last_toast().contains("home fleet at"), "the report names the merge")


func test_docking_at_the_seat_names_the_hulls_and_holds() -> void:
	_screen = Fixture.attach_screen(self)
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var sea: FleetState = _moored_squadron_at_the_seat()
	sea.location = FleetState.Location.AT_SEA
	sea.province = MapModel.NO_ID
	sea.moved = false
	_screen.ship_layer.select(_screen.ship_layer.ship_for(sea))
	var hulls: int = sea.ship_count()

	var hulls_before: int = home.ship_count()
	assert_true(
		MapPlayFleets.try_order(_screen.play, _screen.model.province_data(capital).port_tile)
	)

	assert_false(_screen.ship_layer.fleets.has(sea), "the sea-going squadron is gone")
	assert_eq(home.ship_count(), hulls_before + hulls)
	var report: String = _last_toast()
	assert_true(report.contains("%d hull" % hulls), "the report counts the hulls that joined")
	assert_true(report.contains("cargo hold"), "the report names the holds she carries")


func test_the_home_dossier_shows_her_holds() -> void:
	_screen = Fixture.attach_screen(self)
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))

	var row: Dictionary = MapPlayHomeMerge.row(_screen.play, home)
	var panel: FleetPanel = _screen.hud._fleet_panel

	assert_true(bool(row.get("home", false)))
	assert_true(String(row["holds_text"]).contains("cargo hold"))
	assert_false(bool(row.get("ok", false)), "the home fleet offers no join button")
	assert_true(panel._ships.text.contains("cargo hold"), "the dossier names the holds")
	assert_eq(panel._status.text, "Home fleet")


func test_a_squadron_at_sea_sees_the_merge_before_it_docks() -> void:
	_screen = Fixture.attach_screen(self)
	var capital: int = _screen.play.capital_province
	var sea: FleetState = _moored_squadron_at_the_seat()
	sea.location = FleetState.Location.AT_SEA
	sea.province = MapModel.NO_ID
	sea.sea_zone = NavalMovement.province_sea_zones(_screen.model, capital)[0]
	_screen.ship_layer.select(_screen.ship_layer.ship_for(sea))

	var row: Dictionary = MapPlayHomeMerge.row(_screen.play, sea)

	assert_false(bool(row.get("ok", false)), "the nudge is not a button")
	assert_true(String(row["note"]).contains("joins the home fleet"))


func test_a_transitional_save_repairs_on_load() -> void:
	_screen = Fixture.attach_screen(self)
	var stray: FleetState = _stray_at_the_seat()

	MapPlayHomeMerge.repair(_screen.play)

	assert_false(_screen.ship_layer.fleets.has(stray), "one squadron per capital port")
	assert_null(_screen.ship_layer.ship_for(stray))
	assert_true(_last_toast().contains("rejoined the home fleet"))


## A player squadron parked at the crown's seat *without* the merge: the
## transitional shape a save written before the merge has.
func _stray_at_the_seat() -> FleetState:
	var capital: int = _screen.play.capital_province
	var stray := FleetState.in_port(
		FleetRosters.next_id(_screen.ship_layer.fleets),
		MapScreen.PLAYER_FACTION,
		capital,
		["ship_90"],
		{"ship_90": "fluyte"}
	)
	_screen.ship_layer.fleets.append(stray)
	_screen.ship_layer.rebuild_markers()
	return stray


## A sea-going player squadron moved into the sea zone off the capital.
func _moored_squadron_at_the_seat() -> FleetState:
	var capital: int = _screen.play.capital_province
	var fleet: FleetState = Fixture.fleet_at_sea(
		_screen.ship_layer.fleets, MapScreen.PLAYER_FACTION
	)
	assert_not_null(fleet, "the fixture sails a player squadron")
	fleet.sea_zone = NavalMovement.province_sea_zones(_screen.model, capital)[0]
	fleet.province = MapModel.NO_ID
	fleet.location = FleetState.Location.AT_SEA
	return fleet


func _last_toast() -> String:
	var box: VBoxContainer = _screen.hud._toast_box
	assert_gt(box.get_child_count(), 0, "a report was raised")
	var plate: Control = box.get_child(box.get_child_count() - 1) as Control
	for child: Node in plate.get_children():
		if child is Label:
			return (child as Label).text
	return ""