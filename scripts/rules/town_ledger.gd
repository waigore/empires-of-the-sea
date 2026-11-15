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
## towns from one page instead of thirty dossiers (REQ-P5-04). The snapshot walk,
## the chip tallies and the reading order are [RaiseLedger]'s; the town row, the
## states and the words are this sheet's own.

## What the town's next step is waiting on. One state per row, so the reading
## chips and the row's own word can never disagree.
const STATE_READY: String = RaiseLedger.STATE_READY
const STATE_AT_WORK: String = RaiseLedger.STATE_AT_WORK
const STATE_NO_BUILDER: String = "no_builder"
const STATE_LOCKED: String = RaiseLedger.STATE_LOCKED
const STATE_DEVELOPED: String = "developed"

const FILTER_ALL: String = "all"
const FILTER_READY: String = "ready"
const FILTER_AT_WORK: String = "at_work"
const FILTER_DEVELOPED: String = "developed"
const FILTERS: Array[String] = [FILTER_ALL, FILTER_READY, FILTER_AT_WORK, FILTER_DEVELOPED]

## Every state a row can carry, in the order the snapshot tallies them.
const STATES: Array[String] = [
	STATE_READY, STATE_AT_WORK, STATE_NO_BUILDER, STATE_LOCKED, STATE_DEVELOPED
]

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


## Whole-empire snapshot in reading order. `regions` is one entry per chart:
## {region, model, units, tech_unlocked, stockpile} — the crown's crews there,
## the studies it holds and the stores the next step is paid from. A chart with
## no model is skipped, so a one-region world reads as one heading.
static func snapshot(regions: Array[Dictionary], owner: int) -> Dictionary:
	return RaiseLedger.snapshot(regions, owner, _row, STATES, STATE_ORDER, _admits)


## Rows narrowed to one chart and one reading, grouped under their chart.
static func groups(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> Array[Dictionary]:
	return RaiseLedger.groups(data, region_key, filter_key)


static func count(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> int:
	return RaiseLedger.count(data, region_key, filter_key)


## How many towns each reading would show inside one chart, so a chip carries
## its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	return RaiseLedger.filter_counts(data, region_key, FILTERS)


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
	return RaiseLedger.numeral(ROMAN, level, CivilianWorkPlan.MAX_TOWN, 1)


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


## Only a province with a town carries the work.
static func _admits(province: ProvinceState) -> bool:
	return province.has_town()


static func _row(
	model: MapModel,
	province: ProvinceState,
	region: int,
	units: Array[CivilianState],
	tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> Dictionary:
	var level: int = province.town_level()
	var town: Vector2i = province.town_site()
	var next_level: int = clampi(level + 1, 2, CivilianWorkPlan.MAX_TOWN)
	var cost_text: String = CivilianWork.cost_text(
		CivilianWork.cost_for("upgrade_town", next_level)
	)
	var turns: int = CivilianWorkPlan.duration_for(model, "upgrade_town", town, null)
	var refusal: String = CivilianWorkPlan.town_upgrade_refusal(
		province, tech_unlocked, stockpile
	)
	var crew: CivilianState = RaiseLedger.crew_for(
		units, province.owner, town, "upgrade_town"
	)
	var hand: CivilianState = ImprovementOrders.nearest_builder(units, province.owner, town)
	if refusal.is_empty():
		# The town tile is shared with the wall and the ward, so another crew
		# already at work there is the order's own refusal, not a press (wiki:
		# civilian-units § Per-player tile exclusivity).
		refusal = CivilianWorkPlan.tile_busy_refusal(units, hand, town)
	# What the next step waits on, worst first: a finished town, a crew already
	# at work, the study, the stores or the busy tile the order needs, a free
	# Builder, else the order is open.
	var state: String = RaiseLedger.state_for(
		level,
		CivilianWorkPlan.MAX_TOWN,
		crew,
		refusal,
		hand != null,
		STATE_DEVELOPED,
		STATE_NO_BUILDER
	)
	var row: Dictionary = RaiseLedger.row_head(province, region, level, level_text(level))
	row.merge(RaiseLedger.row_step(state, crew, cost_text, turns))
	row["next_level"] = next_level
	row["next_text"] = level_text(next_level)
	row["note"] = _note(state, next_level, cost_text, turns, refusal, crew)
	return row


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
			return RaiseLedger.at_work_note(crew, "it to %s" % level_text(target))
		STATE_LOCKED:
			return refusal
		STATE_NO_BUILDER:
			return RaiseLedger.no_crew_note("Builder")
	return RaiseLedger.next_note(level_text(next_level), cost_text, turns)
