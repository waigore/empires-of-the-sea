class_name FleetDossierSection
extends VBoxContainer
## Shared scaffold for the fleet dossier's blocks: a small caption, a note line
## that hides when empty, and a row box the block appends its buttons to
## (wiki: ships-and-naval § Missions and Movement). Subclasses hand over plain
## data, never rules (REQ-P3-02), and emit `action_pressed` intents.

signal action_pressed(action: String)

## The mark a row wears when the court's own reading names it (DR-20261122-20).
const COURT_MARK: String = "▸"

var _note: Label = null
var _rows_box: VBoxContainer = null
var _title: Label = null
var _caption: String = ""


func _setup(caption: String) -> void:
	add_theme_constant_override("separation", 4)
	_caption = caption
	var title := UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.9))
	title.text = caption
	add_child(title)
	_title = title
	_note = UiRowBuilder.line(12, Color(0.90, 0.82, 0.62))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	add_child(_rows_box)


## Clears the previous rows and shows the note when it has anything to say.
func _begin(note: String) -> void:
	UiRowBuilder.clear(_rows_box)
	_note.text = note
	_note.visible = not note.is_empty()


## The block's own caption with the counsel's legend on it (`MISSIONS · ▸ court`)
## while a row wears the mark, and the plain caption when none does
## (DR-20261122-20).
func _set_caption_legend(marked: bool) -> void:
	if _title == null:
		return
	_title.text = "%s · %s court" % [_caption, COURT_MARK] if marked else _caption


## One tap-sized row: every row is a phone tap, so they share one shape. A marked
## row leads with the counsel's glyph — the court's own reading named it
## (DR-20261122-20).
func _add_row(text: String, action: String, marked: bool = false) -> void:
	_rows_box.add_child(
		make_press(text, func() -> void: action_pressed.emit(action), marked)
	)


## A row that runs a local press instead of emitting an intent (opening a coast's
## grounds, and the way back out of them).
func _add_row_press(text: String, run: Callable, marked: bool = false) -> Button:
	var button: Button = make_press(text, run, marked)
	_rows_box.add_child(button)
	return button


## One marked press, the shape every dossier row keeps: a marked row leads with
## the counsel's glyph and every row is a phone tap (DR-20261122-20). The open
## coast's window builds its rows with it, so a row reads the same on the sheet
## and inside the scroll.
static func make_press(text: String, run: Callable, marked: bool = false) -> Button:
	var button := Button.new()
	button.text = ("%s %s" % [COURT_MARK, text]) if marked else text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(run)
	return button
