class_name AudioControls
extends Control
## The screen's sound seal: a bell button in the cartouche corner that opens a
## small mix desk (music, effects, mute). Touch-first — every target is at least
## 40 px tall — and it never covers the map centre (REQ-P1-05, REQ-P1-06).

signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal mute_toggled(muted: bool)
signal ui_sound(event_name: String)

const PANEL_WIDTH := 268.0
const TRIGGER_SIZE := 46.0
const PANEL_GAP := 8.0
## The estates seal sits directly under the bell; the mix desk opens below it.
const SEAL_CLEARANCE := 52.0

var _trigger: Button = null
var _panel: PanelContainer = null
var _music: HSlider = null
var _sfx: HSlider = null
var _music_value: Label = null
var _sfx_value: Label = null
var _mute: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_trigger()
	_build_panel()
	set_mix(AudioMix.MUSIC_DEFAULT, AudioMix.SFX_DEFAULT, false)


# --- construction -----------------------------------------------------------


func _build_trigger() -> void:
	_trigger = Button.new()
	_trigger.name = "Trigger"
	_trigger.position = Vector2.ZERO
	_trigger.size = Vector2(TRIGGER_SIZE, TRIGGER_SIZE)
	_trigger.tooltip_text = "Sound"
	_trigger.add_theme_stylebox_override(
		"normal",
		UiTheme.box(Color(0.09, 0.07, 0.05, 0.94), Palette.GOLD_DIM, 1, 4, Vector4(4, 4, 4, 4))
	)
	_trigger.add_theme_stylebox_override(
		"hover",
		UiTheme.box(Color(0.14, 0.11, 0.08, 0.96), Palette.GOLD, 1, 4, Vector4(4, 4, 4, 4))
	)
	_trigger.add_theme_stylebox_override(
		"pressed",
		UiTheme.box(Color(0.06, 0.05, 0.04, 0.98), Palette.GOLD_PALE, 1, 4, Vector4(4, 4, 4, 4))
	)
	_trigger.pressed.connect(_on_trigger_pressed)
	add_child(_trigger)

	var bell := Icon.new("bell", 24, Palette.GOLD_PALE)
	bell.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	bell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trigger.add_child(bell)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MixDesk"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(16, 12, 16, 14))
	)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = "SOUND"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Palette.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(32, 28)
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(func() -> void:
		ui_sound.emit(AudioEvents.UI_CLICK)
		close_panel()
	)
	header.add_child(close)

	var music_row: Dictionary = _build_row("MUSIC")
	column.add_child(music_row["root"])
	_music = music_row["slider"]
	_music_value = music_row["value"]

	var sfx_row: Dictionary = _build_row("EFFECTS")
	column.add_child(sfx_row["root"])
	_sfx = sfx_row["slider"]
	_sfx_value = sfx_row["value"]

	_mute = Button.new()
	_mute.text = "MUTE ALL"
	_mute.toggle_mode = true
	_mute.custom_minimum_size = Vector2(0, 42)
	_mute.add_theme_font_size_override("font_size", 14)
	_mute.pressed.connect(_on_mute_pressed)
	column.add_child(_mute)

	_music.value_changed.connect(_on_music_changed)
	_sfx.value_changed.connect(_on_sfx_changed)
	_sfx.drag_ended.connect(func(_changed: bool) -> void: ui_sound.emit(AudioEvents.UI_CLICK))

	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.reset_size()
	_panel.position = Vector2(0.0, TRIGGER_SIZE + PANEL_GAP + SEAL_CLEARANCE)


func _build_row(caption: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)

	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(label)

	var value := Label.new()
	value.text = "0%"
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", Palette.GOLD_PALE)
	top.add_child(value)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(0, 32)
	slider.focus_mode = Control.FOCUS_NONE
	root.add_child(slider)
	return {"root": root, "slider": slider, "value": value}


# --- interaction ------------------------------------------------------------


func _on_trigger_pressed() -> void:
	ui_sound.emit(AudioEvents.UI_CLICK)
	if _panel.visible:
		close_panel()
	else:
		open_panel()


func _on_music_changed(value: float) -> void:
	_music_value.text = "%d%%" % roundi(value * 100.0)
	music_volume_changed.emit(value)


func _on_sfx_changed(value: float) -> void:
	_sfx_value.text = "%d%%" % roundi(value * 100.0)
	sfx_volume_changed.emit(value)


func _on_mute_pressed() -> void:
	ui_sound.emit(AudioEvents.UI_CLICK)
	mute_toggled.emit(_mute.button_pressed)


# --- state ------------------------------------------------------------------


## Mirror the authoritative mix into the widgets without echoing change signals.
func set_mix(music: float, sfx: float, muted: bool) -> void:
	if _music == null:
		return
	_music.set_value_no_signal(clampf(music, 0.0, 1.0))
	_sfx.set_value_no_signal(clampf(sfx, 0.0, 1.0))
	_music_value.text = "%d%%" % roundi(_music.value * 100.0)
	_sfx_value.text = "%d%%" % roundi(_sfx.value * 100.0)
	_mute.set_pressed_no_signal(muted)
	_mute.text = "UNMUTE" if muted else "MUTE ALL"


func open_panel() -> void:
	_panel.visible = true
	_panel.reset_size()
	_panel.position = Vector2(0.0, TRIGGER_SIZE + PANEL_GAP + SEAL_CLEARANCE)


func close_panel() -> void:
	_panel.visible = false


func is_open() -> bool:
	return _panel != null and _panel.visible


func music_slider() -> HSlider:
	return _music


func sfx_slider() -> HSlider:
	return _sfx


func mute_button() -> Button:
	return _mute
