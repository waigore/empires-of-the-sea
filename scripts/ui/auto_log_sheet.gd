class_name AutoLogSheet
extends SheetFrame
## The Auto seat's whole action log (wiki: auto-mode § Pacing): every line the
## session still keeps, oldest first, so a busy turn's first orders are read
## after the plate under the cartouche has moved on to the newest. Presentation
## only — MapPlayAuto writes the lines and the seat decides nothing here
## (REQ-P3-02, REQ-P5-05). The sheet chrome, fade and pause-door park come from
## SheetFrame.

## A turn's opening line ("Turn 12 — the AI holds the crown's seat.") heads the
## orders that follow it, so the log reads turn by turn.
const TURN_PREFIX: String = "Turn "

var _rows: VBoxContainer = null
var _empty: Label = null
var _note: Label = null


func _init() -> void:
	title_text = "THE CROWN'S ACTION LOG"
	hint_text = (
		"Every order the seat resolved, oldest first. The seat holds the clock "
		+ "while this sheet is open, and resumes at its pace when it closes."
	)


## Re-reads the session's log and repaints the sheet.
func refresh() -> void:
	if play == null:
		return
	_fit()
	_paint()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("scroll", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_note = UiRowBuilder.label("", 12, Palette.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


## A seat that has raised no order has nothing to read; the plate is hidden
## then too, so the seal that opens this sheet is not offered.
func _can_open() -> bool:
	return play != null and not play.auto_log.is_empty()


func _on_profile_changed() -> void:
	if visible:
		_paint()


# --- rows --------------------------------------------------------------------


func _paint() -> void:
	LedgerList.clear(_rows, _empty)
	var lines: PackedStringArray = play.auto_log
	_empty.visible = lines.is_empty()
	if lines.is_empty():
		_empty.text = "The seat has raised no order yet."
		_note.text = ""
		return
	_note.text = "%d line%s kept, oldest first." % [lines.size(), MoneyText.plural(lines.size())]
	for raw: String in lines:
		_rows.add_child(_line(raw))


## A turn's opening line is a heading; every order under it is a row of its own.
func _line(text: String) -> Label:
	if text.begins_with(TURN_PREFIX):
		var head := UiRowBuilder.serif_line(text, 15, Palette.GOLD_PALE)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return head
	var row := UiRowBuilder.wrapped_line("·  %s" % text, 13, Palette.TEXT)
	return row
