class_name KeysSheet
extends RefCounted
## The pause page's KEYS reading: every control the chart answers to, the key
## that sends it, and the door a touch player presses instead (`KeyReference`;
## docs/ui-demo.md § Controls). One page, four groups, no hover — a phone reads
## the same words a desktop key list prints (REQ-P1-07, REQ-P5-03, REQ-P5-07).
##
## Pure furniture: the rows come from `KeyReference`, so a rebound key moves the
## page and never a second table, and nothing here reads or changes game state
## (REQ-P2-03, REQ-P3-03).

const CHIP_WIDTH: float = 74.0
const CHIP_WIDTH_SHORT: float = 64.0
## The note under the title: the keys answer the chart, not the pause page the
## court is reading them on.
const NOTE: String = "Keys answer while the chart is open; close this page first."


## Fills `page` with the whole reading: title, note, four groups, then the way
## back to the pause page. `short` keeps the rows thumb-sized on a phone.
static func build(page: VBoxContainer, short: bool, back: Callable) -> void:
	page.add_child(MenuFrame.title("KEYS", 24 if short else 28))
	page.add_child(MenuFrame.subtitle(NOTE))
	for raw: Variant in KeyReference.groups():
		var group: Dictionary = raw
		page.add_child(MenuFrame.separator())
		page.add_child(MenuFrame.caption(String(group.get("title", ""))))
		for raw_row: Variant in group.get("rows", []):
			page.add_child(_row(raw_row as Dictionary, short))
	if back.is_valid():
		var leave: Button = MenuFrame.action_button(
			"BACK", MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
		)
		leave.name = "KeysBack"
		leave.pressed.connect(back)
		page.add_child(leave)


## One control: the words the court knows it by and the door that does the same
## thing on the left, the key that sends it on the right.
static func _row(row: Dictionary, short: bool) -> Control:
	var line := HBoxContainer.new()
	line.name = "KeyRow"
	line.add_theme_constant_override("separation", 8)
	line.add_child(_words(row))
	line.add_child(_chip(String(row.get("keys", KeyReference.NO_KEY)), short))
	return line


## The row's name, then its touch door in the same line: a phone reads the door
## where a desktop reads the key (`REQ-P5-07`).
static func _words(row: Dictionary) -> Control:
	var label := Label.new()
	var door: String = String(row.get("door", ""))
	label.text = String(row.get("label", ""))
	if not door.is_empty():
		label.text += "  ·  " + door
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.75))
	label.add_theme_constant_override("outline_size", 3)
	return label


## The key cap: a small brass-ruled plate, so a key reads as a press and not as
## a word in the sentence beside it (`REQ-P1-02`).
static func _chip(keys: String, short: bool) -> Control:
	var plate := PanelContainer.new()
	plate.name = "KeyChip"
	plate.custom_minimum_size = Vector2(CHIP_WIDTH_SHORT if short else CHIP_WIDTH, 0.0)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override(
		"panel", UiTheme.box(Color(0, 0, 0, 0.28), Palette.GOLD_DIM, 1, 3, Vector4(6, 2, 6, 2))
	)
	var label := Label.new()
	label.text = keys
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	plate.add_child(label)
	return plate
