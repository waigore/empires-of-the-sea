class_name ProvincePanel
extends PanelContainer
## Slide-in dossier for the selected province. The sheet's title block, its fact
## grid, the estates it holds and the order rail are sections of their own, so no
## build method grows into a god method (REQ-P3-01). Every row is a fact the
## player can act on; the rules decide what an order may do (REQ-P3-02).

signal action_pressed(action: String)
signal close_pressed
signal dock_side_pressed

var _head: ProvinceSheetHead = null
var _grid: ProvinceFactsGrid = null
var _orders: ProvinceOrdersSection = null
var _resources: ProvinceResources = null
var _dock: Button = null
var _column: VBoxContainer = null
var _orders_index: int = -1

## Live state the dossier reads (set by MapPlaySetup, like the estates ledger).
var _model: MapModel = null
var _works: LandWorks = null
var _units: Array[CivilianState] = []
var _visibility: VisibilityModel = null
var _capital_tile: Vector2i = CivilianState.NO_TILE
var _faction: int = -1
var _tech_caps: Dictionary = {}
var _tech_unlocked: Dictionary = {}
var _province_id: int = -1


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

	_head = ProvinceSheetHead.new()
	column.add_child(_head)

	column.add_child(_divider())

	_grid = ProvinceFactsGrid.new()
	column.add_child(_grid)

	column.add_child(_divider())

	_resources = ProvinceResources.new()
	column.add_child(_resources)

	column.add_child(_divider())

	_orders = ProvinceOrdersSection.new()
	_orders.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	column.add_child(_orders)
	_orders_index = _orders.get_index()

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

	var close := _make_button("Close")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: close_pressed.emit())
	footer.add_child(close)

	_dock = _icon_button("◀", "Dock left")
	_dock.pressed.connect(func() -> void: dock_side_pressed.emit())
	footer.add_child(_dock)
	_fit_to_viewport()


## Live tables for the survey rows and the town gate. The panel keeps the
## references, so a turn that changes works or research re-renders the open
## dossier without the map layer handing it over again.
func set_data(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	visibility: VisibilityModel,
	capital_tile: Vector2i,
	faction: int,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary
) -> void:
	var same_map: bool = model != null and model == _model
	_model = model
	_works = works
	_units = units
	_visibility = visibility
	_capital_tile = capital_tile
	_faction = faction
	_tech_caps = tech_caps
	_tech_unlocked = tech_unlocked
	if not same_map:
		# A region switch invalidates the province id it was showing.
		_province_id = -1
		return
	if _province_id >= 0:
		refresh(model, _province_id)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _dock == null:
		return
	_dock.text = glyph
	_dock.tooltip_text = tip


## A phone sheet is short, so orders move above the survey table: every action
## stays one tap away and only the details scroll. Idempotent.
func set_compact(compact: bool) -> void:
	if _orders == null or _grid == null or _column == null:
		return
	# Recruit is a live order now, so it stays on the phone sheet too.
	var orders_at: int = _orders.get_index()
	var grid_at: int = _grid.get_index()
	if compact == (orders_at < grid_at):
		return
	_column.move_child(_orders, grid_at if compact else _orders_index)


func set_training_visible(visible: bool) -> void:
	_orders.set_training_visible(visible)


## Repaints the live crown rows after a road completed or a town grew, without
## re-sliding the sheet the player is reading.
func refresh_crown(crown: Dictionary) -> void:
	_grid.refresh_crown(crown)


## `crown` is `LandConnectivity.province_link` for this province: whether its
## town reaches the capital. When omitted, the roads row falls back to the
## estate survey (DossierCopy).
func refresh(model: MapModel, province_id: int, crown: Dictionary = {}) -> void:
	_model = model
	_province_id = province_id
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return
	_head.show_province(data)
	_grid.show_province(model, province_id, data)
	var rows: Array[Dictionary] = ResourceSurvey.province_rows(
		model, _works, _units, _faction, province_id, _visibility, _capital_tile,
		_tech_caps
	)
	_resources.render(rows)
	_grid.set_estate_roads(data, rows, crown)
	_orders.set_town_order(data, _faction, _tech_unlocked)
	_orders.set_shipyard_visible(
		data.owner == _faction and data.capital and data.port_tile.x >= 0
	)


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


## A dock affordance is a glyph in the corner, never a titled bar: the dossier
## itself is the subject, the side it opens on is housekeeping.
func _icon_button(text: String, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(40, 40)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.add_theme_font_size_override("font_size", 18)
	return button
