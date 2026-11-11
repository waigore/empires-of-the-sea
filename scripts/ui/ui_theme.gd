class_name UiTheme
extends RefCounted
## Period typography and shared styleboxes. System serif fonts keep the build
## asset-free while still reading as 16th-18th century print (REQ-P1-02).

const SERIF_STACK: Array[String] = [
	"Palatino", "Palatino Linotype", "Baskerville", "Georgia", "Times New Roman",
	"Liberation Serif", "DejaVu Serif", "serif",
]

static var _serif: Font = null
static var _serif_italic: Font = null
static var _theme: Theme = null


static func serif() -> Font:
	if _serif == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(SERIF_STACK)
		font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_serif = font
	return _serif


static func serif_italic() -> Font:
	if _serif_italic == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(SERIF_STACK)
		font.font_italic = true
		font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_serif_italic = font
	return _serif_italic


static func box(
	fill: Color,
	border: Color = Color(0, 0, 0, 0),
	border_width: int = 0,
	radius: int = 3,
	margins: Vector4 = Vector4(12, 8, 12, 8)
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	style.anti_aliasing = true
	return style


## The one theme every screen wears. Built on first use and shared, so mounting
## a screen costs no stylebox allocation. Godot shares a `theme` resource by
## reference between the controls that wear it, so callers must treat it as
## read-only: override on the control (`add_theme_*_override`) instead.
static func build() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = serif()
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.GOLD_PALE)
	theme.set_color("font_pressed_color", "Button", Palette.GOLD)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_DIM)
	theme.set_font_size("font_size", "Button", 16)

	theme.set_stylebox("normal", "Button", box(Palette.INK_SOFT, Palette.GOLD_DIM, 1))
	theme.set_stylebox("hover", "Button", box(Color(0.27, 0.22, 0.16), Palette.GOLD, 1))
	theme.set_stylebox("pressed", "Button", box(Color(0.16, 0.13, 0.09), Palette.GOLD, 1))
	theme.set_stylebox("disabled", "Button", box(Color(0.18, 0.15, 0.11), Palette.INK_LINE, 1))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Palette.GOLD, 1))

	var panel_style := box(Color(0.11, 0.09, 0.07, 0.94), Palette.GOLD_DIM, 1)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)
	_theme = theme
	return theme
