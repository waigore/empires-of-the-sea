class_name MainMenu
extends Control
## Title screen: the app's entry point (REQ-P5-01). New game, load a local
## slot, and a dimmed settings door until that slice lands. The page sits on the
## living dusk backdrop, so the first frame already shows the period world.

signal new_game_pressed
signal load_game_pressed
## Debug tool: watch every Great Power play under AI control.
signal observer_pressed
signal quit_pressed

var new_game_button: Button = null
var load_game_button: Button = null
var settings_button: Button = null
var quit_button: Button = null
var observer_button: Button = null
var backdrop: MenuBackdrop = null

var _notice: Label = null
var _title: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	backdrop = MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	_build()
	_intro()


func _build() -> void:
	var short: bool = MenuFrame.is_short(self)
	var box: VBoxContainer = MenuFrame.column(self, 460.0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	if short:
		box.add_theme_constant_override("separation", 8)
	else:
		box.add_child(MenuFrame.crest(88))
	_title = MenuFrame.title("EMPIRES OF THE SEA", 32 if short else 44)
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.85))
	_title.add_theme_constant_override("outline_size", 7)
	box.add_child(_title)
	box.add_child(MenuFrame.subtitle(
		"Anno Domini MDXX  ·  the crowns look westward"
	))
	box.add_child(MenuFrame.separator())

	new_game_button = MenuFrame.action_button(
		"NEW GAME", MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	)
	new_game_button.pressed.connect(func() -> void: new_game_pressed.emit())
	box.add_child(new_game_button)

	load_game_button = MenuFrame.action_button(
		"LOAD GAME", MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	)
	load_game_button.pressed.connect(func() -> void: load_game_pressed.emit())
	box.add_child(load_game_button)

	settings_button = MenuFrame.dimmed_button(
		"SETTINGS", "Settings are not available in this build."
	)
	if short:
		settings_button.custom_minimum_size.y = MenuFrame.BUTTON_HEIGHT_SHORT
	box.add_child(settings_button)

	quit_button = MenuFrame.action_button(
		"QUIT", MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	)
	quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	box.add_child(quit_button)

	observer_button = MenuFrame.small_button("AI OBSERVER (DEBUG)")
	observer_button.pressed.connect(func() -> void: observer_pressed.emit())
	box.add_child(observer_button)

	_notice = MenuFrame.notice("")
	_notice.visible = false
	box.add_child(_notice)

	var version := MenuFrame.caption("version %s" % GameVersion.as_string())
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version)

	_reveal([new_game_button, load_game_button, settings_button, quit_button, observer_button])


## Dissolves the page in and lets the entries arrive one after another, so the
## title screen feels alive before the first input.
func _intro() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	if _title != null:
		var glow := create_tween().set_loops()
		glow.tween_property(_title, "modulate:a", 0.70, 3.4).set_trans(Tween.TRANS_SINE)
		glow.tween_property(_title, "modulate:a", 1.0, 3.4).set_trans(Tween.TRANS_SINE)


func _reveal(controls: Array[Control]) -> void:
	for i in controls.size():
		var control: Control = controls[i]
		var target: float = control.modulate.a
		control.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.18 + float(i) * 0.07)
		tween.tween_property(control, "modulate:a", target, 0.40)


## Shown above the footer when a load cannot be read.
func set_notice(text: String) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.visible = not text.is_empty()


## Android/iOS back gesture on the title screen exits the app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
