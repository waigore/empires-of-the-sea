extends GdToolsTest
## Survey projection for the resource lens: statuses, worked counts and the fog
## rule (no estate is surveyed from unknown ground).

const Fixture = preload("res://tests/map_fixture.gd")


func test_snapshot_reads_every_charted_resource_tile() -> void:
	var model: MapModel = Fixture.region()
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, LandWorks.new(), [], FactionCatalog.PLAYER_FACTION
	)
	assert_gt(int(survey["counts"]["provinces"]), 0)
	assert_gt(int(survey["counts"]["estates"]), 0)
	var provinces: Array = survey["provinces"]
	for raw: Variant in provinces:
		var entry: Dictionary = raw
		assert_gt(int(entry["counts"]["estates"]), 0)
		assert_eq(int(entry["counts"]["estates"]), (entry["rows"] as Array).size())
		assert_false(String(entry["summary"]).is_empty())


func test_a_connected_estate_yields_and_counts_as_worked() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = Fixture.owned_resource_tile(model, works)
	assert_true(tile.x >= 0)
	works.set_improvement(model, tile, 1)
	works.set_prospected(owner, model, tile)
	# The tile itself is the seat: connectivity seeds there, so the estate pays.
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, works, [], owner, null, tile, {}
	)
	var entry: Dictionary = _entry(survey, model.province_at(tile.x, tile.y))
	var row: Dictionary = _row(entry, tile)
	assert_eq(String(row["status"]), "producing")
	assert_eq(int(row["output"]), 1)
	assert_eq(int(entry["counts"]["worked"]), 1)
	assert_gt(int(entry["counts"]["producing"]), 0)
	assert_false((entry["output"] as Dictionary).is_empty())


func test_severed_estate_reports_disconnected() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = Fixture.owned_resource_tile(model, works)
	works.set_improvement(model, tile, 1)
	works.set_prospected(owner, model, tile)
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, works, [], owner, null, Vector2i(-1, -1), {}
	)
	var row: Dictionary = _row(_entry(survey, model.province_at(tile.x, tile.y)), tile)
	assert_eq(String(row["status"]), "disconnected")
	assert_eq(int(row["output"]), 0)


func test_unknown_ground_is_never_surveyed() -> void:
	var model: MapModel = Fixture.region()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: ProvinceState = model.provinces[0]
	var visibility := VisibilityModel.new()
	visibility.setup(model, owner)
	for tile: Vector2i in province.tiles:
		visibility.lower_to(
			model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, LandWorks.new(), [], owner, visibility
	)
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		assert_ne(int(entry["id"]), province.id)


func test_foreign_estates_say_whether_they_are_worked() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var tile: Vector2i = _foreign_resource_tile(model)
	assert_true(tile.x >= 0)
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: int = model.province_at(tile.x, tile.y)
	var survey: Dictionary = ResourceSurvey.snapshot(model, works, [], owner)
	assert_eq(String(_row(_entry(survey, province), tile)["status"]), "foreign")
	works.set_improvement(model, tile, 2)
	survey = ResourceSurvey.snapshot(model, works, [], owner)
	var row: Dictionary = _row(_entry(survey, province), tile)
	assert_eq(String(row["status"]), "foreign_worked")
	assert_eq(int(row["output"]), 0)


func test_builder_at_work_marks_building() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = Fixture.owned_resource_tile(model, works)
	var unit := CivilianState.create(1, owner, "builder", tile)
	unit.start_work("build_improvement", tile, 2)
	var survey: Dictionary = ResourceSurvey.snapshot(
		model, works, [unit], owner, null, tile, {}
	)
	var entry: Dictionary = _entry(survey, model.province_at(tile.x, tile.y))
	var row: Dictionary = _row(entry, tile)
	assert_eq(String(row["status"]), "building")
	assert_eq(int(entry["counts"]["building"]), 1)
	assert_eq(int(entry["counts"]["worked"]), 0)
	assert_true(bool(row["working"]))
	assert_eq(int(row["remaining"]), 2)


func test_anchor_falls_back_to_a_charted_resource_tile() -> void:
	var model: MapModel = Fixture.region()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var base: Dictionary = ResourceSurvey.snapshot(model, LandWorks.new(), [], owner)
	for raw: Variant in base["provinces"]:
		var entry: Dictionary = raw
		var center: Vector2 = entry["center"]
		var guess := Vector2i(roundi(center.x), roundi(center.y))
		if _row(entry, guess).size() > 0:
			continue
		var visibility := VisibilityModel.new()
		visibility.setup(model, owner)
		visibility.lower_to(
			model.index_of(guess.x, guess.y), VisibilityModel.Level.UNKNOWN
		)
		var survey: Dictionary = ResourceSurvey.snapshot(
			model, LandWorks.new(), [], owner, visibility
		)
		var moved: Dictionary = _entry(survey, int(entry["id"]))
		assert_false(moved.is_empty())
		var anchor: Vector2 = moved["anchor"]
		var anchor_tile := Vector2i(roundi(anchor.x), roundi(anchor.y))
		assert_ne(anchor_tile, guess)
		assert_ne(
			visibility.level_at(anchor_tile.x, anchor_tile.y),
			VisibilityModel.Level.UNKNOWN
		)
		return
	assert_true(false, "fixture needs a province whose centre is not a resource tile")


func test_prospect_gate_marks_an_owned_mineral() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = _owned_mineral_tile(model, works)
	if tile.x < 0:
		return
	var survey: Dictionary = ResourceSurvey.snapshot(model, works, [], owner, null, tile)
	var row: Dictionary = _row(_entry(survey, model.province_at(tile.x, tile.y)), tile)
	assert_eq(String(row["status"]), "unprospected")
	assert_true(bool(row["needs_prospecting"]))


# --- helpers -----------------------------------------------------------------


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func _row(entry: Dictionary, tile: Vector2i) -> Dictionary:
	if entry.is_empty():
		return {}
	for raw: Variant in entry["rows"]:
		var row: Dictionary = raw
		if row["tile"] == tile:
			return row
	return {}


func _foreign_resource_tile(model: MapModel) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner == FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if model.resource_at(tile.x, tile.y) >= 0:
				return tile
	return Vector2i(-1, -1)


func _owned_mineral_tile(model: MapModel, works: LandWorks) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			var resource: int = model.resource_at(tile.x, tile.y)
			if resource < 0 or not ImprovementCatalog.needs_prospecting(resource):
				continue
			if works.improvement_at(model, tile) > 0:
				continue
			return tile
	return Vector2i(-1, -1)
