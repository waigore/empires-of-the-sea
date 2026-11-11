class_name ProvinceSheetHead
extends VBoxContainer
## The province dossier's title block: the province's name, its CAPITAL badge and
## the court that holds it. The section owns the head's widgets, so the dossier
## builds one row instead of growing its own build (REQ-P3-01).

var name_label: Label = null
var capital_badge: Label = null
var owner_swatch: ColorRect = null
var owner_label: Label = null


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)

	name_label = Label.new()
	name_label.add_theme_font_override("font", UiTheme.serif())
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(name_label)

	capital_badge = Label.new()
	capital_badge.text = "CAPITAL"
	capital_badge.add_theme_font_size_override("font_size", 10)
	capital_badge.add_theme_color_override("font_color", Palette.INK)
	capital_badge.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.GOLD, Palette.GOLD, 0, 2, Vector4(6, 2, 6, 2))
	)
	capital_badge.visible = false
	header.add_child(capital_badge)

	var owner_row := HBoxContainer.new()
	owner_row.add_theme_constant_override("separation", 8)
	add_child(owner_row)
	owner_swatch = ColorRect.new()
	owner_swatch.custom_minimum_size = Vector2(12, 12)
	owner_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	owner_row.add_child(owner_swatch)
	owner_label = Label.new()
	owner_label.add_theme_font_size_override("font_size", 14)
	owner_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	owner_row.add_child(owner_label)


func show_province(data: ProvinceState) -> void:
	name_label.text = data.name
	capital_badge.visible = data.capital
	owner_swatch.color = Palette.faction_color(data.owner)
	owner_label.text = owner_caption(data.owner)


## Faction type drives the honorific (wiki: factions — three governing types).
static func owner_caption(owner: int) -> String:
	var faction_name: String = FactionCatalog.name_of(owner)
	match FactionCatalog.type_of(owner):
		FactionCatalog.Type.GREAT_POWER:
			return "Crown of %s" % faction_name
		FactionCatalog.Type.MINOR_NATION:
			return "Minor nation of %s" % faction_name
		FactionCatalog.Type.TRIBE:
			return "Tribe of the %s" % faction_name
		_:
			return "Unclaimed territory"
