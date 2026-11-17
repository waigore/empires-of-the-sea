extends GdToolsTest
## Two-region world setup (wiki: game-setup, map-topology, factions), the setup
## post-pass, generation invariants and the advanced-start presets and estates.
## Old World holds Great Powers + Minor Nations; the New World holds Tribes.
## Merged from test_world_bootstrap, test_map_generator, test_advanced_start and
## test_advanced_start_live: the tier's rules and the screen it opens share one
## boot.
##
## The name sorts **early** on purpose: gd-tools dispatches suites in plan
## (name) order four workers wide, so this suite with its published-chart draws
## used to sort last as `test_world_setup` and run alone after every other
## worker had drained (docs/testing.md § Speed rules). Rename it into the
## front half of the alphabet, never back into `w…`/`x…`/`y…`/`z…`.

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
	_mount_advanced_tiers()


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
## mounted suite pays that second build under coverage. Assert the cached chart
## itself — regenerating both regions under coverage used to cost ~2 s for the
## same reading `Fixture.world()` already proved when the suite booted.
func test_the_fixture_world_passes_on_its_first_attempt() -> void:
	var first: MapModel = world.region(FactionCatalog.OLD_WORLD)
	var second: MapModel = world.region(FactionCatalog.NEW_WORLD)
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
			MinorShare.MINOR_PROVINCES,
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
## Only the Old World is read, so the chart is generated without the New World
## `generate_world` would build and discard (`generate_region` is the same
## first-attempt Old World, at half the cost under coverage).
func test_a_pocket_never_cripples_a_great_power() -> void:
	var old_world: MapModel = MapGenerator.new().generate_region(
		4, FactionCatalog.OLD_WORLD, Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT
	)
	assert_true(old_world.setup_errors.is_empty(), str(old_world.setup_errors))
	_assert_even_share(old_world, FactionCatalog.great_power_ids(), "Old World Great Power")


## A cove a Minor Nation seals is handed to that court, and seed 9 used to leave
## Genoa holding five against a 3.33 even share because nothing trimmed it back
## (wiki: game-setup § Minor Nation assignment — "within ±1"; § Feasibility).
func test_a_sealed_cove_never_leaves_a_minor_oversized() -> void:
	var old_world: MapModel = MapGenerator.new().generate_region(
		9, FactionCatalog.OLD_WORLD, Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT
	)
	assert_true(old_world.setup_errors.is_empty(), str(old_world.setup_errors))
	_assert_even_share(old_world, FactionCatalog.minor_ids(), "Old World Minor Nation")


## A landmass too small to seat both rosters is infeasible, and the wiki wants a
## clear failure rather than a half-painted chart (wiki: game-setup
## § Feasibility). Seed 103's Old World holds 20 provinces: the six Minor
## Nations' three-province reservation takes every one of them, so no chunk is
## left for a Great Power. The split used to index an empty chunk list here —
## a `SCRIPT ERROR` the runner counts as a broken suite — and only then report
## `unfair_split` by accident.
func test_a_chart_with_no_land_left_for_the_great_powers_fails_cleanly() -> void:
	var old_world: MapModel = MapGenerator.new().generate_region(
		103, FactionCatalog.OLD_WORLD, Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT
	)
	assert_eq(
		old_world.setup_errors,
		["unfair_split"] as Array[String],
		"the chart is rejected with the wiki's own code"
	)
	for faction_id: int in FactionCatalog.great_power_ids():
		assert_eq(
			_count_owned(old_world, faction_id), 0,
			"no Great Power is seated on a rejected chart"
		)


## The split itself never indexes a chunk list it was not given: a landmass with
## nothing left to hand out yields no group rather than a runtime error.
func test_the_split_handles_a_landmass_with_no_chunk_left() -> void:
	var groups: Array = TerritoryAssignment._spread([] as Array, [0, 1])
	assert_true(groups.is_empty(), "no chunk, no group")


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
## The live setup path (a real map screen opening mid-age) is folded in below —
## one boot pays the tier's rules and the screen it opens.

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
	assert_eq(int(AdvancedStart.entry(AdvancedStart.TURNS50)["treasury"]), 40000)
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


## The published placement rate: a resource on three land tiles in ten, every
## forest cell carrying one whatever the share says, and the open ground filled
## after the guarantee rather than by a fixed one to three tiles a province
## (wiki: resource-terrain-region-rules § Placement rate, § Forest terrain split;
## DR-20261115-16, #676). Measured on the game's own seed and Standard chart.
func test_the_plot_carries_a_resource_on_three_land_tiles_in_ten() -> void:
	var world_map: WorldMap = _standard_world(1500)
	for model: MapModel in world_map.regions:
		var land: int = 0
		var carrying: int = 0
		var forests: int = 0
		var bare_forests: int = 0
		var open_carrying: int = 0
		for y in model.height:
			for x in model.width:
				if not model.is_land(x, y):
					continue
				land += 1
				var terrain: int = model.terrain_at(x, y)
				var forest: bool = terrain == MapModel.Terrain.HARDWOOD_FOREST \
					or terrain == MapModel.Terrain.SCRUB_FOREST
				var carries: bool = model.resource_at(x, y) != MapModel.NO_ID
				if carries:
					carrying += 1
					if not forest:
						open_carrying += 1
				if forest:
					forests += 1
					if not carries:
						bare_forests += 1
		var share: float = float(carrying) / float(maxi(land, 1))
		assert_true(share >= 0.28 and share <= 0.33,
			"region %d carries %.3f of its %d land tiles" % [model.region_id, share, land])
		assert_true(forests > 0)
		# A town tile is levelled to plains before this reading, so every cell
		# still forest must carry its guaranteed row.
		assert_eq(bare_forests, 0, "region %d has %d bare forest cells" % [model.region_id, bare_forests])
		assert_true(open_carrying > 0, "region %d left its open ground bare" % model.region_id)
		# Absolute supply for #676: Standard still funds a market book (not the
		# old ~3% sparse plot). OW land on Standard is ~2.3k tiles → ~670 rows.
		assert_true(carrying >= 300,
			"region %d only places %d resources on Standard" % [model.region_id, carrying])


## Standard chart keeps mean tiles/province in the published band while holding
## 60/30 province counts (wiki: tile-map-and-generation; #700). Measured on seed
## 1500: OW 37.7 (the wiki's ~30–40), NW 41.3 — 30 provinces share a smaller
## New World grid, so its band is the documented 30–45 in docs/world.md.
func test_standard_provinces_sit_in_the_published_size_band() -> void:
	var world_map: WorldMap = _standard_world(1500)
	var old_world: MapModel = world_map.region(FactionCatalog.OLD_WORLD)
	var new_world: MapModel = world_map.region(FactionCatalog.NEW_WORLD)
	assert_eq(old_world.provinces.size(), MapGenerator.OLD_WORLD_PROVINCES)
	assert_eq(new_world.provinces.size(), MapGenerator.NEW_WORLD_PROVINCES)
	_assert_mean_tiles(old_world, 30.0, 40.0)
	_assert_mean_tiles(new_world, 30.0, 45.0)


## The chart presets cascade in area, the default points at Standard, and the
## config's own width/height defaults follow that preset — no stale 128×84
## literal left over from the pre-#700 chart (tests build the default world off
## the table, not off a hard-coded size).
func test_the_chart_presets_cascade_from_a_standard_default() -> void:
	assert_eq(GameConfig.SIZES[GameConfig.DEFAULT_SIZE_INDEX]["label"], "Standard")
	var config := GameConfig.new()
	assert_eq(config.map_width, int(GameConfig.SIZES[GameConfig.DEFAULT_SIZE_INDEX]["width"]))
	assert_eq(config.map_height, int(GameConfig.SIZES[GameConfig.DEFAULT_SIZE_INDEX]["height"]))
	var previous: int = 0
	for preset: Dictionary in GameConfig.SIZES:
		var area: int = int(preset["width"]) * int(preset["height"])
		assert_true(area > previous,
			"preset %s is not larger than the one before it" % preset["label"])
		previous = area


## #676's supply clause survives the smaller Standard chart: the Minor/Tribe
## book still fills a larder (grain offered) and carries an absolute volume
## (485 offers from 16 sellers measured on seed 1500, down from 603 on the old
## 128×84 chart but far from empty).
func test_the_smaller_standard_chart_still_feeds_the_minor_book() -> void:
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(_standard_world(1500))
	var sellers: Dictionary = {}
	var units: int = 0
	var grain: int = 0
	for order: MarketOrder in orders:
		units += order.quantity
		sellers[order.faction] = true
		if order.commodity == "grain":
			grain += order.quantity
	assert_true(units >= 400, "Standard's Minor/Tribe book fell to %d units" % units)
	assert_true(sellers.size() >= 12,
		"only %d Minor/Tribe courts sell on Standard" % sellers.size())
	assert_true(grain > 0, "no Minor/Tribe court offers grain on Standard")


## The published charts are drawn **once per seed and size** and re-read by
## every case below. `static` is what makes that true: gd-tools runs each case
## on a fresh instance, so an instance dictionary would start empty and redraw
## the chart per case (the census cases alone drew Standard four times).
## Keyed by size because the weighting case reads Small and the density cases
## read Standard (docs/testing.md § Speed rules).
##
## A draw is this suite's most expensive fixture: the price is the **tiles**,
## so the census below draws one Small chart (~half Large's area), not Large,
## and a case that only needs two owned towns builds a pocket world instead of
## regenerating Standard.
static var _drawn_charts: Dictionary = {}


func _chart(seed_value: int, width: int, height: int) -> WorldMap:
	var key: String = "%d/%d/%d" % [seed_value, width, height]
	if not _drawn_charts.has(key):
		_drawn_charts[key] = MapGenerator.new().generate_world(seed_value, width, height)
	return _drawn_charts[key]


func _standard_world(seed_value: int) -> WorldMap:
	var preset: Dictionary = GameConfig.SIZES[GameConfig.DEFAULT_SIZE_INDEX]
	return _chart(seed_value, int(preset["width"]), int(preset["height"]))


## The **Small** chart the weighting case reads: seed 42 keeps every pool inside
## its three-deviation band and the gold>gems / meat>grain>horses order the
## table promises (Large at 128×84 used to buy that sample for ~14 s under
## coverage; Small is ~half the tiles). Standard seed 1500 still inverts
## gold/gems, so the census stays on this seed and size rather than the
## density cases' Standard draw.
func _small_world(seed_value: int) -> WorldMap:
	for preset: Dictionary in GameConfig.SIZES:
		if String(preset["label"]) == "Small":
			return _chart(seed_value, int(preset["width"]), int(preset["height"]))
	return _standard_world(seed_value)


func _assert_mean_tiles(model: MapModel, lo: float, hi: float) -> void:
	var land: int = 0
	for province: ProvinceState in model.provinces:
		land += province.tiles.size()
	var mean: float = float(land) / float(maxi(model.provinces.size(), 1))
	assert_true(
		mean >= lo and mean <= hi,
		"region %d mean tiles/province %.1f outside [%.0f, %.0f]" % [
			model.region_id, mean, lo, hi
		]
	)


## The published weighting, measured not eyeballed (issue #676, DR-20261115-16):
## the generator dumps its per-commodity tile counts, and every pool of rows
## that may stand on exactly the same terrain in the same region — so only the
## price separates them — reads the `1 / default market price` split: the
## pool with the widest price gaps orders by price, no pool's split drifts
## beyond three standard deviations of the weighted draw, and the forest
## guarantee still leaves timber the commonest row on the chart
## (wiki: resource-terrain-region-rules § Table).
func test_the_draw_prices_the_rows_by_their_market_price() -> void:
	# One Small chart carries every assertion below: seed 42 keeps gold ahead of
	# gems and every pool inside its three-deviation band (metals n=13 is the
	# tightest sample; spices sit at 0.228 against 0.209 ± 0.137). Large at
	# seed 1500 used to buy a wider peaks gap for ~14 s under coverage; Small
	# is half the tiles and still proves the published price order.
	var counts: Dictionary = {}
	var commodities: Dictionary = {}
	var world_map: WorldMap = _small_world(42)
	for model: MapModel in world_map.regions:
		# Read the packed rows: a tile that carries a row is land, so the
		# census is one pass instead of two instrumented lookups a tile.
		var rows: PackedInt32Array = model.resource
		for index in rows.size():
			var resource: int = rows[index]
			if resource == MapModel.NO_ID:
				continue
			if not commodities.has(resource):
				commodities[resource] = String(
					MapGenerator.resource_info(resource)["commodity"]
				)
			var commodity: String = String(commodities[resource])
			counts[commodity] = int(counts.get(commodity, 0)) + 1
	var dump: Array[String] = []
	for commodity: Variant in counts:
		dump.append("%s=%d@%d" % [
			String(commodity), int(counts[commodity]), CommodityCatalog.base_price(String(commodity))
		])
	dump.sort()
	print("per-commodity tile counts on Small seed 42: ", ", ".join(dump))
	# Pools whose rows share one terrain list and one region scope: only the
	# published price separates their draws (wiki § Table).
	var pools: Array = [
		{"rows": ["meat", "grain", "horses"]},
		{"rows": ["copper", "iron", "coal"]},
		{"rows": ["sugarCane", "tobacco", "cotton", "spices"]},
		{"rows": ["gold", "gems"]},
	]
	for pool: Dictionary in pools:
		var rows: Array = pool["rows"]
		var total: int = 0
		var weights: Dictionary = {}
		var weight_total: float = 0.0
		for commodity: String in rows:
			var weight: float = 1.0 / float(CommodityCatalog.base_price(commodity))
			weights[commodity] = weight
			weight_total += weight
			total += int(counts.get(commodity, 0))
		for commodity: String in rows:
			var expected: float = weights[commodity] / weight_total
			var observed: float = float(int(counts.get(commodity, 0))) / float(maxi(total, 1))
			var drift: float = 3.0 * sqrt(expected * (1.0 - expected) / float(maxi(total, 1)))
			assert_true(
				absf(observed - expected) <= drift,
				"%s drew %.3f against its weighted %.3f (pool n=%d)" % [
					commodity, observed, expected, total,
				],
			)
	# The widest-gap pool orders by price: meat (45) over grain (50) over
	# horses (60), and gold (166) over gems (250).
	assert_true(
		int(counts["meat"]) > int(counts["grain"]) and int(counts["grain"]) > int(counts["horses"]),
		"plains rows read meat %d, grain %d, horses %d" % [
			int(counts["meat"]), int(counts["grain"]), int(counts["horses"]),
		],
	)
	assert_true(
		int(counts["gold"]) > int(counts["gems"]),
		"peaks rows read gold %d, gems %d" % [int(counts["gold"]), int(counts["gems"])],
	)
	# The forest guarantee is placed by terrain, not price, so timber (the
	# cheapest row, on every forest cell) stays the commonest on the chart.
	for commodity: Variant in counts:
		if String(commodity) == "timber":
			continue
		assert_true(
			int(counts["timber"]) > int(counts[commodity]),
			"timber %d stays the commonest row ahead of %s %d" % [
				int(counts["timber"]), String(commodity), int(counts[commodity]),
			],
		)


