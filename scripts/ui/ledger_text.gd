class_name LedgerText
extends RefCounted
## Plain-text (and pure) formatting for the economy ledger: recipe titles and
## tooltips, worker recruit cost lines, the summary/preview strings and the
## whole-number money formatter. No visual nodes, so it is cheap to unit test
## (REQ-P3-03).


## "Planks (Timber)" — output plus its single input when the recipe has one.
static func recipe_title(recipe_id: String) -> String:
	var text: String = CommodityCatalog.label(ProductionRecipes.output(recipe_id))
	var inputs: Dictionary = ProductionRecipes.inputs(recipe_id)
	if inputs.size() == 1:
		text += " (%s)" % CommodityCatalog.label(String(inputs.keys()[0]))
	return text


## "Timber ×2  +  Iron ×1  →  1 Planks  ·  4 labour".
static func recipe_tooltip(recipe_id: String) -> String:
	var parts: PackedStringArray = []
	var inputs: Dictionary = ProductionRecipes.inputs(recipe_id)
	for commodity: Variant in inputs.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(commodity)), int(inputs[commodity])])
	return "  +  ".join(parts) + "  →  1 %s  ·  %d labour" % [
		CommodityCatalog.label(ProductionRecipes.output(recipe_id)),
		ProductionRecipes.labour(recipe_id),
	]


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


## Summary line: treasury, idle/total labour, food need and strikers.
static func summary(economy: PlayerEconomy, report: Dictionary) -> String:
	return "%s ducats   ·   labour %d / %d   ·   food need %d   ·   strikes %d" % [
		TextFormat.thousands(economy.treasury),
		idle_labour(report),
		economy.workers.labour(),
		economy.workers.food_demand() + navy_food(report),
		int((report.get("consumption", {}) as Dictionary).get("strikers", 0)),
	]


## "Next turn:  Grain +3 · ducats -10" or the calm no-change line.
static func preview(report: Dictionary) -> String:
	var parts: PackedStringArray = []
	var delta: Dictionary = report.get("stockpile_delta", {})
	for id: String in delta.keys():
		parts.append("%s %+d" % [CommodityCatalog.label(id), int(delta[id])])
	var treasury_delta: int = int(report.get("treasury_delta", 0))
	if treasury_delta != 0:
		parts.append("%s %+d" % ["ducats", treasury_delta])
	if parts.is_empty():
		return "Next turn: no stock changes."
	return "Next turn:  " + "   ".join(parts)


## The cargo-holds banner above the market rows (wiki: ships-and-naval).
## Extraction ships before trade, so the banner names the colonial tonnage the
## home fleet must carry first (DR-20261109-17).
static func cargo_line(cargo: Dictionary) -> String:
	var holds: int = int(cargo.get("holds", -1))
	if holds < 0:
		return "Cargo holds unknown."
	if holds <= 0:
		return "No cargo holds — launch a merchant hull or moor the home squadron."
	var free: int = int(cargo.get("free", holds))
	var reserved: int = int(cargo.get("reserved", 0))
	if reserved > 0:
		return "CARGO  %d holds  ·  %d for the colonies  ·  %d free this turn" % [
			holds, reserved, free
		]
	return "CARGO  %d holds  ·  %d free this turn" % [holds, free]


static func cargo_color(cargo: Dictionary) -> Color:
	var holds: int = int(cargo.get("holds", -1))
	if holds < 0:
		return Palette.TEXT_DIM
	if holds <= 0:
		return Palette.GOLD_PALE
	return Palette.TEXT


static func idle_labour(report: Dictionary) -> int:
	return int((report.get("consumption", {}) as Dictionary).get("idle_labour", 0))


static func navy_food(report: Dictionary) -> int:
	return int((report.get("consumption", {}) as Dictionary).get("navy_demand", 0))


## One-line market clearing report for the turn toast: the crown's fills and
## any carried or dropped orders (wiki: world-market § Trade orders).
static func market_summary(report: Dictionary, faction: int) -> String:
	var parts: PackedStringArray = []
	var fills: Dictionary = report.get("fills", {}) as Dictionary
	var mine: Dictionary = fills.get(faction, fills.get(str(faction), {})) as Dictionary
	var bought: int = int(mine.get("bought", 0))
	var sold: int = int(mine.get("sold", 0))
	if bought > 0:
		parts.append("bought %d for %d ducats" % [bought, int(mine.get("spent", 0))])
	if sold > 0:
		parts.append("sold %d" % sold)
	var carry: int = (report.get("carry", []) as Array).size()
	if carry > 0:
		parts.append("%d order%s carried" % [carry, "" if carry == 1 else "s"])
	var dropped: int = 0
	for note: Variant in report.get("notes", []):
		if typeof(note) != TYPE_DICTIONARY:
			continue
		var code: String = String((note as Dictionary).get("code", ""))
		if code.begins_with("carry_forward_dropped") and int(
			(note as Dictionary).get("faction", -1)
		) == faction:
			dropped += 1
	if dropped > 0:
		parts.append("%d order%s lapsed" % [dropped, "" if dropped == 1 else "s"])
	if parts.is_empty():
		return ""
	return "The market cleared: " + "  ·  ".join(parts) + "."


## One-line turn summary for the toast channel: what the resolved turn did.
static func turn_summary(report: Dictionary) -> String:
	var parts: PackedStringArray = []
	var extracted: Dictionary = report.get("extraction", {})
	if not extracted.is_empty():
		parts.append("gathered %s" % ImprovementSystem.output_text(extracted))
	var overseas: Dictionary = report.get("overseas", {})
	var landed: int = int(overseas.get("used", 0))
	if landed > 0:
		parts.append("%d colonial tons landed" % landed)
	var made: Dictionary = overseas.get("manufactured", {})
	if not made.is_empty():
		parts.append("%s made in colonial towns" % ImprovementSystem.output_text(made))
	var left: int = int(overseas.get("left_total", 0))
	if left > 0:
		parts.append("%d left on the far shore" % left)
	var treasury: int = int(report.get("riches_treasury", 0))
	if treasury > 0:
		parts.append("+%d from riches" % treasury)
	var production: Dictionary = report.get("production", {})
	var produced: Dictionary = production.get("produced", {})
	for id: String in produced.keys():
		parts.append("%s +%d" % [CommodityCatalog.label(id), int(produced[id])])
	var consumption: Dictionary = report.get("consumption", {})
	var eaters: int = int(consumption.get("food_eaten", 0))
	if eaters > 0:
		parts.append("%d food eaten" % eaters)
	var strikes: int = int(consumption.get("strikers", 0))
	if strikes > 0:
		parts.append("%d on strike" % strikes)
	var research: Dictionary = report.get("research", {})
	var researched: Array = research.get("researched", [])
	for tech_id: Variant in researched:
		parts.append("%s researched" % TechCatalog.display_name(String(tech_id)))
	var unpaid: Array = research.get("unpaid", [])
	if not unpaid.is_empty():
		var plural: String = "" if unpaid.size() == 1 else "s"
		parts.append("%d research slot%s unfunded" % [unpaid.size(), plural])
	var lifted: Array = research.get("boosted", [])
	if not lifted.is_empty():
		parts.append(
			"%d stud%s quickened by the spy network" % [
				lifted.size(), "y" if lifted.size() == 1 else "ies"
			]
		)
	if parts.is_empty():
		return "The ledgers balance — nothing moved this turn."
	return "  ·  ".join(parts)
