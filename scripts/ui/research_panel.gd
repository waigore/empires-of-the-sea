class_name ResearchPanel
extends LedgerFrame
## The college ledger: a goal strip, the research slots with their funding and
## progress, plus the advances open now and the techs already known (wiki:
## research-state, tech-tree § Research Model). Presentation only — every button
## emits an intent and the economy controller asks the rules layer (REQ-P2-03);
## the sheet, masthead and phone profile are LedgerFrame's (REQ-P3-01). The
## queue and catalogue desks own their lists ([ResearchQueueDesk],
## [ResearchCatalogPages]).
##
## Repaints are in place: a funding change rewrites the slot's own line, so the
## gauge animates from where it stood.
##
## Height is the sheet's own rule (DR-20261119-02, DR-20261120-03): the college
## budgets the plate it stands in, never the dock the dossiers ride; a handset
## trades the goal strip's own row for catalogue room; and the plate is never
## asked to be taller than its box (REQ-P1-07, REQ-P5-07).

signal assign_requested(tech_id: String)
signal cancel_requested(slot: int)
signal funding_requested(slot: int)
signal goal_changed(tech_id: String)
## The college's one press: every study under way takes `preset` in one act
## (DR-20261118-26).
signal funding_all_requested(preset: String)
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
## The row the slots heading shares with the tree door — and, on a phone, with
## the goal strip, so the college spends one row on chrome instead of two
## (DR-20261120-03).
var _head_row: HBoxContainer = null
## The college's one door into the full-screen chart (DR-20261115-15).
var _tree_door: Button = null
## The queue's own window: every slot row, scrolled when a handset cannot hold
## them all beside the lists (DR-20261119-02).
var _slots_scroll: ScrollContainer = null
var _slots_body: VBoxContainer = null
## The one press that takes every study to a preset, priced before it signs
## (DR-20261118-26).
var _fund: ResearchFundPress = null
var _tabs: TabContainer = null
var _available_body: VBoxContainer = null
var _known_body: VBoxContainer = null
## Slot index -> its persistent row (REQ-P1-05).
var _slot_rows: Dictionary = {}
## Available / Known desks — paint keys live with the pages (REQ-P3-01).
var _pages: ResearchCatalogPages = ResearchCatalogPages.new()
## The room the last fit budgeted against, so a plate that changes size is
## re-read once and not every frame (DR-20261120-03).
var _last_room: float = -1.0
## What the queue spends a turn, as the walk priced it, so a profile change
## re-reads the heading without running the walk again (DR-20261120-03).
var _spend_gold: int = 0
var _spend_rp: int = 0
## A second fit is already waiting on the frame.
var _settling: bool = false
## The compact profile the sheet last laid out in, so a heading re-read names its
## figure the way that sheet prints it (DR-20261120-03).
var _compact: bool = false


func _init() -> void:
	title_text = "THE COLLEGE"


## The box the college is laid in can change without the viewport changing (a
## safe-area inset, a drag, a plate that re-lays), so the sheet's own size is the
## reading that re-budgets — the viewport's is not (REQ-P1-07).
func _ready() -> void:
	super()
	var box: Control = get_parent() as Control
	if box != null:
		box.resized.connect(_on_box_resized)


## The pages take the room the sheet leaves; the fit is `ResearchSheetFit`'s, so
## the panel only measures and applies it (REQ-P1-07).
func _fit_to_viewport() -> void:
	if _tabs == null or _slots_scroll == null or not is_inside_tree():
		return
	super._fit_to_viewport()
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	var room: float = ResearchSheetFit.room(self, compact)
	_last_room = room
	var fit: Dictionary = ResearchSheetFit.split(
		_column, _slots_scroll, _tabs, _slots_body, room,
		get_theme_stylebox("panel").get_minimum_size().y
	)
	# A fit taken before the frame lays the sheet out reads one-line wrapped lines;
	# one more pass, after the layout, reads the sheet as it stands (DR-20261120-03).
	if _settling:
		_settling = false
	else:
		var after: Callable = Callable(self, "_fit_to_viewport")
		if not get_tree().process_frame.is_connected(after):
			_settling = true
			get_tree().process_frame.connect(after, CONNECT_ONE_SHOT)
	_slots_scroll.custom_minimum_size = Vector2(0.0, float(fit["slots"]))
	_tabs.custom_minimum_size = Vector2(0.0, float(fit["tabs"]))
	# A page or a wrapped line can stand taller than the fit measured it: the window
	# gives the excess up, because it scrolls and the plate does not (DR-20261120-03).
	var over: float = get_combined_minimum_size().y - room
	if over > 0.5:
		_slots_scroll.custom_minimum_size.y = maxf(float(fit["slots"]) - over, 0.0)


## A plate that re-lays re-budgets once: the sheet's own size moved, so the room
## the fit was made for is not the room the crown is reading it in.
func _on_box_resized() -> void:
	if not is_inside_tree():
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	if absf(ResearchSheetFit.room(self, compact) - _last_room) > 0.5:
		_fit_deferred()