## The published multi-region cap: at most 30% of placed rows are "both", and a
## tile offering a region-exclusive row takes it once the cap is reached (wiki:
## resource-terrain-region-rules § Multi-region resource cap).
func test_the_multi_region_cap_binds_where_a_choice_exists() -> void:
	assert_true(ResourceSeeder.both_allowed(0, 0), "the first row is always free")
	assert_true(ResourceSeeder.both_allowed(2, 8), "20% both still leaves room")
	assert_false(ResourceSeeder.both_allowed(3, 7), "30% both is the cap")
	assert_false(ResourceSeeder.both_allowed(9, 1), "a both-heavy plot stays barred")


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
	_setup_page_after_each()


# --- test_game_setup ---

## New-game setup: nation, seed and map-size choices resolve into one config.

const setup_page_SCENE: PackedScene = preload("res://scenes/game_setup.tscn")

var setup_page: GameSetupScreen = null
var setup_started: GameConfig = null
var setup_back_presses: int = 0


## Only the setup cases mount the page; the world cases above never pay for one.
func _open_setup_page() -> GameSetupScreen:
	if is_instance_valid(setup_page):
		return setup_page
	setup_started = null
	setup_back_presses = 0
	setup_page = setup_page_SCENE.instantiate()
	setup_page.start_requested.connect(
		func(config: GameConfig) -> void: setup_started = config
	)
	setup_page.back_pressed.connect(
		func() -> void: setup_back_presses += 1
	)
	add_child(setup_page)
	return setup_page


func _setup_page_after_each() -> void:
	if is_instance_valid(setup_page):
		setup_page.free()
	setup_page = null


func test_offers_every_great_power_and_size_preset() -> void:
	setup_page = _open_setup_page()
	assert_eq(setup_page.nation_option.item_count, FactionCatalog.great_power_ids().size())
	assert_eq(setup_page.nation_option.get_item_text(0), "Spain")
	assert_eq(setup_page.nation_option.get_item_id(1), 1, "England keeps its faction id")
	assert_eq(setup_page.size_option.item_count, GameConfig.SIZES.size())
	assert_eq(setup_page.size_option.selected, GameConfig.DEFAULT_SIZE_INDEX)
	assert_true(setup_page.seed_field.placeholder_text.contains("random"))


func test_leader_choices_follow_the_chosen_crown() -> void:
	setup_page = _open_setup_page()
	assert_eq(setup_page.leader_option.item_count, LeaderCatalog.keys_for(0).size())
	assert_true(setup_page.leader_option.get_item_text(0).contains("Isabella I"))
	assert_true(
		setup_page.leader_option.get_item_text(0).contains("Tribe first contact"),
		"the label names Spain's real effect, not a missing land bonus"
	)
	setup_page.nation_option.select(2)
	setup_page.nation_option.emit_signal("item_selected", 2)
	assert_eq(setup_page.leader_option.item_count, LeaderCatalog.keys_for(2).size())
	assert_true(setup_page.leader_option.get_item_text(0).contains("Napoleon"))
	assert_true(setup_page.leader_option.get_item_text(0).contains("+25%"))
	# Every default crown names its own published bonus (leader-bonuses § UI).
	for faction: int in FactionCatalog.great_power_ids():
		setup_page.nation_option.select(faction)
		setup_page.nation_option.emit_signal("item_selected", faction)
		var text: String = setup_page.leader_option.get_item_text(0)
		assert_true(text.contains(LeaderCatalog.bonus_label(LeaderCatalog.default_key(faction))),
			"%s's label names its effect" % FactionCatalog.name_of(faction))
		assert_false(
			text.contains("no bonus"),
			"%s fields a published bonus" % FactionCatalog.name_of(faction)
		)


func test_start_carries_the_chosen_leader_into_the_config() -> void:
	setup_page = _open_setup_page()
	setup_page.nation_option.select(2)
	setup_page.nation_option.emit_signal("item_selected", 2)
	setup_page.seed_field.text = "42"
	setup_page.start_button.emit_signal("pressed")
	assert_not_null(setup_started)
	if setup_started != null:
		assert_eq(setup_started.player_faction, 2)
		assert_eq(setup_started.player_leader, "napoleon")


func test_start_resolves_nation_seed_and_size() -> void:
	setup_page = _open_setup_page()
	setup_page.nation_option.select(1)
	setup_page.size_option.select(2)
	setup_page.seed_field.text = "777"
	setup_page.start_button.emit_signal("pressed")
	assert_not_null(setup_started, "start emits a config")
	if setup_started == null:
		return
	assert_eq(setup_started.player_faction, 1, "England is the human slot")
	assert_eq(setup_started.map_seed, 777)
	assert_eq(setup_started.map_width, int(GameConfig.SIZES[2]["width"]))
	assert_eq(setup_started.map_height, int(GameConfig.SIZES[2]["height"]))


func test_invalid_seed_keeps_the_player_on_setup() -> void:
	setup_page = _open_setup_page()
	setup_page.seed_field.text = "not-a-number"
	setup_page.start_button.emit_signal("pressed")
	assert_null(setup_started, "no config on an invalid seed")
	assert_true(setup_page._error.visible, "the error is shown")


func test_blank_seed_rolls_a_non_zero_seed() -> void:
	setup_page = _open_setup_page()
	setup_page.seed_field.text = ""
	setup_page.start_button.emit_signal("pressed")
	assert_not_null(setup_started)
	if setup_started != null:
		assert_gt(setup_started.map_seed, 0, "blank seed becomes random")


func test_back_emits_once() -> void:
	setup_page = _open_setup_page()
	setup_page.back_button.emit_signal("pressed")
	assert_eq(setup_back_presses, 1)


func test_config_round_trips_through_plain_data() -> void:
	var config: GameConfig = GameConfig.make(1234, 0, 3, "henry")
	var restored: GameConfig = GameConfig.from_dict(config.to_dict())
	assert_eq(restored.map_seed, 1234)
	assert_eq(restored.map_width, int(GameConfig.SIZES[0]["width"]))
	assert_eq(restored.map_height, int(GameConfig.SIZES[0]["height"]))
	assert_eq(restored.player_faction, 3)
	assert_eq(restored.player_leader, "henry")


func test_config_refuses_a_leader_the_crown_does_not_field() -> void:
	var config: GameConfig = GameConfig.make(1234, 0, 0, "napoleon")
	assert_eq(config.player_leader, "isabella", "Spain keeps its configured leader")


func test_difficulty_starts_on_normal_and_states_its_effect() -> void:
	setup_page = _open_setup_page()
	assert_eq(setup_page.difficulty_option.item_count, Difficulty.IDS.size())
	assert_eq(setup_page.difficulty_option.selected, Difficulty.index_of(Difficulty.DEFAULT))
	assert_eq(setup_page.difficulty_option.get_item_text(0), "Introductory")
	assert_true(
		setup_page._difficulty_hint.text.contains("alike"),
		"Normal reads as the published rules"
	)
	assert_true(
		setup_page._difficulty_hint.text.contains("hold 31 Old World provinces"),
		"the hint states the crown's published bar"
	)


func test_start_carries_the_chosen_difficulty_into_the_config() -> void:
	setup_page = _open_setup_page()
	setup_page.difficulty_option.select(Difficulty.index_of("hard"))
	setup_page.difficulty_option.emit_signal("item_selected", Difficulty.index_of("hard"))
	assert_true(setup_page._difficulty_hint.text.contains("140%"))
	assert_true(
		setup_page._difficulty_hint.text.contains("hold 36 Old World provinces"),
		"the hint states the bar the level sets (DR-20261111-28)"
	)
	setup_page.start_button.emit_signal("pressed")
	assert_not_null(setup_started)
	if setup_started != null:
		assert_eq(setup_started.difficulty, "hard")
		assert_eq(setup_started.to_dict()["difficulty"], "hard")


func test_config_round_trips_the_difficulty_layer() -> void:
	var config: GameConfig = GameConfig.make(99, 1, 1, "", false, "", "impossible")
	var restored: GameConfig = GameConfig.from_dict(config.to_dict())
	assert_eq(restored.difficulty, "impossible")
	assert_eq(GameConfig.make(99, 1, 1).difficulty, Difficulty.DEFAULT)


## The extra row must not push SET SAIL off a landscape phone; the row itself
## rides the page's scroll like every later field (REQ-P1-05, REQ-P1-07;
## geometry measured like tests/test_mobile_layout.gd).
func test_phone_setup_keeps_the_difficulty_row_reachable() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(914, 411)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var page: GameSetupScreen = setup_page_SCENE.instantiate()
	viewport.add_child(page)
	await get_tree().process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	assert_true(page.difficulty_option.is_visible_in_tree(), "the row is mounted")
	assert_true(_contains(screen, page.start_button.get_global_rect()), "SET SAIL stays on screen")
	assert_gt(page.start_button.size.y, 39.5, "SET SAIL is thumb-sized")
	assert_gt(page.difficulty_option.size.y, 39.5, "the Difficulty row is thumb-sized")
	var scroll: ScrollContainer = _page_scroll(page)
	assert_not_null(scroll, "the setup page scrolls its fields")
	if scroll != null:
		assert_true(scroll.scroll_vertical == 0, "the page opens at its top")
		assert_gt(
			scroll.get_v_scroll_bar().max_value,
			0.0,
			"the fields below the fold stay reachable by scrolling"
		)
		assert_true(
			scroll.find_children("*", "", true, false).has(page.difficulty_option),
			"the Difficulty row rides that scroll"
		)
	viewport.free()


func _page_scroll(page: Control) -> ScrollContainer:
	for node: Node in page.find_children("*", "ScrollContainer", true, false):
		return node as ScrollContainer
	return null


func _contains(outer: Rect2, inner: Rect2) -> bool:
	var pad: float = 0.5
	return (
		inner.position.x >= outer.position.x - pad
		and inner.position.y >= outer.position.y - pad
		and inner.end.x <= outer.end.x + pad
		and inner.end.y <= outer.end.y + pad
	)

# --- published tables and catalogs ---

## One boot for the published tables: misc rules and the catalog rows.

const TABLES_WIDTH: int = 6
const TABLES_HEIGHT: int = 3
const VIEWPORT := Vector2(1280.0, 720.0)
const MAP := Vector2(2816.0, 1848.0)
const ROLE_NAMES: Dictionary = {
	"explorer": "Explorer",
	"engineer": "Engineer",
	"builder": "Builder",
	"spy": "Spy",
	"merchant": "Merchant",
	"rail_builder": "Rail Builder",
}
const MANUFACTURED_ROWS: Dictionary = {
	"lumber": 60,
	"fabric": 80,
	"castIron": 160,
	"refinedSugar": 70,
	"cigars": 80,
	"furHats": 110,
	"steel": 170,
	"paper": 60,
	"bronze": 145,
	"garments": 160,
	"rum": 140,
}
const ROSTER: Array[String] = [
	"carrack",
	"fluyte",
	"sloop",
	"trader",
	"galleon",
	"indiaman",
	"frigate",
	"raider",
	"ship_of_the_line",
	"clipper",
	"merchant_steamship",
	"ironclad",
]

# --- test_misc_rules ---

func test_as_string_matches_semver_parts() -> void:
	assert_eq(GameVersion.as_string(), "0.1.0")

func test_is_compatible_with_matching_major() -> void:
	assert_true(GameVersion.is_compatible_with(GameVersion.MAJOR))

func test_is_compatible_with_rejects_other_major() -> void:
	assert_false(GameVersion.is_compatible_with(GameVersion.MAJOR + 1))

func test_menu_caption_is_version_only_when_identity_empty() -> void:
	assert_eq(BuildIdentity.GIT_SHA, "")
	assert_eq(BuildIdentity.COMMIT_UTC, "")
	assert_eq(GameVersion.menu_caption(), "version 0.1.0")
	assert_eq(
		GameVersion.format_menu_caption("0.1.0", "", "20261115-0804"),
		"version 0.1.0",
		"UTC alone is not enough for the build suffix"
	)

func test_menu_caption_appends_baked_sha_and_utc() -> void:
	assert_eq(
		GameVersion.format_menu_caption("0.1.0", "a1b2c3d", "20261115-0804"),
		"version 0.1.0 · a1b2c3d · 20261115-0804"
	)

func test_build_identity_is_baked_only_with_both_fields() -> void:
	assert_false(BuildIdentity.is_baked())

func test_turn_one_is_start_year() -> void:
	assert_eq(TurnTime.year_for_turn(1), 1500)

func test_two_years_per_turn_before_cutoff() -> void:
	assert_eq(TurnTime.year_for_turn(2), 1502)
	assert_eq(TurnTime.year_for_turn(51), 1600)

func test_cutoff_turn_is_1700() -> void:
	assert_eq(TurnTime.TURNS_BEFORE_CUTOFF, 100)
	assert_eq(TurnTime.year_for_turn(101), 1700)

func test_one_year_per_turn_after_cutoff() -> void:
	assert_eq(TurnTime.year_for_turn(102), 1701)
	assert_eq(TurnTime.year_for_turn(201), 1800)

func test_turn_zero_clamps_to_start_year() -> void:
	assert_eq(TurnTime.year_for_turn(0), 1500)
	assert_eq(TurnTime.year_for_turn(-4), 1500)

func test_label_formats_turn_and_year() -> void:
	assert_eq(TurnTime.label_for_turn(1), "Turn 1  ·  1500")
	assert_eq(TurnTime.label_for_turn(201), "Turn 201  ·  1800")

func test_every_cue_points_at_a_shipped_file() -> void:
	var names: Array[String] = AudioEvents.names()
	assert_gt(names.size(), 8)
	for event_name: String in names:
		var path: String = AudioEvents.path_for(event_name)
		assert_true(path.begins_with(AudioEvents.ROOT), event_name)
		assert_true(FileAccess.file_exists(path), path)

func test_unknown_events_have_no_cue() -> void:
	assert_false(AudioEvents.has("cannon_fire_9000"))
	assert_true(AudioEvents.cue("cannon_fire_9000").is_empty())
	assert_eq(AudioEvents.path_for("cannon_fire_9000"), "")

