class_name ForceLedger
extends RefCounted
## The crown's whole-empire muster roll: every army and squadron it holds, in
## both regions, with where each stands and what it carries (wiki:
## military-armies § The muster roll; DR-20261113-12). Pure read-only projection
## of the layer rosters — it never marches, musters, docks or spends, so the
## panel and the tests read the same rows (REQ-P3-02, REQ-P3-03).
##
## Rows stay presentation data: names come from the chart at read time and no
## number here is recomputed — strength is the resolver's own aggregation
## (`ArmyForce.side_strength`, `NavalStrength.strength`), so a ledger row can
## never print a figure the battle would not use (REQ-P2-03).

const REGION_ALL: String = "all"
const REGION_OLD: String = "old_world"
const REGION_NEW: String = "new_world"
const REGION_FILTERS: Array[String] = [REGION_ALL, REGION_OLD, REGION_NEW]

const KIND_ALL: String = "all"
const KIND_ARMY: String = "army"
const KIND_SQUADRON: String = "squadron"
const KIND_FILTERS: Array[String] = [KIND_ALL, KIND_ARMY, KIND_SQUADRON]

const NO_ID: int = -1


## Whole-empire snapshot in reading order. `groups` nests rows under the region
## that holds them so the panel prints one heading per chart.
static func snapshot(
	world: WorldMap,
	army_regions: MapRegionTable,
	fleet_regions: MapRegionTable,
	faction: int
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var by_kind: Dictionary = {KIND_ARMY: 0, KIND_SQUADRON: 0}
	if world == null:
		return _empty(rows, by_kind)
	for region: int in world.region_count():
		var model: MapModel = world.region(region)
		if model == null:
			continue
		var fleets: Array[FleetState] = _fleets_of(fleet_regions, region, faction)
		for raw: Variant in _stored(army_regions, region):
			var army := raw as ArmyState
			if army == null or army.owner != faction:
				continue
			rows.append(_army_row(model, army, region, fleets))
			by_kind[KIND_ARMY] = int(by_kind[KIND_ARMY]) + 1
		for fleet: FleetState in fleets:
			rows.append(_fleet_row(model, fleet, region))
			by_kind[KIND_SQUADRON] = int(by_kind[KIND_SQUADRON]) + 1
	rows.sort_custom(_before)
	var result: Dictionary = _empty(rows, by_kind)
	result["groups"] = _group(rows)
	return result


## Rows narrowed to one region key and one kind (empty/all keeps every kind).
static func groups(
	data: Dictionary, region_key: String, kind: String = KIND_ALL
) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for raw: Variant in data.get("groups", []):
		var group: Dictionary = raw
		if not region_matches(int(group.get("region", -1)), region_key):
			continue
		var rows: Array[Dictionary] = []
		for entry: Variant in group.get("rows", []):
			var row: Dictionary = entry
			if not kind.is_empty() and kind != KIND_ALL and String(row["kind"]) != kind:
				continue
			rows.append(row)
		if rows.is_empty():
			continue
		var narrowed: Dictionary = group.duplicate()
		narrowed["rows"] = rows
		kept.append(narrowed)
	return kept


static func count(data: Dictionary, region_key: String, kind: String = KIND_ALL) -> int:
	var total: int = 0
	for group: Dictionary in groups(data, region_key, kind):
		total += (group["rows"] as Array).size()
	return total


## Armies and squadrons inside one region filter, so the head can print both
## totals and keep a zero legible rather than hiding the button.
static func kind_counts(data: Dictionary, region_key: String) -> Dictionary:
	var counts: Dictionary = {KIND_ARMY: 0, KIND_SQUADRON: 0}
	for raw: Variant in data.get("rows", []):
		var row: Dictionary = raw
		if not region_matches(int(row["region"]), region_key):
			continue
		var kind: String = String(row["kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


static func region_matches(region: int, key: String) -> bool:
	match key:
		REGION_OLD:
			return region == FactionCatalog.OLD_WORLD
		REGION_NEW:
			return region == FactionCatalog.NEW_WORLD
	return true


## One-word name of a kind, and its plural, for headings and filter chips.
static func kind_label(kind: String, plural: bool = false) -> String:
	if kind == KIND_SQUADRON:
		return "squadrons" if plural else "squadron"
	return "armies" if plural else "army"


# --- rows -------------------------------------------------------------------


static func _army_row(
	model: MapModel, army: ArmyState, region: int, fleets: Array[FleetState]
) -> Dictionary:
	var count: int = army.regiments.size()
	var one: Array[ArmyState] = [army]
	return {
		"kind": KIND_ARMY,
		"id": army.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"title": "Home Army" if army.home else "Field army",
		"place": _army_place(model, army, fleets),
		"line": "%d regiment%s · %.1f strength" % [
			count, "" if count == 1 else "s", ArmyForce.side_strength(one)
		],
		"state": _army_state(army),
		"strength": ArmyForce.side_strength(one),
		"moved": army.moved,
	}


static func _fleet_row(model: MapModel, fleet: FleetState, region: int) -> Dictionary:
	var count: int = fleet.ship_count()
	return {
		"kind": KIND_SQUADRON,
		"id": fleet.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"title": _squadron_title(fleet),
		"place": _fleet_place(model, fleet),
		"line": "%d hull%s · %d holds · %.1f strength" % [
			count, "" if count == 1 else "s", TradeCargo.fleet_holds(fleet),
			NavalStrength.strength(fleet)
		],
		"state": _fleet_state(model, fleet),
		"strength": NavalStrength.strength(fleet),
		"moved": fleet.moved,
	}


## A squadron is named by the flagship it already flies (hulls carry their own
## names, wiki: naming § Ship names), so three squadrons never read alike. The
## name is read, never christened here: the muster roll writes nothing.
static func _squadron_title(fleet: FleetState) -> String:
	if fleet.hulls.is_empty():
		return "Squadron"
	var flagship: String = String(fleet.hull_names.get(String(fleet.hulls[0]), ""))
	return ("Squadron — %s" % flagship) if not flagship.is_empty() else "Squadron"


## Where an army stands. An embarked army has no province of its own, so the
## reading names the squadron that carries it instead of the last shore.
static func _army_place(model: MapModel, army: ArmyState, fleets: Array[FleetState]) -> String:
	if army.embarked_fleet != NO_ID:
		for fleet: FleetState in fleets:
			if fleet.id == army.embarked_fleet:
				return "Aboard a squadron — %s" % _fleet_place(model, fleet)
		return "Aboard a squadron"
	var name: String = model.province_name(army.province)
	return name if not name.is_empty() else "In the field"


static func _army_state(army: ArmyState) -> String:
	if army.home:
		return "Musters at the seat — never marches"
	if army.embarked_fleet != NO_ID:
		return "Embarked — fights where it lands"
	var state: String = "Marched this turn" if army.moved else "Held in place"
	if army.field_hospital:
		state += " · field hospital"
	return state


static func _fleet_place(model: MapModel, fleet: FleetState) -> String:
	if fleet.is_in_port():
		var port: String = model.province_name(fleet.province)
		return ("In port at %s" % port) if not port.is_empty() else "In port"
	var zone: String = model.sea_zone_name(fleet.sea_zone)
	return ("At sea — %s" % zone) if not zone.is_empty() else "At sea"


static func _fleet_state(model: MapModel, fleet: FleetState) -> String:
	var parts: PackedStringArray = []
	if fleet.mission != FleetState.Mission.NONE:
		parts.append(FleetMissions.label(fleet.mission))
	if fleet.embarked_army != NO_ID:
		parts.append("carrying an army")
	elif fleet.civilian_count() > 0:
		parts.append("carrying %d civilian%s" % [
			fleet.civilian_count(), "" if fleet.civilian_count() == 1 else "s"
		])
	if parts.is_empty():
		parts.append("Awaiting orders")
	var state: String = " · ".join(parts)
	if fleet.has_beachhead():
		state += " · beachhead marked"
	return state


# --- assembly ---------------------------------------------------------------


static func _fleets_of(
	fleet_regions: MapRegionTable, region: int, faction: int
) -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	for raw: Variant in _stored(fleet_regions, region):
		var fleet := raw as FleetState
		if fleet != null and fleet.owner == faction:
			fleets.append(fleet)
	return fleets


static func _stored(table: MapRegionTable, region: int) -> Array:
	if table == null:
		return []
	var stored: Variant = table.value(region, [])
	if stored is Array:
		return stored
	return []


static func _empty(rows: Array[Dictionary], by_kind: Dictionary) -> Dictionary:
	return {
		"rows": rows,
		"groups": [],
		"by_kind": by_kind,
		"total": rows.size(),
	}


static func _group(rows: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var key: int = -1
	for row: Dictionary in rows:
		if int(row["region"]) != key:
			key = int(row["region"])
			groups.append({
				"region": key,
				"region_label": String(row["region_label"]),
				"rows": [],
			})
		(groups.back()["rows"] as Array).append(row)
	return groups


## Armies first (the men hold ground), then squadrons; inside a kind, the
## chart's alphabetical place and then the instance id keep the order stable.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	if String(a["kind"]) != String(b["kind"]):
		return String(a["kind"]) == KIND_ARMY
	var left: String = String(a["place"])
	var right: String = String(b["place"])
	if left != right:
		return left < right
	return int(a["id"]) < int(b["id"])
