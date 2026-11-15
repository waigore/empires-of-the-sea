class_name WallLedgerPanel
extends RaiseLedgerPanel
## The crown's walls: every province it holds that can carry a fort, the level it
## stands at and the step the Engineer would take next, narrowed by chart and by
## what the step waits on, with one press that files the order (wiki:
## siege-mechanics § Fort Levels, § Wall Protection; DR-20261116-01). The
## projection lives in [WallLedger] and the map hooks in [MapPlayWalls]; this
## class names the wall words and the order, and borrows the rest of the sheet
## from [RaiseLedgerPanel] (REQ-P3-02, REQ-P3-03).


func _init() -> void:
	title_text = "THE CROWN'S WALLS"
	hint_text = (
		"Raise sends the nearest idle Engineer; the price, the wait and the "
		+ "study are the fort table's own, so a row never offers a wall the "
		+ "order would refuse."
	)
	toggle_action = InputActions.WALLS_LEDGER


func _read() -> Dictionary:
	return MapPlayWalls.snapshot(play)


func _filters() -> Array:
	return WallLedger.FILTERS


func _reading_word(key: String) -> String:
	return WallLedger.filter_label(key)


func _groups(region_key: String, reading_key: String) -> Array[Dictionary]:
	return WallLedger.groups(_snapshot, region_key, reading_key)


func _count(region_key: String, reading_key: String) -> int:
	return WallLedger.count(_snapshot, region_key, reading_key)


func _crest_icon() -> String:
	return "wall"


func _row_word(count: int) -> String:
	return "wall" if count == 1 else "walls"


## The rule a crown needs before it pays for a wall sits on the sheet, not in a
## hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
func _note() -> Control:
	var note := UiRowBuilder.label(WallLedger.rule_note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


func _empty_text() -> String:
	return "No wall answers this view. Clear a filter to see the whole coast."


## The count line names the filter and what the view means — and where nothing
## stands, because a crown walls its bare shores before its citadels
## (REQ-P5-03, REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = WallLedger.filter_counts(_snapshot, _region)
	var reading: Dictionary = WallLedger.summary(_snapshot, _region)
	return _count_line(shown, "%d bare, %d ready, %d at work, %d walled." % [
		int(reading["bare"]),
		int(counts.get(WallLedger.FILTER_READY, 0)),
		int(counts.get(WallLedger.FILTER_AT_WORK, 0)),
		int(reading["walled"]) + int(reading["citadel"]),
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := WallLedgerRow.new()
	_dress_row(row, compact)
	row.setup(raw as Dictionary)
	return row


func _file_order(region: int, province_id: int, quiet: bool = false) -> Dictionary:
	return MapPlayWalls.raise(play, region, province_id, quiet)