func test_trims_stay_inside_a_safe_mix_window() -> void:
	for event_name: String in AudioEvents.names():
		var cue: Dictionary = AudioEvents.cue(event_name)
		assert_between(float(cue.get("volume_db", 0.0)), -26.0, 0.0, event_name)
		assert_between(float(cue.get("pitch", 0.0)), 0.0, 0.1, event_name)

func test_names_are_sorted_and_unique() -> void:
	var names: Array[String] = AudioEvents.names()
	var sorted_copy: Array[String] = names.duplicate()
	sorted_copy.sort()
	assert_eq(names, sorted_copy)
	for event_name: String in names:
		assert_eq(names.count(event_name), 1, event_name)

func _seg(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b])

func test_trace_joins_connected_segments() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(10, 0), Vector2(10, 10)),
		_seg(Vector2(10, 10), Vector2(0, 10)),
	]
	var paths: Array[PackedVector2Array] = InkPaths.trace(segments)
	assert_eq(paths.size(), 1)
	assert_eq(paths[0].size(), 4)
	assert_eq(paths[0][0], Vector2(0, 0))
	assert_eq(paths[0][3], Vector2(0, 10))

func test_trace_keeps_disconnected_segments_apart() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(50, 50), Vector2(60, 50)),
	]
	assert_eq(InkPaths.trace(segments).size(), 2)

func test_chaikin_keeps_open_endpoints() -> void:
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)
	])
	var smoothed: PackedVector2Array = InkPaths.chaikin(points, 2, false)
	assert_eq(smoothed[0], Vector2(0, 0))
	assert_eq(smoothed[smoothed.size() - 1], Vector2(10, 10))
	assert_gt(smoothed.size(), points.size())

func test_chaikin_short_input_is_unchanged() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	assert_eq(InkPaths.chaikin(points, 2, false), points)

func test_smooth_segments_closes_a_loop() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(10, 0), Vector2(10, 10)),
		_seg(Vector2(10, 10), Vector2(0, 10)),
		_seg(Vector2(0, 10), Vector2(0, 0)),
	]
	var paths: Array[PackedVector2Array] = InkPaths.smooth_segments(segments, 1)
	assert_eq(paths.size(), 1)
	var path: PackedVector2Array = paths[0]
	assert_eq(path[0], path[path.size() - 1])
	assert_gt(path.size(), 8)

func test_smooth_segments_skips_single_points() -> void:
	var segments: Array[PackedVector2Array] = []
	assert_eq(InkPaths.smooth_segments(segments, 2).size(), 0)

## A grid boundary is traced dead straight; the hand pass is what makes it read
## as ink. It must move points, never run away, and stay deterministic.
func test_hand_wobbles_a_straight_run_within_bounds() -> void:
	var points := PackedVector2Array()
	for i in 40:
		points.append(Vector2(float(i) * 8.0, 0.0))
	var inked: PackedVector2Array = InkPaths.hand(points, 2.0, 1.4)
	assert_eq(inked.size(), points.size())
	var moved: int = 0
	for i in inked.size():
		var offset: float = absf(inked[i].y - points[i].y)
		assert_true(offset <= 2.0001, "the wobble stays inside its amplitude")
		if offset > 0.05:
			moved += 1
	assert_gt(moved, points.size() / 2, "most of a long straight run is displaced")
	assert_eq(InkPaths.hand(points, 2.0, 1.4), inked)

func test_hand_keeps_a_closed_loop_closed() -> void:
	var loop := PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 40), Vector2(0, 40), Vector2(0, 0),
	])
	var inked: PackedVector2Array = InkPaths.hand(loop, 3.0, 0.7)
	assert_eq(inked.size(), loop.size())
	assert_eq(inked[0], inked[inked.size() - 1])

func test_hand_leaves_short_or_flat_paths_alone() -> void:
	var short := PackedVector2Array([Vector2(0, 0), Vector2(1, 0)])
	assert_eq(InkPaths.hand(short, 2.0), short)
	var straight := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	assert_eq(InkPaths.hand(straight, 0.0), straight)

func _model_with_owners(owners: Array[int]) -> MapModel:
	var model := MapModel.new()
	model.setup(TABLES_WIDTH, TABLES_HEIGHT)
	var province_count: int = 3
	for province_id in province_count:
		var tiles: Array[Vector2i] = [
			Vector2i(province_id * 2, 1), Vector2i(province_id * 2 + 1, 1)
		]
		for tile: Vector2i in tiles:
			model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(tile.x, tile.y)] = province_id
		model.provinces.append(
			ProvinceState.create(
				province_id,
				"P%d" % province_id,
				tiles,
				Vector2(float(province_id) * 2.0 + 0.5, 1.5),
				tiles.size(),
				owners[province_id]
			)
		)
	return model

func test_borders_split_different_owners() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.has(0))
	assert_true(borders.has(1))
	assert_true(_has_edge(borders[0], Vector2(2, 1), Vector2(2, 2)), "missing 0|1 border")
	assert_true(_has_edge(borders[1], Vector2(4, 1), Vector2(4, 2)), "missing 1|0 border")

func test_no_border_inside_one_nation() -> void:
	var model: MapModel = _model_with_owners([0, 0, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.is_empty(), "same owner should draw no border")

func test_coastline_keeps_its_ink_and_no_country_line() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_false(_has_edge(borders[0], Vector2(0, 1), Vector2(0, 2)), "west coast got a country line")
	assert_false(_has_edge(borders[0], Vector2(0, 1), Vector2(1, 1)), "north coast got a country line")

func test_a_purchased_tile_draws_its_own_border() -> void:
	var model: MapModel = _model_with_owners([0, 0, 0])
	assert_true(model.purchase_tile(Vector2i(2, 1), 1))
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.has(0), "the seller keeps a border")
	assert_true(borders.has(1), "the buyer gets a border")
	assert_true(_has_edge(borders[1], Vector2(3, 1), Vector2(3, 2)), "missing deed edge")

func test_unclaimed_land_gets_no_border() -> void:
	var model: MapModel = _model_with_owners([MapModel.NO_ID, 0, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.is_empty(), "unclaimed land has no country border")

func test_missing_model_is_safe() -> void:
	assert_true(CountryBorders.build(null, 1.0).is_empty())

func test_unknown_land_draws_no_country_border() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var view := VisibilityModel.new()
	view.setup(model, 0)
	var charted: Dictionary = CountryBorders.build(model, 1.0, view)
	assert_true(charted.has(0), "fogged land still carries its political border")
	view.levels.fill(VisibilityModel.Level.UNKNOWN)
	var uncharted: Dictionary = CountryBorders.build(model, 1.0, view)
	assert_true(uncharted.is_empty(), "unknown land stays off the political map")

func _has_edge(segments: Array, a: Vector2, b: Vector2) -> bool:
	for segment: PackedVector2Array in segments:
		if segment.size() != 2:
			continue
		if segment[0] == a and segment[1] == b:
			return true
		if segment[0] == b and segment[1] == a:
			return true
	return false

func test_clamp_center_keeps_view_inside_map() -> void:
	var clamped: Vector2 = CameraMath.clamp_center(Vector2(-500, -500), 1.0, VIEWPORT, MAP)
	assert_almost_eq(clamped.x, VIEWPORT.x * 0.5, 0.01)
	assert_almost_eq(clamped.y, VIEWPORT.y * 0.5, 0.01)

	clamped = CameraMath.clamp_center(Vector2(99999, 99999), 1.0, VIEWPORT, MAP)
	assert_almost_eq(clamped.x, MAP.x - VIEWPORT.x * 0.5, 0.01)
	assert_almost_eq(clamped.y, MAP.y - VIEWPORT.y * 0.5, 0.01)

func test_clamp_center_allows_interior_positions() -> void:
	var target := Vector2(1400.0, 900.0)
	assert_eq(CameraMath.clamp_center(target, 1.0, VIEWPORT, MAP), target)

func test_clamp_center_centres_small_map() -> void:
	var small := Vector2(400.0, 200.0)
	var clamped: Vector2 = CameraMath.clamp_center(Vector2(0, 0), 1.0, VIEWPORT, small)
	assert_almost_eq(clamped.x, 200.0, 0.01)
	assert_almost_eq(clamped.y, 100.0, 0.01)

## A chart paints water past its tile grid: the camera may compose into that
## margin, which is what lets a phone banner cover sea instead of land.
func test_clamp_view_composes_into_the_painted_margin() -> void:
	var frame := Rect2(Vector2(-1400.0, -1400.0), MAP + Vector2(2800.0, 2800.0))
	var margin_point := Vector2(-300.0, -200.0)
	assert_eq(
		CameraMath.clamp_view(margin_point, 1.0, VIEWPORT, frame),
		margin_point,
		"the painted water past the grid is reachable"
	)
	var clamped: Vector2 = CameraMath.clamp_view(Vector2(-9999, -9999), 1.0, VIEWPORT, frame)
	assert_almost_eq(clamped.x, frame.position.x + VIEWPORT.x * 0.5, 0.01)
	assert_almost_eq(clamped.y, frame.position.y + VIEWPORT.y * 0.5, 0.01)

## The chart is composed in the strip the page's chrome leaves free, so the point
## the player is choosing between sits in the middle of that strip — not under
## the banner at the top of the screen.
func test_compose_center_puts_the_point_in_the_middle_of_the_band() -> void:
	var band := Rect2(0.0, 90.0, VIEWPORT.x, 260.0)
	var frame := Rect2(Vector2.ZERO, MAP)
	var point := Vector2(1400.0, 900.0)
	var center: Vector2 = CameraMath.compose_center(point, 1.0, VIEWPORT, band, frame)
	var screen: Vector2 = CameraMath.world_to_screen(center, 1.0, point, VIEWPORT)
	assert_almost_eq(screen.x, band.get_center().x, 0.01)
	assert_almost_eq(screen.y, band.get_center().y, 0.01)

func test_zoom_anchor_keeps_world_point_under_cursor() -> void:
	var center := Vector2(1400.0, 900.0)
	var anchor := Vector2(1000.0, 200.0)
	var before: Vector2 = CameraMath.screen_to_world(center, 0.6, anchor, VIEWPORT)
	var moved: Vector2 = CameraMath.zoom_anchor(center, 0.6, 1.2, anchor, VIEWPORT)
	var after: Vector2 = CameraMath.screen_to_world(moved, 1.2, anchor, VIEWPORT)
	assert_almost_eq(after.x, before.x, 0.01)
	assert_almost_eq(after.y, before.y, 0.01)

func test_fit_zoom_fits_whole_map() -> void:
	var zoom: float = CameraMath.fit_zoom(VIEWPORT, MAP)
	var expected: float = minf(VIEWPORT.x / MAP.x, VIEWPORT.y / MAP.y)
	assert_almost_eq(zoom, expected, 0.0001)

func test_fit_cover_covers_the_viewport() -> void:
	var zoom: float = CameraMath.fit_cover(VIEWPORT, MAP)
	assert_almost_eq(zoom, maxf(VIEWPORT.x / MAP.x, VIEWPORT.y / MAP.y), 0.0001)
	var tall := Vector2(720.0, 1600.0)
	assert_almost_eq(CameraMath.fit_cover(tall, MAP), 1600.0 / MAP.y, 0.0001)

func test_fit_cover_handles_zero_map() -> void:
	assert_eq(CameraMath.fit_cover(VIEWPORT, Vector2.ZERO), 1.0)

func test_fit_zoom_handles_zero_map() -> void:
	assert_eq(CameraMath.fit_zoom(VIEWPORT, Vector2.ZERO), 1.0)

func test_screen_world_round_trip() -> void:
	var world := Vector2(1234.0, 567.0)
	var screen: Vector2 = CameraMath.world_to_screen(Vector2(1000, 800), 1.7, world, VIEWPORT)
	var back: Vector2 = CameraMath.screen_to_world(Vector2(1000, 800), 1.7, screen, VIEWPORT)
	assert_almost_eq(back.x, world.x, 0.01)
	assert_almost_eq(back.y, world.y, 0.01)

func test_thirty_old_world_provinces_are_not_enough() -> void:
	var world: WorldMap = _world({FactionCatalog.PLAYER_FACTION: 30})
	assert_null(VictoryRules.evaluate(world, 4))

func test_thirty_one_old_world_provinces_win() -> void:
	var world: WorldMap = _world({FactionCatalog.PLAYER_FACTION: 31})
	var victory: VictoryState = VictoryRules.evaluate(world, 7)
	assert_not_null(victory)
	assert_eq(victory.winner_player_id, FactionCatalog.PLAYER_FACTION)
	assert_eq(victory.type, VictoryState.Type.MILITARY)
	assert_eq(victory.turn_number, 7)
	assert_eq(victory.type_label(), "Military victory")
	assert_true(victory.won_by(FactionCatalog.PLAYER_FACTION))
	assert_eq(
		victory.summary(),
		"Spain — Military victory, turn 7",
		"the record names winner, type and turn"
	)

func test_only_great_powers_are_eligible() -> void:
	var world: WorldMap = _world({6: 40})
	assert_null(VictoryRules.evaluate(world, 3), "a Minor Nation never wins")

func test_shared_threshold_resolves_by_the_smallest_player_id() -> void:
	# Two qualified crowns: the smallest player id wins even though the other
	# holds more provinces (wiki: victory § Tie-breaking).
	var world: WorldMap = _world({4: 40, 2: 31})
	var victory: VictoryState = VictoryRules.evaluate(world, 3)
	assert_not_null(victory)
	assert_eq(victory.winner_player_id, 2)

func test_new_world_provinces_do_not_count() -> void:
	var world: WorldMap = _old_and_new(
		{FactionCatalog.PLAYER_FACTION: 10}, {FactionCatalog.PLAYER_FACTION: 30}
	)
	assert_null(VictoryRules.evaluate(world, 3))

func test_an_existing_victory_is_never_overwritten() -> void:
	var first: VictoryState = VictoryRules.evaluate(_world({1: 31}), 3)
	var later: WorldMap = _world({2: 40})
	assert_eq(VictoryRules.resolve(first, later, 9), first)

func test_qualified_crowns_are_ordered_and_filtered() -> void:
	var world: WorldMap = _world({4: 31, 1: 31, 3: 30})
	var ids: Array[int] = VictoryRules.qualified(world)
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], 1)
	assert_eq(ids[1], 4)

func _world(counts: Dictionary) -> WorldMap:
	return _old_and_new(counts, {})

