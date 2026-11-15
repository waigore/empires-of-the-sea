class_name EndTurnDoor
extends RefCounted
## The turn's one gold door, mounted at the cartouche's right end so the chart
## keeps its corner and the turn stays one reach from anywhere (REQ-P1-07,
## REQ-P5-01). The soft glow still marks it as the turn's action without
## covering the map. GameHud keeps the button and the glow; this builds them.

const SIZE := Vector2(140.0, 44.0)
const SIZE_COMPACT := Vector2(104.0, 44.0)


static func build(hud: GameHud, row: HBoxContainer) -> void:
	var wrap := Control.new()
	wrap.name = "EndTurnDoor"
	wrap.custom_minimum_size = SIZE
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wrap)
	hud.end_turn_wrap = wrap

	hud._glow = Panel.new()
	hud._glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_style := UiTheme.box(Color(0, 0, 0, 0), Palette.GOLD, 2, 4, Vector4.ZERO)
	glow_style.shadow_color = Color(0.83, 0.69, 0.22, 0.45)
	glow_style.shadow_size = 6
	hud._glow.add_theme_stylebox_override("panel", glow_style)
	wrap.add_child(hud._glow)

	hud._end_turn_button = Button.new()
	hud._end_turn_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._end_turn_button.offset_left = 1.0
	hud._end_turn_button.offset_top = 1.0
	hud._end_turn_button.offset_right = -1.0
	hud._end_turn_button.offset_bottom = -1.0
	hud._end_turn_button.text = "END TURN"
	hud._end_turn_button.add_theme_font_size_override("font_size", 16)
	hud._end_turn_button.clip_text = true
	ChromeIcons.apply(hud._end_turn_button, "hourglass", 22)
	hud._end_turn_button.add_theme_color_override("font_color", Palette.INK)
	hud._end_turn_button.add_theme_color_override("font_hover_color", Palette.INK)
	hud._end_turn_button.add_theme_color_override("font_pressed_color", Palette.INK)
	hud._end_turn_button.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.GOLD, Palette.GOLD_PALE, 1, 3, Vector4(8, 4, 8, 4))
	)
	hud._end_turn_button.add_theme_stylebox_override(
		"hover", UiTheme.box(Palette.GOLD_PALE, Color(1, 0.96, 0.85), 1, 3, Vector4(8, 4, 8, 4))
	)
	hud._end_turn_button.add_theme_stylebox_override(
		"pressed", UiTheme.box(Palette.GOLD_DIM, Palette.GOLD, 1, 3, Vector4(8, 4, 8, 4))
	)
	hud._end_turn_button.pressed.connect(func() -> void: hud.end_turn_pressed.emit())
	wrap.add_child(hud._end_turn_button)

	var pulse := hud.create_tween().set_loops()
	pulse.tween_property(hud._glow, "modulate:a", 0.35, 1.4).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(hud._glow, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)


## A phone keeps the door tappable and its word legible: a shorter plaque and a
## smaller type size, never an icon the player has to guess (REQ-P1-05).
static func apply_compact(hud: GameHud, compact: bool) -> void:
	if hud.end_turn_wrap == null:
		return
	hud.end_turn_wrap.custom_minimum_size = SIZE_COMPACT if compact else SIZE
	if hud._end_turn_button != null:
		hud._end_turn_button.add_theme_font_size_override(
			"font_size", 12 if compact else 16
		)
