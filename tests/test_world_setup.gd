extends GdToolsTest
## Two-region world setup (wiki: game-setup, map-topology, factions), the setup
## post-pass, generation invariants and the advanced-start presets and estates.
## Old World holds Great Powers + Minor Nations; the New World holds Tribes.
## Merged from test_world_bootstrap, test_map_generator and test_advanced_start.

const Fixture = preload("res://tests/map_fixture.gd")

const SEED: int = Fixture.SEED
const WIDTH: int = Fixture.WORLD_WIDTH
const HEIGHT: int = Fixture.WORLD_HEIGHT

## Non-underscore so before_all state is copied onto each test instance.
var world: WorldMap = null


func before_all() -> void:
	world = Fixture.world()
	_bootstrap_world()
	_advanced_before_all()
	_generator_before_all()


func test_world_has_two_regions_with_clean_setup() -> void:
	assert_eq(world.region_count(), 2)
	assert_eq(world.region(0).region_id, FactionCatalog.OLD_WORLD)
	assert_eq(world.region(1).region_id, FactionCatalog.NEW_WORLD)
	assert_true(world.region(0).setup_errors.is_empty(), "OW: %s" % str(world.region(0).setup_errors))
	assert_true(world.region(1).setup_errors.is_empty(), "NW: %s" % str(world.region(1).setup_errors))
	assert_eq(world.total_provinces(), world.region(0).province_count() + world.region(1).province_count())


## The shared fixture is generated once per suite, so it must pass its fair
## split on the first attempt: a seed that fails makes `generate_world` build a
## second world (wiki: game-setup § Tribe assignment regen-until-pass), and every
## mounted suite pays that second build under coverage.
func test_the_fixture_world_passes_on_its_first_attempt() -> void:
	var first: MapModel = MapGenerator.new().generate_region(
		SEED, FactionCatalog.OLD_WORLD, WIDTH, HEIGHT
	)
	var second: MapModel = MapGenerator.new().generate_region(
		SEED + 7919, FactionCatalog.NEW_WORLD,
		maxi(48, int(round(float(WIDTH) * 0.88))),
		maxi(36, int(round(float(HEIGHT) * 0.9))),
	)
	assert_true(first.setup_errors.is_empty(), "OW first attempt: %s" % str(first.setup_errors))
	assert_true(second.setup_errors.is_empty(), "NW first attempt: %s" % str(second.setup_errors))


func test_regions_host_the_expected_faction_rosters() -> void:
	assert_eq(
		world.factions_in(FactionCatalog.OLD_WORLD),
		FactionCatalog.great_power_ids() + FactionCatalog.minor_ids()
	)
	assert_eq(world.factions_in(FactionCatalog.NEW_WORLD), FactionCatalog.tribe_ids())
	# Great Powers start in the Old World; the New World roster is Tribes only.
	assert_eq(world.great_powers_in(FactionCatalog.NEW_WORLD).size(), 0)


func test_every_faction_owns_provinces_in_its_region_only() -> void:
	for region_index in world.region_count():
		var model: MapModel = world.region(region_index)
		var owners: Dictionary = {}
		for province: ProvinceState in model.provinces:
			var owner: int = province.owner
			assert_true(FactionCatalog.has_faction(owner), "region %d owner %d" % [region_index, owner])
			assert_true(
				FactionCatalog.can_own_region(owner, region_index),
				"%s cannot own provinces in region %d"
				% [FactionCatalog.name_of(owner), region_index]
			)
			owners[owner] = true
		for faction_id: int in model.faction_ids:
			assert_true(
				owners.has(faction_id),
				"%s owns no province in region %d"
				% [FactionCatalog.name_of(faction_id), region_index]
			)


func test_each_faction_holds_one_contiguous_territory() -> void:
	for region_index in world.region_count():
		var model: MapModel = world.region(region_index)
		for faction_id: int in model.faction_ids:
			var owned: Array[int] = []
			for province: ProvinceState in model.provinces:
				if province.owner == faction_id:
					owned.append(province.id)
			assert_true(_is_connected(model, owned), "%s is not contiguous" % FactionCatalog.name_of(faction_id))


func test_great_powers_and_tribes_own_a_sea_bound_province() -> void:
	var old_world: MapModel = world.region(0)
	for faction_id: int in FactionCatalog.great_power_ids():
		assert_true(_owns_sea_bound(old_world, faction_id), "GP %s is landlocked" % FactionCatalog.name_of(faction_id))
	var new_world: MapModel = world.region(1)
	for faction_id: int in FactionCatalog.tribe_ids():
		assert_true(_owns_sea_bound(new_world, faction_id), "Tribe %s is landlocked" % FactionCatalog.name_of(faction_id))


func test_every_faction_gets_exactly_one_capital() -> void:
	for region_index in world.region_count():
		var model: MapModel = world.region(region_index)
		var capitals: Dictionary = {}
		for province: ProvinceState in model.provinces:
			if not province.capital:
				continue
			var owner: int = province.owner
			assert_false(capitals.has(owner), "%s has two capitals" % FactionCatalog.name_of(owner))
			capitals[owner] = province.id
			var tile: Vector2i = province.capital_tile
			assert_true(model.is_land(tile.x, tile.y))
			assert_eq(model.terrain_at(tile.x, tile.y), MapModel.Terrain.PLAINS)
		for faction_id: int in model.faction_ids:
			assert_true(capitals.has(faction_id), "%s has no capital" % FactionCatalog.name_of(faction_id))
			var province_id: int = int(capitals[faction_id])
			if FactionCatalog.type_of(faction_id) == FactionCatalog.Type.GREAT_POWER:
				assert_true(CapitalChoice.is_sea_bound(model, province_id))
			assert_eq(world.capital_province_of(region_index, faction_id), province_id)


func test_seat_is_the_capital_and_falls_back_to_a_holding() -> void:
	var model: MapModel = world.region(FactionCatalog.OLD_WORLD)
	var player: int = FactionCatalog.PLAYER_FACTION
	var seat: int = world.seat_province(FactionCatalog.OLD_WORLD, player)
	assert_eq(seat, world.capital_province_of(FactionCatalog.OLD_WORLD, player))
	var capitals: Array[bool] = []
	for province: ProvinceState in model.provinces:
		capitals.append(province.capital)
		province.capital = false
	var fallback: int = world.seat_province(FactionCatalog.OLD_WORLD, player)
	for index in model.provinces.size():
		model.provinces[index].capital = capitals[index]
	assert_eq(model.province_data(fallback).owner, player)
	assert_eq(world.seat_province(FactionCatalog.OLD_WORLD, 9999), MapModel.NO_ID)

func test_owned_provinces_counts_the_region_only() -> void:
	var player: int = FactionCatalog.PLAYER_FACTION
	var model: MapModel = world.region(FactionCatalog.OLD_WORLD)
	var expected: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner == player:
			expected += 1
	assert_eq(world.owned_provinces(FactionCatalog.OLD_WORLD, player), expected)
	assert_eq(world.owned_provinces(FactionCatalog.OLD_WORLD, 9999), 0)


func test_warp_zones_pair_the_two_maps() -> void:
	assert_true(world.warp_links.size() >= 2)
	for region_index in world.region_count():
		assert_true(world.warp_zones(region_index).size() >= 1)
	for link: Dictionary in world.warp_links:
		var from_region: int = int(link["from_region"])
		var to_region: int = int(link["to_region"])
		assert_ne(from_region, to_region)
		var model: MapModel = world.region(from_region)
		var zone_id: int = int(link["from_zone"])
		assert_true(model.sea_zone_data(zone_id) != null)
		assert_true(_zone_touches_edge(model, zone_id))
		assert_eq(
			int(world.warp_partner(from_region, zone_id)["to_region"]), to_region
		)


