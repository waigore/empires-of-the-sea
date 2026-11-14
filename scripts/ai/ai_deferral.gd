class_name AiDeferral
extends RefCounted
## The deferred-aim escalation tracker (docs/ai.md; issue #603).
##
## One systemic defect produces most of the open AI board: a reserve the court
## cannot reach (the war chest at war, a study the purse cannot fund) turns
## every spend floor that reads it into a standstill, and the aim that justifies
## the reserve stays `deferred` for the rest of the campaign while the trace
## shows nothing moving. Point-patches moved the deadlock from planner to
## planner (#490 → #578 → #594 → #598); this tracker is the one change that
## ends the family.
##
## `note` reads one allocated ledger (the rows `AiObjectiveLedger.allocate`
## produced, children included) and keeps, per aim id, how many consecutive
## turns the aim has been deferred **without its shortfall shrinking** — a
## stall. An aim that funds clears its record; one that starts closing the gap
## restarts it; one that stands still or falls further behind counts the turn.
## The ledger itself stays a pure reading (REQ-P2-03): the escalation lives in
## what the planners read back — `AiIncome` re-routes a stalled war chest, and
## the trace names an aim stalled past `ledger.blocked_turns` as `blocked`
## with its reason instead of another silent deferred row.
##
## Pure: rows in, records out. No order is issued and no state is mutated
## outside the records the caller keeps (REQ-P4-03).

## Record shape: aim id -> {turns: int, shortfall: Dictionary}. The shortfall is
## the row this record is stalling on; `turns` is the stall length in turns.


## Fold one allocated ledger into the next record map. A deferred aim with a
## shortfall continues (or opens) its stall; a funded aim clears; a deferred
## aim without a shortfall (a starved parent naming its child) carries no stall
## of its own — the child's row is the one being tracked; a blocked aim keeps
## the record it had, so an escalation-blocked reading does not restart the
## count it names; an aim that is absent this turn simply leaves no record.
static func note(records: Dictionary, rows: Variant) -> Dictionary:
	var next: Dictionary = {}
	_note_rows(records, next, rows)
	return next


## The stall length of one aim, 0 when it has no record.
static func stall(records: Dictionary, aim_id: String) -> int:
	var record: Dictionary = _dictionary(records.get(aim_id, {}))
	return maxi(int(record.get("turns", 0)), 0)


## Every aim stalled at least `threshold` turns, as id -> stall length — the
## escalation map the readings hand the planners and the trace.
static func escalated(records: Dictionary, threshold: int) -> Dictionary:
	var out: Dictionary = {}
	for aim_id: Variant in records.keys():
		var turns: int = stall(records, String(aim_id))
		if turns >= maxi(threshold, 1):
			out[String(aim_id)] = turns
	return out


## One snapshot per court's stall records, keyed by faction id. Rows are plain
## {id -> {turns, shortfall}} and JSON-safe as they stand (issue #603).
static func snapshots(by_faction: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in by_faction.keys():
		var records: Dictionary = _dictionary(by_faction[raw])
		var rows: Dictionary = {}
		for aim_id: Variant in records.keys():
			var record: Dictionary = _dictionary(records[aim_id])
			if record.is_empty():
				continue
			rows[String(aim_id)] = {
				"turns": maxi(int(record.get("turns", 0)), 0),
				"shortfall": _dictionary(record.get("shortfall", {})).duplicate(),
			}
		result[int(raw)] = rows
	return result


## Rebuild the per-court stall map from a save row (issue #603).
static func from_stored(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	var stored: Dictionary = _dictionary(raw)
	for faction: Variant in stored.keys():
		var records: Dictionary = _dictionary(stored[faction])
		var rows: Dictionary = {}
		for aim_id: Variant in records.keys():
			var record: Dictionary = _dictionary(records[aim_id])
			if record.is_empty():
				continue
			var shortfall: Dictionary = _dictionary(record.get("shortfall", {}))
			if shortfall.is_empty():
				continue
			rows[String(aim_id)] = {
				"turns": maxi(int(record.get("turns", 0)), 0),
				"shortfall": shortfall,
			}
		if not rows.is_empty():
			result[int(faction)] = rows
	return result


# --- fold ---------------------------------------------------------------------


static func _note_rows(records: Dictionary, next: Dictionary, rows: Variant) -> void:
	if typeof(rows) != TYPE_ARRAY:
		return
	for raw: Variant in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var aim_id: String = String(row.get("id", ""))
		if not aim_id.is_empty():
			_note_aim(records, next, aim_id, row)
		_note_rows(records, next, row.get("children", []))


static func _note_aim(
	records: Dictionary, next: Dictionary, aim_id: String, row: Dictionary
) -> void:
	var status: String = String(row.get("status", ""))
	var shortfall: Dictionary = _dictionary(row.get("shortfall", {}))
	var previous: Dictionary = _dictionary(records.get(aim_id, {}))
	if status == AiObjective.STATUS_DEFERRED and not shortfall.is_empty():
		next[aim_id] = {
			"turns": _stall_turns(previous, shortfall),
			"shortfall": shortfall,
		}
	elif status == AiObjective.STATUS_BLOCKED and not previous.is_empty():
		# An escalation-blocked reading keeps the stall it names; a rule-blocked
		# aim never had a record to keep.
		next[aim_id] = previous
	# funded, plain deferred (no shortfall) and absent: the aim moved, so the
	# stall this record was counting is over.


## The next stall length for one aim: 1 when the shortfall just started
## shrinking (or the aim is newly deferred); otherwise the count continues —
## standing still and falling further behind are the same stall to the court.
static func _stall_turns(previous: Dictionary, shortfall: Dictionary) -> int:
	if previous.is_empty():
		return 1
	if _total(shortfall) < _total(_dictionary(previous.get("shortfall", {}))):
		return 1
	return maxi(int(previous.get("turns", 0)), 0) + 1


## Total shortfall across the row's resources, so a stall that changes shape
## (one ducat short becoming one regiment short) still reads as standing still.
static func _total(shortfall: Dictionary) -> int:
	var total: int = 0
	for raw: Variant in shortfall.keys():
		total += maxi(int(shortfall[raw]), 0)
	return total


static func _dictionary(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}
