class_name ResearchPanel
extends PanelContainer
## The college ledger: a goal strip, the research slots with their funding and
## progress, plus the advances open now and the techs already known (wiki:
## research-state, tech-tree § Research Model — the goal slot sorts the display
## and spends nothing). Presentation only — every button emits an intent and the
## economy controller asks the rules layer (REQ-P2-03).
##
## Repaints are in place: one ResearchSlotRow lives per slot, and each page is
## rebuilt only when its list actually changes. A funding change therefore
## rewrites the slot's own line — nothing reloads, and the gauge animates from
## where it stood (REQ-P1-05).

signal assign_requested(tech_id: String)
signal cancel_requested(slot: int)
signal funding_requested(slot: int)
signal goal_changed(tech_id: String)
signal close_pressed

var _state: ResearchState = null
## Tech id -> spy-network percent, set by refresh (DR-20261110-03).
var _boost: Dictionary = {}
## The goal tech, mirrored from `_state.goal` on every refresh. It sorts the
## queue and funds nothing; the state keeps it so a load reopens the same order
## (wiki: tech-tree § Goal slot; DR-20261111-21).
var _goal: String = ""
var _treasury: int = 0
var _column: VBoxContainer = null
var _summary: Label = null
var _goal_row: HBoxContainer = null
var _slots_heading: Label = null
var _slots_body: VBoxContainer = null
var _tabs: TabContainer = null
var _available_body: VBoxContainer = null
var _known_body: VBoxContainer = null
var _hint: Label = null
var _title: Label = null
var _close: Button = null
## Slot index -> its persistent row (REQ-P1-05).
var _slot_rows: Dictionary = {}
## Signatures of what each rebuilt region last drew, so a repaint that changes
## none of them touches no widget.
var _goal_key: String = ""
var _available_key: String = ""
var _known_key: String = ""


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(20, 14, 20, 14))
	)
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


## The tab body gives way so the header, slots and Close stay put: the pages
## take the room the sheet leaves, and a phone drops the standing hint instead
## of pushing content past the panel's edge. The masthead, standing line and
## empty goal prompt also yield, so the queue and the lists keep the height
## (REQ-P1-07).
func _fit_to_viewport() -> void:
	if _tabs == null or not is_inside_tree():
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	set_compact(compact)
	var top: float = 64.0 if compact else PanelDock.TOP
	var bottom: float = 10.0 if compact else absf(PanelDock.BOTTOM)
	var room: float = maxf(get_viewport_rect().size.y - top - bottom, 0.0)
	var chrome: float = get_combined_minimum_size().y - _tabs.custom_minimum_size.y
	_tabs.custom_minimum_size = Vector2(0.0, clampf(room - chrome, 0.0, 300.0))


## Phone chrome: a 411-point sheet cannot carry a 24 pt masthead, a standing
## line, a goal prompt and three full-height slot rows above the list.
func set_compact(compact: bool) -> void:
	if _tabs == null:
		return
	var margins: Vector4 = Vector4(12, 8, 12, 8) if compact else Vector4(20, 14, 20, 14)
	add_theme_stylebox_override(
		"panel", UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, margins)
	)
	if _title != null:
		_title.add_theme_font_size_override("font_size", 20 if compact else 24)
	if _close != null:
		_close.custom_minimum_size = Vector2(64, 40) if compact else Vector2(78, 34)
	if _summary != null:
		_summary.visible = not compact
	if _hint != null:
		_hint.visible = not compact
	if _column != null:
		_column.add_theme_constant_override("separation", 4 if compact else 8)
	if _goal_row != null:
		_goal_row.visible = not compact or not _goal.is_empty()
	if _slots_heading != null:
		_slots_heading.add_theme_font_size_override("font_size", 10 if compact else 11)
	if _slots_body != null:
		_slots_body.add_theme_constant_override("separation", 2 if compact else 4)
	for row: Variant in _slot_rows.values():
		if row is ResearchSlotRow:
			(row as ResearchSlotRow).set_compact(compact)


