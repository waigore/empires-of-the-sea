class_name SaveBrowser
extends Control
## Local slot picker shared by the title screen and the in-game pause menu.
## Load only offers readable saves; save asks twice before overwriting a slot.

signal slot_chosen(slot: int)
signal back_pressed

enum Mode { LOAD, SAVE }

var slot_buttons: Array[Button] = []
var back_button: Button = null

var _mode: int = Mode.LOAD
var _dir: String = SaveStore.DIR
var _slots_box: VBoxContainer = null
var _title: Label = null
var _status: Label = null
var _pending_overwrite: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	MenuFrame.backdrop(self)
	_build()
	refresh()


## Call after adding the page so the rows reflect the caller's directory.
func setup(mode: int, dir: String = SaveStore.DIR) -> void:
	_mode = Mode.SAVE if mode == Mode.SAVE else Mode.LOAD
	_dir = dir
	_pending_overwrite = -1
	refresh()


func mode() -> int:
	return _mode


func _build() -> void:
	var box: VBoxContainer = MenuFrame.column(self, 640.0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(MenuFrame.crest(52))
	_title = MenuFrame.title("LOAD GAME", 32)
	box.add_child(_title)
	box.add_child(MenuFrame.subtitle("Saves are kept on this device only."))
	box.add_child(MenuFrame.separator())

	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 8)
	box.add_child(_slots_box)

	_status = MenuFrame.subtitle("")
	_status.add_theme_color_override("font_color", Palette.GOLD_PALE)
	box.add_child(_status)

	back_button = MenuFrame.small_button("BACK", 160.0)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	box.add_child(back_button)


## Rebuilds every row from disk; safe to call whenever the page reappears.
func refresh() -> void:
	if _slots_box == null or _title == null:
		return
	_title.text = "SAVE GAME" if _mode == Mode.SAVE else "LOAD GAME"
	_status.text = ""
	for child: Node in _slots_box.get_children():
		_slots_box.remove_child(child)
		child.queue_free()
	slot_buttons.clear()
	for row: Dictionary in SaveStore.slots(_dir):
		var slot: int = int(row["slot"])
		var exists: bool = bool(row["exists"])
		var button := MenuFrame.action_button(_row_text(slot, row, exists), 68.0)
		button.add_theme_font_size_override("font_size", 15)
		button.disabled = (not exists) and _mode == Mode.LOAD
		if slot == _pending_overwrite:
			button.modulate = Color(1.0, 0.82, 0.62)
		button.pressed.connect(_on_slot_pressed.bind(slot, exists))
		_slots_box.add_child(button)
		slot_buttons.append(button)


func _row_text(slot: int, row: Dictionary, exists: bool) -> String:
	if not exists:
		return "SLOT %d   ·   Empty" % slot
	var where: String = String(row.get("region", "—"))
	var stamp: String = String(row.get("saved_at", ""))
	return "SLOT %d   ·   %s  —  Turn %d\n%s  ·  seed %d  ·  %s" % [
		slot,
		String(row.get("nation", "—")),
		int(row.get("turn", 1)),
		where,
		int(row.get("seed", 0)),
		stamp,
	]


func _on_slot_pressed(slot: int, exists: bool) -> void:
	if _mode == Mode.SAVE and exists and _pending_overwrite != slot:
		_pending_overwrite = slot
		refresh()
		_status.text = "Press slot %d again to overwrite it." % slot
		return
	_pending_overwrite = -1
	slot_chosen.emit(slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_pressed.emit()
