class_name EconomyOverseas
extends RefCounted
## Cargo from the crown's overseas provinces (wiki: extraction-and-improvements
## § Flow to Stockpile; ships-and-naval § Cargo holds and capacity; DR-20261109-17).
## Pure rules: home-region yield enters the stockpile directly, overseas yield
## crosses on the home fleet's cargo holds and only when it is delivered.
##
## A colony yields through its own port/road network — there is no capital tile
## to seed connectivity abroad — so an unconnected overseas tile produces
## nothing to ship. When holds run short the richest commodity ships first
## (deterministic: base price descending, then id), and whatever is left stays
## on the far shore: no per-province storage exists (wiki: stockpiles).


## Extraction totals for every region except the home one.
static func region_totals(
	world: WorldMap,
	home_region: int,
	owner: int,
	tech_caps: Dictionary,
	works_by_region: MapRegionTable
) -> Dictionary:
	var by_region: Dictionary = {}
	if world == null or works_by_region == null:
		return by_region
	for index in world.region_count():
		if index == home_region:
			continue
		var works: LandWorks = works_by_region.value(index, null) as LandWorks
		if works == null:
			continue
		var totals: Dictionary = Extraction.yields(
			world.region(index), owner, -1, tech_caps, works, CivilianState.NO_TILE
		)
		if not totals.is_empty():
			by_region[index] = totals
	return by_region


## One commodity map over every region's yield.
static func merge(by_region: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for raw_region: Variant in by_region.keys():
		var region_totals: Dictionary = by_region[raw_region] as Dictionary
		for raw_id: Variant in region_totals.keys():
			var id: String = String(raw_id)
			var amount: int = int(region_totals[raw_id])
			if amount <= 0:
				continue
			totals[id] = int(totals.get(id, 0)) + amount
	return totals


## Ships as much overseas cargo as the holds allow, richest first.
## {"holds", "used", "shipped", "left", "left_total"}.
static func plan(by_region: Dictionary, holds: int) -> Dictionary:
	var available: Dictionary = merge(by_region)
	var shipped: Dictionary = {}
	var left: Dictionary = available.duplicate()
	var capacity: int = maxi(holds, 0)
	var used: int = 0
	for raw: Variant in priority(available.keys()):
		var id: String = String(raw)
		var take: int = mini(int(available[id]), capacity - used)
		if take <= 0:
			continue
		shipped[id] = take
		used += take
		var remainder: int = int(available[id]) - take
		if remainder > 0:
			left[id] = remainder
		else:
			left.erase(id)
	var left_total: int = 0
	for value: Variant in left.values():
		left_total += int(value)
	return {
		"holds": capacity,
		"used": used,
		"shipped": shipped,
		"left": left,
		"left_total": left_total,
	}


## Commodity ids richest per hold first; ties break by id so saves replay alike.
static func priority(ids: Array) -> Array:
	var ordered: Array = ids.duplicate()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		var id_a: String = String(a)
		var id_b: String = String(b)
		var price_a: int = CommodityCatalog.base_price(id_a)
		var price_b: int = CommodityCatalog.base_price(id_b)
		if price_a != price_b:
			return price_a > price_b
		return id_a < id_b
	)
	return ordered


## Tons that made the crossing this turn.
static func shipped_total(plan: Dictionary) -> int:
	return int(plan.get("used", 0))
