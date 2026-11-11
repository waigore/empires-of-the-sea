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
	assert_eq(int(entry["counts"]["developed"]), 1)
	assert_eq(int(entry["counts"]["linked"]), 1)
	assert_gt(int(entry["counts"]["producing"]), 0)
	assert_false((entry["output"] as Dictionary).is_empty())
	assert_true(String(entry["summary"]).contains("linked to the crown"))


func test_the_plate_counts_developed_estates_apart_from_linked_ones() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = Fixture.owned_resource_tile(model, works)
	works.set_improvement(model, tile, 1)
	works.set_prospected(owner, model, tile)
	var province: int = model.province_at(tile.x, tile.y)
	var linked: Dictionary = _entry(
		ResourceSurvey.snapshot(model, works, [], owner, null, tile, {}), province
	)
	var cut: Dictionary = _entry(
		ResourceSurvey.snapshot(
			model, works, [], owner, null, Vector2i(-1, -1), {}
		),
		province
	)
	assert_eq(int(cut["counts"]["developed"]), int(linked["counts"]["developed"]))
	assert_eq(int(cut["counts"]["linked"]), 0, "no capital, no crown link")
	assert_gt(int(linked["counts"]["linked"]), 0)


func test_roads_are_projected_as_segments_tagged_linked_or_cut() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var pair: Array[Vector2i] = _owned_pair(model)
	assert_eq(pair.size(), 2, "fixture needs two neighbouring owned tiles")
	works.set_transport(model, pair[0], LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, pair[1], LandWorks.TRANSPORT_RAIL)
	var routes: Dictionary = ResourceRoutes.snapshot(model, works, owner, pair[0])
	var segments: Array = routes["segments"]
	assert_eq(segments.size(), 1, "one pair, one segment")
	var segment: Dictionary = segments[0]
	assert_true(bool(segment["linked"]), "both ends reach the seat")
	assert_true(bool(segment["rail"]), "the higher level carries the stroke")
	assert_eq(int(routes["counts"]["linked"]), 1)
	# No capital means no crown network: the same road draws as cut ink.
	routes = ResourceRoutes.snapshot(model, works, owner, Vector2i(-1, -1))
	segment = (routes["segments"] as Array)[0]
	assert_false(bool(segment["linked"]))
	assert_eq(int(routes["counts"]["linked"]), 0)
	# Unknown ground never draws a road.
	var visibility := VisibilityModel.new()
	visibility.setup(model, owner)
	visibility.lower_to(
		model.index_of(pair[1].x, pair[1].y), VisibilityModel.Level.UNKNOWN
	)
	routes = ResourceRoutes.snapshot(model, works, owner, pair[0], visibility)
	assert_true((routes["segments"] as Array).is_empty())
	# Fogged ground still projects the stroke, tagged for fainter ink.
	visibility.setup(model, owner)
	visibility.lower_to(
		model.index_of(pair[1].x, pair[1].y), VisibilityModel.Level.FOGGED
	)
	routes = ResourceRoutes.snapshot(model, works, owner, pair[0], visibility)
	assert_eq((routes["segments"] as Array).size(), 1)
	assert_true(bool((routes["segments"] as Array)[0]["fogged"]))
	# Guard: empty chart and a bad owner never invent a network.
	routes = ResourceRoutes.snapshot(null, works, owner)
	assert_true((routes["segments"] as Array).is_empty())
	routes = ResourceRoutes.snapshot(model, works, -1)
	assert_true((routes["segments"] as Array).is_empty())


func test_a_coastal_road_does_not_pair_onto_the_sea() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var coast: Vector2i = _owned_coast_toward_sea(model)
	assert_true(coast.x >= 0, "fixture needs an owned land tile facing the sea")
	works.set_transport(model, coast, LandWorks.TRANSPORT_ROAD)
	var routes: Dictionary = ResourceRoutes.snapshot(model, works, owner, coast)
	assert_eq(int(routes["counts"]["road"]), 0, "sea never completes a road pair")


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


func test_a_hidden_mineral_is_never_surveyed_until_prospected() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var tile: Vector2i = _owned_mineral_tile(model, works)
	if tile.x < 0:
		return
	var province: int = model.province_at(tile.x, tile.y)
	var survey: Dictionary = ResourceSurvey.snapshot(model, works, [], owner, null, tile)
	assert_true(_row(_entry(survey, province), tile).is_empty(),
		"an unsurveyed mineral has no survey row")
	assert_gt(
		MineralSurvey.unsurveyed_in_province(model, works, owner, province, null).size(),
		0, "the province still has ground to read"
	)
	# Once the crown prospects the tile the estate appears, unchanged by fog.
	works.set_prospected(owner, model, tile)
	survey = ResourceSurvey.snapshot(model, works, [], owner, null, tile)
	var row: Dictionary = _row(_entry(survey, province), tile)
	assert_false(row.is_empty(), "the survey now names the deposit")
	assert_true(bool(row["needs_prospecting"]))
	assert_true(bool(row["prospected"]))
	assert_eq(String(row["status"]), "vacant")


func test_the_dossier_reads_one_province_with_the_survey_vocabulary() -> void:
	var model: MapModel = Fixture.region()
	var works := LandWorks.new()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: ProvinceState = model.provinces[0]
	var rows: Array[Dictionary] = ResourceSurvey.province_rows(
		model, works, [], owner, province.id
	)
	var entry: Dictionary = _entry(
		ResourceSurvey.snapshot(model, works, [], owner), province.id
	)
	assert_eq(rows.size(), (entry["rows"] as Array).size(), "same estates as the lens")
	var surveyed: Array[Vector2i] = []
	for raw: Variant in entry["rows"]:
		surveyed.append((raw as Dictionary)["tile"])
	for row: Dictionary in rows:
		assert_true(province.tiles.has(row["tile"]), "only this province's tiles")
		assert_true(surveyed.has(row["tile"]), "the same tiles the lens draws")


