class_name DeedIncome
extends RefCounted
## Purchased land pays its owner (wiki: world-market § Touch points with
## purchased tiles; DR-20261110-09). A tile bought from a Minor Nation or Tribe
## yields its harvest and every ton credits the buyer's treasury at the
## commodity's market price — never the stockpile, never a cargo hold. The
## seller publishes no row for the tile, so money and ledger never disagree
## (REQ-P2-03). Pure rules: the controller calls it once per turn.

## Minor land never develops past the bootstrap estate.
const DEED_LEVEL: int = 1


## Deeds this crown holds in one region: Array[Vector2i], row-major.
static func tiles(model: MapModel, owner: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if model == null or owner < 0:
		return result
	for tile: Vector2i in model.ownership.owned_tiles(model, owner):
		if model.is_purchased_tile(tile):
			result.append(tile)
	return result


## Yield of one deed: the settler's own estate capped at level 1, the
## province's town limit and the terrain cap. The prospecting gate does not
## apply (the deed makes the buyer the extractor, civilian-units § Merchant)
## and no foreign connectivity run happens (world-market § Riches handoff).
static func tile_yield(
	model: MapModel, tile: Vector2i, works: LandWorks = null
) -> Dictionary:
	var result: Dictionary = {}
	if model == null or not model.in_bounds(tile.x, tile.y):
		return result
	var commodity: String = Extraction.commodity_for_resource(
		model.resource_at(tile.x, tile.y)
	)
	if commodity.is_empty() or not CommodityCatalog.is_tradeable(commodity):
		return result
	var level: int = DEED_LEVEL
	if works != null:
		level = mini(DEED_LEVEL, works.improvement_at(model, tile))
	if level <= 0:
		return result
	var cap: int = TerrainCaps.extraction_cap(
		model.terrain_at(tile.x, tile.y), commodity, Extraction.tech_cap_for(commodity, {})
	)
	var amount: int = Extraction.effective_yield(
		level, cap, Extraction.DEFAULT_TRANSPORT, province_town_cap(model, tile)
	)
	if amount > 0:
		result[commodity] = amount
	return result


## Units per commodity and their treasury value at market price.
## {"units": {id: n}, "treasury": n}.
static func income(
	world: WorldMap, region: int, owner: int, works: LandWorks = null
) -> Dictionary:
	var model: MapModel = world.region(region) if world != null else null
	var units: Dictionary = {}
	var total: int = 0
	for tile: Vector2i in tiles(model, owner):
		var harvest: Dictionary = tile_yield(model, tile, works)
		for raw: Variant in harvest.keys():
			var id: String = String(raw)
			var amount: int = int(harvest[raw])
			units[id] = int(units.get(id, 0)) + amount
			total += amount * CommodityCatalog.base_price(id)
	return {"units": units, "treasury": total, "tiles": tiles(model, owner), "model": model}


## Takes every deed's tons out of `home_yield`: the crown was paid the
## treasure for them, so the harvest is never counted twice (REQ-P2-03).
static func without_deeds(home_yield: Dictionary, units: Dictionary) -> Dictionary:
	var kept: Dictionary = home_yield.duplicate()
	for raw: Variant in units.keys():
		var id: String = String(raw)
		var remainder: int = int(kept.get(id, 0)) - int(units[raw])
		if remainder > 0:
			kept[id] = remainder
		else:
			kept.erase(id)
	return kept


## Credits the purse once; returns the income() shape for the turn report.
static func settle(report: Dictionary, economy: PlayerEconomy) -> Dictionary:
	var credit: int = int(report.get("treasury", 0))
	if economy != null and credit > 0:
		economy.add_treasury(credit)
	report["line"] = summary_line(credit)
	return report


## The toast fragment naming a deed's take; empty when nothing earned.
static func summary_line(credit: int) -> String:
	return "" if credit <= 0 else "+%d from deeds" % credit


## Town development caps an estate the way it caps a Great Power's (0 town: no
## cap). wiki: extraction-and-improvements § Extraction formula and town cap.
static func province_town_cap(model: MapModel, tile: Vector2i) -> int:
	var province_id: int = model.province_at(tile.x, tile.y)
	var province: ProvinceState = model.get_province(province_id)
	if province == null or province.town_development <= 0:
		return Extraction.MAX_YIELD
	return maxi(province.town_level(), 1)