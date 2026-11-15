class_name ResearchPanel
extends LedgerFrame
## The college ledger: a goal strip, the research slots with their funding and
## progress, plus the advances open now and the techs already known (wiki:
## research-state, tech-tree § Research Model — the goal slot sorts the display
## and spends nothing). Presentation only — every button emits an intent and the
## economy controller asks the rules layer (REQ-P2-03). The sheet, masthead and
## phone profile are LedgerFrame's (REQ-P3-01).
##
## Repaints are in place: one ResearchSlotRow lives per slot, and each page is
## rebuilt only when its list actually changes. A funding change therefore
## rewrites the slot's own line — nothing reloads, and the gauge animates from
## where it stood (REQ-P1-05).

signal assign_requested(tech_id: String)
signal cancel_requested(slot: int)
signal funding_requested(slot: int)
signal goal_changed(tech_id: String)
## The college's door into the full-screen chart: the sheet hands the HUD the
## state it already reads, and the chart opens over the ledger (DR-20261115-15).
signal tree_requested

var _state: ResearchState = null
## Tech id -> spy-network percent, set by refresh (DR-20261110-03).
var _boost: Dictionary = {}
## The crown's leaderKey, whose published funding multiplier the RP figures
## include (wiki: leader-bonuses — Victoria).
var _leader: String = ""
## The goal tech, mirrored from `_state.goal` on every refresh. It sorts the
## queue and funds nothing; the state keeps it so a load reopens the same order
## (wiki: tech-tree § Goal slot; DR-20261111-21).
var _goal: String = ""
var _treasury: int = 0
var _summary: Label = null
## The rule behind an unpaid study, named under the summary whenever a slot
## starves. Always visible — a phone hides the standing hint, and a hover-only
## rule is unreachable on touch (REQ-P1-05, REQ-P5-05).
var _notice: Label = null
var _goal_row: ResearchGoalStrip = null
var _slots_heading: Label = null
## The college's one door into the full-screen chart (DR-20261115-15).
var _tree_door: Button = null
var _slots_body: VBoxContainer = null
var _tabs: TabContainer = null
var _available_body: VBoxContainer = null
var _known_body: VBoxContainer = null
## Slot index -> its persistent row (REQ-P1-05).
var _slot_rows: Dictionary = {}
## Signatures of what each rebuilt region last drew, so a repaint that changes
## none of them touches no widget.
var _available_key: String = ""
var _known_key: String = ""


func _init() -> void:
	title_text = "THE COLLEGE"


## The tab body gives way so the header, slots and Close stay put: the pages
## take the room the sheet leaves, and a phone drops the standing hint instead
## of pushing content past the panel's edge. The masthead, standing line and
## empty goal prompt also yield, so the queue and the lists keep the height
## (REQ-P1-07).
func _fit_to_viewport() -> void:
	if _tabs == null or not is_inside_tree():
		return
	super._fit_to_viewport()
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	var top: float = 64.0 if compact else PanelDock.TOP
	var bottom: float = 10.0 if compact else absf(PanelDock.BOTTOM)
	var room: float = maxf(get_viewport_rect().size.y - top - bottom, 0.0)
	var chrome: float = get_combined_minimum_size().y - _tabs.custom_minimum_size.y
	_tabs.custom_minimum_size = Vector2(0.0, clampf(room - chrome, 0.0, 300.0))


## Phone chrome: a 411-point sheet cannot carry a 24 pt masthead, a standing
## line, a goal prompt and three full-height slot rows above the list. The
## masthead and standing line are LedgerFrame's; the college's own rows follow.
func _apply_profile(compact: bool) -> void:
	if _summary != null:
		_summary.visible = not compact
	if _goal_row != null:
		_goal_row.visible = not compact or not _goal.is_empty()
	if _slots_heading != null:
		_slots_heading.add_theme_font_size_override("font_size", 10 if compact else 11)
	if _tree_door != null:
		_tree_door.custom_minimum_size = Vector2(112.0 if compact else 118.0, 26.0 if compact else 28.0)
		_tree_door.add_theme_font_size_override("font_size", 10 if compact else 11)
	if _slots_body != null:
		_slots_body.add_theme_constant_override("separation", 2 if compact else 4)
	for row: Variant in _slot_rows.values():
		if row is ResearchSlotRow:
			(row as ResearchSlotRow).set_compact(compact)


