class_name DossierHeader
extends HBoxContainer
## The flag, title, dock seal and close seal every force dossier wears. The fleet
## and army dossiers each built a private copy of this row; one header keeps the
## two in step (REQ-P3-01, RUB-P3-02).

signal dock_pressed
signal close_pressed

var flag: ColorRect = null
var title: Label = null
var dock: Button = null
var close: Button = null


## `title_size` is the dossier's own display size; a force name that can wrap
## asks for it, a short caption does not.
static func make(title_size: int, wrap_title: bool = false) -> DossierHeader:
	var header := DossierHeader.new()
	header._build(title_size, wrap_title)
	return header


func _build(title_size: int, wrap_title: bool) -> void:
	add_theme_constant_override("separation", 10)

	flag = ColorRect.new()
	flag.custom_minimum_size = Vector2(14, 14)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(flag)

	title = Label.new()
	title.add_theme_font_override("font", UiTheme.serif())
	title.add_theme_font_size_override("font_size", title_size)
	title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap_title:
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)

	dock = UiRowBuilder.small_button("◀", "Dock left")
	dock.pressed.connect(func() -> void: dock_pressed.emit())
	add_child(dock)

	close = UiRowBuilder.small_button("×", "Close")
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func() -> void: close_pressed.emit())
	add_child(close)


func set_dock_affordance(glyph: String, tip: String) -> void:
	dock.text = glyph
	dock.tooltip_text = tip
