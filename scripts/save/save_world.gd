class_name SaveWorld
extends RefCounted
## Save shape of the generated world and the fog the player has raised over it.
## The world is rebuilt from its seed, so only the mutable overlay (owners,
## walls, resources, deeds) and the per-region visibility travel (REQ-P3-01).


static func capture_regions(world: WorldMap) -> Array[Dictionary]:
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


## Lays the saved overlay onto the freshly generated world. A shape mismatch
## (width, height, province count) means the seed no longer regenerates the
## same map, so the load is refused.
static func apply_regions(world: WorldMap, regions: Variant) -> bool:
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


static func capture_visibility(play: PlaySession) -> Dictionary:
	var by_region: Dictionary = {}
	for raw: Variant in play.visibility_by_region.keys():
		var visibility: VisibilityModel = play.visibility_by_region[raw]
		if visibility != null:
			by_region[int(raw)] = visibility.to_dict()
	return {"by_region": by_region}


static func restore_visibility(play: PlaySession, data: Variant) -> void:
	play.visibility_by_region.clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var by_region: Dictionary = data.get("by_region", {})
	for raw: Variant in by_region.keys():
		var region: int = int(raw)
		var model: MapModel = play.world.region(region)
		var entry: Variant = by_region[raw]
		if model == null or typeof(entry) != TYPE_DICTIONARY:
			continue
		var visibility := VisibilityModel.new()
		visibility.setup(model, play.player_faction)
		if visibility.apply_dict(entry):
			play.visibility_by_region[region] = visibility


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


## Accepts the two vector shapes a save may carry (Vector2i or [x, y]).
static func _vector(raw: Variant) -> Vector2i:
	match typeof(raw):
		TYPE_VECTOR2I:
			return Vector2i(raw)
		TYPE_VECTOR2:
			return Vector2i(raw)
		TYPE_ARRAY:
			var pair: Array = raw
			if pair.size() == 2:
				return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i(-1, -1)
