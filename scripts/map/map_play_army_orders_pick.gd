class_name MapPlayArmyOrdersPick
extends RefCounted
## The orders the court's own staff would give its armies this turn, named on THE
## CROWN'S ARMY before the crown opens a single standard's dossier (wiki:
## military-armies § The crown's army, § Movement and attacks; DR-20261121-14).
##
## The reading is not a second opinion: it is `MapPlayArmyPick.pick` — the call
## one standard's own dossier reads, and the published land policy behind it —
## asked for every army the crown fields in both charts, so the sheet cannot name
## an order the policy would not give (REQ-P2-03).
##
## A reading only: nothing here splits a standard, marches a regiment or rolls a
## die, and the crown still presses her own order (REQ-P3-03, REQ-P5-06).

## The most standards one line names before it counts the rest, so a handset's
## reading stays one line of chrome (REQ-P5-07).
const NAMED_LIMIT: int = 3

## Armies wait for an order and the pass gives none: the gate the sheet names
## instead of a clause it cannot print.
const NO_ORDER_LINE: String = "the court would give no waiting army an order this turn"


## The sheet's sentence: the pick's own line, capitalised and closed — the one
## wording every pick surface prints (MapPlayPickProse; REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, snapshot: Dictionary = {}) -> String:
	return MapPlayPickProse.sentence(String(pick(play, snapshot).get("line", "")))


## The army's pick as the sheet prints it: `{armies, line}`, where each standard
## is `{region, army, kind, line}`. Empty when the session runs no planner for the
## crown, an observer session, a decided campaign, a session with no army layer or
## diplomacy, or an army the pass leaves entirely alone.
static func pick(play: PlaySession, snapshot: Dictionary = {}) -> Dictionary:
	if play == null or play.world == null or play.army_layer == null:
		return {}
	if play.diplomacy == null or play.observer_mode or play.campaign_over():
		return {}
	var faction: int = play.player_faction
	if AiControl.court_kind(play, faction) == AiControl.KIND_NONE:
		return {}
	var armies: Array[Dictionary] = _armies(play, faction)
	if not armies.is_empty():
		return of(armies, snapshot)
	# The pass names no order: the sheet says whether any standard waited for one,
	# so an army already under way reads nothing rather than a gate.
	return gate(_waiting(play, faction))


## The gate a silent pass earns: `waiting` standards stood for an order and the
## policy gave none, so the sheet names that rather than a clause it cannot print.
## An army with nothing waiting has nothing to say (REQ-P5-06).
static func gate(waiting: int) -> Dictionary:
	if waiting <= 0:
		return {}
	var none: Array[Dictionary] = []
	return {"armies": none, "line": NO_ORDER_LINE}


## The pick, worded off the standards the pass orders and the sheet's own
## snapshot: the standards in the order the sheet prints its headings, or the gate
## that leaves a waiting army with nothing to name. Pure — a sheet and its suite
## drive it without a session.
static func of(armies: Array[Dictionary], snapshot: Dictionary = {}) -> Dictionary:
	if armies.is_empty():
		return {}
	var ordered: Array[Dictionary] = _in_heading_order(armies, snapshot)
	return {"armies": ordered, "line": pick_line(ordered)}


## "the court would send the Home Army to take the field with 4 regiments and the
## field army at Tucapel to storm Cádiz this turn". Beyond three the line counts
## the standards it cannot name (`… and 2 more`) so a busy army stays one line of
## chrome.
static func pick_line(armies: Array[Dictionary]) -> String:
	var clauses: Array[String] = []
	for army: Dictionary in armies:
		var clause: String = String(army.get("line", ""))
		if not clause.is_empty():
			clauses.append(clause)
	var joined: String = MapPlayPickProse.capped(clauses, NAMED_LIMIT)
	if joined.is_empty():
		return ""
	return "the court would send %s this turn" % joined


## One standard's clause: the standard the sheet names it by, then the order the
## pass would give it. Empty when the order names nothing this module can say (an
## unknown kind, or a ground with no such province), so the line can never promise
## a march to nowhere.
static func clause(model: MapModel, army: ArmyState, pick: Dictionary) -> String:
	if model == null or army == null or pick.is_empty():
		return ""
	var said: String = MapPlayArmyPickWords.order_clause(model, pick)
	if said.is_empty():
		return ""
	return "%s %s" % [standard(model, army), said]


## The standard a clause names: the seat by its own title, a field army by the
## province it stands in, so two standards never read alike.
static func standard(model: MapModel, army: ArmyState) -> String:
	if army == null:
		return ""
	if army.home:
		return "the Home Army"
	var place: String = ""
	if model != null and army.province >= 0:
		place = model.province_name(army.province)
	if place.is_empty():
		return "the field army"
	return "the field army at %s" % place


## The orders the pass books, in the pass's own order: one clause per standard of
## the crown the policy orders, read on the chart it stands on.
static func _armies(play: PlaySession, faction: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		for army: ArmyState in MapPlayCourt.visible_armies(play, region):
			if army == null or army.owner != faction:
				continue
			var order: Dictionary = MapPlayArmyPick.pick(play, army)
			var said: String = clause(model, army, order)
			if said.is_empty():
				continue
			found.append({
				"region": region,
				"army": army.id,
				"kind": String(order.get("kind", "")),
				"line": said,
			})
	return found


## The standards the pass weighs at all — the crown's own, unmoved and not
## embarked — so the sheet knows whether a silent pass left anyone waiting for an
## order.
static func _waiting(play: PlaySession, faction: int) -> int:
	var waiting: int = 0
	for region: int in play.army_layer.regions.region_ids():
		for army: ArmyState in MapPlayCourt.visible_armies(play, region):
			if army == null or army.owner != faction:
				continue
			if army.moved or army.is_embarked():
				continue
			waiting += 1
	return waiting


## The standards in the order the sheet prints its headings (its own `groups`), so
## the line reads down the page it answers. A standard the snapshot does not print
## keeps the pass's order after them.
static func _in_heading_order(
	armies: Array[Dictionary], snapshot: Dictionary
) -> Array[Dictionary]:
	var order: Dictionary = {}
	var index: int = 0
	for raw: Variant in snapshot.get("groups", []):
		var group: Dictionary = raw
		if order.has(_key(group)):
			continue
		order[_key(group)] = index
		index += 1
	if order.is_empty():
		return armies
	var keyed: Array[Dictionary] = armies.duplicate()
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: int = int(order.get(_key(a), 1 << 30))
		var right: int = int(order.get(_key(b), 1 << 30))
		if left != right:
			return left < right
		return int(a.get("army", 0)) < int(b.get("army", 0))
	)
	return keyed


## A standard's own key: the chart it stands on and the id its roster minted it.
## The sheet calls the id `army` on a heading and the pick calls it `army` on its
## own entry, so one key reads both.
static func _key(entry: Dictionary) -> String:
	return "%d:%d" % [int(entry.get("region", -1)), int(entry.get("army", -1))]
