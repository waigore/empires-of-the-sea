class_name CivilianPanel
extends PanelContainer
## Dossier for a selected civilian: posting, development of its tile, and the
## work orders its type may take (wiki: civilian-units § Work Order Summary).

signal action_pressed(action: String)
signal cancel_pressed
signal close_pressed
signal dock_side_pressed

var _title: Label = null
var _subtitle: Label = null
var _status: Label = null
var _detail: GridContainer = null
var _orders: VBoxContainer = null
var _cancel: Button = null
var _stock_line: Label = null
var _dock: Button = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(20, 16, 20, 16))
	)
	_build()


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
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.serif())
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(_subtitle)

	_detail = GridContainer.new()
	_detail.columns = 2
	_detail.add_theme_constant_override("h_separation", 16)
	_detail.add_theme_constant_override("v_separation", 4)
	column.add_child(_detail)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Palette.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var heading := Label.new()
	heading.text = "WORK ORDERS"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(heading)

	_orders = VBoxContainer.new()
	_orders.add_theme_constant_override("separation", 4)
	column.add_child(_orders)

	_stock_line = Label.new()
	_stock_line.add_theme_font_size_override("font_size", 11)
	_stock_line.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.7))
	_stock_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stock_line)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	shell.add_child(footer)

	_cancel = _make_button("Cancel Work")
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	footer.add_child(_cancel)

	_dock = _make_button("◀")
	_dock.tooltip_text = "Dock left"
	_dock.custom_minimum_size = Vector2(48, 0)
	_dock.pressed.connect(func() -> void: dock_side_pressed.emit())
	footer.add_child(_dock)

	var close := _make_button("Close")
	close.pressed.connect(func() -> void: close_pressed.emit())
	footer.add_child(close)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _dock == null:
		return
	_dock.text = glyph
	_dock.tooltip_text = tip


func refresh(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null
) -> void:
	if unit == null:
		return
	_title.text = unit.display_name()
	_subtitle.text = "Crown of %s · %s" % [
		FactionCatalog.name_of(unit.owner),
		MapModel.TERRAIN_LABELS.get(
			model.terrain_at(unit.tile.x, unit.tile.y), "Unknown"
		),
	]
	_fill_detail(model, unit, works)
	_status.text = _status_text(model, unit)
	_cancel.visible = unit.is_working()
	_fill_orders(model, unit, works, units, stockpile, visibility)
	_stock_line.text = "Stores: %d lumber · %d cast iron · %d bronze · %d paper" % [
		int(stockpile.get("lumber", 0)),
		int(stockpile.get("castIron", 0)),
		int(stockpile.get("bronze", 0)),
		int(stockpile.get("paper", 0)),
	]


func _fill_detail(model: MapModel, unit: CivilianState, works: LandWorks) -> void:
	_clear(_detail)
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	_add_row("Province", model.province_name(province) if province >= 0 else "—")
	_add_row("Tile", "%d, %d" % [unit.tile.x, unit.tile.y])
	var resource: int = model.resource_at(unit.tile.x, unit.tile.y)
	if resource >= 0:
		_add_row("Resource", String(MapGenerator.resource_info(resource).get("name", "—")))
	else:
		_add_row("Resource", "None surveyed")
	var development: PackedStringArray = PackedStringArray()
	var level: int = works.improvement_at(model, unit.tile)
	if level > 0:
		development.append(
			ImprovementCatalog.display_name(model.resource_at(unit.tile.x, unit.tile.y), level)
		)
	if works.transport_at(model, unit.tile) >= LandWorks.TRANSPORT_ROAD:
		development.append("Road")
	if works.has_port(model, unit.tile):
		development.append("Port")
	if works.is_prospected(unit.owner, model, unit.tile):
		development.append("Prospected")
	_add_row("Works", " · ".join(development) if not development.is_empty() else "—")


func _status_text(_model: MapModel, unit: CivilianState) -> String:
	if not unit.is_working():
		return "Idle — choose an order below."
	return "%s · %d turn%s left." % [
		CivilianWork.label(unit.work_action()),
		unit.remaining_turns(),
		"" if unit.remaining_turns() == 1 else "s",
	]


func _fill_orders(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel
) -> void:
	_clear(_orders)
	for option: Dictionary in CivilianWork.options(
		model, unit, works, units, stockpile, visibility
	):
		var action: String = String(option["action"])
		var button := _make_button(
			"%s · %s" % [String(option["label"]), String(option["cost_text"])]
		)
		button.disabled = not bool(option["ok"]) or unit.is_working()
		button.pressed.connect(func() -> void: action_pressed.emit(action))
		_orders.add_child(button)
		if not bool(option["ok"]):
			var reason := Label.new()
			reason.text = String(option["reason"])
			reason.add_theme_font_size_override("font_size", 11)
			reason.add_theme_color_override("font_color", Color(0.80, 0.63, 0.45, 0.9))
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_orders.add_child(reason)


func _add_row(caption: String, value: String) -> void:
	var key := Label.new()
	key.text = caption
	key.add_theme_font_size_override("font_size", 12)
	key.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_detail.add_child(key)
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_child(label)


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_size_override("font_size", 14)
	return button