func test_same_seed_reproduces_the_world() -> void:
	var other: WorldMap = MapGenerator.new().generate_world(SEED, WIDTH, HEIGHT)
	for region_index in world.region_count():
		var first: MapModel = world.region(region_index)
		var second: MapModel = other.region(region_index)
		assert_eq(first.terrain, second.terrain)
		assert_eq(first.province, second.province)
		var first_owners: Array[int] = []
		var second_owners: Array[int] = []
		for province: ProvinceState in first.provinces:
			first_owners.append(province.owner)
		for province: ProvinceState in second.provinces:
			second_owners.append(province.owner)
		assert_eq(first_owners, second_owners)


func test_the_map_seats_the_published_roster() -> void:
	# wiki: naming § default ruleset (6 GPs, 6 minors, 10 tribes) and
	# advanced-starts § locked full-init profile (60 OW / 30 NW provinces).
	assert_eq(world.region(FactionCatalog.OLD_WORLD).provinces.size(), 60)
	assert_eq(world.region(FactionCatalog.NEW_WORLD).provinces.size(), 30)
	assert_eq(FactionCatalog.minor_ids().size(), 6)
	var old_world: MapModel = world.region(FactionCatalog.OLD_WORLD)
	for faction_id: int in FactionCatalog.minor_ids():
		assert_gte(
			_count_owned(old_world, faction_id),
			TerritoryAssignment.MINOR_PROVINCES,
			"%s holds the minimum provinces" % FactionCatalog.name_of(faction_id)
		)
	_assert_even_share(old_world, FactionCatalog.great_power_ids(), "Old World Great Power")
	# Minor Nations share their reservation evenly too, and a cove one of them
	# seals must not carry it past the band (wiki: game-setup § Minor Nation
	# assignment — "within ±1").
	_assert_even_share(old_world, FactionCatalog.minor_ids(), "Old World Minor Nation")
	var new_world: MapModel = world.region(FactionCatalog.NEW_WORLD)
	_assert_even_share(new_world, FactionCatalog.tribe_ids(), "New World Tribe")


## A Great Power seated in a pocket used to start with a third of a rival's land
## (wiki: game-setup § GP assignment — "fair split"). Seed 4 was such a chart.
func test_a_pocket_never_cripples_a_great_power() -> void:
	var chart: WorldMap = MapGenerator.new().generate_world(
		4, Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT
	)
	var old_world: MapModel = chart.region(FactionCatalog.OLD_WORLD)
	assert_true(old_world.setup_errors.is_empty(), str(old_world.setup_errors))
	_assert_even_share(old_world, FactionCatalog.great_power_ids(), "Old World Great Power")


## A cove a Minor Nation seals is handed to that court, and seed 9 used to leave
## Genoa holding five against a 3.33 even share because nothing trimmed it back
## (wiki: game-setup § Minor Nation assignment — "within ±1"; § Feasibility).
func test_a_sealed_cove_never_leaves_a_minor_oversized() -> void:
	var chart: WorldMap = MapGenerator.new().generate_world(
		9, Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT
	)
	var old_world: MapModel = chart.region(FactionCatalog.OLD_WORLD)
	assert_true(old_world.setup_errors.is_empty(), str(old_world.setup_errors))
	_assert_even_share(old_world, FactionCatalog.minor_ids(), "Old World Minor Nation")


## A court above the band hands back a province that already borders the
## Great-Power pool (wiki: game-setup § Minor Nation assignment — "within ±1").
func test_a_minor_over_the_band_hands_back_a_border_province() -> void:
	# One-tile provinces, row-major: 10 holds four, 11 one, and tile 5 is pool.
	var model: MapModel = _grid_model(3, 2, [10, 10, 10, 10, 11, MapModel.NO_ID])
	var pool: Array = [5]
	var grown: Array = MinorShare.trim(model, pool, _grid_ids(model), [10, 11])
	assert_eq(_count_owned(model, 10), 3, "the court lands back inside the band")
	assert_eq(_count_owned(model, 11), 1, "the other court keeps its share")
	assert_true(grown.has(2), "the vacated province returns to the Great-Power pool")
	assert_eq(model.province_data(2).owner, MapModel.NO_ID, "and has no owner")


## A court whose only pool-facing province holds its holding together keeps its
## land rather than split itself (wiki: game-setup § Minor Nation assignment).
func test_a_minor_never_splits_its_own_holding_to_land_back() -> void:
	# 10 owns tiles 0-2; only tile 1 reaches the pool (tile 5) and taking it
	# would cut tile 0 off from tile 2, so the court keeps all three.
	var model: MapModel = _grid_model(4, 2, [
		10, 10, 10, 11,
		12, MapModel.NO_ID, 13, 13,
	])
	var pool: Array = [5]
	var grown: Array = MinorShare.trim(model, pool, _grid_ids(model), [10, 11, 12, 13])
	assert_eq(_count_owned(model, 10), 3, "a cut province is never handed away")
	assert_eq(grown, pool, "the pool does not grow")


## A Tribe left without a sea-bound province fails with the wiki's own code, so
## the regen-until-pass path and a reader of the failure can tell a Tribe's
## missing landfall from a Great Power's (wiki: game-setup § Tribe assignment,
## § Acceptance Criteria — `tribe_missing_sea_bound_province`).
func test_a_tribe_without_a_landfall_names_its_own_code() -> void:
	# An all-land chart: no province touches a sea zone, so no seed is sea-bound.
	var model: MapModel = _grid_model(2, 1, [MapModel.NO_ID, MapModel.NO_ID])
	var tribes: Array[int] = [
		FactionCatalog.tribe_ids()[0], FactionCatalog.tribe_ids()[1],
	]
	var result: Dictionary = TerritoryAssignment.assign_new_world(model, tribes)
	assert_false(bool(result["ok"]))
	assert_eq(String(result["error"]), "tribe_missing_sea_bound_province")


## The Old World keeps its own code for the same failure, so the two regions'
## failures stay distinguishable.
func test_a_great_power_without_a_landfall_keeps_the_old_world_code() -> void:
	var model: MapModel = _grid_model(2, 1, [MapModel.NO_ID, MapModel.NO_ID])
	var greats: Array[int] = [
		FactionCatalog.great_power_ids()[0], FactionCatalog.great_power_ids()[1],
	]
	var result: Dictionary = TerritoryAssignment.assign_old_world(
		model, greats, [] as Array[int]
	)
	assert_false(bool(result["ok"]))
	assert_eq(String(result["error"]), TerritoryAssignment.ERROR_NO_SEA_BOUND_PROVINCE)


func _grid_model(width: int, height: int, owners: Array) -> MapModel:
	var model := MapModel.new()
	model.setup(width, height)
	var provinces: Array[ProvinceState] = []
	for y in height:
		for x in width:
			var index: int = model.index_of(x, y)
			model.terrain[index] = MapModel.Terrain.PLAINS
			model.province[index] = index
			var tiles: Array[Vector2i] = [Vector2i(x, y)]
			provinces.append(ProvinceState.create(
				index, "P%d" % index, tiles,
				Vector2(x + 0.5, y + 0.5), 1, int(owners[index])
			))
	model.provinces = provinces
	return model


