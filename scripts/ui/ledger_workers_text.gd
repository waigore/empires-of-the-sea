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
