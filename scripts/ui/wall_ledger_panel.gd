class_name WallLedgerPanel
extends LedgerSheet
## The crown's walls: every province it holds that can carry a fort, the level
## it stands at and the step the Engineer would take next, narrowed by chart and
## by what the step waits on, with one press that files the order (wiki:
## siege-mechanics § Fort Levels, § Wall Protection; DR-20261116-01). The
## projection lives in [WallLedger] and the map hooks in [MapPlayWalls]; this
## class only renders rows and asks for the order (REQ-P3-02, REQ-P3-03). The
## sheet chrome, fade and pause-door park come from SheetFrame; the chips, rows
## and empty notice from LedgerSheet.


func _init() -> void:
	title_text = "THE CROWN'S WALLS"
	hint_text = (
		"Raise sends the nearest idle Engineer; the price, the wait and the "
		+ "study are the fort table's own, so a row never offers a wall the "
		+ "order would refuse."
	)
	toggle_action = InputActions.WALLS_LEDGER


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both charts for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = MapPlayWalls.snapshot(play)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("wall", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Chart", "Reading", WallLedger.FILTERS, WallLedger.filter_label, _rule_note
	)


## The rule a crown needs before it pays for a wall sits on the sheet, not in a
## hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
func _rule_note() -> Control:
	var note := UiRowBuilder.label(WallLedger.rule_note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = WallLedger.groups(_snapshot, _region, _reading)
	var shown: int = WallLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


func _empty_text() -> String:
	return "No wall answers this view. Clear a filter to see the whole coast."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d wall%s" % [
		String(group["region_label"]).to_upper(), count, "" if count == 1 else "s"
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := WallLedgerRow.new()
	row.compact = compact
	row.raise_pressed.connect(_raise)
	row.setup(raw as Dictionary)
	return row


## The count line names the filter and what the view means — and where nothing
## stands, because a crown walls its bare shores before its citadels
## (REQ-P5-03, REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = WallLedger.filter_counts(_snapshot, _region)
	var reading: Dictionary = WallLedger.summary(_snapshot, _region)
	var line: String = (
		"Showing %d of %d walls %s — %d bare, %d ready, %d at work, %d walled."
		% [
			shown,
			int(_snapshot.get("total", 0)),
			LedgerRows.scope_text(_region),
			int(reading["bare"]),
			int(counts.get(WallLedger.FILTER_READY, 0)),
			int(counts.get(WallLedger.FILTER_AT_WORK, 0)),
			int(reading["walled"]) + int(reading["citadel"]),
		]
	)
	if _reading != WallLedger.FILTER_ALL:
		line += " Reading: %s only." % WallLedger.filter_label(_reading).to_lower()
	return line


func _raise(region: int, province_id: int) -> void:
	if play == null:
		return
	MapPlayWalls.raise(play, region, province_id)
	refresh()
