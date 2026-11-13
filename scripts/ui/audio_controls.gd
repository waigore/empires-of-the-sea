class_name AudioControls
extends Control
## The title page's sound seal: a bell button in the corner that opens the shared
## mix desk (music, effects, mute). The map carries no bell of its own — its
## pause menu embeds the same SoundDesk (REQ-P1-05, REQ-P1-06).

const PANEL_WIDTH := SoundDesk.WIDTH
const TRIGGER_SIZE := 46.0
const PANEL_GAP := 8.0

var _trigger: Button = null
var _panel: PanelContainer = null
var _desk: SoundDesk = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_trigger()
	_build_panel()


func _build_trigger() -> void:
	_trigger = Button.new()
	_trigger.name = "Trigger"
	_trigger.position = Vector2.ZERO
	_trigger.size = Vector2(TRIGGER_SIZE, TRIGGER_SIZE)
	_trigger.tooltip_text = "Sound"
	_trigger.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ChromeIcons.apply(_trigger, "bell", 26)
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

	_desk = SoundDesk.new()
	_desk.closable = true
	_panel.add_child(_desk)
	_desk.close_requested.connect(close_panel)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.reset_size()
	_panel.position = Vector2(0.0, TRIGGER_SIZE + PANEL_GAP)


func _on_trigger_pressed() -> void:
	_desk.ui_sound.emit(AudioEvents.UI_CLICK)
	if _panel.visible:
		close_panel()
	else:
		open_panel()


## Wire the desk to the shell's director: the sliders and the mute button drive
## the authoritative mix, and the widgets mirror changes made elsewhere.
func bind(director: AudioDirector) -> void:
	if _desk != null:
		_desk.bind(director)


## Mirror the authoritative mix into the widgets without echoing change signals.
func set_mix(music: float, sfx: float, muted: bool) -> void:
	if _desk != null:
		_desk.set_mix(music, sfx, muted)


func open_panel() -> void:
	_panel.visible = true
	_panel.reset_size()
	_panel.position = Vector2(0.0, TRIGGER_SIZE + PANEL_GAP)


func close_panel() -> void:
	_panel.visible = false


func is_open() -> bool:
	return _panel != null and _panel.visible


func music_slider() -> HSlider:
	return _desk.music if _desk != null else null


func sfx_slider() -> HSlider:
	return _desk.sfx if _desk != null else null


func mute_button() -> Button:
	return _desk.mute if _desk != null else null