func _old_and_new(old_world: Dictionary, new_world: Dictionary) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(_model(old_world, FactionCatalog.OLD_WORLD))
	world.add_region(_model(new_world, FactionCatalog.NEW_WORLD))
	return world

func _model(counts: Dictionary, region_id: int) -> MapModel:
	var model := MapModel.new()
	model.setup(1, 1)
	model.region_id = region_id
	model.faction_ids = FactionCatalog.ids_in_region(region_id)
	var next_id: int = 0
	for faction_id: int in counts.keys():
		for _index in int(counts[faction_id]):
			var tiles: Array[Vector2i] = []
			model.provinces.append(
				ProvinceState.create(
					next_id, "Province %d" % next_id, tiles, Vector2.ZERO, 1, faction_id
				)
			)
			next_id += 1
	return model

# --- test_catalogs ---

func test_every_great_power_fields_exactly_one_default_leader() -> void:
	var seen: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		var keys: Array[String] = LeaderCatalog.keys_for(faction)
		assert_eq(keys.size(), 1, "crown %d fields one leader variant" % faction)
		assert_eq(LeaderCatalog.default_key(faction), keys[0], "first variant is the default")
		var key: String = keys[0]
		assert_false(seen.has(key), "leader key %s is not shared" % key)
		seen[key] = true
		assert_true(LeaderCatalog.label(key) != "")

func test_minors_tribes_and_unknown_factions_reserve_the_neutral_leader() -> void:
	for faction: int in FactionCatalog.minor_ids() + FactionCatalog.tribe_ids():
		assert_eq(LeaderCatalog.default_key(faction), LeaderCatalog.DEFAULT_KEY)
		assert_true(LeaderCatalog.keys_for(faction).is_empty())
	assert_eq(LeaderCatalog.default_key(-1), LeaderCatalog.DEFAULT_KEY)

func test_bonus_table_matches_the_documented_multipliers() -> void:
	# Land is published per side: Napoleon both, Gustavus attacking, Frederick
	# defending (wiki: leader-bonuses § Bonus Table).
	assert_almost_eq(LeaderCatalog.land_multiplier("napoleon", false), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("napoleon", true), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("gustavus", false), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("gustavus", true), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("frederick", true), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("frederick", false), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("reserve", true), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("", false), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("isabella", false), 1.0, 0.001)
	assert_eq(LeaderCatalog.land_percent("napoleon"), 25)
	assert_eq(LeaderCatalog.land_percent("isabella"), 0)


## One primary bonus per key: each non-land key publishes exactly its own domain
## and nothing else (wiki: leader-bonuses § Design notes).
func test_each_non_land_key_publishes_exactly_its_own_domain() -> void:
	assert_almost_eq(LeaderCatalog.naval_multiplier("de_ruyter"), 1.15, 0.001)
	for key: String in [
		"napoleon", "gustavus", "frederick", "isabella", "henry", "victoria", "reserve"
	]:
		assert_almost_eq(
			LeaderCatalog.naval_multiplier(key), 1.0, 0.001, "%s has no naval row" % key
		)
	assert_almost_eq(LeaderCatalog.first_contact_score("isabella"), 60.0, 0.001)
	assert_almost_eq(
		LeaderCatalog.first_contact_score("henry"), DiplomacyCatalog.INITIAL_SCORE, 0.001
	)
	assert_eq(LeaderCatalog.coastal_rings("henry"), 1)
	assert_eq(LeaderCatalog.coastal_rings("isabella"), 0)
	assert_almost_eq(LeaderCatalog.funding_multiplier("victoria"), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.funding_multiplier("henry"), 1.0, 0.001)


func test_bonus_labels_name_the_real_effect() -> void:
	assert_true(LeaderCatalog.bonus_label("isabella").contains("first contact"))
	assert_true(LeaderCatalog.bonus_label("henry").contains("coastal"))
	assert_true(LeaderCatalog.bonus_label("de_ruyter").contains("naval"))
	assert_true(LeaderCatalog.bonus_label("victoria").contains("research"))
	assert_true(LeaderCatalog.bonus_label("gustavus").contains("attacking"))
	assert_true(LeaderCatalog.bonus_label("frederick").contains("defending"))
	assert_eq(LeaderCatalog.bonus_label("reserve"), "no bonus",
		"a key with no row never reads as a missing land bonus")

func test_variant_ids_match_exactly_first_then_by_substring() -> void:
	assert_almost_eq(LeaderCatalog.land_multiplier("france_napoleon_leader", false), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("Prussia_Frederick_Leader", true), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("unknown_court", false), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.naval_multiplier("dutch_michiel_de_ruyter_leader"), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.funding_multiplier("ENG_victoria_leader"), 1.15, 0.001)
	assert_eq(LeaderCatalog.coastal_rings("POR_henry_leader"), 1)

func test_roster_assigns_the_choice_to_the_human_crown_only() -> void:
	var roster: Dictionary = LeaderCatalog.roster(2, "napoleon")
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(roster.has(faction), "crown %d has a leader" % faction)
	assert_eq(roster[2], "napoleon")
	assert_eq(roster[0], LeaderCatalog.default_key(0), "rivals keep their config leader")
	var refused: Dictionary = LeaderCatalog.roster(2, "isabella")
	assert_eq(refused[2], "napoleon", "a crown cannot field another crown's leader")

func test_saved_map_keeps_known_keys_and_backfills_missing_crowns() -> void:
	var saved: Dictionary = {0: "isabella", 2: "napoleon", 3: "invented_leader", 99: "napoleon"}
	var restored: Dictionary = LeaderCatalog.from_saved(saved)
	assert_eq(restored[0], "isabella")
	assert_eq(restored[2], "napoleon")
	assert_eq(restored[3], LeaderCatalog.default_key(3), "unknown keys are dropped")
	assert_false(restored.has(99), "non-Great-Power rows are ignored")
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(restored.has(faction), "crown %d backfilled" % faction)

func test_ai_personality_reads_the_same_default_leader() -> void:
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(AiPersonality.leader_for(faction), LeaderCatalog.default_key(faction))

func test_default_roster_matches_the_configured_counts() -> void:
	assert_eq(FactionCatalog.great_power_ids().size(), 6)
	assert_eq(FactionCatalog.minor_ids().size(), 6)
	assert_eq(FactionCatalog.tribe_ids().size(), 10)
	assert_eq(FactionCatalog.count(), 22)

func test_great_power_colours_follow_gdd_09() -> void:
	## wiki: naming § Default map colour id — GDD 09 RGB per semantic id.
	assert_eq(FactionCatalog.color_of(0), Color8(220, 180, 60), "Spain is yellow")
	assert_eq(FactionCatalog.color_of(1), Color8(180, 80, 80), "England is red")
	assert_eq(FactionCatalog.color_of(2), Color8(80, 140, 200), "France is dark blue")
	assert_eq(FactionCatalog.color_of(3), Color8(90, 160, 90), "Portugal is green")
	assert_eq(
		FactionCatalog.color_of(4),
		Color8(220, 140, 100),
		"United Provinces uses the netherlands orange"
	)
	assert_eq(FactionCatalog.color_of(5), Color8(100, 120, 200), "Sweden is light blue")

func test_ids_are_unique_and_resolvable() -> void:
	var seen: Dictionary = {}
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_false(seen.has(id), "duplicate faction id %d" % id)
		seen[id] = true
		assert_eq(int(FactionCatalog.get_faction(id)["id"]), id)
		assert_true(FactionCatalog.name_of(id) != "")

func test_only_great_powers_win_and_submit_orders() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_true(FactionCatalog.can_win(id))
		assert_true(FactionCatalog.submits_orders(id))
		assert_true(FactionCatalog.has_navy(id))
	for id: int in FactionCatalog.minor_ids() + FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.can_win(id))
		assert_false(FactionCatalog.submits_orders(id))
		assert_false(FactionCatalog.has_navy(id))

func test_region_ownership_matches_faction_type() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))
	for id: int in FactionCatalog.minor_ids():
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_false(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))
	for id: int in FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))

func test_minors_have_military_parity_but_tribes_do_not() -> void:
	for id: int in FactionCatalog.minor_ids():
		assert_true(FactionCatalog.has_military_parity(id))
	for id: int in FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.has_military_parity(id))

func test_unknown_ids_fall_back_to_unclaimed() -> void:
	assert_eq(FactionCatalog.name_of(-1), "Unclaimed")
	assert_eq(FactionCatalog.type_of(-1), -1)
	assert_false(FactionCatalog.can_own_region(-1, FactionCatalog.OLD_WORLD))
	assert_false(FactionCatalog.has_faction(999))

func test_region_labels_and_keys_are_defined() -> void:
	assert_eq(FactionCatalog.region_label(FactionCatalog.OLD_WORLD), "Old World")
	assert_eq(FactionCatalog.region_label(FactionCatalog.NEW_WORLD), "New World")
	assert_eq(FactionCatalog.region_key(FactionCatalog.NEW_WORLD), "new_world")
	assert_eq(FactionCatalog.ids_in_region(FactionCatalog.NEW_WORLD), FactionCatalog.tribe_ids())

func test_names_are_indexed_by_faction_id() -> void:
	var names: Array[String] = FactionCatalog.names()
	assert_eq(names.size(), FactionCatalog.count())
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_eq(names[id], FactionCatalog.name_of(id))

func test_catalog_lists_every_regiment_once() -> void:
	var ids: Array[String] = RegimentCatalog.ids()
	assert_eq(ids.size(), 29)
	var seen: Dictionary = {}
	for type_id: String in ids:
		assert_false(seen.has(type_id), "duplicate regiment %s" % type_id)
		seen[type_id] = true
		assert_eq(RegimentCatalog.display_name(type_id), String(RegimentCatalog.row(type_id)["name"]))

func test_tactical_stats_match_the_wiki_table() -> void:
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpn"), 0)
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpm"), 3)
	assert_eq(RegimentCatalog.stat("guards", "fpn"), 12)
	assert_eq(RegimentCatalog.stat("guards", "fpm"), 10)
	assert_eq(RegimentCatalog.stat("siege_guns", "rng"), 12)
	assert_eq(RegimentCatalog.stat("carbine_cavalry", "mvr"), 9)
	assert_eq(RegimentCatalog.era("guards"), 4)
	assert_eq(RegimentCatalog.era("culverin"), 1)

func test_categories_drive_cavalry_and_infantry_rules() -> void:
	assert_true(RegimentCatalog.is_cavalry("squires"))
	assert_true(RegimentCatalog.is_cavalry("cuirassiers"))
	assert_false(RegimentCatalog.is_cavalry("guards"))
	assert_true(RegimentCatalog.is_artillery("royal_artillery"))
	assert_false(RegimentCatalog.is_infantry("field_artillery"))
	assert_true(RegimentCatalog.is_infantry("bowmen"))
	assert_true(RegimentCatalog.is_infantry("peasant_levies"))

## Regiment detail: the dossier line names the category, the tactical stats and
## the food bill; the despatch text groups losses by type, name-ordered.
func test_regiment_detail_lines_carry_stats_and_tally_losses() -> void:
	assert_eq(RegimentCatalog.category_name("guards"), "Heavy infantry")
	assert_eq(RegimentCatalog.category_name("culverin"), "Heavy artillery")
	assert_eq(RegimentCatalog.category_name("peasant_levies"), "Light infantry")
	assert_eq(RegimentCatalog.category_name("pikemen"), "Regular infantry")
	assert_eq(RegimentCatalog.category_name("bowmen"), "Bowmen")
	assert_eq(RegimentCatalog.category_name("squires"), "Light cavalry")
	assert_eq(RegimentCatalog.category_name("knights"), "Spear cavalry")
	assert_eq(RegimentCatalog.category_name("harquebusiers"), "Heavy cavalry")
	assert_eq(RegimentCatalog.category_name("horse_artillery"), "Light artillery")
	assert_eq(
		RegimentCatalog.detail_line("guards"),
		"Heavy infantry · FPN 12 · FPM 10 · RNG 6 · DEF 6 · MVR 4 · 3 food"
	)
	assert_eq(RegimentCatalog.detail_text({"guards": 3}), "3 Guards")
	assert_eq(RegimentCatalog.detail_text({"guards": 1}), "Guards")
	assert_eq(
		RegimentCatalog.detail_text({"pikemen": 3, "culverin": 1}),
		"Culverin · 3 Pikemen"
	)
	assert_eq(RegimentCatalog.detail_text({}), "")

func test_treasury_costs_follow_the_canonical_scale() -> void:
	assert_eq(RegimentCatalog.treasury_cost("peasant_levies"), 2000)
	assert_eq(RegimentCatalog.treasury_cost("arquebusiers"), 5000)
	assert_eq(RegimentCatalog.treasury_cost("siege_guns"), 22000)

func test_food_upkeep_keeps_cavalry_and_artillery_highest() -> void:
	assert_eq(RegimentCatalog.food_upkeep("peasant_levies"), 1)
	assert_eq(RegimentCatalog.food_upkeep("pikemen"), 2)
	assert_eq(RegimentCatalog.food_upkeep("guards"), 3)
	assert_eq(RegimentCatalog.food_upkeep("squires"), 3)
	assert_eq(RegimentCatalog.food_upkeep("culverin"), 3)

func test_unknown_types_fall_back_to_peasant_levies() -> void:
	assert_eq(RegimentCatalog.normalize("dragoons"), RegimentCatalog.DEFAULT_TYPE)
	assert_eq(RegimentCatalog.display_name("dragoons"), "Regiment")
	assert_false(RegimentCatalog.has_type("dragoons"))

func test_garrison_recovery_uses_the_most_advanced_infantry_for_the_era() -> void:
	assert_eq(RegimentCatalog.garrison_type_for(4), "guards")
	assert_eq(RegimentCatalog.garrison_type_for(1), "arquebusiers")
	assert_eq(RegimentCatalog.garrison_type_for(9), RegimentCatalog.DEFAULT_TYPE)

func test_catalog_holds_the_full_wiki_tree() -> void:
	assert_eq(TechCatalog.TECHS.size(), TechAudit.EXPECTED_COUNT)
	assert_eq(TechCatalog.ids().size(), TechCatalog.TECHS.size())
	assert_eq(TechAudit.validate(), [] as Array[String])
	assert_true(TechCatalog.roots().size() >= 7, "several starting techs")

