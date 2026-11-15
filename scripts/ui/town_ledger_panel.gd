class_name TownLedgerPanel
extends SheetFrame
## The crown's towns: every province it holds that has a town, the level it
## stands at and the step the Builder would take next, narrowed by chart and by
## what the step waits on, with one press that files the order (wiki:
## extraction-and-improvements § Town manufacturing bonus, civilian-units
## § Builder upgrade_town; DR-20261115-12). The projection lives in
## [TownLedger] and the map hooks in [MapPlayTowns]; this class only renders
## rows and asks for the order (REQ-P3-02, REQ-P3-03). The sheet chrome, fade
## and pause-door park come from SheetFrame.

var _rows: VBoxContainer = null
var _empty: Label = null
var _bar: LedgerFilterBar = null
var _region: String = LedgerRows.REGION_ALL
var _filter: String = TownLedger.FILTER_ALL
var _snapshot: Dictionary = {}


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
	_bar = LedgerFilterBar.new()
	_bar.fill(
		"Chart", "Reading", LedgerRows.REGION_FILTERS, TownLedger.FILTERS,
		TownLedger.filter_label
	)
	_bar.chosen.connect(_on_filter)
	column.add_child(_bar)
	# The rule a crown needs before it pays for a level sits on the sheet, not
	# in a hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
	var note := UiRowBuilder.label(TownLedger.bonus_note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- filters -----------------------------------------------------------------


func _on_filter(key: String, region_row: bool) -> void:
	if region_row:
		_region = key
	else:
		_filter = key
	refresh()


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	_bar.render(_region, _filter)
	var groups: Array[Dictionary] = TownLedger.groups(_snapshot, _region, _filter)
	var shown: int = TownLedger.count(_snapshot, _region, _filter)
	_subtitle.text = _subtitle_text(shown)
	_empty.visible = shown == 0
	if shown == 0:
		_empty.text = "No town answers this view. Clear a filter to see the whole realm."
		return
	LedgerList.fill(_rows, _empty, groups, _heading, _make_row)


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
	var scope: String = "in both charts"
	if _region == LedgerRows.REGION_OLD:
		scope = "in the Old World"
	elif _region == LedgerRows.REGION_NEW:
		scope = "in the New World"
	var counts: Dictionary = TownLedger.filter_counts(_snapshot, _region)
	var line: String = "Showing %d of %d towns %s — %d ready, %d at work, %d developed." % [
		shown,
		int(_snapshot.get("total", 0)),
		scope,
		int(counts.get(TownLedger.FILTER_READY, 0)),
		int(counts.get(TownLedger.FILTER_AT_WORK, 0)),
		int(counts.get(TownLedger.FILTER_DEVELOPED, 0)),
	]
	if _filter != TownLedger.FILTER_ALL:
		line += " Reading: %s only." % TownLedger.filter_label(_filter).to_lower()
	return line


func _raise(region: int, province_id: int) -> void:
	if play == null:
		return
	MapPlayTowns.raise(play, region, province_id)
	refresh()
