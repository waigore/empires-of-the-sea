class_name ResearchTreeTab
extends VBoxContainer
## The college's whole tree: every catalog advance, filtered by branch, with
## what the crown still lacks for it and the road the goal walks (wiki:
## tech-tree § Categories, § Prerequisites, § Research Model — goal slot).
##
## Owns no rules state and orders nothing: the panel hands it a snapshot and it
## emits the goal intent, exactly as the AVAILABLE rows do (REQ-P3-02). The
## chips stay put while the list scrolls, so a phone never scrolls back to its
## filter (REQ-P1-07).

signal goal_requested(tech_id: String)

const CATEGORY_ALL: String = ""

## The branch the reader is looking at; "" is the whole tree.
var category: String = CATEGORY_ALL

var _state: ResearchState = null
var _goal: String = ""
var _summary: Label = null
var _road: Label = null
var _chips: Dictionary = {}
var _body: VBoxContainer = null
## What the last paint drew, so a repaint that changes none of it touches no row.
var _key: String = ""


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	_summary = UiRowBuilder.wrapped_line("", 12, Palette.TEXT_DIM)
	add_child(_summary)
	add_child(_chip_row())
	_road = UiRowBuilder.wrapped_line("", 12, Palette.GOLD)
	add_child(_road)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	scroll.add_child(_body)


## One scrolling strip of branch chips: seven branches plus the whole tree, so
## the row never wraps and never pushes the list off a phone sheet.
func _chip_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var caption := UiRowBuilder.caption("BRANCH", 9, Palette.TEXT_DIM, 52.0)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 30)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 4)
	scroll.add_child(flow)
	flow.add_child(_chip(CATEGORY_ALL, "All branches"))
	for key: String in TechCatalog.CATEGORIES:
		flow.add_child(_chip(key, TechCatalog.category_short_label(key)))
	return row


func _chip(key: String, caption: String) -> Button:
	var button := UiRowBuilder.button(caption, 30.0, 0.0, 12)
	button.toggle_mode = true
	button.pressed.connect(_press_category.bind(key))
	_chips[key] = button
	return button


func _press_category(key: String) -> void:
	if key == category:
		# The lit chip clears itself, as the roster's craft chips do.
		key = CATEGORY_ALL
	category = key
	_key = ""
	refresh(_state, _goal)


## Repaints the summary, the road and the rows from live research state. The
## goal is the panel's (it owns the intent); this tab only reads it.
func refresh(state: ResearchState, goal: String = "") -> void:
	_state = state
	_goal = TechOrder.normalize(goal)
	if _body == null or _state == null:
		return
	var counts: Dictionary = TechPlan.counts(_state)
	_summary.text = "%d advances · %d known · %d open now · %d at study" % [
		TechCatalog.ids().size(),
		int(counts[TechPlan.State.KNOWN]),
		int(counts[TechPlan.State.OPEN]),
		int(counts[TechPlan.State.STUDYING]),
	]
	_road.text = _road_text()
	_road.visible = not _road.text.is_empty()
	for key: Variant in _chips.keys():
		(_chips[key] as Button).set_pressed_no_signal(String(key) == category)
	var key_text: String = _signature()
	if key_text == _key:
		return
	_key = key_text
	_fill()


## The goal in one sentence, or the invitation when no goal is set: the tree is
## where a player learns the goal slot exists (REQ-P5-03).
func _road_text() -> String:
	if _goal.is_empty():
		return "Set a goal on any advance and the queue walks to it."
	return TechPlan.road_line(_state, _goal)


func _fill() -> void:
	UiRowBuilder.clear(_body)
	var techs: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if category != CATEGORY_ALL and TechCatalog.category(tech_id) != category:
			continue
		techs.append(tech_id)
	techs = TechOrder.sorted(techs, _goal)
	for tech_id: String in techs:
		_body.add_child(ResearchRow.catalog(
			_state, tech_id, _goal,
			func(id: String) -> void: goal_requested.emit(id)
		))


## Everything a row reads: the branch, the goal, what is known, what is at
## study and what the crown has found. A change in any of them repaints.
func _signature() -> String:
	var active: PackedStringArray = []
	for index in _state.slots.size():
		active.append(_state.tech_at(index))
	var revealed: Array = _state.revealed.keys()
	revealed.sort()
	return "%s|%s|%s|%s|%s" % [
		category,
		_goal,
		";".join(_state.unlocked_ids()),
		";".join(active),
		";".join(PackedStringArray(revealed)),
	]


## Phone chrome: the summary line yields its room to the list, and the road
## keeps one wrapped line (REQ-P1-07).
func set_compact(compact: bool) -> void:
	if _summary != null:
		_summary.visible = not compact
	if _road != null:
		_road.add_theme_font_size_override("font_size", 11 if compact else 12)
