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
		for province: Dictionary in model.provinces:
			var owner: int = int(province["owner"])
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
			for province: Dictionary in model.provinces:
				if int(province["owner"]) == faction_id:
					owned.append(int(province["id"]))
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
		for province: Dictionary in model.provinces:
			if not bool(province["capital"]):
				continue
			var owner: int = int(province["owner"])
			assert_false(capitals.has(owner), "%s has two capitals" % FactionCatalog.name_of(owner))
			capitals[owner] = int(province["id"])
			var tile: Vector2i = province["capital_tile"]
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
	for province: Dictionary in model.provinces:
		capitals.append(bool(province["capital"]))
		province["capital"] = false
	var fallback: int = world.seat_province(FactionCatalog.OLD_WORLD, player)
	for index in model.provinces.size():
		model.provinces[index]["capital"] = capitals[index]
	assert_eq(int(model.province_data(fallback)["owner"]), player)
	assert_eq(world.seat_province(FactionCatalog.OLD_WORLD, 9999), MapModel.NO_ID)


func test_owned_provinces_counts_the_region_only() -> void:
	var player: int = FactionCatalog.PLAYER_FACTION
	var model: MapModel = world.region(FactionCatalog.OLD_WORLD)
	var expected: int = 0
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == player:
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
		assert_true(model.sea_zone_data(zone_id).size() > 0)
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
		for province: Dictionary in first.provinces:
			first_owners.append(int(province["owner"]))
		for province: Dictionary in second.provinces:
			second_owners.append(int(province["owner"]))
		assert_eq(first_owners, second_owners)


func _owns_sea_bound(model: MapModel, faction_id: int) -> bool:
	for province: Dictionary in model.provinces:
		if int(province["owner"]) != faction_id:
			continue
		if CapitalChoice.is_sea_bound(model, int(province["id"])):
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
	for tile: Vector2i in model.sea_zone_data(zone_id).get("tiles", []):
		if tile.x == 0 or tile.y == 0 or tile.x == model.width - 1 or tile.y == model.height - 1:
			return true
	return false
