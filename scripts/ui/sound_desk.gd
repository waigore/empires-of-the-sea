class_name SoundDesk
extends VBoxContainer
## Music, effects and mute in one compact desk. The title page opens it from its
## bell seal; the campaign folds the same desk into its pause menu, so the map
## itself carries no sound control (REQ-P1-05, REQ-P1-06).

signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal mute_toggled(muted: bool)
signal ui_sound(event_name: String)
signal close_requested

const WIDTH: float = 268.0

## A closable desk (the title page's popup) carries its own ✕; an embedded desk
## belongs to the page around it. Set before the desk enters the tree.
var closable: bool = false

var music: HSlider = null
var sfx: HSlider = null
var mute: Button = null
var music_value: Label = null
var sfx_value: Label = null
var _bound: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(WIDTH, 0.0)
	_build_header()
	var music_row: Dictionary = _build_row("MUSIC")
	add_child(music_row["root"])
	music = music_row["slider"]
	music_value = music_row["value"]
	var sfx_row: Dictionary = _build_row("EFFECTS")
	add_child(sfx_row["root"])
	sfx = sfx_row["slider"]
	sfx_value = sfx_row["value"]
	_build_mute()
	music.value_changed.connect(_on_music_changed)
	sfx.value_changed.connect(_on_sfx_changed)
	sfx.drag_ended.connect(func(_changed: bool) -> void: ui_sound.emit(AudioEvents.UI_CLICK))
	set_mix(AudioMix.MUSIC_DEFAULT, AudioMix.SFX_DEFAULT, false)


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)

	var title := Label.new()
	title.text = "SOUND"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Palette.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	if not closable:
		return
	var close := Button.new()
	close.name = "Close"
	close.text = "✕"
	close.custom_minimum_size = Vector2(32, 28)
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(func() -> void:
		ui_sound.emit(AudioEvents.UI_CLICK)
		close_requested.emit()
	)
	header.add_child(close)


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


func _build_mute() -> void:
	mute = Button.new()
	mute.name = "Mute"
	mute.text = "MUTE ALL"
	mute.toggle_mode = true
	mute.custom_minimum_size = Vector2(0, 42)
	mute.add_theme_font_size_override("font_size", 14)
	mute.pressed.connect(func() -> void:
		ui_sound.emit(AudioEvents.UI_CLICK)
		mute_toggled.emit(mute.button_pressed)
	)
	add_child(mute)


func _on_music_changed(value: float) -> void:
	music_value.text = "%d%%" % roundi(value * 100.0)
	music_volume_changed.emit(value)


func _on_sfx_changed(value: float) -> void:
	sfx_value.text = "%d%%" % roundi(value * 100.0)
	sfx_volume_changed.emit(value)


## Wire the desk to a director: the sliders and the mute button drive the
## authoritative mix, and the widgets mirror changes made elsewhere (the global
## mute key). The desk is bound once, whichever page mounts it.
func bind(director: AudioDirector) -> void:
	if director == null or _bound:
		return
	_bound = true
	ui_sound.connect(director.play_event)
	music_volume_changed.connect(director.set_music_volume)
	sfx_volume_changed.connect(director.set_sfx_volume)
	mute_toggled.connect(director.set_muted)
	director.mix_changed.connect(_on_director_mix_changed)
	set_mix(director.mix.music, director.mix.sfx, director.mix.muted)


func _on_director_mix_changed(music_level: float, sfx_level: float, muted: bool) -> void:
	set_mix(music_level, sfx_level, muted)


## Mirror the authoritative mix into the widgets without echoing change signals.
func set_mix(music_level: float, sfx_level: float, muted: bool) -> void:
	if music == null:
		return
	music.set_value_no_signal(clampf(music_level, 0.0, 1.0))
	sfx.set_value_no_signal(clampf(sfx_level, 0.0, 1.0))
	music_value.text = "%d%%" % roundi(music.value * 100.0)
	sfx_value.text = "%d%%" % roundi(sfx.value * 100.0)
	mute.set_pressed_no_signal(muted)
	mute.text = "UNMUTE" if muted else "MUTE ALL"
