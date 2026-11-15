class_name NavalLedger
extends RefCounted
## The crown's navy, hull by hull: every hull it floats in both charts, the
## squadron she flies under, her class and her own combat and cargo numbers
## (wiki: ships-and-naval § Ship combat and cargo stats, § Ship instances,
## § Missions and Movement; DR-20261115-14). Pure read-only projection of the
## layer rosters — it never launches, breaks up, docks or orders a hull
## (REQ-P3-02, REQ-P3-03).
##
## No number here is recomputed: a hull's line is `NavalStrength.hull_line`, her
## role is `ShipStats.entry`, and her squadron's strength and holds are
## `NavalStrength.strength` and `TradeCargo.fleet_holds`, so a row can never
## print a figure the sea's battle or the world market would not use
## (REQ-P2-03).
##
## A hull's orders are her squadron's, so the standing (where she sails, what
## station she holds) is read once on the squadron heading, and the row prints
## only what is her own: her name, her class, her guns and her holds.

const REGION_ALL: String = "all"
const REGION_OLD: String = "old_world"
const REGION_NEW: String = "new_world"
const REGION_FILTERS: Array[String] = [REGION_ALL, REGION_OLD, REGION_NEW]

## The reading's own filters: the two kinds of hull a crown acts on.
const READING_ALL: String = "all"
const READING_WARSHIP: String = "warship"
const READING_MERCHANT: String = "merchant"
const READINGS: Array[String] = [READING_ALL, READING_WARSHIP, READING_MERCHANT]

const NO_ID: int = -1


