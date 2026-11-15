class_name HospitalLedger
extends RefCounted
## The crown's hospitals: every province it holds that can carry a ward, the
## level it stands at, whether its staff ate this turn and the step the Engineer
## would take next (wiki: combat § Regiment condition; DR-20261116-02).
## Pure read-only projection — the price, the wait and the gate are
## `HospitalRules`' own table, the very one the work order charges, so a row can
## never offer a ward the rules would refuse (REQ-P2-03, REQ-P3-02).
##
## The province dossier prints one province's ward and the defence lens marks
## where one stands; this sheet is the decision the level raises — which of the
## crown's own shores keep no ward, what the next one costs, what it waits on,
## who is free to raise it and what the whole staff eats — so a crown heals its
## armies from one page instead of thirty dossiers (REQ-P5-03, REQ-P5-04).
## The snapshot walk, the chip tallies and the state ladder are
## [RaiseLedger]'s; the ward row, its states and its words are this sheet's own
## (REQ-P3-01).

## What the ward's next step is waiting on. One state per row, so the reading
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

const ROMAN: Array[String] = ["—", "I", "II"]
const NO_ID: int = -1


## Whole-empire snapshot in reading order. `regions` is one entry per chart:
## {region, model, units, tech_unlocked, stockpile} — the crown's crews there,
## the studies it holds and the stores the next step is paid from. A chart with
## no model is skipped, so a one-region world reads as one heading. A province
## with no town tile and no seat cannot carry a ward (it is raised on the town
## tile), so it earns no row.
static func snapshot(regions: Array[Dictionary], owner: int) -> Dictionary:
	return RaiseLedger.snapshot(regions, owner, _row, STATES, STATE_ORDER, Callable(), _before)


