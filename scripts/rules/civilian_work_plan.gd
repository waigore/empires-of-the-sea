class_name CivilianWorkPlan
extends RefCounted
## Cost, duration and target-level maths for civilian work orders (wiki:
## civilian-units § Work Order Summary, extraction-and-improvements § Improvement
## build costs and town development). Pure data/maths; CivilianWork validates
## and applies orders, so the arithmetic has one home.

const IMPROVEMENT_COSTS: Array[Dictionary] = [
	{},
	{"lumber": 1, "castIron": 1},
	{"lumber": 4, "castIron": 4},
	{"lumber": 8, "castIron": 8},
	{"lumber": 16, "castIron": 16},
]
## The improvement-input feedstock the H8 bootstrap covers: the raw whose
## extraction supplies the manufactures every raise spends (wool and cotton
## weave the muster's fabric and are not part of the gate — wiki:
## extraction-and-improvements § H8 feedstock bootstrap).
const FEEDSTOCK_RESOURCES: Array[String] = ["timber", "iron"]
const PROSPECT_TURNS: int = 1
const EXPLORE_MAX_TURNS: int = 3
## Town development tops out at 4; upgrade rows reuse the improvement table as
## the interim ruleset cost (wiki leaves it "per ruleset").
const MAX_TOWN: int = 4
## The Builder's town order needs National Bureaucracy (wiki:
## tech-tree-diplomacy-civilian). The province dossier's button and the work
## order's gate read this one id, so the button can never offer an order the
## rules refuse.
const TOWN_TECH: String = "national_bureaucracy"
const COMMODITY_NAMES: Dictionary = {
	"lumber": "lumber",
	"castIron": "cast iron",
	"steel": "steel",
	"bronze": "bronze",
	"paper": "paper",
}


static func cost_for(action: String, level: int = 1) -> Dictionary:
	if CivilianTransport.knows(action):
		return CivilianTransport.cost(action)
	if action == "build_fort":
		return FortRules.cost(clampi(level, 1, FortRules.MAX_LEVEL))
	if action == "build_hospital":
		return HospitalRules.cost(clampi(level, 1, HospitalRules.MAX_LEVEL))
	if action == "build_improvement" or action == "upgrade_town":
		return (
			IMPROVEMENT_COSTS[clampi(level, 1, LandWorks.MAX_IMPROVEMENT)] as Dictionary
		).duplicate()
	return {}


## The H8 feedstock bootstrap, level 1 only (wiki: extraction-and-improvements
## § H8 feedstock bootstrap): a level-0 raise on an unimproved timber or iron
## estate omits the manufacture inputs the court holds none of, breaking the
## circular dependency where sourcing lumber or cast iron itself requires the
## other. The `castIron` waiver runs while the stockpile holds at least one
## lumber but no cast iron; the `lumber` waiver adds the lumber when the
## stockpile holds neither, so the first feedstock estate is free. Once the
## court holds both inputs the full cost applies (issue #878).
static func bootstrap_cost(
	model: MapModel, tile: Vector2i, stockpile: Dictionary, level: int
) -> Dictionary:
	var cost: Dictionary = cost_for("build_improvement", level)
	if level != 1 or model == null or tile.x < 0:
		return cost
	var info: Dictionary = MapGenerator.resource_info(model.resource_at(tile.x, tile.y))
	if not FEEDSTOCK_RESOURCES.has(String(info.get("commodity", ""))):
		return cost
	if int(stockpile.get("castIron", 0)) >= 1:
		return cost
	# The castIron waiver: the raise pays no cast iron it does not hold.
	cost.erase("castIron")
	if int(stockpile.get("lumber", 0)) < 1:
		# The lumber waiver: the first feedstock estate is free.
		cost.erase("lumber")
	return cost


static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: PackedStringArray = PackedStringArray()
	for commodity: Variant in cost.keys():
		var id: String = String(commodity)
		parts.append("%d %s" % [int(cost[commodity]), String(COMMODITY_NAMES.get(id, id))])
	return " + ".join(parts)


## Wiki exploration time: ceil(3 × tiles / largest province), capped at 3.
static func explore_turns(model: MapModel, province_id: int) -> int:
	var tiles: int = model.province_tiles(province_id).size()
	if tiles <= 0:
		return 1
	var largest: int = 1
	for province: ProvinceState in model.provinces:
		largest = maxi(largest, int((province.tiles as Array).size()))
	var turns: int = int(ceil(3.0 * float(tiles) / float(largest)))
	return clampi(turns, 1, EXPLORE_MAX_TURNS)


