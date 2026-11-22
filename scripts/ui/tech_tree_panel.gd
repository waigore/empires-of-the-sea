class_name TechTreePanel
extends SheetFrame
## The college's whole tree, full screen: every catalog advance laid out left to
## right by its prerequisite depth, its edges drawn, and the aimed advance's
## ancestor road lit gold (wiki: tech-tree § Prerequisites, § Research Model;
## DR-20261115-15). Selecting an advance reads what it grants and aims the
## queue at it; the goal is the ledger's own state, so this sheet writes nothing
## else (REQ-P5-03, REQ-P1-05).
##
## The chart pans in both directions, so a 115-node graph is reachable on a
## phone as well as on the atlas (REQ-P1-07). Hover previews an advance on a
## desktop; a tap selects it and prints the same reading, so no rule lives
## behind a hover (REQ-P1-05).
##
## The chart also names the study the court would open: the college's own gold
## sentence under the goal's road, and a `▸` on the advance it names, so the
## crown sees where the court would go without scanning 115 nodes
## (wiki: tech-tree § Research Model; DR-20261121-20).

signal goal_requested(tech_id: String)

const DETAIL_PIXELS: int = 13
const DETAIL_PIXELS_COMPACT: int = 12
const LEGEND_PIXELS: int = 10

var _state: ResearchState = null
var _goal: String = ""
var _selected: String = ""
var _canvas: TechTreeCanvas = null
var _chart_scroll: ScrollContainer = null
var _road: Label = null
## The advance the chart marks as the court's own, mirrored from the pick.
var _court_tech: String = ""
var _detail_title: Label = null
var _detail_meta: Label = null
var _detail_effect: Label = null
var _goal_button: Button = null


func _init() -> void:
	title_text = "THE TECH TREE"
	hint_text = (
		"Drag the chart to pan; the wheel or two fingers scroll. Tap an advance "
		+ "to read what it grants and aim the queue at it."
	)


## The sheet opens on the crown's own college: the panel hands it the state it
## already reads, so the chart never keeps a second copy of what is known.
func _can_open() -> bool:
	return _state != null


## Hands the sheet the college's live research state and opens it.
func present(state: ResearchState) -> void:
	_state = state
	open()


func refresh() -> void:
	if _state == null or _canvas == null:
		return
	_goal = TechOrder.normalize(_state.goal)
	_sync_counsel()
	_court_tech = String(_counsel.pick.get("tech", ""))
	_canvas.present(_state, _goal, _court_tech)
	_road.text = _road_text()
	_render_detail(_selected)


## The college's pass answers on the session's own research state, not on the
## chart snapshot the frame hands over by default.
func _counsel_args() -> Array:
	return []


## The advance the chart marks as the court's own, or "" (DR-20261121-20).
func court_tech() -> String:
	return _court_tech


## The advance the reader last aimed at, or "" before the first tap.
func selected() -> String:
	return _selected


# --- sheet hooks -------------------------------------------------------------


func _build_body(column: VBoxContainer) -> void:
	_road = UiRowBuilder.wrapped_line("", 12, Palette.GOLD)
	column.add_child(_road)
	# The court's own pick sits under the goal's road, above the chart it marks:
	# two sentences, the crown's aim and the staff's next study (DR-20261121-20).
	_counsel_line(column)
	column.add_child(_legend())

	_chart_scroll = ScrollContainer.new()
	_chart_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_chart_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_chart_scroll)

	_canvas = TechTreeCanvas.new()
	_canvas.node_pressed.connect(_on_node_pressed)
	_canvas.node_hovered.connect(_on_node_hovered)
	_chart_scroll.add_child(_canvas)

	column.add_child(_detail_strip())


func _apply_profile(compact: bool, narrow: bool) -> void:
	super._apply_profile(compact, narrow)
	if _detail_effect != null:
		_detail_effect.add_theme_font_size_override(
			"font_size", DETAIL_PIXELS_COMPACT if compact else DETAIL_PIXELS
		)
	if _detail_meta != null:
		_detail_meta.visible = not narrow


# --- body --------------------------------------------------------------------


## The four standings the node ink carries, named once so the chart is read
## without a legend hunt (REQ-P1-08), and the two marks a node can wear: the
## crown's goal and the court's own next study (DR-20261121-20).
func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for entry: Array in [
		["Known", Palette.GOLD_PALE], ["At study", Palette.GOLD],
		["Open now", Palette.TEXT], ["Locked", Palette.TEXT_DIM],
		["◆ goal", Palette.GOLD_PALE], ["▸ court", Palette.GOLD_PALE],
	]:
		row.add_child(UiRowBuilder.label(String(entry[0]), LEGEND_PIXELS, entry[1] as Color))
	return row


## What the aimed advance grants, under the chart: the name, its era, branch and
## cost, where it stands for this crown, and the effect line the catalog already
## publishes. The goal door sits here, so aiming is one press from the reading.
func _detail_strip() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", UiTheme.box(Color(0.13, 0.10, 0.07, 0.98), Palette.GOLD_DIM, 1, 3, Vector4(12, 8, 12, 8))
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)

	_detail_title = UiRowBuilder.label("", 15, Palette.GOLD_PALE)
	column.add_child(_detail_title)
	_detail_meta = UiRowBuilder.label("", 11, Palette.TEXT_DIM)
	column.add_child(_detail_meta)
	_detail_effect = UiRowBuilder.wrapped_line("", DETAIL_PIXELS, Palette.TEXT)
	column.add_child(_detail_effect)

	_goal_button = UiRowBuilder.button("Set as research goal", 34.0, 0.0, 12)
	_goal_button.pressed.connect(_on_goal_pressed)
	column.add_child(_goal_button)
	return panel


func _road_text() -> String:
	if _goal.is_empty():
		return "Set a goal on any advance and the queue walks to it."
	return TechPlan.road_line(_state, _goal)


func _render_detail(tech_id: String) -> void:
	if _detail_title == null:
		return
	if tech_id.is_empty() or not TechCatalog.known(tech_id):
		_detail_title.text = "Select an advance"
		_detail_meta.text = ""
		_detail_effect.text = (
			"Every advance the college can study, its prerequisites and what it grants."
		)
		_goal_button.disabled = true
		_goal_button.text = "Set as research goal"
		return
	_detail_title.text = TechCatalog.display_name(tech_id)
	_detail_meta.text = "%s · %s · %d RP · %s" % [
		TechCatalog.era_name(tech_id),
		TechCatalog.category_short_label(TechCatalog.category(tech_id)),
		TechCatalog.cost(tech_id),
		TechPlan.reason(_state, tech_id),
	]
	_detail_effect.text = TechCatalog.effect_text(tech_id)
	_goal_button.disabled = false
	_goal_button.text = (
		"Clear the goal" if tech_id == _goal else "Set as research goal"
	)


# --- intents -----------------------------------------------------------------


func _on_node_pressed(tech_id: String) -> void:
	_selected = tech_id
	_canvas.select(tech_id)
	_render_detail(tech_id)


## A desktop hover previews the advance; leaving the node restores the reading
## of whatever is selected, so the strip never goes blank under the pointer.
func _on_node_hovered(tech_id: String) -> void:
	_render_detail(tech_id if not tech_id.is_empty() else _selected)


func _on_goal_pressed() -> void:
	if _selected.is_empty():
		return
	goal_requested.emit(_selected)
