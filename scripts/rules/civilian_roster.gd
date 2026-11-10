class_name CivilianRoster
extends RefCounted
## View-model for the crown's civilian roster: every unit in every region, with
## the province it stands in and its current order. Pure data, so the panel and
## the tests read the same rows (REQ-P3-02, REQ-P3-03).
##
## The roster is a read-only projection of MapRegionTable + MapModel; it never
## moves, assigns or advances a unit. Rows carry the unit id and region, which is
## all the screen needs to jump to the unit on its own map.

const REGION_ALL: String = "all"
const REGION_OLD: String = "old_world"
const REGION_NEW: String = "new_world"
const REGION_FILTERS: Array[String] = [REGION_ALL, REGION_OLD, REGION_NEW]

const NO_PROVINCE: int = -1


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


## Rows narrowed to one region key and one type (empty type keeps every type).
static func groups(
	snapshot_data: Dictionary, region_key: String, type_id: String = ""
) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for raw: Variant in snapshot_data.get("groups", []):
		var group: Dictionary = raw
		if not region_matches(int(group.get("region", -1)), region_key):
			continue
		var rows: Array[Dictionary] = []
		for entry: Variant in group.get("rows", []):
			var row: Dictionary = entry
			if not type_id.is_empty() and String(row["type_id"]) != type_id:
				continue
			rows.append(row)
		if rows.is_empty():
			continue
		var narrowed: Dictionary = group.duplicate()
		narrowed["rows"] = rows
		kept.append(narrowed)
	return kept


static func count(snapshot_data: Dictionary, region_key: String, type_id: String = "") -> int:
	var total: int = 0
	for group: Dictionary in groups(snapshot_data, region_key, type_id):
		total += (group["rows"] as Array).size()
	return total


## Type totals inside one region filter, for the icon chips (all six types stay
## listed so a zero is legible rather than a vanished button).
static func type_counts(snapshot_data: Dictionary, region_key: String) -> Dictionary:
	var counts: Dictionary = {}
	for type_id: String in CivilianCatalog.ORDER:
		counts[type_id] = 0
	for raw: Variant in snapshot_data.get("rows", []):
		var row: Dictionary = raw
		if not region_matches(int(row["region"]), region_key):
			continue
		var type_id: String = String(row["type_id"])
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	return counts


static func region_matches(region: int, key: String) -> bool:
	match key:
		REGION_OLD:
			return region == FactionCatalog.OLD_WORLD
		REGION_NEW:
			return region == FactionCatalog.NEW_WORLD
	return true


## "Surveying · 2 turns to go" / "Idle — ready for orders".
static func status_text(unit: CivilianState) -> String:
	if unit == null or not unit.is_working():
		return "Idle — ready for orders"
	var left: int = unit.remaining_turns()
	return "%s · %d turn%s to go" % [
		CivilianWork.label(unit.work_action()),
		left,
		"" if left == 1 else "s",
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
