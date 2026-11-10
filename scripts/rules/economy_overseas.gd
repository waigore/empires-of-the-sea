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


## Extraction totals for every region except the home one. Overseas totals are
## **raw only**: a developed town's manufactures are earned from what the holds
## deliver, so `delivered` adds them after the crossing
## (wiki: extraction-and-improvements § Town manufacturing bonus).
## `town_raw` collects region -> province -> town-connected raw for that split.
static func region_totals(
	world: WorldMap,
	home_region: int,
	owner: int,
	tech_caps: Dictionary,
	works_by_region: MapRegionTable,
	tech_unlocked: Dictionary = {},
	town_raw: Dictionary = {}
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
		var detail: Dictionary = {}
		var totals: Dictionary = Extraction.yields(
			world.region(index), owner, -1, tech_caps, works, CivilianState.NO_TILE,
			tech_unlocked, false, detail
		)
		if not totals.is_empty():
			by_region[index] = totals
		if not detail.is_empty():
			town_raw[index] = detail
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


## Adds the tonnage this turn's holds can carry from the crown's other regions
## to its home yield (wiki: extraction-and-improvements § Flow to Stockpile;
## DR-20261109-17), then pays the town manufacturing bonus on the raw that
## actually landed (wiki: § Town manufacturing bonus).
## The caller computes its own home-region yield — its seat lives there — and
## this module owns the crossing, so the player ledger and a rival's economy
## ship by the same rule (REQ-P2-03).
## Returns the [method plan] fields plus:
##   "extraction" — home yield + delivered raw + bonus manufactures
##   "manufactured" — the bonus manufactures only (they never spend a hold)
##   "by_province" — region -> province -> delivered raw, for the AI's ledger.
static func delivered(
	home_totals: Dictionary,
	world: WorldMap,
	home_region: int,
	owner: int,
	tech_caps: Dictionary,
	works_by_region: MapRegionTable,
	holds: int,
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var town_raw: Dictionary = {}
	var plan: Dictionary = plan(
		region_totals(
			world, home_region, owner, tech_caps, works_by_region, tech_unlocked,
			town_raw
		),
		holds
	)
	var totals: Dictionary = home_totals.duplicate()
	var shipped: Dictionary = plan["shipped"] as Dictionary
	for raw: Variant in shipped.keys():
		var id: String = String(raw)
		totals[id] = int(totals.get(id, 0)) + int(shipped[raw])
	var landed: Dictionary = split(town_raw, shipped, world)
	var manufactured: Dictionary = _manufactured(world, landed, tech_unlocked)
	for made: Variant in manufactured.keys():
		var id: String = String(made)
		totals[id] = int(totals.get(id, 0)) + int(manufactured[made])
	plan["extraction"] = totals
	plan["manufactured"] = manufactured
	plan["by_province"] = landed
	return plan


## Attributes the shipped tonnage back to the provinces that grew it. Within one
## commodity the fullest-developed town draws first (multiplier descending, then
## most raw, then region and province id), so a level-4 town earns its bonus
## before a level-2 one and a save replays alike (DR-20261110-17).
static func split(
	town_raw: Dictionary, shipped: Dictionary, world: WorldMap
) -> Dictionary:
	var landed: Dictionary = {}
	for commodity: Variant in priority(shipped.keys()):
		var id: String = String(commodity)
		var left: int = int(shipped.get(commodity, 0))
		if left <= 0:
			continue
		for entry: Dictionary in _shipping_order(town_raw, id, world):
			if left <= 0:
				break
			var take: int = mini(left, int(entry["raw"]))
			if take <= 0:
				continue
			var region: int = int(entry["region"])
			var province: int = int(entry["province"])
			if not landed.has(region):
				landed[region] = {}
			var by_province: Dictionary = landed[region]
			if not by_province.has(province):
				by_province[province] = {}
			var cargo: Dictionary = by_province[province]
			cargo[id] = int(cargo.get(id, 0)) + take
			left -= take
	return landed


## Town manufactures from the raw that crossed this turn: input is delivered
## tonnage only, output lands in the stockpile without a hold
## (wiki: § Town manufacturing bonus).
static func _manufactured(
	world: WorldMap, landed: Dictionary, tech_unlocked: Dictionary
) -> Dictionary:
	var made: Dictionary = {}
	for raw_region: Variant in landed.keys():
		var region: int = int(raw_region)
		var model: MapModel = world.region(region) if world != null else null
		if model == null:
			continue
		var by_province: Dictionary = landed[raw_region] as Dictionary
		for raw_province: Variant in by_province.keys():
			var province: ProvinceState = model.get_province(int(raw_province))
			if province == null or province.town_development <= 0:
				continue
			var bonus: Dictionary = TownIndustry.bonus_for_province(
				by_province[raw_province], province.town_development, tech_unlocked
			)
			for raw_id: Variant in bonus.keys():
				var id: String = String(raw_id)
				made[id] = int(made.get(id, 0)) + int(bonus[raw_id])
	return made


## Every province holding this commodity, best town first, then fullest hold.
static func _shipping_order(
	town_raw: Dictionary, commodity: String, world: WorldMap
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw_region: Variant in town_raw.keys():
		var region: int = int(raw_region)
		var by_province: Dictionary = town_raw[raw_region] as Dictionary
		var model: MapModel = world.region(region) if world != null else null
		for raw_province: Variant in by_province.keys():
			var cargo: Dictionary = by_province[raw_province] as Dictionary
			var amount: int = int(cargo.get(commodity, 0))
			if amount <= 0:
				continue
			var province: ProvinceState = (
				model.get_province(int(raw_province)) if model != null else null
			)
			rows.append({
				"region": region,
				"province": int(raw_province),
				"raw": amount,
				"multiplier": (
					TownIndustry.multiplier(province.town_development)
					if province != null else 0
				),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["multiplier"]) != int(b["multiplier"]):
			return int(a["multiplier"]) > int(b["multiplier"])
		if int(a["raw"]) != int(b["raw"]):
			return int(a["raw"]) > int(b["raw"])
		if int(a["region"]) != int(b["region"]):
			return int(a["region"]) < int(b["region"])
		return int(a["province"]) < int(b["province"])
	)
	return rows


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
