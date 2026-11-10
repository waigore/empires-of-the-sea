class_name GameMenu
extends CanvasLayer
## In-game pause menu (REQ-P5-01): resume, save to a local slot, load a local
## slot (the router rebuilds the whole screen) and a dimmed settings door.

signal save_chosen(slot: int)
signal load_chosen(slot: int)
signal main_menu_chosen

const SAVE_BROWSER: PackedScene = preload("res://scenes/save_browser.tscn")

var trigger: Button = null
var save_button: Button = null
var load_button: Button = null
var settings_button: Button = null
var main_menu_button: Button = null
var resume_button: Button = null
var browser: SaveBrowser = null

var _ui: Control = null
var _overlay: Control = null
var _pause_page: VBoxContainer = null
var _status: Label = null
var _owns_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = Control.new()
	_ui.name = "MenuUI"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiTheme.build()
	add_child(_ui)
	_build_trigger()
	_build_overlay()
	_build_browser()


func _build_trigger() -> void:
	trigger = Button.new()
	trigger.name = "MenuTrigger"
	trigger.text = "MENU"
	trigger.tooltip_text = "Menu"
	trigger.position = Vector2(18.0, 132.0)
	trigger.size = Vector2(46.0, 46.0)
	trigger.add_theme_font_size_override("font_size", 10)
	trigger.add_theme_stylebox_override(
		"normal",
		UiTheme.box(Color(0.09, 0.07, 0.05, 0.94), Palette.GOLD_DIM, 1, 4, Vector4(4, 4, 4, 4))
	)
	trigger.add_theme_stylebox_override(
		"hover",
		UiTheme.box(Color(0.14, 0.11, 0.08, 0.96), Palette.GOLD, 1, 4, Vector4(4, 4, 4, 4))
	)
	trigger.pressed.connect(open)
	_ui.add_child(trigger)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_ui.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.02, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	# Same centred-column contract as the menu pages: centred while it fits,
	# scrolled from the top once it does not (REQ-P5-01).
	var short: bool = MenuFrame.is_short(_ui)
	var row: float = MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	var box: VBoxContainer = MenuFrame.column(_overlay, 380.0)
	var frame := MenuFrame.panel()
	box.add_child(frame)

	_pause_page = VBoxContainer.new()
	_pause_page.add_theme_constant_override("separation", 8 if short else 10)
	frame.add_child(_pause_page)

	var heading := MenuFrame.title("PAUSED", 26 if short else 30)
	_pause_page.add_child(heading)
	if not short:
		_pause_page.add_child(MenuFrame.subtitle("The sea waits while the ledger is open."))

	resume_button = MenuFrame.action_button("RESUME", row)
	resume_button.pressed.connect(close)
	_pause_page.add_child(resume_button)

	save_button = MenuFrame.action_button("SAVE GAME", row)
	save_button.pressed.connect(open_save)
	_pause_page.add_child(save_button)

	load_button = MenuFrame.action_button("LOAD GAME", row)
	load_button.pressed.connect(open_load)
	_pause_page.add_child(load_button)

	settings_button = MenuFrame.dimmed_button(
		"SETTINGS", "Settings are not available in this build."
	)
	settings_button.custom_minimum_size.y = row
	_pause_page.add_child(settings_button)

	main_menu_button = MenuFrame.action_button("MAIN MENU", row)
	main_menu_button.pressed.connect(_on_main_menu)
	_pause_page.add_child(main_menu_button)

	_status = MenuFrame.subtitle("")
	_status.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_pause_page.add_child(_status)


func _build_browser() -> void:
	browser = SAVE_BROWSER.instantiate()
	browser.visible = false
	browser.slot_chosen.connect(_on_browser_slot)
	browser.back_pressed.connect(_show_pause_page)
	_overlay.add_child(browser)


func open() -> void:
	if _overlay == null or _overlay.visible:
		return
	_overlay.visible = true
	_show_pause_page()
	_status.text = ""
	_owns_pause = true
	get_tree().paused = true


func close() -> void:
	if _overlay == null:
		return
	_overlay.visible = false
	browser.visible = false
	if _owns_pause:
		get_tree().paused = false
		_owns_pause = false


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func open_save() -> void:
	if browser == null:
		return
	_pause_page.visible = false
	browser.visible = true
	browser.setup(SaveBrowser.Mode.SAVE, _save_dir())


func open_load() -> void:
	if browser == null:
		return
	_pause_page.visible = false
	browser.visible = true
	browser.setup(SaveBrowser.Mode.LOAD, _save_dir())


func show_save_result(ok: bool, slot: int) -> void:
	_show_pause_page()
	_status.text = (
		"Saved to slot %d." % slot if ok else "The save could not be written."
	)
	if ok and browser != null:
		browser.refresh()


## A slot the router refused: the pause menu comes back with the notice and the
## running campaign stays exactly where it was (wiki: campaign-persistence
## § Load and resume — a refused load replaces nothing).
func show_load_refused(message: String) -> void:
	open()
	_show_pause_page()
	_status.text = message


func _show_pause_page() -> void:
	if _pause_page != null:
		_pause_page.visible = true
	if browser != null:
		browser.visible = false


func _on_browser_slot(slot: int) -> void:
	if browser == null:
		return
	if browser.mode() == SaveBrowser.Mode.SAVE:
		save_chosen.emit(slot)
		return
	close()
	load_chosen.emit(slot)


func _on_main_menu() -> void:
	close()
	main_menu_chosen.emit()


func _save_dir() -> String:
	var screen := get_parent() as MapScreen
	return screen.save_dir if screen != null else SaveStore.DIR


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed(InputActions.CANCEL):
		handle_back()
		get_viewport().set_input_as_handled()


## Android/iOS back gesture: step back one layer inside the pause menu.
func handle_back() -> bool:
	if not is_open():
		return false
	if browser != null and browser.visible:
		_show_pause_page()
	else:
		close()
	return true


func _exit_tree() -> void:
	if _owns_pause:
		get_tree().paused = false
		_owns_pause = false
