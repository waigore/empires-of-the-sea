extends GdToolsTest
## Setup post-pass: capital works and guaranteed grain reach extraction
## (wiki: capital-and-connectivity § Init town roads,
## tile-map-and-generation § Great Power starting grain).

const SEED: int = 1500

var _model: MapModel = null
var _works: LandWorks = null


func before_each() -> void:
	_model = MapGenerator.new().generate_region(SEED, FactionCatalog.OLD_WORLD, 96, 64)
	_works = LandWorks.new()
	WorldBootstrap.apply(_model, _works)


func test_every_great_power_gets_four_grain_farms() -> void:
	for faction: int in FactionCatalog.great_power_ids():
		var province: int = WorldBootstrap.capital_province(_model, faction)
		assert_gt(province, -1, "GP %d has a capital province" % faction)
		var capital: Vector2i = _model.capital_tile_of(province)
		var farms: int = 0
		for tile: Vector2i in _model.province_tiles(province):
			if tile == capital:
				continue
			if _model.resource_at(tile.x, tile.y) != WorldBootstrap.GRAIN_RESOURCE:
				continue
			if _works.improvement_at(_model, tile) != WorldBootstrap.FARM_LEVEL:
				continue
			farms += 1
		assert_eq(farms, WorldBootstrap.GRAIN_FARMS, "GP %d has four grain farms" % faction)


func test_bootstrap_farms_reach_the_crown() -> void:
	var province: int = WorldBootstrap.capital_province(
		_model, FactionCatalog.PLAYER_FACTION
	)
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		_model, _works, FactionCatalog.PLAYER_FACTION, _model.capital_tile_of(province)
	)
	var farms: int = 0
	for tile: Vector2i in _model.province_tiles(province):
		if _works.improvement_at(_model, tile) != WorldBootstrap.FARM_LEVEL:
			continue
		assert_true(
			connected.has(_model.index_of(tile.x, tile.y)),
			"bootstrap farm at %s is connected" % tile
		)
		farms += 1
	assert_eq(farms, WorldBootstrap.GRAIN_FARMS)


func test_the_capital_province_feeds_the_opening_crown() -> void:
	var province: int = WorldBootstrap.capital_province(
		_model, FactionCatalog.PLAYER_FACTION
	)
	var yields: Dictionary = Extraction.yields(
		_model, FactionCatalog.PLAYER_FACTION, province, {}, _works,
		_model.capital_tile_of(province)
	)
	assert_gte(int(yields.get("grain", 0)), 4 + Extraction.CAPITAL_GRAIN_BONUS)


func test_capital_ports_and_harbour_roads_are_real() -> void:
	assert_gt(_works.ports.size(), 0, "capital ports are seeded")
	assert_gt(_works.transport.size(), 0, "harbour roads are seeded")
	for province: ProvinceState in _model.provinces:
		if not province.capital:
			continue
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		assert_eq(
			province.town_development, WorldBootstrap.CAPITAL_TOWN_DEVELOPMENT
		)


func test_the_post_pass_is_deterministic() -> void:
	var second: MapModel = MapGenerator.new().generate_region(
		SEED, FactionCatalog.OLD_WORLD, 96, 64
	)
	var works := LandWorks.new()
	WorldBootstrap.apply(second, works)
	assert_eq(second.resource, _model.resource)
	assert_eq(works.improvement, _works.improvement)
	assert_eq(works.transport, _works.transport)
	assert_eq(works.ports, _works.ports)


func test_the_new_world_gets_no_great_power_farms() -> void:
	var model: MapModel = MapGenerator.new().generate_region(
		SEED + 7919, FactionCatalog.NEW_WORLD, 84, 58
	)
	var works := LandWorks.new()
	var report: Dictionary = WorldBootstrap.apply(model, works)
	assert_eq(int(report["farms"]), 0)
	assert_true(works.improvement.is_empty())
