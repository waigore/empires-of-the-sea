class_name ResearchPanel
extends PanelContainer
## The college ledger: research slots with their funding and progress, plus the
## advances open now and the techs already known (wiki: research-state,
## tech-tree § Research Model). Presentation only — every button emits an
## intent and the economy controller asks the rules layer (REQ-P2-03).

signal assign_requested(tech_id: String)
signal cancel_requested(slot: int)
signal funding_requested(slot: int)
signal close_pressed

var _state: ResearchState = null
## Tech id -> spy-network percent, set by refresh (DR-20261110-03).
var _boost: Dictionary = {}
var _summary: Label = null
var _slots_body: VBoxContainer = null
var _tabs: TabContainer = null
var _available_body: VBoxContainer = null
var _known_body: VBoxContainer = null
var _hint: Label = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(20, 14, 20, 14))
	)
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


## The tab body gives way on a phone so the header, slots and Close stay put.
func _fit_to_viewport() -> void:
	if _tabs == null:
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	_tabs.custom_minimum_size = Vector2(0.0, 0.0 if compact else 300.0)


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	var title := Label.new()
	title.text = "THE COLLEGE"
	title.add_theme_font_override("font", UiTheme.serif())
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(78, 34)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close)

	_summary = _label("", 14, Palette.TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)

	var slots_heading := _label("RESEARCH SLOTS", 11, Palette.TEXT_DIM)
	column.add_child(slots_heading)

	_slots_body = VBoxContainer.new()
	_slots_body.add_theme_constant_override("separation", 4)
	column.add_child(_slots_body)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 300)
	_tabs.add_theme_color_override("font_selected_color", Palette.GOLD_PALE)
	_tabs.add_theme_color_override("font_unselected_color", Palette.TEXT_DIM)
	column.add_child(_tabs)
	_available_body = _add_page("AVAILABLE")
	_known_body = _add_page("KNOWN")

	_hint = _label("", 11, Palette.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)


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


## Rebuilds slots, open advances and known techs from live research state.
## `boost` carries the spy network's per-tech percent (DR-20261110-03); it marks
## the slots it lifts so a faster study is never silent (REQ-P5-05).
func refresh(state: ResearchState, treasury: int, boost: Dictionary = {}) -> void:
	_state = state
	_boost = boost
	if _tabs == null or _state == null:
		return
	_clear(_slots_body)
	_clear(_available_body)
	_clear(_known_body)
	var active: int = _state.researching().size()
	_summary.text = "%d slot%s · %d at study · %d ducats · %d tech%s known" % [
		_state.slots.size(),
		"" if _state.slots.size() == 1 else "s",
		active,
		treasury,
		_state.unlocked_ids().size(),
		"" if _state.unlocked_ids().size() == 1 else "s",
	]
	var open: Array[String] = _open_advances()
	_fill_slots()
	_fill_available(open)
	_fill_known()
	_tabs.set_tab_title(0, "AVAILABLE (%d)" % open.size())
	_tabs.set_tab_title(1, "KNOWN (%d)" % _state.unlocked_ids().size())
	_hint.text = _hint_text(open.size())


func _fill_slots() -> void:
	for index in _state.slots.size():
		_slots_body.add_child(ResearchRow.slot(
			_state, index,
			func(slot: int) -> void: cancel_requested.emit(slot),
			func(slot: int) -> void: funding_requested.emit(slot),
			SpyNetworks.boost_for(_boost, _state.tech_at(index))
		))


func _fill_available(techs: Array[String]) -> void:
	if techs.is_empty():
		_available_body.add_child(
			_label("No advances are open — finish a prerequisite or chart a resource.", 12, Palette.TEXT_DIM)
		)
		return
	for tech_id: String in techs:
		_available_body.add_child(ResearchRow.available(
			_state, tech_id,
			func(id: String) -> void: assign_requested.emit(id)
		))


func _fill_known() -> void:
	var known: Array[String] = _state.unlocked_ids()
	if known.is_empty():
		_known_body.add_child(_label("Nothing is known beyond the old learning.", 12, Palette.TEXT_DIM))
		return
	for tech_id: String in _sorted(known):
		_known_body.add_child(ResearchRow.known(tech_id))


## Researchable and not already in a slot.
func _open_advances() -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in _state.researchable():
		if not _state.is_active(tech_id):
			out.append(tech_id)
	return _sorted(out)


## Category first (catalog order), then era, then display name.
func _sorted(techs: Array[String]) -> Array[String]:
	var out: Array[String] = techs.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ca: int = TechCatalog.CATEGORIES.find(TechCatalog.category(a))
		var cb: int = TechCatalog.CATEGORIES.find(TechCatalog.category(b))
		if ca != cb:
			return ca < cb
		if TechCatalog.era(a) != TechCatalog.era(b):
			return TechCatalog.era(a) < TechCatalog.era(b)
		return TechCatalog.display_name(a) < TechCatalog.display_name(b)
	)
	return out


func _hint_text(open_count: int) -> String:
	if _state.free_slot() < 0 and open_count > 0:
		return "Every slot is at study — cancel one to take another path."
	return "Funding is paid every turn; cancelling a slot forfeits its progress."


func _clear(body: VBoxContainer) -> void:
	for child in body.get_children():
		child.queue_free()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