func _grid_ids(model: MapModel) -> Array:
	return range(model.provinces.size())


## Every faction holds at least one province and no count strays more than one
## from the even share (wiki: game-setup § assignment, "within ±1").
func _assert_even_share(model: MapModel, factions: Array[int], label: String) -> void:
	var counts: Array[int] = []
	var total: int = 0
	for faction_id: int in factions:
		var owned: int = _count_owned(model, faction_id)
		counts.append(owned)
		total += owned
	var share: float = float(total) / float(counts.size())
	for index in counts.size():
		assert_true(counts[index] > 0, "%s %d owns land" % [label, factions[index]])
		assert_true(
			absf(float(counts[index]) - share) <= 1.0,
			"%s shares %s near %.2f" % [label, str(counts), share]
		)


func test_every_old_world_province_is_owned() -> void:
	var old_world: MapModel = world.region(FactionCatalog.OLD_WORLD)
	for province: ProvinceState in old_world.provinces:
		assert_ne(province.owner, MapModel.NO_ID, "province %d has an owner" % province.id)


func _count_owned(model: MapModel, faction_id: int) -> int:
	var owned: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner == faction_id:
			owned += 1
	return owned


func _owns_sea_bound(model: MapModel, faction_id: int) -> bool:
	for province: ProvinceState in model.provinces:
		if province.owner != faction_id:
			continue
		if CapitalChoice.is_sea_bound(model, province.id):
			return true
	return false


func _is_connected(model: MapModel, province_ids: Array[int]) -> bool:
	if province_ids.is_empty():
		return false
	var lookup: Dictionary = {}
	for province_id: int in province_ids:
		lookup[province_id] = true
	var visited: Dictionary = {province_ids[0]: true}
	var queue: Array[int] = [province_ids[0]]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if lookup.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return visited.size() == province_ids.size()


func _zone_touches_edge(model: MapModel, zone_id: int) -> bool:
	var zone: SeaZoneState = model.sea_zone_data(zone_id)
	if zone == null:
		return false
	for tile: Vector2i in zone.tiles:
		if tile.x == 0 or tile.y == 0 or tile.x == model.width - 1 or tile.y == model.height - 1:
			return true
	return false

# --- from test_world_bootstrap.gd ---
## Setup post-pass: capital works and guaranteed grain reach extraction.

## Setup post-pass: capital works and guaranteed grain reach extraction
## (wiki: capital-and-connectivity § Init town roads,
## tile-map-and-generation § Great Power starting grain).


## Cases only need one region at a time. 64×48 still seats four grain farms per
## Great Power and a thin capital (the 44×34 fixture world does not); under
## coverage that is ~2× fewer tiles than the old 96×64 two-region boot.
const BOOT_WIDTH: int = 64
const BOOT_HEIGHT: int = 48
const NEW_WORLD_SEED: int = Fixture.SEED + 7919

## Non-underscore so before_all state is copied onto each test instance. The
## post-pass is read-only in every case below, so region charts in before_all
## keep world generation (the suite's dominant cost under coverage) off the
## hot path. Old World, its determinism twin, and the New World are each
## generated once — never via `generate_world`, which would build discarded
## charts.
var model: MapModel = null
var works: LandWorks = null
var report: Dictionary = {}
var model_twin: MapModel = null
var works_twin: LandWorks = null
var new_world: MapModel = null
var new_world_works: LandWorks = null
var new_world_report: Dictionary = {}


func _bootstrap_world() -> void:
	model = MapGenerator.new().generate_region(
		Fixture.SEED, FactionCatalog.OLD_WORLD, BOOT_WIDTH, BOOT_HEIGHT
	)
	works = LandWorks.new()
	report = WorldBootstrap.apply(model, works)
	model_twin = MapGenerator.new().generate_region(
		Fixture.SEED, FactionCatalog.OLD_WORLD, BOOT_WIDTH, BOOT_HEIGHT
	)
	works_twin = LandWorks.new()
	WorldBootstrap.apply(model_twin, works_twin)
	new_world = MapGenerator.new().generate_region(
		NEW_WORLD_SEED, FactionCatalog.NEW_WORLD, BOOT_WIDTH, BOOT_HEIGHT
	)
	new_world_works = LandWorks.new()
	new_world_report = WorldBootstrap.apply(new_world, new_world_works)


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


## Grain is a plains crop (wiki: resource-terrain-region-rules § Table), so no
## guaranteed farm may stand on hills, forest, swamp or mountain ground.
func test_every_farm_stands_on_ground_that_grows_grain() -> void:
	var legal: Array = WorldBootstrap.grain_terrains()
	assert_true(legal.has(MapModel.Terrain.PLAINS), "grain grows on plains")
	var farms: int = 0
	for province: ProvinceState in model.provinces:
		for tile: Vector2i in province.tiles:
			if model.resource_at(tile.x, tile.y) != WorldBootstrap.GRAIN_RESOURCE:
				continue
			if works.improvement_at(model, tile) != WorldBootstrap.FARM_LEVEL:
				continue
			farms += 1
			assert_true(
				WorldBootstrap.may_host_grain(model, tile),
				"grain farm at %s stands on %d" % [tile, model.terrain_at(tile.x, tile.y)]
			)
	assert_gt(farms, 0)


## A capital province too thin in plains has its remaining farm sites levelled
## rather than carrying a crop its ground cannot grow; the four farms stand.
func test_a_thin_capital_province_levels_its_farm_sites() -> void:
	assert_gt(int(report["farms_levelled"]), 0, "the fixture chart has a thin capital")
	for faction: int in FactionCatalog.great_power_ids():
		var province: int = WorldBootstrap.capital_province(model, faction)
		var farms: int = 0
		for tile: Vector2i in model.province_tiles(province):
			if works.improvement_at(model, tile) != WorldBootstrap.FARM_LEVEL:
				continue
			if model.resource_at(tile.x, tile.y) != WorldBootstrap.GRAIN_RESOURCE:
				continue
			farms += 1
			assert_eq(
				model.terrain_at(tile.x, tile.y), MapModel.Terrain.PLAINS,
				"the levelled site at %s is plain" % tile
			)
		assert_eq(farms, WorldBootstrap.GRAIN_FARMS)


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


## Both AI passes read the seat through one helper: the province and its capital
## tile together, and -1/(-1, -1) where the crown has no capital.
func test_capital_seat_pairs_province_and_tile() -> void:
	var faction: int = FactionCatalog.PLAYER_FACTION
	var seat: Dictionary = WorldBootstrap.capital_seat(model, faction)
	var province: int = WorldBootstrap.capital_province(model, faction)
	assert_gt(province, -1, "the crown holds a capital")
	assert_eq(int(seat["province"]), province)
	assert_eq(seat["tile"], model.capital_tile_of(province))

	var landless: Dictionary = WorldBootstrap.capital_seat(new_world, faction)
	assert_eq(int(landless["province"]), -1, "no Great Power capital in the New World")
	assert_eq(landless["tile"], Vector2i(-1, -1))


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
	assert_eq(model_twin.resource, model.resource)
	assert_eq(works_twin.improvement, works.improvement)
	assert_eq(works_twin.transport, works.transport)
	assert_eq(works_twin.ports, works.ports)


func test_the_new_world_gets_no_great_power_farms() -> void:
	assert_eq(int(new_world_report["farms"]), 0)
	assert_eq(int(new_world_report["town_roads"]), 0, "the New World is not wired at init")
	assert_true(new_world_works.improvement.is_empty())