## Whole-navy snapshot in reading order. `groups` nests each squadron's rows
## under it, so the sheet prints one heading per squadron and one row per hull.
static func snapshot(
	world: WorldMap, fleet_regions: MapRegionTable, faction: int
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var groups: Array[Dictionary] = []
	var by_region: Dictionary = {}
	var squadrons: Dictionary = {}
	var strength: float = 0.0
	var holds: int = 0
	if world == null or fleet_regions == null:
		return _empty(rows, groups, by_region, squadrons, strength, holds)
	for region: int in world.region_count():
		var model: MapModel = world.region(region)
		if model == null:
			continue
		for fleet: FleetState in _fleets_of(fleet_regions, region, faction):
			var group: Dictionary = _squadron(model, fleet, region)
			var group_rows: Array[Dictionary] = []
			for hull_id: String in fleet.hulls:
				var row: Dictionary = _hull_row(model, fleet, hull_id, group)
				group_rows.append(row)
				_count(by_region, region, String(row["role"]))
			group_rows.sort_custom(_before_hull)
			# The flat reading follows the same order the sheet prints, so a
			# reader that walks `rows` sees the line before the train.
			rows.append_array(group_rows)
			group["rows"] = group_rows
			squadrons[region] = int(squadrons.get(region, 0)) + 1
			strength += NavalStrength.strength(fleet)
			holds += TradeCargo.fleet_holds(fleet)
			# A slip with no hull yet has no row of its own; the count line
			# still names the squadron, so an empty yard is never silent.
			if not group_rows.is_empty():
				groups.append(group)
	groups.sort_custom(_before_group)
	return {
		"rows": rows,
		"groups": groups,
		"by_region": by_region,
		"squadrons": squadrons,
		"strength": strength,
		"holds": holds,
		"total": rows.size(),
	}


## Squadrons narrowed to one chart and one reading, each keeping only the hulls
## the reading names. A squadron with no row left drops out.
static func groups(
	data: Dictionary, region_key: String, reading: String = READING_ALL
) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for raw: Variant in data.get("groups", []):
		var group: Dictionary = raw
		if not region_matches(int(group.get("region", NO_ID)), region_key):
			continue
		var rows: Array[Dictionary] = []
		for entry: Variant in group.get("rows", []):
			var row: Dictionary = entry
			if not matches(row, reading):
				continue
			rows.append(row)
		if rows.is_empty():
			continue
		var narrowed: Dictionary = group.duplicate()
		narrowed["rows"] = rows
		kept.append(narrowed)
	return kept


static func count(data: Dictionary, region_key: String, reading: String = READING_ALL) -> int:
	var total: int = 0
	for group: Dictionary in groups(data, region_key, reading):
		total += (group["rows"] as Array).size()
	return total


## How many hulls each reading would show inside one chart, so a chip carries
## its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	var counts: Dictionary = {}
	for key: String in READINGS:
		counts[key] = count(data, region_key, key)
	return counts


## How many squadrons the crown floats inside one chart, hull-less slips
## included: the count line reads the fleet, not only the hulls on it.
static func squadron_count(data: Dictionary, region_key: String) -> int:
	var total: int = 0
	for raw: Variant in (data.get("squadrons", {}) as Dictionary).keys():
		if region_matches(int(raw), region_key):
			total += int(data["squadrons"][raw])
	return total


static func matches(row: Dictionary, reading: String) -> bool:
	if reading.is_empty() or reading == READING_ALL:
		return true
	return String(row.get("role", "")) == reading


static func region_matches(region: int, key: String) -> bool:
	match key:
		REGION_OLD:
			return region == FactionCatalog.OLD_WORLD
		REGION_NEW:
			return region == FactionCatalog.NEW_WORLD
	return true


## The reading's own word, for its chip and the sheet's count line.
static func reading_label(key: String) -> String:
	match key:
		READING_WARSHIP:
			return "Warships"
		READING_MERCHANT:
			return "Merchant hulls"
	return "All hulls"


# --- readings ---------------------------------------------------------------


## The count line: the view against the chart it is read in, with the fleet's
## own totals when the reading shows every hull (REQ-P5-05). A narrowed reading
## prints no holds or strength, because a squadron's holds belong to her
## merchant hulls and a squadron's strength to all of them; the totals are
## summed over the squadrons the chart holds, so a one-chart view never prints
## the other chart's fleet.
static func summary(
	data: Dictionary, region_key: String, reading: String = READING_ALL
) -> String:
	var in_scope: int = count(data, region_key, READING_ALL)
	var shown: int = count(data, region_key, reading)
	var scope: String = scope_text(region_key)
	var squadrons: int = squadron_count(data, region_key)
	var fleet: String = "%d squadron%s" % [squadrons, "" if squadrons == 1 else "s"]
	if reading != READING_ALL and not reading.is_empty():
		return "Showing %d of %d hulls %s — %s only." % [
			shown, in_scope, scope, reading_label(reading).to_lower()
		]
	var counts: Dictionary = filter_counts(data, region_key)
	var holds: int = 0
	var strength: float = 0.0
	for group: Dictionary in groups(data, region_key, READING_ALL):
		holds += int(group["holds"])
		strength += float(group["strength"])
	return "Showing %d of %d hulls in %s %s — %d warships, %d merchant hulls · %d holds · %.1f strength." % [
		shown,
		in_scope,
		fleet,
		scope,
		int(counts.get(READING_WARSHIP, 0)),
		int(counts.get(READING_MERCHANT, 0)),
		holds,
		strength,
	]


static func scope_text(region_key: String) -> String:
	if region_key == REGION_OLD:
		return "in the Old World"
	if region_key == REGION_NEW:
		return "in the New World"
	return "in both charts"


## The rule a crown pays by sits on the sheet, never in a hover: a merchant
## hull's holds cap what the world market will sell the crown, and every hull's
## guns and planking stand in the strength the sea's battle fights with
## (wiki: ships-and-naval § Cargo holds and capacity, § Aggregation Formula).
static func note() -> String:
	return (
		"A merchant hull's holds cap what the world market sells the crown "
		+ "each turn; every hull's guns, range, armour, planking and sailing "
		+ "stand in the strength the sea's battle fights with."
	)


# --- rows -------------------------------------------------------------------


## One squadron's standing: the flagship it flies under, where it sails and the
## station it holds. Every hull of hers reads this heading before its own row.
static func _squadron(model: MapModel, fleet: FleetState, region: int) -> Dictionary:
	return {
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"fleet": fleet.id,
		"title": _squadron_title(fleet),
		"heading": "%s  ·  %s" % [
			FactionCatalog.region_label(region).to_upper(), _squadron_title(fleet).to_upper()
		],
		"place": _fleet_place(model, fleet),
		"station": _fleet_station(fleet),
		"hulls": fleet.ship_count(),
		"holds": TradeCargo.fleet_holds(fleet),
		"strength": NavalStrength.strength(fleet),
	}


## A squadron is named by the flagship she already flies (wiki: naming § Ship
## names), so two squadrons never read alike. The name is read, never written.
static func _squadron_title(fleet: FleetState) -> String:
	if fleet.hulls.is_empty():
		return "Yard slip"
	return "Squadron — %s" % ShipNames.of(fleet, fleet.hulls[0])


static func _hull_row(
	model: MapModel, fleet: FleetState, hull_id: String, group: Dictionary
) -> Dictionary:
	var type_id: String = fleet.type_of(hull_id)
	var role: String = READING_WARSHIP if ShipStats.is_warship(type_id) else READING_MERCHANT
	return {
		"hull": hull_id,
		"name": ShipNames.of(fleet, hull_id),
		"type": type_id,
		"class": ShipStats.display_name(type_id),
		"role": role,
		"role_label": "WARSHIP" if role == READING_WARSHIP else "MERCHANT",
		"region": int(group["region"]),
		"region_label": String(group["region_label"]),
		"fleet": fleet.id,
		"fleet_title": String(group["title"]),
		"place": _fleet_place(model, fleet),
		"line": NavalStrength.hull_line(type_id),
		"state": _hull_state(type_id, role),
		"holds": int(ShipStats.entry(type_id).get("cargo", 0)),
		"strength": ShipStats.strength(type_id),
		"durability": ShipStats.durability(type_id),
		"flags": [role],
	}


## What a hull is for, in the rules' own figures: a merchant hull's holds are
## what the market sells against, and a warship carries none — she fights.
static func _hull_state(type_id: String, role: String) -> String:
	var cargo: int = int(ShipStats.entry(type_id).get("cargo", 0))
	if role == READING_WARSHIP:
		return "No holds — she fights in the line"
	return "%d hold%s for the world market" % [cargo, "" if cargo == 1 else "s"]


## Where the squadron sails. The hull's orders are the squadron's, so every row
## of hers reads the same place.
static func _fleet_place(model: MapModel, fleet: FleetState) -> String:
	if fleet.is_in_port():
		var port: String = model.province_name(fleet.province)
		return ("In port at %s" % port) if not port.is_empty() else "In port"
	var zone: String = model.sea_zone_name(fleet.sea_zone)
	return ("At sea — %s" % zone) if not zone.is_empty() else "At sea"


static func _fleet_station(fleet: FleetState) -> String:
	if fleet.mission == FleetState.Mission.NONE:
		return "Awaiting orders"
	return FleetMissions.label(fleet.mission)


# --- assembly ---------------------------------------------------------------


static func _count(by_region: Dictionary, region: int, role: String) -> void:
	var counts: Dictionary = by_region.get(region, {READING_WARSHIP: 0, READING_MERCHANT: 0})
	counts[role] = int(counts.get(role, 0)) + 1
	by_region[region] = counts


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


static func _empty(
	rows: Array[Dictionary],
	groups: Array[Dictionary],
	by_region: Dictionary,
	squadrons: Dictionary,
	strength: float,
	holds: int
) -> Dictionary:
	return {
		"rows": rows,
		"groups": groups,
		"by_region": by_region,
		"squadrons": squadrons,
		"strength": strength,
		"holds": holds,
		"total": rows.size(),
	}


## The line leads: warships before merchantmen, then the heavier class, then
## the instance id, so a squadron reads the same way every turn.
static func _before_hull(a: Dictionary, b: Dictionary) -> bool:
	if String(a["role"]) != String(b["role"]):
		return String(a["role"]) == READING_WARSHIP
	if String(a["class"]) != String(b["class"]):
		return String(a["class"]) < String(b["class"])
	return String(a["hull"]) < String(b["hull"])


static func _before_group(a: Dictionary, b: Dictionary) -> bool:
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	return int(a["fleet"]) < int(b["fleet"])
