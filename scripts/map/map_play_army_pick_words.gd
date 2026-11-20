class_name MapPlayArmyPickWords
extends RefCounted
## How one land pick is worded (wiki: military-armies § Home Army, § Movement and
## attacks; DR-20261120-10): the order the published land policy would give the
## standard, in the rule book's own names — the field the Home Army would take,
## the province a field army would march on and the ground's own reason, the road
## home to merge. A reading, never an order; every figure is one the planner
## actually decided on (REQ-P2-03, REQ-P5-06).


## The pick's own sentence, opened like one: one capital and a full stop.
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


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