func test_costs_follow_the_era_formula() -> void:
	var costs: Dictionary = {}
	for tech_id: String in TechCatalog.ids():
		costs[TechCatalog.cost(tech_id)] = true
	assert_eq(costs.size(), 4)
	assert_true(costs.has(1800))
	assert_true(costs.has(2400))
	assert_true(costs.has(3000))
	assert_true(costs.has(3600))
	assert_eq(TechCatalog.cost("crop_rotation"), 1800)
	assert_eq(TechCatalog.cost("saw_mill"), 1800)
	assert_eq(TechCatalog.cost("wind_saw_mill"), 2400)
	assert_eq(TechCatalog.cost("circular_saw"), 3000)
	assert_eq(TechCatalog.cost("safety_lamp"), 3600)

func test_prerequisites_cross_categories() -> void:
	assert_has(TechCatalog.prerequisites("circular_saw"), "university")
	assert_has(TechCatalog.prerequisites("dynamite"), "banking")
	assert_has(TechCatalog.prerequisites("dynamite"), "explosives")
	assert_has(TechCatalog.prerequisites("large_tobacco_plantations"), "seed_drill")
	assert_has(TechCatalog.dependents("university"), "advanced_hull_design")
	assert_eq(TechCatalog.prerequisites("crop_rotation"), [] as Array[String])

func test_extraction_caps_default_to_one() -> void:
	assert_eq(TechCatalog.extraction_caps({}), {})
	assert_eq(TechCatalog.cap_for("grain", {}), 1)
	assert_eq(TechCatalog.cap_for("timber", {"land_enclosure": true}), 1)
	assert_eq(TechCatalog.cap_for("horses", {"crop_rotation": true}), 1)

func test_gathering_techs_lift_the_cap_per_resource() -> void:
	var unlocked: Dictionary = {"land_enclosure": true}
	assert_eq(TechCatalog.cap_for("grain", unlocked), 2)
	unlocked["seed_drill"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 3)
	unlocked["moldboard_plow"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 4)
	assert_eq(TechCatalog.extraction_caps(unlocked), {"grain": 4})

func test_cap_chains_stop_at_the_wiki_exceptions() -> void:
	var wool: Dictionary = {"sheep_ranching": true, "scientific_sheep_breeding": true}
	assert_eq(TechCatalog.cap_for("wool", wool), TechCatalog.CAP_EXCEPTIONS["wool"])
	assert_eq(TechCatalog.CAP_EXCEPTIONS["horses"], 1)
	var iron: Dictionary = {
		"iron_mining": true, "steam_in_mining": true, "industrial_iron_mining": true,
	}
	assert_eq(TechCatalog.cap_for("iron", iron), 4)
	var copper: Dictionary = {
		"copper_and_tin_mining": true, "large_copper_and_tin_mines": true,
		"efficient_extraction_of_copper_and_tin": true,
	}
	assert_eq(TechCatalog.cap_for("copper", copper), 4)
	assert_eq(TechCatalog.cap_for("tin", copper), 4)

func test_discovery_techs_name_their_resources() -> void:
	assert_eq(TechCatalog.discovery_resources("discovery_of_sugar"), ["sugarCane"])
	assert_eq(
		TechCatalog.discovery_resources("discovery_of_gold_or_silver"),
		["gold", "silver"]
	)
	assert_eq(TechCatalog.discovery_resources("saw_mill"), [] as Array[String])
	assert_eq(TechCatalog.display_name("discovery_of_sugar"), "Discovery of Sugar")

## Every resource the map can place carries its published base name (wiki:
## extraction-and-improvements § Improvement Naming): minerals read Mine, the
## crops their own work, and no index falls back to the generic "Improvement".
func test_every_placeable_resource_has_its_published_improvement() -> void:
	var names: Dictionary = {
		"timber": "Lumber camp", "iron": "Mine", "coal": "Mine", "gold": "Mine",
		"grain": "Farm", "wool": "Pasture", "horses": "Ranch", "meat": "Ranch",
		"tin": "Mine", "copper": "Mine", "silver": "Mine", "gems": "Mine",
		"diamonds": "Mine", "sugarCane": "Plantation", "tobacco": "Plantation",
		"cotton": "Plantation", "furs": "Fur post", "spices": "Plantation",
	}
	var table: Array[Dictionary] = MapGenerator.resource_table()
	assert_eq(table.size(), names.size())
	for index in table.size():
		var commodity: String = String(table[index]["commodity"])
		assert_true(names.has(commodity), "unpublished resource %s" % commodity)
		assert_eq(ImprovementCatalog.base_name(index), String(names[commodity]), commodity)
		assert_eq(
			ImprovementCatalog.display_name(index, 2),
			"%s (L2)" % String(names[commodity]),
			commodity
		)

func test_effect_text_uses_the_fixed_phrases() -> void:
	assert_true(TechCatalog.effect_text("saw_mill").contains("Improves:"))
	assert_true(TechCatalog.effect_text("saw_mill").to_lower().contains("timber"))
	assert_true(TechCatalog.effect_text("land_enclosure").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("discovery_of_sugar").contains("Enables:"))
	assert_true(TechCatalog.effect_text("clipper_ships").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("crop_rotation").contains("Unlocks:"))

func test_catalog_covers_all_six_wiki_types() -> void:
	assert_eq(CivilianCatalog.TYPES.size(), 6)
	assert_eq(CivilianCatalog.ORDER.size(), 6)
	for type_id: String in CivilianCatalog.ORDER:
		assert_true(CivilianCatalog.known(type_id), type_id)
		assert_eq(CivilianCatalog.display_name(type_id), String(ROLE_NAMES[type_id]))

func test_training_costs_match_the_wiki() -> void:
	for type_id: String in ["explorer", "engineer", "builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 1000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 2, type_id)
	for type_id: String in ["spy", "merchant", "rail_builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 2000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 4, type_id)

func test_the_playable_roster_includes_the_spy_merchant_and_rail_builder() -> void:
	assert_eq(
		CivilianCatalog.playable_types(),
		["explorer", "engineer", "builder", "spy", "merchant", "rail_builder"]
	)
	assert_true(CivilianCatalog.is_implemented("spy"), "Spy")
	for type_id: String in CivilianCatalog.playable_types():
		assert_true(CivilianCatalog.is_implemented(type_id), type_id)
		assert_eq(CivilianCatalog.deferred_reason(type_id), "")

func test_tech_gated_types_unlock_on_research() -> void:
	assert_eq(CivilianCatalog.unlock_tech("explorer"), "")
	assert_eq(CivilianCatalog.unlock_tech("rail_builder"), "early_steam_engine")
	assert_eq(CivilianCatalog.unlock_tech("merchant"), "merchant_companies")
	assert_true(CivilianCatalog.is_unlocked("explorer"))
	assert_false(CivilianCatalog.is_unlocked("rail_builder"))
	assert_true(CivilianCatalog.is_unlocked("rail_builder", {"early_steam_engine": true}))

func test_work_lists_match_the_wiki_table() -> void:
	assert_eq(CivilianCatalog.works("explorer"), ["explore", "prospect"])
	assert_eq(CivilianCatalog.works("builder"), ["build_improvement", "upgrade_town"])
	assert_eq(
		CivilianCatalog.works("engineer"),
		["build_road", "build_port", "build_fort", "build_hospital"],
		"a fort and a hospital are the engineer's province works"
	)
	assert_eq(CivilianCatalog.works("spy"), ["counter_spy"], "screen plus passive tradecraft")
	assert_eq(CivilianCatalog.works("merchant"), ["purchase_land"])
	assert_eq(CivilianCatalog.works("rail_builder"), ["build_rail"])

func test_affordability_needs_cash_and_paper() -> void:
	assert_true(CivilianCatalog.can_afford("explorer", 1000, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 999, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 1000, 1))
	assert_false(CivilianCatalog.can_afford("merchant", 1999, 4))

func test_training_cost_text_reads_as_a_purse_line() -> void:
	assert_eq(CivilianCatalog.training_cost_text("explorer"), "1,000 cash + 2 paper")
	assert_eq(CivilianCatalog.training_cost_text("merchant"), "2,000 cash + 4 paper")

func test_money_text_groups_and_signs_one_way() -> void:
	assert_eq(MoneyText.thousands(0), "0")
	assert_eq(MoneyText.thousands(999), "999")
	assert_eq(MoneyText.thousands(1000), "1,000")
	assert_eq(MoneyText.thousands(1234567), "1,234,567")
	assert_eq(MoneyText.thousands(-1234), "-1,234")
	assert_eq(MoneyText.thousands(-100), "-100")
	assert_eq(MoneyText.money(500), "£500")
	assert_eq(MoneyText.money(12500), "£12,500")
	assert_eq(MoneyText.ducats(8000), "8,000 ducats")

func test_money_text_cost_line_names_gold_materials_and_the_worker() -> void:
	assert_eq(
		MoneyText.cost_line(8000, {"lumber": 2, "fabric": 1}, 1),
		"8,000 ducats · 2 Lumber · 1 Fabric · 1 worker"
	)
	assert_eq(
		MoneyText.cost_line(120, {}, 0),
		"120 ducats",
		"a line that spends no headcount names no worker"
	)
	assert_eq(MoneyText.cost_line(2400, {}, 2), "2,400 ducats · 2 workers")

func test_unknown_types_fall_back_to_a_known_row() -> void:
	assert_false(CivilianCatalog.known("privateer"))
	assert_true(CivilianCatalog.known(CivilianCatalog.normalize("privateer")))
	assert_eq(CivilianCatalog.normalize("privateer"), CivilianCatalog.DEFAULT_TYPE)

func test_catalog_covers_the_wiki_lists() -> void:
	assert_eq(CommodityCatalog.FOOD, ["grain", "meat"] as Array[String])
	assert_eq(CommodityCatalog.RAW.size(), 11)
	# Two second-stage rows join the catalogue: garments from fabric and rum
	# from refined sugar (wiki: production-recipes § Town-works gates;
	# DR-20261116-04).
	assert_eq(CommodityCatalog.MANUFACTURED.size(), 11)
	assert_eq(CommodityCatalog.LUXURY.size(), 0)
	assert_eq(
		CommodityCatalog.RICHES,
		["gold", "silver", "gems", "diamonds", "spices"] as Array[String]
	)
	assert_eq(CommodityCatalog.ADVANCED, [] as Array[String])
	assert_eq(CommodityCatalog.all_ids().size(), 29)

func test_categories_match_the_table() -> void:
	assert_eq(CommodityCatalog.category_of("grain"), CommodityCatalog.Category.FOOD)
	assert_eq(CommodityCatalog.category_of("timber"), CommodityCatalog.Category.RAW)
	assert_eq(CommodityCatalog.category_of("castIron"), CommodityCatalog.Category.MANUFACTURED)
	assert_eq(CommodityCatalog.category_of("gold"), CommodityCatalog.Category.RICHES)
	assert_eq(CommodityCatalog.category_of("spices"), CommodityCatalog.Category.RICHES)
	assert_eq(CommodityCatalog.category_of("silk"), CommodityCatalog.NO_CATEGORY)
	assert_false(CommodityCatalog.known("silk"))
	assert_eq(CommodityCatalog.category_label(CommodityCatalog.Category.RAW), "Raw materials")

func test_tradeable_excludes_only_riches() -> void:
	assert_true(CommodityCatalog.is_tradeable("timber"))
	assert_true(CommodityCatalog.is_tradeable("lumber"))
	assert_true(CommodityCatalog.is_tradeable("grain"))
	# Spices is a rich: not traded; clears to treasury at 50 (Imperialism II;
	# wiki: world-market § Tradeable commodities; DR-20261113-13).
	assert_false(CommodityCatalog.is_tradeable("spices"))
	assert_false(CommodityCatalog.is_tradeable("gold"))
	assert_false(CommodityCatalog.is_tradeable("diamonds"))
	assert_false(CommodityCatalog.is_tradeable("silk"))
	var tradeable: int = 0
	for id: String in CommodityCatalog.all_ids():
		if CommodityCatalog.is_tradeable(id):
			tradeable += 1
	assert_eq(tradeable, 24)

func test_manufactured_prices_are_break_even() -> void:
	for id: String in MANUFACTURED_ROWS.keys():
		assert_eq(CommodityCatalog.base_price(id), int(MANUFACTURED_ROWS[id]), id)

func test_raw_and_riches_prices_match_the_rules() -> void:
	assert_eq(CommodityCatalog.base_price("grain"), 50)
	assert_eq(CommodityCatalog.base_price("timber"), 30)
	assert_eq(CommodityCatalog.base_price("iron"), 80)
	assert_eq(CommodityCatalog.base_price("coal"), 90)
	assert_eq(CommodityCatalog.base_price("spices"), 50)
	assert_eq(CommodityCatalog.base_price("gold"), 166)
	assert_eq(CommodityCatalog.base_price("diamonds"), 500)
	assert_eq(CommodityCatalog.base_price("silk"), 0)

func test_labels_are_readable_and_stable() -> void:
	assert_eq(CommodityCatalog.label("grain"), "Grain")
	assert_eq(CommodityCatalog.label("castIron"), "Cast Iron")
	assert_eq(CommodityCatalog.label("sugarCane"), "Sugar Cane")
	assert_eq(CommodityCatalog.label("furHats"), "Fur Hats")

func test_ids_in_returns_a_copy_of_the_category() -> void:
	var food: Array[String] = CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD)
	assert_eq(food, ["grain", "meat"] as Array[String])
	food.append("silk")
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD).size(), 2)
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.LUXURY).size(), 0)

func test_ship_stats_cover_the_whole_roster() -> void:
	assert_eq(ShipStats.STATS.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipStats.known(ship_id), ship_id)

func test_frozen_merchant_rows_match_the_wiki() -> void:
	var carrack: Dictionary = ShipStats.entry("carrack")
	assert_eq(int(carrack["frp"]), 2)
	assert_eq(int(carrack["rng"]), 1)
	assert_eq(int(carrack["arm"]), 1)
	assert_eq(int(carrack["hull"]), 2)
	assert_eq(int(carrack["mv"]), 2)
	assert_eq(int(carrack["cargo"]), 3)
	var fluyte: Dictionary = ShipStats.entry("fluyte")
	assert_eq(int(fluyte["hull"]), 1)
	assert_eq(int(fluyte["flee"]), 3)
	assert_eq(int(fluyte["cargo"]), 4)

func test_line_and_steam_rows_match_the_wiki() -> void:
	var line: Dictionary = ShipStats.entry("ship_of_the_line")
	assert_eq(int(line["frp"]), 6)
	assert_eq(int(line["hull"]), 8)
	assert_eq(int(line["intercept"]), 2)
	var ironclad: Dictionary = ShipStats.entry("ironclad")
	assert_eq(int(ironclad["arm"]), 8)
	assert_eq(int(ironclad["cargo"]), 0)
	var steamer: Dictionary = ShipStats.entry("merchant_steamship")
	assert_eq(int(steamer["cargo"]), 9)
	assert_eq(int(steamer["arm"]), 3)

