class_name FleetCrewSection
extends VBoxContainer
## The fleet dossier's passenger block (DR-20261109-17): who is aboard, idle
## civilians to take on, coasts to put them ashore, and the home squadron's
## sortie zones. Emits intents; CivilianVoyage and FleetSortie own the rules.

signal action_pressed(action: String)

var _note: Label = null
var _rows_box: VBoxContainer = null


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var caption := Label.new()
	caption.text = "PASSENGERS"
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


## Empty data hides the block; every row is one tap on a phone.
func set_data(crew: Dictionary) -> void:
	for child: Node in _rows_box.get_children():
		child.queue_free()
	var embark: Array = crew.get("embark", [])
	var land: Array = crew.get("land", [])
	var sortie: Array = crew.get("sortie", [])
	var count: int = int(crew.get("count", 0))
	var has_rows: bool = not embark.is_empty() or not land.is_empty() \
		or not sortie.is_empty()
	visible = count > 0 or has_rows
	_note.text = String(crew.get("note", ""))
	_note.visible = not _note.text.is_empty()
	for raw: Variant in land:
		var row: Dictionary = raw as Dictionary
		_button(
			"Put ashore at %s" % String(row.get("name", "the coast")),
			"crew:land:%d" % int(row.get("province", -1))
		)
	for raw: Variant in embark:
		var row: Dictionary = raw as Dictionary
		_button(
			"Take %s aboard" % String(row.get("name", "a civilian")),
			"crew:embark:%d" % int(row.get("id", -1))
		)
	for raw: Variant in sortie:
		var row: Dictionary = raw as Dictionary
		_button(
			"Put to sea into %s" % String(row.get("name", "the roads")),
			"sortie:%d" % int(row.get("zone", -1))
		)


func _button(text: String, action: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(func() -> void: action_pressed.emit(action))
	_rows_box.add_child(button)
