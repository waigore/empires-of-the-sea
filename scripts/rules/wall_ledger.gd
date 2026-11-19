class_name WallLedger
extends RefCounted
## The crown's walls: every province it holds that can carry a fort, the level
## it stands at and the step the Engineer would take next (wiki: siege-mechanics
## § Fort Levels, § Wall Protection, § Emplaced Artillery; DR-20261116-01).
## Pure read-only projection — the price, the wait and the gate are `FortRules`'
## own table, the very one the work order charges, so a row can never offer a
## wall the rules would refuse (REQ-P2-03, REQ-P3-02).
##
## The province dossier prints one province's fort; the military lens prints
## every charted province's band; this sheet is the decision the level raises —
## which of the crown's own shores stand bare, what the next wall costs, what it
## waits on and who is free to raise it — so a crown walls its frontier from one
## page instead of thirty dossiers (REQ-P5-03, REQ-P5-04). The snapshot walk, the
## chip tallies and the reading order are [RaiseLedger]'s; the wall row, the
## states and the words are this sheet's own.

## What the wall's next step is waiting on. One state per row, so the reading
## chips and the row's own word can never disagree.
const STATE_READY: String = RaiseLedger.STATE_READY
const STATE_AT_WORK: String = RaiseLedger.STATE_AT_WORK
const STATE_NO_ENGINEER: String = "no_engineer"
const STATE_LOCKED: String = RaiseLedger.STATE_LOCKED
const STATE_RAISED: String = "raised"

const FILTER_ALL: String = "all"
const FILTER_READY: String = "ready"
const FILTER_AT_WORK: String = "at_work"
const FILTER_RAISED: String = "raised"
const FILTERS: Array[String] = [FILTER_ALL, FILTER_READY, FILTER_AT_WORK, FILTER_RAISED]

## Every state a row can carry, in the order the snapshot tallies them.
const STATES: Array[String] = [
	STATE_READY, STATE_AT_WORK, STATE_NO_ENGINEER, STATE_LOCKED, STATE_RAISED
]

## The order the sheet prints its states in: what can be raised now leads, what
## is already in hand follows, and what is finished reads last.
const STATE_ORDER: Dictionary = {
	STATE_READY: 0,
	STATE_AT_WORK: 1,
	STATE_NO_ENGINEER: 2,
	STATE_LOCKED: 3,
	STATE_RAISED: 4,
}

const ROMAN: Array[String] = ["—", "I", "II", "III"]


## Whole-empire snapshot in reading order. `regions` is one entry per chart:
## {region, model, units, tech_unlocked, stockpile} — the crown's crews there,
## the studies it holds and the stores the next step is paid from. A chart with
## no model is skipped, so a one-region world reads as one heading. A province
## with no town tile and no seat cannot carry a wall (the fort is raised on the
## town tile), so it earns no row.
static func snapshot(regions: Array[Dictionary], owner: int) -> Dictionary:
	return RaiseLedger.snapshot(regions, owner, _row, STATES, STATE_ORDER)