func test_role_split_and_cargo_holds() -> void:
	assert_true(ShipStats.is_warship("sloop"))
	assert_true(ShipStats.is_warship("ship_of_the_line"))
	assert_false(ShipStats.is_warship("galleon"))
	for ship_id: String in ROSTER:
		var cargo: int = int(ShipStats.entry(ship_id)["cargo"])
		if ShipStats.is_warship(ship_id):
			assert_eq(cargo, 0, ship_id)
		else:
			assert_gt(cargo, 0, ship_id)

func test_strength_weights_firepower_range_armour_and_speed() -> void:
	# carrack: 2*1.0 + 1*0.4 + 1*0.15 + 2*0.1
	assert_almost_eq(ShipStats.strength("carrack"), 2.75, 0.0001)
	# ironclad: 5 + 1.2 + 1.2 + 0.3
	assert_almost_eq(ShipStats.strength("ironclad"), 7.7, 0.0001)
	# sloop: 2 + 0.8 + 0.15 + 0.3
	assert_almost_eq(ShipStats.strength("sloop"), 3.25, 0.0001)

func test_durability_is_hull_times_armour_bonus() -> void:
	# HULL * (1 + ARM/10)
	assert_almost_eq(ShipStats.durability("carrack"), 2.2, 0.0001)
	assert_almost_eq(ShipStats.durability("ironclad"), 10.8, 0.0001)
	assert_almost_eq(ShipStats.durability("fluyte"), 1.1, 0.0001)

func test_unknown_ship_stats_fall_back_to_the_carrack() -> void:
	assert_false(ShipStats.known("dromon"))
	assert_eq(ShipStats.normalize("dromon"), "carrack")
	assert_eq(ShipStats.entry("dromon"), ShipStats.entry("carrack"))
	assert_almost_eq(ShipStats.strength("dromon"), 2.75, 0.0001)

func test_display_names_are_period_readable() -> void:
	assert_eq(ShipStats.display_name("ship_of_the_line"), "Ship of the Line")
	assert_eq(ShipStats.display_name("merchant_steamship"), "Merchant Steamship")
	assert_eq(ShipStats.display_name("dromon"), "Carrack")

func test_ship_economy_covers_the_whole_roster() -> void:
	assert_eq(ShipEconomy.ENTRIES.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipEconomy.known(ship_id), ship_id)
		assert_true(ShipStats.known(ship_id), ship_id)

func test_frozen_baseline_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("carrack"), 8000)
	assert_eq(ShipEconomy.build_inputs("carrack"), {"lumber": 2, "fabric": 1})
	assert_true(ShipEconomy.is_always_buildable("carrack"))
	assert_eq(ShipEconomy.unlock_era("carrack"), 0)
	assert_eq(ShipEconomy.treasury_cost("fluyte"), 6000)
	assert_eq(ShipEconomy.build_inputs("fluyte"), {"lumber": 1, "fabric": 1})
	assert_eq(ShipEconomy.unlock_era("fluyte"), 1)

func test_steam_and_line_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("ship_of_the_line"), 16500)
	assert_eq(ShipEconomy.build_inputs("ship_of_the_line"), {"lumber": 5, "fabric": 3})
	assert_eq(ShipEconomy.unlock_era("ship_of_the_line"), 3)
	assert_eq(ShipEconomy.treasury_cost("ironclad"), 21000)
	assert_eq(
		ShipEconomy.build_inputs("ironclad"), {"lumber": 2, "fabric": 2, "castIron": 5}
	)
	assert_eq(ShipEconomy.unlock_era("ironclad"), 4)
	assert_eq(ShipEconomy.treasury_cost("merchant_steamship"), 15500)
	assert_eq(
		ShipEconomy.build_inputs("merchant_steamship"),
		{"lumber": 2, "fabric": 2, "coal": 3}
	)
	assert_eq(ShipEconomy.treasury_cost("raider"), 11500)
	assert_eq(
		ShipEconomy.build_inputs("raider"), {"lumber": 2, "fabric": 1, "castIron": 2}
	)

func test_roles_align_with_ship_stats() -> void:
	for ship_id: String in ROSTER:
		var role: String = String(ShipEconomy.entry(ship_id)["role"])
		if ShipStats.is_warship(ship_id):
			assert_eq(role, "warship", ship_id)
		else:
			assert_eq(role, "merchant", ship_id)

func test_unknown_ship_economy_falls_back_to_the_carrack() -> void:
	assert_false(ShipEconomy.known("dromon"))
	assert_eq(ShipEconomy.entry("dromon"), ShipEconomy.entry("carrack"))
	assert_eq(ShipEconomy.treasury_cost("dromon"), 8000)

func test_food_upkeep_is_two_per_hull() -> void:
	assert_eq(ShipEconomy.FOOD_UPKEEP_PER_SHIP, 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("carrack"), 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("ironclad"), 2)
	var fleet: FleetState = FleetState.at_sea(
		1, 0, 3, ["ship_1", "ship_2", "ship_3"], {"ship_1": "sloop", "ship_2": "carrack"}
	)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(fleet), 6)
	var minted: FleetState = FleetState.at_sea(2, 0, 3, [])
	# Factory still mints one default hull when none are given.
	assert_eq(ShipEconomy.food_upkeep_for_fleet(minted), 2)
	var sunk: FleetState = FleetState.at_sea(3, 0, 3, ["ship_9"])
	sunk.remove_hull("ship_9")
	assert_eq(ShipEconomy.food_upkeep_for_fleet(sunk), 0)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(null), 0)

func test_food_upkeep_sums_owned_fleets_only() -> void:
	var fleets: Array[FleetState] = [
		FleetState.at_sea(1, 0, 1, ["ship_1", "ship_2"]),
		FleetState.at_sea(2, 1, 2, ["ship_3", "ship_4", "ship_5"]),
		FleetState.in_port(3, 0, 4, ["ship_6"]),
	]
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 0), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 1), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 2), 0)

func test_can_afford_checks_treasury_and_materials() -> void:
	var stock: Dictionary = {"lumber": 2, "fabric": 1}
	assert_true(ShipEconomy.can_afford("carrack", 8000, stock))
	assert_false(ShipEconomy.can_afford("carrack", 7999, stock))
	assert_false(ShipEconomy.can_afford("carrack", 8000, {"lumber": 1, "fabric": 1}))
	assert_true(ShipEconomy.can_afford("sloop", 5500, {"lumber": 1, "fabric": 1}))
	assert_false(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 4})
	)
	assert_true(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 5})
	)

func test_missing_inputs_lists_shortfalls() -> void:
	var short: Dictionary = ShipEconomy.missing_inputs(
		"raider", {"lumber": 1, "fabric": 1, "castIron": 0}
	)
	assert_eq(short, {"lumber": 1, "castIron": 2})
	assert_eq(ShipEconomy.missing_inputs("carrack", {"lumber": 2, "fabric": 1}), {})

func test_catalog_has_the_published_recipes() -> void:
	# Ten first-stage rows plus the two second-stage works rows the town's
	# works open (wiki: production-recipes § Town-works gates; DR-20261116-04).
	assert_eq(ProductionRecipes.ids().size(), 12)
	assert_eq(ProductionRecipes.output("lumber"), "lumber")
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})
	assert_eq(ProductionRecipes.labour("lumber"), 2)
	assert_eq(ProductionRecipes.inputs("bronze"), {"copper": 1, "tin": 1})
	assert_eq(ProductionRecipes.labour("bronze"), 3)
	assert_eq(ProductionRecipes.output("fabric_from_wool"), "fabric")
	assert_false(ProductionRecipes.known("silk_gown"))

func test_inputs_are_returned_as_a_copy() -> void:
	var inputs: Dictionary = ProductionRecipes.inputs("lumber")
	inputs["timber"] = 99
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})

func test_cotton_fabric_needs_its_technology() -> void:
	assert_true(ProductionRecipes.available("fabric_from_wool", {}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {}))
	assert_true(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": true}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": false}))
	var gated: Array[String] = ProductionRecipes.available_ids({})
	assert_false(gated.has("fabric_from_cotton"))
	assert_true(gated.has("fabric_from_wool"))
	assert_true(ProductionRecipes.available("steel", {}))

func test_max_runs_is_limited_by_inputs_and_labour() -> void:
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 10}, 6), 3)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 3}, 20), 1)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 0}, 20), 0)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 9), 2)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 2), 0)
	assert_eq(ProductionRecipes.max_runs("unknown", {"timber": 10}, 10), 0)

## The ledger's per-row ceiling: the whole runs the coming phase could start from
## the post-Consumption store once the other rows hold their claims. The row's
## own assignment is not counted against itself, so a full board still reads a
## true ceiling for each row (wiki: stockpiles-and-production § Production flow;
## issue #453).
func test_allowance_holds_back_the_other_rows_claims() -> void:
	assert_eq(ProductionRecipes.allowance("lumber", {"timber": 4}, 20, []), 2)
	# Paper and lumber share timber: two paper runs eat the whole tonnage.
	assert_eq(
		ProductionRecipes.allowance("lumber", {"timber": 4}, 20, [{"recipe": "paper", "units": 2}]),
		0
	)
	assert_eq(
		ProductionRecipes.allowance("lumber", {"timber": 4}, 20, [{"recipe": "lumber", "units": 1}]),
		2
	)
	# Labour is shared too: two paper runs spend four of six points.
	assert_eq(
		ProductionRecipes.allowance("lumber", {"timber": 8}, 6, [{"recipe": "paper", "units": 2}]),
		1
	)
	assert_eq(ProductionRecipes.allowance("unknown", {"timber": 4}, 20, []), 0)
	assert_eq(ProductionRecipes.claimed_labour([{"recipe": "steel", "units": 3}]), 6)
	# A row with no recipe, and a row that is not a dictionary, claim nothing.
	assert_eq(
		ProductionRecipes.claimed_labour([{"recipe": "bronze", "units": 2}, {"units": 5}, 7]),
		6
	)


func test_plan_runs_whole_recipes_and_scales_io() -> void:
	var stock: Dictionary = {"timber": 5}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 3}], stock, 6, {}
	)
	assert_eq(report["runs"], {"lumber": 2})
	assert_eq(report["consumed"], {"timber": 4})
	assert_eq(report["produced"], {"lumber": 2})
	assert_eq(report["labour_used"], 4)
	assert_eq(stock["timber"], 1)
	assert_eq(stock["lumber"], 2)

func test_plan_skips_recipes_it_cannot_run_once() -> void:
	var stock: Dictionary = {"timber": 1}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 4}], stock, 10, {}
	)
	assert_eq(report["runs"], {})
	assert_eq(report["produced"], {})
	assert_eq(stock["timber"], 1)
	assert_eq(report["labour_used"], 0)

func test_plan_respects_assignment_order_and_labour_budget() -> void:
	var stock: Dictionary = {"iron": 4, "coal": 2}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "steel", "units": 2},
			{"recipe": "castIron", "units": 2},
		],
		stock,
		4,
		{}
	)
	# Steel takes the full labour budget first; castIron never starts. Alloy
	# output stays in the workshop until the next Production phase.
	assert_eq(report["runs"], {"steel": 2})
	assert_eq(report["produced"], {})
	assert_eq(int(stock.get("steel", 0)), 0)
	assert_eq(ProductionWorkshop.units(report["wip"], "steel"), 2)
	assert_eq(stock["iron"], 2)
	assert_eq(stock["coal"], 0)
	assert_eq(report["labour_used"], 4)

func test_plan_ignores_unavailable_and_zero_unit_rows() -> void:
	var stock: Dictionary = {"cotton": 4, "timber": 4}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "fabric_from_cotton", "units": 2},
			{"recipe": "lumber", "units": 0},
			{"recipe": "lumber", "units": -3},
		],
		stock,
		10,
		{}
	)
	assert_eq(report["runs"], {})
	assert_eq(stock["cotton"], 4)
	assert_eq(stock["timber"], 4)
	var allowed: Dictionary = ProductionRecipes.plan(
		[{"recipe": "fabric_from_cotton", "units": 2}], stock, 10, {"cotton_weaving": true}
	)
	assert_eq(allowed["runs"], {"fabric_from_cotton": 2})
	assert_eq(stock["cotton"], 0)
	assert_eq(stock["fabric"], 2)

## The workshop owner cleans a save's batches and serves the landings a phase
## pays, without knowing any recipe (wiki: production-recipes § Turns per unit;
## DR-20261112-11, DR-20261113-02).
func test_workshop_cleans_batches_and_serves_landings() -> void:
	assert_eq(ProductionWorkshop.clean_batch({"units": 2, "turns_left": 1}), {
		"units": 2, "turns_left": 1
	})
	assert_eq(ProductionWorkshop.clean_batch({"units": 0, "turns_left": 1}), {})
	assert_eq(ProductionWorkshop.clean_batch({"units": 2, "turns_left": 0}), {})
	assert_eq(ProductionWorkshop.clean_batch("steel"), {})
	var wip: Dictionary = {
		"steel": [{"units": 3, "turns_left": 1}, {"units": 2, "turns_left": 2}, "bad"],
	}
	assert_eq(ProductionWorkshop.batches(wip, "steel").size(), 2)
	assert_eq(ProductionWorkshop.batches({"steel": "bad"}, "steel"), [])
	assert_eq(ProductionWorkshop.units(wip, "steel"), 5)
	assert_eq(ProductionWorkshop.soonest(wip, "steel"), 1)
	assert_eq(ProductionWorkshop.soonest({}, "steel"), 0)
	assert_eq(ProductionWorkshop.ready_units(wip, "steel", 2), 1, "only the served batch lands")
	assert_eq(ProductionWorkshop.serve(wip, "steel", 2), {
		"landed": 1,
		"kept": [{"units": 2, "turns_left": 1}, {"units": 2, "turns_left": 1}],
	})
	assert_eq(ProductionWorkshop.serve({}, "steel", 2), {"landed": 0, "kept": []})


func test_plan_cannot_drive_quantities_negative() -> void:
	var stock: Dictionary = {"iron": 1, "coal": 1, "timber": 0}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "steel", "units": 5}], stock, 3, {}
	)
	assert_eq(report["runs"], {"steel": 1})
	assert_eq(stock["iron"], 0)
	assert_eq(stock["coal"], 0)


