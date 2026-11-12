class_name RegimentDecorations
extends RefCounted
## The despatch marks a regiment's record keeps beside the tally and the
## colours: the fields it stood in, newest first, and the citations its conduct
## earned there (wiki: naming § Regiment records; DR-20261112-10).
##
## A citation marks a field the colours **held while mauled**: a won engagement
## the regiment ended under its full strength. Both halves are already in the
## aftermath hook, so nothing new is read and no rule outcome moves — strength,
## casualties, chevrons, rest, upkeep and every AI decision are untouched
## (REQ-P2-03). Pure data, no nodes (REQ-P3-03).

## Fields one record keeps; the tally still counts every engagement, so the
## dossier can say how many earlier fields it no longer names.
const KEPT: int = 8
## Fields the dossier line names before it counts the rest.
const SHOWN: int = 2
## Citations that make a regiment laurelled rather than merely cited.
const LAUREL_AT: int = 3


## An empty record: no citation yet and no field stood in.
static func blank() -> Dictionary:
	return {"cited": 0, "fields": []}


## One despatch entry for every surviving regiment of `side`: the field, whether
## the side won it, and whether the colours were cited there. Returns how many
## colours this engagement cited, so the plate can say what the field added.
static func note(side: Array[ArmyState], province: int, won: bool) -> int:
	var cited: int = 0
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			var held: bool = won and float(
				army.condition_of(regiment_id)["fraction"]
			) < 1.0
			var store: Dictionary = _store(army, regiment_id)
			var fields: Array = store["fields"]
			fields.push_front({"p": province, "w": won, "c": held})
			while fields.size() > KEPT:
				fields.pop_back()
			store["fields"] = fields
			if held:
				store["cited"] = int(store["cited"]) + 1
				cited += 1
			army.regiment_history[regiment_id] = store
	return cited


## The fields one regiment stood in, newest first.
static func history(army: ArmyState, regiment_id: String) -> Array:
	if army == null:
		return []
	var fields: Variant = _store(army, regiment_id)["fields"]
	return (fields as Array).duplicate() if fields is Array else []


## Every field where the colours were cited, over the whole record — the kept
## history rolls, the count does not.
static func citations(army: ArmyState, regiment_id: String) -> int:
	if army == null:
		return 0
	return int(_store(army, regiment_id)["cited"])


## The colours' stand: `laurelled` from three citations, `cited` from one, and
## empty for a regiment the crown has never named.
static func rank(army: ArmyState, regiment_id: String) -> String:
	var cited: int = citations(army, regiment_id)
	if cited <= 0:
		return ""
	return "laurelled" if cited >= LAUREL_AT else "cited"


## `Cited — Lisboa won · Évora lost · +3 earlier`, the decoration the colours
## earned leading. Empty for a regiment that has never marched under fire, so a
## green roster gains no line (DR-20261112-10).
static func line(army: ArmyState, regiment_id: String, model: MapModel = null) -> String:
	var fields: Array = history(army, regiment_id)
	if fields.is_empty():
		return ""
	var shown: int = mini(fields.size(), SHOWN)
	var parts: PackedStringArray = PackedStringArray()
	for index in shown:
		var entry: Dictionary = fields[index]
		var title: String = ""
		if model != null:
			title = model.province_name(int(entry.get("p", MapModel.NO_ID)))
		parts.append("%s %s" % [
			title if not title.is_empty() else "a field",
			"won" if bool(entry.get("w", false)) else "lost",
		])
	var text: String = "%s — %s" % [_lead(army, regiment_id), " · ".join(parts)]
	var fought: int = int(army.regiment_engagements.get(regiment_id, 0))
	if fought > shown:
		text += " · +%d earlier" % (fought - shown)
	return text


## The decoration word that opens the line: the ladder the citations climbed,
## else the plain word for a record with no citation yet.
static func _lead(army: ArmyState, regiment_id: String) -> String:
	var earned: String = rank(army, regiment_id)
	if earned.is_empty():
		return "History"
	return earned.capitalize()


## A record's stored shape, zeroed for an instance that has none yet — a recruit,
## a scenario muster, or a save written before records existed.
static func _store(army: ArmyState, regiment_id: String) -> Dictionary:
	var raw: Variant = army.regiment_history.get(regiment_id, {})
	if not raw is Dictionary:
		return blank()
	var store: Dictionary = raw as Dictionary
	var fields: Variant = store.get("fields", [])
	return {
		"cited": int(store.get("cited", 0)),
		"fields": (fields as Array).duplicate() if fields is Array else [],
	}


## A save's despatch maps, keys as strings and values as plain dictionaries, so
## a round-trip through JSON restores what the colours stood in.
static func history_from(raw: Variant) -> Dictionary:
	var mapped: Dictionary = {}
	if not raw is Dictionary:
		return mapped
	for key: Variant in (raw as Dictionary).keys():
		mapped[String(key)] = history_of((raw as Dictionary)[key])
	return mapped


## One stored record, normalised: a save may carry ints as floats, and an older
## entry may carry no citation mark at all.
static func history_of(raw: Variant) -> Dictionary:
	var store: Dictionary = blank()
	if not raw is Dictionary:
		return store
	var fields: Array = []
	var kept: Variant = (raw as Dictionary).get("fields", [])
	if kept is Array:
		for entry: Variant in (kept as Array):
			if not entry is Dictionary:
				continue
			var row: Dictionary = entry as Dictionary
			fields.append({
				"p": int(row.get("p", MapModel.NO_ID)),
				"w": bool(row.get("w", false)),
				"c": bool(row.get("c", false)),
			})
	store["cited"] = int((raw as Dictionary).get("cited", 0))
	store["fields"] = fields
	return store
