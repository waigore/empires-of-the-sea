class_name LedgerSheet
extends SheetFrame
## The spine a full-screen crown ledger shares: the chart chips, the sheet's own
## reading chips, the scrolling row column and the one repaint a press asks for.
## The provinces, the towns, the muster roll, the navy and the people all read
## that shape, so the stripped body, the count line, the empty notice and the
## clear that keeps it are written once here instead of per sheet
## (REQ-P3-01, REQ-P3-02).
##
## A sheet still owns what is its own: the readings it offers, the rows it mints,
## the words of its count line, the empty line it earns and the door or note it
## adds under the chips. This is the full-screen sheet, not the docked economy
## [LedgerFrame].

## The chart the sheet is narrowed to, one of LedgerRows.REGION_FILTERS.
var _region: String = LedgerRows.REGION_ALL
## The sheet's own reading key: a force's kind, a province's defect, a town's
## step, a hull's role. One name for the axis so a press reads the same on every
## sheet.
var _reading: String = LedgerRows.ALL
var _bar: LedgerFilterBar = null
var _rows: VBoxContainer = null
var _empty: Label = null


# --- subclass hooks ----------------------------------------------------------


## The line under the masthead: what the view leaves of the whole reading. The
## chips, the empty notice and the rows are the spine's; these words are the
## sheet's (REQ-P5-05).
func _subtitle_text(_shown: int) -> String:
	return ""


## The line an emptied view prints: a filter names its way back, a crown with
## nothing yet is told how it earns its first row (REQ-P5-05).
func _empty_text() -> String:
	return "No row answers this view. Clear a filter to see the whole ledger."


## Repaint the view from the last snapshot. A sheet narrows its own reading and
## prints it through `_paint_filtered`; the spine calls this when a chip or the
## layout profile changes.
func _apply_filter() -> void:
	pass


# --- body --------------------------------------------------------------------


## The scrolling row column and the notice that stands in when a view empties.
func _build_rows(column: VBoxContainer) -> void:
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


## The whole filtered body: both chip rows, whatever the sheet adds under them
## (a door to a narrower sheet, a rule printed in place of a hover) and its rows.
## `extra` builds that one Control; the spine mounts it before the rows.
func _build_filter_body(
	column: VBoxContainer,
	chart_caption: String,
	reading_caption: String,
	readings: Array,
	reading_word: Callable,
	extra: Callable = Callable()
) -> void:
	_bar = LedgerFilterBar.new()
	_bar.fill(
		chart_caption, reading_caption, LedgerRows.REGION_FILTERS, readings, reading_word
	)
	_bar.chosen.connect(_on_filter)
	column.add_child(_bar)
	if extra.is_valid():
		var added: Control = extra.call()
		if added != null:
			column.add_child(added)
	_build_rows(column)


# --- filters -----------------------------------------------------------------


## A chip was pressed: the chart axis is the spine's, the reading axis is the
## sheet's own key, and either press repaints from a fresh snapshot.
func _on_filter(key: String, region_row: bool) -> void:
	if region_row:
		_region = key
	else:
		_reading = key
	refresh()


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- rows --------------------------------------------------------------------


## Paints one narrowed view: the chosen chips, the count line, the empty notice
## a view without rows earns, and the grouped rows under their chart headings.
## Either branch clears the last view, so an emptied sheet prints its notice
## alone instead of standing over the rows the last press left (REQ-P5-05).
func _paint_filtered(
	groups: Array[Dictionary], shown: int, heading: Callable, row: Callable
) -> void:
	if _bar != null:
		_bar.render(_region, _reading)
	_subtitle.text = _subtitle_text(shown)
	_empty.visible = shown == 0
	if shown == 0:
		LedgerList.clear(_rows, _empty)
		_empty.text = _empty_text()
		return
	LedgerList.fill(_rows, _empty, groups, heading, row)
