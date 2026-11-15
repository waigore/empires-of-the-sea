class_name RaiseLedgerPanel
extends LedgerSheet
## The crown's raise sheets — the towns and the walls — share their whole body:
## the sheet binds the session, re-reads both charts, paints the chart and
## reading chips, groups the rows under their headings, prints the count line and
## files the one order a press asks for. A sheet still owns what it reads: its
## projection, the words of its states, the note under the chips and the map hook
## behind Raise (REQ-P3-01, REQ-P3-02).
##
## The sheet chrome, fade and pause-door park come from SheetFrame; the chips,
## rows and empty notice from LedgerSheet; only the raise reading is this
## spine's own.


## Binds the session the sheet reads; every raise sheet takes it the same way.
func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both charts for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = _read()
	_fit()
	_apply_filter()


# --- what a sheet names ------------------------------------------------------


## The projection this sheet prints, read fresh for the player's crown.
func _read() -> Dictionary:
	return {}


## The reading chips this sheet offers, in the order they print.
func _filters() -> Array:
	return []


## One-word name of a reading key.
func _reading_word(key: String) -> String:
	return key


## The rows one chart-and-reading view leaves, grouped under their chart.
func _groups(_region_key: String, _reading_key: String) -> Array[Dictionary]:
	return []


## How many rows that view prints: the count line and a chip's tally read it.
func _count(_region_key: String, _reading_key: String) -> int:
	return 0


## The rule a crown reads before it pays, printed on the sheet rather than in a
## hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
func _note() -> Control:
	return null


## The noun a heading counts, singular or plural: "town", "towns".
func _row_word(_count: int) -> String:
	return "rows"


## The map hook that files this sheet's work order.
func _file_order(_region: int, _province_id: int) -> void:
	pass


## The row widget this sheet mints, dressed and wired by `_dress_row`.
func _make_row(_raw: Variant, _compact: bool) -> Control:
	return null


# --- the shared body ---------------------------------------------------------


## The medallion's own kind of thing: a wall, a crest.
func _crest_icon() -> String:
	return "crest"


func _build_crest() -> Control:
	return Icon.new(_crest_icon(), 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(column, "Chart", "Reading", _filters(), _reading_word, _note)


func _apply_filter() -> void:
	_paint_filtered(
		_groups(_region, _reading), _count(_region, _reading), _heading, _make_row
	)


func _empty_text() -> String:
	return "No row answers this view. Clear a filter to see the whole ledger."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d %s" % [
		String(group["region_label"]).to_upper(), count, _row_word(count)
	])


## The trailing clause a narrowed reading earns on the count line.
func _reading_note() -> String:
	if _reading == LedgerRows.ALL:
		return ""
	return " Reading: %s only." % _reading_word(_reading).to_lower()


## The one row widget every raise sheet mints: dressed for the profile and wired
## to the sheet's own order hook.
func _dress_row(row: RaiseLedgerRow, compact_now: bool) -> RaiseLedgerRow:
	row.compact = compact_now
	row.raise_pressed.connect(_file_order)
	return row