func _build_body(column: VBoxContainer) -> void:
	_summary = UiRowBuilder.label("", 14, Palette.TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)

	_notice = UiRowBuilder.label("", 12, Palette.CRIMSON)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	column.add_child(_notice)

	_goal_row = ResearchGoalStrip.new()
	_goal_row.clear_pressed.connect(func() -> void: set_goal(""))
	column.add_child(_goal_row)

	_slots_heading = UiRowBuilder.label("RESEARCH SLOTS", 11, Palette.TEXT_DIM)
	# The whole tree is a full-screen chart of its own, so the college keeps one
	# clear door beside the slots heading: it costs the lists no height, and the
	# sheet's room stays for the slots and the two lists (DR-20261115-15).
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	_slots_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(_slots_heading)
	_tree_door = UiRowBuilder.button("TECH TREE ›", 28.0, 118.0, 11)
	_tree_door.tooltip_text = "Open the whole tree, every advance and its road"
	_tree_door.pressed.connect(func() -> void: tree_requested.emit())
	head_row.add_child(_tree_door)
	column.add_child(head_row)

	_slots_body = VBoxContainer.new()
	_slots_body.add_theme_constant_override("separation", 4)
	column.add_child(_slots_body)

	_tabs = _make_tabs(300.0)
	_available_body = _add_tab(_tabs, "AVAILABLE", VBoxContainer.new())
	_known_body = _add_tab(_tabs, "KNOWN", VBoxContainer.new())

	_make_hint("")


func select_tab(index: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


## The goal tech, or "" when the queue is unsorted.
func goal_tech() -> String:
	return _goal


## The live research state the sheet reads, so the full-screen chart opens on
## the same college the ledger shows (DR-20261115-15).
func research_state() -> ResearchState:
	return _state


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
func refresh(
	state: ResearchState, treasury: int, boost: Dictionary = {}, leader: String = ""
) -> void:
	_state = state
	_treasury = treasury
	_boost = boost
	_leader = leader
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
	_goal_row.render(_state, _goal)
	_fill_slots()
	_fill_available(open)
	_fill_known()
	_tabs.set_tab_title(0, "AVAILABLE (%d)" % open.size())
	_tabs.set_tab_title(1, "KNOWN (%d)" % _state.unlocked_ids().size())
	_hint.text = _hint_text(open.size(), _notice.visible)
	_fit_deferred()


## The height budget shifts as slots fill, so the tabs are re-measured once the
## frame has laid the rows out.
func _fit_deferred() -> void:
	if is_inside_tree():
		call_deferred("_fit_to_viewport")


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
	var unpaid: int = 0
	var left: int = _treasury
	for index in _state.slots.size():
		var row: ResearchSlotRow = _slot_rows.get(index)
		if row == null:
			row = ResearchSlotRow.new(index)
			row.cancel_pressed.connect(func(slot: int) -> void: cancel_requested.emit(slot))
			row.funding_pressed.connect(func(slot: int) -> void: funding_requested.emit(slot))
			_slots_body.add_child(row)
			_slot_rows[index] = row
		row.update(_state, _boost, left, _leader)
		gold += row.gold_next()
		points += row.rp_next()
		left -= row.gold_next()
		if row.unpaid_next():
			unpaid += 1
	_slots_heading.text = _slots_spend_text(gold, points)
	_set_notice(unpaid)


## The court's studies, and the rule that stops the ones the purse cannot pay:
## the treasury stops at the floor the techs set, so a starved row reads as rule
## and not as a broken purse (wiki: tech-tree-labour-economy § money_lending,
## banking; REQ-P5-05).
func _set_notice(unpaid: int) -> void:
	_notice.visible = unpaid > 0
	if unpaid <= 0:
		_notice.text = ""
		return
	var subject: String = "1 study goes" if unpaid == 1 else "%d studies go" % unpaid
	_notice.text = "%s unpaid — %s." % [
		subject, LedgerText.research_floor_line(_state.treasury_floor()),
	]


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
			_available_body.add_child(UiRowBuilder.label(
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
			_known_body.add_child(UiRowBuilder.label(
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


func _hint_text(open_count: int, starved: bool) -> String:
	if starved:
		return "A study the treasury cannot cover keeps its slot and its points; it only waits."
	if _state.free_slot() < 0 and open_count > 0:
		return "Every slot is at study — cancel one to take another path."
	return "Funding is paid every turn; cancelling a slot forfeits its progress."


## Replaces a page's rows but keeps the player's place in the list: a rebuild
## that jumped back to the top would read as a reload.
func _rebuild(body: Container, paint: Callable) -> void:
	var scroll := body.get_parent() as ScrollContainer
	var keep: int = scroll.scroll_vertical if scroll != null else 0
	UiRowBuilder.clear(body)
	paint.call()
	if scroll != null:
		scroll.set_deferred("scroll_vertical", keep)
