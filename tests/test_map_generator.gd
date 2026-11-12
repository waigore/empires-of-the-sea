extends GdToolsTest
## Generation invariants: deterministic output, complete assignment and
## contiguous provinces (wiki: tile-map-and-generation).

const Fixture = preload("res://tests/map_fixture.gd")

const SEED: int = Fixture.SEED
const WIDTH: int = Fixture.WIDTH
const HEIGHT: int = Fixture.HEIGHT

## Non-underscore so before_all state is copied onto each test instance.
var model: MapModel = null


func before_all() -> void:
	model = Fixture.region()


func test_same_seed_is_deterministic() -> void:
	var other: MapModel = MapGenerator.new().generate(SEED, WIDTH, HEIGHT)
	assert_eq(other.terrain, model.terrain)
	assert_eq(other.province, model.province)
	assert_eq(other.sea_zone, model.sea_zone)
	var names: Array = []
	for province: ProvinceState in other.provinces:
		names.append(province.name)
	var expected: Array = []
	for province: ProvinceState in model.provinces:
		expected.append(province.name)
	assert_eq(names, expected)


func test_different_seed_changes_the_map() -> void:
	var other: MapModel = MapGenerator.new().generate(SEED + 1, WIDTH, HEIGHT)
	assert_ne(other.terrain, model.terrain)


func test_land_ratio_is_plausible() -> void:
	var ratio: float = float(MapGeo.land_tile_count(model)) / float(WIDTH * HEIGHT)
	assert_between(ratio, 0.15, 0.65, "land ratio %.3f" % ratio)


func test_every_tile_is_assigned() -> void:
	for y in model.height:
		for x in model.width:
			var province: int = model.province_at(x, y)
			var zone: int = model.sea_zone_at(x, y)
			if model.is_land(x, y):
				assert_ne(province, MapModel.NO_ID, "land tile %d,%d has no province" % [x, y])
				assert_eq(zone, MapModel.NO_ID)
			else:
				assert_ne(zone, MapModel.NO_ID, "sea tile %d,%d has no zone" % [x, y])
				assert_eq(province, MapModel.NO_ID)


func test_every_province_is_contiguous() -> void:
	for province: ProvinceState in model.provinces:
		var tiles: Array = province.tiles
		assert_true(tiles.size() > 0)
		assert_true(_is_contiguous(tiles), "province %s is not contiguous" % province.name)


func test_every_sea_zone_is_contiguous() -> void:
	for zone: SeaZoneState in model.sea_zones:
		assert_true(_is_contiguous(zone.tiles))


func test_province_borders_are_inside_the_map() -> void:
	for y in model.height:
		for x in model.width:
			if model.is_land(x, y):
				assert_true(x >= 0 and y >= 0 and x < WIDTH and y < HEIGHT)


func test_default_map_is_the_old_world() -> void:
	assert_eq(model.region_id, FactionCatalog.OLD_WORLD)
	assert_true(model.setup_errors.is_empty(), "setup errors: %s" % str(model.setup_errors))
	assert_eq(model.faction_ids, FactionCatalog.ids_in_region(FactionCatalog.OLD_WORLD))


func test_ownership_spreads_across_factions_with_one_capital_each() -> void:
	var capitals: int = 0
	var owners: Dictionary = {}
	for province: ProvinceState in model.provinces:
		var owner: int = province.owner
		assert_true(FactionCatalog.has_faction(owner), "owner %d is a faction" % owner)
		assert_true(FactionCatalog.can_own_region(owner, model.region_id))
		owners[owner] = true
		if province.capital:
			capitals += 1
	assert_eq(capitals, owners.size())
	for faction_id: int in model.faction_ids:
		assert_true(owners.has(faction_id), "faction %d owns no province" % faction_id)


func test_capitals_follow_the_capital_choice_rule() -> void:
	var seen: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if not province.capital:
			continue
		var owner: int = province.owner
		assert_false(seen.has(owner), "faction %d has two capitals" % owner)
		seen[owner] = true
		var tile: Vector2i = province.capital_tile
		assert_true(model.is_land(tile.x, tile.y))
		assert_eq(model.terrain_at(tile.x, tile.y), MapModel.Terrain.PLAINS)
		var kind: int = (
			CapitalChoice.KIND_GREAT_POWER
			if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER
			else CapitalChoice.KIND_MINOR
		)
		if kind == CapitalChoice.KIND_GREAT_POWER:
			assert_true(CapitalChoice.is_sea_bound(model, province.id))
		var pick: Dictionary = CapitalChoice.pick_province(model, owner, kind)
		assert_eq(int(pick["province_id"]), province.id)
		if CapitalChoice.is_sea_bound(model, province.id):
			var ports: Dictionary = province.ports
			assert_eq(
				ports.size(),
				CapitalChoice.sea_bound_sea_zones(model, province.id).size()
			)
	assert_eq(seen.size(), model.faction_ids.size())