# --- from test_advanced_start.gd ---
## Advanced starts: tier tables, tech lists, musters, colonies and estates.
## Advanced starts (wiki: advanced-starts; DR-20261111-01): tier tables, the
## fixed tech lists, the balanced muster, inherited colonies, chart and estates.
## The live setup path (a real map screen opening mid-age) lives in
## test_advanced_start_live so these cheap cases never wait behind those mounts.

const NEW_WORLD: int = 1

var adv_world: WorldMap = null
var adv_saved: Array = []


func _advanced_before_all() -> void:
	adv_saved = Fixture.snapshot(Fixture.world())


func _advanced_before_each() -> void:
	Fixture.restore(Fixture.world(), adv_saved)
	adv_world = Fixture.world()


func _advanced_after_each() -> void:
	Fixture.restore(adv_world, adv_saved)


# --- tier tables -------------------------------------------------------------


func test_presets_match_the_published_tiers() -> void:
	assert_eq(AdvancedStart.turn(AdvancedStart.TURNS50), 50)
	assert_eq(AdvancedStart.turn(AdvancedStart.TURNS100), 100)
	assert_eq(int(AdvancedStart.entry(AdvancedStart.TURNS50)["treasury"]), 20000)
	assert_eq(int(AdvancedStart.entry(AdvancedStart.TURNS100)["treasury"]), 40000)
	assert_eq(int(AdvancedStart.entry(AdvancedStart.TURNS100)["apprentices"]), 4)
	assert_eq(AdvancedStart.regiments(AdvancedStart.TURNS50), 6)
	assert_eq(AdvancedStart.regiments(AdvancedStart.TURNS100), 12)
	assert_eq(AdvancedStart.cargo_ships(AdvancedStart.TURNS100), 6)
	assert_almost_eq(AdvancedStart.nw_reveal(AdvancedStart.TURNS50), 0.625, 0.0001)


func test_turn_zero_is_the_ordinary_campaign() -> void:
	assert_false(AdvancedStart.active(AdvancedStart.NONE))
	assert_eq(AdvancedStart.tech_ids(AdvancedStart.NONE).size(), 0)
	assert_eq(AdvancedStart.regiment_types(AdvancedStart.NONE).size(), 0)
	assert_eq(AdvancedStart.normalize("nonsense"), AdvancedStart.NONE)


# --- technology --------------------------------------------------------------


func test_tech_lists_are_the_fixed_rows_and_closed_under_prereqs() -> void:
	var fifty: Array[String] = AdvancedStart.tech_ids(AdvancedStart.TURNS50)
	var hundred: Array[String] = AdvancedStart.tech_ids(AdvancedStart.TURNS100)
	assert_eq(fifty.size(), 23, "50-turn list has 23 techs")
	assert_eq(hundred.size(), 45, "100-turn list has 45 techs")
	for tech: String in hundred:
		assert_true(TechCatalog.known(tech), "%s is a catalog tech" % tech)
		for prereq: String in TechCatalog.prerequisites(tech):
			assert_has(hundred, prereq, "%s needs an in-list prereq" % tech)
	assert_false(fifty.has("early_steam_engine"), "the 50-turn age stops before steam")


# --- muster ------------------------------------------------------------------


func test_the_muster_balances_branches_with_buildable_types() -> void:
	for tier: String in [AdvancedStart.TURNS50, AdvancedStart.TURNS100]:
		var types: Array[String] = AdvancedStart.regiment_types(tier)
		assert_eq(types.size(), AdvancedStart.regiments(tier), "full roster musters")
		var branches: Dictionary = {"infantry": 0, "cavalry": 0, "artillery": 0}
		var tech: Dictionary = AdvancedStart.tech_table(tier)
		for type_id: String in types:
			assert_true(
				RegimentEconomy.buildable(type_id, tech),
				"%s is unlocked by the tier's techs" % type_id
			)
			branches[_branch(type_id)] = int(branches[_branch(type_id)]) + 1
		for branch: String in branches.keys():
			assert_gte(int(branches[branch]), 1, "%s gets regiments" % branch)


func _branch(type_id: String) -> String:
	match RegimentCatalog.category(type_id):
		RegimentCatalog.Category.LIGHT_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.SPEAR_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.HEAVY_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.LIGHT_ARTILLERY:
			return "artillery"
		RegimentCatalog.Category.HEAVY_ARTILLERY:
			return "artillery"
		_:
			return "infantry"


# --- colonies and chart ------------------------------------------------------


func test_colonies_leave_every_tribe_a_home() -> void:
	var model: MapModel = adv_world.region(NEW_WORLD)
	var before: Dictionary = _tribe_counts(model)
	var claimed: Dictionary = AdvancedWorld.claim(
		adv_world, AdvancedStart.nw_owned(AdvancedStart.TURNS100), FactionCatalog.great_power_ids()
	)
	assert_false(claimed.is_empty(), "the Passage shore yields colonies")
	for faction: Variant in claimed.keys():
		var provinces: Array = claimed[faction]
		assert_lte(provinces.size(), 6, "a crown takes at most six")
		for province_id: int in provinces:
			assert_eq(
				model.province_owner(province_id), int(faction),
				"the colony changes hands"
			)
	var after: Dictionary = _tribe_counts(model)
	for owner: Variant in before.keys():
		assert_gte(int(after.get(owner, 0)), 1, "tribe %s keeps a province" % owner)


func test_claimed_colonies_are_contiguous() -> void:
	var model: MapModel = adv_world.region(NEW_WORLD)
	var claimed: Dictionary = AdvancedWorld.claim(
		adv_world, AdvancedStart.nw_owned(AdvancedStart.TURNS100), FactionCatalog.great_power_ids()
	)
	for faction: Variant in claimed.keys():
		var provinces: Array = claimed[faction]
		if provinces.size() < 2:
			continue
		var reached: Dictionary = {int(provinces[0]): true}
		var queue: Array[int] = [int(provinces[0])]
		var head: int = 0
		while head < queue.size():
			var province_id: int = queue[head]
			head += 1
			for raw: Variant in MapGeo.province_neighbors(model, province_id):
				if reached.has(int(raw)) or not provinces.has(int(raw)):
					continue
				reached[int(raw)] = true
				queue.append(int(raw))
		assert_eq(reached.size(), provinces.size(), "colonies touch each other")


func _tribe_counts(model: MapModel) -> Dictionary:
	var counts: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
			counts[province.owner] = int(counts.get(province.owner, 0)) + 1
	return counts


func test_the_chart_opens_the_documented_share() -> void:
	var model: MapModel = adv_world.region(NEW_WORLD)
	var visibility := VisibilityModel.new()
	visibility.setup(model, FactionCatalog.PLAYER_FACTION)
	visibility.apply_initial()
	var revealed: int = AdvancedWorld.reveal(
		adv_world, visibility, FactionCatalog.PLAYER_FACTION,
		AdvancedStart.nw_reveal(AdvancedStart.TURNS50)
	)
	var total: int = model.province_count()
	assert_gte(revealed, ceili(float(total) * 0.625) - 1, "most of the New World charts")
	assert_lte(revealed, total, "never more than the map")
	var charted: Array[int] = AdvancedWorld.charted_provinces(
		adv_world, AdvancedStart.nw_reveal(AdvancedStart.TURNS100)
	)
	assert_eq(charted.size(), total, "the 100-turn chart is the whole New World")


