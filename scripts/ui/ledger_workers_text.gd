class_name LedgerWorkersText
extends RefCounted
## Plain-text (and pure) formatting for the WORKERS tab: what one hire costs,
## what a batch costs, the promise a disband makes and the larder's own reading.
## No visual nodes, so it is cheap to unit test (REQ-P3-03).

## The tab's one standing promise, above the larder it answers.
const INTRO: String = (
	"Trained workers eat grain, meat and their tier luxury. Disband refunds nothing."
)


## "Store 16 food · Fur Hats ×1" — the larder as it stands, naming only the
## luxuries this pool actually wants.
static func larder_store(read: Dictionary) -> String:
	var parts: PackedStringArray = ["%d food" % int(read["store_food"])]
	var store: Dictionary = read["store_luxury"]
	for id: Variant in store.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(id)), int(store[id])])
	return "Store " + "  ·  ".join(parts)


## "20 food wanted — army 8 · navy 4 · pool 6 · wards 2 · Refined Sugar ×3", or
## the short form "24 mouths eat 24 food" when the pool is the only appetite.
## Every appetite the phase pays is named in its own deduction order, because the
## army and the navy eat before the pool: a store that covers the pool alone still
## strikes it, and a reading that showed only the pool's mouths had the store
## cover them (wiki: workers-and-population § Consumption; REQ-P2-03).
static func larder_appetite(read: Dictionary) -> String:
	var appetites: Dictionary = read.get("appetites", {}) as Dictionary
	var army: int = int(appetites.get("army", 0))
	var navy: int = int(appetites.get("navy", 0))
	var pool: int = int(appetites.get("pool", int(read["food"])))
	var wards: int = int(appetites.get("wards", 0))
	var text: String
	if army + navy + wards <= 0:
		text = "%d mouths eat %d food" % [int(read["mouths"]), pool]
	else:
		var parts: PackedStringArray = []
		if army > 0:
			parts.append("army %d" % army)
		if navy > 0:
			parts.append("navy %d" % navy)
		if pool > 0:
			parts.append("pool %d" % pool)
		if wards > 0:
			parts.append("wards %d" % wards)
		text = "%d food wanted — %s" % [
			army + navy + pool + wards, " · ".join(parts),
		]
	var want: Dictionary = read["luxury"]
	for id: Variant in want.keys():
		text += "  ·  %s ×%d" % [CommodityCatalog.label(String(id)), int(want[id])]
	var arriving: int = int(read["arriving"])
	if arriving > 0:
		text += "  ·  %d arriving" % arriving
	return text


## "Short 2 food — 1 striker, masters first." or the calm cover line. Food is
## named first because the phase feeds it before any luxury, and the tier named
## is the one a shortfall bites first: the highest tier in the pool
## (wiki: workers-and-population § Consumption). The figure is the **whole
## larder's** shortfall — every appetite the phase pays, not the pool alone — so a
## store that keeps the workers fed while a ward or an army goes short never
## reads calm (total food demand = workers + navy + army + hospital staffs), and
## the mouth that missed is named from the dry run's own fed figures.
static func larder_shortfall(read: Dictionary) -> String:
	var short: int = int(read.get("store_short", read.get("food_short", 0)))
	var strikers: int = int(read["strikers"])
	if strikers <= 0:
		if short <= 0:
			return "The larder covers every mouth."
		return "Short %d food — %s." % [short, larder_hungry_mouth(read)]
	var tier: int = int(read["striking_tier"])
	var who: String = "%d striker%s, %s first" % [
		strikers,
		"" if strikers == 1 else "s",
		WorkerPool.tier_name(maxi(tier, 0)).to_lower(),
	]
	if short > 0:
		return "Short %d food — %s." % [short, who]
	var luxuries: Dictionary = read["luxury_short"]
	for id: Variant in luxuries.keys():
		return "Short %d %s — %s." % [
			int(luxuries[id]), CommodityCatalog.label(String(id)), who
		]
	return "The larder runs short — %s." % who


## The appetite the dry run could not serve, in the phase's own order, for a
## crown whose workers ate: a starving army or navy, or a ward that lost its
## staff (wiki: combat § Regiment condition; DR-20261112-04).
static func larder_hungry_mouth(read: Dictionary) -> String:
	var report: Dictionary = read.get("report", {}) as Dictionary
	if int(report.get("army_demand", 0)) > int(report.get("army_fed", 0)):
		return "the army goes short"
	if int(report.get("navy_demand", 0)) > int(report.get("navy_fed", 0)):
		return "the navy goes short"
	if int(report.get("hospital_demand", 0)) > int(report.get("hospital_fed", 0)):
		return "the wards go unfed"
	return "the store cannot cover every mouth"