func _build() -> void:
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	add_child(_column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_column.add_child(header)

	var title := Label.new()
	title.text = "THE COLLEGE"
	title.add_theme_font_override("font", UiTheme.serif())
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = title
	header.add_child(title)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(78, 34)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(func() -> void: close_pressed.emit())
	_close = close
	header.add_child(close)

	_summary = _label("", 14, Palette.TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_summary)

	_goal_row = HBoxContainer.new()
	_goal_row.add_theme_constant_override("separation", 8)
	_column.add_child(_goal_row)

	_slots_heading = _label("RESEARCH SLOTS", 11, Palette.TEXT_DIM)
	_column.add_child(_slots_heading)

	_slots_body = VBoxContainer.new()
	_slots_body.add_theme_constant_override("separation", 4)
	_column.add_child(_slots_body)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 300)
	_tabs.add_theme_color_override("font_selected_color", Palette.GOLD_PALE)
	_tabs.add_theme_color_override("font_unselected_color", Palette.TEXT_DIM)
	_column.add_child(_tabs)
	_available_body = _add_page("AVAILABLE")
	_known_body = _add_page("KNOWN")

	_hint = _label("", 11, Palette.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_hint)


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


## The goal tech, or "" when the queue is unsorted.
func goal_tech() -> String:
	return _goal


## Steers the queue toward `tech_id`; "" (or an unknown id) clears the goal.
## The goal spends nothing and rides no research order, but it is kept with the
## campaign, so the ledger reopens where the player left it (wiki: tech-tree
## § Goal slot; DR-20261111-21).
func set_goal(tech_id: String) -> void:
	var next: String = TechOrder.normalize(tech_id)
	if next == _goal:
		return
	_goal = next
	if _state != null:
		_state.goal = next
	goal_changed.emit(_goal)
	refresh(_state, _treasury, _boost)


## Rebuilds the goal strip, slots, open advances and known techs from live
## research state. `boost` carries the spy network's per-tech percent
## (DR-20261110-03); it marks the slots it lifts so a faster study is never
## silent (REQ-P5-05).
func refresh(state: ResearchState, treasury: int, boost: Dictionary = {}) -> void:
	_state = state
	_treasury = treasury
	_boost = boost
	if _tabs == null or _state == null:
		return
	_goal = TechOrder.normalize(_state.goal)
	_state.ensure_slots()
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
	_fill_goal()
	_fill_slots()
	_fill_available(open)
	_fill_known()
	_tabs.set_tab_title(0, "AVAILABLE (%d)" % open.size())
	_tabs.set_tab_title(1, "KNOWN (%d)" % _state.unlocked_ids().size())
	_hint.text = _hint_text(open.size())
	_fit_deferred()


## The height budget shifts as slots fill, so the tabs are re-measured once the
## frame has laid the rows out.
func _fit_deferred() -> void:
	if is_inside_tree():
		call_deferred("_fit_to_viewport")


## The goal strip: the plate, the advance it steers toward, its standing and a
## Clear button. An empty goal explains itself rather than leaving a blank line.
func _fill_goal() -> void:
	var key: String = "%s|%s" % [_goal, _goal_standing()]
	if key == _goal_key:
		return
	_goal_key = key
	_clear(_goal_row)
	var tag := _label("GOAL", 11, Palette.TEXT_DIM)
	tag.custom_minimum_size = Vector2(46, 0)
	_goal_row.add_child(tag)
	if _goal.is_empty():
		var hint := _label(
			"No goal — set one to sort the queue by the path that reaches it.",
			12, Palette.TEXT_DIM
		)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_goal_row.add_child(hint)
		return
	_goal_row.add_child(ResearchRow.icon(_goal, 30.0))
	var name_label := _label(TechCatalog.display_name(_goal), 14, Palette.GOLD_PALE)
	name_label.tooltip_text = TechCatalog.effect_text(_goal)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal_row.add_child(name_label)
	var standing := _label(_goal_standing(), 11, Palette.TEXT_DIM)
	standing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_goal_row.add_child(standing)
	var clear := Button.new()
	clear.text = "Clear"
	clear.custom_minimum_size = Vector2(64, 30)
	clear.add_theme_font_size_override("font_size", 12)
	clear.tooltip_text = "Keep the goal out of the queue's order"
	clear.pressed.connect(func() -> void: set_goal(""))
	_goal_row.add_child(clear)


