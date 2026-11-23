extends RefCounted
## Packed Standard census chart for generator suites. Coverage multiplies a
## cold `generate_world(96×64)` by ~10×; loading this fixture keeps the same
## seed-160 chart without that cost (docs/testing.md § Speed rules).

const PATH: String = "res://tests/data/census_world_160.bin"
## Must match `test_generated_world_rules.CENSUS_SEED` and the Standard preset.
const SEED: int = 160
const WIDTH: int = 96
const HEIGHT: int = 64

static var _world: WorldMap = null


static func world() -> WorldMap:
	if _world != null:
		return _world
	var absolute: String = ProjectSettings.globalize_path(PATH)
	assert(
		FileAccess.file_exists(absolute),
		"missing census fixture %s — run tools/write_census_fixture.gd" % PATH
	)
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	assert(file != null, "cannot read census fixture %s" % PATH)
	var payload: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	assert(typeof(payload) == TYPE_DICTIONARY, "census fixture is not a dictionary")
	_world = _unpack_world(payload as Dictionary)
	return _world


## Rebuilds the packed bytes from a live generate. Used by the writer tool when
## the generator or the census seed changes.
static func pack_world(source: WorldMap) -> PackedByteArray:
	var regions: Array = []
	for model: MapModel in source.regions:
		regions.append(_pack_model(model))
	var links: Array = []
	for link: Dictionary in source.warp_links:
		links.append(link.duplicate(true))
	return var_to_bytes({
		"seed": SEED,
		"width": WIDTH,
		"height": HEIGHT,
		"regions": regions,
		"warp_links": links,
	})


static func _unpack_world(data: Dictionary) -> WorldMap:
	assert(int(data.get("seed", -1)) == SEED, "census fixture seed drift")
	assert(int(data.get("width", 0)) == WIDTH, "census fixture width drift")
	assert(int(data.get("height", 0)) == HEIGHT, "census fixture height drift")
	var world := WorldMap.new()
	for raw: Variant in data.get("regions", []):
		assert(typeof(raw) == TYPE_DICTIONARY)
		world.add_region(_unpack_model(raw as Dictionary))
	for raw: Variant in data.get("warp_links", []):
		if typeof(raw) == TYPE_DICTIONARY:
			world.warp_links.append((raw as Dictionary).duplicate(true))
	return world


static func _pack_model(model: MapModel) -> Dictionary:
	var provinces: Array = []
	for province: ProvinceState in model.provinces:
		provinces.append({
			"id": province.id,
			"name": province.name,
			"tiles": province.tiles.duplicate(),
			"center": province.center,
			"area": province.area,
			"owner": province.owner,
			"capital": province.capital,
			"capital_tile": province.capital_tile,
			"ports": province.ports.duplicate(true),
			"town_development": province.town_development,
			"town_tile": province.town_tile,
			"port_tile": province.port_tile,
			"fort_level": province.fort_level,
			"hospital_level": province.hospital_level,
			"hospital_staffed": province.hospital_staffed,
			"resource": province.resource,
			"resource_tile": province.resource_tile,
			"population": province.population,
			"coastal": province.coastal,
			"road_paths": province.road_paths.duplicate(true),
		})
	var zones: Array = []
	for zone: SeaZoneState in model.sea_zones:
		zones.append({
			"id": zone.id,
			"name": zone.name,
			"tiles": zone.tiles.duplicate(),
			"center": zone.center,
			"area": zone.area,
		})
	return {
		"region_id": model.region_id,
		"region_key": model.region_key,
		"width": model.width,
		"height": model.height,
		"faction_ids": model.faction_ids.duplicate(),
		"setup_errors": model.setup_errors.duplicate(),
		"terrain": model.terrain,
		"province": model.province,
		"sea_zone": model.sea_zone,
		"resource": model.resource,
		"ownership": model.ownership.to_dict(),
		"provinces": provinces,
		"sea_zones": zones,
	}


static func _unpack_model(data: Dictionary) -> MapModel:
	var model := MapModel.new()
	model.setup(int(data["width"]), int(data["height"]))
	model.region_id = int(data["region_id"])
	model.region_key = String(data["region_key"])
	model.faction_ids = data["faction_ids"]
	model.setup_errors = data["setup_errors"]
	model.terrain = data["terrain"]
	model.province = data["province"]
	model.sea_zone = data["sea_zone"]
	model.resource = data["resource"]
	model.ownership.apply_dict(data.get("ownership", {}))
	for raw: Variant in data.get("provinces", []):
		var entry: Dictionary = raw
		var province := ProvinceState.new()
		province.id = int(entry["id"])
		province.name = String(entry["name"])
		province.tiles = entry["tiles"]
		province.center = entry["center"]
		province.area = int(entry["area"])
		province.owner = int(entry["owner"])
		province.capital = bool(entry["capital"])
		province.capital_tile = entry["capital_tile"]
		province.ports = entry["ports"]
		province.town_development = int(entry["town_development"])
		province.town_tile = entry["town_tile"]
		province.port_tile = entry["port_tile"]
		province.fort_level = int(entry["fort_level"])
		province.hospital_level = int(entry["hospital_level"])
		province.hospital_staffed = bool(entry["hospital_staffed"])
		province.resource = int(entry["resource"])
		province.resource_tile = entry["resource_tile"]
		province.population = int(entry["population"])
		province.coastal = bool(entry["coastal"])
		province.road_paths = entry["road_paths"]
		model.provinces.append(province)
	for raw: Variant in data.get("sea_zones", []):
		var entry: Dictionary = raw
		var zone := SeaZoneState.new()
		zone.id = int(entry["id"])
		zone.name = String(entry["name"])
		zone.tiles = entry["tiles"]
		zone.center = entry["center"]
		zone.area = int(entry["area"])
		model.sea_zones.append(zone)
	return model
