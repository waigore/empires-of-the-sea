class_name LedgerWorkersText
extends RefCounted
## Plain-text (and pure) formatting for the WORKERS tab: what one hire costs,
## what a batch costs and the promise a disband makes. No visual nodes, so it is
## cheap to unit test (REQ-P3-03).


## "120 ducats   Fabric ×2" — the visible cost of recruiting one tier.
static func recruit_cost(tier: int) -> String:
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	var materials: Dictionary = cost.get("materials", {})
	var parts: PackedStringArray = []
	if int(cost.get("treasury", 0)) > 0:
		parts.append("%d ducats" % int(cost.get("treasury", 0)))
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
		parts.append("%d ducats" % gold)
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
		parts.append("%d ducats" % int(cost.get("treasury", 0)))
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
