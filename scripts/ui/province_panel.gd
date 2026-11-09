class_name ProvincePanel
extends PanelContainer
## Slide-in dossier for the selected province: owner, terrain, resource,
## population, port and the demo's order buttons.

signal action_pressed(action: String)
signal close_pressed
signal dock_side_pressed

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
var _fort_value: Label = null
var _capital_badge: Label = null
var _training_box: VBoxContainer = null
var _dock: Button = null
var _column: VBoxContainer = null
var _grid: GridContainer = null
var _orders_box: VBoxContainer = null
var _orders_index: int = -1
var _recruit: Button = null
var _shipyard: Button = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(20, 18, 20, 18))
	)
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)


## The dossier re-orders itself for the viewport it is actually shown in.
func _fit_to_viewport() -> void:
	set_compact(HudLayout.is_compact(get_viewport_rect().size))


func _build() -> void:
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 8)
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(shell)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	_column = column

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
	_grid = grid

	_terrain_value = _add_row(grid, "Terrain")
	_resource_icon = Icon.new("tree", 16, Palette.GOLD)
	_resource_value = _add_row_with_icon(grid, "Resource", _resource_icon)
	_population_value = _add_row(grid, "Population")
	_port_value = _add_row(grid, "Port")
	_capital_value = _add_row(grid, "Capital")
	_road_value = _add_row(grid, "Roads")
	_fort_value = _add_row(grid, "Fort")

	column.add_child(_divider())

	_orders_box = VBoxContainer.new()
	_orders_box.add_theme_constant_override("separation", 8)
	column.add_child(_orders_box)
	_orders_index = _orders_box.get_index()

	var orders := Label.new()
	orders.text = "ORDERS"
	orders.add_theme_font_size_override("font_size", 11)
	orders.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_orders_box.add_child(orders)

	_recruit = _make_button("Recruit Regiment")
	_recruit.tooltip_text = "Muster at your capital; the regiment joins the Home Army."
	_recruit.pressed.connect(func() -> void: action_pressed.emit("recruit"))
	_orders_box.add_child(_recruit)

	_shipyard = _make_button("Shipyard")
	_shipyard.tooltip_text = "Launch and break up hulls at your capital port."
	_shipyard.pressed.connect(func() -> void: action_pressed.emit("shipyard"))
	_shipyard.visible = false
	_orders_box.add_child(_shipyard)

	var build := _make_button("Build Improvement")
	build.pressed.connect(func() -> void: action_pressed.emit("build"))
	_orders_box.add_child(build)

	var town := _make_button("Upgrade Town")
	town.tooltip_text = "Raise this province's town development (National Bureaucracy)."
	town.pressed.connect(func() -> void: action_pressed.emit("upgrade_town"))
	_orders_box.add_child(town)

	_training_box = VBoxContainer.new()
	_training_box.add_theme_constant_override("separation", 6)
	_training_box.visible = false
	_orders_box.add_child(_training_box)

	var training := Label.new()
	training.text = "TRAIN CIVILIANS"
	training.add_theme_font_size_override("font_size", 11)
	training.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_training_box.add_child(training)

	for type_id: String in CivilianCatalog.playable_types():
		var train := _make_button(
			"Train %s · %s" % [
				CivilianCatalog.display_name(type_id),
				CivilianCatalog.training_cost_text(type_id),
			]
		)
		train.add_theme_font_size_override("font_size", 13)
		train.pressed.connect(func() -> void: action_pressed.emit("train_%s" % type_id))
		_training_box.add_child(train)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	column.add_child(spacer)

	var hint := Label.new()
	hint.text = "Civilians muster at the capital; estates are managed from the ledger."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.6))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	shell.add_child(footer)

	_dock = _make_button("◀ Dock")
	_dock.tooltip_text = "Dock left"
	_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock.pressed.connect(func() -> void: dock_side_pressed.emit())
	footer.add_child(_dock)

	var close := _make_button("Close")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: close_pressed.emit())
	footer.add_child(close)
	_fit_to_viewport()


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _dock == null:
		return
	_dock.text = "%s Dock" % glyph
	_dock.tooltip_text = tip


## A phone sheet is short, so orders move above the survey table: every action
## stays one tap away and only the details scroll. Idempotent.
func set_compact(compact: bool) -> void:
	if _orders_box == null or _grid == null or _column == null:
		return
	# Recruit is a live order now, so it stays on the phone sheet too.
	var orders_at: int = _orders_box.get_index()
	var grid_at: int = _grid.get_index()
	if compact == (orders_at < grid_at):
		return
	_column.move_child(_orders_box, grid_at if compact else _orders_index)


func set_training_visible(visible: bool) -> void:
	_training_box.visible = visible


func refresh(model: MapModel, province_id: int) -> void:
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return
	_name_label.text = data.name
	_capital_badge.visible = data.capital
	var owner: int = data.owner
	_owner_swatch.color = Palette.faction_color(owner)
	_owner_label.text = _owner_caption(owner)
	_terrain_value.text = _dominant_terrain(model, province_id)
	var resource: int = data.resource
	if resource >= 0:
		var info: Dictionary = MapGenerator.resource_info(resource)
		_resource_icon.kind = String(info.get("icon", "ore"))
		_resource_icon.queue_redraw()
		_resource_value.text = String(info.get("name", "—"))
	else:
		_resource_icon.kind = "ore"
		_resource_icon.queue_redraw()
		_resource_value.text = "None surveyed"
	_population_value.text = "%s souls" % _thousands(data.population)
	var port: Vector2i = data.port_tile
	if port.x >= 0:
		var zone: int = model.sea_zone_at(port.x, port.y)
		_port_value.text = "Harbour · %s" % model.sea_zone_name(zone)
	else:
		_port_value.text = "Landlocked"
	var seat: Vector2i = data.capital_tile
	if seat.x >= 0:
		_capital_value.text = "Seat of the Crown · %d, %d" % [seat.x, seat.y]
	else:
		_capital_value.text = "—"
	var road_tiles: int = 0
	for path: Array in data.road_paths:
		road_tiles += path.size()
	_road_value.text = "%d tiles" % road_tiles if road_tiles > 0 else "—"
	_fort_value.text = FortRules.describe(data.fort_level)
	# The yard is a capital-port order: it launches hulls into the home fleet
	# (wiki: ships-and-naval § Home Fleet).
	_shipyard.visible = (
		data.owner == FactionCatalog.PLAYER_FACTION
		and data.capital
		and data.port_tile.x >= 0
	)


## Faction type drives the honorific (wiki: factions — three governing types).
func _owner_caption(owner: int) -> String:
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
