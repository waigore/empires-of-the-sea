class_name MenuFrame
extends RefCounted
## Shared period furniture for the out-of-map screens (main menu, setup, saves,
## pause). Keeps one look and one set of touch-sized targets (REQ-P1-02, P1-05).

const BUTTON_HEIGHT: float = 52.0
## Thumb-sized but compact: a 20:9 phone held landscape reports ~411 points of
## height, and the title page has to fit there without a scroll (REQ-P5-01).
const BUTTON_HEIGHT_SHORT: float = 44.0
const PANEL_WIDTH: float = 520.0
## Below this height the menu pages switch to their compact arrangement.
const SHORT_HEIGHT: float = 620.0


## Paints the full-screen ink ground every menu page sits on.
static func backdrop(host: Control) -> ColorRect:
	var ground := ColorRect.new()
	ground.color = Palette.INK
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ground)

	var wash := ColorRect.new()
	wash.color = Color(0.06, 0.05, 0.04, 0.55)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(wash)
	return ground


## Centred vertical column, safe on phones and tablets. A scroll container keeps
## every row reachable on short landscape screens.
static func column(host: Control, width: float = PANEL_WIDTH) -> VBoxContainer:
	var scroll := _scroller(host)
	return _column(scroll, host, width, true)


## Page with a pinned action row: the content scrolls, the footer never does,
## so the primary action cannot fall below the fold on a phone (REQ-P5-01).
static func page(host: Control, width: float, footer: Control) -> VBoxContainer:
	var frame := VBoxContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 16.0
	frame.offset_top = 16.0
	frame.offset_right = -16.0
	frame.offset_bottom = -16.0
	frame.add_theme_constant_override("separation", 10)
	host.add_child(frame)

	var scroll := _scroller(frame)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = _column(scroll, host, width, false)
	if footer != null:
		frame.add_child(footer)
	return box


static func _scroller(host: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16.0
	scroll.offset_top = 16.0
	scroll.offset_right = -16.0
	scroll.offset_bottom = -16.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	host.add_child(scroll)
	return scroll


## The column is centred while it fits and scrolls from its top once it does
## not: a centred container that merely fills the viewport would clip the
## heading and the footer at the same time and open the page mid-way down.
static func _column(
	scroll: ScrollContainer, host: Control, width: float, centre: bool
) -> VBoxContainer:
	var frame := CenterContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if centre:
		frame.custom_minimum_size.y = maxf(host.get_viewport_rect().size.y - 32.0, 0.0)
	scroll.add_child(frame)

	var available: float = maxf(host.get_viewport_rect().size.x - 32.0, 240.0)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(minf(width, available), 0.0)
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	return box


## True on a phone held landscape, where every decorative row competes with the
## action the player came for (REQ-P1-05, REQ-P5-01).
static func is_short(host: Control) -> bool:
	return host.get_viewport_rect().size.y < SHORT_HEIGHT


static func crest(size: int = 72) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(Icon.new("crest", size, Palette.GOLD))
	return row


static func title(text: String, size: int = 40) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	return label


static func subtitle(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.serif_italic())
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	return label


static func action_button(text: String, height: float = BUTTON_HEIGHT) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, height)
	button.add_theme_font_size_override("font_size", 17)
	return button


static func small_button(text: String, width: float = 120.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 44.0)
	button.add_theme_font_size_override("font_size", 14)
	return button


## Disabled entry with a quiet reason, used until settings land.
static func dimmed_button(text: String, reason: String) -> Button:
	var button := action_button(text)
	button.disabled = true
	button.tooltip_text = reason
	button.add_theme_stylebox_override(
		"disabled", UiTheme.box(Color(0.14, 0.12, 0.09, 0.95), Palette.GOLD_DIM, 1)
	)
	button.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM)
	return button


static func separator() -> HSeparator:
	var line := HSeparator.new()
	line.add_theme_constant_override("separation", 18)
	return line


static func notice(text: String = "") -> Label:
	var label := subtitle(text)
	label.add_theme_color_override("font_color", Palette.CRIMSON)
	return label


static func style_option(option: OptionButton) -> void:
	option.custom_minimum_size = Vector2(0.0, 48.0)
	option.add_theme_font_size_override("font_size", 16)
	option.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.INK_SOFT, Palette.GOLD_DIM, 1, 3, Vector4(14, 8, 14, 8))
	)
	option.add_theme_stylebox_override(
		"hover", UiTheme.box(Color(0.27, 0.22, 0.16), Palette.GOLD, 1, 3, Vector4(14, 8, 14, 8))
	)
	option.add_theme_stylebox_override(
		"pressed", UiTheme.box(Color(0.16, 0.13, 0.09), Palette.GOLD, 1, 3, Vector4(14, 8, 14, 8))
	)


static func style_line_edit(field: LineEdit) -> void:
	field.custom_minimum_size = Vector2(0.0, 48.0)
	field.add_theme_font_size_override("font_size", 16)
	field.add_theme_color_override("font_color", Palette.TEXT)
	field.add_theme_color_override("font_placeholder_color", Palette.TEXT_DIM)
	field.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.INK_SOFT, Palette.GOLD_DIM, 1, 3, Vector4(14, 8, 14, 8))
	)
	field.add_theme_stylebox_override(
		"focus", UiTheme.box(Palette.INK_SOFT, Palette.GOLD, 1, 3, Vector4(14, 8, 14, 8))
	)


static func panel(height: float = 0.0) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(28, 24, 28, 24))
	)
	if height > 0.0:
		frame.custom_minimum_size = Vector2(0.0, height)
	return frame
