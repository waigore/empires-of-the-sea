class_name MapPlayProvinceCounsel
extends RefCounted
## The orders the court's own staff would give on one province's ground, named
## on the province dossier before the crown presses a row (wiki: world-model
## § The crown's provinces; DR-20261121-19).
##
## The reading is not a second opinion: it merges the clause of
## `MapPlayPeoplePick` — the work the civilian pass would put its crews to, the
## call THE CROWN'S PEOPLE prints — with the clause of `MapPlayArmyOrdersPick` —
## the orders the land pass would give its hosts, the call THE CROWN'S ARMY
## prints — narrowed to the work and the marches that land on this province, so
## the dossier cannot name a raise or a march either sheet would refuse
## (REQ-P2-03, REQ-P3-03).
##
## A reading only: nothing here sets an order, marches a host or spends a
## material, and the crown still presses her own rows (REQ-P5-06).

## The court would give this province's ground an order.
const KIND_ORDERS: String = "orders"
## The crown's own province holds an idle crew and the pass books nothing here.
const KIND_NO_WORK: String = "no_work"

## The gate a silent pass earns on the crown's own ground: a crew stood here
## idle and the court booked it no work here this turn.
const NO_WORK_LINE: String = "the court would set no crew to work here this turn"


## The sheet's sentence: the pick's own line, capitalised and closed — the one
## wording every pick surface prints (MapPlayPickProse; REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, model: MapModel, province_id: int) -> String:
	return MapPlayPickProse.sentence_of(pick(play, model, province_id))


## The dossier's pick as the sheet prints it: `{kind, crews, armies, line}`,
## where each crew is `{role, short}` and each host is `{line}`. Empty when the
## session runs no planner for the crown, an observer session, a decided
## campaign, a crown with no ledger, a session with no civilian layer, a
## province the dossier is not showing, or ground neither pass would work.
static func pick(play: PlaySession, model: MapModel, province_id: int) -> Dictionary:
	if not MapPlayPickProse.crown_crew_ready(play):
		return {}
	if model == null or province_id < 0:
		return {}
	return of(
		_crews(play, model, province_id),
		_armies(play, model, province_id),
		_idle_here(play, model, province_id)
	)


## The pick, worded off the crews and hosts that land here: the work the pass
## would give, then the hosts it would send, under one court and one verb, or the
## gate that leaves the crown's own ground with nothing to name. Pure — a sheet
## and its suite drive it without a session.
static func of(
	crews: Array[Dictionary], armies: Array[Dictionary], idle_here: int = 0
) -> Dictionary:
	var clauses: Array[String] = []
	for crew: Dictionary in crews:
		var role: String = String(crew.get("role", ""))
		var short: String = String(crew.get("short", ""))
		if role.is_empty() or short.is_empty():
			continue
		clauses.append("its %s to %s" % [role, short])
	for army: Dictionary in armies:
		var said: String = String(army.get("line", ""))
		if not said.is_empty():
			clauses.append(said)
	var line: String = MapPlayPickProse.court_line("the court would order", clauses)
	if not line.is_empty():
		return {"kind": KIND_ORDERS, "crews": crews, "armies": armies, "line": line}
	# Nothing lands here: the crown's own ground says whether an idle crew stood
	# for work, so an empty province reads nothing rather than a gate.
	if idle_here <= 0:
		return {}
	return {"kind": KIND_NO_WORK, "crews": [], "armies": [], "line": NO_WORK_LINE}


## The crews the pass would put to work on this province's ground, in the
## pass's own order: the craft and the work, its own province stripped because
## the sheet is the place.
static func _crews(
	play: PlaySession, model: MapModel, province_id: int
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var pick: Dictionary = MapPlayPeoplePick.pick(play)
	for raw: Variant in pick.get("crews", []):
		var crew: Dictionary = raw
		if not _lands_here(play, model, crew, province_id):
			continue
		var role: String = String(crew.get("role", ""))
		var short: String = String(crew.get("short", ""))
		if role.is_empty() or short.is_empty():
			continue
		found.append({"role": role, "short": short})
	return found


## The hosts the land pass would send onto this province, in the pass's own
## order: the standard and the order, the sheet's own words.
static func _armies(
	play: PlaySession, model: MapModel, province_id: int
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var pick: Dictionary = MapPlayArmyOrdersPick.pick(play)
	for raw: Variant in pick.get("armies", []):
		var army: Dictionary = raw
		if int(army.get("region", -1)) != model.region_id:
			continue
		if int(army.get("province", MapModel.NO_ID)) != province_id:
			continue
		var said: String = String(army.get("line", ""))
		if said.is_empty():
			continue
		found.append({"line": said})
	return found


## Whether a crew's order lands on this province: its own chart first, because
## unit ids and province ids are minted per roster (REQ-P2-03).
static func _lands_here(
	play: PlaySession, model: MapModel, crew: Dictionary, province_id: int
) -> bool:
	if int(crew.get("region", -1)) != model.region_id:
		return false
	var tile: Variant = crew.get("tile", null)
	if not (tile is Vector2i) or (tile as Vector2i).x < 0:
		return false
	return model.province_at((tile as Vector2i).x, (tile as Vector2i).y) == province_id


## The crown's idle crews standing on this province's own ground: the count the
## gate reads, so an empty sheet names why it is empty.
static func _idle_here(play: PlaySession, model: MapModel, province_id: int) -> int:
	var faction: int = play.player_faction
	if model.province_owner(province_id) != faction:
		return 0
	var stored: Array[CivilianState] = []
	stored.assign(play.civilian_layer.regions.value(model.region_id, []))
	var idle: int = 0
	for unit: CivilianState in stored:
		if unit == null or unit.owner != faction or unit.is_working():
			continue
		if model.province_at(unit.tile.x, unit.tile.y) == province_id:
			idle += 1
	return idle