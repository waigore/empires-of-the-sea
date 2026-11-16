class_name TownLedgerPanel
extends RaiseLedgerPanel
## The crown's towns: every province it holds that has a town, the level it
## stands at and the step the Builder would take next, narrowed by chart and by
## what the step waits on, with one press that files the order (wiki:
## extraction-and-improvements § Town manufacturing bonus, civilian-units
## § Builder upgrade_town; DR-20261115-12). The projection lives in [TownLedger]
## and the map hooks in [MapPlayTowns]; this class names the town words and the
## order, and borrows the rest of the sheet from [RaiseLedgerPanel]
## (REQ-P3-02, REQ-P3-03).


func _init() -> void:
	title_text = "THE CROWN'S TOWNS"
	hint_text = (
		"Raise sends the nearest idle Builder; the price and the wait are the "
		+ "work plan's own, so a row never offers an order the rules refuse."
	)
	toggle_action = InputActions.TOWNS_LEDGER


func _read() -> Dictionary:
	return MapPlayTowns.snapshot(play)


func _filters() -> Array:
	return TownLedger.FILTERS


func _reading_word(key: String) -> String:
	return TownLedger.filter_label(key)


func _groups(region_key: String, reading_key: String) -> Array[Dictionary]:
	return TownLedger.groups(_snapshot, region_key, reading_key)


func _count(region_key: String, reading_key: String) -> int:
	return TownLedger.count(_snapshot, region_key, reading_key)


func _row_word(count: int) -> String:
	return "town" if count == 1 else "towns"


## The rule a crown needs before it pays for a level sits on the sheet, not in a
## hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
func _note() -> Control:
	var note := UiRowBuilder.label(TownLedger.bonus_note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


func _empty_text() -> String:
	return "No town answers this view. Clear a filter to see the whole realm."


## The count line names the filter and what the view means, so a crown reads
## what it is looking at before it reads a row (REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = TownLedger.filter_counts(_snapshot, _region)
	return _count_line(shown, "%d ready, %d at work, %d developed." % [
		int(counts.get(TownLedger.FILTER_READY, 0)),
		int(counts.get(TownLedger.FILTER_AT_WORK, 0)),
		int(counts.get(TownLedger.FILTER_DEVELOPED, 0)),
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := TownLedgerRow.new()
	_dress_row(row, compact)
	row.setup(raw as Dictionary)
	return row


func _file_order(region: int, province_id: int, quiet: bool = false) -> Dictionary:
	return MapPlayTowns.raise(play, region, province_id, quiet)
