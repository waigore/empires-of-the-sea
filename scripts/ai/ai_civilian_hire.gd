class_name AiCivilianHire
extends RefCounted
## The court's hire order: the roster it counts, the crew the published order
## takes first, the footings and purses that gate it, and the one crew the
## court's archetype keeps beyond the region's asks (wiki: civilian-build-planner;
## civilian-work-planner).
##
## The work pass (AiCivilianPlanner) owns what is genuinely per-run: the estate
## ledger read, the per-tile reservations, the scored candidates. The standing
## question that pass asks every turn has two halves: how many of each crew the
## region wants (`ai_civilian_targets.gd`, AiCivilianTargets) and this module —
## which hire the published order takes first, and which hire the court's taste
## leads with (AiStaffTaste). A court at war keeps its expansion door shut, and
## the closed hire says why (REQ-P5-05; DR-20261116-15). Pure rules: state in,
## one hire out; the map adapter applies it.

## Why a court at war hires no expansion crew, printed by the economy trace so
## the closed hire is never silent (REQ-P5-05; DR-20261116-15).
const REASON_CREWS: String = "at war: no new crew"
## Why a court banking for its army hires no crew its purse cannot spare, printed
## so the closed hire is never silent (issue #1059; the same plain-English shape).
const REASON_BANK: String = "the bank holds the purse: no spare crew"
## The two crews that serve the expansion doors the footing can shut.
const EXPANSION_CREWS: Array[String] = ["explorer", "merchant"]
## The crews the muster's own provision keeps: a Builder raises the ration
## estates and an Engineer links them to the crown network, so the food the
## army eats rides the works purse even while the court banks (issue #1059;
## the same provision clause the bank's farm trim and the farmhand hire ride).
const PROVISION_CREWS: Array[String] = ["builder", "engineer"]