## A luxury is a trained hand's work: cigars need an apprentice, fur hats a
## journeyman, and a higher tier satisfies the gate (wiki: production-recipes
## § Worker-tier gates; DR-20261114-07).
func test_luxury_rows_need_a_trained_hand() -> void:
	assert_eq(ProductionRecipes.min_tier("cigars"), WorkerPool.Tier.APPRENTICE)
	assert_eq(ProductionRecipes.min_tier("furHats"), WorkerPool.Tier.JOURNEYMAN)
	assert_eq(ProductionRecipes.min_tier("lumber"), 0, "a plain row needs no hand")
	var peasants: WorkerPool = WorkerPool.make(4)
	assert_false(ProductionRecipes.tier_met("cigars", peasants))
	assert_false(ProductionRecipes.tier_met("furHats", peasants))
	assert_true(ProductionRecipes.tier_met("lumber", peasants))
	var apprentices: WorkerPool = WorkerPool.make(3, 1)
	assert_true(ProductionRecipes.tier_met("cigars", apprentices))
	assert_false(ProductionRecipes.tier_met("furHats", apprentices))
	var masters: WorkerPool = WorkerPool.make(3, 0, 0, 1)
	assert_true(ProductionRecipes.tier_met("cigars", masters), "a master runs an apprentice row")
	assert_true(ProductionRecipes.tier_met("furHats", masters), "a master runs a journeyman row")
	# A projection with no pool fails closed rather than opening every row.
	assert_false(ProductionRecipes.tier_met("cigars", null))
	assert_true(ProductionRecipes.tier_met("lumber", null))
	assert_false(ProductionRecipes.available_for("cigars", {}, peasants))
	assert_true(ProductionRecipes.available_for("cigars", {}, apprentices))
	assert_false(ProductionRecipes.available_ids_for({}, peasants).has("cigars"))
	assert_true(ProductionRecipes.available_ids_for({}, apprentices).has("cigars"))
	assert_false(ProductionRecipes.available_ids_for({}, apprentices).has("furHats"))


## A gated row neither runs nor offers a ceiling, and the phase leaves its
## inputs alone (wiki: production-recipes § Worker-tier gates; REQ-P2-03).
func test_a_gated_row_does_not_run_and_its_ceiling_is_zero() -> void:
	var stock: Dictionary = {"tobacco": 4, "furs": 4}
	var peasants: WorkerPool = WorkerPool.make(4)
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}, {"recipe": "furHats", "units": 2}],
		stock, 20, {}, {}, peasants
	)
	assert_eq(report["runs"], {})
	assert_eq(stock["tobacco"], 4)
	assert_eq(stock["furs"], 4)
	assert_eq(ProductionRecipes.allowance("cigars", stock, 20, [], peasants), 0)
	# A gated row set by the court claims no labour from the rows that do run.
	assert_eq(
		ProductionRecipes.allowance(
			"lumber", {"timber": 8}, 6, [{"recipe": "cigars", "units": 2}], peasants
		),
		3,
		"a gated row claims nothing from the rows that run"
	)
	var apprentices: WorkerPool = WorkerPool.make(3, 1)
	assert_eq(ProductionRecipes.allowance("cigars", stock, 20, [], apprentices), 2)
	assert_eq(ProductionRecipes.allowance("furHats", stock, 20, [], apprentices), 0)
	var allowed: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}], stock, 20, {}, {}, apprentices
	)
	assert_eq(allowed["runs"], {"cigars": 2})
	assert_eq(stock["tobacco"], 0)


## A second-stage row is the town's own work: garments need a level-2 town and
## rum a level-4 one, and the gate is a presence test on the crown's best town,
## not a count of towns (wiki: production-recipes § Town-works gates;
## DR-20261116-04).
func test_town_rows_need_the_town_works() -> void:
	assert_eq(ProductionRecipes.min_town("garments"), 2)
	assert_eq(ProductionRecipes.min_town("rum"), 4)
	assert_eq(ProductionRecipes.min_town("lumber"), 0, "a plain row asks nothing of the town")
	assert_false(ProductionRecipes.town_met("garments", 0))
	assert_false(ProductionRecipes.town_met("garments", 1))
	assert_true(ProductionRecipes.town_met("garments", 2))
	assert_false(ProductionRecipes.town_met("rum", 2))
	assert_true(ProductionRecipes.town_met("rum", 4), "a fully developed town opens the finer works")
	assert_true(ProductionRecipes.town_met("lumber", 0), "an ungated row never waits on a town")
	assert_false(ProductionRecipes.available_for("garments", {}, null, 1))
	assert_true(ProductionRecipes.available_for("garments", {}, null, 2))
	assert_false(ProductionRecipes.available_ids_for({}, null, 1).has("garments"))
	assert_true(ProductionRecipes.available_ids_for({}, null, 2).has("garments"))
	assert_false(ProductionRecipes.available_ids_for({}, null, 2).has("rum"))


## A closed works gate neither runs the row nor offers a ceiling, and the phase
## leaves its inputs alone; the town's works claims nothing from the rows that
## do run (REQ-P2-03).
func test_a_closed_works_gate_stops_the_row_and_its_ceiling() -> void:
	var stock: Dictionary = {"fabric": 4, "refinedSugar": 4}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "garments", "units": 2}, {"recipe": "rum", "units": 2}],
		stock, 20, {}, {}, null, 1
	)
	assert_eq(report["runs"], {})
	assert_eq(stock["fabric"], 4)
	assert_eq(stock["refinedSugar"], 4)
	assert_eq(ProductionRecipes.allowance("garments", stock, 20, [], null, {}, 1), 0)
	assert_eq(
		ProductionRecipes.allowance(
			"lumber", {"timber": 8}, 6, [{"recipe": "garments", "units": 2}], null, {}, 1
		),
		3,
		"a row behind a closed works gate claims nothing from the rows that run"
	)
	var open_town: Dictionary = ProductionRecipes.plan(
		[{"recipe": "garments", "units": 2}], stock, 20, {}, {}, null, 2
	)
	assert_eq(open_town["runs"], {"garments": 2})
	assert_eq(stock["fabric"], 0)
	assert_eq(ProductionRecipes.allowance("garments", {"fabric": 4}, 20, [], null, {}, 2), 2)


## The presence test reads the crown's best town in any province on any chart,
## never a rival's town (wiki: production-recipes § Town-works gates;
## DR-20261116-04).
func test_the_works_gate_reads_the_crowns_best_town() -> void:
	# Two owned towns are enough: a pocket chart, not a regenerated Standard
	# draw (~8 s under coverage) that only existed to avoid dirtying the census.
	assert_eq(TownIndustry.best_level(null, FactionCatalog.PLAYER_FACTION), 0, "no world, no town")
	var model: MapModel = MapModel.new()
	model.setup(4, 1)
	var own_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var rival_tiles: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	for tile: Vector2i in own_tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
	for tile: Vector2i in rival_tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 1
	var own: ProvinceState = ProvinceState.create(
		0, "Own", own_tiles, Vector2(0.5, 0.0), 2, FactionCatalog.PLAYER_FACTION
	)
	var rival: ProvinceState = ProvinceState.create(
		1, "Rival", rival_tiles, Vector2(2.5, 0.0), 2, FactionCatalog.PLAYER_FACTION + 1
	)
	own.town_development = 3
	rival.town_development = 4
	model.provinces.append(own)
	model.provinces.append(rival)
	var world_map: WorldMap = WorldMap.new()
	world_map.add_region(model)
	assert_eq(
		TownIndustry.best_level(world_map, FactionCatalog.PLAYER_FACTION), 3,
		"a rival's finer town does not open the crown's works"
	)


## A batch already on the anvil was paid when it started: losing the hand that
## opened the row does not strand its output (DR-20261112-11, DR-20261114-07).
func test_a_carried_batch_lands_even_when_the_hand_is_gone() -> void:
	var stock: Dictionary = {}
	var wip: Dictionary = {"cigars": [{"units": 2, "turns_left": 1}]}
	var report: Dictionary = ProductionRecipes.plan([], stock, 0, {}, wip, WorkerPool.make(4))
	assert_eq(report["produced"], {"cigars": 1}, "a slow row gives up one unit a phase")
	assert_eq(stock["cigars"], 1)
	assert_eq(ProductionWorkshop.units(report["wip"], "cigars"), 1, "the rest waits")


## A one-turn row never waits: a carried batch of it (only a damaged or
## hand-edited save can hold one) lands whole (DR-20261113-02).
func test_a_carried_one_turn_batch_lands_whole() -> void:
	var stock: Dictionary = {}
	var wip: Dictionary = {"lumber": [{"units": 2, "turns_left": 1}]}
	var report: Dictionary = ProductionRecipes.plan([], stock, 0, {}, wip, null)
	assert_eq(report["produced"], {"lumber": 2})
	assert_eq(stock["lumber"], 2)


## A luxury is slow work: a cigar ages and a fur hat cures, so both rows take
## two turns while refined sugar — the apprentice's own ration — stays one
## (wiki: production-recipes § Recipe Catalog; DR-20261114-10).
func test_the_luxury_rows_take_two_turns() -> void:
	assert_eq(ProductionRecipes.turns("cigars"), 2)
	assert_eq(ProductionRecipes.turns("furHats"), 2)
	assert_eq(ProductionRecipes.turns("refinedSugar"), 1, "the apprentice's own ration is quick work")
	assert_eq(ProductionRecipes.turns("steel"), 2)
	assert_eq(ProductionRecipes.turns("lumber"), 1)


## A cigar batch pays its tobacco and labour when it starts, lands nothing that
## phase, then gives up one unit a phase (DR-20261113-02, DR-20261114-10).
func test_a_cigar_batch_lands_one_unit_a_phase() -> void:
	var stock: Dictionary = {"tobacco": 4}
	var apprentices: WorkerPool = WorkerPool.make(3, 1)
	var first: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}], stock, 20, {}, {}, apprentices
	)
	assert_eq(first["runs"], {"cigars": 2})
	assert_eq(first["produced"], {}, "a two-turn row lands nothing in the phase it starts")
	assert_eq(stock["tobacco"], 0, "the batch pays its inputs up front")
	assert_eq(ProductionWorkshop.units(first["wip"], "cigars"), 2)
	var second: Dictionary = ProductionRecipes.plan([], stock, 0, {}, first["wip"], apprentices)
	assert_eq(second["produced"], {"cigars": 1}, "one unit a phase")
	assert_eq(ProductionWorkshop.units(second["wip"], "cigars"), 1)
	var third: Dictionary = ProductionRecipes.plan([], stock, 0, {}, second["wip"], apprentices)
	assert_eq(third["produced"], {"cigars": 1})
	assert_eq(stock["cigars"], 2)
	assert_true(third["wip"].is_empty(), "the batch is spent")


## A slow row's bench holds three pieces: a fourth run waits for a landing, the
## ledger's ceiling stops where the phase would, and a one-turn row is never
## capped (wiki: production-recipes § Workshop queue; DR-20261114-12).
func test_the_workshop_holds_three_pieces_of_a_slow_row() -> void:
	assert_eq(ProductionWorkshop.QUEUE_CAP, 3)
	var stock: Dictionary = {"tobacco": 20}
	var apprentices: WorkerPool = WorkerPool.make(3, 1)
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 5}], stock, 20, {}, {}, apprentices
	)
	assert_eq(report["runs"], {"cigars": 3}, "the bench takes three pieces")
	assert_eq(ProductionWorkshop.units(report["wip"], "cigars"), 3)
	assert_eq(stock["tobacco"], 14, "the fourth run pays nothing")
	# A batch still serving its first turn leaves the bench full: no new run,
	# even with inputs and labour to spare.
	var held: Dictionary = {"cigars": [{"units": 3, "turns_left": 2}]}
	var again: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}], stock, 20, {}, held, apprentices
	)
	assert_eq(again["runs"], {})
	assert_eq(stock["tobacco"], 14)
	# Two assignments of one row share the same bench.
	var split: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}, {"recipe": "cigars", "units": 2}],
		{"tobacco": 20}, 20, {}, {}, apprentices
	)
	assert_eq(split["runs"], {"cigars": 3}, "two assignments share one bench")
	# The ceiling the ledger offers stops at the room the coming phase leaves.
	assert_eq(
		ProductionRecipes.allowance("cigars", stock, 20, [], apprentices, held), 0
	)
	assert_eq(
		ProductionRecipes.allowance(
			"cigars", stock, 20, [], apprentices, {"cigars": [{"units": 2, "turns_left": 1}]}
		),
		2,
		"a landing frees its place for the run set now"
	)
	# A one-turn row never waits, so the cap never binds it.
	assert_eq(ProductionRecipes.allowance("lumber", {"timber": 20}, 20, [], null, {}), 10)
	# A batch already on the anvil keeps its place: a save over the cap still
	# lands, and only new runs wait.
	var legacy: Dictionary = {"cigars": [{"units": 5, "turns_left": 1}]}
	var served: Dictionary = ProductionRecipes.plan([], {}, 0, {}, legacy, apprentices)
	assert_eq(served["produced"], {"cigars": 1}, "a paid batch still lands")
	assert_eq(ProductionWorkshop.units(served["wip"], "cigars"), 4)
	assert_eq(ProductionWorkshop.room(legacy, "cigars", 2), 0, "an over-full bench has no room")


func test_every_track_points_at_a_shipped_file() -> void:
	var ids: Array[String] = MusicPlaylist.ids()
	assert_gte(ids.size(), 6)
	for track_id: String in ids:
		var path: String = MusicPlaylist.path_for(track_id)
		assert_true(path.begins_with(MusicPlaylist.ROOT), track_id)
		assert_true(FileAccess.file_exists(path), path)
	assert_true(FileAccess.file_exists(MusicPlaylist.AMBIENCE))

func test_unknown_track_has_no_path() -> void:
	assert_true(MusicPlaylist.track("sea_shanty_404").is_empty())
	assert_eq(MusicPlaylist.path_for("sea_shanty_404"), "")

func test_eras_open_on_the_consort_and_close_on_the_minuet() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1500), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1549), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1550), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1699), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1700), MusicPlaylist.GILDED_MINUET)
	assert_eq(MusicPlaylist.bed_id_for_year(1800), MusicPlaylist.GILDED_MINUET)

func test_years_before_the_start_fall_back_to_the_first_bed() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1400), MusicPlaylist.AGE_OF_DISCOVERY)

func test_beds_follow_the_turn_calendar() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(TurnTime.year_for_turn(1)),
		MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_for_turn(1)["id"], MusicPlaylist.AGE_OF_DISCOVERY)
	# 1500 + 2 years per turn: turn 30 is 1558, turn 101 is 1700.
	assert_eq(MusicPlaylist.bed_for_turn(30)["id"], MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_for_turn(101)["id"], MusicPlaylist.GILDED_MINUET)

