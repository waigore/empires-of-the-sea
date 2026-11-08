class_name EconomyPanel
extends PanelContainer
## Ledger: production assignment, world market and worker roster in three tabs.
## Presentation only — every button emits an intent and the controller asks the
## rules layer what happened (REQ-P2-03).

signal trade_requested(commodity: String, quantity: int, is_buy: bool)
signal production_changed(recipe_id: String, units: int)
signal recruit_requested(tier: int)
signal close_pressed

const ROW_HEIGHT: float = 38.0

var _summary: Label = null
var _preview: Label = null
var _tabs: TabContainer = null
var _production_body: VBoxContainer = null
var _market_body: VBoxContainer = null
var _workers_body: VBoxContainer = null
var _economy: PlayerEconomy = null
var _market: WorldMarket = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(20, 14, 20, 14))
	)
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)


## The ledger re-fits itself for the viewport it is actually shown in.
func _fit_to_viewport() -> void:
	set_compact(HudLayout.is_compact(get_viewport_rect().size))


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	var title := Label.new()
	title.text = "THE LEDGER"
	title.add_theme_font_override("font", UiTheme.serif())
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := _small_button("Close")
	close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close)

	_summary = _label("", 14, Palette.TEXT)
	column.add_child(_summary)

	_preview = _label("", 12, Palette.TEXT_DIM)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# An autowrapped Label reports a min height measured at width 1, which would
	# push the Close/newer rows off a short screen. A sane wrap width bounds it.
	_preview.custom_minimum_size = Vector2(240, 0)
	column.add_child(_preview)

	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 300)
	_tabs.add_theme_color_override("font_selected_color", Palette.GOLD_PALE)
	_tabs.add_theme_color_override("font_unselected_color", Palette.TEXT_DIM)
	column.add_child(_tabs)
	_production_body = _add_page("PRODUCTION")
	_market_body = _add_page("MARKET")
	_workers_body = _add_page("WORKERS")
	_fit_to_viewport()


func _add_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	return body


