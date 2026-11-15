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
const NO_ID: int = -1


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
	return ROMAN[clampi(level, 0, FortRules.MAX_LEVEL)]


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
	var refusal: String = CivilianWorkPlan.fort_refusal(level, tech_unlocked, stockpile)
	var crew: CivilianState = _crew(units, province.owner, site)
	var state: String = _state(level, crew, refusal, units, province.owner, site)
	var cost_text: String = CivilianWorkPlan.cost_text(FortRules.cost(next))
	return {
		"id": province.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"name": String(province.name),
		"capital": province.capital,
		"level": level,
		"level_text": level_text(level),
		"line": FortRules.describe(level),
		"guns": FortRules.guns(level),
		"wall_hp": int(round(FortRules.wall_hp(level))),
		"next_level": next,
		"next_name": FortRules.level_name(next),
		"cost_text": cost_text,
		"turns": FortRules.turns(next),
		"state": state,
		"crew": String(crew.display_name()) if crew != null else "",
		"remaining": crew.remaining_turns() if crew != null else 0,
		"note": _note(state, next, cost_text, refusal, crew),
	}


## What the next step waits on, worst first: a finished wall, a crew already at
## work, the study the order needs, a free Engineer, else the order is open.
static func _state(
	level: int,
	crew: CivilianState,
	refusal: String,
	units: Array[CivilianState],
	owner: int,
	site: Vector2i
) -> String:
	return RaiseLedger.state_for(
		level,
		FortRules.MAX_LEVEL,
		crew,
		refusal,
		ImprovementOrders.nearest_engineer(units, owner, site) != null,
		STATE_RAISED,
		STATE_NO_ENGINEER
	)


## The Engineer already raising this wall, read from the crew's own record so
## the row names the level the order was priced for.
static func _crew(
	units: Array[CivilianState], owner: int, site: Vector2i
) -> CivilianState:
	return RaiseLedger.crew_for(units, owner, site, "build_fort")


static func _note(
	state: String, next: int, cost_text: String, refusal: String, crew: CivilianState
) -> String:
	match state:
		STATE_RAISED:
			return "Fully walled — %d guns, %d wall hp." % [
				FortRules.guns(next), int(round(FortRules.wall_hp(next)))
			]
		STATE_AT_WORK:
			var target: int = crew.work_detail("fort_level", next)
			var left: int = crew.remaining_turns()
			return "%s raises the %s fort · %d turn%s left." % [
				crew.display_name(), FortRules.level_name(target).to_lower(), left,
				"" if left == 1 else "s",
			]
		STATE_LOCKED:
			return refusal
		STATE_NO_ENGINEER:
			return "No idle Engineer musters — train one at the capital."
	var turns: int = FortRules.turns(next)
	return "Next: %s fort · %s · %d turn%s" % [
		FortRules.level_name(next).to_lower(), cost_text, turns, "" if turns == 1 else "s",
	]