## Next civilian to train: the published hire order, each step against the
## region's staff targets. A court whose staff already meets every target trains
## nothing — there is no staff cap and no unconditional builder fill (wiki:
## civilian-build-planner; DR staff lever). The exception is the crew the court's
## own archetype keeps beyond the region's asks: that target is one higher, so a
## court at the map's own target still hires in character (AiStaffTaste).
##
## A court at war hires no **expansion** crew: the Explorer and the Merchant
## serve the voyage and the Tribe chain the same footing holds shut, so the hire
## order stops at them and the yard keeps its coin for the muster
## (DR-20261116-15). Builders, Engineers and Spies are the front's own staff and
## stay open. A caller that passes no footing (`phase` absent) hires exactly as
## published.
static func training_order(
	config: AiConfig, units: Array, context: Dictionary
) -> Dictionary:
	if config == null or int(context.get("capital_province", -1)) < 0:
		return {}
	var own: Array[CivilianState] = owned_units(units, config.faction)
	var targets: Dictionary = context.get("staff_targets", {})
	# The region's own asks, so the order can name a hire the taste alone wanted.
	var region: Dictionary = context.get("own_targets", {})
	if targets.is_empty():
		region = AiCivilianTargets.region_targets(
			config, null, null, units, {}, {}, context
		)
		targets = AiStaffTaste.raises(config, region)
	# Discretionary hires (spy, merchant) spend the standing reserve. Extraction
	# staff — builders, engineers, explorers — may draw on the works purse while
	# the court is on `earn`, so a war chest does not freeze the mines that refill
	# it (issue #489 / #603 income lever).
	var hire_purse: int = int(context.get("hire_treasury", context.get("treasury", 0)))
	var works_purse: int = hire_purse
	if bool(context.get("earn", false)):
		works_purse = maxi(hire_purse, int(context.get("treasury", 0)))
	# The Merchant's own purse (issue #1225): the carve-outs below open the
	# gate; this purse pays the crew that walks through it.
	var merchant_purse: int = merchant_ride_purse(context)
	# The bank holds the purse (issue #1059): a court short of the bar banking
	# for its next line hires its provision crews — the Builder and the
	# Engineer the farms and their roads need — against the works purse, but
	# every other crew reads the standing purse, so the ladder the chart
	# grows does not burn the chest the muster waits for. The measured bench
	# banked 193 turns while the college re-hired an Explorer roughly every
	# tenth turn — a chest fill of ~16 ducats a turn against a 2,200 muster
	# chest. A caller with no bank reading keeps the published purses.
	var banked: bool = bool(context.get("conquest_bank", false))
	var queue: Array[String] = _hire_queue(
		own,
		targets,
		bool(context.get("at_war", false)),
		context.get("tech_unlocked", {}),
		merchant_purse,
		int(context.get("paper", 0)),
		bool(context.get("voyage_crew", false))
	)
	# The court's own crew leads once the region can spare it — a taste, never a
	# legality. A shut footing is not its to walk through: an expansion crew it
	# names falls back to the published order's own report.
	var type_id: String = AiStaffTaste.lead(config, queue, own)
	if not crews_open(context) and is_expansion_crew(type_id):
		type_id = ""
	if type_id.is_empty() and not queue.is_empty():
		type_id = queue[0]
	if type_id.is_empty() or not CivilianCatalog.is_implemented(type_id):
		return {}
	# The claim crew's own carve-out (issue #1139): a voyage already stranded is
	# the one case the claim pays for — #1127 / #1132 kept the aim open exactly
	# for it, and docs/ai.md names the claim's Merchant in the same clause. While
	# the claim stands (a stranded voyage still asks for a `merchant` crew), that
	# one Merchant is hired like a provision crew: the war footing and the bank
	# hold the expansion roster, not the rescue of the voyage the court already
	# paid for. Per-claim, not per-roster: only the crew the stranded claim asks
	# for opens, so the college cannot re-hire against the chest (#1059).
	var claim_crew: bool = (
		is_expansion_crew(type_id)
		and String(context.get("voyage_crew_kind", "")) == type_id
		and bool(context.get("voyage_stranded", false))
	)
	# The deed Merchant's own carve-out (#1139's shape, issue #1135): a priced,
	# openable deed is a purchase the court is saving toward — `market.deed` is
	# funded in its ledger — and the Merchant that walks to it was refused by
	# the same bank clause while the court banks, so the deed stayed priced,
	# openable and unsigned the whole campaign. The bank holds the roster, not
	# the one crew the court's own ledger is saving toward.
	var deed_crew: bool = (
		type_id == "merchant"
		and int(context.get("merchant_targets", 0)) > 0
		and int(context.get("deed_price", 0)) > 0
	)
	# The footing's own reading, never a legality gate: the hire is the court's
	# choice, and a crew it does hire still passes the same catalog gate
	# (DR-20261116-15).
	if not crews_open(context) and is_expansion_crew(type_id) and not claim_crew:
		return {"ok": false, "reason": REASON_CREWS}
	var tech: Dictionary = context.get("tech_unlocked", {})
	if not CivilianCatalog.is_unlocked(type_id, tech):
		return {}
	# The bank's own provision (issue #1059): the crews the farms and their
	# roads need keep the works purse — a chest that cannot exist for want
	# of fed hands and roads never arms a court — while the rest of the
	# ladder stands behind the chest with every other deferrable spend. The
	# stranded claim's Merchant rides the same provision (#1139), and so does
	# the deed Merchant while the court's own ledger funds its deed (#1135).
	if banked and not PROVISION_CREWS.has(type_id) and not claim_crew and not deed_crew:
		return {"ok": false, "reason": REASON_BANK}
	var purse: int = hire_purse
	if type_id == "builder" or type_id == "engineer" or type_id == "explorer":
		purse = works_purse
	elif type_id == "merchant":
		purse = merchant_purse
	if not CivilianCatalog.can_afford(
		type_id, purse, int(context.get("paper", 0))
	):
		return {}
	return {
		"ok": true,
		"type_id": type_id,
		"taste": AiStaffTaste.drives(config, type_id, targets, region, own),
	}


## True when the court's footing leaves the expansion-crew slot open. A caller
## that passes no `phase` (fixtures, the mainline planners) reads the published
## behaviour: every crew is open.
static func crews_open(context: Dictionary) -> bool:
	return AiPhasePlanner.opens(
		String(context.get("phase", AiPhasePlanner.PHASE_UNKNOWN)),
		AiPhasePlanner.SLOT_CREWS
	)


## True for the crews the voyage and the Tribe chain need: Explorer, Merchant.
static func is_expansion_crew(type_id: String) -> bool:
	return EXPANSION_CREWS.has(type_id)


