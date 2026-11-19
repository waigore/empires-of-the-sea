class_name CivilianRoster
extends RefCounted
## View-model for the crown's civilian roster: every unit in every region, with
## the province it stands in and its current order. Pure data, so the panel and
## the tests read the same rows (REQ-P3-02, REQ-P3-03).
##
## The roster is a read-only projection of MapRegionTable + MapModel; it never
## moves, assigns or advances a unit. Rows carry the unit id and region, which is
## all the screen needs to jump to the unit on its own map.

## Who waits for orders. A working unit is paid for and counting down; an idle
## one is free to be given a new one, and a column of them is the crown's
## chore (REQ-P5-04).
const STATUS_ALL: String = "all"
const STATUS_IDLE: String = "idle"
const STATUS_WORKING: String = "working"
const STATUS_FILTERS: Array[String] = [STATUS_ALL, STATUS_IDLE, STATUS_WORKING]

const NO_PROVINCE: int = -1
## The line a walk prints when no crew waits: the press is hidden in that state,
## so this is the answer to a press that raced the turn's close.
const IDLE_NONE: String = "No crew waits for orders."


## Whole-empire snapshot in map order. `groups` nests rows under region then
## province so the panel can print one heading per posting.
static func snapshot(
	world: WorldMap, regions: MapRegionTable, faction: int
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var by_type: Dictionary = {}
	for type_id: String in CivilianCatalog.ORDER:
		by_type[type_id] = 0
	var by_region: Dictionary = {}
	if world == null or regions == null:
		return _empty(rows, by_type, by_region)
	for region: int in world.region_count():
		by_region[region] = 0
		var model: MapModel = world.region(region)
		if model == null:
			continue
		var stored: Array[CivilianState] = []
		stored.assign(regions.value(region, []))
		for unit: CivilianState in stored:
			if unit == null or unit.owner != faction:
				continue
			var row: Dictionary = _row(model, unit, region)
			rows.append(row)
			by_type[String(row["type_id"])] = int(by_type.get(row["type_id"], 0)) + 1
			by_region[region] = int(by_region[region]) + 1
	rows.sort_custom(_before)
	var result: Dictionary = _empty(rows, by_type, by_region)
	result["groups"] = _group(rows)
	return result


## Rows narrowed to one region key, one type (empty type keeps every type) and
## one order status (all keeps both). Each facet is read against the other two,
## so a chip's tally is what pressing it would show.
static func groups(
	snapshot_data: Dictionary, region_key: String, type_id: String = "",
	status_key: String = STATUS_ALL
) -> Array[Dictionary]:
	return LedgerRows.groups(snapshot_data, region_key, _keep.bind(type_id, status_key))


static func count(
	snapshot_data: Dictionary, region_key: String, type_id: String = "",
	status_key: String = STATUS_ALL
) -> int:
	return LedgerRows.count(snapshot_data, region_key, _keep.bind(type_id, status_key))


## One row survives when it is the craft the type chip names (empty keeps every
## craft) and the order the status chip names.
static func _keep(row: Dictionary, type_id: String, status_key: String) -> bool:
	if not type_id.is_empty() and String(row["type_id"]) != type_id:
		return false
	return status_matches(row, status_key)


## Type totals inside one region and order filter, for the icon chips (all six
## types stay listed so a zero is legible rather than a vanished button).
static func type_counts(
	snapshot_data: Dictionary, region_key: String, status_key: String = STATUS_ALL
) -> Dictionary:
	var counts: Dictionary = {}
	for type_id: String in CivilianCatalog.ORDER:
		counts[type_id] = 0
	for raw: Variant in snapshot_data.get("rows", []):
		var row: Dictionary = raw
		if not LedgerRows.region_matches(int(row["region"]), region_key):
			continue
		if not status_matches(row, status_key):
			continue
		var type_id: String = String(row["type_id"])
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	return counts


## Idle and at-work totals inside one region and craft filter, for the order
## chips. `all` is the sum, so the three chips always agree with the rows.
static func status_counts(
	snapshot_data: Dictionary, region_key: String, type_id: String = ""
) -> Dictionary:
	var counts: Dictionary = {STATUS_ALL: 0, STATUS_IDLE: 0, STATUS_WORKING: 0}
	for raw: Variant in snapshot_data.get("rows", []):
		var row: Dictionary = raw
		if not LedgerRows.region_matches(int(row["region"]), region_key):
			continue
		if not type_id.is_empty() and String(row["type_id"]) != type_id:
			continue
		counts[STATUS_ALL] = int(counts[STATUS_ALL]) + 1
		var key: String = STATUS_WORKING if bool(row["working"]) else STATUS_IDLE
		counts[key] = int(counts[key]) + 1
	return counts


static func status_matches(row: Dictionary, key: String) -> bool:
	match key:
		STATUS_IDLE:
			return not bool(row.get("working", false))
		STATUS_WORKING:
			return bool(row.get("working", false))
	return true


## One-word name of an order filter, for the chips and the sheet's subtitle.
static func status_label(key: String) -> String:
	match key:
		STATUS_IDLE:
			return "Idle"
		STATUS_WORKING:
			return "At work"
	return "All orders"


## The crews that wait for orders, in the roster's own reading order, so the walk
## that finds them never depends on the chips the reader left set (REQ-P5-04).
static func idle_rows(snapshot_data: Dictionary) -> Array[Dictionary]:
	var waiting: Array[Dictionary] = []
	for raw: Variant in snapshot_data.get("rows", []):
		var row: Dictionary = raw
		if not bool(row.get("working", false)):
			waiting.append(row)
	return waiting


## The crew that waits after the one the crown is looking at — the next press's
## own answer, wrapping onto the first so a walk covers the whole column. An
## empty dictionary when every crew has an order. A selection that is at work (or
## none at all) starts the walk at the first crew that waits.
static func next_idle(
	snapshot_data: Dictionary, region: int, unit_id: int
) -> Dictionary:
	var waiting: Array[Dictionary] = idle_rows(snapshot_data)
	if waiting.is_empty():
		return {}
	var start: int = 0
	for index in waiting.size():
		var row: Dictionary = waiting[index]
		if int(row["unit_id"]) == unit_id and int(row["region"]) == region:
			start = (index + 1) % waiting.size()
			break
	return waiting[start]


## How many crews wait, in the words the press and its receipt use: "2 crews
## wait for orders", "1 crew waits for orders", "every crew has its order".
static func idle_note(snapshot_data: Dictionary) -> String:
	var idle: int = int(snapshot_data.get("idle", 0))
	if idle <= 0:
		return "every crew has its order"
	if idle == 1:
		return "1 crew waits for orders"
	return "%d crews wait for orders" % idle


## The line a walk prints: the crew the crown was sent to and how many others
## still wait behind it. The press gives the crew the court's eye, not an order,
## so the count is the roster's own less the one now on screen (REQ-P5-05).
static func idle_receipt(row: Dictionary, waiting: int) -> String:
	var crew: String = String(row.get("role", "Crew"))
	var place: String = String(row.get("province_name", "the map"))
	if waiting <= 0:
		return "%s at %s — the only crew that waited." % [crew, place]
	if waiting == 1:
		return "%s at %s — 1 crew still waits." % [crew, place]
	return "%s at %s — %d crews still wait." % [crew, place, waiting]


## The press's own caption: what it does and how many it can find.
static func find_caption(snapshot_data: Dictionary) -> String:
	var idle: int = int(snapshot_data.get("idle", 0))
	if idle <= 0:
		return ""
	return "Find the next crew that waits (%d)" % idle


## "Surveying · 2 turns to go" / "Idle — ready for orders".
static func status_text(unit: CivilianState) -> String:
	if unit == null or not unit.is_working():
		return "Idle — ready for orders"
	var left: int = unit.remaining_turns()
	return "%s · %d turn%s to go" % [
		CivilianWork.label(unit.work_action()),
		left,
		MoneyText.plural(left),
	]


## One-line order state for the phone row, where the wide status column folds
## into the posting line.
static func short_status(unit: CivilianState) -> String:
	if unit == null or not unit.is_working():
		return "Idle"
	return "%s · %dt" % [CivilianWork.label(unit.work_action()), unit.remaining_turns()]


static func _row(model: MapModel, unit: CivilianState, region: int) -> Dictionary:
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	var place: String = "Open country"
	if province != NO_PROVINCE:
		place = model.province_name(province)
	var progress: float = 0.0
	if unit.is_working() and unit.total_turns() > 0:
		progress = 1.0 - float(unit.remaining_turns()) / float(unit.total_turns())
	return {
		"unit_id": unit.id,
		"type_id": unit.type_id,
		"role": CivilianCatalog.display_name(unit.type_id),
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"province_id": province,
		"province_name": place,
		"tile": unit.tile,
		"working": unit.is_working(),
		"status": "working" if unit.is_working() else "idle",
		"status_text": status_text(unit),
		"short_status": short_status(unit),
		"progress": clampf(progress, 0.0, 1.0),
		"remaining": unit.remaining_turns(),
	}


static func _empty(
	rows: Array[Dictionary], by_type: Dictionary, by_region: Dictionary
) -> Dictionary:
	return {
		"rows": rows,
		"groups": [],
		"by_type": by_type,
		"by_region": by_region,
		"total": rows.size(),
		"idle": _count_status(rows, false),
		"working": _count_status(rows, true),
	}


static func _count_status(rows: Array[Dictionary], working: bool) -> int:
	var total: int = 0
	for row: Dictionary in rows:
		if bool(row["working"]) == working:
			total += 1
	return total


static func _group(rows: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var key: String = ""
	for row: Dictionary in rows:
		var row_key: String = "%d:%d" % [int(row["region"]), int(row["province_id"])]
		if row_key != key:
			key = row_key
			groups.append({
				"region": int(row["region"]),
				"region_label": String(row["region_label"]),
				"province_id": int(row["province_id"]),
				"province_name": String(row["province_name"]),
				"rows": [],
			})
		(groups.back()["rows"] as Array).append(row)
	return groups


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	var left: String = String(a["province_name"])
	var right: String = String(b["province_name"])
	if left != right:
		return left < right
	if int(a["province_id"]) != int(b["province_id"]):
		return int(a["province_id"]) < int(b["province_id"])
	var left_type: int = CivilianCatalog.ORDER.find(String(a["type_id"]))
	var right_type: int = CivilianCatalog.ORDER.find(String(b["type_id"]))
	if left_type != right_type:
		return left_type < right_type
	return int(a["unit_id"]) < int(b["unit_id"])
