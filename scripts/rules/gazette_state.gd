class_name GazetteState
extends RefCounted
## The Gazette's memory: the watchlist the player edits and every turn's printed
## sheet (wiki: the-gazette § Courts of interest, § History screen;
## DR-20261110-14). Pure data with no nodes, so the rules, the save and the
## tests share one shape (REQ-P3-03).
##
## A removal sticks: once the player strikes a court off the list, forming a new
## bond with it never puts it back. The archive is unbounded within a campaign
## and takes an entry even for a turn that printed nothing, so the history has
## no gaps.

## Courts followed on the interest page, ascending.
var watched: Array[int] = []
## Faction -> true for every court the player struck off the watchlist.
var removed: Dictionary = {}
## One sheet per resolved turn, ascending: {turn, items: Array[Dictionary]}.
var sheets: Array[Dictionary] = []
## Turn whose plate already auto-opened; a reload must not raise it twice.
var opened_turn: int = 0


func is_watched(faction: int) -> bool:
	return watched.has(faction)


## Adds or removes one court. A removal is remembered for the whole campaign.
func set_watched(faction: int, on: bool) -> void:
	if faction < 0:
		return
	if on:
		removed.erase(faction)
		if not watched.has(faction):
			watched.append(faction)
			watched.sort()
		return
	while watched.has(faction):
		watched.erase(faction)
	removed[faction] = true


## Puts every newly bonded court on the list, except the ones the player already
## struck off. Returns the courts it added, so a caller can name them.
static func seed(gazette: GazetteState, state: DiplomacyState, viewer: int) -> Array[int]:
	var added: Array[int] = []
	if gazette == null or state == null:
		return added
	for faction: int in _every_faction():
		if faction == viewer or gazette.is_watched(faction):
			continue
		if gazette.removed.has(faction):
			continue
		if not bonded(state, viewer, faction):
			continue
		gazette.set_watched(faction, true)
		added.append(faction)
	return added


## Embassy, non-aggression pact, formal alliance or war — the bonds the initial
## list is drawn from (wiki: the-gazette § Courts of interest).
static func bonded(state: DiplomacyState, viewer: int, faction: int) -> bool:
	if state == null or faction == viewer:
		return false
	var record: DiplomacyRelation = state.relation(viewer, faction)
	if record != null and (record.at_war or record.formal_alliance):
		return true
	for stage: String in [
		DiplomacyCatalog.STAGE_EMBASSY,
		DiplomacyCatalog.STAGE_NAP,
		DiplomacyCatalog.STAGE_JOIN_EMPIRE,
	]:
		if state.overture(viewer, faction) == stage:
			return true
		if state.overture(faction, viewer) == stage:
			return true
	return false


## Files one turn's sheet. A turn is written once; a repeated call replaces the
## entry so a replayed close cannot double the page.
func append(sheet: Dictionary) -> void:
	var turn: int = int(sheet.get("turn", 0))
	if turn <= 0:
		return
	for index in sheets.size():
		if int(sheets[index].get("turn", 0)) == turn:
			sheets[index] = sheet
			return
	sheets.append(sheet)
	sheets.sort_custom(_older_first)


func has_sheet(turn: int) -> bool:
	return not sheet_for(turn).is_empty()


func sheet_for(turn: int) -> Dictionary:
	for sheet: Dictionary in sheets:
		if int(sheet.get("turn", 0)) == turn:
			return sheet
	return {}


## Newest first, the order the history screen reads (wiki: the-gazette
## § History screen).
func history() -> Array[Dictionary]:
	var newest: Array[Dictionary] = []
	newest.assign(sheets)
	newest.sort_custom(_newer_first)
	return newest


func newest() -> Dictionary:
	var sheets: Array[Dictionary] = history()
	return sheets[0] if not sheets.is_empty() else {}


func newest_turn() -> int:
	return int(sheets[sheets.size() - 1].get("turn", 0)) if not sheets.is_empty() else 0


func to_dict() -> Dictionary:
	return {
		"watched": watched.duplicate(),
		"removed": removed.keys(),
		"sheets": sheets.duplicate(true),
		"opened_turn": opened_turn,
	}


static func from_dict(raw: Variant) -> GazetteState:
	var state := GazetteState.new()
	if typeof(raw) != TYPE_DICTIONARY:
		return state
	var data: Dictionary = raw
	for faction: Variant in data.get("watched", []):
		var id: int = int(faction)
		if id >= 0 and not state.watched.has(id):
			state.watched.append(id)
	state.watched.sort()
	for faction: Variant in data.get("removed", []):
		state.removed[int(faction)] = true
	for entry: Variant in data.get("sheets", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sheet: Dictionary = entry
		if int(sheet.get("turn", 0)) > 0:
			state.append(sheet.duplicate(true))
	state.opened_turn = int(data.get("opened_turn", 0))
	return state


static func _every_faction() -> Array[int]:
	var ids: Array[int] = []
	ids.append_array(FactionCatalog.great_power_ids())
	ids.append_array(FactionCatalog.minor_ids())
	ids.append_array(FactionCatalog.tribe_ids())
	ids.sort()
	return ids


static func _older_first(left: Dictionary, right: Dictionary) -> bool:
	return int(left["turn"]) < int(right["turn"])


static func _newer_first(left: Dictionary, right: Dictionary) -> bool:
	return int(left["turn"]) > int(right["turn"])
