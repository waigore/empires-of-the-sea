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


## "Timber ×2  +  Iron ×1  →  1 Planks  ·  4 labour". A multi-turn row names
## its wait: "· 2 turns per run" (wiki: production-recipes § Turns per unit).
static func recipe_tooltip(recipe_id: String) -> String:
	var parts: PackedStringArray = []
	var inputs: Dictionary = ProductionRecipes.inputs(recipe_id)
	for commodity: Variant in inputs.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(commodity)), int(inputs[commodity])])
	var text: String = "  +  ".join(parts) + "  →  1 %s  ·  %d labour" % [
		CommodityCatalog.label(ProductionRecipes.output(recipe_id)),
		ProductionRecipes.labour(recipe_id),
	]
	var turns: int = ProductionRecipes.turns(recipe_id)
	if turns > 1:
		text += "  ·  %d turns per run" % turns
	return text


## The next-turn figure beside a holding: "" when the phase leaves the store
## alone, so no row carries a column of "+0" (wiki: stockpiles-and-production
## § Production flow; REQ-P5-05).
static func stock_delta_text(delta: int) -> String:
	if delta == 0:
		return ""
	return "%+d" % delta


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


## Summary line: treasury, idle/total labour, food need and strikers. The food
## need is every mouth the Consumption phase feeds — workers, the army, the navy
## and the hospital staffs (wiki: workers-and-population § Consumption).
static func summary(economy: PlayerEconomy, report: Dictionary) -> String:
	return "%s ducats   ·   labour %d / %d   ·   food need %d   ·   strikes %d" % [
		TextFormat.thousands(economy.treasury),
		idle_labour(report),
		economy.workers.labour(),
		economy.workers.food_demand() + army_food(report) + navy_food(report)
		+ hospital_food(report),
		int((report.get("consumption", {}) as Dictionary).get("strikers", 0)),
	]


## "Next turn:  Grain +3 · ducats -10" or the calm no-change line. A staged order
## settles at the auction after these phases, so the line names it rather than
## letting the promise read as the whole purse movement (wiki:
## stockpiles-and-production § Production flow, world-market § Trade orders).
static func preview(report: Dictionary) -> String:
	var parts: PackedStringArray = []
	var delta: Dictionary = report.get("stockpile_delta", {})
	for id: String in delta.keys():
		parts.append("%s %+d" % [CommodityCatalog.label(id), int(delta[id])])
	var treasury_delta: int = int(report.get("treasury_delta", 0))
	if treasury_delta != 0:
		parts.append("%s %+d" % ["ducats", treasury_delta])
	var staged: int = int(report.get("staged_orders", 0))
	var auction: String = _auction_line(staged)
	if parts.is_empty():
		var calm: String = "Next turn: no stock changes."
		if auction.is_empty():
			return calm
		return calm + "  " + auction
	var line: String = "Next turn:  " + "   ".join(parts)
	if auction.is_empty():
		return line
	return line + "   ·  " + auction


## "1 order settles at the auction." / "" when nothing is staged.
static func _auction_line(staged: int) -> String:
	if staged <= 0:
		return ""
	if staged == 1:
		return "1 order settles at the auction"
	return "%d orders settle at the auction" % staged


## The crown's overseas share of Minor and Tribe sales this clearing (wiki:
## world-market § First right of refusal, § Subsidy price adjustment). The
## clearing report carries it as `credits.by_gp`; a bare map is accepted too.
static func share_credit(report: Dictionary, faction: int) -> int:
	var credits: Dictionary = report.get("credits", {}) as Dictionary
	var by_gp: Dictionary = credits.get("by_gp", credits) as Dictionary
	return roundi(float(by_gp.get(faction, by_gp.get(str(faction), 0.0))))


## One line of the Deal Book. A purchase names the price the pair was charged —
## the crown's terms and the subsidy step included — and the ducats it cost; a
## sale names its receipt (wiki: world-market § Subsidy price adjustment;
## REQ-P5-05). `price` is the untaxed published price, so older saved rows that
## carry no `buy_unit` still read.
static func deal_line(deal: Dictionary, viewer: int = FactionCatalog.PLAYER_FACTION) -> String:
	var quantity: int = int(deal.get("quantity", 0))
	var commodity: String = CommodityCatalog.label(String(deal.get("commodity", "")))
	var price: int = int(deal.get("price", 0))
	var buyer: int = int(deal.get("buyer", -2))
	var seller: int = int(deal.get("seller", -2))
	var mine: bool = buyer == viewer
	var other_id: int = seller if mine else buyer
	var other: String = "the world market" if other_id < 0 else FactionCatalog.name_of(other_id)
	if mine:
		var claim: String = (
			" as its favoured partner" if bool(deal.get("is_favoured", false)) else ""
		)
		var unit: int = int(deal.get("buy_unit", price))
		return "Bought %d %s from %s at %d — %d ducats%s" % [
			quantity, commodity, other, unit, unit * quantity, claim,
		]
	var earned: int = int(deal.get("earned", price * quantity))
	# A sale's receipt is rounded from the whole deal, so the published price need
	# not multiply to it: name the rate that moved it (REQ-P5-05).
	var note: String = ""
	if quantity > 0 and price * quantity > 0 and earned != price * quantity:
		note = " (exports %d%%)" % roundi(100.0 * float(earned) / float(price * quantity))
	return "Sold %d %s to %s at %d — %d ducats%s" % [
		quantity, commodity, other, price, earned, note,
	]


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


