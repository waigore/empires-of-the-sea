class_name NavalIntel
extends RefCounted
## What the crown may read about a rival squadron (wiki: ships-and-naval
## § Sighted strength; DR-20261113-20).
## A rival the crown has just sighted shows `*` and no hull badge: her weight is
## not the crown's to know until the squadron has stayed under the same eye
## across a turn boundary. Leaving the crown's chart starts the watch over.
## Plain state, node-free, so the view, the dossier and the save codec read one
## record (REQ-P2-03, REQ-P3-03).

## turn the crown first sighted a squadron in the current watch; a sighting
## older than the current turn is a read squadron.
const KEY_SEEN: String = "seen"
const KEY_REVEALED: String = "revealed"

var _seen: Dictionary = {}
var _revealed: Dictionary = {}


## One refresh of the crown's watch over the water it can see.
##
## `in_view` holds the ids of rival squadrons drawn under the crown's fog this
## refresh and `turn` the turn being played. A squadron first sighted last turn
## and still in view is revealed now; one sighted this turn waits for the next.
## Squadrons no longer in view lose both the read and the clock. Returns the ids
## revealed by this refresh, so a caller can report the news (never re-reports).
func observe(in_view: Array, turn: int) -> Array[int]:
	var visible: Dictionary = {}
	for raw: Variant in in_view:
		visible[int(raw)] = true
	var revealed: Array[int] = []
	for raw: Variant in visible.keys():
		var fleet_id: int = int(raw)
		if _revealed.has(fleet_id):
			continue
		if _seen.has(fleet_id) and int(_seen[fleet_id]) < turn:
			_revealed[fleet_id] = true
			revealed.append(fleet_id)
			continue
		if not _seen.has(fleet_id):
			_seen[fleet_id] = turn
	# A squadron that slipped out of the crown's sight is unread again: on her
	# return she must be watched across a fresh turn boundary.
	for raw: Variant in _seen.keys():
		if not visible.has(int(raw)):
			_seen.erase(raw)
	for raw: Variant in _revealed.keys():
		if not visible.has(int(raw)):
			_revealed.erase(raw)
	revealed.sort()
	return revealed


## Whether the crown has read this squadron's weight.
func is_revealed(fleet_id: int) -> bool:
	return _revealed.has(fleet_id)


## Squadrons under the crown's eye this watch, read or not.
func watched() -> Array[int]:
	var ids: Array[int] = []
	for raw: Variant in _seen.keys():
		ids.append(int(raw))
	for raw: Variant in _revealed.keys():
		if not ids.has(int(raw)):
			ids.append(int(raw))
	ids.sort()
	return ids


## Plain data for the save (wiki: campaign-persistence § Snapshot contract).
func to_dict() -> Dictionary:
	return {
		KEY_SEEN: _seen.duplicate(),
		KEY_REVEALED: _revealed.keys(),
	}


## Rehydrates a saved watch; a legacy save carries none and starts empty, and
## entries the save cannot express are dropped rather than invented.
static func from_dict(raw: Variant) -> NavalIntel:
	var intel := NavalIntel.new()
	if typeof(raw) != TYPE_DICTIONARY:
		return intel
	var data: Dictionary = raw
	var seen: Variant = data.get(KEY_SEEN, {})
	if typeof(seen) == TYPE_DICTIONARY:
		for entry: Variant in (seen as Dictionary).keys():
			var fleet_id: int = int(entry)
			var turn: int = int((seen as Dictionary)[entry])
			if fleet_id >= 0 and turn > 0:
				intel._seen[fleet_id] = turn
	var revealed: Variant = data.get(KEY_REVEALED, [])
	if typeof(revealed) == TYPE_ARRAY:
		for entry: Variant in revealed as Array:
			var fleet_id: int = int(entry)
			if fleet_id >= 0:
				intel._revealed[fleet_id] = true
	return intel
