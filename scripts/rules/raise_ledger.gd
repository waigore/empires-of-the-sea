class_name RaiseLedger
extends RefCounted
## What the crown's raise ledgers share: a town and a wall are the same reading —
## every owned province that can carry the work, the level it stands at, the crew
## already at it, the study the next step waits on and the press that files the
## order. The sheets differ only in their domain: the row each mints, the states
## it prints and the words of its note stay with [TownLedger] and [WallLedger];
## the snapshot walk, the tallies, the chip narrowing and the reading order are
## written once here (REQ-P3-01, REQ-P3-02).
##
## Pure projection over presentation dictionaries and rules records: no nodes, no
## order of its own and no snapshot of its own (REQ-P3-03).

## The states every raise row can carry whatever its domain: a step the crown can
## take now, a crew already taking it and a study that has not opened it. The
## finished and no-crew words are the sheet's own, passed in where needed.
const STATE_READY: String = "ready"
const STATE_AT_WORK: String = "at_work"
const STATE_LOCKED: String = "locked"


## Whole-empire snapshot in reading order. `regions` is one entry per chart:
## {region, model, units, tech_unlocked, stockpile} — the crown's crews there,
## the studies it holds and the stores the next step is paid from. `row` mints
## one province's row and `states` are the tallies the chips read; `admit` says
## whether a province earns a row at all, and a row the sheet mints empty earns
## none, so a province that cannot carry the work is skipped.
static func snapshot(
	regions: Array[Dictionary],
	owner: int,
	row: Callable,
	states: Array,
	order: Dictionary,
	admit: Callable = Callable()
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts: Dictionary = empty_counts(states)
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
			if province == null or province.owner != owner:
				continue
			if admit.is_valid() and not bool(admit.call(province)):
				continue
			var line: Dictionary = row.call(
				model, province, region, units, tech_unlocked, stockpile
			)
			if line.is_empty():
				continue
			rows.append(line)
			var state: String = String(line["state"])
			counts[state] = int(counts.get(state, 0)) + 1
	sort_rows(rows, order)
	return {
		"rows": rows,
		"groups": LedgerRows.group(rows),
		"counts": counts,
		"total": rows.size(),
	}


## Zero per state, so a chip carries its own tally and a zero stays legible.
static func empty_counts(states: Array) -> Dictionary:
	var counts: Dictionary = {}
	for state: String in states:
		counts[state] = 0
	return counts


## Rows narrowed to one chart and one reading, grouped under their chart.
static func groups(
	data: Dictionary, region_key: String, filter_key: String = LedgerRows.ALL
) -> Array[Dictionary]:
	return LedgerRows.groups(data, region_key, matches.bind(filter_key))


static func count(
	data: Dictionary, region_key: String, filter_key: String = LedgerRows.ALL
) -> int:
	return LedgerRows.count(data, region_key, matches.bind(filter_key))


## How many rows each reading would show inside one chart, so a chip carries its
## own tally and a zero stays legible rather than hidden.
static func filter_counts(
	data: Dictionary, region_key: String, filters: Array
) -> Dictionary:
	return LedgerRows.counts(data, region_key, filters, matches)


## A raise reading is the row's own state word.
static func matches(row: Dictionary, filter_key: String) -> bool:
	return LedgerRows.field_matches(row, "state", filter_key)


## What the next step waits on, worst first: a finished work, a crew already at
## it, the study the order needs, a free hand, else the order is open. The
## finished and no-crew words are the sheet's own.
static func state_for(
	level: int,
	max_level: int,
	crew: CivilianState,
	refusal: String,
	crew_free: bool,
	done_state: String,
	no_crew_state: String
) -> String:
	if level >= max_level:
		return done_state
	if crew != null:
		return STATE_AT_WORK
	if not refusal.is_empty():
		return STATE_LOCKED
	if not crew_free:
		return no_crew_state
	return STATE_READY


## The crew already at this work, read from the crew's own record so the row
## names the step the order was priced for.
static func crew_for(
	units: Array[CivilianState], owner: int, tile: Vector2i, action: String
) -> CivilianState:
	for raw: Variant in units:
		var unit := raw as CivilianState
		if unit == null or unit.owner != owner or not unit.is_working():
			continue
		if unit.work_action() == action and unit.work_tile() == tile:
			return unit
	return null


## Reading order: the state's own rank, then the weakest level, then the chart and
## the province, so what can be raised now leads and a crown reads its coast in
## one pass.
static func sort_rows(rows: Array[Dictionary], order: Dictionary) -> void:
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var left: int = int(order.get(String(a["state"]), 9))
			var right: int = int(order.get(String(b["state"]), 9))
			if left != right:
				return left < right
			if int(a["level"]) != int(b["level"]):
				return int(a["level"]) < int(b["level"])
			if int(a["region"]) != int(b["region"]):
				return int(a["region"]) < int(b["region"])
			return int(a["id"]) < int(b["id"])
	)
