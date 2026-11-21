class_name MapPlayArmyPickWords
extends RefCounted
## How one land pick is worded (wiki: military-armies § Home Army, § Movement and
## attacks; DR-20261120-10): the order the published land policy would give the
## standard, in the rule book's own names — the field the Home Army would take,
## the province a field army would march on and the ground's own reason, the road
## home to merge. A reading, never an order; every figure is one the planner
## actually decided on (REQ-P2-03, REQ-P5-06).

## The Home Army taking the field: what leaves the seat and what stays to hold it.
## Empty when nothing would march, because a split that moves no standard is no
## order the court would give.
static func split_line(going: int, guard: int) -> String:
	if going <= 0:
		return ""
	if guard <= 0:
		return "the court would take the field — %d regiments from the seat" % going
	return "the court would take the field — %d regiments from the seat, %d held to guard it" % [
		going, guard
	]

## A march the pass books, with the reason the ground gives it. Empty when the
## target names no province, so the line can never print a march to nowhere.
static func march_line(model: MapModel, province: int, why: String) -> String:
	if model == null or province < 0:
		return ""
	var name: String = model.province_name(province)
	match why:
		MapPlayArmyPick.WHY_STORM:
			return "the court would march on %s to storm it" % name
		MapPlayArmyPick.WHY_RELIEF:
			return "the court would march on %s to throw out the host there" % name
		MapPlayArmyPick.WHY_FRONTIER:
			return "the court would advance to %s, the frontier" % name
	return ""

## The interior-lines march home: a worn field army folds into the mass the seat
## has mustered, so the next cut re-fields a stronger standard (issue #974).
static func rotate_line(model: MapModel, province: int) -> String:
	if model == null or province < 0:
		return ""
	return "the court would march home to %s to merge with the Home Army" % model.province_name(
		province
	)


## The order one standard would take, as one clause of the army sheet's line: the
## verb phrase the pick's own kind and ground give it, to be read after the
## standard the sheet names (`the Home Army to take the field with 4 regiments`).
## Empty when the pick names no order this module can say, so the line can never
## promise a march to nowhere (REQ-P2-03, REQ-P5-06; DR-20261121-14).
static func order_clause(model: MapModel, pick: Dictionary) -> String:
	if pick.is_empty():
		return ""
	var kind: String = String(pick.get("kind", ""))
	if kind == MapPlayArmyPick.KIND_SPLIT:
		var going: int = int(pick.get("regiments", 0))
		if going <= 0:
			return ""
		return "to take the field with %d regiment%s" % [going, "" if going == 1 else "s"]
	if kind == MapPlayArmyPick.KIND_ROTATE:
		var home: int = int(pick.get("province", -1))
		if model == null or home < 0:
			return ""
		return "home to %s to merge with the Home Army" % model.province_name(home)
	if kind != MapPlayArmyPick.KIND_MARCH:
		return ""
	var province: int = int(pick.get("province", -1))
	if model == null or province < 0:
		return ""
	var name: String = model.province_name(province)
	if name.is_empty():
		return ""
	match String(pick.get("why", "")):
		MapPlayArmyPick.WHY_STORM:
			return "to storm %s" % name
		MapPlayArmyPick.WHY_RELIEF:
			return "to throw the host out of %s" % name
		MapPlayArmyPick.WHY_FRONTIER:
			return "to advance to %s, the frontier" % name
	return ""