## "120 ducats   Fabric ×2" — the visible cost of recruiting one tier.
static func recruit_cost(tier: int) -> String:
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	var materials: Dictionary = cost.get("materials", {})
	var parts: PackedStringArray = []
	if int(cost.get("treasury", 0)) > 0:
		parts.append(MoneyText.ducats(int(cost.get("treasury", 0))))
	for commodity: Variant in materials.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(commodity)), int(materials[commodity])])
	return "   ".join(parts)


## The whole batch's price: "600 ducats and Paper ×6" — the row's promise before
## the press, so a batch is never a surprise (REQ-P5-05).
static func recruit_batch_cost(tier: int, count: int) -> String:
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	var parts: PackedStringArray = []
	var gold: int = int(cost.get("treasury", 0)) * count
	if gold > 0:
		parts.append(MoneyText.ducats(gold))
	var materials: Dictionary = cost.get("materials", {})
	for commodity: Variant in materials.keys():
		parts.append(
			"%s ×%d"
			% [CommodityCatalog.label(String(commodity)), int(materials[commodity]) * count]
		)
	return " and ".join(parts)


## "Send one back to the fields — no recruit cost is refunded. An apprentice eats
## 2 food and a unit of Refined Sugar a turn." The row's promise and its saving.
static func disband_hint(tier: int) -> String:
	var one: String = WorkerPool.tier_one(tier).to_lower()
	var article: String = "an" if one.begins_with("a") else "a"
	var eats: String = "%d food" % WorkerPool.FOOD_PER_WORKER[tier]
	var luxury: String = WorkerPool.luxury_for(tier)
	if not luxury.is_empty():
		eats += " and a unit of %s" % CommodityCatalog.label(luxury)
	return (
		"Send one back to the fields — no recruit cost is refunded. %s %s eats %s a turn."
		% [article.capitalize(), one, eats]
	)


## "Recruit 200 ducats · Paper ×2" / "Recruit Fabric ×2" — the price a row pays
## for one head, built from the same cost row the order charges (REQ-P2-03).
static func recruit_price(tier: int) -> String:
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	var materials: Dictionary = cost.get("materials", {})
	var parts: PackedStringArray = []
	if int(cost.get("treasury", 0)) > 0:
		parts.append(MoneyText.ducats(int(cost.get("treasury", 0))))
	for commodity: Variant in materials.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(commodity)), int(materials[commodity])])
	return "Recruit " + " · ".join(parts)


## What one worker of the tier eats at a Consumption: a peasant takes one food
## unit from either larder; every trained tier takes one grain **and** one meat
## plus its own luxury (wiki: workers-and-population § Worker Tiers;
## economy_consumption.gd `_feed_worker`).
static func ration_line(tier: int) -> String:
	if not WorkerPool.is_trained(tier):
		return "eats 1 grain or meat a turn"
	var text: String = "eats 1 grain + 1 meat"
	var luxury: String = WorkerPool.luxury_for(tier)
	if not luxury.is_empty():
		text += " and %s" % CommodityCatalog.label(luxury)
	return text + " a turn"


## "needs Apprentice Workers and Sugar Refining" — the studies a locked tier
## waits on, named from the gate table, so a touch row is never silent
## (wiki: workers-and-population § Tech gates; REQ-P1-05, REQ-P5-05).
static func gate_line(missing: Array[String]) -> String:
	var names: PackedStringArray = []
	for tech: String in missing:
		names.append(TechCatalog.display_name(tech))
	if names.is_empty():
		return ""
	return "needs " + _join_names(names)


## "A" / "A and B" / "A, B and C" — one clause for the two gates and the many.
static func _join_names(names: PackedStringArray) -> String:
	if names.size() <= 1:
		return names[0] if names.size() == 1 else ""
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]


## The one dim line under a tier row: the price it pays, then either the study
## it waits on (a locked tier), the rule that stops it, or the ration it eats.
## Every clause is its own table's, so the row can promise no rule the order
## would refuse (REQ-P2-03, REQ-P5-05, REQ-P5-06).
static func recruit_line(tier: int, reason: String, missing: Array[String]) -> String:
	var price: String = recruit_price(tier)
	if not missing.is_empty():
		return "%s — %s" % [price, gate_line(missing)]
	if not reason.is_empty():
		return "%s — %s" % [price, reason.to_lower()]
	return "%s — %s" % [price, ration_line(tier)]
