class_name ProvinceSheetHead
extends VBoxContainer
## The province dossier's title block: the province's name, its CAPITAL badge,
## the court that holds it and the door to the whole realm. The section owns the
## head's widgets, so the dossier builds one row instead of growing its own
## build (REQ-P3-01).

## The whole realm: every province the crown holds, read in one ledger
## (DR-20261115-09). The dossier is where a crown asks about its land, so the
## door to the whole of it lives here rather than as a loose seal over the chart.
signal realm_pressed

var name_label: Label = null
var capital_badge: Label = null
var owner_swatch: ColorRect = null
var owner_label: Label = null
var realm_button: Button = null


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

	# The realm door: the dossier is one province, the crown's holding is not.
	# It sits on the owner row so the title keeps its width on a phone sheet.
	owner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realm_button = Button.new()
	realm_button.text = "Realm"
	realm_button.tooltip_text = "Every province the crown holds (T)"
	realm_button.custom_minimum_size = Vector2(72, 28)
	realm_button.add_theme_font_size_override("font_size", 12)
	realm_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	realm_button.pressed.connect(func() -> void: realm_pressed.emit())
	owner_row.add_child(realm_button)


func show_province(data: ProvinceState) -> void:
	_fill(data.name, data.capital, data.owner, owner_caption(data.owner))


## Fill the title block from a caller's own reading instead of the province
## record: the observatory's province sheet hands over the words its reading
## module wrote, so one head paints every province sheet (REQ-P3-01).
func fill(reading: Dictionary) -> void:
	_fill(
		String(reading.get("name", "")),
		bool(reading.get("capital", false)),
		int(reading.get("owner", MapModel.NO_ID)),
		String(reading.get("owner_caption", ""))
	)


func _fill(title: String, is_capital: bool, owner: int, caption: String) -> void:
	name_label.text = title
	capital_badge.visible = is_capital
	owner_swatch.color = Palette.faction_color(owner)
	owner_label.text = caption


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