## Rows narrowed to one chart and one reading, grouped under their chart.
static func groups(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> Array[Dictionary]:
	return RaiseLedger.groups(data, region_key, filter_key)


static func count(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> int:
	return RaiseLedger.count(data, region_key, filter_key)


## How many wards each reading would show inside one chart, so a chip carries
## its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	return RaiseLedger.filter_counts(data, region_key, FILTERS)


## A ward reading is the row's own state word.
static func matches(row: Dictionary, filter_key: String) -> bool:
	return RaiseLedger.matches(row, filter_key)


## One-word name of a reading, for its chip and the sheet's count line.
static func filter_label(key: String) -> String:
	match key:
		FILTER_READY:
			return "Ready"
		FILTER_AT_WORK:
			return "At work"
		FILTER_RAISED:
			return "Warded"
	return "All wards"


## What a crown's holdings read as, ward by ward, inside one chart: how many
## shores keep none, how many are ready, at work or standing, how many went
## unfed this turn and what the whole staff eats. A chip narrows the reading;
## this line answers the questions a crown asks first — "where does nothing
## heal?" and "what does the ward bill come to?" — without a filter of its own.
static func summary(data: Dictionary, region_key: String) -> Dictionary:
	var reading: Dictionary = {
		"total": 0,
		"bare": 0,
		"ready": 0,
		"at_work": 0,
		"standing": 0,
		"unfed": 0,
		"ration": 0,
	}
	for group: Dictionary in groups(data, region_key, FILTER_ALL):
		for raw: Variant in group.get("rows", []):
			var row: Dictionary = raw
			var level: int = int(row.get("level", 0))
			reading["total"] = int(reading["total"]) + 1
			var state: String = String(row.get("state", ""))
			if state == STATE_READY:
				reading["ready"] = int(reading["ready"]) + 1
			elif state == STATE_AT_WORK:
				reading["at_work"] = int(reading["at_work"]) + 1
			if level <= 0:
				reading["bare"] = int(reading["bare"]) + 1
				continue
			reading["standing"] = int(reading["standing"]) + 1
			reading["ration"] = int(reading["ration"]) + int(row.get("demand", 0))
			if not bool(row.get("staffed", true)):
				reading["unfed"] = int(reading["unfed"]) + 1
	return reading


## The level as the court reads it: a ward is a numeral, and an empty shore is a
## dash rather than a zero (P1).
static func level_text(level: int) -> String:
	return ROMAN[clampi(level, 0, HospitalRules.MAX_LEVEL)]


## The rule a crown pays by, printed on the sheet rather than hidden in a hover
## (wiki: combat § Regiment condition; DR-20261112-04). An unfed ward keeps its
## walls and loses its nurses, so the note says what it still heals rather than
## claiming it heals nothing.
static func rule_note() -> String:
	var top: int = HospitalRules.MAX_LEVEL
	return (
		"A ward sets the tempo an army recovers at — rest %d%% at a field ward and "
		+ "%d%% at a general one, and the wear a defeat leaves cut to %d%% and "
		+ "%d%%. Its staff eats %d food a turn per level; a ward the larder cannot "
		+ "cover goes unfed — its walls still shelter the wounded, but its nurses "
		+ "are lost and the province rests at the field's %d%%."
	) % [
		roundi(HospitalRules.rest_share(1) * 100.0),
		roundi(HospitalRules.rest_share(top) * 100.0),
		roundi(HospitalRules.triage_scale(1) * 100.0),
		roundi(HospitalRules.triage_scale(top) * 100.0),
		HospitalRules.RATION_PER_LEVEL,
		roundi(RegimentCondition.REST_SHARE * 100.0),
	]


# --- rows -------------------------------------------------------------------


static func _row(
	model: MapModel,
	province: ProvinceState,
	region: int,
	units: Array[CivilianState],
	tech_unlocked: Dictionary,
	stockpile: Variant
) -> Dictionary:
	var site: Vector2i = HospitalRules.site_tile(model, province.id)
	if site.x < 0:
		return {}
	var level: int = HospitalRules.clamp_level(province.hospital_level)
	var next: int = HospitalRules.next_level(level)
	var staffed: bool = province.hospital_staffed
	var crew: CivilianState = _crew(units, province.owner, site)
	var hand: CivilianState = ImprovementOrders.nearest_engineer(units, province.owner, site)
	var refusal: String = CivilianWorkPlan.hospital_refusal(level, tech_unlocked, stockpile)
	if refusal.is_empty():
		# The ward shares the town tile with the town and the wall, so another
		# crew already at work there is the order's own refusal, not a press
		# (wiki: civilian-units § Per-player tile exclusivity).
		refusal = CivilianWorkPlan.tile_busy_refusal(units, hand, site)
	var state: String = _state(level, crew, refusal, hand)
	var cost_text: String = CivilianWorkPlan.cost_text(HospitalRules.cost(next))
	return {
		"id": province.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"name": String(province.name),
		"capital": province.capital,
		"level": level,
		"level_text": level_text(level),
		"line": HospitalRules.describe(level, staffed),
		"staffed": level > 0 and staffed,
		"demand": HospitalRules.food_demand(level),
		"next_level": next,
		"next_name": HospitalRules.level_name(next),
		"cost_text": cost_text,
		"turns": HospitalRules.turns(next),
		"state": state,
		"crew": String(crew.display_name()) if crew != null else "",
		"remaining": crew.remaining_turns() if crew != null else 0,
		"note": _note(state, level, next, cost_text, refusal, crew, staffed),
	}


## What the next step waits on, worst first: a finished ward, a crew already at
## work, the study, the stores or the busy tile the order needs, a free
## Engineer, else the order is open.
static func _state(
	level: int, crew: CivilianState, refusal: String, hand: CivilianState
) -> String:
	return RaiseLedger.state_for(
		level,
		HospitalRules.MAX_LEVEL,
		crew,
		refusal,
		hand != null,
		STATE_RAISED,
		STATE_NO_ENGINEER
	)


## The Engineer already raising this ward, read from the crew's own record so
## the row names the level the order was priced for.
static func _crew(
	units: Array[CivilianState], owner: int, site: Vector2i
) -> CivilianState:
	return RaiseLedger.crew_for(units, owner, site, "build_hospital")


static func _note(
	state: String,
	level: int,
	next: int,
	cost_text: String,
	refusal: String,
	crew: CivilianState,
	staffed: bool
) -> String:
	match state:
		STATE_RAISED:
			if not staffed:
				# A ward that went unfed keeps its walls and loses its nurses:
				# the province rests at the field's share, not the ward's
				# (wiki: combat § Regiment condition; DR-20261112-04).
				return "Fully warded — rest %d%% this turn, the staff went unfed; wear %d%%." % [
					roundi(RegimentCondition.REST_SHARE * 100.0),
					roundi(HospitalRules.triage_scale(level) * 100.0),
				]
			return "Fully warded — rest %d%%, wear %d%%, staff %d food a turn." % [
				roundi(HospitalRules.rest_share(level) * 100.0),
				roundi(HospitalRules.triage_scale(level) * 100.0),
				HospitalRules.food_demand(level),
			]
		STATE_AT_WORK:
			var target: int = crew.work_detail("hospital_level", next)
			var left: int = crew.remaining_turns()
			return "%s raises the %s · %d turn%s left." % [
				crew.display_name(), HospitalRules.level_name(target).to_lower(), left,
				"" if left == 1 else "s",
			]
		STATE_LOCKED:
			return refusal
		STATE_NO_ENGINEER:
			return "No idle Engineer musters — train one at the capital."
	var turns: int = HospitalRules.turns(next)
	return "Next: %s · %s · %d turn%s" % [
		HospitalRules.level_name(next).to_lower(), cost_text, turns,
		"" if turns == 1 else "s",
	]


# --- assembly ---------------------------------------------------------------


## Reading order: what can be raised now, then what is in hand, then what waits
## on a study, a purse or a crew, and the finished wards last. Within a state
## the weakest ward leads, and a ward that went unfed leads its own state, so a
## crown heals a hungry empty shore before a full one.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	var left: int = int(STATE_ORDER.get(String(a["state"]), 9))
	var right: int = int(STATE_ORDER.get(String(b["state"]), 9))
	if left != right:
		return left < right
	if bool(a["staffed"]) != bool(b["staffed"]):
		return not bool(a["staffed"])
	if int(a["level"]) != int(b["level"]):
		return int(a["level"]) < int(b["level"])
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	return int(a["id"]) < int(b["id"])
