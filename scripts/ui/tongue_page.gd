class_name TonguePage
extends Control
## The settings page both menus share: the tongue the court speaks (wiki:
## dialogue-content-and-yarn § Localization; DR-20261113-09). One touch-sized
## row per tongue the build ships, plus the device's own choice, so a reader on
## a foreign phone can have the court in his own words (REQ-P5-07).
##
## The choice goes through [TonguePrefs], which applies it at once and keeps it
## for the next boot. The page never changes a rule: it moves the words a court
## prints, never the outcome they report (REQ-P2-03).

signal back_pressed
signal tongue_chosen(code: String)

const WIDTH: float = 400.0
## Reads the page's own tongue rows back in tests and for a host that wants to
## point the record at another path.
var settings_path: String = TonguePrefs.SETTINGS_PATH
var rows: Array[Button] = []
var back_button: Button = null
var status: Label = null
var heading: Label = null

var _list: VBoxContainer = null
var _row_height: float = MenuFrame.BUTTON_HEIGHT


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.02, 0.70)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var short: bool = MenuFrame.is_short(self)
	_row_height = MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	var box: VBoxContainer = MenuFrame.column(self, WIDTH)
	var frame := MenuFrame.panel()
	box.add_child(frame)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", 8 if short else 10)
	frame.add_child(page)

	heading = MenuFrame.title("THE COURT'S TONGUE", 22 if short else 26)
	page.add_child(heading)
	if not short:
		page.add_child(MenuFrame.subtitle(
			"The court answers in the tongue you choose. A line no file answers keeps its English."
		))

	_list = VBoxContainer.new()
	_list.name = "Tongues"
	_list.add_theme_constant_override("separation", 6)
	page.add_child(_list)

	status = MenuFrame.caption("")
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(status)

	back_button = MenuFrame.action_button("BACK", _row_height)
	back_button.pressed.connect(_on_back)
	page.add_child(back_button)


## Rebuilds the rows for the tongue now in force, so the page always shows the
## court's present tongue rather than the one it was built with.
func refresh() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	rows.clear()
	var current: String = TonguePrefs.stored(settings_path)
	_list.add_child(_row("", "FOLLOW THIS DEVICE", current.is_empty()))
	for tongue: Dictionary in DialogueLocale.tongues():
		var code: String = String(tongue.get("code", ""))
		_list.add_child(_row(code, String(tongue.get("name", code)), current == code))
	status.text = "THE COURT READS %s" % _spoken(current)


func open() -> void:
	refresh()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _row(code: String, label: String, is_current: bool) -> Button:
	var button: Button = MenuFrame.action_button(label, _row_height)
	button.name = "Tongue_%s" % (code if not code.is_empty() else "device")
	button.tooltip_text = label
	if is_current:
		button.text = "%s  ·  in use" % label
		button.add_theme_stylebox_override(
			"normal",
			UiTheme.box(Color(0.16, 0.13, 0.09, 0.98), Palette.GOLD, 2, 3, Vector4(14, 8, 14, 8))
		)
	button.pressed.connect(_on_chosen.bind(code))
	rows.append(button)
	return button


func _on_chosen(code: String) -> void:
	var kept: bool = TonguePrefs.choose(code, settings_path)
	refresh()
	if not kept:
		status.text = "THE COURT READS %s — THE CHOICE COULD NOT BE KEPT" % _spoken(code)
	tongue_chosen.emit(code)


## What the court says in this tongue, or the device's own when no tongue was
## picked.
func _spoken(code: String) -> String:
	if code.is_empty():
		return DialogueLocale.native_name(DialogueLocale.device_locale())
	return DialogueLocale.native_name(code)


func _on_back() -> void:
	close()
	back_pressed.emit()
