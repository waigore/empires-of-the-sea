class_name LedgerReportText
extends RefCounted
## Plain-text (and pure) formatting for the court's own ledger: the economy
## summary, the Consumption reads it counts, the research floor's rule and the
## one-line turn toast. No visual nodes, so it is cheap to unit test
## (REQ-P3-03).


## Summary line: treasury, idle/total labour, food need and strikers. The food
## need is every mouth the Consumption phase feeds — workers, the army, the navy
## and the hospital staffs (wiki: workers-and-population § Consumption).
static func summary(economy: PlayerEconomy, report: Dictionary) -> String:
	return "%s   ·   labour %d / %d   ·   food need %d   ·   strikes %d" % [
		MoneyText.ducats(economy.treasury),
		idle_labour(report),
		economy.workers.labour(),
		economy.workers.food_demand() + army_food(report) + navy_food(report)
		+ hospital_food(report),
		int(_consumption(report).get("strikers", 0)),
	]


## The phase's own Consumption record. Every figure below reads this one slice,
## so a report without it feeds nobody and strikes nobody.
static func _consumption(report: Dictionary) -> Dictionary:
	return report.get("consumption", {}) as Dictionary


static func idle_labour(report: Dictionary) -> int:
	return int(_consumption(report).get("idle_labour", 0))


static func army_food(report: Dictionary) -> int:
	return int(_consumption(report).get("army_demand", 0))


static func navy_food(report: Dictionary) -> int:
	return int(_consumption(report).get("navy_demand", 0))


## Rations the crown's hospital staffs eat this turn (wiki: combat § Regiment
## condition; DR-20261112-04).
static func hospital_food(report: Dictionary) -> int:
	return int(_consumption(report).get("hospital_demand", 0))


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
## `trouble_only` keeps just the lines that ask the crown to act — a sealed
## coast, a strike, an unfed ward, a study the purse could not pay. The dispatch
## lane raises that cut and leaves the harvest, the overseas deliveries and the
## finished study to the ledger sheet and the Gazette (wiki: hud-toasts).
static func turn_summary(report: Dictionary, trouble_only: bool = false) -> String:
	var parts: PackedStringArray = []
	var trouble: PackedStringArray = []
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
		# The number names its rule: the holds were the cap, not the harvest
		# (wiki: ships-and-naval § Cargo holds and capacity; DR-20261116-05).
		parts.append("%d left on the far shore — the holds were full" % left)
	# Why a coast paid nothing this turn, in the court's own despatch
	# (wiki: capital-and-connectivity § Blockade; REQ-P5-05).
	var shut: String = String(report.get("blockade", ""))
	if not shut.is_empty():
		trouble.append(shut)
	var treasury: int = int(report.get("riches_treasury", 0))
	if treasury > 0:
		parts.append("+%s from riches" % MoneyText.thousands(treasury))
	var production: Dictionary = report.get("production", {})
	var produced: Dictionary = production.get("produced", {})
	for id: String in produced.keys():
		parts.append("%s +%d" % [CommodityCatalog.label(id), int(produced[id])])
	var consumption: Dictionary = _consumption(report)
	var eaters: int = int(consumption.get("food_eaten", 0))
	if eaters > 0:
		parts.append("%d food eaten" % eaters)
	var strikes: int = int(consumption.get("strikers", 0))
	if strikes > 0:
		trouble.append("%d on strike" % strikes)
	# A ward whose staff went unfed keeps its walls but loses its nurses: say it,
	# never silently (wiki: combat § Regiment condition; DR-20261112-04).
	var hungry: Array = (report.get("hospital", {}) as Dictionary).get("hungry", [])
	if not hungry.is_empty():
		trouble.append(
			"%d hospital%s unstaffed" % [hungry.size(), "" if hungry.size() == 1 else "s"]
		)
	var research: Dictionary = report.get("research", {})
	var researched: Array = research.get("researched", [])
	for tech_id: Variant in researched:
		parts.append("%s researched" % TechCatalog.display_name(String(tech_id)))
	var unpaid: Array = research.get("unpaid", [])
	if not unpaid.is_empty():
		var plural: String = "" if unpaid.size() == 1 else "s"
		trouble.append("%d research slot%s unfunded — %s" % [
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
	if trouble_only:
		if trouble.is_empty():
			return ""
		return "  ·  ".join(trouble)
	if parts.is_empty() and trouble.is_empty():
		return "The ledgers balance — nothing moved this turn."
	return "  ·  ".join(parts + trouble)