func test_beds_carry_period_metadata() -> void:
	for bed: Dictionary in MusicPlaylist.ERA_BEDS:
		assert_true(bed.has("title"), "title")
		assert_true(bed.has("era"), "era")
		assert_gt(int(bed["from_year"]), 0)

func test_only_stingers_are_one_shots() -> void:
	assert_true(MusicPlaylist.loops(MusicPlaylist.SPANISH_MAIN))
	assert_true(MusicPlaylist.loops(MusicPlaylist.BROADSIDES))
	assert_false(MusicPlaylist.loops(MusicPlaylist.VICTORY))
	assert_false(MusicPlaylist.loops(MusicPlaylist.DEFEAT))

func test_every_regiment_has_a_training_row() -> void:
	for type_id: String in RegimentCatalog.ids():
		assert_true(RegimentEconomy.TECH.has(type_id), "%s has a tech row" % type_id)
		var tech: String = RegimentEconomy.tech_for(type_id)
		if not tech.is_empty():
			assert_true(TechCatalog.known(tech), "%s maps to a real tech" % type_id)

func test_cavalry_inputs_match_the_published_table() -> void:
	var squires: Dictionary = RegimentEconomy.training_inputs("squires")
	assert_eq(int(squires["fabric"]), 1)
	assert_eq(int(squires["castIron"]), 1)
	assert_eq(int(squires["horses"]), 2)
	var knights: Dictionary = RegimentEconomy.training_inputs("knights")
	assert_eq(int(knights["castIron"]), 2)
	assert_eq(int(knights["horses"]), 2)
	var lancers: Dictionary = RegimentEconomy.training_inputs("lancers")
	assert_false(lancers.has("horses"), "lancers need no horses")

func test_start_regiments_are_buildable_and_later_ones_are_tech_gated() -> void:
	assert_true(RegimentEconomy.buildable("peasant_levies", {}))
	assert_true(RegimentEconomy.buildable("culverin", {}))
	assert_false(RegimentEconomy.buildable("lancers", {}))
	assert_true(RegimentEconomy.buildable("lancers", {"organised_regiments": true}))
	assert_false(RegimentEconomy.buildable("guards", {"needle_guns": true}))
	assert_true(RegimentEconomy.buildable("guards", {"elite_military_training": true}))

func test_blocked_reasons_follow_the_ledger() -> void:
	var stock: Dictionary = {"fabric": 5, "castIron": 5, "bronze": 5}
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 0, stock, 5, {}),
		"Insufficient treasury"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, {}, 5, {}),
		"Insufficient materials"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, stock, 0, {}),
		"Insufficient workers"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("lancers", 99999, stock, 5, {}),
		"Requires Organised Regiments"
	)
	assert_eq(RegimentEconomy.blocked_reason("pikemen", 99999, stock, 5, {}), "")

func test_cost_text_lists_cash_materials_and_the_worker() -> void:
	var text: String = RegimentEconomy.cost_text("peasant_levies")
	assert_true(text.contains("2,000 ducats"), text)
	assert_true(text.contains("Fabric"), text)
	assert_true(text.contains("1 worker"), text)

func test_recruit_deducts_the_ledger_and_joins_the_home_army() -> void:
	var economy := PlayerEconomy.starting()
	var home := ArmyState.muster(1, 0, 4, true, [] as Array[String], 1)
	var treasury: int = economy.treasury
	var fabric: int = economy.quantity("fabric")
	var peasants: int = economy.available_peasants()

	var result: Dictionary = ArmyTraining.recruit(economy, home, "peasant_levies", "unit_9")

	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(home.count(), 1)
	assert_eq(home.type_of("unit_9"), "peasant_levies")
	assert_eq(economy.treasury, treasury - RegimentCatalog.treasury_cost("peasant_levies"))
	assert_eq(economy.quantity("fabric"), fabric - 1)
	assert_eq(economy.available_peasants(), peasants - 1)

func test_recruit_refuses_a_field_army() -> void:
	var economy := PlayerEconomy.starting()
	var field := ArmyState.muster(2, 0, 4, false, [] as Array[String], 1)
	var result: Dictionary = ArmyTraining.recruit(economy, field, "peasant_levies", "unit_9")
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Regiments muster only in the Home Army.")
	assert_eq(field.count(), 0)

func test_rows_lead_with_what_the_crown_can_muster_today() -> void:
	var economy := PlayerEconomy.starting()
	var rows: Array[Dictionary] = ArmyTraining.rows(economy)
	assert_eq(rows.size(), RegimentCatalog.ROWS.size())
	assert_true(bool(rows[0]["ok"]), "first row is buildable")
	var seen_locked: bool = false
	for row: Dictionary in rows:
		if not bool(row["ok"]):
			seen_locked = true
		elif seen_locked:
			assert_true(false, "buildable rows must come before locked rows")


# --- folded: the live advanced start (one mount per tier) ---
## The live setup path of an advanced start (wiki: advanced-starts;
## DR-20261111-01): a real map screen opening at a mid-age tier, with the
## treasury, the muster, the chart and the roster the tier promises (merged
## from test_advanced_start_live). One mount per tier: under coverage a mount
## costs ~0.5–2 s, so the five live cases re-seat from a pristine save
## (`Fixture.suite_reset`, ~0.15 s) instead of remounting each time.

## Non-underscore so before_all state is copied onto each test instance.
## Live mounts use a private chart so idle screens cannot rewrite `Fixture.world`
## under later cases (`test_same_seed_reproduces_the_world` reads that chart).
var advanced_live_world: WorldMap = null
var advanced_live_saved: Array = []
var tier50_screen: MapScreen = null
var tier50_pristine: Dictionary = {}
var tier100_screen: MapScreen = null
var tier100_pristine: Dictionary = {}


func _mount_advanced_tiers() -> void:
	advanced_live_world = MapGenerator.new().generate_world(SEED, WIDTH, HEIGHT)
	# Full SaveWorld half: a shallow ownership snapshot cannot rewind town
	# levels / resources the tier writes before suite_reset reseats a case.
	advanced_live_saved = []
	for entry: Dictionary in SaveWorld.capture(advanced_live_world):
		advanced_live_saved.append(entry)
	tier50_screen = _instantiate_tier(AdvancedStart.TURNS50)
	tier50_pristine = Fixture.suite_capture(tier50_screen)
	SaveWorld.apply(advanced_live_world, advanced_live_saved)
	tier100_screen = _instantiate_tier(AdvancedStart.TURNS100)
	tier100_pristine = Fixture.suite_capture(tier100_screen)
	SaveWorld.apply(advanced_live_world, advanced_live_saved)


func _instantiate_tier(tier: String) -> MapScreen:
	var screen: MapScreen = Fixture.SCENE.instantiate()
	screen.map_width = Fixture.WORLD_WIDTH
	screen.map_height = Fixture.WORLD_HEIGHT
	screen.preset_world = advanced_live_world
	screen.advanced_start = tier
	add_child(screen)
	return screen


func after_all() -> void:
	if is_instance_valid(tier50_screen):
		tier50_screen.free()
	if is_instance_valid(tier100_screen):
		tier100_screen.free()
	tier50_screen = null
	tier100_screen = null
	tier50_pristine = {}
	tier100_pristine = {}
	advanced_live_world = null
	advanced_live_saved = []


func test_a_new_campaign_opens_on_the_preset() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS50)
	var play: PlaySession = screen.play
	assert_eq(play.turn, 50, "the age opens at turn 50")
	assert_eq(TurnTime.year_for_turn(play.turn), 1598)
	assert_eq(play.advanced_start, AdvancedStart.TURNS50)
	assert_eq(play.treasury(), 40000, "the tier purse")
	assert_eq(play.economy.economy.workers.count(WorkerPool.Tier.PEASANT), 16)
	assert_eq(play.economy.economy.research.unlocked_ids().size(), 23)
	assert_gte(
		play.economy.economy.quantity("grain"), 16 * PlayerEconomy.START_GRAIN_TURNS,
		"the tier workforce is fed from the first turn"
	)
	assert_true(play.visibility_by_region.has(NEW_WORLD), "the inherited chart exists")
	var home: ArmyState = _home_army(screen, play.player_faction)
	assert_not_null(home)
	assert_eq(home.count(), 11, "five opening regiments plus the tier's six")
	assert_gte(_home_galleons(screen, play.player_faction), 1, "a Galleon waits in port")
	var roster: Array = screen.civilian_layer.regions.value(0, [])
	assert_eq(_civilian_count(roster, play.player_faction, "explorer"), 3)
	assert_eq(_civilian_count(roster, play.player_faction, "spy"), 1)


## Old World capitals open behind a Wood wall on an advanced start too, and the
## tier's granted fort studies do not pre-bump it: the free upgrade is a research
## unlock's moment, not an inherited tech (wiki: siege-mechanics § Fort Levels;
## issue #919).
func test_capitals_open_walled_and_a_tier_does_not_pre_bump_them() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS50)
	var play: PlaySession = screen.play
	var model: MapModel = play.world.region(FactionCatalog.OLD_WORLD)
	assert_true(
		play.economy.economy.research.is_unlocked("mine_engineering"),
		"the tier already holds the fort study",
	)
	for province: ProvinceState in model.provinces:
		if not province.capital:
			continue
		assert_eq(
			province.fort_level, FortCapital.START_LEVEL,
			"capital of %d opens at Wood" % province.owner,
		)


func test_a_late_campaign_opens_with_the_documented_progress() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS100)
	var play: PlaySession = screen.play
	assert_eq(play.turn, 100, "the age opens at turn 100")
	assert_eq(TurnTime.year_for_turn(play.turn), 1698)
	assert_eq(play.treasury(), 40000)
	assert_eq(
		play.hud._treasury_label.text, TextFormat.thousands(play.treasury()),
		"the top bar reads the tier purse, not the turn-0 ledger it opened on",
	)
	assert_eq(
		play.hud._income_label.text, TextFormat.delta(play.income),
		"the per-turn figure follows the tier ledger too",
	)
	assert_eq(play.economy.economy.workers.count(WorkerPool.Tier.APPRENTICE), 4)
	assert_eq(play.economy.economy.research.unlocked_ids().size(), 45)
	assert_gte(_home_galleons(screen, play.player_faction), 6, "the late tier sails a convoy")
	var home: ArmyState = _home_army(screen, play.player_faction)
	assert_not_null(home)
	assert_eq(home.count(), 17, "five opening regiments plus the tier's twelve")
	var roster: Array = screen.civilian_layer.regions.value(0, [])
	assert_gte(
		_civilian_count(roster, play.player_faction, "rail_builder"), 1,
		"the late tier fields a Rail Builder"
	)


## Every court inherits the same New World chart (wiki § NW sea-zone visibility
## is per Great Power): a rival reads the Passage lanes its own grid holds, so
## its voyages are not blind to water the player was given.
func test_rivals_inherit_the_passage_lanes() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS50)
	var play: PlaySession = screen.play
	var human: int = play.player_faction
	var human_zones: Array[int] = play.court_charts.known_zones(human, NEW_WORLD)
	assert_false(human_zones.is_empty(), "the crown inherits the Passage lanes")
	for faction: int in FactionCatalog.great_power_ids():
		if faction == human:
			continue
		var view: VisibilityModel = play.court_charts.model_for(faction, NEW_WORLD)
		assert_not_null(view, "a rival holds a New World chart")
		assert_eq(view.player_id, faction, "each court reads its own grid")
		var rival_zones: Array[int] = play.court_charts.known_zones(faction, NEW_WORLD)
		assert_eq(rival_zones, human_zones, "every court reads the same lanes")


## A rival reads its own colony beach (100-turn claim): owned shore, fully
## visible water, through the court's own grid rather than the player's.
func test_a_rival_reads_its_own_colony_coast() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS100)
	var play: PlaySession = screen.play
	var model: MapModel = play.world.region(NEW_WORLD)
	for faction: int in FactionCatalog.great_power_ids():
		var view: VisibilityModel = play.court_charts.model_for(faction, NEW_WORLD)
		assert_not_null(view)
		var held: int = 0
		for province: ProvinceState in model.provinces:
			if province.owner != faction:
				continue
			held += 1
			assert_true(
				view.is_province_fully_visible(province.id),
				"a crown reads its own colony"
			)
		assert_gte(held, 1, "the late tier seats every crown in the New World")


## Every hull id is minted once for the life of the save (wiki: ships-and-naval
## § Ship instances — "the same id must never appear in two fleets"). The tier's
## cargo muster founds a squadron at each seat, so a fleet born with an empty
## roster must not take the `ship_<fleet id>` default.
func test_the_tier_musters_unique_hull_ids() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS100)
	var seen: Dictionary = {}
	for region: int in screen.ship_layer.regions.region_ids():
		for raw: Variant in screen.ship_layer.regions.value(region, []):
			var fleet: FleetState = raw as FleetState
			if fleet == null:
				continue
			for hull_id: String in fleet.hulls:
				assert_false(
					seen.has(hull_id),
					"%s sails in two fleets (%d and %d)" % [
						hull_id, int(seen.get(hull_id, -1)), fleet.id,
					]
				)
				seen[hull_id] = fleet.id


func _open(tier: String) -> MapScreen:
	var screen: MapScreen = tier50_screen if tier == AdvancedStart.TURNS50 else tier100_screen
	var pristine: Dictionary = (
		tier50_pristine if tier == AdvancedStart.TURNS50 else tier100_pristine
	)
	SaveWorld.apply(advanced_live_world, advanced_live_saved)
	Fixture.suite_reset(screen, pristine)
	return screen


func _home_army(screen: MapScreen, faction: int) -> ArmyState:
	for raw: Variant in screen.army_layer.regions.value(0, []):
		var army: ArmyState = raw as ArmyState
		if army != null and army.owner == faction and army.is_home_army():
			return army
	return null


func _home_galleons(screen: MapScreen, faction: int) -> int:
	var count: int = 0
	for raw: Variant in screen.ship_layer.regions.value(0, []):
		var fleet: FleetState = raw as FleetState
		if fleet == null or fleet.owner != faction:
			continue
		for hull: String in fleet.hulls:
			if fleet.type_of(hull) == "galleon":
				count += 1
	return count


func _civilian_count(roster: Array, faction: int, type_id: String) -> int:
	var count: int = 0
	for raw: Variant in roster:
		var unit: CivilianState = raw as CivilianState
		if unit != null and unit.owner == faction and unit.type_id == type_id:
			count += 1
	return count
