class_name MainMenu
extends Control
## Title screen: the app's entry point (REQ-P5-01). New game, load a local
## slot, and a dimmed settings door until that slice lands.

signal new_game_pressed
signal load_game_pressed
signal quit_pressed

var new_game_button: Button = null
var load_game_button: Button = null
var settings_button: Button = null
var quit_button: Button = null

var _notice: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	MenuFrame.backdrop(self)
	_build()
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)


func _build() -> void:
	var box: VBoxContainer = MenuFrame.column(self, 460.0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(MenuFrame.crest(88))
	box.add_child(MenuFrame.title("EMPIRES OF THE SEA", 44))
	box.add_child(MenuFrame.subtitle(
		"Anno Domini MDXX  ·  the crowns look westward"
	))
	box.add_child(MenuFrame.separator())

	new_game_button = MenuFrame.action_button("NEW GAME")
	new_game_button.pressed.connect(func() -> void: new_game_pressed.emit())
	box.add_child(new_game_button)

	load_game_button = MenuFrame.action_button("LOAD GAME")
	load_game_button.pressed.connect(func() -> void: load_game_pressed.emit())
	box.add_child(load_game_button)

	settings_button = MenuFrame.dimmed_button(
		"SETTINGS", "Settings are not available in this build."
	)
	box.add_child(settings_button)

	quit_button = MenuFrame.action_button("QUIT")
	quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	box.add_child(quit_button)

	_notice = MenuFrame.notice("")
	_notice.visible = false
	box.add_child(_notice)

	var version := MenuFrame.caption("version %s" % GameVersion.as_string())
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version)


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
