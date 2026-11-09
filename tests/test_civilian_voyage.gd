extends GdToolsTest
## Civilians aboard a squadron and ashore again (wiki: civilian-units
## § Overseas deployment; fog-and-exploration § New World arrival;
## DR-20261109-17). Pure rules on the shared naval fixture.

const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = NavalFixture.build()


func _fleet() -> FleetState:
	return FleetState.in_port(
		1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"}
	)


func _unit(type_id: String = "builder", tile: Vector2i = Vector2i(0, 0)) -> CivilianState:
	return CivilianState.create(7, 0, type_id, tile)


func test_one_hull_carries_one_civilian() -> void:
	assert_eq(CivilianVoyage.capacity(_fleet()), 2)
	assert_eq(CivilianVoyage.capacity(null), 0)


func test_a_civilian_boards_a_squadron_in_its_port() -> void:
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	var result: Dictionary = CivilianVoyage.embark(_model, unit, fleet)

	assert_true(bool(result["ok"]))
	assert_true(unit.is_embarked())
	assert_eq(unit.embarked_fleet, fleet.id)
	assert_eq(unit.tile, CivilianState.NO_TILE)
	assert_true(unit.moved)
	assert_true(fleet.has_civilian(unit.id))
	assert_eq(fleet.civilian_count(), 1)


func test_boarding_refusals_name_the_missing_condition() -> void:
	var fleet: FleetState = _fleet()

	assert_true(String(CivilianVoyage.embark(_model, null, fleet)["reason"]).contains("no civilian"))
	assert_true(String(CivilianVoyage.embark(_model, _unit(), null)["reason"]).contains("No squadron"))

	var foreign: CivilianState = CivilianState.create(8, 1, "builder", Vector2i(0, 0))
	assert_true(String(CivilianVoyage.embark(_model, foreign, fleet)["reason"]).contains("Own colours"))

	var busy: CivilianState = _unit()
	busy.start_work("build_improvement", Vector2i(0, 0), 1)
	assert_true(String(CivilianVoyage.embark(_model, busy, fleet)["reason"]).contains("busy working"))

	var marched: CivilianState = _unit()
	marched.moved = true
	assert_true(String(CivilianVoyage.embark(_model, marched, fleet)["reason"]).contains("already moved"))

	var at_sea: FleetState = FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	assert_true(String(CivilianVoyage.embark(_model, _unit(), at_sea)["reason"]).contains("in port"))

	var sailed: FleetState = _fleet()
	sailed.moved = true
	assert_true(String(CivilianVoyage.embark(_model, _unit(), sailed)["reason"]).contains("already sailed"))

	var elsewhere: CivilianState = _unit("builder", Vector2i(5, 0))
	assert_true(String(CivilianVoyage.embark(_model, elsewhere, fleet)["reason"]).contains("not in this port"))


func test_a_squadron_carrying_an_army_takes_no_colonists() -> void:
	var fleet: FleetState = _fleet()
	fleet.embarked_army = 3
	var result: Dictionary = CivilianVoyage.embark(_model, _unit(), fleet)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("carries troops"))


func test_the_passenger_list_cannot_exceed_the_hulls() -> void:
	var fleet: FleetState = FleetState.in_port(2, 0, 0, ["a"], {"a": "fluyte"})
	var first: CivilianState = CivilianState.create(7, 0, "builder", Vector2i(0, 0))
	var second: CivilianState = CivilianState.create(8, 0, "explorer", Vector2i(1, 0))

	assert_true(bool(CivilianVoyage.embark(_model, first, fleet)["ok"]))
	var refused: Dictionary = CivilianVoyage.embark(_model, second, fleet)

	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("1 hull"))
	assert_eq(fleet.civilian_count(), 1)


func test_the_port_province_is_the_landing_ground() -> void:
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	CivilianVoyage.embark(_model, unit, fleet)

	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(_model, unit, fleet)

	assert_true(tiles.has(Vector2i(0, 0)))
	assert_true(tiles.has(Vector2i(1, 0)))
	assert_true(tiles.has(Vector2i(0, 1)))
	assert_false(tiles.has(Vector2i(5, 0)), "another province is not this port")
	assert_eq(CivilianVoyage.landing_provinces(_model, unit, fleet), [0])
	assert_eq(
		CivilianVoyage.landing_tile_in(_model, unit, fleet, 0),
		Vector2i(0, 0)
	)


func test_a_squadron_at_sea_lands_on_the_bordering_coast() -> void:
	var fleet: FleetState = FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	var explorer: CivilianState = _unit("explorer", Vector2i(0, 0))
	explorer.embarked_fleet = fleet.id
	fleet.add_civilian(explorer.id)

	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(_model, explorer, fleet)

	assert_true(tiles.has(Vector2i(1, 0)), "coast beside the zone")
	assert_true(tiles.has(Vector2i(0, 1)))
	assert_false(tiles.has(Vector2i(0, 0)), "inland tiles stay out of reach")
	assert_false(tiles.has(Vector2i(5, 1)), "the far zone is not this coast")