func select_tab(index: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


## The tab body is the part that gives way on a short (phone) viewport, so the
## header and Close stay on screen instead of being pushed off the bottom.
func set_compact(compact: bool) -> void:
	if _tabs == null:
		return
	_tabs.custom_minimum_size = Vector2(0.0, 0.0 if compact else 300.0)
	# A 27 px tab strip is a mouse target; a phone tab gets thumb padding.
	if compact:
		_tabs.add_theme_stylebox_override("tab_selected", _tab_box(true))
		_tabs.add_theme_stylebox_override("tab_unselected", _tab_box(false))
		_tabs.add_theme_stylebox_override("tab_hovered", _tab_box(false))
		return
	for key: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		_tabs.remove_theme_stylebox_override(key)


func _tab_box(selected: bool) -> StyleBoxFlat:
	var fill := Color(0.16, 0.13, 0.09, 0.98) if selected else Color(0.09, 0.07, 0.05, 0.9)
	return UiTheme.box(fill, Palette.GOLD_DIM, 1, 3, Vector4(16, 11, 16, 11))


## Rebuilds every row from live state plus the end-of-turn projection report.
func refresh(economy: PlayerEconomy, market: WorldMarket, report: Dictionary) -> void:
	_economy = economy
	_market = market
	if _tabs == null:
		return
	_summary.text = "%s ducats   ·   labour %d / %d   ·   food need %d   ·   strikes %d" % [
		_format(economy.treasury),
		_labour_idle(report),
		economy.workers.labour(),
		economy.workers.food_demand() + _navy_food(report),
		int((report.get("consumption", {}) as Dictionary).get("strikers", 0)),
	]
	_preview.text = _preview_text(report)
	_clear(_production_body)
	_clear(_market_body)
	_clear(_workers_body)
	_fill_production()
	_fill_market()
	_fill_workers()


func _fill_production() -> void:
	for recipe_id: String in ProductionRecipes.available_ids(_economy.tech_unlocked):
		_production_body.add_child(_recipe_row(recipe_id))
	_add_spacer(_production_body)


func _recipe_row(recipe_id: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 8)

	var name_label := _label(_recipe_title(recipe_id), 14, Palette.TEXT)
	name_label.tooltip_text = _recipe_text(recipe_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var units: int = _economy.assignment_units(recipe_id)
	var stepper := _label("%d" % units, 14, Palette.GOLD_PALE)
	stepper.custom_minimum_size = Vector2(48, 0)
	stepper.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(stepper)

	var minus := _small_button("−")
	minus.custom_minimum_size = Vector2(70, ROW_HEIGHT)
	minus.pressed.connect(func() -> void: production_changed.emit(recipe_id, units - 1))
	row.add_child(minus)

	var plus := _small_button("+")
	plus.custom_minimum_size = Vector2(70, ROW_HEIGHT)
	plus.pressed.connect(func() -> void: production_changed.emit(recipe_id, units + 1))
	row.add_child(plus)
	return row


func _fill_market() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(_column_caption("COMMODITY", 132.0))
	header.add_child(_column_caption("HAVE", 44.0))
	header.add_child(_column_caption("PRICE", 44.0))
	_market_body.add_child(header)
	for category in [
		CommodityCatalog.Category.FOOD,
		CommodityCatalog.Category.RAW,
		CommodityCatalog.Category.MANUFACTURED,
	]:
		for id: String in CommodityCatalog.ids_in(category):
			_market_body.add_child(_market_row(id, _economy.quantity(id)))
	_add_spacer(_market_body)


func _market_row(id: String, held: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 8)

	var name_label := _label(CommodityCatalog.label(id), 14, Palette.TEXT)
	name_label.custom_minimum_size = Vector2(132, 0)
	row.add_child(name_label)

	var qty := _label("%d" % held, 14, Palette.GOLD_PALE)
	qty.custom_minimum_size = Vector2(44, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var unit_price: int = _market.price(id)
	var price := _label("%d" % unit_price, 13, Palette.TEXT_DIM)
	price.custom_minimum_size = Vector2(44, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)

	var sell := _small_button("Sell")
	sell.custom_minimum_size = Vector2(70, ROW_HEIGHT)
	sell.disabled = held <= 0
	sell.tooltip_text = "Sell 1 %s for %d ducats" % [CommodityCatalog.label(id), unit_price]
	sell.pressed.connect(func() -> void: trade_requested.emit(id, 1, false))
	row.add_child(sell)

	var buy := _small_button("Buy")
	buy.custom_minimum_size = Vector2(70, ROW_HEIGHT)
	buy.tooltip_text = "Buy 1 %s for %d ducats" % [CommodityCatalog.label(id), unit_price]
	buy.pressed.connect(func() -> void: trade_requested.emit(id, 1, true))
	row.add_child(buy)
	return row


func _fill_workers() -> void:
	_workers_body.add_child(
		_label(
			"Peasants eat 1 food; trained workers eat grain + meat and need their tier luxury.",
			11,
			Palette.TEXT_DIM
		)
	)
	for tier in WorkerPool.TIER_COUNT:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.add_theme_constant_override("separation", 8)
		var name_label := _label(WorkerPool.tier_name(tier), 14, Palette.TEXT)
		name_label.custom_minimum_size = Vector2(132, 0)
		row.add_child(name_label)
		var detail := _label(
			"%d  ·  labour %d" % [
				_economy.workers.count(tier),
				_economy.workers.count(tier) * WorkerPool.LABOUR_PER_WORKER[tier],
			],
			13,
			Palette.TEXT_DIM
		)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(detail)
		var reason: String = _economy.recruit_blocked_reason(tier)
		var recruit := _small_button("Recruit")
		recruit.custom_minimum_size = Vector2(88, ROW_HEIGHT)
		recruit.disabled = not reason.is_empty()
		recruit.tooltip_text = reason if not reason.is_empty() else _recruit_text(tier)
		recruit.pressed.connect(func() -> void: recruit_requested.emit(tier))
		row.add_child(recruit)
		_workers_body.add_child(row)
	_add_spacer(_workers_body)


# --- helpers -----------------------------------------------------------------


func _add_spacer(body: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	body.add_child(spacer)


func _clear(body: VBoxContainer) -> void:
	for child in body.get_children():
		child.queue_free()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _column_caption(text: String, width: float) -> Label:
	var label := _label(text, 10, Palette.TEXT_DIM)
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(78, ROW_HEIGHT)
	button.add_theme_font_size_override("font_size", 13)
	return button


func _recipe_title(recipe_id: String) -> String:
	var out_id: String = ProductionRecipes.output(recipe_id)
	var text: String = CommodityCatalog.label(out_id)
	var inputs: Dictionary = ProductionRecipes.inputs(recipe_id)
	if inputs.size() == 1:
		text += " (%s)" % CommodityCatalog.label(String(inputs.keys()[0]))
	return text


func _recipe_text(recipe_id: String) -> String:
	var parts: PackedStringArray = []
	var inputs: Dictionary = ProductionRecipes.inputs(recipe_id)
	for commodity: Variant in inputs.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(commodity)), int(inputs[commodity])])
	return "  +  ".join(parts) + "  →  1 %s  ·  %d labour" % [
		CommodityCatalog.label(ProductionRecipes.output(recipe_id)),
		ProductionRecipes.labour(recipe_id),
	]


func _recruit_text(tier: int) -> String:
	var cost: Dictionary = WorkerPool.recruit_cost(tier)
	var materials: Dictionary = cost.get("materials", {})
	var parts: PackedStringArray = []
	if int(cost.get("treasury", 0)) > 0:
		parts.append("%d ducats" % int(cost.get("treasury", 0)))
	for commodity: Variant in materials.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(commodity)), int(materials[commodity])])
	return "   ".join(parts)


func _labour_idle(report: Dictionary) -> int:
	return int((report.get("consumption", {}) as Dictionary).get("idle_labour", 0))


func _navy_food(report: Dictionary) -> int:
	return int((report.get("consumption", {}) as Dictionary).get("navy_demand", 0))


func _preview_text(report: Dictionary) -> String:
	var parts: PackedStringArray = []
	var delta: Dictionary = report.get("stockpile_delta", {})
	for id: String in delta.keys():
		parts.append("%s %+d" % [CommodityCatalog.label(id), int(delta[id])])
	var treasury_delta: int = int(report.get("treasury_delta", 0))
	if treasury_delta != 0:
		parts.append("%s %+d" % ["ducats", treasury_delta])
	if parts.is_empty():
		return "Next turn: no stock changes."
	return "Next turn:  " + "   ".join(parts)


func _format(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
