class_name MapRegionTable
extends RefCounted
## One value per map region, owned by the layer that hides off-screen state.
##
## Map layers keep their per-region rosters here instead of a bare Dictionary so
## spawning, turn ticks and save/load share one "region -> value" contract. Save
## code walks [method encode]/[method decode] rather than layer privates
## (REQ-P3-02 narrow APIs). Roster values are Arrays; works tables may store a
## single object per region.

var _slots: Dictionary = {}


func has_region(region_id: int) -> bool:
	return _slots.has(region_id)


## Stored value, or `fallback` when the region has never been visited.
func value(region_id: int, fallback: Variant = null) -> Variant:
	return _slots.get(region_id, fallback)


func set_region(region_id: int, entry: Variant) -> void:
	_slots[region_id] = entry


func clear() -> void:
	_slots.clear()


func region_ids() -> Array[int]:
	var ids: Array[int] = []
	for raw: Variant in _slots.keys():
		ids.append(int(raw))
	ids.sort()
	return ids


## Every stored value, for the "tick all regions" loops.
func values() -> Array:
	return _slots.values()


## Serialises the table: Arrays become arrays of `encode_item` results (null
## entries dropped), single values become one encoded entry (REQ-P3-04).
func encode(encode_item: Callable) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in _slots.keys():
		var entry: Variant = _slots[raw]
		if entry == null:
			continue
		if entry is Array:
			var rows: Array = []
			for item: Variant in entry:
				if item != null:
					rows.append(encode_item.call(item))
			out[int(raw)] = rows
			continue
		out[int(raw)] = encode_item.call(entry)
	return out


## Replaces the table from a save dictionary. `decode_item` receives the raw
## entry and returns the restored value; null results are skipped.
func decode(data: Dictionary, decode_item: Callable) -> void:
	clear()
	for raw: Variant in data.keys():
		var decoded: Variant = decode_item.call(data[raw])
		if decoded != null:
			_slots[int(raw)] = decoded
