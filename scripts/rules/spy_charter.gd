class_name SpyCharter
extends RefCounted
## The charted grace a departed Spy leaves behind (wiki: fog-and-exploration
## § Spy timer expiry; Configurable Values — five turns, fixed in current
## product). A province a Spy stands in is held and its clock reset; a province
## whose Spy has left keeps its charted tiles while the clock runs down, then
## fogs. Own ground never takes a clock, so a crown's own provinces can never be
## fogged by this rule.
##
## Plain state, node-free: the fog pass books it once a turn and the save codec
## carries it beside the tile grid (REQ-P2-03, REQ-P3-03).

## Turns a province stays charted after its Spy leaves.
const TURNS: int = 5

## Province id -> turns of charter left.
var _left: Dictionary = {}


## Books this turn's Spy presence. `present` lists the provinces a Spy of this
## crown stands in; `own` lists the crown's own provinces, which never take a
## clock. Returns the provinces the crown still holds through the grace,
## ascending.
func book(present: Array, own: Array = []) -> Array:
	var standing: Array = []
	for raw: Variant in present:
		var province: int = int(raw)
		if province < 0 or own.has(province):
			_left.erase(province)
			continue
		if standing.has(province):
			continue
		standing.append(province)
		_left[province] = TURNS
	var held: Array = []
	held.append_array(standing)
	for raw: Variant in _left.keys():
		var province: int = int(raw)
		if standing.has(province):
			continue
		var left: int = int(_left[province])
		if left <= 0:
			_left.erase(province)
			continue
		held.append(province)
		_left[province] = left - 1
	held.sort()
	return held


## Turns of charter a province has left, 0 when none.
func left(province_id: int) -> int:
	return maxi(int(_left.get(province_id, 0)), 0)


## Plain data for the save: only live clocks are written.
func to_dict() -> Dictionary:
	return _left.duplicate()


## Rehydrates the clocks; a save without them (or with junk) starts empty.
func apply_dict(raw: Variant) -> void:
	_left = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for raw_province: Variant in (raw as Dictionary).keys():
		var left_turns: int = int((raw as Dictionary)[raw_province])
		if left_turns > 0:
			_left[int(raw_province)] = left_turns
