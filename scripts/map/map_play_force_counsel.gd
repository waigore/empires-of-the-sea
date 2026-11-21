class_name MapPlayForceCounsel
extends RefCounted
## The orders the court's own staff would give every force this turn, named on THE
## CROWN'S MUSTER before the crown opens either force sheet (wiki:
## military-armies § The muster roll, § The crown's army; ships-and-naval
## § The crown's navy; DR-20261121-17).
##
## The reading is not a second opinion: it is [MapPlayArmyOrdersPick] and
## [MapPlayNavyPick] — the calls THE CROWN'S ARMY and THE CROWN'S NAVY print, and
## the published policies behind each — merged into the roll's own row order, so
## the roll cannot name an order either sheet would refuse (REQ-P2-03). No second
## planner copies a policy.
##
## A reading only: nothing here marches a standard, takes a station or rolls a
## die, and the crown still presses her own order (REQ-P3-03, REQ-P5-06).

## Forces wait for an order and both passes give none: the gate the roll names
## instead of a clause it cannot print.
const NO_ORDER_LINE: String = "the court would give no waiting force an order this turn"


## The roll's sentence: the pick's own line, capitalised and closed — the one
## wording every pick surface prints (MapPlayPickProse; REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, snapshot: Dictionary = {}) -> String:
	return MapPlayPickProse.sentence(String(pick(play, snapshot).get("line", "")))


## The roll's pick as the sheet prints it: `{forces, line}`, where each force is
## `{region, kind, id, line}` and `kind` is the roll's own (`ForceLedger`). Empty
## when the session runs no planner for the crown, an observer session, a decided
## campaign, a session with no army or naval layer, or every force already under
## way.
static func pick(play: PlaySession, snapshot: Dictionary = {}) -> Dictionary:
	var army: Dictionary = MapPlayArmyOrdersPick.pick(play)
	var navy: Dictionary = MapPlayNavyPick.pick(play)
	var forces: Array[Dictionary] = _merged(army, navy)
	if not forces.is_empty():
		return of(forces, snapshot)
	# Neither sheet names an order: the roll says whether any force waited for
	# one, so a muster already under way reads nothing rather than a gate.
	return gate(_waited(army, navy))


## The gate a silent pair of passes earns: a force stood for an order and the
## policy gave none, so the roll names that rather than a clause it cannot print.
## A muster with nothing waiting has nothing to say (REQ-P5-06).
static func gate(waited: bool) -> Dictionary:
	if not waited:
		return {}
	var none: Array[Dictionary] = []
	return {"forces": none, "line": NO_ORDER_LINE}


## The pick, worded off the forces the passes order and the roll's own snapshot:
## the forces in the order the roll prints its rows, or the gate that leaves a
## waiting muster with nothing to name. Pure — a sheet and its suite drive it
## without a session.
static func of(forces: Array[Dictionary], snapshot: Dictionary = {}) -> Dictionary:
	if forces.is_empty():
		return {}
	var ordered: Array[Dictionary] = _in_roll_order(forces, snapshot)
	return {"forces": ordered, "line": pick_line(ordered)}


## "the court would send the Home Army to take the field with 4 regiments, the
## field army at Tucapel to storm Cádiz and the Leopard into the Mar Caribe this
## turn". Beyond three the line counts the forces it cannot name (`… and 2 more`)
## so a busy muster stays one line of chrome.
static func pick_line(forces: Array[Dictionary]) -> String:
	var clauses: Array[String] = []
	for force: Dictionary in forces:
		var clause: String = String(force.get("line", ""))
		if not clause.is_empty():
			clauses.append(clause)
	return MapPlayPickProse.court_line("the court would send", clauses, "this turn")


## Both sheets' clauses as the roll reads them: the army's standards and the
## navy's squadrons, each named by the force kind and the id its roster minted it,
## so one line holds every force the crown fields.
static func _merged(army: Dictionary, navy: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for raw: Variant in army.get("armies", []):
		var entry: Dictionary = raw
		found.append(_force(entry, "army", ForceLedger.KIND_ARMY))
	for raw: Variant in navy.get("squadrons", []):
		var entry: Dictionary = raw
		found.append(_force(entry, "fleet_id", ForceLedger.KIND_SQUADRON))
	return found


## One sheet's entry read as a roll row: the chart, the force kind, the id and
## the clause the sheet prints for it.
static func _force(entry: Dictionary, id_key: String, kind: String) -> Dictionary:
	return {
		"region": int(entry.get("region", -1)),
		"kind": kind,
		"id": int(entry.get(id_key, -1)),
		"line": String(entry.get("line", "")),
	}


## Whether either sheet's pass left a force waiting for an order it did not give:
## each sheet's own gate worded it, so the roll never re-derives what "waiting"
## means (REQ-P2-03).
static func _waited(army: Dictionary, navy: Dictionary) -> bool:
	return (
		not String(army.get("line", "")).is_empty()
		or not String(navy.get("line", "")).is_empty()
	)


## The forces in the order the roll prints its rows (its own snapshot), so the
## line reads down the page it answers. A force the snapshot does not print keeps
## the passes' order after them.
static func _in_roll_order(
	forces: Array[Dictionary], snapshot: Dictionary
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
		return forces
	var keyed: Array[Dictionary] = forces.duplicate()
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: int = int(order.get(_key(a), 1 << 30))
		var right: int = int(order.get(_key(b), 1 << 30))
		if left != right:
			return left < right
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return keyed


## A force's own key: the chart it stands or sails on, its kind and its id. The
## roll calls the id `id` on a row and the pick calls it the same on its entry.
static func _key(entry: Dictionary) -> String:
	return "%d:%s:%d" % [
		int(entry.get("region", -1)),
		String(entry.get("kind", "")),
		int(entry.get("id", -1)),
	]
