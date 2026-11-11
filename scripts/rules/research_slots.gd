class_name ResearchSlots
extends RefCounted
## Slot-assignment persistence (wiki: research-state § Slot Occupancy
## Persistence). Loading is deliberately forgiving and self-contained: invalid
## entries are dropped, an unknown funding preset falls back to `none`, and any
## progress no surviving slot binds is forfeited, so every study in progress
## occupies a slot. Pure data — the economy applies it (REQ-P3-03).


## Slot index -> {tech, funding} from a snapshot's `slots` value. Accepts the
## positional array this project writes and the wiki's object form keyed by slot
## index; a negative index, an empty tech id or a malformed entry is dropped.
static func assignments(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) == TYPE_ARRAY:
		var entries: Array = raw
		for index in entries.size():
			_add(out, index, entries[index])
	elif typeof(raw) == TYPE_DICTIONARY:
		var keyed: Dictionary = raw
		for key: Variant in keyed.keys():
			var index: int = _index_of(key)
			if index >= 0:
				_add(out, index, keyed[key])
	return out


## Replaces `state`'s knowledge, revealed commodities, slots and progress from a
## research snapshot. Entries whose tech is unknown, already known, duplicated,
## or beyond this player's roster are dropped during this catalog-aware pass.
## The ledger goal is client state: a slot this build cannot read (or a save that
## carries none) opens the queue in catalog order (wiki: tech-tree § Goal slot;
## DR-20261111-21).
static func restore(state: ResearchState, data: Dictionary) -> void:
	if state == null:
		return
	state.unlocked = _flags(data.get("unlocked", {}))
	state.revealed = _flags(data.get("revealed", {}))
	state.goal = TechOrder.normalize(String(data.get("goal", "")))
	state.slots = _idle_slots(state.slot_count())
	var saved: Dictionary = _ints(data.get("progress", {}))
	var entries: Dictionary = assignments(data.get("slots", []))
	var bound: Dictionary = {}
	for key: Variant in entries.keys():
		var slot: int = int(key)
		if slot >= state.slots.size():
			continue
		var entry: Dictionary = entries[key]
		var tech_id: String = String(entry["tech"])
		if not TechCatalog.known(tech_id) or state.is_unlocked(tech_id):
			continue
		if bound.has(tech_id):
			continue
		bound[tech_id] = true
		state.slots[slot] = {"tech": tech_id, "funding": String(entry["funding"])}
	state.progress = {}
	for tech_id: String in bound.keys():
		state.progress[tech_id] = int(saved.get(tech_id, 0))


static func _add(out: Dictionary, index: int, raw: Variant) -> void:
	if index < 0 or typeof(raw) != TYPE_DICTIONARY:
		return
	var entry: Dictionary = raw
	var tech_id: String = String(entry.get("tech", ""))
	if tech_id.is_empty():
		return
	var funding: String = String(entry.get("funding", "none"))
	out[index] = {
		"tech": tech_id,
		"funding": funding if ResearchFunding.known(funding) else "none",
	}


static func _index_of(key: Variant) -> int:
	if typeof(key) == TYPE_STRING and not String(key).is_valid_int():
		return -1
	return int(key)


static func _idle_slots(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _index in maxi(count, 0):
		out.append({"tech": ResearchState.EMPTY_TECH, "funding": ResearchFunding.DEFAULT})
	return out


static func _flags(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: Variant in (raw as Dictionary).keys():
		out[String(key)] = bool((raw as Dictionary)[key])
	return out


static func _ints(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: Variant in (raw as Dictionary).keys():
		out[String(key)] = int((raw as Dictionary)[key])
	return out