func test_the_dossier_hides_estates_the_crown_has_not_charted() -> void:
	var model: MapModel = Fixture.region()
	var owner: int = FactionCatalog.PLAYER_FACTION
	var province: ProvinceState = model.provinces[0]
	var visibility := VisibilityModel.new()
	visibility.setup(model, owner)
	for tile: Vector2i in province.tiles:
		visibility.lower_to(
			model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var rows: Array[Dictionary] = ResourceSurvey.province_rows(
		model, LandWorks.new(), [], owner, province.id, visibility
	)
	assert_true(rows.is_empty(), "unknown ground is never surveyed")


# --- yield readings match the Extraction phase -------------------------------


## One lane of owned land: a capital province west, a province east whose town
## sits south of the road, and one timber estate on the road at x=4.
func _lane(terrain: int, town_level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(6, 2)
	var groups: Dictionary = {0: [], 1: []}
	for y in 2:
		for x in 6:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			var province_id: int = 0 if x < 3 else 1
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	var provinces: Array[ProvinceState] = []
	for province_id in 2:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		provinces.append(ProvinceState.create(
			province_id, "P%d" % province_id, tiles, Vector2(2.0, 0.5),
			tiles.size(), FactionCatalog.PLAYER_FACTION, province_id == 0
		))
	provinces[0].capital_tile = Vector2i(0, 0)
	provinces[0].town_tile = Vector2i(0, 0)
	provinces[0].town_development = 4
	provinces[1].town_tile = Vector2i(3, 1)
	provinces[1].town_development = town_level
	model.provinces = provinces
	model.terrain[model.index_of(4, 0)] = terrain
	model.resource[model.index_of(4, 0)] = 0
	return model


## The lens row's yield and the Extraction phase's timber total for the estate.
func _read(model: MapModel, works: LandWorks) -> Dictionary:
	var owner: int = FactionCatalog.PLAYER_FACTION
	var entry: Dictionary = _entry(
		ResourceSurvey.snapshot(
			model, works, [], owner, null, Vector2i(0, 0), {"timber": 4}
		),
		1
	)
	var output: int = -1
	for row: Dictionary in entry["rows"]:
		if row["tile"] == Vector2i(4, 0):
			output = int(row["output"])
	var totals: Dictionary = Extraction.yields(
		model, owner, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	return {"lens": output, "phase": int(totals.get("timber", 0))}


## A non-capital estate on a rail path to the crown is not town-capped: town
## development limits only the Town-rule link (wiki: extraction-and-improvements
## § Extraction formula and town development cap).
func test_a_road_estate_is_not_priced_at_its_town_level() -> void:
	var model: MapModel = _lane(MapModel.Terrain.HARDWOOD_FOREST, 1)
	var works := LandWorks.new()
	for x in 6:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Vector2i(4, 0), 4)
	var read: Dictionary = _read(model, works)
	assert_eq(int(read["phase"]), 4, "a rail path to the crown pays in full")
	assert_eq(int(read["lens"]), 4, "the lens prices what the phase pays")


## The cap is the path's bottleneck, not the estate's own road level.
func test_a_bottleneck_behind_the_estate_caps_the_lens_reading() -> void:
	var model: MapModel = _lane(MapModel.Terrain.HARDWOOD_FOREST, 4)
	var works := LandWorks.new()
	for x in 6:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, Vector2i(4, 0), LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Vector2i(4, 0), 4)
	var read: Dictionary = _read(model, works)
	assert_eq(int(read["phase"]), 1, "the road west of the estate is the bottleneck")
	assert_eq(int(read["lens"]), 1, "the lens reads the path, not the tile")


## Scrub forest hard-caps timber at 1 after the tech cap; the map reading must
## consult it too (wiki: extraction-and-improvements § Terrain extraction hard
## caps — "the map-view builder action state").
func test_scrub_timber_is_read_at_its_terrain_cap() -> void:
	var model: MapModel = _lane(MapModel.Terrain.SCRUB_FOREST, 4)
	var works := LandWorks.new()
	for x in 6:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Vector2i(4, 0), 4)
	var read: Dictionary = _read(model, works)
	assert_eq(int(read["phase"]), 1, "scrub forest caps timber at level 1")
	assert_eq(int(read["lens"]), 1, "the lens cannot promise a yield the phase refuses")


# --- helpers -----------------------------------------------------------------


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


## Two 4-adjacent land tiles the crown owns, for the road projection fixture.
func _owned_pair(model: MapModel) -> Array[Vector2i]:
	var pair: Array[Vector2i] = []
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next: Vector2i = tile + step
				if model.owner_at(next.x, next.y) != province.owner:
					continue
				pair.append(tile)
				pair.append(next)
				return pair
	return pair


## An owned land tile whose right or down neighbour is water (or off-chart), so
## the road walker hits the land/bounds guard without inventing a segment.
func _owned_coast_toward_sea(model: MapModel) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next: Vector2i = tile + step
				if not model.in_bounds(next.x, next.y) or not model.is_land(next.x, next.y):
					return tile
	return Vector2i(-1, -1)


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
