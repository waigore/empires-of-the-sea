class_name ProvinceHosts
extends RefCounted
## The hosts standing on one province's ground, counted for a reading crown
## (wiki: fog-and-exploration § Order-of-battle readings; DR-20261123-13). A
## court's garrison counts are **read**, never published, for other courts: its
## own forces everywhere, and a foreign army in a province its grid holds at
## `fogged` or better. The chart draws a rival's standard only where the
## province is fully visible (`ArmyMarkers.sync_visibility`), so the province
## sheet is the one surface that carries the count the rules allow on a fogged
## chart (REQ-P2-03, REQ-P5-03).
##
## A reading only: no march, order or fight lives here, and no strength is
## predicted — a host is counted in **regiments**, the basket the rules publish.

## Per-court regiment counts on one province, keyed by faction id. The viewing
## crown's own hosts always count; another court's only while `known` — the
## province the viewer's chart holds at `fogged` or better. An army ashore only:
## an embarked host stands aboard its squadron, not on the ground
## (ArmyState.embarked_fleet).
static func counts(
	armies: Array, province_id: int, viewer: int, known: bool
) -> Dictionary:
	var found: Dictionary = {}
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army == null or army.province != province_id or army.embarked_fleet >= 0:
			continue
		if army.owner != viewer and not known:
			continue
		var men: int = army.count()
		if men <= 0:
			continue
		found[army.owner] = int(found.get(army.owner, 0)) + men
	return found


## The province sheet's Hosts row: `England 3 regiments · Aztec 1 regiment`,
## the province's own court first and every other court by faction id, or `""`
## for ground no host stands on — the row hides rather than printing an absence
## (the Deeds row's own rule, DR-20261120-05).
static func line(
	armies: Array, province_id: int, owner: int, viewer: int, known: bool
) -> String:
	var counted: Dictionary = counts(armies, province_id, viewer, known)
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
		var men: int = int(counted[id])
		parts.append(
			"%s %d regiment%s" % [
				FactionCatalog.name_of(id), men, "" if men == 1 else "s",
			]
		)
	return " · ".join(parts)