## How far the goal has come: known, in a slot with its RP, or not yet begun.
func _goal_standing() -> String:
	if _state == null:
		return ""
	if _state.is_unlocked(_goal):
		return "reached"
	if _state.is_active(_goal):
		return "%d / %d RP" % [_state.progress_of(_goal), TechCatalog.cost(_goal)]
	return "%d RP" % TechCatalog.cost(_goal)


## One persistent row per slot, rewritten in place. The heading carries what the
## whole college spends and buys each turn, so the cost of research is never
## silent (REQ-P1-05).
##
## Each slot is previewed against the treasury the ones before it leave behind,
## exactly as the Research phase spends in slot order — so a slot the treasury
## cannot reach shows as unpaid here rather than promising points it will not
## earn.
func _fill_slots() -> void:
	var gold: int = 0
	var points: int = 0
	var left: int = _treasury
	for index in _state.slots.size():
		var row: ResearchSlotRow = _slot_rows.get(index)
		if row == null:
			row = ResearchSlotRow.new(index)
			row.cancel_pressed.connect(func(slot: int) -> void: cancel_requested.emit(slot))
			row.funding_pressed.connect(func(slot: int) -> void: funding_requested.emit(slot))
			_slots_body.add_child(row)
			_slot_rows[index] = row
		row.update(_state, _boost, left)
		gold += row.gold_next()
		points += row.rp_next()
		left -= row.gold_next()
	_slots_heading.text = _slots_spend_text(gold, points)


func _slots_spend_text(gold: int, points: int) -> String:
	if gold <= 0 and points <= 0:
		return "RESEARCH SLOTS · nothing is funded"
	return "RESEARCH SLOTS · %s ducats & %s RP a turn" % [
		TextFormat.thousands(gold), TextFormat.thousands(points),
	]


## Rebuilt only when the open list, the goal or the free slot changes; a
## funding change repaints none of it.
func _fill_available(techs: Array[String]) -> void:
	var key: String = "%s|%s|%d" % [";".join(techs), _goal, _state.free_slot()]
	if key == _available_key:
		return
	_available_key = key
	_rebuild(_available_body, func() -> void:
		if techs.is_empty():
			_available_body.add_child(_label(
				"No advances are open — finish a prerequisite or chart a resource.",
				12, Palette.TEXT_DIM
			))
			return
		for tech_id: String in techs:
			_available_body.add_child(ResearchRow.available(
				_state, tech_id,
				func(id: String) -> void: assign_requested.emit(id),
				_goal,
				func(id: String) -> void: set_goal("" if id == _goal else id)
			))
	)


func _fill_known() -> void:
	var known: Array[String] = _state.unlocked_ids()
	var key: String = "%s|%s" % [";".join(known), _goal]
	if key == _known_key:
		return
	_known_key = key
	_rebuild(_known_body, func() -> void:
		if known.is_empty():
			_known_body.add_child(_label(
				"Nothing is known beyond the old learning.", 12, Palette.TEXT_DIM
			))
			return
		for tech_id: String in TechOrder.sorted(known, _goal):
			_known_body.add_child(ResearchRow.known(tech_id, _goal))
	)


## Researchable, not already in a slot, goal path first.
func _open_advances() -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in _state.researchable():
		if not _state.is_active(tech_id):
			out.append(tech_id)
	return TechOrder.sorted(out, _goal)


func _hint_text(open_count: int) -> String:
	if _state.free_slot() < 0 and open_count > 0:
		return "Every slot is at study — cancel one to take another path."
	return "Funding is paid every turn; cancelling a slot forfeits its progress."


## Replaces a page's rows but keeps the player's place in the list: a rebuild
## that jumped back to the top would read as a reload.
func _rebuild(body: Container, paint: Callable) -> void:
	var scroll := body.get_parent() as ScrollContainer
	var keep: int = scroll.scroll_vertical if scroll != null else 0
	_clear(body)
	paint.call()
	if scroll != null:
		scroll.set_deferred("scroll_vertical", keep)


func _clear(body: Container) -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
