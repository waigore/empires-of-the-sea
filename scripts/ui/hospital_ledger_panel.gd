class_name HospitalLedgerPanel
extends RaiseLedgerPanel
## The crown's hospitals: every province it holds that can carry a ward, the
## level it stands at, whether its staff ate and the step the Engineer would
## take next, narrowed by chart and by what the step waits on, with one press
## that files the order and one confirmed press that files every ready ward the
## view prints (wiki: combat § Regiment condition; DR-20261116-02,
## DR-20261116-03). The projection lives in [HospitalLedger] and the map hooks
## in [MapPlayHospitals]; this class names the ward words and the order, and
## borrows the rest of the sheet from [RaiseLedgerPanel] (REQ-P3-02, REQ-P3-03).


func _init() -> void:
	title_text = "THE CROWN'S HOSPITALS"
	hint_text = (
		"Raise sends the nearest idle Engineer; the price, the wait and the "
		+ "study are the ward table's own, so a row never offers a ward the "
		+ "order would refuse."
	)


func _read() -> Dictionary:
	return MapPlayHospitals.snapshot(play)


func _filters() -> Array:
	return HospitalLedger.FILTERS


func _reading_word(key: String) -> String:
	return HospitalLedger.filter_label(key)


func _groups(region_key: String, reading_key: String) -> Array[Dictionary]:
	return HospitalLedger.groups(_snapshot, region_key, reading_key)


func _count(region_key: String, reading_key: String) -> int:
	return HospitalLedger.count(_snapshot, region_key, reading_key)


func _crest_icon() -> String:
	return "hospital"


func _row_word(count: int) -> String:
	return "ward" if count == 1 else "wards"


## The rule a crown needs before it pays for a step sits on the sheet, not in a
## hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
func _note() -> Control:
	var note := UiRowBuilder.label(HospitalLedger.rule_note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


func _empty_text() -> String:
	return "No ward answers this view. Clear a filter to see the whole realm."


## The count line names the filter and what the view means — and what the whole
## staff eats, because a ward's ration is part of its price (REQ-P5-03,
## REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = HospitalLedger.filter_counts(_snapshot, _region)
	var reading: Dictionary = HospitalLedger.summary(_snapshot, _region)
	var line: String = (
		"Showing %d of %d wards %s — %d bare, %d ready, %d at work, %d standing."
		% [
			shown,
			int(_snapshot.get("total", 0)),
			LedgerRows.scope_text(_region),
			int(reading["bare"]),
			int(counts.get(HospitalLedger.FILTER_READY, 0)),
			int(counts.get(HospitalLedger.FILTER_AT_WORK, 0)),
			int(reading["standing"]),
		]
	)
	line += " Staffs eat %d food a turn." % int(reading["ration"])
	var unfed: int = int(reading["unfed"])
	if unfed > 0:
		line += " %d went unfed this turn." % unfed
	return line + _reading_note()


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := HospitalLedgerRow.new()
	_dress_row(row, compact)
	row.setup(raw as Dictionary)
	return row


func _file_order(region: int, province_id: int, quiet: bool = false) -> Dictionary:
	return MapPlayHospitals.raise(play, region, province_id, quiet)
