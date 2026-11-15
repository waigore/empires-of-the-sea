class_name TownLedger
extends RefCounted
## The crown's towns: every province it holds that has a town, the level it
## stands at and the step the Builder would take next (wiki:
## extraction-and-improvements § Town manufacturing bonus, civilian-units
## § Builder upgrade_town; DR-20261115-12). Pure read-only projection — the
## price, the wait and the gate are the work plan's own maths, so a row can
## never offer an order the rules would refuse (REQ-P2-03, REQ-P3-02).
##
## The province ledger already prints each province's town level; this sheet is
## the decision the level raises — what the next step costs, what it waits on
## and who is free to take it — so a crown with thirty provinces raises its
## towns from one page instead of thirty dossiers (REQ-P5-04).

## What the town's next step is waiting on. One state per row, so the reading
## chips and the row's own word can never disagree.
const STATE_READY: String = "ready"
const STATE_AT_WORK: String = "at_work"
const STATE_NO_BUILDER: String = "no_builder"
const STATE_LOCKED: String = "locked"
const STATE_DEVELOPED: String = "developed"

const FILTER_ALL: String = "all"
const FILTER_READY: String = "ready"
const FILTER_AT_WORK: String = "at_work"
const FILTER_DEVELOPED: String = "developed"
const FILTERS: Array[String] = [FILTER_ALL, FILTER_READY, FILTER_AT_WORK, FILTER_DEVELOPED]

## The order the sheet prints its states in: what can be raised now leads, what
## is already in hand follows, and what is finished reads last.
const STATE_ORDER: Dictionary = {
	STATE_READY: 0,
	STATE_AT_WORK: 1,
	STATE_NO_BUILDER: 2,
	STATE_LOCKED: 3,
	STATE_DEVELOPED: 4,
}

const ROMAN: Array[String] = ["", "I", "II", "III", "IV"]
const NO_ID: int = -1


## Whole-empire snapshot in reading order. `regions` is one entry per chart:
## {region, model, units, tech_unlocked} — the crown's crews there and the
## studies it holds. A chart with no model is skipped, so a one-region world
## reads as one heading.
static func snapshot(regions: Array[Dictionary], owner: int) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {
		STATE_READY: 0,
		STATE_AT_WORK: 0,
		STATE_NO_BUILDER: 0,
		STATE_LOCKED: 0,
		STATE_DEVELOPED: 0,
	}
	for entry: Dictionary in regions:
		var model := entry.get("model") as MapModel
		if model == null:
			continue
		var region: int = int(entry.get("region", model.region_id))
		var units: Array[CivilianState] = []
		units.assign(entry.get("units", []))
		var tech_unlocked: Dictionary = entry.get("tech_unlocked", {})
		## The crown's own stores, when the caller knows them: the row reads the
		## same money gate the order charges (REQ-P2-03).
		var stockpile: Variant = entry.get("stockpile", null)
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != owner or not province.has_town():
				continue
			var row: Dictionary = _row(
				model, province, region, units, tech_unlocked, stockpile
			)
			rows.append(row)
			var state: String = String(row["state"])
			counts[state] = int(counts.get(state, 0)) + 1
	rows.sort_custom(_before)
	return {
		"rows": rows,
		"groups": LedgerRows.group(rows),
		"counts": counts,
		"total": rows.size(),
	}


