class_name Extraction
extends RefCounted
## Extraction phase (wiki: extraction-and-improvements). Each connected land tile
## yields min(improvement, tech cap, terrain cap, path transport, town cap).
## Developed towns then turn town-connected raw into bonus manufactures, and
## Great Powers also receive the flat capital grain bonus every turn.
##
## `town_bonus: false` leaves the manufactures to the caller and `town_raw` hands
## back the province -> town-connected raw detail: an overseas region ships its
## raw first, and only the cargo-delivered tons feed its town bonus
## (wiki: § Town manufacturing bonus; DR-20261110-17).

const STARTING_IMPROVEMENT: int = 1
const DEFAULT_TECH_CAP: int = 1
const DEFAULT_TRANSPORT: int = 1
const MAX_YIELD: int = 4
const CAPITAL_GRAIN_BONUS: int = 5

const GRAIN: String = "grain"


## The published formula, clamped to the 0-4 improvement range.
static func effective_yield(
	improvement: int, tech_cap: int, transport: int, town_cap: int
) -> int:
	var value: int = mini(mini(improvement, tech_cap), mini(transport, town_cap))
	return clampi(value, 0, MAX_YIELD)


## Per-commodity tech ceiling; callers pass TechCatalog.extraction_caps().
static func tech_cap_for(commodity: String, tech_caps: Dictionary) -> int:
	return maxi(int(tech_caps.get(commodity, DEFAULT_TECH_CAP)), 0)


## Map resource index -> commodity id, via the generator's resource table.
static func commodity_for_resource(resource_index: int) -> String:
	if resource_index < 0:
		return ""
	var info: Dictionary = MapGenerator.resource_info(resource_index)
	return String(info.get("commodity", ""))


## Commodity totals per turn for one owner. Provinces without a town development
## level are treated as inland (town cap does not limit yield, per wiki).
## When `works` is supplied, only owned, connected, prospected improvements
## yield; without it the slice keeps its bootstrap level-1 placeholder.
static func yields(
	model: MapModel,
	owner: int,
	capital_province: int,
	tech_caps: Dictionary = {},
	works: LandWorks = null,
	capital_tile: Vector2i = CivilianState.NO_TILE,
	tech_unlocked: Dictionary = {},
	town_bonus: bool = true,
	town_raw: Dictionary = {}
) -> Dictionary:
	var totals: Dictionary = {}
	if model == null or owner < 0:
		return totals
	var resolved: Dictionary = {}
	var connected: Dictionary = {}
	var towns: Dictionary = {}
	if works != null:
		resolved = LandConnectivity.resolve(model, works, owner, capital_tile)
		connected = resolved.get("tiles", {}) as Dictionary
		towns = resolved.get("towns", {}) as Dictionary
	var raw_by_province: Dictionary = {}
	var town_sets: Dictionary = {}
	for tile: Vector2i in model.ownership.owned_tiles(model, owner):
		var province_id: int = model.province_at(tile.x, tile.y)
		var province: ProvinceState = model.get_province(province_id)
		if province == null:
			continue
		var index: int = model.index_of(tile.x, tile.y)
		if (
			works != null
			and province.town_tile.x >= 0
			and int(towns.get(province_id, -1)) == index
		):
			continue
		var resource: int = model.resource_at(tile.x, tile.y)
		var commodity: String = commodity_for_resource(resource)
		if commodity.is_empty():
			continue
		var level: int = STARTING_IMPROVEMENT
		var transport: int = DEFAULT_TRANSPORT
		var town_cap: int = MAX_YIELD
		if works != null:
			var entry: Dictionary = connected.get(index, {}) as Dictionary
			if entry.is_empty():
				continue
			level = works.improvement_at(model, tile)
			if level <= 0:
				continue
			if (
				ImprovementCatalog.needs_prospecting(resource)
				and not works.is_prospected(owner, model, tile)
			):
				continue
			transport = int(entry.get("transport", 0))
			if transport <= 0:
				continue
			town_cap = LandConnectivity.town_cap_for(model, resolved, province_id, index)
		else:
			town_cap = province.town_level() if province.town_development > 0 else MAX_YIELD
		var cap: int = TerrainCaps.extraction_cap(
			model.terrain_at(tile.x, tile.y), commodity, tech_cap_for(commodity, tech_caps)
		)
		var amount: int = effective_yield(level, cap, transport, town_cap)
		if amount <= 0:
			continue
		totals[commodity] = int(totals.get(commodity, 0)) + amount
		if works == null or not CommodityCatalog.is_raw(commodity):
			continue
		var town_index: int = int(towns.get(province_id, -1))
		var town_set: Dictionary = town_sets.get(province_id, {}) as Dictionary
		if town_set.is_empty() and town_index >= 0:
			town_set = LandConnectivity.town_connected(
				model, works, province_id, town_index
			)
			town_sets[province_id] = town_set
		if not town_set.has(index):
			continue
		if not raw_by_province.has(province_id):
			raw_by_province[province_id] = {}
		var raw: Dictionary = raw_by_province[province_id]
		raw[commodity] = int(raw.get(commodity, 0)) + amount
	for province_id: Variant in raw_by_province.keys():
		town_raw[int(province_id)] = raw_by_province[province_id]
	if not town_bonus:
		return _with_capital_grain(model, owner, capital_province, totals)
	for province_id: Variant in raw_by_province.keys():
		var province: ProvinceState = model.get_province(int(province_id))
		if province == null:
			continue
		var bonus: Dictionary = TownIndustry.bonus_for_province(
			raw_by_province[province_id], province.town_development, tech_unlocked
		)
		for commodity: Variant in bonus.keys():
			var id: String = String(commodity)
			totals[id] = int(totals.get(id, 0)) + int(bonus[commodity])
	return _with_capital_grain(model, owner, capital_province, totals)


## Great Powers only: the flat capital grain bonus, whatever the town rule did.
static func _with_capital_grain(
	model: MapModel, owner: int, capital_province: int, totals: Dictionary
) -> Dictionary:
	if capital_province >= 0 and model.province_owner(capital_province) == owner:
		totals[GRAIN] = int(totals.get(GRAIN, 0)) + CAPITAL_GRAIN_BONUS
	return totals


## Province -> town-connected raw still on the land after Extraction. Overseas
## callers price a town bonus against what the holds actually deliver, so they
## pass this detail instead of the region's whole harvest.
static func province_raw(
	model: MapModel,
	owner: int,
	tech_caps: Dictionary = {},
	works: LandWorks = null,
	capital_tile: Vector2i = CivilianState.NO_TILE,
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var raw: Dictionary = {}
	yields(model, owner, -1, tech_caps, works, capital_tile, tech_unlocked, false, raw)
	return raw
