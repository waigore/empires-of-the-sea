extends GdToolsTest
## Setup post-pass: capital works and guaranteed grain reach extraction
## (wiki: capital-and-connectivity § Init town roads,
## tile-map-and-generation § Great Power starting grain).

const Fixture = preload("res://tests/map_fixture.gd")

## The post-pass only needs a region big enough for every Great Power capital;
## the small shared region keeps generation (this suite's dominant cost under
## coverage) to a fraction of the old 96x64 map.
const SEED: int = Fixture.SEED
const WIDTH: int = Fixture.WIDTH
const HEIGHT: int = Fixture.HEIGHT
const NEW_WORLD_WIDTH: int = Fixture.WIDTH
const NEW_WORLD_HEIGHT: int = Fixture.HEIGHT

## Non-underscore so before_all state is copied onto each test instance. The
## post-pass is read-only in every case below, so one region per worker keeps
## world generation (the suite's dominant cost under coverage) off the hot path.
var model: MapModel = null
var works: LandWorks = null
var report: Dictionary = {}


func before_all() -> void:
	model = MapGenerator.new().generate_region(SEED, FactionCatalog.OLD_WORLD, WIDTH, HEIGHT)
	works = LandWorks.new()
	report = WorldBootstrap.apply(model, works)


func test_every_great_power_gets_four_grain_farms() -> void:
	for faction: int in FactionCatalog.great_power_ids():
		var province: int = WorldBootstrap.capital_province(model, faction)
		assert_gt(province, -1, "GP %d has a capital province" % faction)
		var capital: Vector2i = model.capital_tile_of(province)
		var farms: int = 0
		for tile: Vector2i in model.province_tiles(province):
			if tile == capital:
				continue
			if model.resource_at(tile.x, tile.y) != WorldBootstrap.GRAIN_RESOURCE:
				continue
			if works.improvement_at(model, tile) != WorldBootstrap.FARM_LEVEL:
				continue
			farms += 1
		assert_eq(farms, WorldBootstrap.GRAIN_FARMS, "GP %d has four grain farms" % faction)


func test_bootstrap_farms_reach_the_crown() -> void:
	var province: int = WorldBootstrap.capital_province(
		model, FactionCatalog.PLAYER_FACTION
	)
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		model, works, FactionCatalog.PLAYER_FACTION, model.capital_tile_of(province)
	)
	var farms: int = 0
	for tile: Vector2i in model.province_tiles(province):
		if works.improvement_at(model, tile) != WorldBootstrap.FARM_LEVEL:
			continue
		assert_true(
			connected.has(model.index_of(tile.x, tile.y)),
			"bootstrap farm at %s is connected" % tile
		)
		farms += 1
	assert_eq(farms, WorldBootstrap.GRAIN_FARMS)


func test_the_capital_province_feeds_the_opening_crown() -> void:
	var province: int = WorldBootstrap.capital_province(
		model, FactionCatalog.PLAYER_FACTION
	)
	var yields: Dictionary = Extraction.yields(
		model, FactionCatalog.PLAYER_FACTION, province, {}, works,
		model.capital_tile_of(province)
	)
	assert_gte(int(yields.get("grain", 0)), 4 + Extraction.CAPITAL_GRAIN_BONUS)


func test_capital_ports_and_harbour_roads_are_real() -> void:
	assert_gt(works.ports.size(), 0, "capital ports are seeded")
	assert_gt(works.transport.size(), 0, "harbour roads are seeded")
	for province: ProvinceState in model.provinces:
		if not province.capital:
			continue
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		assert_eq(
			province.town_development, WorldBootstrap.CAPITAL_TOWN_DEVELOPMENT
		)


## Init town roads (wiki: capital-and-connectivity § Init town roads): every
## owned town reaches its crown on owned land from turn 1, so the Town rule
## anchors extraction instead of waiting on a Builder.
func test_every_owned_town_reaches_the_crown() -> void:
	var checked: int = 0
	for faction: int in FactionCatalog.ids_in_region(FactionCatalog.OLD_WORLD):
		var seat: int = WorldBootstrap.capital_province(model, faction)
		if seat < 0:
			continue
		var connected: Dictionary = ImprovementSystem.connected_tiles(
			model, works, faction, model.capital_tile_of(seat)
		)
		for province: ProvinceState in model.provinces:
			if province.owner != faction or province.capital:
				continue
			var town: Vector2i = province.town_tile
			assert_true(town.x >= 0, "%s has no town" % province.name)
			assert_true(
				connected.has(model.index_of(town.x, town.y)),
				"%s of %s does not reach its capital"
				% [province.name, FactionCatalog.name_of(faction)]
			)
			checked += 1
	assert_gt(checked, 0)


func test_town_roads_are_wired_and_counted() -> void:
	assert_gt(int(report["town_roads"]), 0, "the post-pass lays town roads")
	for province: ProvinceState in model.provinces:
		for path: Array in province.road_paths:
			assert_true(path.size() >= 2, "a road path joins two tiles")


func test_the_post_pass_is_deterministic() -> void:
	var second: MapModel = MapGenerator.new().generate_region(
		SEED, FactionCatalog.OLD_WORLD, WIDTH, HEIGHT
	)
	var second_works := LandWorks.new()
	WorldBootstrap.apply(second, second_works)
	assert_eq(second.resource, model.resource)
	assert_eq(second_works.improvement, works.improvement)
	assert_eq(second_works.transport, works.transport)
	assert_eq(second_works.ports, works.ports)


func test_the_new_world_gets_no_great_power_farms() -> void:
	var new_world: MapModel = MapGenerator.new().generate_region(
		SEED + 7919, FactionCatalog.NEW_WORLD, NEW_WORLD_WIDTH, NEW_WORLD_HEIGHT
	)
	var new_world_works := LandWorks.new()
	var new_world_report: Dictionary = WorldBootstrap.apply(new_world, new_world_works)
	assert_eq(int(new_world_report["farms"]), 0)
	assert_eq(int(new_world_report["town_roads"]), 0, "the New World is not wired at init")
	assert_true(new_world_works.improvement.is_empty())
