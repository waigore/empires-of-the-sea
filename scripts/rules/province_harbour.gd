class_name ProvinceHarbour
extends RefCounted
## The squadrons standing in one province's harbour, counted for a reading crown
## (wiki: fog-and-exploration § Order-of-battle readings; DR-20261123-14). A
## court's hull counts are **read**, never published, for other courts: its own
## hulls everywhere, and a foreign squadron "in a charted port". The chart draws
## a rival's marker only where the province is fully visible
## (`MapPlayFleetIntel._known`), so the province sheet is the one surface that
## carries the count the rules allow on a fogged chart (REQ-P2-03, REQ-P5-03).
##
## A reading only: no sail, order or fight lives here, and no strength is
## predicted — a squadron is counted in **hulls**, the basket the rules publish.

## Per-court hull counts in one harbour, keyed by faction id. The viewing
## crown's own hulls always count; another court's only while `known` — the
## province the viewer's chart holds at `fogged` or better. A squadron in port
## only: a squadron at sea rides no harbour, and a slip with no hulls names none.
static func counts(
	fleets: Array, province_id: int, viewer: int, known: bool
) -> Dictionary:
	var found: Dictionary = {}
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.province != province_id or not fleet.is_in_port():
			continue
		if fleet.owner != viewer and not known:
			continue
		var hulls: int = fleet.ship_count()
		if hulls <= 0:
			continue
		found[fleet.owner] = int(found.get(fleet.owner, 0)) + hulls
	return found


## Regiments riding the squadrons in one harbour, keyed by faction id. The same
## gate and the same squadrons as `counts` — the viewer's own everywhere, and
## another court's only while `known` — because a regiment aboard a squadron is
## the third reading the rules publish (wiki: fog-and-exploration §
## Order-of-battle readings, "a regiment aboard a squadron wherever that squadron
## is seen"). The fleet's own `embarked_army` names the host it carries, so a
## stale back-reference on the army cannot invent one (DR-20261123-18).
static func aboard(
	fleets: Array, armies: Array, province_id: int, viewer: int, known: bool
) -> Dictionary:
	var found: Dictionary = {}
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.province != province_id or not fleet.is_in_port():
			continue
		if fleet.owner != viewer and not known:
			continue
		if fleet.ship_count() <= 0:
			continue
		var men: int = _carried(fleet, armies)
		if men <= 0:
			continue
		found[fleet.owner] = int(found.get(fleet.owner, 0)) + men
	return found


## The regiments one squadron carries: the host its own `embarked_army` names,
## counted the rules' way (`ArmyState.count`). A squadron carrying no host, or a
## host another court owns, carries none.
static func _carried(fleet: FleetState, armies: Array) -> int:
	if fleet.embarked_army < 0:
		return 0
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army == null or army.id != fleet.embarked_army:
			continue
		if army.owner != fleet.owner:
			return 0
		return army.count()
	return 0


## The province sheet's Squadrons row: `England 3 hulls · Spain 1 hull`, the
## province's own court first and every other court by faction id, or `""` for a
## harbour no squadron rides — the row hides rather than printing an absence
## (the Deeds row's own rule, DR-20261120-05). A squadron carrying a host names
## the men too — `England 3 hulls, 2 regiments aboard` — so this row and the
## Hosts row above it account for every regiment the rules let a crown read on
## one province.
static func line(
	fleets: Array,
	province_id: int,
	owner: int,
	viewer: int,
	known: bool,
	armies: Array = []
) -> String:
	var counted: Dictionary = counts(fleets, province_id, viewer, known)
	if counted.is_empty():
		return ""
	var rest: Array[int] = []
	for raw: Variant in counted.keys():
		if int(raw) != owner:
			rest.append(int(raw))
	rest.sort()
	var order: Array[int] = []
	if counted.has(owner):
		order.append(owner)
	order.append_array(rest)
	var riding: Dictionary = aboard(fleets, armies, province_id, viewer, known)
	var parts: PackedStringArray = PackedStringArray()
	for id: int in order:
		var hulls: int = int(counted[id])
		var clause: String = "%s %d hull%s" % [
			FactionCatalog.name_of(id), hulls, "" if hulls == 1 else "s",
		]
		var men: int = int(riding.get(id, 0))
		if men > 0:
			clause += ", %d regiment%s aboard" % [men, "" if men == 1 else "s"]
		parts.append(clause)
	return " · ".join(parts)
