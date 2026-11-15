class_name WallLedgerRow
extends PanelContainer
## One wall in the crown's ledger: its level medallion, the province it stands
## in, the wall that meets an attack today, what the next step costs and waits
## on, and the press that files the Engineer's order. Presentation only — every
## figure arrives in the row dictionary and the press is an intent
## (REQ-P3-02, REQ-P5-04).

signal raise_pressed(region: int, province_id: int)

var data: Dictionary = {}
var compact: bool = false

var _medallion: Label = null
var _name: Label = null
var _chip: Label = null
var _place: Label = null
var _note: Label = null
var _raise: Button = null


func setup(row: Dictionary) -> void:
	data = row
	_build()
	_fill()


func _build() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.13, 0.11, 0.08, 0.88),
			Color(0.54, 0.43, 0.12, 0.55),
			1,
			3,
			Vector4(8, 5, 8, 5) if compact else Vector4(10, 7, 10, 7)
		)
	)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10 if compact else 12)
	add_child(line)

	_medallion = Label.new()
	_medallion.custom_minimum_size = Vector2(38 if compact else 44, 38 if compact else 44)
	_medallion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_medallion.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_medallion.add_theme_font_override("font", UiTheme.serif())
	_medallion.add_theme_font_size_override("font_size", 15 if compact else 17)
	_medallion.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_medallion)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	info.add_child(heading)

	_name = Label.new()
	_name.add_theme_font_override("font", UiTheme.serif())
	_name.add_theme_font_size_override("font_size", 17 if compact else 19)
	_name.add_theme_color_override("font_color", Palette.GOLD_PALE)
	heading.add_child(_name)

	_chip = Label.new()
	_chip.add_theme_font_size_override("font_size", 9)
	_chip.add_theme_color_override("font_color", Palette.INK)
	heading.add_child(_chip)

	_place = Label.new()
	_place.add_theme_font_size_override("font_size", 11)
	_place.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
	_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_place)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 12)
	_note.add_theme_color_override("font_color", Palette.TEXT)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_note)

	_raise = Button.new()
	_raise.text = "Raise"
	_raise.custom_minimum_size = Vector2(72 if compact else 78, 42 if compact else 36)
	_raise.add_theme_font_size_override("font_size", 13)
	_raise.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_raise.pressed.connect(_raise_wall)
	line.add_child(_raise)


func _fill() -> void:
	_medallion.text = String(data.get("level_text", "—"))
	_medallion.add_theme_stylebox_override(
		"normal",
		UiTheme.box(
			Color(0.20, 0.16, 0.10, 0.95), Palette.GOLD_DIM, 1, 3, Vector4(2, 2, 2, 2)
		)
	)
	_name.text = String(data.get("name", "Province"))
	var chip: Dictionary = _chip_reading()
	_chip.text = String(chip["text"])
	var chip_color: Color = chip["color"]
	_chip.add_theme_stylebox_override(
		"normal", UiTheme.box(chip_color, chip_color, 0, 2, Vector4(6, 1, 6, 1))
	)
	_place.text = "%s  ·  %s" % [
		String(data.get("line", "No fort")),
		String(data.get("region_label", "Uncharted")),
	]
	_note.text = String(data.get("note", ""))
	var ready: bool = String(data.get("state", "")) == WallLedger.STATE_READY
	_raise.visible = ready
	_raise.tooltip_text = "Send the nearest idle Engineer to wall %s" % _name.text


## The one word the row carries, so a crown reads what a wall waits on before it
## reads the price (REQ-P5-03).
func _chip_reading() -> Dictionary:
	match String(data.get("state", "")):
		WallLedger.STATE_AT_WORK:
			return {"text": "AT WORK", "color": Palette.SURVEY_BUILDING}
		WallLedger.STATE_NO_ENGINEER:
			return {"text": "NO ENGINEER", "color": Palette.SURVEY_VACANT}
		WallLedger.STATE_LOCKED:
			return {"text": "LOCKED", "color": Palette.SURVEY_OFFLINE}
		WallLedger.STATE_RAISED:
			return {"text": "WALLED", "color": Palette.GOLD_DIM}
	return {"text": "READY", "color": Palette.SURVEY_YIELDING}


func _raise_wall() -> void:
	raise_pressed.emit(int(data.get("region", 0)), int(data.get("id", -1)))
