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
## turns the aim has been deferred **without its shortfall reaching a new low** —
## a stall. An aim that funds clears its record; one whose gap falls below the
## best the stall has seen restarts it; a per-turn wobble above that best —
## standing still, falling behind, one ducat of noise — counts the turn, so an
## oscillating chest cannot reset the escalation bar forever (the 2026-11-15
## full-AI measurement: a wobbling shortfall kept the re-route from ever
## answering and the court's worker training froze for 175 turns). Past the
## escalation bar the valve has answered, and the record gains its exit: a
## shortfall that falls back above the best — the court spending its margin
## under the re-route — resets the low to the current gap, so the fill's
## recovery counts as progress and the chest re-arms (issue #1484). The ledger
## itself stays a pure reading (REQ-P2-03): the escalation lives in what the
## planners read back — `AiIncome` re-routes a stalled war chest, and the trace
## names an aim stalled past `ledger.blocked_turns` as `blocked` with its
## reason instead of another silent deferred row.
##
## Pure: rows in, records out. No order is issued and no state is mutated
## outside the records the caller keeps (REQ-P4-03).

## Record shape: aim id -> {turns: int, shortfall: Dictionary, low: int}. The
## shortfall is the row this record is stalling on; `turns` is the stall length
## in turns; `low` is the smallest shortfall total the stall has seen.


## Fold one allocated ledger into the next record map. A deferred aim with a
## shortfall continues (or opens) its stall; a funded aim clears; a deferred
## aim without a shortfall (a starved parent naming its child) carries no stall
## of its own — the child's row is the one being tracked; a blocked aim keeps
## the record it had, so an escalation-blocked reading does not restart the
## count it names; an aim that is absent this turn simply leaves no record.
static func note(records: Dictionary, rows: Variant, escalate_turns: int = 0) -> Dictionary:
	var next: Dictionary = {}
	_note_rows(records, next, rows, maxi(escalate_turns, 0))
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


## One court's stall records out of the whole state's deferral table
## (faction -> records): faction keys a JSON round trip turned into strings
## are filed back as ints (issue #603).
static func records_for(deferrals: Dictionary, faction: int) -> Dictionary:
	for raw: Variant in deferrals.keys():
		if int(raw) == faction:
			return _dictionary(deferrals[raw])
	return {}


## The stall length of one aim for one court, read straight off the state's
## deferral table: 0 when the court has none.
static func stall_for(deferrals: Dictionary, faction: int, aim_id: String) -> int:
	return stall(records_for(deferrals, faction), aim_id)


## The best gap one aim's stall has seen for one court — its low water: the
## shortfall the fill has never beaten, so a reading that names the gap this
## turn knows whether the fill is moving. 0 when the court has no record.
static func low_water_for(deferrals: Dictionary, faction: int, aim_id: String) -> int:
	var record: Dictionary = _dictionary(
		records_for(deferrals, faction).get(aim_id, {})
	)
	return maxi(int(record.get("low", -1)), 0)


## A loaded stall map, validated: a record a save could not describe is
## dropped, and the survivor is the plain {turns, shortfall, low} row (issue
## #603). A record written before the low water existed reads the gap it was
## stalling on as its best.
static func clean(records: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for aim_id: Variant in records.keys():
		var record: Dictionary = _dictionary(records[aim_id])
		var shortfall: Dictionary = _dictionary(record.get("shortfall", {}))
		if shortfall.is_empty():
			continue
		var low: int = int(record.get("low", -1))
		if low < 0:
			low = _total(shortfall)
		out[String(aim_id)] = {
			"turns": maxi(int(record.get("turns", 0)), 0),
			"shortfall": shortfall,
			"low": low,
		}
	return out


# --- fold ---------------------------------------------------------------------


static func _note_rows(records: Dictionary, next: Dictionary, rows: Variant, bar: int) -> void:
	if typeof(rows) != TYPE_ARRAY:
		return
	for raw: Variant in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var aim_id: String = String(row.get("id", ""))
		if not aim_id.is_empty():
			_note_aim(records, next, aim_id, row, bar)
		_note_rows(records, next, row.get("children", []), bar)


static func _note_aim(
	records: Dictionary, next: Dictionary, aim_id: String, row: Dictionary, bar: int
) -> void:
	var status: String = String(row.get("status", ""))
	var shortfall: Dictionary = _dictionary(row.get("shortfall", {}))
	var previous: Dictionary = _dictionary(records.get(aim_id, {}))
	if status == AiObjective.STATUS_DEFERRED and not shortfall.is_empty():
		next[aim_id] = {
			"turns": _stall_turns(previous, shortfall),
			"shortfall": shortfall,
			"low": _low_water(previous, shortfall, bar),
		}
	elif status == AiObjective.STATUS_BLOCKED and not previous.is_empty():
		# An escalation-blocked reading keeps the stall it names; a rule-blocked
		# aim never had a record to keep.
		next[aim_id] = previous
	# funded, plain deferred (no shortfall) and absent: the aim moved, so the
	# stall this record was counting is over.


## The next stall length for one aim: 1 when the aim is newly deferred or the
## shortfall just reached a new low; otherwise the count continues — standing
## still, falling behind and a per-turn wobble above the best gap are the same
## stall to the court.
static func _stall_turns(previous: Dictionary, shortfall: Dictionary) -> int:
	if previous.is_empty():
		return 1
	if _total(shortfall) < _held_low(previous, shortfall):
		return 1
	return maxi(int(previous.get("turns", 0)), 0) + 1


## The best gap the stall has seen, carried in the record; a record a save
## wrote before the low water existed reads the gap it was stalling on.
static func _held_low(previous: Dictionary, shortfall: Dictionary) -> int:
	var held: int = int(previous.get("low", -1))
	if held < 0:
		return _total(_dictionary(previous.get("shortfall", {})))
	return held


## The record's low water: the smaller of the gap the stall has seen and this
## turn's shortfall, so the next turn's progress check reads the true best. A
## new stall's best is this turn's own shortfall. Past the escalation bar the
## valve has answered — the court is living on the re-routed reserve and spends
## its margin down — so a shortfall that falls back above the best the stall
## has seen resets the low to the current gap: the spend-down is the episode's
## own floor, and recovery from the dip counts as progress again (issue
## #1484). Without the reset the low is a monotone historic best a spend-down
## can never beat, and a chest that once stood high never re-arms. The stall
## count itself keeps running, so a court that stands still under the re-route
## stays re-routed; only a genuine recovery restarts it.
static func _low_water(previous: Dictionary, shortfall: Dictionary, bar: int) -> int:
	if previous.is_empty():
		return _total(shortfall)
	var held: int = _held_low(previous, shortfall)
	var total: int = _total(shortfall)
	if bar > 0 and int(previous.get("turns", 0)) >= bar and total > held:
		return total
	return mini(held, total)


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
