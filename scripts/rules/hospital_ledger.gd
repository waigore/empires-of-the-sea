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

## What the ward's next step is waiting on. One state per row, so the reading
## chips and the row's own word can never disagree.
const STATE_READY: String = "ready"
const STATE_AT_WORK: String = "at_work"
const STATE_NO_ENGINEER: String = "no_engineer"
const STATE_LOCKED: String = "locked"
const STATE_RAISED: String = "raised"

const FILTER_ALL: String = "all"
const FILTER_READY: String = "ready"
const FILTER_AT_WORK: String = "at_work"
const FILTER_RAISED: String = "raised"
const FILTERS: Array[String] = [FILTER_ALL, FILTER_READY, FILTER_AT_WORK, FILTER_RAISED]

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
## {region, model, units, tech_unlocked} — the crown's crews there and the
## studies it holds. `stockpile` is the crown's live purse, or `null` when the
## caller prices no spend (the ledger's own fixtures do not). A chart with no
## model is skipped, so a one-region world reads as one heading. A province with
## no town tile and no seat cannot carry a ward (it is raised on the town tile),
## so it earns no row.
static func snapshot(
	regions: Array[Dictionary], owner: int, stockpile: Variant = null
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {
		STATE_READY: 0,
		STATE_AT_WORK: 0,
		STATE_NO_ENGINEER: 0,
		STATE_LOCKED: 0,
		STATE_RAISED: 0,
	}
	for entry: Dictionary in regions:
		var model := entry.get("model") as MapModel
		if model == null:
			continue
		var region: int = int(entry.get("region", model.region_id))
		var units: Array[CivilianState] = []
		units.assign(entry.get("units", []))
		var tech_unlocked: Dictionary = entry.get("tech_unlocked", {})
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != owner:
				continue
			var row: Dictionary = _row(model, province, region, units, tech_unlocked, stockpile)
			if row.is_empty():
				continue
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


## How many wards each reading would show inside one chart, so a chip carries
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
## (wiki: combat § Regiment condition; DR-20261112-04).
static func rule_note() -> String:
	var top: int = HospitalRules.MAX_LEVEL
	return (
		"A ward sets the tempo an army recovers at — rest %d%% at a field ward and "
		+ "%d%% at a general one, and the wear a defeat leaves cut to %d%% and "
		+ "%d%%. Its staff eats %d food a turn per level; a ward the larder cannot "
		+ "cover goes unfed and heals nothing that turn, so the ration is part of "
		+ "the wall."
	) % [
		roundi(HospitalRules.rest_share(1) * 100.0),
		roundi(HospitalRules.rest_share(top) * 100.0),
		roundi(HospitalRules.triage_scale(1) * 100.0),
		roundi(HospitalRules.triage_scale(top) * 100.0),
		HospitalRules.RATION_PER_LEVEL,
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
	var refusal: String = CivilianWorkPlan.hospital_refusal(level, tech_unlocked, stockpile)
	var crew: CivilianState = _crew(units, province.owner, site)
	var state: String = _state(level, crew, refusal, units, province.owner, site)
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
		"note": _note(state, level, next, cost_text, refusal, crew),
	}


## What the next step waits on, worst first: a finished ward, a crew already at
## work, the study or the stores the order needs, a free Engineer, else the
## order is open.
static func _state(
	level: int,
	crew: CivilianState,
	refusal: String,
	units: Array[CivilianState],
	owner: int,
	site: Vector2i
) -> String:
	if level >= HospitalRules.MAX_LEVEL:
		return STATE_RAISED
	if crew != null:
		return STATE_AT_WORK
	if not refusal.is_empty():
		return STATE_LOCKED
	if ImprovementOrders.nearest_engineer(units, owner, site) == null:
		return STATE_NO_ENGINEER
	return STATE_READY


## The Engineer already raising this ward, read from the crew's own record so
## the row names the level the order was priced for.
static func _crew(
	units: Array[CivilianState], owner: int, site: Vector2i
) -> CivilianState:
	for raw: Variant in units:
		var unit := raw as CivilianState
		if unit == null or unit.owner != owner or not unit.is_working():
			continue
		if unit.work_action() == "build_hospital" and unit.work_tile() == site:
			return unit
	return null


static func _note(
	state: String,
	level: int,
	next: int,
	cost_text: String,
	refusal: String,
	crew: CivilianState
) -> String:
	match state:
		STATE_RAISED:
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
