class_name FleetMissionSection
extends VBoxContainer
## The fleet dossier's mission block: the current station note and one button
## per station or hostile coast the squadron could take (wiki: ships-and-naval
## § Missions and Movement). Emits intents; the rules modules own validation.


signal action_pressed(action: String)

var _note: Label = null
var _rows_box: VBoxContainer = null


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var caption := Label.new()
	caption.text = "MISSIONS"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.9))
	add_child(caption)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 12)
	_note.add_theme_color_override("font_color", Color(0.90, 0.82, 0.62))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	add_child(_rows_box)


## Empty data hides the block: a fresh squadron has no landing duty yet.
func set_data(note: String, rows: Array[Dictionary]) -> void:
	visible = not note.is_empty() or not rows.is_empty()
	for child: Node in _rows_box.get_children():
		child.queue_free()
	_note.text = note
	_note.visible = not note.is_empty()
	for row: Dictionary in rows:
		var button := Button.new()
		button.text = String(row.get(
			"label", "Mark %s" % String(row.get("name", "the coast"))
		))
		button.custom_minimum_size = Vector2(0, 36)
		button.add_theme_font_size_override("font_size", 13)
		var province: int = int(row.get("province", -1))
		var action: String = String(
			row.get("action", "beachhead:%d" % province)
		)
		button.pressed.connect(
			func() -> void: action_pressed.emit(action)
		)
		_rows_box.add_child(button)