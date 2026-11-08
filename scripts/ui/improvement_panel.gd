class_name ImprovementPanel
extends Control
## The crown's estates ledger: a whole-realm view of improvements, yields,
## active works and vacant resource tiles, with one-click Builder dispatch.
## The panel renders ImprovementLedger rows and emits intents; MapScreen owns
## the rules call and the camera (REQ-P3-02, REQ-P3-03).

signal action_pressed(action: String, tile: Vector2i)
signal focus_pressed(tile: Vector2i)

const FILTERS: Array[String] = ["all", "producing", "building", "vacant", "issues"]

var model: MapModel = null
var works: LandWorks = null
var units: Array[CivilianState] = []
var stockpile: Dictionary = {}
var capital_tile: Vector2i = CivilianState.NO_TILE
var faction: int = 0
var tech_caps: Dictionary = {}

var _toggle: Button = null
var _overlay: Control = null
var _margin: MarginContainer = null
var _panel: PanelContainer = null
var _rows: VBoxContainer = null
var _stat_values: Dictionary = {}
var _stats: Control = null
var _output_line: Label = null
var _stores_line: Label = null
var _subtitle: Label = null
var _filter_buttons: Dictionary = {}
var _data: Dictionary = {}
var _filter: String = "all"
var _province_filter: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build_toggle()
	_build_overlay()
	resized.connect(_fit_to_viewport)
	_fit_to_viewport()


func _fit_to_viewport() -> void:
	HudLayout.fit_estates(self)


func set_data(
	p_model: MapModel,
	p_works: LandWorks,
	p_units: Array[CivilianState],
	p_stockpile: Dictionary,
	p_capital: Vector2i,
	p_faction: int = 0,
	p_tech_caps: Dictionary = {}
) -> void:
	model = p_model
	works = p_works
	units = p_units
	stockpile = p_stockpile
	capital_tile = p_capital
	faction = p_faction
	tech_caps = p_tech_caps


## Research can lift a cap mid-turn; the screen pushes the new table in.
func set_tech_caps(p_tech_caps: Dictionary) -> void:
	tech_caps = p_tech_caps


func open(province_id: int = -1, filter_key: String = "all") -> void:
	_province_filter = province_id
	_filter = filter_key if FILTERS.has(filter_key) else "all"
	_overlay.visible = true
	refresh()
	_sync_filters()


func close() -> void:
	if _overlay != null:
		_overlay.visible = false


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func refresh() -> void:
	if model == null or works == null:
		return
	_data = ImprovementLedger.snapshot(
		model, works, units, stockpile, faction, capital_tile, tech_caps
	)
	_update_summary()
	_apply_filter()


func refresh_if_open() -> void:
	if is_open():
		refresh()


func _input(event: InputEvent) -> void:
	if not is_open() or not event.is_action_pressed(InputActions.CANCEL):
		return
	close()
	get_viewport().set_input_as_handled()


# --- construction -----------------------------------------------------------


func _build_toggle() -> void:
	_toggle = Button.new()
	_toggle.text = "ESTATES"
	_toggle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toggle.offset_left = 18.0
	_toggle.offset_top = 132.0
	_toggle.offset_right = 238.0
	_toggle.offset_bottom = 176.0
	_toggle.add_theme_font_size_override("font_size", 14)
	_toggle.pressed.connect(func() -> void: open())
	add_child(_toggle)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.04, 0.03, 0.74)
	_overlay.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = margin
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 88)
	margin.add_theme_constant_override("margin_bottom", 34)
	_overlay.add_child(margin)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.98), Palette.GOLD_DIM, 1, 4, Vector4(20, 16, 20, 16))
	)
	margin.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	_add_header(column)
	_add_summary(column)
	_add_filters(column)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	scroll.add_child(_rows)

	_add_footer(column)


func _add_header(column: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	var title := Label.new()
	title.text = "THE CROWN'S ESTATES"
	title.add_theme_font_override("font", UiTheme.serif())
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	titles.add_child(title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", Palette.TEXT_DIM)
	titles.add_child(_subtitle)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(92, 38)
	close_button.pressed.connect(close)
	header.add_child(close_button)


func _add_summary(column: VBoxContainer) -> void:
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 26)
	column.add_child(stats)
	_stats = stats
	for spec: Array in [
		["estates", "ESTATES"],
		["producing", "PRODUCING"],
		["output", "YIELD / TURN"],
		["building", "WORKS"],
	]:
		stats.add_child(_stat_box(String(spec[0]), String(spec[1])))

	_output_line = Label.new()
	_output_line.add_theme_font_size_override("font_size", 13)
	_output_line.add_theme_color_override("font_color", Palette.GOLD)
	_output_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_output_line)


