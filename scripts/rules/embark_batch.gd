class_name EmbarkBatch
extends RefCounted
## What the passengers block's one press takes aboard, in one hand: how many of
## the idle crews the block prints the hulls can hold now, and the reason the next
## one waits (wiki: civilian-units § Boarding; DR-20261119-18).
##
## The block printed one press per idle crew, so a crown that wanted a squadron
## manned signed it four or five times, and the last press of a full berth
## answered in the rules' words only after it had spent the taps. The walk is
## [RaiseBatchSum]'s — the one every yard's one press reads — with each berth
## standing in for a price: one hull carries one civilian, so the gate reads the
## berths the crews before it leave and stops at the first refusal the rules give
## (REQ-P5-04, REQ-P2-03).
##
## Pure: `plan` writes nothing, `file` lays the boarding down through the
## caller's own callable, and the block and the intent read the same walk, so the
## count a crown confirms is the count the rules accept.

## What the press counts its line in.
const WORD: String = "crews"


## The plan the block's press would file, read before it is pressed: `units` are
## the block's own embark rows, in the order the block prints them. Returns
## [RaiseBatchSum]'s record — `count` (the rows the view prints), `filed` (the
## crews the hulls can take now) and `refusal` (the sentence the next one waits
## on) — so the press's face and the boarding agree (DR-20261118-21).
static func plan(
	model: MapModel, units: Array[CivilianState], fleet: FleetState
) -> Dictionary:
	if fleet == null:
		return RaiseBatchSum.blank()
	var rows: Array[Dictionary] = []
	for unit: CivilianState in units:
		if unit == null:
			continue
		rows.append({"type_id": str(unit.id), "batch_ready": true})
	return _berths(RaiseBatchSum.plan(rows, 0, {}, _free, _nothing, gate(model, units, fleet)))


## The crews a press takes aboard: the same walk `plan` reads, with `board` laid
## down for every step it keeps (the civilian is the argument). A crown that
## presses signs exactly the line it read (REQ-P2-03).
static func file(
	model: MapModel, units: Array[CivilianState], fleet: FleetState, board: Callable
) -> Dictionary:
	var types: Array[String] = []
	for unit: CivilianState in units:
		if unit != null:
			types.append(str(unit.id))
	if fleet == null or types.is_empty():
		return RaiseBatchSum.blank()
	return _berths(
		RaiseBatchSum.file(types, 0, {}, _free, _nothing, gate(model, units, fleet), board)
	)


## The one refusal this press adds to the rules' own: the berths the crews before
## this one leave. Every other answer is [CivilianVoyage.can_embark]'s, in its own
## order and its own words (wiki: civilian-units § Boarding).
static func gate(
	model: MapModel, units: Array[CivilianState], fleet: FleetState
) -> Callable:
	var by_id: Dictionary = {}
	for unit: CivilianState in units:
		if unit != null:
			by_id[str(unit.id)] = unit
	# The berths are read against the crews already aboard the fleet *and* the
	# crews this walk has filed: the read leaves the fleet untouched, so `filed` is
	# what holds its berths, while the press boards as it goes and the count moves
	# with it (DR-20261119-18).
	var aboard: int = fleet.civilian_count()
	return func(type_id: String, _purse: int, _stock: Dictionary, filed: int) -> String:
		var unit: CivilianState = by_id.get(type_id)
		if unit == null:
			return "There is no civilian to embark."
		var refusal: String = String(
			CivilianVoyage.can_embark(model, unit, fleet).get("reason", "")
		)
		if not refusal.is_empty():
			return refusal
		var taken: int = maxi(fleet.civilian_count(), aboard + filed)
		if CivilianVoyage.capacity(fleet) - taken <= 0:
			return CivilianVoyage.capacity_refusal(fleet)
		return ""


## The line under the press: how many of the crews the block prints wait on the
## berths, and the rules' own reason — `""` when the walk carries every one, so a
## covered berth prints nothing (REQ-P5-05).
static func wait_line(reading: Dictionary) -> String:
	var total: int = int(reading.get("count", 0))
	var filed: int = int(reading.get("filed", 0))
	var refusal: String = String(reading.get("refusal", ""))
	if filed <= 0 or refusal.is_empty() or total <= filed:
		return ""
	var waiting: int = total - filed
	return "%d of %d wait%s: %s" % [
		waiting, total, MoneyText.verb_s(waiting), _sentence(refusal)
	]


## The receipt one press prints: the crews the hulls took and, when the walk
## stopped short, the one that waits and why — never silent, and never a count the
## ledger does not carry (REQ-P5-05).
static func receipt(reading: Dictionary, place: String) -> String:
	var filed: int = int(reading.get("filed", 0))
	if filed <= 0:
		var refusal: String = String(reading.get("refusal", ""))
		return refusal if not refusal.is_empty() else "No crew could be taken aboard."
	var total: int = int(reading.get("count", 0))
	if filed == 1:
		return "1 crew is taken aboard at %s%s" % [place, _waits(reading, total, filed)]
	return "%d%s crews are taken aboard at %s%s" % [
		filed,
		"" if total <= filed else " of %d" % total,
		place,
		_waits(reading, total, filed),
	]


## A boarding spends no purse, no material and no peasant: the walk's own spend
## is emptied so no reader of the record prices a berth.
static func _berths(reading: Dictionary) -> Dictionary:
	reading["ducats"] = 0
	reading["materials"] = {}
	reading["workers"] = 0
	return reading


static func _waits(reading: Dictionary, total: int, filed: int) -> String:
	var refusal: String = String(reading.get("refusal", ""))
	if refusal.is_empty() or total <= filed:
		return ""
	return " — the next waits: %s" % _sentence(refusal)


static func _sentence(text: String) -> String:
	return text if text.ends_with(".") else text + "."


static func _free(_type_id: String) -> int:
	return 0


static func _nothing(_type_id: String) -> Dictionary:
	return {}
