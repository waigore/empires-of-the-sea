class_name EstateLedger
extends RefCounted
## View-model for the crown's estates ledger: groups the raw
## ImprovementLedger snapshot by province and answers the filter questions.
## Pure data (no visual nodes), so ImprovementPanel only builds rows from it
## (REQ-P3-02, REQ-P3-03).

const NO_PROVINCE: int = -1


## Snapshot rows grouped under their province, in map order:
## [{id, name, rows, producing}, …].
static func grouped(snapshot: Dictionary) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var index_by_id: Dictionary = {}
	for raw: Variant in snapshot.get("groups", []):
		var group: Dictionary = raw
		var id: int = int(group.get("id", NO_PROVINCE))
		if index_by_id.has(id):
			var merged: Dictionary = groups[int(index_by_id[id])]
			var extra: Array = group.get("rows", [])
			(merged["rows"] as Array).append_array(extra)
			continue
		var entry: Dictionary = {
			"id": id,
			"name": String(group.get("name", "")),
			"rows": Array(group.get("rows", [])).duplicate(),
			"producing": int(group.get("producing", 0)),
		}
		index_by_id[id] = groups.size()
		groups.append(entry)
	return groups


## Groups narrowed to one province (NO_PROVINCE keeps every group).
static func in_province(groups: Array[Dictionary], province_id: int) -> Array[Dictionary]:
	if province_id < 0:
		return groups
	var kept: Array[Dictionary] = []
	for group: Dictionary in groups:
		if int(group["id"]) == province_id:
			kept.append(group)
	return kept


## Rows of one group matching the filter key ("all" keeps every row).
static func matching(row_list: Array, filter_key: String) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for raw: Variant in row_list:
		var row: Dictionary = raw
		if _matches(row, filter_key):
			kept.append(row)
	return kept


static func _matches(row: Dictionary, filter_key: String) -> bool:
	match filter_key:
		"producing":
			return int(row.get("output", 0)) > 0
		"building":
			return bool(row.get("working", false))
		"vacant":
			return String(row.get("status", "")) == "vacant"
		"issues":
			return String(row.get("status", "")) in ["disconnected", "unprospected"]
	return true


## Sum of every projected yield in a totals table.
static func total_output(totals: Dictionary) -> int:
	var total: int = 0
	for raw: Variant in totals.keys():
		total += int(totals[raw])
	return total