## Rows narrowed to one chart and one reading, grouped under their chart.
static func groups(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> Array[Dictionary]:
	return RaiseLedger.groups(data, region_key, filter_key)


static func count(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> int:
	return RaiseLedger.count(data, region_key, filter_key)


## How many walls each reading would show inside one chart, so a chip carries
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
		FILTER_RAISED:
			return "Walled"
	return "All walls"


## What a crown's holdings read as, wall by wall, inside one chart: how many
## shores stand bare, how many are walled and how many are citadels. A chip
## narrows the reading; this line answers the question a crown asks first —
## "where is nothing standing?" — without a filter of its own.
static func summary(data: Dictionary, region_key: String) -> Dictionary:
	var reading: Dictionary = {"total": 0, "bare": 0, "walled": 0, "citadel": 0}
	for group: Dictionary in groups(data, region_key, FILTER_ALL):
		for raw: Variant in group.get("rows", []):
			var level: int = int((raw as Dictionary).get("level", 0))
			reading["total"] = int(reading["total"]) + 1
			if level <= 0:
				reading["bare"] = int(reading["bare"]) + 1
			elif level >= FortRules.MAX_LEVEL:
				reading["citadel"] = int(reading["citadel"]) + 1
			else:
				reading["walled"] = int(reading["walled"]) + 1
	return reading


## The level as the court reads it: a wall is a numeral, and an open shore is a
## dash rather than a zero (P1).
static func level_text(level: int) -> String:
	return RaiseLedger.numeral(ROMAN, level, FortRules.MAX_LEVEL)


## The rule a crown pays by, printed on the sheet rather than hidden in a hover
## (wiki: siege-mechanics § Wall Protection, § Emplaced Artillery).
static func rule_note() -> String:
	return (
		"A wall soaks the attack before it tells: 10 / 20 / 30 wall hp by level, "
		+ "and 1–3 emplaced guns that fire with the garrison. The last gun falls "
		+ "even when an assault is repelled, so a wall is worth the turn it takes."
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
	var site: Vector2i = FortRules.site_tile(model, province.id)
	if site.x < 0:
		return {}
	var level: int = FortRules.clamp_level(province.fort_level)
	var next: int = FortRules.next_level(level)
	var refusal: String = CivilianWorkRefusals.fort(level, tech_unlocked, stockpile)
	var crew: CivilianState = RaiseLedger.crew_for(units, province.owner, site, "build_fort")
	# What the next step waits on, worst first: a finished wall, a crew already
	# at work, the study the order needs, a free Engineer, else the order is
	# open.
	var state: String = RaiseLedger.state_for(
		level,
		FortRules.MAX_LEVEL,
		crew,
		refusal,
		ImprovementOrders.nearest_engineer(units, province.owner, site) != null,
		STATE_RAISED,
		STATE_NO_ENGINEER
	)
	var cost: Dictionary = FortRules.cost(next)
	var cost_text: String = CivilianWorkPlan.cost_text(cost)
	var turns: int = FortRules.turns(next)
	var row: Dictionary = RaiseLedger.row_head(province, region, level, level_text(level))
	row.merge(RaiseLedger.row_step(state, crew, cost_text, turns))
	row["cost"] = cost
	row["line"] = FortRules.describe(level)
	row["guns"] = FortRules.guns(level)
	row["wall_hp"] = int(round(FortRules.wall_hp(level)))
	row["next_level"] = next
	row["next_name"] = FortRules.level_name(next)
	row["note"] = _note(state, next, cost_text, turns, refusal, crew)
	# The raise is priced, so the prize is too: the soak and the battery the
	# next wall brings, read off the same fort table the order charges. A
	# finished wall and one an Engineer is already raising have no level to
	# price (REQ-P2-03, REQ-P5-06; DR-20261117-05).
	row["preview_text"] = (
		preview_text(level, next)
		if state != STATE_RAISED and state != STATE_AT_WORK
		else ""
	)
	return row


## What one more wall buys, in the sheet's own words: the soak it stands behind
## and the battery it mounts, with the step the crown pays for. The figures are
## `FortRules`' own table, the one combat resolves against, so a row can never
## sell a wall the battle would not honour (REQ-P2-03). Empty at the top level:
## there is no raise to price.
static func preview_text(level: int, next: int) -> String:
	if level >= FortRules.MAX_LEVEL:
		return ""
	var pieces: int = FortRules.guns(next)
	var add_guns: int = pieces - FortRules.guns(level)
	var add_hp: int = roundi(FortRules.wall_hp(next) - FortRules.wall_hp(level))
	return "L%d soaks %d wall hp with %d gun%s (+%d hp, +%d gun%s)" % [
		next,
		roundi(FortRules.wall_hp(next)),
		pieces,
		"" if pieces == 1 else "s",
		add_hp,
		add_guns,
		"" if add_guns == 1 else "s",
	]


static func _note(
	state: String,
	next: int,
	cost_text: String,
	turns: int,
	refusal: String,
	crew: CivilianState
) -> String:
	match state:
		STATE_RAISED:
			return "Fully walled — %d guns, %d wall hp." % [
				FortRules.guns(next), int(round(FortRules.wall_hp(next)))
			]
		STATE_AT_WORK:
			var target: int = crew.work_detail("fort_level", next)
			return RaiseLedger.at_work_note(
				crew, "the %s fort" % FortRules.level_name(target).to_lower()
			)
		STATE_LOCKED:
			return refusal
		STATE_NO_ENGINEER:
			return RaiseLedger.no_crew_note("Engineer")
	return RaiseLedger.next_note(
		"%s fort" % FortRules.level_name(next).to_lower(), cost_text, turns
	)