## Wiki § NW sea-zone visibility: the chart holds the water beside a flood-filled
## shore *and* the shortest S–S lanes from the Passage that reach it; water off
## both stays unknown.
func test_the_chart_holds_the_passage_lanes() -> void:
	var model: MapModel = adv_world.region(NEW_WORLD)
	var shared: float = AdvancedStart.nw_reveal(AdvancedStart.TURNS50)
	var visibility := VisibilityModel.new()
	visibility.setup(model, FactionCatalog.PLAYER_FACTION)
	visibility.apply_initial()
	AdvancedWorld.reveal(adv_world, visibility, FactionCatalog.PLAYER_FACTION, shared)
	var provinces: Array[int] = AdvancedWorld.charted_provinces(adv_world, shared)
	var entries: Array[int] = adv_world.warp_zones(NEW_WORLD)
	var lanes: Array[int] = AdvancedSeas.charted(model, entries, provinces)
	assert_false(lanes.is_empty(), "the Passage reaches the charted shore")
	for zone_id: int in lanes:
		var data: SeaZoneState = model.sea_zone_data(zone_id)
		assert_not_null(data, "a lane names a real zone")
		for tile: Vector2i in data.tiles:
			assert_gte(
				visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FOGGED,
				"lane water is charted"
			)
	for zone: SeaZoneState in model.sea_zones:
		if lanes.has(zone.id):
			continue
		for tile: Vector2i in zone.tiles:
			assert_eq(
				visibility.level_at(tile.x, tile.y), VisibilityModel.Level.UNKNOWN,
				"water off the lane and off a revealed shore stays unknown"
			)


## The lane, not only the shore: a province charted across open water brings the
## water that reaches it from the Passage, so a voyage can sail the whole way
## instead of guessing at the last step (wiki § NW sea-zone visibility).
func test_a_lane_carries_the_chart_across_open_water() -> void:
	var model: MapModel = adv_world.region(NEW_WORLD)
	var entries: Array[int] = adv_world.warp_zones(NEW_WORLD)
	if entries.is_empty():
		return
	var from_entry: Dictionary = AdvancedSeas.hops(model, entries)
	var far: int = _far_shore(model, from_entry)
	assert_gte(far, 0, "the fixture has a shore off the Passage mouth")
	var shore: Array[int] = NavalMovement.province_sea_zones(model, far)
	var lanes: Array[int] = AdvancedSeas.charted(model, entries, [far])
	for zone: int in shore:
		assert_has(lanes, zone, "the shore's own water charts")
	assert_gt(lanes.size(), shore.size(), "the lane that reaches it charts too")
	var to_shore: Dictionary = AdvancedSeas.hops(model, shore)
	var nearest: int = 1 << 30
	for zone: int in shore:
		nearest = mini(nearest, int(from_entry.get(zone, nearest)))
	for zone: int in lanes:
		assert_eq(
			int(from_entry.get(zone, -1)) + int(to_shore.get(zone, -1)), nearest,
			"every charted zone lies on a shortest lane to the shore"
		)


## Charted water is `fogged`; a shore the crown owns paints its own water fully
## visible through the standing coastal pass.
func test_the_lane_paints_fogged_water_and_a_held_beach_fully_visible() -> void:
	var model: MapModel = adv_world.region(NEW_WORLD)
	var entries: Array[int] = adv_world.warp_zones(NEW_WORLD)
	var far: int = _far_shore(model, AdvancedSeas.hops(model, entries))
	if far < 0:
		return
	var zone: int = int(NavalMovement.province_sea_zones(model, far)[0])
	var visibility := VisibilityModel.new()
	visibility.setup(model, FactionCatalog.PLAYER_FACTION)
	visibility.apply_initial()
	AdvancedSeas.chart(model, visibility, zone, FactionCatalog.PLAYER_FACTION)
	for tile: Vector2i in model.sea_zone_data(zone).tiles:
		assert_eq(
			visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FOGGED,
			"a charted lane is fogged, not surveyed"
		)
	(model.get_province(far) as ProvinceState).owner = FactionCatalog.PLAYER_FACTION
	AdvancedSeas.chart(model, visibility, zone, FactionCatalog.PLAYER_FACTION)
	for tile: Vector2i in model.sea_zone_data(zone).tiles:
		assert_eq(
			visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE,
			"the crown's own beach is fully visible"
		)


## Wiki § NW sea-zone visibility leaves `unknown` only the water that is neither
## P–S adjacent to a revealed province nor on the connecting path. A shore the
## Passage cannot reach in one lane still charts its own water; water off both
## stays unknown.
func test_the_shore_charts_even_where_no_lane_reaches() -> void:
	var model: MapModel = MapModel.new()
	model.setup(8, 3)
	model.region_id = NEW_WORLD
	for y in 3:
		for x in 8:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	# Two shores on two seas that never touch, plus one sea with no shore at all.
	var near: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var far: Array[Vector2i] = [Vector2i(4, 0), Vector2i(5, 0)]
	for tile: Vector2i in near + far:
		model.province[model.index_of(tile.x, tile.y)] = 0 if near.has(tile) else 1
	var zones: Array = [
		SeaZoneState.create(0, "Entry", [Vector2i(0, 1), Vector2i(1, 1)], Vector2.ZERO, 2),
		SeaZoneState.create(1, "Far", [Vector2i(4, 1), Vector2i(5, 1)], Vector2.ZERO, 2),
		SeaZoneState.create(2, "Offshore", [Vector2i(7, 1)], Vector2.ZERO, 1),
	]
	model.sea_zones.clear()
	for zone: SeaZoneState in zones:
		model.sea_zones.append(zone)
		for tile: Vector2i in zone.tiles:
			model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.OCEAN
			model.sea_zone[model.index_of(tile.x, tile.y)] = zone.id
	model.provinces.append(ProvinceState.create(0, "Near", near, Vector2.ZERO, 2, 6))
	model.provinces.append(ProvinceState.create(1, "Far", far, Vector2.ZERO, 2, 6))
	var charted: Array[int] = AdvancedSeas.charted(model, [0], [0, 1])
	assert_has(charted, 0, "the shore beside the Passage charts")
	assert_has(charted, 1, "the far shore charts its own water")
	assert_false(charted.has(2), "water beside no revealed province stays unknown")
	assert_eq(AdvancedSeas.charted(model, [], [0, 1]), charted, "no entry, the shore still charts")
	assert_eq(
		AdvancedSeas.charted(model, [0], []), [] as Array[int], "no shore, no water"
	)


## A province whose shore zone is not at the Passage mouth, preferring one that
## needs more than one S–S hop; -1 when the map has no such shore.
func _far_shore(model: MapModel, from_entry: Dictionary) -> int:
	var fallback: int = -1
	for province: ProvinceState in model.provinces:
		for zone: int in NavalMovement.province_sea_zones(model, province.id):
			var hops: int = int(from_entry.get(zone, -1))
			if hops > 1:
				return province.id
			if hops == 1 and fallback < 0:
				fallback = province.id
	return fallback


# --- estates -----------------------------------------------------------------


func test_prospecting_marks_the_tier_share() -> void:
	var works: Dictionary = {}
	var minerals: int = _mineral_count(adv_world, FactionCatalog.PLAYER_FACTION)
	if minerals == 0:
		return
	var marked: int = AdvancedEstates.prospect(
		adv_world, works, [FactionCatalog.PLAYER_FACTION],
		AdvancedStart.prospect_share(AdvancedStart.TURNS50)
	)
	assert_gte(marked, ceili(float(minerals) * 0.5) - 1, "half the minerals are known")


