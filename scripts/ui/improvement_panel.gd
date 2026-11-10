class_name ImprovementPanel
extends Control
## The crown's estates ledger: a whole-realm view of improvements, yields,
## active works and vacant resource tiles, with one-click Builder dispatch.
## The panel renders ImprovementLedger rows and emits intents; MapScreen owns
## the rules call and the camera (REQ-P3-02, REQ-P3-03). Summary and filter strip
## live in EstatesHead; grouping/filtering in EstateLedger.

signal action_pressed(action: String, tile: Vector2i)
signal focus_pressed(tile: Vector2i)

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
var _head: EstatesHead = null
var _subtitle: Label = null
var _data: Dictionary = {}
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
	_overlay.visible = true
	if _head != null:
		_head.set_filter(filter_key)
	refresh()


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
	_head.render(_data, stockpile)
	_subtitle.text = _subtitle_text()
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
	# The pause seal owns the rail's first 46 px; start after it so the manor
	# medallion is not hidden under the MENU button.
	_toggle.offset_left = 70.0
	_toggle.offset_top = 132.0
	_toggle.offset_right = 176.0
	_toggle.offset_bottom = 176.0
	_toggle.add_theme_font_size_override("font_size", 14)
	_toggle.tooltip_text = "The crown's estates and works"
	ChromeIcons.apply(_toggle, "manor", 20)
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

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 42)
	_margin.add_theme_constant_override("margin_right", 42)
	_margin.add_theme_constant_override("margin_top", 88)
	_margin.add_theme_constant_override("margin_bottom", 34)
	_overlay.add_child(_margin)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.98), Palette.GOLD_DIM, 1, 4, Vector4(20, 16, 20, 16))
	)
	_margin.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	column.add_child(_header())
	_head = EstatesHead.new()
	_head.filter_selected.connect(_press_filter)
	column.add_child(_head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	scroll.add_child(_rows)

	column.add_child(_footer())


func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

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
	return header


func _footer() -> Control:
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 4)
	var hint := Label.new()
	hint.text = (
		"Build orders place the nearest idle Builder on the estate; materials are "
		+ "spent on assignment and are not refunded if the work is cancelled. "
		+ "Roads and ports carry yields to the crown."
	)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 0.76))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(hint)
	return footer


# --- rendering --------------------------------------------------------------


func _subtitle_text() -> String:
	if _province_filter >= 0 and model != null:
		return "%s · every resource tile in this province." % model.province_name(_province_filter)
	return "Every owned resource tile, its works and its road to the crown."


func _press_filter(_key: String) -> void:
	_apply_filter()


func _apply_filter() -> void:
	_clear_rows()
	if _head == null:
		return
	var groups: Array[Dictionary] = EstateLedger.grouped(_data)
	var shown: int = 0
	for group: Dictionary in EstateLedger.in_province(groups, _province_filter):
		var rows: Array[Dictionary] = EstateLedger.matching(group["rows"], _head.filter)
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


## Phone-sized filter buttons, exposed so layout tests assert tap targets
## instead of reaching into the EstatesHead child (REQ-P3-02).
func filter_buttons() -> Dictionary:
	return _head.filter_buttons() if _head != null else {}


## Compact estates card: thin margins, thumb-sized filters, and the summary
## block traded for list rows (the group headings still count each region and
## the projection line still carries the yield).
func set_compact(compact: bool) -> void:
	if _margin == null:
		return
	_margin.add_theme_constant_override("margin_left", 12 if compact else 42)
	_margin.add_theme_constant_override("margin_right", 12 if compact else 42)
	_margin.add_theme_constant_override("margin_top", 66 if compact else 88)
	_margin.add_theme_constant_override("margin_bottom", 8 if compact else 34)
	if _head != null:
		_head.set_compact(compact)
	if _subtitle != null:
		_subtitle.visible = not compact
