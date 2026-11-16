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

## The reading's own filters: the two kinds of hull a crown acts on.
const READING_ALL: String = "all"
const READING_WARSHIP: String = "warship"
const READING_MERCHANT: String = "merchant"
const READINGS: Array[String] = [READING_ALL, READING_WARSHIP, READING_MERCHANT]


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
	return LedgerRows.groups(data, region_key, matches.bind(reading))


static func count(data: Dictionary, region_key: String, reading: String = READING_ALL) -> int:
	return LedgerRows.count(data, region_key, matches.bind(reading))


## How many hulls each reading would show inside one chart, so a chip carries
## its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	return LedgerRows.counts(data, region_key, READINGS, matches)


## How many squadrons the crown floats inside one chart, hull-less slips
## included: the count line reads the fleet, not only the hulls on it.
static func squadron_count(data: Dictionary, region_key: String) -> int:
	var total: int = 0
	for raw: Variant in (data.get("squadrons", {}) as Dictionary).keys():
		if LedgerRows.region_matches(int(raw), region_key):
			total += int(data["squadrons"][raw])
	return total


static func matches(row: Dictionary, reading: String) -> bool:
	return LedgerRows.field_matches(row, "role", reading)


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
	return LedgerRows.scope_text(region_key)


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
		"place": LedgerRows.fleet_place(model, fleet),
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
		"place": LedgerRows.fleet_place(model, fleet),
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
	return LedgerRows.stored_fleets(fleet_regions, region, faction)


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


## The line leads: warships before merchantmen, then the heavier class — the
## class's own weighted strength, the figure her row prints — then the instance
## id, so a squadron reads the same way every turn and a ship-of-the-line never
## reads under a frigate (wiki: ships-and-naval § The crown's navy).
static func _before_hull(a: Dictionary, b: Dictionary) -> bool:
	if String(a["role"]) != String(b["role"]):
		return String(a["role"]) == READING_WARSHIP
	var left: float = float(a["strength"])
	var right: float = float(b["strength"])
	if not is_equal_approx(left, right):
		return left > right
	if String(a["class"]) != String(b["class"]):
		return String(a["class"]) < String(b["class"])
	return _hull_before(String(a["hull"]), String(b["hull"]))


## Hull instance ids are `ship_<n>` (wiki: ships-and-naval § Ship instances), so
## the reading orders them by their number and not by their spelling: ship_9
## reads before ship_10. An id that carries no number falls back to its text.
static func _hull_before(a: String, b: String) -> bool:
	var left: int = _hull_number(a)
	var right: int = _hull_number(b)
	if left >= 0 and right >= 0 and left != right:
		return left < right
	return a < b


## The number in a hull instance id, or -1 when the id is not `ship_<n>`.
static func _hull_number(hull_id: String) -> int:
	if not hull_id.begins_with("ship_"):
		return -1
	var tail: String = hull_id.substr(5)
	if not tail.is_valid_int():
		return -1
	return tail.to_int()


static func _before_group(a: Dictionary, b: Dictionary) -> bool:
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	return int(a["fleet"]) < int(b["fleet"])