## Rows narrowed to one chart and one reading, grouped under their chart.
static func groups(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> Array[Dictionary]:
	return LedgerRows.groups(data, region_key, matches.bind(filter_key))


static func count(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> int:
	return LedgerRows.count(data, region_key, matches.bind(filter_key))


## How many towns each reading would show inside one chart, so a chip carries
## its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	return LedgerRows.counts(data, region_key, FILTERS, matches)


static func matches(row: Dictionary, filter_key: String) -> bool:
	return LedgerRows.field_matches(row, "state", filter_key)


## One-word name of a reading, for its chip and the sheet's count line.
static func filter_label(key: String) -> String:
	match key:
		FILTER_READY:
			return "Ready"
		FILTER_AT_WORK:
			return "At work"
		FILTER_DEVELOPED:
			return "Developed"
	return "All towns"


## The level as the court reads it: a town is a numeral, not a number.
static func level_text(level: int) -> String:
	return ROMAN[clampi(level, 1, CivilianWorkPlan.MAX_TOWN)]


## The rule a crown needs before it pays for a level: the bonus sits at 2 and 4
## only, and it is made from the raw the town's own estates deliver (wiki:
## extraction-and-improvements § Town manufacturing bonus).
static func bonus_note() -> String:
	return (
		"A town pays manufactures at levels 2 and 4 only — level 3 buys the road "
		+ "to 4. The bonus is made from the raw its own estates deliver, so a town "
		+ "with no works pays nothing."
	)


# --- rows -------------------------------------------------------------------


static func _row(
	model: MapModel,
	province: ProvinceState,
	region: int,
	units: Array[CivilianState],
	tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> Dictionary:
	var level: int = province.town_level()
	var town: Vector2i = _town_tile(province)
	var next_level: int = clampi(level + 1, 2, CivilianWorkPlan.MAX_TOWN)
	var cost_text: String = CivilianWork.cost_text(
		CivilianWork.cost_for("upgrade_town", next_level)
	)
	var turns: int = CivilianWorkPlan.duration_for(model, "upgrade_town", town, null)
	var refusal: String = CivilianWorkPlan.town_upgrade_refusal(
		province, tech_unlocked, stockpile
	)
	var crew: CivilianState = _crew(units, province.owner, town)
	var state: String = _state(level, crew, refusal, units, province.owner, town)
	return {
		"id": province.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"name": String(province.name),
		"capital": province.capital,
		"level": level,
		"level_text": level_text(level),
		"next_level": next_level,
		"next_text": level_text(next_level),
		"cost_text": cost_text,
		"turns": turns,
		"state": state,
		"crew": String(crew.display_name()) if crew != null else "",
		"remaining": crew.remaining_turns() if crew != null else 0,
		"note": _note(state, next_level, cost_text, turns, refusal, crew),
	}


## The town tile the order would be filed on: the province's own town, or the
## seat on a hand-built chart that predates town assignment — the same two
## steps `ImprovementOrders.upgrade_town` takes.
static func _town_tile(province: ProvinceState) -> Vector2i:
	if province.town_tile.x >= 0:
		return province.town_tile
	if province.capital:
		return province.capital_tile
	return Vector2i(-1, -1)


## What the next step waits on, worst first: a finished town, a crew already at
## work, the study the order needs, a free Builder, else the order is open.
static func _state(
	level: int,
	crew: CivilianState,
	refusal: String,
	units: Array[CivilianState],
	owner: int,
	town: Vector2i
) -> String:
	if level >= CivilianWorkPlan.MAX_TOWN:
		return STATE_DEVELOPED
	if crew != null:
		return STATE_AT_WORK
	if not refusal.is_empty():
		return STATE_LOCKED
	if ImprovementOrders.nearest_builder(units, owner, town) == null:
		return STATE_NO_BUILDER
	return STATE_READY


## The Builder already raising this town, read from the crew's own record so
## the row names the level the order was priced for.
static func _crew(
	units: Array[CivilianState], owner: int, town: Vector2i
) -> CivilianState:
	for raw: Variant in units:
		var unit := raw as CivilianState
		if unit == null or unit.owner != owner or not unit.is_working():
			continue
		if unit.work_action() == "upgrade_town" and unit.work_tile() == town:
			return unit
	return null


static func _note(
	state: String,
	next_level: int,
	cost_text: String,
	turns: int,
	refusal: String,
	crew: CivilianState
) -> String:
	match state:
		STATE_DEVELOPED:
			return "Fully developed — level 4 pays ×2 manufactures."
		STATE_AT_WORK:
			var target: int = crew.work_detail("town_level", next_level)
			var left: int = crew.remaining_turns()
			return "%s raises it to %s · %d turn%s left." % [
				crew.display_name(), level_text(target), left, "" if left == 1 else "s"
			]
		STATE_LOCKED:
			return refusal
		STATE_NO_BUILDER:
			return "No idle Builder musters — train one at the capital."
	return "Next: %s · %s · %d turn%s" % [
		level_text(next_level), cost_text, turns, "" if turns == 1 else "s"
	]


# --- assembly ---------------------------------------------------------------


## Reading order: what can be raised now, then what is in hand, then what waits
## on a study or a crew, and the finished towns last. Within a state the
## cheapest step leads, so a crown reads its purse before its ambition.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	var left: int = int(STATE_ORDER.get(String(a["state"]), 9))
	var right: int = int(STATE_ORDER.get(String(b["state"]), 9))
	if left != right:
		return left < right
	if int(a["level"]) != int(b["level"]):
		return int(a["level"]) < int(b["level"])
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	return int(a["id"]) < int(b["id"])