func test_development_raises_estates_and_roads() -> void:
	var works: Dictionary = {}
	var raised: int = AdvancedEstates.develop(
		adv_world, works, [FactionCatalog.PLAYER_FACTION],
		AdvancedStart.develop_share(AdvancedStart.TURNS50)
	)
	assert_gte(raised, 1, "forward courts already hold estates")
	var model: MapModel = adv_world.region(0)
	var ledger: LandWorks = works[0]
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if ledger.improvement_at(model, tile) <= 0:
				continue
			assert_true(
				ledger.transport_at(model, tile) > 0 or province.town_tile.x < 0,
				"an estate is reached by road"
			)


func test_minor_land_is_bought_without_moving_the_province() -> void:
	var works: Dictionary = {}
	var bought: int = AdvancedEstates.purchase_minor_land(
		adv_world, works, FactionCatalog.great_power_ids(),
		AdvancedStart.develop_share(AdvancedStart.TURNS50)
	)
	assert_gte(bought, 1, "the Minor Nations have sold land")
	var model: MapModel = adv_world.region(0)
	var deeds: int = 0
	for province: ProvinceState in model.provinces:
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.MINOR_NATION:
			continue
		for tile: Vector2i in province.tiles:
			if not model.is_purchased_tile(tile):
				continue
			deeds += 1
			assert_ne(model.owner_at(tile.x, tile.y), province.owner, "the deed moves, not the province")
			assert_true(
				(works[0] as LandWorks).improvement_at(model, tile) > 0
				or model.resource_at(tile.x, tile.y) < 0,
				"bought land is developed"
			)
	assert_eq(deeds, bought, "every purchase is a deed")


## A deed lifts the seller's town at any share of the tier (wiki: adv_world-market
## § Minor and tribe auto-sell — the town stands at `min(4, 1 + deeds)`,
## DR-20261112-01). The tier's round-robin purchases bypass the Merchant's
## completion, so the town has to rise here or the manufactures a bought-up
## Minor used to pay never reach the book.
func test_a_tier_deed_lifts_the_sellers_town() -> void:
	var works: Dictionary = {}
	var bought: int = AdvancedEstates.purchase_minor_land(
		adv_world, works, FactionCatalog.great_power_ids(),
		AdvancedStart.develop_share(AdvancedStart.TURNS50)
	)
	assert_gte(bought, 1, "the Minor Nations have sold land")
	var lifted: int = 0
	for model: MapModel in adv_world.regions:
		for province: ProvinceState in model.provinces:
			var deeds: int = MinorTownGrowth.deeds_in(model, province)
			if deeds <= 0:
				continue
			assert_eq(
				province.town_development, MinorTownGrowth.level_for(deeds),
				"province %d stands on %d deeds" % [province.id, deeds]
			)
			if MinorTownGrowth.level_for(deeds) > 1:
				lifted += 1
	assert_gte(lifted, 1, "a bought-up town rose off its level-1 baseline")


func _mineral_count(adv_world: WorldMap, faction: int) -> int:
	var count: int = 0
	for model: MapModel in adv_world.regions:
		for province: ProvinceState in model.provinces:
			if model.province_owner(province.id) != faction:
				continue
			for tile: Vector2i in province.tiles:
				if ImprovementCatalog.needs_prospecting(model.resource_at(tile.x, tile.y)):
					count += 1
	return count

# --- from test_map_generator.gd ---
## Generation: land, sea zones, provinces and fair splits.
## Generation invariants: deterministic output, complete assignment and
## contiguous provinces (wiki: tile-map-and-generation).


const GEN_SEED: int = Fixture.SEED
const GEN_WIDTH: int = Fixture.WIDTH
const GEN_HEIGHT: int = Fixture.HEIGHT

## Non-underscore so before_all state is copied onto each test instance.
var gen_model: MapModel = null


func _generator_before_all() -> void:
	gen_model = Fixture.region()


func test_same_seed_is_deterministic() -> void:
	var other: MapModel = MapGenerator.new().generate(GEN_SEED, GEN_WIDTH, GEN_HEIGHT)
	assert_eq(other.terrain, gen_model.terrain)
	assert_eq(other.province, gen_model.province)
	assert_eq(other.sea_zone, gen_model.sea_zone)
	var names: Array = []
	for province: ProvinceState in other.provinces:
		names.append(province.name)
	var expected: Array = []
	for province: ProvinceState in gen_model.provinces:
		expected.append(province.name)
	assert_eq(names, expected)
	var waters: Array = []
	for zone: SeaZoneState in other.sea_zones:
		waters.append(zone.name)
	var charted: Array = []
	for zone: SeaZoneState in gen_model.sea_zones:
		charted.append(zone.name)
	assert_eq(waters, charted, "the same chart names its waters differently")


func test_different_seed_changes_the_map() -> void:
	var other: MapModel = MapGenerator.new().generate(GEN_SEED + 1, GEN_WIDTH, GEN_HEIGHT)
	assert_ne(other.terrain, gen_model.terrain)


func test_land_ratio_is_plausible() -> void:
	var ratio: float = float(MapGeo.land_tile_count(gen_model)) / float(GEN_WIDTH * GEN_HEIGHT)
	assert_between(ratio, 0.15, 0.65, "land ratio %.3f" % ratio)


func test_every_tile_is_assigned() -> void:
	for y in gen_model.height:
		for x in gen_model.width:
			var province: int = gen_model.province_at(x, y)
			var zone: int = gen_model.sea_zone_at(x, y)
			if gen_model.is_land(x, y):
				assert_ne(province, MapModel.NO_ID, "land tile %d,%d has no province" % [x, y])
				assert_eq(zone, MapModel.NO_ID)
			else:
				assert_ne(zone, MapModel.NO_ID, "sea tile %d,%d has no zone" % [x, y])
				assert_eq(province, MapModel.NO_ID)


func test_every_province_is_contiguous() -> void:
	for province: ProvinceState in gen_model.provinces:
		var tiles: Array = province.tiles
		assert_true(tiles.size() > 0)
		assert_true(_is_contiguous(tiles), "province %s is not contiguous" % province.name)


func test_every_sea_zone_is_contiguous() -> void:
	for zone: SeaZoneState in gen_model.sea_zones:
		assert_true(_is_contiguous(zone.tiles))


func test_province_borders_are_inside_the_map() -> void:
	for y in gen_model.height:
		for x in gen_model.width:
			if gen_model.is_land(x, y):
				assert_true(x >= 0 and y >= 0 and x < GEN_WIDTH and y < GEN_HEIGHT)


func test_default_map_is_the_old_world() -> void:
	assert_eq(gen_model.region_id, FactionCatalog.OLD_WORLD)
	assert_true(gen_model.setup_errors.is_empty(), "setup errors: %s" % str(gen_model.setup_errors))
	assert_eq(gen_model.faction_ids, FactionCatalog.ids_in_region(FactionCatalog.OLD_WORLD))


func test_ownership_spreads_across_factions_with_one_capital_each() -> void:
	var capitals: int = 0
	var owners: Dictionary = {}
	for province: ProvinceState in gen_model.provinces:
		var owner: int = province.owner
		assert_true(FactionCatalog.has_faction(owner), "owner %d is a faction" % owner)
		assert_true(FactionCatalog.can_own_region(owner, gen_model.region_id))
		owners[owner] = true
		if province.capital:
			capitals += 1
	assert_eq(capitals, owners.size())
	for faction_id: int in gen_model.faction_ids:
		assert_true(owners.has(faction_id), "faction %d owns no province" % faction_id)


