class_name TownLedgerPanel
extends LedgerSheet
## The crown's towns: every province it holds that has a town, the level it
## stands at and the step the Builder would take next, narrowed by chart and by
## what the step waits on, with one press that files the order (wiki:
## extraction-and-improvements § Town manufacturing bonus, civilian-units
## § Builder upgrade_town; DR-20261115-12). The projection lives in
## [TownLedger] and the map hooks in [MapPlayTowns]; this class only renders
## rows and asks for the order (REQ-P3-02, REQ-P3-03). The sheet chrome, fade
## and pause-door park come from SheetFrame; the chips, rows and empty notice
## from LedgerSheet.



func _init() -> void:
	title_text = "THE CROWN'S TOWNS"
	hint_text = (
		"Raise sends the nearest idle Builder; the price and the wait are the "
		+ "work plan's own, so a row never offers an order the rules refuse."
	)
	toggle_action = InputActions.TOWNS_LEDGER


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both charts for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = MapPlayTowns.snapshot(play)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("crest", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Chart", "Reading", TownLedger.FILTERS, TownLedger.filter_label, _bonus_note
	)


## The rule a crown needs before it pays for a level sits on the sheet, not in a
## hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
func _bonus_note() -> Control:
	var note := UiRowBuilder.label(TownLedger.bonus_note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = TownLedger.groups(_snapshot, _region, _reading)
	var shown: int = TownLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


func _empty_text() -> String:
	return "No town answers this view. Clear a filter to see the whole realm."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d town%s" % [
		String(group["region_label"]).to_upper(), count, "" if count == 1 else "s"
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := TownLedgerRow.new()
	row.compact = compact
	row.raise_pressed.connect(_raise)
	row.setup(raw as Dictionary)
	return row


## The count line names the filter and what the view means, so a crown reads
## what it is looking at before it reads a row (REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = TownLedger.filter_counts(_snapshot, _region)
	var line: String = "Showing %d of %d towns %s — %d ready, %d at work, %d developed." % [
		shown,
		int(_snapshot.get("total", 0)),
		LedgerRows.scope_text(_region),
		int(counts.get(TownLedger.FILTER_READY, 0)),
		int(counts.get(TownLedger.FILTER_AT_WORK, 0)),
		int(counts.get(TownLedger.FILTER_DEVELOPED, 0)),
	]
	if _reading != TownLedger.FILTER_ALL:
		line += " Reading: %s only." % TownLedger.filter_label(_reading).to_lower()
	return line


func _raise(region: int, province_id: int) -> void:
	if play == null:
		return
	MapPlayTowns.raise(play, region, province_id)
	refresh()
