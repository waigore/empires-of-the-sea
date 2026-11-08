class_name FleetPanel
extends PanelContainer
## Bottom-centre dossier for the selected fleet: colours, station and the
## remaining move. Orders happen on the map; this panel only reads state.

signal close_pressed

var _flag: ColorRect = null
var _title: Label = null
var _location: Label = null
var _ships: Label = null
var _status: Label = null
var _hint: Label = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(18, 12, 18, 12)
		)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	_flag = ColorRect.new()
	_flag.custom_minimum_size = Vector2(14, 14)
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_flag)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.serif())
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(40, 40)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close)

	_location = Label.new()
	_location.add_theme_font_size_override("font_size", 15)
	_location.add_theme_color_override("font_color", Palette.TEXT)
	column.add_child(_location)

	_ships = Label.new()
	_ships.add_theme_font_size_override("font_size", 13)
	_ships.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(_ships)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Palette.GOLD_PALE)
	column.add_child(_status)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)


func refresh(model: MapModel, fleet: FleetState, is_player: bool) -> void:
	if model == null or fleet == null:
		return
	_flag.color = Palette.faction_color(fleet.owner)
	_title.text = "FLEET OF %s" % String(MapGenerator.FACTION_NAMES[fleet.owner]).to_upper()
	if fleet.is_at_sea():
		_location.text = "At sea · %s" % model.sea_zone_name(fleet.sea_zone)
	else:
		_location.text = "In port · %s" % model.province_name(fleet.province)
	_ships.text = "%d ships · %s" % [fleet.ship_count(), fleet.hull_summary()]
	if not is_player:
		_status.text = "Enemy colours · no orders"
		_hint.text = "Observe only. Orders require your own fleet."
	elif fleet.moved:
		_status.text = "Has moved this turn"
		_hint.text = "End the turn to sail again."
	else:
		_status.text = "1 move this turn"
		_hint.text = "Tap a highlighted sea zone or a friendly port."
