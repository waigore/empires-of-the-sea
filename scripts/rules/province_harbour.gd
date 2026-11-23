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


## The province sheet's Squadrons row: `England 3 hulls · Spain 1 hull`, the
## province's own court first and every other court by faction id, or `""` for a
## harbour no squadron rides — the row hides rather than printing an absence
## (the Deeds row's own rule, DR-20261120-05).
static func line(
	fleets: Array, province_id: int, owner: int, viewer: int, known: bool
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
	var parts: PackedStringArray = PackedStringArray()
	for id: int in order:
		var hulls: int = int(counted[id])
		parts.append(
			"%s %d hull%s" % [
				FactionCatalog.name_of(id), hulls, "" if hulls == 1 else "s",
			]
		)
	return " · ".join(parts)