func test_capitals_follow_the_capital_choice_rule() -> void:
	var seen: Dictionary = {}
	for province: ProvinceState in gen_model.provinces:
		if not province.capital:
			continue
		var owner: int = province.owner
		assert_false(seen.has(owner), "faction %d has two capitals" % owner)
		seen[owner] = true
		var tile: Vector2i = province.capital_tile
		assert_true(gen_model.is_land(tile.x, tile.y))
		assert_eq(gen_model.terrain_at(tile.x, tile.y), MapModel.Terrain.PLAINS)
		var kind: int = (
			CapitalChoice.KIND_GREAT_POWER
			if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER
			else CapitalChoice.KIND_MINOR
		)
		if kind == CapitalChoice.KIND_GREAT_POWER:
			assert_true(CapitalChoice.is_sea_bound(gen_model, province.id))
		var pick: Dictionary = CapitalChoice.pick_province(gen_model, owner, kind)
		assert_eq(int(pick["province_id"]), province.id)
		if CapitalChoice.is_sea_bound(gen_model, province.id):
			var ports: Dictionary = province.ports
			assert_eq(
				ports.size(),
				CapitalChoice.sea_bound_sea_zones(gen_model, province.id).size()
			)
	assert_eq(seen.size(), gen_model.faction_ids.size())


func test_every_province_has_a_town_tile() -> void:
	for province: ProvinceState in gen_model.provinces:
		var town: Vector2i = province.town_tile
		assert_true(town.x >= 0, "province %s has no town" % province.name)
		assert_eq(gen_model.province_at(town.x, town.y), province.id)
		assert_eq(gen_model.terrain_at(town.x, town.y), MapModel.Terrain.PLAINS)
		assert_eq(gen_model.resource_at(town.x, town.y), MapModel.NO_ID)
		assert_gte(province.town_development, 1)
		if province.capital:
			assert_eq(town, province.capital_tile)


func test_coastal_provinces_have_a_waterfront_port() -> void:
	for province: ProvinceState in gen_model.provinces:
		var port: Vector2i = province.port_tile
		if not province.coastal:
			assert_eq(port, Vector2i(-1, -1))
			continue
		assert_true(port.x >= 0, "coastal province %s has no port" % province.name)
		assert_true(gen_model.is_land(port.x, port.y))
		assert_true(MapGeo.is_coastal_tile(gen_model, port.x, port.y))


func test_resources_sit_on_allowed_terrain() -> void:
	var table: Array[Dictionary] = MapGenerator.resource_table()
	for province: ProvinceState in gen_model.provinces:
		var resource: int = province.resource
		if resource < 0:
			continue
		var tile: Vector2i = province.resource_tile
		var terrain: int = gen_model.terrain_at(tile.x, tile.y)
		var allowed: Array = table[resource]["terrain"]
		assert_true(allowed.has(terrain), "%s on %d" % [table[resource]["name"], terrain])


## Every row of the published resource–terrain–region table, so a crop left out
## of the catalog cannot silently take its discovery tech down with it (wiki:
## resource-terrain-region-rules § Table).
const PUBLISHED_RESOURCES: Dictionary = {
	"grain": ["ow", [MapModel.Terrain.PLAINS]],
	"meat": ["ow", [MapModel.Terrain.PLAINS]],
	"wool": ["ow", [MapModel.Terrain.HILLS]],
	"horses": ["ow", [MapModel.Terrain.PLAINS]],
	"timber": ["both", [MapModel.Terrain.HARDWOOD_FOREST, MapModel.Terrain.SCRUB_FOREST]],
	"iron": ["both", [MapModel.Terrain.HILLS, MapModel.Terrain.MOUNTAINS]],
	"copper": ["both", [MapModel.Terrain.HILLS, MapModel.Terrain.MOUNTAINS]],
	"tin": ["both", [MapModel.Terrain.SWAMP]],
	"coal": ["both", [MapModel.Terrain.HILLS, MapModel.Terrain.MOUNTAINS]],
	"sugarCane": ["nw", [MapModel.Terrain.PLAINS]],
	"tobacco": ["nw", [MapModel.Terrain.PLAINS]],
	"cotton": ["nw", [MapModel.Terrain.PLAINS]],
	"furs": ["nw", [MapModel.Terrain.HARDWOOD_FOREST]],
	"spices": ["nw", [MapModel.Terrain.PLAINS]],
	"silver": ["nw", [MapModel.Terrain.HILLS]],
	"gold": ["nw", [MapModel.Terrain.MOUNTAINS]],
	"gems": ["nw", [MapModel.Terrain.MOUNTAINS]],
	"diamonds": ["nw", [MapModel.Terrain.DESERT]],
}


func test_the_resource_table_carries_every_published_row() -> void:
	var table: Array[Dictionary] = MapGenerator.resource_table()
	assert_eq(table.size(), PUBLISHED_RESOURCES.size())
	for entry: Dictionary in table:
		var commodity: String = String(entry["commodity"])
		assert_true(PUBLISHED_RESOURCES.has(commodity), "unpublished resource %s" % commodity)
		var expected: Array = PUBLISHED_RESOURCES[commodity]
		assert_eq(String(entry["scope"]), String(expected[0]), "%s scope" % commodity)
		assert_eq(entry["terrain"], expected[1], "%s terrain" % commodity)


## The New World's crops must be placeable, or their discovery techs — and the
## sugar/tobacco/fur luxuries, cotton cloth and trained worker tiers behind them
## — could never be researched (wiki: resource-terrain-region-rules § Table;
## tech-tree-new-world § Discovery prerequisites).
func test_the_new_world_carries_a_crop_its_techs_ask_for() -> void:
	var world: WorldMap = Fixture.world()
	var tribes: MapModel = world.region(1)
	var view := VisibilityModel.new()
	view.setup(tribes, FactionCatalog.PLAYER_FACTION)
	view.levels.fill(VisibilityModel.Level.FOGGED)
	var found: Dictionary = TechDiscovery.revealed(world, {1: view}, LandWorks.new(), 0)
	var crops: Array[String] = ["sugarCane", "tobacco", "cotton", "furs", "spices"]
	var seen: Array[String] = []
	for crop: String in crops:
		if found.has(crop):
			seen.append(crop)
	assert_false(seen.is_empty(), "a charted New World carries no crop at all")
	for crop: String in crops:
		assert_ne(
			TechCatalog.discovery_resources(_discovery_tech_for(crop)).size(), 0,
			"no discovery tech names %s" % crop
		)


## The discovery tech a crop's research chain hangs on, by the catalog's own
## discovery list (wiki: tech-tree-new-world § Discovery prerequisites).
func _discovery_tech_for(commodity: String) -> String:
	for tech_id: String in TechCatalog.ids():
		if (TechCatalog.discovery_resources(tech_id) as Array).has(commodity):
			return tech_id
	return ""


func test_names_are_unique() -> void:
	var seen: Dictionary = {}
	for province: ProvinceState in gen_model.provinces:
		var name: String = province.name
		assert_false(seen.has(name), "duplicate province name %s" % name)
		seen[name] = true
	var zones: Dictionary = {}
	for zone: SeaZoneState in gen_model.sea_zones:
		var name: String = String(zone.name)
		assert_false(zones.has(name), "duplicate sea zone name %s" % name)
		zones[name] = true


