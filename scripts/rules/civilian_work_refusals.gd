class_name CivilianWorkRefusals
extends RefCounted
## Why a civilian work order cannot start, in the order's own wording (wiki:
## civilian-units § Work Order Summary; siege-mechanics § Fort Levels). Pure
## rules: ledgers, the province dossier and [CivilianWorkGates] share one
## sentence so a row never offers what the order would refuse (REQ-P3-01,
## REQ-P2-03). Cost and duration maths stay on [CivilianWorkPlan].


## Why this crown cannot raise the province's town now, or "" when the order is
## open. Ownership and the Builder are the work order's own business; this
## answers the gates the province dossier also has to show — the town, its
## ladder, the study and the stores (wiki: civilian-units § Builder;
## tech-tree-diplomacy-civilian). `stockpile` is the crown's own purse when the
## caller knows it; null leaves the money gate to the order that charges it.
static func town_upgrade(
	province: ProvinceState, tech_unlocked: Dictionary = {}, stockpile: Variant = null
) -> String:
	if province == null or not province.has_town():
		return "This province has no town to upgrade."
	if province.town_level() >= CivilianWorkPlan.MAX_TOWN:
		return "This town is already fully developed."
	if not bool(tech_unlocked.get(CivilianWorkPlan.TOWN_TECH, false)):
		return "Requires %s to upgrade a town." % TechCatalog.display_name(
			CivilianWorkPlan.TOWN_TECH
		)
	return known_stores(
		CivilianWorkPlan.cost_for(
			"upgrade_town",
			clampi(province.town_level() + 1, 2, CivilianWorkPlan.MAX_TOWN)
		),
		stockpile
	)


## Why this crown cannot raise the province's wall now, or "" when the order is
## open. The province dossier's order and the walls ledger's rows read this one
## wording, so a row can never offer a wall the order would refuse (wiki:
## siege-mechanics § Fort Levels; DR-20261116-01). `stockpile` is the crown's
## own stores when the caller knows them; null leaves the money gate to the
## order that charges it.
static func fort(
	level: int, tech_unlocked: Dictionary = {}, stockpile: Variant = null
) -> String:
	if FortRules.clamp_level(level) >= FortRules.MAX_LEVEL:
		return "This province already holds a %s fort." % FortRules.level_name(
			FortRules.MAX_LEVEL
		).to_lower()
	var next: int = FortRules.next_level(level)
	var gate: String = FortRules.tech_gate(next)
	if not gate.is_empty() and not bool(tech_unlocked.get(gate, false)):
		return "A %s fort needs %s." % [
			FortRules.level_name(next), TechCatalog.display_name(gate)
		]
	return known_stores(FortRules.cost(next), stockpile)


## Why this crown cannot raise the province's ward now, or "" when the order is
## open. The hospitals ledger's rows read this one wording, so a row can never
## offer a ward the order would refuse: the level cap and the study are
## `HospitalRules.refusal`'s own, and the materials are the work order's own
## shortfall sentence (wiki: combat § Regiment condition; DR-20261116-02).
## `stockpile` is `null` when the caller prices no spend at all — a projection
## that never charges a cost must never read LOCKED on an empty purse.
static func hospital(
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
	return "Stores are short of %s." % CivilianWorkPlan.cost_text(short)


## The money gate the order itself charges, in the order's own wording: the
## materials the crown cannot pay today. Every surface that prices a spend reads
## this one sentence (wiki: civilian-units § Work Order Summary; REQ-P2-03).
static func stores(cost: Dictionary, stockpile: Dictionary) -> String:
	var short: Dictionary = ImprovementSystem.short_inputs(cost, stockpile)
	if short.is_empty():
		return ""
	return "Stores are short of %s." % CivilianWorkPlan.cost_text(short)


## The same gate for a caller that may not know the purse: unknown stores (null)
## leave the money gate to the order that charges it, so a reading that never
## prices a spend is not told it is short.
static func known_stores(cost: Dictionary, stockpile: Variant) -> String:
	if typeof(stockpile) != TYPE_DICTIONARY:
		return ""
	return stores(cost, stockpile as Dictionary)


## The per-player tile exclusivity rule the orders enforce, in the order's own
## wording: one Builder, Engineer or Merchant works a tile at a time (wiki:
## civilian-units § Per-player tile exclusivity). `crew` is the hand the order
## would send; a null hand is the row's own "no crew" word, not a busy tile.
## Every raise sheet reads this before it offers a press, so a row can never
## promise an order the exclusivity rule refuses (REQ-P2-03).
static func tile_busy(
	units: Array[CivilianState], crew: CivilianState, tile: Vector2i
) -> String:
	if crew == null:
		return ""
	var free: Dictionary = CivilianTransport.exclusive(units, crew, tile)
	if bool(free.get("ok", false)):
		return ""
	return String(free.get("reason", ""))
