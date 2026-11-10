extends GdToolsTest
## Purchased land pays its owner (wiki: world-market § Touch points with
## purchased tiles; DR-20261110-09): a deed yields its harvest into the
## treasury, never the stockpile, and its seller publishes no row.

## Two provinces: a crown capital province and a Minor's timber province.
func _fixture() -> MapModel:
	var model: MapModel = MapModel.new()
	model.setup(4, 2)
	model.terrain.fill(MapModel.Terrain.PLAINS)
	for x in 3:
		model.province[model.index_of(x, 0)] = 0
	for x in 2:
		model.province[model.index_of(x, 1)] = 1
	var tiles0: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var tiles1: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
	var mine := ProvinceState.create(0, "Mine", tiles0, Vector2.ZERO, 2,
		FactionCatalog.PLAYER_FACTION)
	var theirs := ProvinceState.create(1, "Timberland", tiles1, Vector2.ZERO, 2,
		FactionCatalog.minor_ids()[0])
	model.provinces.append(mine)
	model.provinces.append(theirs)
	# Resource 0 is Timber (MapCatalog.resource_table).
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(0, 1)] = 0
	return model


func _world(model: MapModel) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(model)
	return world


func test_a_deed_pays_the_purse_not_the_stockpile() -> void:
	var model: MapModel = _fixture()
	assert_true(model.purchase_tile(Vector2i(0, 1), FactionCatalog.PLAYER_FACTION))
	var report: Dictionary = DeedIncome.income(
		_world(model), WorldMap.OLD_WORLD, FactionCatalog.PLAYER_FACTION
	)
	assert_eq(report["units"], {"timber": 1})
	# One ton of timber at its catalog price (30).
	assert_eq(int(report["treasury"]), CommodityCatalog.base_price("timber"))
	assert_eq((report["tiles"] as Array).size(), 1)


func test_a_deed_leaves_the_extraction_totals() -> void:
	var model: MapModel = _fixture()
	# A town province caps an off-town estate, so the crown's own timber is the
	# baseline; buying the Minor's tile moves exactly one ton out of the yield.
	var raw: Dictionary = Extraction.yields(model, FactionCatalog.PLAYER_FACTION, 0)
	var own_timber: int = int(raw.get("timber", 0))
	assert_true(model.purchase_tile(Vector2i(0, 1), FactionCatalog.PLAYER_FACTION))
	var deed: Dictionary = DeedIncome.income(
		_world(model), WorldMap.OLD_WORLD, FactionCatalog.PLAYER_FACTION
	)
	var kept: Dictionary = DeedIncome.without_deeds(raw, deed["units"] as Dictionary)
	# Only the deed's tile leaves the totals; the crown's own timber stays.
	assert_eq(int(kept.get("timber", 0)), own_timber - 1)
	assert_eq(int(kept.get("grain", 0)), int(raw.get("grain", 0)))
	assert_false(DeedIncome.without_deeds({"timber": 1}, {"timber": 1}).has("timber"))


func test_settle_credits_the_treasury_once() -> void:
	var model: MapModel = _fixture()
	assert_true(model.purchase_tile(Vector2i(0, 1), FactionCatalog.PLAYER_FACTION))
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var before: int = economy.treasury
	var report: Dictionary = DeedIncome.income(
		_world(model), WorldMap.OLD_WORLD, FactionCatalog.PLAYER_FACTION
	)
	report.erase("model")
	var settled: Dictionary = DeedIncome.settle(report, economy)
	assert_eq(economy.treasury, before + int(settled["treasury"]))
	assert_eq(String(settled["line"]), "+%d from deeds" % int(settled["treasury"]))
	assert_eq(economy.quantity("timber"), 0, "deed yield is cash, not stock")


func test_no_deed_means_no_income_and_empty_guards() -> void:
	var model: MapModel = _fixture()
	var report: Dictionary = DeedIncome.income(
		_world(model), WorldMap.OLD_WORLD, FactionCatalog.PLAYER_FACTION
	)
	assert_eq(int(report["treasury"]), 0)
	assert_eq((report["tiles"] as Array).size(), 0)
	var empty: Dictionary = DeedIncome.income(null, WorldMap.OLD_WORLD, 0)
	assert_eq(int(empty["treasury"]), 0)
	assert_eq(DeedIncome.without_deeds({"timber": 2}, {"grain": 1}), {"timber": 2})


func test_a_deed_waits_for_its_estate() -> void:
	var model: MapModel = _fixture()
	assert_true(model.purchase_tile(Vector2i(0, 1), FactionCatalog.PLAYER_FACTION))
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 1), 0)
	var wild: Dictionary = DeedIncome.income(
		_world(model), WorldMap.OLD_WORLD, FactionCatalog.PLAYER_FACTION, works
	)
	assert_eq(int(wild["treasury"]), 0, "undeveloped ground grows nothing")
	works.set_improvement(model, Vector2i(0, 1), 3)
	var raised: Dictionary = DeedIncome.income(
		_world(model), WorldMap.OLD_WORLD, FactionCatalog.PLAYER_FACTION, works
	)
	# Minor land never develops past level 1, however the tile was improved.
	assert_eq(raised["units"], {"timber": 1})


func test_guards_name_what_a_deed_cannot_pay() -> void:
	var model: MapModel = _fixture()
	var tile := Vector2i(0, 1)
	assert_true(DeedIncome.tile_yield(null, tile).is_empty())
	assert_true(DeedIncome.tile_yield(model, Vector2i(99, 99)).is_empty())
	# A tile with no resource at all.
	assert_true(DeedIncome.tile_yield(model, Vector2i(2, 0)).is_empty())
	# A rich never trades, so a deed on one pays nothing.
	var rich := Vector2i(1, 1)
	model.resource[model.index_of(rich.x, rich.y)] = 3
	assert_true(DeedIncome.tile_yield(model, rich).is_empty())
	# An off-map town lookup falls back to the garden cap.
	assert_eq(DeedIncome.province_town_cap(model, Vector2i(99, 99)), Extraction.MAX_YIELD)
	# A settle with no credit and no purse still reports an empty line.
	var poor: Dictionary = DeedIncome.settle({"units": {}, "treasury": 0}, null)
	assert_eq(String(poor["line"]), "")
	assert_eq(int(poor["treasury"]), 0)


func test_deeds_follow_the_owner() -> void:
	var model: MapModel = _fixture()
	assert_true(model.purchase_tile(Vector2i(0, 1), FactionCatalog.PLAYER_FACTION))
	var rival: Dictionary = DeedIncome.income(_world(model), WorldMap.OLD_WORLD, 1)
	assert_eq(int(rival["treasury"]), 0)
	assert_true(DeedIncome.tiles(model, 1).is_empty())
	assert_eq(DeedIncome.tiles(model, FactionCatalog.PLAYER_FACTION).size(), 1)
	assert_eq(DeedIncome.tiles(null, 0), [] as Array[Vector2i])