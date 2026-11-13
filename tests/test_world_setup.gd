extends GdToolsTest
## Two-region world setup (wiki: game-setup, map-topology, factions).
## Old World holds Great Powers + Minor Nations; the New World holds Tribes.

const Fixture = preload("res://tests/map_fixture.gd")

const SEED: int = Fixture.SEED
const WIDTH: int = Fixture.WORLD_WIDTH
const HEIGHT: int = Fixture.WORLD_HEIGHT

## Non-underscore so before_all state is copied onto each test instance.
var world: WorldMap = null


func before_all() -> void:
	world = Fixture.world()


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
