class_name Extraction
extends RefCounted
## Extraction phase (wiki: extraction-and-improvements). Each connected land tile
## yields min(improvement, tech cap, transport, town development); Great Powers
## also receive the flat capital grain bonus every turn.

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
	capital_tile: Vector2i = CivilianState.NO_TILE
) -> Dictionary:
	var totals: Dictionary = {}
	if model == null or owner < 0:
		return totals
	var connected: Dictionary = {}
	if works != null:
		connected = ImprovementSystem.connected_tiles(model, works, owner, capital_tile)
	for tile: Vector2i in model.ownership.owned_tiles(model, owner):
		var province_id: int = model.province_at(tile.x, tile.y)
		var province: ProvinceState = model.get_province(province_id)
		if province == null:
			continue
		var town_cap: int = province.town_development
		if town_cap <= 0:
			town_cap = MAX_YIELD
		var resource: int = model.resource_at(tile.x, tile.y)
		var commodity: String = commodity_for_resource(resource)
		if commodity.is_empty():
			continue
		var level: int = STARTING_IMPROVEMENT
		var transport: int = DEFAULT_TRANSPORT
		if works != null:
			level = works.improvement_at(model, tile)
			if level <= 0 or not connected.has(model.index_of(tile.x, tile.y)):
				continue
			if (
				ImprovementCatalog.needs_prospecting(resource)
				and not works.is_prospected(owner, model, tile)
			):
				continue
			transport = maxi(DEFAULT_TRANSPORT, works.transport_at(model, tile))
			if works.has_port(model, tile):
				transport = LandWorks.TRANSPORT_RAIL
		var amount: int = effective_yield(
			level, tech_cap_for(commodity, tech_caps), transport, town_cap
		)
		if amount > 0:
			totals[commodity] = int(totals.get(commodity, 0)) + amount
	if capital_province >= 0 and model.province_owner(capital_province) == owner:
		totals[GRAIN] = int(totals.get(GRAIN, 0)) + CAPITAL_GRAIN_BONUS
	return totals
