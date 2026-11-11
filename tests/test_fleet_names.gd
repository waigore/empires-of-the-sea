extends GdToolsTest
## Every hull bears a name (wiki: naming § Ship names; DR-20261111-07): a launch
## christens it from its crown's period pool, a squadron never flies the same name
## twice, a saved hull keeps the name it was given, and a hull saved before names
## existed is christened on load by the same arithmetic.

const Fixture = preload("res://tests/map_fixture.gd")

var _econ: PlayerEconomy


func before_each() -> void:
	_econ = PlayerEconomy.starting()
	_econ.treasury = 60000


func test_a_launch_christens_the_hull_from_its_crown() -> void:
	var fleet := FleetState.empty_in_port(3, 0, 1)

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_1")

	assert_true(bool(result["ok"]), String(result["reason"]))
	var name: String = String(result["name"])
	assert_true(
		ShipNames.pool_for(0).has(name),
		"Spain christens from its own pool, got '%s'" % name
	)
	assert_eq(ShipNames.of(fleet, "ship_1"), name, "the name is kept on the hull")


func test_the_same_crown_squadron_and_hull_always_name_alike() -> void:
	var first := FleetState.empty_in_port(3, 0, 1)
	var second := FleetState.empty_in_port(3, 0, 1)

	first.add_hull("ship_7", "carrack")
	second.add_hull("ship_7", "carrack")

	assert_eq(ShipNames.of(first, "ship_7"), ShipNames.of(second, "ship_7"))
	assert_true(
		ShipNames.pool_for(0).has(ShipNames.of(first, "ship_7")),
		"a reloaded fleet speaks the same name"
	)


func test_a_squadron_never_flies_the_same_name_twice() -> void:
	var fleet := FleetState.empty_in_port(3, 0, 1)
	for index in range(14):
		fleet.add_hull("ship_%d" % index, "carrack")

	var names: Array[String] = []
	var numbered: bool = false
	for hull_id: String in fleet.hulls:
		var name: String = ShipNames.of(fleet, hull_id)
		assert_false(name.is_empty())
		assert_false(names.has(name), "'%s' flies twice" % name)
		if name.ends_with(" II"):
			numbered = true
		names.append(name)
	assert_eq(names.size(), fleet.ship_count())
	# Past the ten-name pool the repeats are numbered, never duplicated.
	assert_true(numbered, "a repeat is numbered, not duplicated")


func test_a_crown_with_no_pool_still_names_its_hulls() -> void:
	var fleet := FleetState.empty_in_port(2, 9, 5)
	fleet.add_hull("ship_1", "sloop")

	assert_true(ShipNames.GENERIC.has(ShipNames.of(fleet, "ship_1")))


func test_a_saved_hull_keeps_the_name_it_was_given() -> void:
	var fleet := FleetState.in_port(3, 1, 4, ["ship_2", "ship_5"], {})
	var before: Dictionary = {}
	for hull_id: String in fleet.hulls:
		before[hull_id] = ShipNames.of(fleet, hull_id)

	var restored: FleetState = FleetState.from_dict(fleet.to_dict())

	for hull_id: String in restored.hulls:
		assert_eq(ShipNames.of(restored, hull_id), String(before[hull_id]))
	assert_eq(restored.to_dict()["hull_names"], fleet.to_dict()["hull_names"])


func test_a_hull_saved_before_names_existed_is_christened_on_load() -> void:
	var fleet := FleetState.in_port(3, 1, 4, ["ship_2", "ship_5"], {})
	var legacy: Dictionary = fleet.to_dict()
	legacy.erase("hull_names")

	var restored: FleetState = FleetState.from_dict(legacy)

	assert_eq(restored.ship_count(), 2)
	for hull_id: String in restored.hulls:
		assert_eq(
			ShipNames.of(restored, hull_id),
			ShipNames.of(fleet, hull_id),
			"the load speaks the name the hull would have flown"
		)


func test_a_merge_keeps_every_hull_name() -> void:
	var home := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var returning := FleetState.at_sea(5, 1, 2, ["ship_4"], {})
	var expected: String = ShipNames.of(returning, "ship_4")
	var home_name: String = ShipNames.of(home, "ship_1")

	home.merge_from(returning)

	assert_eq(ShipNames.of(home, "ship_4"), expected)
	assert_eq(ShipNames.of(home, "ship_1"), home_name)


func test_scrapping_names_the_hull_it_breaks() -> void:
	var fleet := FleetState.in_port(3, 0, 1, ["ship_1", "ship_2"], {})
	var doomed: String = ShipNames.of(fleet, "ship_2")

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_2")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(String(result["name"]), doomed)
	assert_false(fleet.hull_names.has("ship_2"), "a broken hull keeps no name")


func test_an_unnamed_hull_reads_a_name_without_a_write() -> void:
	var fleet := FleetState.in_port(3, 0, 1, [], {})
	fleet.hulls.append("ship_9")
	fleet.hull_types["ship_9"] = "carrack"

	var name: String = ShipNames.of(fleet, "ship_9")

	assert_false(name.is_empty())
	assert_false(fleet.hull_names.has("ship_9"), "a read never stores work of its own")


## The dossier names the hull, and the break-up confirmation names what it breaks
## (REQ-P1-03, REQ-P5-04).
func test_the_dossier_and_the_break_up_name_the_hull() -> void:
	var panel := FleetPanel.new()
	add_child(panel)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var hull_name: String = ShipNames.of(fleet, "ship_1")
	var rows: Array[Dictionary] = [
		{
			"type_id": "carrack",
			"name": "Carrack",
			"cost_text": "8000",
			"ok": true,
			"reason": "",
		},
	]

	panel.refresh(Fixture.region(), fleet, true, "", rows)
	panel.set_yard_open(true)

	var printed: bool = false
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains(hull_name) and text.contains("Carrack"):
			printed = true
	assert_true(printed, "the hull row prints '%s — Carrack'" % hull_name)

	var confirm: Button = null
	for node: Node in panel.find_children("*", "Button", true, false):
		if (node as Button).text == "Break up":
			confirm = node as Button
	assert_not_null(confirm, "the hull offers a break-up")
	panel._on_scrap_pressed("ship_1")
	for node: Node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "Confirm scrap":
			confirm = button
	assert_eq(confirm.text, "Confirm scrap", "the first tap only arms")
	assert_true(
		confirm.tooltip_text.contains(hull_name),
		"the confirmation names the hull: '%s'" % confirm.tooltip_text
	)
	panel.free()
