class_name ProvincePanel
extends PanelContainer
## Slide-in dossier for the selected province: owner, terrain, resource,
## population, port and the demo's order buttons.

signal action_pressed(action: String)
signal close_pressed

var _name_label: Label = null
var _owner_label: Label = null
var _owner_swatch: ColorRect = null
var _terrain_value: Label = null
var _resource_icon: Icon = null
var _resource_value: Label = null
var _population_value: Label = null
var _port_value: Label = null
var _capital_value: Label = null
var _road_value: Label = null
var _capital_badge: Label = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(20, 18, 20, 18))
	)
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", UiTheme.serif())
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_name_label)

	_capital_badge = Label.new()
	_capital_badge.text = "CAPITAL"
	_capital_badge.add_theme_font_size_override("font_size", 10)
	_capital_badge.add_theme_color_override("font_color", Palette.INK)
	_capital_badge.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.GOLD, Palette.GOLD, 0, 2, Vector4(6, 2, 6, 2))
	)
	_capital_badge.visible = false
	header.add_child(_capital_badge)

	var owner_row := HBoxContainer.new()
	owner_row.add_theme_constant_override("separation", 8)
	column.add_child(owner_row)
	_owner_swatch = ColorRect.new()
	_owner_swatch.custom_minimum_size = Vector2(12, 12)
	_owner_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	owner_row.add_child(_owner_swatch)
	_owner_label = Label.new()
	_owner_label.add_theme_font_size_override("font_size", 14)
	_owner_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	owner_row.add_child(_owner_label)

	column.add_child(_divider())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)

	_terrain_value = _add_row(grid, "Terrain")
	_resource_icon = Icon.new("tree", 16, Palette.GOLD)
	_resource_value = _add_row_with_icon(grid, "Resource", _resource_icon)
	_population_value = _add_row(grid, "Population")
	_port_value = _add_row(grid, "Port")
	_capital_value = _add_row(grid, "Capital")
	_road_value = _add_row(grid, "Roads")

	column.add_child(_divider())

	var orders := Label.new()
	orders.text = "ORDERS"
	orders.add_theme_font_size_override("font_size", 11)
	orders.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(orders)

	var recruit := _make_button("Recruit Regiment")
	recruit.pressed.connect(func() -> void: action_pressed.emit("recruit"))
	column.add_child(recruit)

	var build := _make_button("Build Improvement")
	build.pressed.connect(func() -> void: action_pressed.emit("build"))
	column.add_child(build)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	column.add_child(spacer)

	var hint := Label.new()
	hint.text = "Demo build — orders are illustrative."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.6))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	var close := _make_button("Close")
	close.pressed.connect(func() -> void: close_pressed.emit())
	column.add_child(close)


func refresh(model: MapModel, province_id: int) -> void:
	var data: Dictionary = model.province_data(province_id)
	if data.is_empty():
		return
	_name_label.text = String(data["name"])
	_capital_badge.visible = bool(data["capital"])
	var owner: int = int(data["owner"])
	_owner_swatch.color = Palette.faction_color(owner)
	_owner_label.text = "Crown of %s" % MapGenerator.FACTION_NAMES[owner]
	_terrain_value.text = _dominant_terrain(model, province_id)
	var resource: int = int(data["resource"])
	if resource >= 0:
		var info: Dictionary = MapGenerator.resource_info(resource)
		_resource_icon.kind = String(info.get("icon", "ore"))
		_resource_icon.queue_redraw()
		_resource_value.text = String(info.get("name", "—"))
	else:
		_resource_icon.kind = "ore"
		_resource_icon.queue_redraw()
		_resource_value.text = "None surveyed"
	_population_value.text = "%s souls" % _thousands(int(data["population"]))
	var port: Vector2i = data["port_tile"]
	if port.x >= 0:
		var zone: int = model.sea_zone_at(port.x, port.y)
		_port_value.text = "Harbour · %s" % model.sea_zone_name(zone)
	else:
		_port_value.text = "Landlocked"
	var seat: Vector2i = Vector2i(data.get("capital_tile", CapitalChoice.NO_TILE))
	if seat.x >= 0:
		_capital_value.text = "Seat of the Crown · %d, %d" % [seat.x, seat.y]
	else:
		_capital_value.text = "—"
	var road_tiles: int = 0
	for path: Array in data.get("road_paths", []):
		road_tiles += path.size()
	_road_value.text = "%d tiles" % road_tiles if road_tiles > 0 else "—"


func _dominant_terrain(model: MapModel, province_id: int) -> String:
	var counts: Dictionary = {}
	for tile: Vector2i in model.province_tiles(province_id):
		var terrain: int = model.terrain_at(tile.x, tile.y)
		counts[terrain] = int(counts.get(terrain, 0)) + 1
	var best: int = MapModel.Terrain.PLAINS
	var best_count: int = -1
	for terrain: int in counts.keys():
		if int(counts[terrain]) > best_count:
			best_count = int(counts[terrain])
			best = terrain
	return String(MapModel.TERRAIN_LABELS.get(best, "Unknown"))


func _thousands(value: int) -> String:
	var text: String = str(value)
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _add_row(grid: GridContainer, caption: String) -> Label:
	var key := Label.new()
	key.text = caption
	key.add_theme_font_size_override("font_size", 13)
	key.add_theme_color_override("font_color", Palette.TEXT_DIM)
	grid.add_child(key)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", Palette.TEXT)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	return value


func _add_row_with_icon(grid: GridContainer, caption: String, icon: Icon) -> Label:
	var key := Label.new()
	key.text = caption
	key.add_theme_font_size_override("font_size", 13)
	key.add_theme_color_override("font_color", Palette.TEXT_DIM)
	grid.add_child(key)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	grid.add_child(row)
	row.add_child(icon)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", Palette.TEXT)
	row.add_child(value)
	return value


func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.83, 0.69, 0.22, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 15)
	return button
