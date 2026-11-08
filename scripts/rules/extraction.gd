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


## Per-commodity tech ceiling; v1 has no gathering tech, so the default cap is 1.
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
static func yields(
	model: MapModel, owner: int, capital_province: int, tech_caps: Dictionary = {}
) -> Dictionary:
	var totals: Dictionary = {}
	if model == null or owner < 0:
		return totals
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) != owner:
			continue
		var town_cap: int = int(province.get("town_development", 0))
		if town_cap <= 0:
			town_cap = MAX_YIELD
		for tile: Vector2i in province.get("tiles", []):
			var commodity: String = commodity_for_resource(model.resource_at(tile.x, tile.y))
			if commodity.is_empty():
				continue
			var amount: int = effective_yield(
				STARTING_IMPROVEMENT,
				tech_cap_for(commodity, tech_caps),
				DEFAULT_TRANSPORT,
				town_cap
			)
			if amount > 0:
				totals[commodity] = int(totals.get(commodity, 0)) + amount
	if capital_province >= 0 and model.province_owner(capital_province) == owner:
		totals[GRAIN] = int(totals.get(GRAIN, 0)) + CAPITAL_GRAIN_BONUS
	return totals
