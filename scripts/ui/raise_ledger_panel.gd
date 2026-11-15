class_name RaiseLedgerPanel
extends LedgerSheet
## The crown's raise sheets — the towns, the walls and the hospitals — share
## their whole body: the sheet binds the session, re-reads both charts, paints the
## chart and reading chips, groups the rows under their headings, prints the count
## line, files the one order a row's press asks for and files every ready step the
## view prints in one confirmed press. A sheet still owns what it reads: its
## projection, the words of its states, the note under the chips and the map hook
## behind Raise (REQ-P3-01, REQ-P3-02, REQ-P5-04).
##
## The sheet chrome, fade and pause-door park come from SheetFrame; the chips,
## rows and empty notice from LedgerSheet; the arm and its count from
## [RaiseBatchPress]; the batch walk from [RaiseLedger]. Only the raise reading is
## this spine's own.

var _batch: RaiseBatchPress = null


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


## The map hook that files this sheet's work order. `quiet` keeps the batch's
## per-order line off the despatch lane, so the receipt is the one the court
## reads (REQ-P5-05, REQ-P5-06).
func _file_order(_region: int, _province_id: int, _quiet: bool = false) -> Dictionary:
	return {"ok": false, "message": ""}


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
	_build_filter_body(column, "Chart", "Reading", _filters(), _reading_word, _extra)


## What the sheet prints under its chips: the rule a crown reads before it pays
## and the one press that files every ready step the view holds (REQ-P5-04).
func _extra() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var note: Control = _note()
	if note != null:
		box.add_child(note)
	_batch = RaiseBatchPress.new()
	_batch.confirmed.connect(_raise_all)
	box.add_child(_batch)
	return box


func _apply_filter() -> void:
	_paint_filtered(
		_groups(_region, _reading), _count(_region, _reading), _heading, _make_row
	)
	_sync_batch()


func _empty_text() -> String:
	return "No row answers this view. Clear a filter to see the whole ledger."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d %s" % [
		String(group["region_label"]).to_upper(), count, _row_word(count)
	])


## The count line every raise sheet opens with: the view against the roll it is
## read from and the chart it is narrowed to, so a crown knows what it is
## looking at before it reads a row (REQ-P5-05). A sheet appends its own tallies
## — what the view holds and what the whole roll comes to — and a narrowed
## reading names itself, so the chips and the line can never disagree.
func _count_line(shown: int, tallies: String) -> String:
	var total: int = int(_snapshot.get("total", 0))
	var line: String = "Showing %d of %d %s %s — %s" % [
		shown, total, _row_word(total), LedgerRows.scope_text(_region), tallies
	]
	if _reading == LedgerRows.ALL:
		return line
	return line + " Reading: %s only." % _reading_word(_reading).to_lower()


## The one row widget every raise sheet mints: dressed for the profile and wired
## to the sheet's own order hook.
func _dress_row(row: RaiseLedgerRow, compact_now: bool) -> RaiseLedgerRow:
	row.compact = compact_now
	row.raise_pressed.connect(_on_raise)
	return row


## One row's press: the sheet files the order and repaints from the new state.
func _on_raise(region: int, province_id: int) -> void:
	_file_order(region, province_id)
	refresh()


# --- the batch press ---------------------------------------------------------


## The ready steps the current view prints, in the order it prints them.
func _ready_targets() -> Array[Dictionary]:
	return RaiseLedger.ready_targets(_snapshot, _region, _reading)


## The press names how many steps it would file, so the count is read before the
## stores are spent (REQ-P5-03, REQ-P5-05).
func _sync_batch() -> void:
	if _batch == null:
		return
	var ready: int = _ready_targets().size()
	_batch.set_ready(ready, _row_word(ready))


## Files every ready step the view prints, in its order, and prints one receipt:
## the orders' own words are held back, so the court reads the press and not a
## lane of thirty lines (REQ-P5-05, REQ-P5-06; DR-20261116-03).
func _raise_all() -> void:
	var targets: Array[Dictionary] = _ready_targets()
	var receipt: Dictionary = RaiseLedger.file_batch(targets, _file_quiet)
	refresh()
	if play != null and play.hud != null:
		play.hud.toast(RaiseLedger.batch_receipt(receipt, _row_word(int(receipt["total"]))))


## The batch's own order hook: the sheet's hook with its line held back.
func _file_quiet(region: int, province_id: int) -> Dictionary:
	return _file_order(region, province_id, true)
