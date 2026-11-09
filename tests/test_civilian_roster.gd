extends GdToolsTest
## Pure view-model for the whole-empire civilian roster: grouping by region and
## province, region/craft filters and status text. The map-screen jump is
## covered in test_map_screen_crown_orders.

const Fixture = preload("res://tests/civilian_fixture.gd")

var _world: WorldMap = null
var _regions: MapRegionTable = null


func before_each() -> void:
	_world = _build_world()
	_regions = _build_regions()


func test_snapshot_spans_both_regions_and_ignores_rivals() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(_world, _regions, 0)
	assert_eq(int(snapshot["total"]), 5)
	assert_eq(int(snapshot["by_region"][FactionCatalog.OLD_WORLD]), 3)
	assert_eq(int(snapshot["by_region"][FactionCatalog.NEW_WORLD]), 2)
	assert_eq(int(snapshot["idle"]), 4)
	assert_eq(int(snapshot["working"]), 1)
	assert_eq(int(snapshot["by_type"]["merchant"]), 1)
	assert_eq((snapshot["groups"] as Array).size(), 2, "one posting per region")


func test_region_filter_narrows_to_one_world() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(_world, _regions, 0)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_ALL), 5)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_OLD), 3)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_NEW), 2)
	for group: Dictionary in CivilianRoster.groups(snapshot, CivilianRoster.REGION_NEW):
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)


func test_craft_filter_and_chip_counts() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(_world, _regions, 0)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_ALL, "merchant"), 1)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_OLD, "merchant"), 0)
	var counts: Dictionary = CivilianRoster.type_counts(snapshot, CivilianRoster.REGION_OLD)
	assert_eq(int(counts["explorer"]), 1)
	assert_eq(int(counts["builder"]), 1)
	assert_eq(int(counts["merchant"]), 0)


func test_rows_carry_posting_and_work_status() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(_world, _regions, 0)
	var merchant: Dictionary = _row_of_type(snapshot, "merchant")
	assert_eq(String(merchant["province_name"]), "Veracruz")
	assert_eq(int(merchant["region"]), FactionCatalog.NEW_WORLD)
	assert_true(String(merchant["status_text"]).contains("Build improvement"))
	assert_true(String(merchant["status_text"]).contains("2 turns to go"))
	assert_almost_eq(float(merchant["progress"]), 0.0, 0.001)
	var explorer: Dictionary = _row_of_type(snapshot, "explorer")
	assert_eq(String(explorer["status_text"]), "Idle — ready for orders")


func test_empty_inputs_make_an_empty_roster() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(null, null, 0)
	assert_eq(int(snapshot["total"]), 0)
	assert_true((snapshot["groups"] as Array).is_empty())
	for type_id: String in CivilianCatalog.ORDER:
		assert_eq(int(snapshot["by_type"][type_id]), 0)


func _row_of_type(snapshot: Dictionary, type_id: String) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if String(row["type_id"]) == type_id:
			return row
	return {}


func _build_regions() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old_units: Array[CivilianState] = []
	old_units.append(_unit(1, 0, "explorer", Vector2i(0, 0)))
	old_units.append(_unit(2, 0, "builder", Vector2i(0, 2)))
	old_units.append(_unit(3, 0, "spy", Vector2i(1, 1)))
	old_units.append(_unit(4, 1, "spy", Vector2i(2, 0)))
	table.set_region(FactionCatalog.OLD_WORLD, old_units)

	var new_units: Array[CivilianState] = []
	var merchant: CivilianState = _unit(5, 0, "merchant", Vector2i(0, 0))
	merchant.start_work("build_improvement", Vector2i(0, 1), 2, Vector2i(0, 0))
	new_units.append(merchant)
	new_units.append(_unit(6, 0, "rail_builder", Vector2i(0, 2)))
	table.set_region(FactionCatalog.NEW_WORLD, new_units)
	return table


func _unit(id: int, owner: int, type_id: String, tile: Vector2i) -> CivilianState:
	return CivilianState.create(id, owner, type_id, tile)


func _build_world() -> WorldMap:
	var old: MapModel = Fixture.build()
	var new: MapModel = Fixture.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(new)
	return world