## A sea zone wears the name of the water it lies nearest, not the next name in
## the list (wiki: naming § Sea-zone display names, DR-20261113-07): the western
## ocean is the Atlantic, the northern water the Baltic, the south the
## Mediterranean; the New World's west is the Pacific, its north-east the
## Caribbean.
func test_sea_names_follow_the_water() -> void:
	assert_eq(
		MapNaming.sea_name({}, FactionCatalog.OLD_WORLD, Vector2(0.08, 0.34)),
		"Océano Atlántico"
	)
	assert_eq(
		MapNaming.sea_name({}, FactionCatalog.OLD_WORLD, Vector2(0.60, 0.06)), "Mar Báltico"
	)
	assert_eq(
		MapNaming.sea_name({}, FactionCatalog.OLD_WORLD, Vector2(0.50, 0.64)), "Mar Mediterráneo"
	)
	assert_eq(
		MapNaming.sea_name({}, FactionCatalog.NEW_WORLD, Vector2(0.12, 0.40)), "Mar Pacífico"
	)
	assert_eq(
		MapNaming.sea_name({}, FactionCatalog.NEW_WORLD, Vector2(0.60, 0.20)), "Mar de los Caribes"
	)


## One water names one zone: each further zone takes the next-nearest water, so
## no label repeats. A chart with more zones than presets keeps labelling,
## spending the presets again with a numeric ordinal.
func test_sea_names_never_repeat_a_water() -> void:
	var used: Dictionary = {}
	var presets: Array[String] = MapNaming.sea_presets(FactionCatalog.OLD_WORLD)
	var at := Vector2(0.42, 0.12)
	var last_distance: float = -1.0
	for _i in presets.size():
		var name: String = MapNaming.sea_name(used, FactionCatalog.OLD_WORLD, at)
		assert_true(presets.has(name), "%s is no preset of the Old World" % name)
		var distance: float = at.distance_squared_to(
			MapNaming.sea_anchor(FactionCatalog.OLD_WORLD, name)
		)
		assert_true(distance >= last_distance, "%s answered out of order" % name)
		last_distance = distance
	var overflow: String = MapNaming.sea_name(used, FactionCatalog.OLD_WORLD, at)
	assert_true(overflow.ends_with(" (2)"), "%s carries no ordinal" % overflow)
	assert_eq(used.size(), presets.size() + 1, "a label was handed out twice")


## A chart far beyond its preset list still labels every zone: presets are spent
## again with the next free ordinal and no label is ever repeated.
func test_sea_names_outlast_their_presets() -> void:
	var used: Dictionary = {}
	var presets: Array[String] = MapNaming.sea_presets(FactionCatalog.NEW_WORLD)
	var at := Vector2(0.5, 0.5)
	for _i in presets.size() * 3:
		var name: String = MapNaming.sea_name(used, FactionCatalog.NEW_WORLD, at)
		assert_false(name.is_empty(), "a zone went unnamed")
	assert_eq(used.size(), presets.size() * 3, "a label was handed out twice")
	assert_true(used.has("Mar Pacífico (3)"), "the presets were not spent again")


## The generated chart reads like a chart: its northernmost water carries a
## northern name and its southernmost a southern one, never the reverse.
func test_generated_sea_names_are_geographic() -> void:
	var north: SeaZoneState = null
	var south: SeaZoneState = null
	for zone: SeaZoneState in gen_model.sea_zones:
		if north == null or zone.center.y < north.center.y:
			north = zone
		if south == null or zone.center.y > south.center.y:
			south = zone
	assert_true(north != null and south != null, "the chart holds no sea zone")
	var north_at: float = _water_latitude(String(north.name))
	var south_at: float = _water_latitude(String(south.name))
	assert_true(north_at < south_at, "north reads %s, south reads %s" % [north.name, south.name])
	assert_true(north_at < 0.45, "the northernmost water reads %s" % north.name)


## Latitude of the preset a label names, with any overflow ordinal dropped.
func _water_latitude(name: String) -> float:
	var base: String = name.split(" (")[0]
	return MapNaming.sea_anchor(FactionCatalog.OLD_WORLD, base).y


## A province must read as its owner's country: Spanish provinces get Spanish
## cities, English provinces English ones, and the capital its capital city.
func test_province_names_match_their_owner() -> void:
	for province: ProvinceState in gen_model.provinces:
		if province.owner == MapModel.NO_ID:
			continue
		var pool: Array[String] = MapNaming.faction_pool(province.owner)
		assert_false(pool.is_empty(), "faction %d has no name pool" % province.owner)
		if province.capital:
			assert_eq(province.name, MapNaming.capital_name(province.owner))
			continue
		assert_true(
			_name_from_pool(province.name, pool),
			"%s does not belong to %s" % [province.name, FactionCatalog.name_of(province.owner)]
		)


func test_tribe_provinces_use_tribe_names() -> void:
	var tribes: MapModel = Fixture.world().region(1)
	assert_true(tribes.setup_errors.is_empty(), "setup errors: %s" % str(tribes.setup_errors))
	var checked: int = 0
	for province: ProvinceState in tribes.provinces:
		if province.owner == MapModel.NO_ID:
			continue
		var pool: Array[String] = MapNaming.faction_pool(province.owner)
		assert_false(pool.is_empty(), "tribe %d has no name pool" % province.owner)
		if province.capital:
			assert_eq(province.name, MapNaming.capital_name(province.owner))
		else:
			assert_true(
				_name_from_pool(province.name, pool),
				"%s does not belong to %s" % [province.name, FactionCatalog.name_of(province.owner)]
			)
		checked += 1
	assert_true(checked > 0)


## The naming config gives England the capital city "London" (wiki: naming
## § Great Powers capitalCityName); the Spanish exonym must not reach the chart.
func test_the_english_capital_is_london() -> void:
	assert_eq(MapNaming.capital_name(1), "London")
	var seats: int = 0
	for province: ProvinceState in gen_model.provinces:
		assert_ne(province.name, "Londres", "the exonym never names a province")
		if province.owner == 1 and province.capital:
			assert_eq(province.name, "London", "England's seat reads London")
			seats += 1
	assert_eq(seats, 1)


func test_every_faction_has_a_name_pool() -> void:
	for faction: Dictionary in FactionCatalog.all():
		var faction_id: int = int(faction["id"])
		assert_false(MapNaming.faction_pool(faction_id).is_empty(), "no pool for %d" % faction_id)
		assert_ne(MapNaming.capital_name(faction_id), "")


func _name_from_pool(name: String, pool: Array[String]) -> bool:
	if name.begins_with("Tierra "):
		return true
	for root: String in pool:
		if name == root or name.ends_with(" " + root):
			return true
	return false


func test_resource_info_lookup() -> void:
	assert_eq(String(MapGenerator.resource_info(0).get("name", "")), "Timber")
	assert_true(MapGenerator.resource_info(-1).is_empty())
	assert_true(MapGenerator.resource_info(999).is_empty())


func _is_contiguous(tiles: Array) -> bool:
	if tiles.is_empty():
		return false
	var lookup: Dictionary = {}
	for tile: Vector2i in tiles:
		lookup[tile] = true
	var start: Vector2i = tiles[0]
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = tile + offset
			if lookup.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen.size() == tiles.size()


# --- merged hooks (advanced start) ------------------------------------------

func before_each() -> void:
	_advanced_before_each()


func after_each() -> void:
	_advanced_after_each()
