class_name RealmReadings
extends RefCounted
## The three realm readings one province carries — what it yields, how hard it
## is to hold and how far it sits from the seat — as pure projections over the
## records the turn already resolved (REQ-P3-02, REQ-P3-03).
##
## No figure is recomputed here: the defence multiplier is the battle's own
## [ArmyModifiers.TERRAIN_DEFENCE], the fort's guns are [FortRules]', the band is
## the defence lens's [DefenceSurvey] and the price is the market's own
## [WorldMarket.sell_price], so a realm row can never print a figure the turn or
## a fight would not use (REQ-P2-03).

const NO_ID: int = -1


## Economy: what is developed, what could still be raised, what the estates
## gathered this turn and what that harvest is worth at today's sell price.
## `estate` is [ProvinceLedger]'s own read of the estates ledger's group.
static func economy(estate: Dictionary, owner: int, market: WorldMarket) -> Dictionary:
	var reading: Dictionary = {
		"estates": int(estate["estates"]),
		"developed": 0,
		"headroom": 0,
		"output": int(estate["output"]),
		"value": 0,
		"by_kind": {},
		"working": bool(estate["working"]),
	}
	for raw: Variant in estate["rows"]:
		var row: Dictionary = raw
		if int(row.get("level", 0)) > 0:
			reading["developed"] = int(reading["developed"]) + 1
		if _has_headroom(row):
			reading["headroom"] = int(reading["headroom"]) + 1
		var output: int = int(row.get("output", 0))
		if output <= 0:
			continue
		var kind: String = String(ImprovementCatalog.entry(int(row.get("resource", -1)))["icon"])
		var by_kind: Dictionary = reading["by_kind"]
		by_kind[kind] = int(by_kind.get(kind, 0)) + output
		var commodity: String = String(row.get("commodity", ""))
		var price: int = market.sell_price(commodity, owner) if market != null else 0
		reading["value"] = int(reading["value"]) + output * price
	return reading


## Whether a resource tile still has room above it: the lowest of the terrain,
## study and level ceilings, and the mineral survey that gates a deposit.
static func _has_headroom(row: Dictionary) -> bool:
	if int(row.get("level", 0)) >= ImprovementCatalog.MAX_LEVEL:
		return false
	if bool(row.get("needs_prospecting", false)) and not bool(row.get("prospected", false)):
		return false
	var ceiling: int = mini(
		int(row.get("terrain_cap", 0)), int(row.get("tech_cap", 0))
	)
	return int(row.get("level", 0)) < ceiling


## Defence: one figure built from the same terms a fight would use — the
## garrison at the ground's own multiplier, plus the wall's emplaced battery.
static func defence(
	province: ProvinceState, garrison: Dictionary, model: MapModel, tech: Dictionary
) -> Dictionary:
	var fort: int = FortRules.clamp_level(province.fort_level)
	var terrain: int = ArmyModifiers.terrain_for(model, province.id)
	var strength: float = float(garrison["strength"])
	var emplaced: float = FortRules.emplaced_strength(fort, tech)
	var multiplier: float = ArmyModifiers.terrain_multiplier(terrain)
	return {
		"strength": strength,
		"regiments": int(garrison["regiments"]),
		"fort": fort,
		"fort_name": FortRules.level_name(fort),
		"guns": FortRules.guns(fort),
		"wall": FortRules.wall_hp(fort),
		"hospital": HospitalRules.clamp_level(province.hospital_level),
		"terrain": terrain,
		"terrain_name": DefenceSurvey.terrain_name(terrain),
		"terrain_line": DefenceSurvey.terrain_line(terrain),
		"multiplier": multiplier,
		"emplaced": emplaced,
		"figure": roundi(strength * multiplier + emplaced),
		"band": DefenceSurvey.band_for(fort, int(garrison["regiments"])),
	}


## Connectivity: how many owned-land hops from the seat, whether the crown road
## reaches it, and whether it lies on the seat's own chart.
static func connectivity(
	link: Dictionary, hops: Dictionary, province_id: int, seat: int, region: int,
	seat_region: int
) -> Dictionary:
	return {
		"hops": int(hops.get(province_id, -1)),
		"linked": bool(link.get("linked", false)),
		"blockaded": bool(link.get("blockaded", false)),
		"distance": int(link.get("distance", -1)),
		"same_chart": seat_region == NO_ID or region == seat_region,
		"seat": province_id == seat,
	}