func test_every_province_has_a_town_tile() -> void:
	for province: ProvinceState in model.provinces:
		var town: Vector2i = province.town_tile
		assert_true(town.x >= 0, "province %s has no town" % province.name)
		assert_eq(model.province_at(town.x, town.y), province.id)
		assert_eq(model.terrain_at(town.x, town.y), MapModel.Terrain.PLAINS)
		assert_eq(model.resource_at(town.x, town.y), MapModel.NO_ID)
		assert_gte(province.town_development, 1)
		if province.capital:
			assert_eq(town, province.capital_tile)


func test_coastal_provinces_have_a_waterfront_port() -> void:
	for province: ProvinceState in model.provinces:
		var port: Vector2i = province.port_tile
		if not province.coastal:
			assert_eq(port, Vector2i(-1, -1))
			continue
		assert_true(port.x >= 0, "coastal province %s has no port" % province.name)
		assert_true(model.is_land(port.x, port.y))
		assert_true(MapGeo.is_coastal_tile(model, port.x, port.y))


func test_resources_sit_on_allowed_terrain() -> void:
	var table: Array[Dictionary] = MapGenerator.resource_table()
	for province: ProvinceState in model.provinces:
		var resource: int = province.resource
		if resource < 0:
			continue
		var tile: Vector2i = province.resource_tile
		var terrain: int = model.terrain_at(tile.x, tile.y)
		var allowed: Array = table[resource]["terrain"]
		assert_true(allowed.has(terrain), "%s on %d" % [table[resource]["name"], terrain])


func test_names_are_unique() -> void:
	var seen: Dictionary = {}
	for province: ProvinceState in model.provinces:
		var name: String = province.name
		assert_false(seen.has(name), "duplicate province name %s" % name)
		seen[name] = true
	var zones: Dictionary = {}
	for zone: SeaZoneState in model.sea_zones:
		var name: String = String(zone.name)
		assert_false(zones.has(name), "duplicate sea zone name %s" % name)
		zones[name] = true


## A sea zone's name is the region preset in declared order — the zone standing
## nth in sorted local-id order takes the nth preset entry — and a region with
## more zones than names cycles the preset again behind a numeric ordinal, never
## a shuffle and never an empty label (wiki: naming § Sea-zone display names).
func test_sea_zone_names_cycle_the_preset_with_ordinals() -> void:
	var old_world: int = FactionCatalog.OLD_WORLD
	var preset: Array[String] = MapNaming.OLD_WORLD_SEA_NAMES
	assert_eq(MapNaming.sea_name(0, old_world), preset[0], "the first zone takes the first name")
	assert_eq(MapNaming.sea_name(preset.size() - 1, old_world), preset[preset.size() - 1])
	assert_eq(
		MapNaming.sea_name(preset.size(), old_world),
		"%s (2)" % preset[0],
		"the second cycle marks its ordinal"
	)
	assert_eq(
		MapNaming.sea_name(preset.size() * 2 + 3, old_world),
		"%s (3)" % preset[3],
		"the third cycle reads its own ordinal"
	)
	var seen: Dictionary = {}
	for index in preset.size() * 3:
		var name: String = MapNaming.sea_name(index, old_world)
		assert_false(name.is_empty(), "zone %d has no name" % index)
		assert_false(seen.has(name), "two zones share %s" % name)
		seen[name] = true
	var new_world: int = FactionCatalog.NEW_WORLD
	assert_eq(
		MapNaming.sea_name(7, new_world), MapNaming.NEW_WORLD_SEA_NAMES[7],
		"the New World reads its own preset"
	)
	assert_eq(
		MapNaming.sea_name(7, new_world), MapNaming.sea_name(7, new_world),
		"the same zone always reads the same name"
	)
	# The generated chart names its zones in that same sorted order.
	for order in model.sea_zones.size():
		assert_eq(
			String(model.sea_zones[order].name), MapNaming.sea_name(order, model.region_id),
			"zone %d is named by its place in the id order" % order
		)


## A province must read as its owner's country: Spanish provinces get Spanish
## cities, English provinces English ones, and the capital its capital city.
func test_province_names_match_their_owner() -> void:
	for province: ProvinceState in model.provinces:
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
	for province: ProvinceState in model.provinces:
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
