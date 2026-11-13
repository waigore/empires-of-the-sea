class_name NavalIntel
extends RefCounted
## What the crown may read about a rival squadron (wiki: ships-and-naval
## § Sighted strength; DR-20261113-20).
## A rival the crown has just sighted shows `*` and no hull badge: her weight is
## not the crown's to know until the squadron has stayed under the same eye
## across a turn boundary. Leaving the crown's chart starts the watch over.
## The watch is kept **per chart**: fleet ids are minted per roster, so id 5 can
## stand for one squadron on the Old World and another in the New World, and a
## read earned on one map must never hand over the other's weight.
## Plain state, node-free, so the view, the dossier and the save codec read one
## record (REQ-P2-03, REQ-P3-03).

## turn the crown first sighted a squadron in the current watch; a sighting
## older than the current turn is a read squadron.
const KEY_SEEN: String = "seen"
const KEY_REVEALED: String = "revealed"
const KEY_REGIONS: String = "regions"

## region id -> {seen: {fleet id: turn sighted}, revealed: {fleet id: true}}
var _watches: Dictionary = {}


## One refresh of the crown's watch over the water of `region` it can see.
##
## `in_view` holds the ids of rival squadrons drawn under the crown's fog this
## refresh and `turn` the turn being played. A squadron first sighted last turn
## and still in view is revealed now; one sighted this turn waits for the next.
## Squadrons no longer in view on this chart lose both the read and the clock.
## Another chart's watch is untouched: looking at the New World is not a rival
## leaving the Old World's water.
## Returns the ids revealed by this refresh, so a caller can report the news
## (never re-reports).
func observe(in_view: Array, turn: int, region: int) -> Array[int]:
	var seen: Dictionary = _seen_of(region)
	var read: Dictionary = _revealed_of(region)
	var visible: Dictionary = {}
	for raw: Variant in in_view:
		visible[int(raw)] = true
	var revealed: Array[int] = []
	for raw: Variant in visible.keys():
		var fleet_id: int = int(raw)
		if read.has(fleet_id):
			continue
		if seen.has(fleet_id) and int(seen[fleet_id]) < turn:
			read[fleet_id] = true
			revealed.append(fleet_id)
			continue
		if not seen.has(fleet_id):
			seen[fleet_id] = turn
	# A squadron that slipped out of the crown's sight is unread again: on her
	# return she must be watched across a fresh turn boundary.
	for raw: Variant in seen.keys():
		if not visible.has(int(raw)):
			seen.erase(raw)
	for raw: Variant in read.keys():
		if not visible.has(int(raw)):
			read.erase(raw)
	revealed.sort()
	return revealed


## Whether the crown has read this squadron's weight on `region`'s chart.
func is_revealed(fleet_id: int, region: int) -> bool:
	if not _watches.has(region):
		return false
	return (_revealed_of(region)).has(fleet_id)


## Squadrons under the crown's eye on `region`'s chart, read or not.
func watched(region: int) -> Array[int]:
	var ids: Array[int] = []
	for raw: Variant in _seen_of(region).keys():
		ids.append(int(raw))
	for raw: Variant in _revealed_of(region).keys():
		if not ids.has(int(raw)):
			ids.append(int(raw))
	ids.sort()
	return ids


## Plain data for the save (wiki: campaign-persistence § Snapshot contract).
## One entry per chart the crown has watched; an empty watch saves nothing.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in _watches.keys():
		var region: int = int(raw)
		var seen: Dictionary = _seen_of(region)
		if seen.is_empty() and _revealed_of(region).is_empty():
			continue
		out[region] = {
			KEY_SEEN: seen.duplicate(),
			KEY_REVEALED: _revealed_of(region).keys(),
		}
	return {KEY_REGIONS: out}


## Rehydrates the saved watches. `legacy_region` is the chart the save was made
## on: a save written before the watch was kept per chart carries its one watch
## at the top level, and that watch belonged to the region the court was
## standing in. Entries the save cannot express are dropped, never invented.
static func from_dict(raw: Variant, legacy_region: int = -1) -> NavalIntel:
	var intel := NavalIntel.new()
	if typeof(raw) != TYPE_DICTIONARY:
		return intel
	var data: Dictionary = raw
	if data.has(KEY_REGIONS):
		var regions: Variant = data[KEY_REGIONS]
		if typeof(regions) == TYPE_DICTIONARY:
			for raw_region: Variant in (regions as Dictionary).keys():
				_read_watch(intel, int(raw_region), (regions as Dictionary)[raw_region])
		return intel
	if legacy_region >= 0 and (data.has(KEY_SEEN) or data.has(KEY_REVEALED)):
		_read_watch(intel, legacy_region, data)
	return intel


## Fills one chart's watch from a saved entry, keeping only what the format can
## express: a sighting needs a live id and a turn, a read needs a live id.
static func _read_watch(intel: NavalIntel, region: int, raw: Variant) -> void:
	if region < 0 or typeof(raw) != TYPE_DICTIONARY:
		return
	var data: Dictionary = raw
	var seen: Variant = data.get(KEY_SEEN, {})
	if typeof(seen) == TYPE_DICTIONARY:
		for entry: Variant in (seen as Dictionary).keys():
			var fleet_id: int = int(entry)
			var turn: int = int((seen as Dictionary)[entry])
			if fleet_id >= 0 and turn > 0:
				intel._seen_of(region)[fleet_id] = turn
	var revealed: Variant = data.get(KEY_REVEALED, [])
	if typeof(revealed) == TYPE_ARRAY:
		for entry: Variant in revealed as Array:
			var fleet_id: int = int(entry)
			if fleet_id >= 0:
				intel._revealed_of(region)[fleet_id] = true


## One chart's record, created on first use so a caller never has to seed it.
func _seen_of(region: int) -> Dictionary:
	return _record(region)[KEY_SEEN] as Dictionary


func _revealed_of(region: int) -> Dictionary:
	return _record(region)[KEY_REVEALED] as Dictionary


func _record(region: int) -> Dictionary:
	if not _watches.has(region):
		_watches[region] = {KEY_SEEN: {}, KEY_REVEALED: {}}
	return _watches[region] as Dictionary