func test_a_builder_needs_crown_land_where_an_explorer_may_land_anywhere() -> void:
	var fleet: FleetState = FleetState.at_sea(2, 1, 1, ["c"], {"c": "fluyte"})
	var builder: CivilianState = _unit("builder", Vector2i(0, 0))
	builder.embarked_fleet = fleet.id
	fleet.add_civilian(builder.id)
	var explorer: CivilianState = _unit("explorer", Vector2i(0, 0))
	explorer.embarked_fleet = fleet.id
	fleet.add_civilian(explorer.id)

	var builder_tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(
		_model, builder, fleet
	)
	assert_false(builder_tiles.has(Vector2i(5, 1)), "a rival coast refuses a builder")
	var explorer_tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(
		_model, explorer, fleet
	)
	assert_true(explorer_tiles.has(Vector2i(5, 1)), "an explorer surveys any coast")


func test_going_ashore_spends_the_move_and_frees_the_hull() -> void:
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	CivilianVoyage.embark(_model, unit, fleet)

	var result: Dictionary = CivilianVoyage.disembark(
		_model, unit, fleet, Vector2i(0, 1)
	)

	assert_true(bool(result["ok"]))
	assert_false(unit.is_embarked())
	assert_eq(unit.tile, Vector2i(0, 1))
	assert_true(unit.moved)
	assert_false(fleet.has_civilian(unit.id))
	assert_eq(CivilianVoyage.disembark(
		_model, unit, fleet, Vector2i(0, 1)
	)["ok"], false)


func test_a_landing_reveals_the_tile_and_its_orthogonal_neighbours() -> void:
	var view := VisibilityModel.new()
	view.setup(_model, 0)
	view.levels.fill(VisibilityModel.Level.UNKNOWN)

	var changed: Array = view.reveal_landing(Vector2i(1, 0))

	assert_eq(view.level_at(1, 0), VisibilityModel.Level.FULLY_VISIBLE)
	for tile: Vector2i in [
		Vector2i(2, 0), Vector2i(0, 0), Vector2i(1, 1)
	]:
		assert_eq(
			view.level_at(tile.x, tile.y),
			VisibilityModel.Level.FULLY_VISIBLE,
			str(tile)
		)
	assert_eq(
		view.level_at(0, 1), VisibilityModel.Level.UNKNOWN, "diagonals stay dark"
	)
	assert_eq(changed.size(), 4)
	assert_eq(view.reveal_landing(Vector2i(-1, -1)), [] as Array)


func test_passengers_survive_a_save_round_trip() -> void:
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	CivilianVoyage.embark(_model, unit, fleet)

	var restored_fleet: FleetState = FleetState.from_dict(fleet.to_dict())
	var restored_unit: CivilianState = CivilianState.from_dict(unit.to_dict())

	assert_eq(restored_fleet.embarked_civilians, [7])
	assert_true(restored_fleet.has_civilian(7))
	assert_true(restored_unit.is_embarked())
	assert_eq(restored_unit.embarked_fleet, fleet.id)


func test_the_roster_entry_follows_the_squadron_across_regions() -> void:
	var layer := CivilianLayer.new()
	layer.model = _model
	var unit: CivilianState = _unit()
	layer.units = [unit]
	layer.regions.set_region(0, layer.units)
	layer.regions.set_region(1, [] as Array[CivilianState])

	CivilianVoyageMap.move_to_region(layer, unit.id, 1)

	assert_eq(layer.units.size(), 0)
	var destination: Array = layer.regions.value(1, [])
	assert_true(destination.has(unit))
	assert_eq(CivilianVoyageMap.region_of(layer, unit), 1)
	assert_eq(CivilianVoyageMap.by_id(layer, unit.id), unit)
	assert_eq(CivilianVoyageMap.by_id(layer, 99), null)
	layer.free()


func test_a_sunken_squadron_drowns_its_passengers() -> void:
	var layer := CivilianLayer.new()
	layer.model = _model
	var safe: CivilianState = _unit()
	safe.embarked_fleet = 5
	var lost: CivilianState = CivilianState.create(8, 0, "explorer", CivilianState.NO_TILE)
	lost.embarked_fleet = 6
	layer.units = [safe, lost]
	layer.regions.set_region(0, layer.units)

	var dropped: Array[CivilianState] = CivilianVoyageMap.drop_lost(layer, {5: true})

	assert_eq(dropped.size(), 1)
	assert_eq(dropped[0], lost)
	assert_eq(layer.units.size(), 1)
	assert_true(layer.units.has(safe))
	layer.free()
