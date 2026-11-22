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
## Every force the reading names is also keyed, so the roll marks the rows its
## line answers with the counsel's `▸` — the realm's own mark
## ([MapPlayRealmCounsel]) — and a crown finds the forces her staff would send
## among a long muster (DR-20261122-03).
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


## The roll's pick as the sheet prints it: `{forces, keys, line}`, where each
## force is `{region, kind, id, line}`, `kind` is the roll's own (`ForceLedger`)
## and `keys` holds `force_key`'s `"region:kind:id"` for every force named — the
## row key the sheet marks. Empty when the session runs no planner for the crown,
## an observer session, a decided campaign, a session with no army or naval
## layer, or every force already under way.
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
	return {"forces": none, "keys": {}, "line": NO_ORDER_LINE}


## The pick, worded off the forces the passes order and the roll's own snapshot:
## the forces in the order the roll prints its rows, and their keys, or the gate
## that leaves a waiting muster with nothing to name. Pure — a sheet and its
## suite drive it without a session.
static func of(forces: Array[Dictionary], snapshot: Dictionary = {}) -> Dictionary:
	if forces.is_empty():
		return {}
	var ordered: Array[Dictionary] = _in_roll_order(forces, snapshot)
	return {"forces": ordered, "keys": keys_of(ordered), "line": pick_line(ordered)}


## The forces the reading names, by `force_key` — what the roll's rows look
## themselves up by, so a marked row is one the line answers (DR-20261122-03).
## A force whose clause the module cannot word keeps its key: the court would
## still order it, and a row that marched while wearing no mark would lie.
static func keys_of(forces: Array[Dictionary]) -> Dictionary:
	var keys: Dictionary = {}
	for force: Dictionary in forces:
		keys[force_key(force)] = true
	return keys


## The key a roll row and the pass's own entry share: the chart the force stands
## or sails on, its kind and the id its roster minted it — ids are minted per
## chart and per roster, so the chart is part of the key (REQ-P2-03).
static func force_key(entry: Dictionary) -> String:
	return "%d:%s:%d" % [
		int(entry.get("region", -1)),
		String(entry.get("kind", "")),
		int(entry.get("id", -1)),
	]


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
		if order.has(force_key(row)):
			continue
		order[force_key(row)] = index
		index += 1
	if order.is_empty():
		return forces
	var keyed: Array[Dictionary] = forces.duplicate()
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: int = int(order.get(force_key(a), 1 << 30))
		var right: int = int(order.get(force_key(b), 1 << 30))
		if left != right:
			return left < right
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return keyed

