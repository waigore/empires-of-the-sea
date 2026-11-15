class_name LedgerRows
extends RefCounted
## The plumbing every crown ledger shares: which chart a row sits on, the rows a
## chart-and-reading filter leaves, the tally each chip carries and the one
## heading per chart they print under (REQ-P3-01, REQ-P3-02).
##
## The people, the provinces, the towns, the muster roll and the navy all read
## the same way — a snapshot of rows, narrowed by chart and by the sheet's own
## reading, counted for the chips and grouped for the headings — so that shape is
## written once here instead of copied per sheet. A sheet keeps what is its own:
## the words of its readings, the row it mints and the order it prints them in.
##
## Pure helpers over presentation dictionaries: no nodes, no rules outcome and no
## snapshot of their own (REQ-P3-03).

## The key every sheet uses to mean "every row" of its own reading, and the
## chart keys each sheet narrows with.
const ALL: String = "all"
const REGION_ALL: String = ALL
const REGION_OLD: String = "old_world"
const REGION_NEW: String = "new_world"
const REGION_FILTERS: Array[String] = [REGION_ALL, REGION_OLD, REGION_NEW]


## Which chart a row sits on, read against one of REGION_FILTERS. `all` — and any
## key a sheet does not know — keeps every chart.
static func region_matches(region: int, key: String) -> bool:
	match key:
		REGION_OLD:
			return region == FactionCatalog.OLD_WORLD
		REGION_NEW:
			return region == FactionCatalog.NEW_WORLD
	return true


## The chart a view is read in, as a sheet's count line says it: "in both charts",
## "in the Old World", "in the New World". One wording, so no sheet writes the
## same three branches again.
static func scope_text(region_key: String) -> String:
	if region_key == REGION_OLD:
		return "in the Old World"
	if region_key == REGION_NEW:
		return "in the New World"
	return "in both charts"


## True when a row's own reading equals the key; `all` (or an empty key) keeps
## every row. A sheet whose reading is one word on the row — a kind, a state, a
## role — reads it here instead of writing the same comparison again.
static func field_matches(row: Dictionary, field: String, key: String) -> bool:
	if key.is_empty() or key == ALL:
		return true
	return String(row.get(field, "")) == key


## True when the row carries the key among its flags (a province's defect, a
## hull's role); `all` keeps every row.
static func flags_match(row: Dictionary, key: String) -> bool:
	if key.is_empty() or key == ALL:
		return true
	return (row.get("flags", []) as Array).has(key)


## The snapshot's groups narrowed to one chart and to the rows `keep` accepts. A
## group with no row left drops out, so a heading never stands over an empty
## chart; the snapshot's own groups are left untouched.
static func groups(
	data: Dictionary, region_key: String, keep: Callable
) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for raw: Variant in data.get("groups", []):
		var group: Dictionary = raw
		if not region_matches(int(group.get("region", -1)), region_key):
			continue
		var rows: Array[Dictionary] = []
		for entry: Variant in group.get("rows", []):
			var row: Dictionary = entry
			if not bool(keep.call(row)):
				continue
			rows.append(row)
		if rows.is_empty():
			continue
		var narrowed: Dictionary = group.duplicate()
		narrowed["rows"] = rows
		kept.append(narrowed)
	return kept


## How many rows a narrowed view prints: the sheet's count line and a chip's own
## tally read the same number.
static func count(data: Dictionary, region_key: String, keep: Callable) -> int:
	var total: int = 0
	for group: Dictionary in groups(data, region_key, keep):
		total += (group["rows"] as Array).size()
	return total


## One tally per reading key, each read against the chart alone, so a chip can
## carry its own count and a zero stays legible rather than hidden. `reading`
## is the sheet's own `(row, key) -> bool`.
static func counts(
	data: Dictionary, region_key: String, keys: Array, reading: Callable
) -> Dictionary:
	var counts: Dictionary = {}
	for key: String in keys:
		counts[key] = count(data, region_key, reading.bind(key))
	return counts


## Rows nested under the chart that holds them, in the order they arrive: one
## heading per chart, however the sheet's own reading order interleaves the
## charts (a town's level, a spy's duty). A chart's heading stands where its
## first row does, and its rows keep the order they arrive in, so a sheet that
## sorts by its own key before the chart still prints one heading per chart
## instead of splitting a chart in two.
static func group(rows: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var at: Dictionary = {}
	for row: Dictionary in rows:
		var region: int = int(row["region"])
		if not at.has(region):
			at[region] = groups.size()
			groups.append({
				"region": region,
				"region_label": String(row["region_label"]),
				"rows": [] as Array[Dictionary],
			})
		(groups[int(at[region])]["rows"] as Array[Dictionary]).append(row)
	return groups


## One region's roster as an Array, empty when the region was never visited or
## the table is missing. A ledger only walks rosters, so the null-and-type guard
## is asked for once here instead of copied into every sheet.
static func stored_rows(table: MapRegionTable, region: int) -> Array:
	if table == null:
		return []
	var stored: Variant = table.value(region, [])
	return stored if stored is Array else []


## The crown's own squadrons in one chart: the region's roster read as fleets and
## kept to `faction`. The muster roll and the navy both walk it, so the guard and
## the owner test are asked for once here.
static func stored_fleets(
	table: MapRegionTable, region: int, faction: int
) -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	for raw: Variant in stored_rows(table, region):
		var fleet := raw as FleetState
		if fleet != null and fleet.owner == faction:
			fleets.append(fleet)
	return fleets


## Where one squadron stands, as both the muster roll and the navy sheet read
## her: "In port at Lisbon", "At sea — Western Approaches". One wording, so the
## two sheets can never name the same berth differently, and the chart owns the
## names it prints.
static func fleet_place(model: MapModel, fleet: FleetState) -> String:
	if fleet.is_in_port():
		var port: String = model.province_name(fleet.province)
		return ("In port at %s" % port) if not port.is_empty() else "In port"
	var zone: String = model.sea_zone_name(fleet.sea_zone)
	return ("At sea — %s" % zone) if not zone.is_empty() else "At sea"