## Phone chrome: a 411-point sheet cannot carry a standing line, a goal prompt and
## three full-height slot rows above the list. The goal strip gives up its own row
## — it rides the slots heading, whose figure loses the caption the rows under it
## already give — so the sheet spends one row on chrome where it spent two
## (DR-20261120-03).
func _apply_profile(compact: bool) -> void:
	_compact = compact
	if _summary != null:
		_summary.visible = not compact
	if _goal_row != null:
		_goal_row.visible = not compact or not _goal.is_empty()
		_goal_row.set_compact(compact)
		_goal_row.ride(_column, _head_row, compact)
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
	if _fund != null:
		_fund.set_compact(compact)
	_slots_heading.text = ResearchBatch.heading_line(_spend_gold, _spend_rp, _compact)


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
	_head_row = HBoxContainer.new()
	_head_row.add_theme_constant_override("separation", 8)
	_slots_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head_row.add_child(_slots_heading)
	_tree_door = UiRowBuilder.button("TECH TREE ›", 28.0, 118.0, 11)
	_tree_door.tooltip_text = "Open the whole tree, every advance and its road"
	_tree_door.pressed.connect(func() -> void: tree_requested.emit())
	_head_row.add_child(_tree_door)
	column.add_child(_head_row)

	# The queue keeps a window of its own so a handset can give the lists their
	# floor without clipping a slot row: the window scrolls and the rows are
	# never redrawn (DR-20261119-02, REQ-P5-07).
	_slots_scroll = ScrollContainer.new()
	_slots_scroll.name = "Slots"
	_slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_slots_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_slots_scroll)
	_slots_body = VBoxContainer.new()
	_slots_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_body.add_theme_constant_override("separation", 4)
	_slots_scroll.add_child(_slots_body)

	# The college's one press sits under the slots it funds, the way the yards'
	# batch press sits under their rows (DR-20261118-26).
	_fund = ResearchFundPress.new()
	_fund.funding_all_requested.connect(
		func(preset: String) -> void: funding_all_requested.emit(preset)
	)
	column.add_child(_fund)

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


## The college's one press, so a test reads the preset it would file instead of
## walking the sheet's children (REQ-P3-02).
func fund_press() -> ResearchFundPress:
	return _fund


## Steers the queue toward `tech_id`; "" (or an unknown id) clears the goal.
## The goal spends nothing and rides no research order, but it is kept with the
## campaign, so the ledger reopens where the player left it (wiki: tech-tree
## § Goal slot; DR-20261111-21).
##
## The repaint re-reads every reading the sheet was drawn with, the crown's leader
## included: a goal tap must not quietly drop Victoria's ×1.15 from the slots and
## the press line, or the sheet would price a turn the phase does not pay
## (wiki: leader-bonuses; REQ-P2-03).
func set_goal(tech_id: String) -> void:
	var next: String = TechOrder.normalize(tech_id)
	if next == _goal:
		return
	_goal = next
	if _state != null:
		_state.goal = next
	goal_changed.emit(_goal)
	refresh(_state, _treasury, _boost, _leader)


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
	var open: Array[String] = ResearchCatalogPages.open_advances(_state, _goal)
	_goal_row.render(_state, _goal)
	_fill_slots()
	_pages.paint_available(
		_available_body, _state, open, _goal,
		func(id: String) -> void: assign_requested.emit(id),
		func(id: String) -> void: set_goal("" if id == _goal else id)
	)
	_pages.paint_known(_known_body, _state, _goal)
	_tabs.set_tab_title(0, "AVAILABLE (%d)" % open.size())
	_tabs.set_tab_title(1, "KNOWN (%d)" % _state.unlocked_ids().size())
	_hint.text = ResearchBatch.hint_line(open.size(), _state.free_slot(), _notice.visible)
	_fit_deferred()


## The height budget shifts as slots fill, so the tabs are re-measured once the
## frame has laid the rows out.
func _fit_deferred() -> void:
	if is_inside_tree():
		call_deferred("_fit_to_viewport")


## One persistent row per slot — `ResearchQueueDesk` walks and mounts; the panel
## rewrites the heading, notice and press from the same spend totals.
func _fill_slots() -> void:
	var spend: Dictionary = ResearchQueueDesk.fill(
		_slots_body, _slot_rows, _state, _treasury, _boost, _leader,
		func(slot: int) -> void: cancel_requested.emit(slot),
		func(slot: int) -> void: funding_requested.emit(slot)
	)
	_spend_gold = int(spend["gold"])
	_spend_rp = int(spend["rp"])
	_slots_heading.text = ResearchBatch.heading_line(_spend_gold, _spend_rp, _compact)
	_notice.text = ResearchQueueDesk.notice_line(_state, int(spend["unpaid"]))
	_notice.visible = not _notice.text.is_empty()
	if _fund != null:
		_fund.render(_state, _treasury, _boost, _leader)