func _stat_box(key: String, caption: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -3)
	var value := Label.new()
	value.text = "0"
	value.add_theme_font_size_override("font_size", 22)
	value.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(value)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	box.add_child(label)
	_stat_values[key] = value
	return box


func _add_filters(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	for spec: Array in [
		["all", "All"],
		["producing", "Producing"],
		["building", "Works"],
		["vacant", "Vacant"],
		["issues", "Issues"],
	]:
		var key: String = String(spec[0])
		var button := Button.new()
		button.text = String(spec[1])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 28)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_press_filter.bind(key))
		_filter_buttons[key] = button
		row.add_child(button)


func _add_footer(column: VBoxContainer) -> void:
	_stores_line = Label.new()
	_stores_line.add_theme_font_size_override("font_size", 11)
	_stores_line.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.8))
	_stores_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stores_line)

	var hint := Label.new()
	hint.text = (
		"Build orders place the nearest idle Builder on the estate; materials are "
		+ "spent on assignment and are not refunded if the work is cancelled. "
		+ "Roads and ports carry yields to the crown."
	)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 0.76))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)


# --- rendering --------------------------------------------------------------


func _update_summary() -> void:
	var counts: Dictionary = _data.get("counts", {})
	var totals: Dictionary = _data.get("totals", {})
	(_stat_values["estates"] as Label).text = str(int(counts.get("estates", 0)))
	(_stat_values["producing"] as Label).text = str(int(counts.get("producing", 0)))
	(_stat_values["output"] as Label).text = str(_total_output(totals))
	(_stat_values["building"] as Label).text = str(int(counts.get("building", 0)))
	_output_line.text = "Projected yield: %s  ·  idle Builders: %d" % [
		ImprovementSystem.output_text(totals),
		int(counts.get("idle_builders", 0)),
	]
	_subtitle.text = "Every owned resource tile, its works and its road to the crown."
	if _province_filter >= 0 and model != null:
		_subtitle.text = "%s · every resource tile in this province." % model.province_name(
			_province_filter
		)
	_stores_line.text = "Stores: %d lumber · %d cast iron · %d bronze · %d paper · %d grain" % [
		int(stockpile.get("lumber", 0)),
		int(stockpile.get("castIron", 0)),
		int(stockpile.get("bronze", 0)),
		int(stockpile.get("paper", 0)),
		int(stockpile.get("grain", 0)),
	]


func _total_output(totals: Dictionary) -> int:
	var total: int = 0
	for raw: Variant in totals.keys():
		total += int(totals[raw])
	return total


func _press_filter(key: String) -> void:
	_filter = key
	_sync_filters()
	_apply_filter()


func _sync_filters() -> void:
	for key: String in _filter_buttons.keys():
		var button: Button = _filter_buttons[key]
		button.set_pressed_no_signal(key == _filter)


func _apply_filter() -> void:
	_clear_rows()
	var groups: Array = _data.get("groups", [])
	var shown: int = 0
	for group: Dictionary in groups:
		if _province_filter >= 0 and int(group["id"]) != _province_filter:
			continue
		var rows: Array[Dictionary] = []
		for row: Dictionary in group["rows"]:
			if _matches(row):
				rows.append(row)
		if rows.is_empty():
			continue
		shown += rows.size()
		_add_group(group, rows)
	if shown == 0:
		var empty := Label.new()
		empty.text = "No estates match this view."
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_rows.add_child(empty)


func _matches(row: Dictionary) -> bool:
	match _filter:
		"producing":
			return int(row["output"]) > 0
		"building":
			return bool(row["working"])
		"vacant":
			return String(row["status"]) == "vacant"
		"issues":
			return String(row["status"]) in ["disconnected", "unprospected"]
	return true


func _add_group(group: Dictionary, rows: Array[Dictionary]) -> void:
	var heading := Label.new()
	heading.text = "%s  ·  %d estate%s  ·  %d producing" % [
		String(group["name"]).to_upper(),
		rows.size(),
		"" if rows.size() == 1 else "s",
		int(group["producing"]),
	]
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Palette.GOLD_DIM)
	_rows.add_child(heading)
	for row: Dictionary in rows:
		var item := ImprovementRow.new()
		item.compact = HudLayout.is_compact(get_viewport_rect().size)
		item.build_pressed.connect(func(tile: Vector2i) -> void: action_pressed.emit("build", tile))
		item.cancel_pressed.connect(func(tile: Vector2i) -> void: action_pressed.emit("cancel", tile))
		item.focus_pressed.connect(func(tile: Vector2i) -> void: focus_pressed.emit(tile))
		_rows.add_child(item)
		item.setup(row)


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