## The purse the Merchant's hire draws on while its own carve-out stands: the
## works purse the deed's own purchase prices against (`LandPurchase.check`
## reads the region's `treasury` row), for a priced, openable deed (#1135) or a
## stranded claim's Merchant (#1139); the standing purse for every other hire —
## the bank holds the roster, not the purse the deed's chain funds (#1225).
static func merchant_ride_purse(context: Dictionary) -> int:
	var hire: int = int(context.get("hire_treasury", context.get("treasury", 0)))
	if not bool(context.get("earn", false)):
		return hire
	var works: int = maxi(hire, int(context.get("treasury", 0)))
	var claim: bool = bool(context.get("voyage_stranded", false)) \
		and String(context.get("voyage_crew_kind", "")) == "merchant"
	var deed: bool = int(context.get("merchant_targets", 0)) > 0 \
		and int(context.get("deed_price", 0)) > 0
	return works if claim or deed else hire


## The court's civilian roster, in the order every hiring pass reads it: one
## estate-ledger read, one hire order, one reservation per crew.
static func owned_units(units: Array, owner: int) -> Array[CivilianState]:
	var roster: Array[CivilianState] = []
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner:
			roster.append(unit)
	roster.sort_custom(func(a: CivilianState, b: CivilianState) -> bool: return a.id < b.id)
	return roster


## The crew the hire order would take if the purse allowed: the first name in
## the published queue, whether or not the court can pay for it. Empty when every
## target is already met. The market keeps its price back from this turn's bids,
## so a court that has lost a crew can still buy another (issue #894).
static func next_crew(config: AiConfig, units: Array, context: Dictionary) -> String:
	if config == null:
		return ""
	var targets: Dictionary = context.get("staff_targets", {})
	if targets.is_empty():
		return ""
	var queue: Array[String] = _hire_queue(
		owned_units(units, config.faction),
		targets,
		bool(context.get("at_war", false)),
		context.get("tech_unlocked", {}),
		0,
		int(context.get("paper", 0)),
		bool(context.get("voyage_crew", false))
	)
	return queue[0] if not queue.is_empty() else ""


## The crews the court may hire this turn, in the published order: builders,
## engineers, the deed partner once the first two crews stand, a war spy screen
## before another explorer, then the peace spy, then a merchant when a deed is
## on offer or an envoy chain toward one is openable. Empty when every target is
## already met; which of them is taken is the caller's (AiStaffTaste.lead).
##
## `voyage_crew` puts the Explorer first: a court whose last Explorer would sail
## with the colony takes the second crew before the estate queue, so the voyage
## leaves a prospector on the home hills (issue #894).
static func _hire_queue(
	roster: Array[CivilianState],
	targets: Dictionary,
	at_war: bool = false,
	tech_unlocked: Dictionary = {},
	treasury: int = 0,
	paper: int = 0,
	voyage_crew: bool = false
) -> Array[String]:
	var builders: int = 0
	var engineers: int = 0
	var explorers: int = 0
	var spies: int = 0
	var merchants: int = 0
	for unit: CivilianState in roster:
		if unit.type_id == "builder":
			builders += 1
		elif unit.type_id == "engineer":
			engineers += 1
		elif unit.type_id == "explorer":
			explorers += 1
		elif unit.type_id == "spy":
			spies += 1
		elif unit.type_id == "merchant":
			merchants += 1
	var queue: Array[String] = []
	if voyage_crew and explorers < int(targets.get("explorer", 0)):
		queue.append("explorer")
	if builders < int(targets.get("builder", 0)):
		queue.append("builder")
	if engineers < int(targets.get("engineer", 0)):
		queue.append("engineer")
	# The deed partner waits on the crew, not on the estate queue: with the first
	# Builder and Engineer standing, one Merchant is taken ahead of the second
	# Builder and the survey queue — a hire parked behind an unbounded target is
	# a deed never signed (issue #841; wiki: civilian-units § Merchant).
	var deeds: bool = merchants < int(targets.get("merchant", 0))
	var merchant_ready: bool = CivilianCatalog.is_unlocked("merchant", tech_unlocked) and (
		CivilianCatalog.can_afford("merchant", treasury, paper)
	)
	if deeds and merchant_ready and builders >= 1 and engineers >= 1:
		queue.append("merchant")
	if at_war and spies < int(targets.get("spy", 0)):
		queue.append("spy")
	if explorers < int(targets.get("explorer", 0)):
		queue.append("explorer")
	if spies < int(targets.get("spy", 0)) and not queue.has("spy"):
		queue.append("spy")
	if deeds and merchant_ready and not queue.has("merchant"):
		queue.append("merchant")
	return queue
