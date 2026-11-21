class_name MapPlayPeoplePick
extends RefCounted
## The work the court's own civilian pass would give its crews this turn, named
## on THE CROWN'S PEOPLE before the crown opens a single dossier (wiki:
## civilian-units § Empire roster; DR-20261121-12).
##
## The reading is not a second opinion: it is `MapPlayCivilianPick.picks` — the
## same pass a crew's own sheet and the chart's mark read — one clause per crew
## the pass books something for, so the roster cannot name a raise, a march or a
## watch the pass would not take (REQ-P2-03, REQ-P3-03).
##
## A reading only: nothing here marches a crew, sets an order or spends a
## material, and the crown still presses her own sheets (REQ-P5-06).

## The actions whose short form names the work but not the ground it stands on,
## so the clause adds the province the pass would put the crew to work on. A
## march, a survey, a deed or a screen already names its own ground.
const PLACE_ACTIONS: Array[String] = [
	"build_improvement",
	"upgrade_town",
	"build_fort",
	"build_hospital",
	"build_road",
	"build_port",
	"build_rail",
]

## The most crews one line names before it counts the rest, so a handset's
## reading stays one line of chrome (REQ-P5-07).
const NAMED_LIMIT: int = 3

## Crews wait and the pass puts none to work: the gate the sheet names instead
## of a clause it cannot print.
const NO_WORK_LINE: String = "the court would set no waiting crew to work this turn"


## The sheet's sentence: the pick's own clause, capitalised and closed — the
## same one wording every pick surface prints (REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, snapshot: Dictionary = {}) -> String:
	return sentence(String(pick(play, snapshot).get("line", "")))


## `text` as a printed sentence: "the court would put …" → "The court would put …".
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The roster's pick as the people sheet prints it: `{crews, line}`, where each
## crew is `{region, unit_id, role, action, tile, place, short}`. Empty when the
## session runs no planner for the crown, an observer session, a decided
## campaign, a crown with no ledger or a session with no civilian layer.
static func pick(play: PlaySession, snapshot: Dictionary = {}) -> Dictionary:
	if play == null or play.world == null or play.campaign_over():
		return {}
	if play.observer_mode or play.civilian_layer == null:
		return {}
	var faction: int = play.player_faction
	if play.ledger_for(faction) == null:
		return {}
	if AiControl.court_kind(play, faction) == AiControl.KIND_NONE:
		return {}
	return of(_crews(play, faction), snapshot)


## The crews the pass books something for, in the pass's own order: the work it
## would give each idle crew, named by its craft and the ground the work takes.
static func _crews(play: PlaySession, faction: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var picks: Dictionary = MapPlayCivilianPick.picks(play, faction)
	if picks.is_empty():
		return found
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var stored: Array[CivilianState] = []
		stored.assign(play.civilian_layer.regions.value(region, []))
		for unit: CivilianState in stored:
			if unit == null or unit.owner != faction or unit.is_working():
				continue
			# Unit ids are minted per roster, so the pick is read on its own
			# chart: a crew of id 5 on the New World is not the Old World's id 5
			# (REQ-P2-03).
			var pick: Dictionary = picks.get(unit.id, {})
			if pick.is_empty() or int(pick.get("region", -1)) != region:
				continue
			var entry: Dictionary = _entry(model, unit, pick)
			if entry.is_empty():
				continue
			entry["region"] = region
			found.append(entry)
	return found


## One crew's own words: the craft the roster prints it under, the order the pass
## would give it and the ground that order lands on.
static func _entry(
	model: MapModel, unit: CivilianState, pick: Dictionary
) -> Dictionary:
	var action: String = String(pick.get("action", ""))
	var short: String = String(pick.get("short", ""))
	if action.is_empty() or short.is_empty():
		return {}
	var tile: Variant = pick.get("tile", CivilianState.NO_TILE)
	var ground: Vector2i = tile if tile is Vector2i else CivilianState.NO_TILE
	return {
		"unit_id": unit.id,
		"role": CivilianCatalog.display_name(unit.type_id),
		"action": action,
		"tile": ground,
		"place": _place(model, ground) if PLACE_ACTIONS.has(action) else "",
		"short": short,
	}


## The province a work order's ground stands in, or the wilds off any province.
static func _place(model: MapModel, tile: Vector2i) -> String:
	if model == null or tile.x < 0:
		return ""
	return MapPlayCivilianPickWords.place(model, model.province_at(tile.x, tile.y))


## The pick, worded off the crew list and the sheet's own snapshot: the crews in
## the order the sheet prints its rows, or the gate that leaves a waiting roster
## with nothing to name. Pure — a sheet and its suite drive it without a session.
static func of(crews: Array[Dictionary], snapshot: Dictionary = {}) -> Dictionary:
	if not crews.is_empty():
		var ordered: Array[Dictionary] = _in_row_order(crews, snapshot)
		return {"crews": ordered, "line": pick_line(ordered)}
	# No crew is put to work: the roster's own idle tally says whether any crew
	# waited for the pass to spend. A snapshot that carries no tally names no
	# gate, because the sheet has not read the roster yet.
	if int(snapshot.get("idle", 0)) <= 0:
		return {}
	return {"crews": [], "line": NO_WORK_LINE}


## The crews in the order the sheet prints its rows (its own `rows`), so the
## line reads down the page it answers. A crew the snapshot does not print keeps
## the pass's order after them.
static func _in_row_order(
	crews: Array[Dictionary], snapshot: Dictionary
) -> Array[Dictionary]:
	var order: Dictionary = {}
	var index: int = 0
	for raw: Variant in snapshot.get("rows", []):
		var row: Dictionary = raw
		if order.has(_key(row)):
			continue
		order[_key(row)] = index
		index += 1
	if order.is_empty():
		return crews
	var keyed: Array[Dictionary] = crews.duplicate()
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: int = int(order.get(_key(a), 1 << 30))
		var right: int = int(order.get(_key(b), 1 << 30))
		if left != right:
			return left < right
		return int(a.get("unit_id", 0)) < int(b.get("unit_id", 0))
	)
	return keyed


## A crew's own row key: the chart it stands on and the id its roster minted it.
static func _key(entry: Dictionary) -> String:
	return "%d:%d" % [int(entry.get("region", -1)), int(entry.get("unit_id", -1))]


## "the court would put its Builder to raise the lumber camp at Cádiz, its
## Explorer to survey the Mar Caribe and its Engineer to build a road at Sevilla
## this turn". Beyond three the line counts the crews it cannot name
## (`… and 2 more`) so a busy roster stays one line of chrome.
static func pick_line(crews: Array[Dictionary]) -> String:
	var named: Array[String] = []
	var hidden: int = 0
	for crew: Dictionary in crews:
		if named.size() >= NAMED_LIMIT:
			hidden += 1
			continue
		named.append(_clause(crew))
	if named.is_empty():
		return ""
	var joined: String = ", ".join(named) if hidden > 0 else _join(named)
	if hidden > 0:
		joined += " and %d more" % hidden
	return "the court would put %s this turn" % joined


## One crew's clause: what the pass would put it to, on the ground the order
## lands on.
static func _clause(crew: Dictionary) -> String:
	var role: String = String(crew.get("role", "crew"))
	var short: String = String(crew.get("short", ""))
	var place: String = String(crew.get("place", ""))
	if place.is_empty():
		return "its %s to %s" % [role, short]
	return "its %s to %s at %s" % [role, short, place]


## A list read the way prose reads it: "A", "A and B", "A, B and C".
static func _join(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() <= 2:
		return " and ".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]