## Fort the engineer would raise in this province next: level + 1, capped.
static func fort_target(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return FortRules.next_level(0)
	return FortRules.next_level(
		FortRules.level_at(model, model.province_at(tile.x, tile.y))
	)


## Hospital the engineer would raise in this province next: level + 1, capped.
static func hospital_target(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return HospitalRules.next_level(0)
	return HospitalRules.next_level(
		HospitalRules.level_at(model, model.province_at(tile.x, tile.y))
	)


## Town the Builder would raise next: current level + 1, capped at 4.
static func town_upgrade_level(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return 2
	var province: ProvinceState = model.province_data(model.province_at(tile.x, tile.y))
	if province == null:
		return 2
	return clampi(province.town_level() + 1, 2, MAX_TOWN)


## Town level a finished upgrade lands. The order is priced and gated for the
## level the town held when it was assigned, but the town can rise while the
## crew works — a Great Power seat moved to this province is set to 4 — so the
## finish lands the higher of the two and never lowers a town it finds raised.
static func town_after_upgrade(current: int, priced: int) -> int:
	return maxi(current, clampi(priced, 1, MAX_TOWN))


## Why this crown cannot raise the province's town now, or "" when the order is
## open. Ownership and the Builder are the work order's own business; this
## answers the gates the province dossier also has to show — the town, its
## ladder, the study and the stores (wiki: civilian-units § Builder;
## tech-tree-diplomacy-civilian). `stockpile` is the crown's own purse when the
## caller knows it; null leaves the money gate to the order that charges it.
static func town_upgrade_refusal(
	province: ProvinceState, tech_unlocked: Dictionary = {}, stockpile: Variant = null
) -> String:
	if province == null or not province.has_town():
		return "This province has no town to upgrade."
	if province.town_level() >= MAX_TOWN:
		return "This town is already fully developed."
	if not bool(tech_unlocked.get(TOWN_TECH, false)):
		return "Requires %s to upgrade a town." % TechCatalog.display_name(TOWN_TECH)
	return _known_stores_refusal(
		cost_for("upgrade_town", clampi(province.town_level() + 1, 2, MAX_TOWN)),
		stockpile
	)


## Why this crown cannot raise the province's wall now, or "" when the order is
## open. The province dossier's order and the walls ledger's rows read this one
## wording, so a row can never offer a wall the order would refuse (wiki:
## siege-mechanics § Fort Levels; DR-20261116-01). `stockpile` is the crown's
## own stores when the caller knows them; null leaves the money gate to the
## order that charges it.
static func fort_refusal(
	level: int, tech_unlocked: Dictionary = {}, stockpile: Variant = null
) -> String:
	if FortRules.clamp_level(level) >= FortRules.MAX_LEVEL:
		return "This province already holds a modern fort."
	var next: int = FortRules.next_level(level)
	var gate: String = FortRules.tech_gate(next)
	if not gate.is_empty() and not bool(tech_unlocked.get(gate, false)):
		return "A %s fort needs %s." % [
			FortRules.level_name(next), TechCatalog.display_name(gate)
		]
	return _known_stores_refusal(FortRules.cost(next), stockpile)


## The money gate the order itself charges, in the order's own wording: the
## materials the crown cannot pay today. Every surface that prices a spend reads
## this one sentence (wiki: civilian-units § Work Order Summary; REQ-P2-03).
static func stores_refusal(cost: Dictionary, stockpile: Dictionary) -> String:
	var short: Dictionary = ImprovementSystem.short_inputs(cost, stockpile)
	if short.is_empty():
		return ""
	return "Stores are short of %s." % cost_text(short)


## The same gate for a caller that may not know the purse: unknown stores (null)
## leave the money gate to the order that charges it, so a reading that never
## prices a spend is not told it is short.
static func _known_stores_refusal(cost: Dictionary, stockpile: Variant) -> String:
	if typeof(stockpile) != TYPE_DICTIONARY:
		return ""
	return stores_refusal(cost, stockpile as Dictionary)


## The per-player tile exclusivity rule the orders enforce, in the order's own
## wording: one Builder, Engineer or Merchant works a tile at a time (wiki:
## civilian-units § Per-player tile exclusivity). `crew` is the hand the order
## would send; a null hand is the row's own "no crew" word, not a busy tile.
## Every raise sheet reads this before it offers a press, so a row can never
## promise an order the exclusivity rule refuses (REQ-P2-03).
static func tile_busy_refusal(
	units: Array[CivilianState], crew: CivilianState, tile: Vector2i
) -> String:
	if crew == null:
		return ""
	var free: Dictionary = CivilianTransport.exclusive(units, crew, tile)
	if bool(free.get("ok", false)):
		return ""
	return String(free.get("reason", ""))


## Why this crown cannot raise the province's ward now, or "" when the order is
## open. The hospitals ledger's rows read this one wording, so a row can never
## offer a ward the order would refuse: the level cap and the study are
## `HospitalRules.refusal`'s own, and the materials are the work order's own
## shortfall sentence (wiki: combat § Regiment condition; DR-20261116-02).
## `stockpile` is `null` when the caller prices no spend at all — a projection
## that never charges a cost must never read LOCKED on an empty purse.
static func hospital_refusal(
	level: int, tech_unlocked: Dictionary = {}, stockpile: Variant = null
) -> String:
	var why: String = HospitalRules.refusal(level, tech_unlocked)
	if not why.is_empty():
		return why
	if stockpile == null:
		return ""
	var stock: Dictionary = stockpile if stockpile is Dictionary else {}
	var short: Dictionary = ImprovementSystem.short_inputs(
		HospitalRules.cost(HospitalRules.next_level(level)), stock
	)
	if short.is_empty():
		return ""
	return "Stores are short of %s." % cost_text(short)


## The order as the court reads it. A fort is the one order that lands at one of
## three levels, each with its own price, wait and tech gate, so the order names
## the level it would raise — "Build fort" alone cannot be told from "Build
## fort" for a higher wall (wiki: siege-mechanics § Fort Levels).
static func order_label(
	action: String, model: MapModel, tile: Vector2i, plain: String
) -> String:
	if action != "build_fort":
		return plain
	return "Build %s fort" % FortRules.level_name(fort_target(model, tile)).to_lower()


## One row of the work-order list: the label the court reads, the price beside
## it and the materials the rules charge. A fort's price also names the turns it
## takes, because its wall is the one order that arrives over several of them.
## The row also says what the work lands, for the works no ledger prices: the
## transport a road, a harbour or a railroad brings to the tile (DR-20261117-05).
static func option_row(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks,
	check: Dictionary, plain: String
) -> Dictionary:
	var cost: Dictionary = cost_for(action, cost_level(action, model, tile, works))
	var price: String = cost_text(cost)
	if action == LandPurchase.ACTION:
		price = String(check.get("cost_text", LandPurchase.cost_text(model, tile)))
	var row: Dictionary = {
		"label": order_label(action, model, tile, plain),
		"cost": cost,
		"cost_text": price,
		"preview_text": transport_preview(action, model, tile, works),
	}
	if action != "build_fort":
		return row
	var turns: int = duration_for(model, action, tile, works)
	row["cost_text"] = "%s · %d turn%s" % [price, turns, "" if turns == 1 else "s"]
	return row


## What a transport work lands on this tile, in the order's own words: the
## transport level the path will carry, which is the ceiling the Extraction
## formula puts on an estate here (wiki: extraction-and-improvements §
## Extraction; capital-and-connectivity § Path transport cap). A port is read as
## the landfall it is — a harbour tile carries the rail's transport and anchors
## the sea road. Empty for every other order: those are priced where their own
## ledger prints the payoff (REQ-P5-06, REQ-P2-03; DR-20261117-05).
static func transport_preview(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks
) -> String:
	if not CivilianTransport.knows(action):
		return ""
	var level: int = transport_after(action, works.transport_at(model, tile))
	var text: String = "Transport %d — an estate here gathers up to %d a turn" % [
		level, level
	]
	if action == "build_port":
		return "Landfall · " + text
	return text


## The transport level a finished work leaves on the tile: a road raises the
## path one step (level 2 at most), a railroad lands 4, and a harbour carries
## the rail's transport in the network's own reading (`LandConnectivity`).
static func transport_after(action: String, current: int) -> int:
	match action:
		"build_road":
			return mini(current + 1, LandWorks.TRANSPORT_IMPROVED_ROAD)
		"build_port", "build_rail":
			return LandWorks.TRANSPORT_RAIL
	return current


static func cost_level(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks
) -> int:
	if action == "upgrade_town":
		return town_upgrade_level(model, tile)
	if action == "build_fort":
		return fort_target(model, tile)
	if action == "build_hospital":
		return hospital_target(model, tile)
	return works.improvement_at(model, tile) + 1


static func duration_for(
	model: MapModel, action: String, tile: Vector2i, works: LandWorks
) -> int:
	match action:
		"explore":
			return explore_turns(model, model.province_at(tile.x, tile.y))
		"prospect":
			return PROSPECT_TURNS
		"build_improvement":
			return clampi(
				works.improvement_at(model, tile) + 1, 1, LandWorks.MAX_IMPROVEMENT
			)
		"upgrade_town":
			return town_upgrade_level(model, tile)
		"build_fort":
			return FortRules.turns(fort_target(model, tile))
		"build_hospital":
			return HospitalRules.turns(hospital_target(model, tile))
	if CivilianTransport.knows(action):
		return CivilianTransport.turns(action)
	return 1
