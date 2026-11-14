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
				"capital_tile": province.capital_tile,
				"ports": province.ports.duplicate(),
				"town_development": province.town_development,
				"town_tile": province.town_tile,
				"fort_level": province.fort_level,
				"hospital_level": province.hospital_level,
				"hospital_staffed": province.hospital_staffed,
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


## Fog of war per region: the player's charted tiles live beside the world half
## of the slot because a load lays both over the regenerated map. Every rival
## court's own grid rides along, so a load does not hand the AI perfect sight
## (wiki: fog-and-exploration; DR-20261110-21).
static func capture_visibility(play: PlaySession) -> Dictionary:
	var by_region: Dictionary = {}
	for raw: Variant in play.visibility_by_region.keys():
		var visibility: VisibilityModel = play.visibility_by_region[raw]
		if visibility != null:
			by_region[int(raw)] = visibility.to_dict()
	var data: Dictionary = {"by_region": by_region}
	if play.court_charts != null:
		data["courts"] = play.court_charts.to_dict()
	return data


## Rebuilds each region's fog from the save; unknown regions and malformed
## entries are skipped so a partial save still loads what it can.
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
	_restore_courts(play, data.get("courts", {}))


## Every rival court's chart, laid over the regenerated world.
static func _restore_courts(play: PlaySession, data: Variant) -> void:
	if play.world == null:
		return
	if play.court_charts == null:
		play.court_charts = CourtCharts.new()
	play.court_charts.setup(play.world, play.player_faction, play.visibility_by_region)
	play.court_charts.apply_dict(play.world, data)


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


## A candidate world is reusable only when every region it holds matches the
## size the save records for that same region, so a mismatched preset still gets
## a fresh generation instead of a wrong map. A world's charts are not all one
## size (the New World is wider than the Old), so the save's own per-region
## sizes are the only honest check; comparing every region to one width used to
## reject every real multi-chart preset and pay for a whole regeneration on
## each load.
static func reusable(candidate: WorldMap, regions: Variant) -> WorldMap:
	if candidate == null or candidate.region_count() == 0:
		return null
	if typeof(regions) != TYPE_ARRAY:
		return null
	var saved: Array = regions
	if saved.size() != candidate.region_count():
		return null
	for index in candidate.region_count():
		var model: MapModel = candidate.region(index)
		if model == null or typeof(saved[index]) != TYPE_DICTIONARY:
			return null
		var data: Dictionary = saved[index]
		if int(data.get("width", 0)) != model.width:
			return null
		if int(data.get("height", 0)) != model.height:
			return null
	return candidate


static func _apply_province(model: MapModel, data: Dictionary) -> bool:
	var province: ProvinceState = model.get_province(int(data.get("id", -1)))
	if province == null:
		return false
	province.owner = int(data.get("owner", MapModel.NO_ID))
	province.capital = bool(data.get("capital", false))
	if data.has("capital_tile"):
		province.capital_tile = _vector(data.get("capital_tile", Vector2i(-1, -1)))
	if data.has("ports"):
		province.ports = _ports(data.get("ports", {}))
	province.town_development = int(data.get("town_development", 0))
	if data.has("town_tile"):
		province.town_tile = _vector(data.get("town_tile", Vector2i(-1, -1)))
	province.fort_level = clampi(int(data.get("fort_level", 0)), 0, FortRules.MAX_LEVEL)
	province.hospital_level = clampi(
		int(data.get("hospital_level", 0)), 0, HospitalRules.MAX_LEVEL
	)
	# A save written before the wards ate carries no flag: its staffs are fed.
	province.hospital_staffed = bool(data.get("hospital_staffed", true))
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


## Seaboard ports (`zone id -> tile`). Text literals keep Vector2i values and
## int keys; a malformed entry is dropped rather than failing the whole load.
static func _ports(raw: Variant) -> Dictionary:
	var ports: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return ports
	var data: Dictionary = raw
	for key: Variant in data.keys():
		var tile: Vector2i = _vector(data[key])
		if tile.x < 0:
			continue
		ports[int(key)] = tile
	return ports