static func army_food(report: Dictionary) -> int:
	return int((report.get("consumption", {}) as Dictionary).get("army_demand", 0))


static func navy_food(report: Dictionary) -> int:
	return int((report.get("consumption", {}) as Dictionary).get("navy_demand", 0))


## Rations the crown's hospital staffs eat this turn (wiki: combat § Regiment
## condition; DR-20261112-04).
static func hospital_food(report: Dictionary) -> int:
	return int((report.get("consumption", {}) as Dictionary).get("hospital_demand", 0))


## One-line market clearing report for the turn toast: the crown's fills and
## any carried or dropped orders (wiki: world-market § Trade orders). A sale
## names the ducats it paid, and the overseas share is named too: the auction
## is the one purse movement the per-turn figure cannot project.
static func market_summary(report: Dictionary, faction: int) -> String:
	var parts: PackedStringArray = []
	var fills: Dictionary = report.get("fills", {}) as Dictionary
	var mine: Dictionary = fills.get(faction, fills.get(str(faction), {})) as Dictionary
	var bought: int = int(mine.get("bought", 0))
	var sold: int = int(mine.get("sold", 0))
	if bought > 0:
		parts.append("bought %d for %d ducats" % [bought, int(mine.get("spent", 0))])
	if sold > 0:
		var earned: int = int(mine.get("earned", 0))
		parts.append(
			"sold %d for %d ducats" % [sold, earned] if earned > 0 else "sold %d" % sold
		)
	var share: int = share_credit(report, faction)
	if share > 0:
		parts.append("%d ducats in shares" % share)
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


## The rule that leaves a study unpaid: the Research phase may spend the treasury
## down to a floor the wiki sets by the techs the court knows (wiki:
## tech-tree-labour-economy § money_lending, banking). Naming it where the slot
## starves lets the crown read a rule instead of a broken purse (REQ-P5-05).
static func research_floor_line(floor: int) -> String:
	if floor >= 0:
		return (
			"research may not borrow yet: the treasury stops at %s ducats, and "
			+ "Money Lending would let it spend down to %s"
		) % [TextFormat.thousands(floor), TextFormat.thousands(ResearchFunding.DEBT_FLOOR)]
	if floor <= ResearchFunding.BANK_DEBT_FLOOR:
		return "Money Lending and Banking let research spend down to %s ducats" % (
			TextFormat.thousands(floor)
		)
	return (
		"Money Lending lets research spend the treasury down to %s ducats, "
		+ "and Banking would extend it to %s"
	) % [TextFormat.thousands(floor), TextFormat.thousands(ResearchFunding.BANK_DEBT_FLOOR)]


## The same rule in a despatch's few words: what stopped this turn's studies.
static func research_floor_note(floor: int) -> String:
	if floor >= 0:
		return "research may not borrow"
	return "the %s lending floor is reached" % TextFormat.thousands(floor)


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
	# Why a coast paid nothing this turn, in the court's own despatch
	# (wiki: capital-and-connectivity § Blockade; REQ-P5-05).
	var shut: String = String(report.get("blockade", ""))
	if not shut.is_empty():
		parts.append(shut)
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
	# A ward whose staff went unfed heals nothing next turn: say it, never
	# silently (wiki: combat § Regiment condition; DR-20261112-04).
	var hungry: Array = (report.get("hospital", {}) as Dictionary).get("hungry", [])
	if not hungry.is_empty():
		parts.append(
			"%d hospital%s unstaffed" % [hungry.size(), "" if hungry.size() == 1 else "s"]
		)
	var research: Dictionary = report.get("research", {})
	var researched: Array = research.get("researched", [])
	for tech_id: Variant in researched:
		parts.append("%s researched" % TechCatalog.display_name(String(tech_id)))
	var unpaid: Array = research.get("unpaid", [])
	if not unpaid.is_empty():
		var plural: String = "" if unpaid.size() == 1 else "s"
		parts.append("%d research slot%s unfunded — %s" % [
			unpaid.size(), plural,
			research_floor_note(int(research.get("floor", 0))),
		])
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
