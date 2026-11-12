class_name FleetDossierSection
extends VBoxContainer
## Shared scaffold for the fleet dossier's blocks: a small caption, a note line
## that hides when empty, and a row box the block appends its buttons to
## (wiki: ships-and-naval § Missions and Movement). Subclasses hand over plain
## data, never rules (REQ-P3-02), and emit `action_pressed` intents.

signal action_pressed(action: String)

var _note: Label = null
var _rows_box: VBoxContainer = null


func _setup(caption: String) -> void:
	add_theme_constant_override("separation", 4)
	var title := UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.9))
	title.text = caption
	add_child(title)
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


## One tap-sized row: every row is a phone tap, so they share one shape.
func _add_row(text: String, action: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(func() -> void: action_pressed.emit(action))
	_rows_box.add_child(button)
