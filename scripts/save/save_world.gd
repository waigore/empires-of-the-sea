class_name SaveWorld
extends RefCounted
## Region ownership, province records, resources and tile deeds on the save
## wire (wiki: world-model-identity). Split out of SaveCodec so the world half
## of a slot can be captured and reapplied over a reused world without growing
## the codec past the file-size bars (REQ-P3-02, REQ-P3-03).


static func capture(world: WorldMap) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	for model: MapModel in world.regions:
		var provinces: Array[Dictionary] = []
		for province: ProvinceState in model.provinces:
			var province_entry: Dictionary = {
				"id": province.id,
				"owner": province.owner,
				"capital": province.capital,
				"town_development": province.town_development,
				"fort_level": province.fort_level,
				"resource": province.resource,
				"resource_tile": province.resource_tile,
				"population": province.population,
				"road_paths": province.road_paths.duplicate(true),
			}
			provinces.append(province_entry)
		var region_entry: Dictionary = {
			"width": model.width,
			"height": model.height,
			"provinces": provinces,
			"resources": model.resource.duplicate(),
			"tile_deeds": model.ownership.to_dict(),
		}
		regions.append(region_entry)
	return regions


## Reapplies a captured world over `world`. Returns false when the save cannot
## describe this world (region count or sizes differ), so the caller regenerates.
static func apply(world: WorldMap, regions: Variant) -> bool:
	if typeof(regions) != TYPE_ARRAY or regions.size() != world.region_count():
		return false
	for index in world.region_count():
		var entry: Variant = regions[index]
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var model: MapModel = world.region(index)
		var data: Dictionary = entry
		if int(data.get("width", 0)) != model.width or int(data.get("height", 0)) != model.height:
			return false
		var provinces: Array = data.get("provinces", [])
		if provinces.size() != model.provinces.size():
			return false
		for raw: Variant in provinces:
			if typeof(raw) != TYPE_DICTIONARY:
				return false
			if not _apply_province(model, raw):
				return false
		if not _apply_resources(model, data.get("resources", PackedInt32Array())):
			return false
		model.ownership.apply_dict(data.get("tile_deeds", {}))
	return true


## A candidate world is reusable only when its region sizes match the save, so a
## mismatched preset still gets a fresh generation instead of a wrong map.
static func reusable(candidate: WorldMap, width: int, height: int) -> WorldMap:
	if candidate == null or candidate.region_count() == 0:
		return null
	for index in candidate.region_count():
		var model: MapModel = candidate.region(index)
		if model == null or model.width != width or model.height != height:
			return null
	return candidate


static func _apply_province(model: MapModel, data: Dictionary) -> bool:
	var province: ProvinceState = model.get_province(int(data.get("id", -1)))
	if province == null:
		return false
	province.owner = int(data.get("owner", MapModel.NO_ID))
	province.capital = bool(data.get("capital", false))
	province.town_development = int(data.get("town_development", 0))
	province.fort_level = clampi(int(data.get("fort_level", 0)), 0, FortRules.MAX_LEVEL)
	province.resource = int(data.get("resource", MapModel.NO_ID))
	province.resource_tile = _vector(data.get("resource_tile", Vector2i(-1, -1)))
	province.population = int(data.get("population", 0))
	var paths: Variant = data.get("road_paths", [])
	if typeof(paths) != TYPE_ARRAY:
		return false
	province.road_paths = paths.duplicate(true)
	return true


static func _apply_resources(model: MapModel, raw: Variant) -> bool:
	var wanted: int = model.width * model.height
	if typeof(raw) == TYPE_PACKED_INT32_ARRAY:
		var packed: PackedInt32Array = raw
		if packed.size() != wanted:
			return false
		model.resource = packed
		return true
	if typeof(raw) != TYPE_ARRAY or raw.size() != wanted:
		return false
	for index in wanted:
		model.resource[index] = int(raw[index])
	return true


static func _vector(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)
