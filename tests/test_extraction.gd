extends GdToolsTest
## Extraction phase (wiki: extraction-and-improvements).


func test_effective_yield_takes_the_minimum() -> void:
	assert_eq(Extraction.effective_yield(4, 4, 4, 4), 4)
	assert_eq(Extraction.effective_yield(4, 1, 4, 4), 1)
	assert_eq(Extraction.effective_yield(2, 4, 1, 4), 1)
	assert_eq(Extraction.effective_yield(3, 4, 4, 2), 2)
	assert_eq(Extraction.effective_yield(0, 4, 4, 4), 0)
	assert_eq(Extraction.effective_yield(9, 4, 4, 4), 4)
	assert_eq(Extraction.effective_yield(-3, 4, 4, 4), 0)


func test_tech_cap_defaults_to_one() -> void:
	assert_eq(Extraction.tech_cap_for("timber", {}), 1)
	assert_eq(Extraction.tech_cap_for("timber", {"timber": 3}), 3)
	assert_eq(Extraction.tech_cap_for("timber", {"timber": -1}), 0)


func test_map_resources_map_to_catalog_commodities() -> void:
	assert_eq(Extraction.commodity_for_resource(0), "timber")
	assert_eq(Extraction.commodity_for_resource(3), "gold")
	assert_eq(Extraction.commodity_for_resource(4), "grain")
	assert_eq(Extraction.commodity_for_resource(MapModel.NO_ID), "")


func test_seeded_map_resources_are_real_commodities() -> void:
	var table: Array[Dictionary] = MapGenerator.resource_table()
	for entry: Dictionary in table:
		assert_true(
			CommodityCatalog.known(String(entry["commodity"])), String(entry["commodity"])
		)


func test_yields_sum_owned_resource_tiles_and_the_capital_bonus() -> void:
	var model: MapModel = _fixture()
	var totals: Dictionary = Extraction.yields(model, 0, 0)
	assert_eq(totals, {"timber": 1, "grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})


func test_yields_ignore_tiles_owned_by_others() -> void:
	var model: MapModel = _fixture()
	var totals: Dictionary = Extraction.yields(model, 1, 1)
	assert_eq(totals, {"grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})
	var none: Dictionary = Extraction.yields(model, 2, -1)
	assert_eq(none, {})


func test_capital_bonus_needs_an_owned_capital() -> void:
	var model: MapModel = _fixture()
	var foreign: Dictionary = Extraction.yields(model, 0, 1)
	assert_eq(int(foreign.get("grain", 0)), 1)
	assert_eq(Extraction.yields(null, 0, 0), {})


func test_improved_tiles_use_the_works_level_and_connectivity() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 1)
	var totals: Dictionary = Extraction.yields(model, 0, 0, {}, works, Vector2i(0, 0))
	assert_eq(totals, {"timber": 1, "grain": Extraction.CAPITAL_GRAIN_BONUS})
	# The unimproved grain tile on (1, 0) no longer pays the placeholder level 1.
	var no_works: Dictionary = Extraction.yields(model, 0, 0)
	assert_eq(no_works, {"timber": 1, "grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})


func test_disconnected_improvements_are_skipped() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 1)
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(-1, -1)
	)
	assert_eq(totals, {})


func test_works_respect_prospecting_and_extraction_caps() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 2)
	works.set_transport(model, Vector2i(0, 0), LandWorks.TRANSPORT_RAIL)
	var base: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(base, {"timber": 1})
	var capped: Dictionary = Extraction.yields(
		model, 0, -1, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(capped, {"timber": 2})

	model.resource[model.index_of(0, 0)] = 1
	works.set_improvement(model, Vector2i(0, 0), 1)
	var unprospected: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(unprospected, {})
	works.set_prospected(0, model, Vector2i(0, 0))
	var prospected: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(prospected, {"iron": 1})


func test_tech_caps_lift_the_yield_per_tile() -> void:
	var model: MapModel = MapModel.new()
	model.setup(3, 1)
	model.province[model.index_of(0, 0)] = 0
	model.province[model.index_of(1, 0)] = 0
	model.provinces.append({
		"id": 0,
		"owner": 0,
		"tiles": [Vector2i(0, 0), Vector2i(1, 0)],
		"town_development": 4,
	})
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(1, 0)] = 0
	var base: Dictionary = Extraction.yields(model, 0, -1)
	assert_eq(base, {"timber": 2})
	var capped: Dictionary = Extraction.yields(model, 0, -1, {"timber": 3})
	# Improvement level, not the tech cap, now limits the tiles in this slice.
	assert_eq(capped, {"timber": 2})


func _fixture() -> MapModel:
	var model: MapModel = MapModel.new()
	model.setup(3, 2)
	for x in 2:
		model.province[model.index_of(x, 0)] = 0
	model.province[model.index_of(2, 0)] = 1
	model.province[model.index_of(0, 1)] = 1
	model.provinces.append({
		"id": 0,
		"owner": 0,
		"tiles": [Vector2i(0, 0), Vector2i(1, 0)],
		"town_development": 4,
	})
	model.provinces.append({
		"id": 1,
		"owner": 1,
		"tiles": [Vector2i(2, 0), Vector2i(0, 1)],
		"town_development": 0,
	})
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(1, 0)] = 4
	model.resource[model.index_of(2, 0)] = 4
	return model
