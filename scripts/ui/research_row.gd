class_name ResearchRow
extends RefCounted
## Row builders for the research ledger (REQ-P3-02). The panel owns state and
## signals; these helpers only assemble one line of widgets per row. Every row
## leads with the series medallion (TechIcons) and stacks its name over a small
## meta line, so a narrow panel keeps room for the buttons. An occupied slot's
## line is a ResearchSlotRow instead — the panel keeps those alive so a repaint
## never rebuilds the sheet (REQ-P1-05).

const ROW_HEIGHT: float = 44.0
const ICON_SIZE: float = 30.0
const MARK_WIDTH: float = 14.0
const GOAL_ON_PATH: String = "◇"
const GOAL_ITSELF: String = "◆"
## The mark the counsel reads by: the advance the published research policy
## would open in the crown's first free slot wears it before its own name, the
## same `▸` the chart sets on the node it names (DR-20261121-20, DR-20261122-19).
const COURT_MARK: String = "▸"


## A researchable tech the crown can start now (or reason it cannot). `goal_id`
## lights the goal mark and the goal button reads back which tech is the goal.
## The row names what the study opens under its price, because a touch crown
## never sees a tooltip (REQ-P1-05, REQ-P5-03). `court` marks the advance the
## court's own college would open next, so the list the crown presses Research
## on points at the study the idle slot's sentence above it names.
static func available(
	state: ResearchState,
	tech_id: String,
	on_assign: Callable,
	goal_id: String = "",
	on_goal: Callable = Callable(),
	court: bool = false
) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(icon(tech_id))
	row.add_child(goal_mark(tech_id, goal_id))
	row.add_child(_name_column(
		tech_id,
		"%s · %d RP" % [TechCatalog.era_name(tech_id), TechCatalog.cost(tech_id)],
		Palette.TEXT,
		Palette.TEXT_DIM,
		TechCatalog.payoff_text(tech_id),
		court
	))

	if on_goal.is_valid():
		var is_goal: bool = tech_id == goal_id
		var goal := UiRowBuilder.button(
			"Goal " + GOAL_ITSELF if is_goal else "Goal", 0.0, 0.0
		)
		goal.custom_minimum_size = Vector2(80, ROW_HEIGHT)
		goal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		goal.tooltip_text = (
			"Clear the goal" if is_goal else "Steer the queue toward this advance"
		)
		if is_goal:
			goal.add_theme_color_override("font_color", Palette.GOLD_PALE)
		goal.pressed.connect(func() -> void: on_goal.call(tech_id))
		row.add_child(goal)

	var start := UiRowBuilder.button("Research", 0.0, 0.0)
	start.custom_minimum_size = Vector2(92, ROW_HEIGHT)
	start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start.disabled = state.free_slot() < 0
	if start.disabled:
		start.tooltip_text = "Every research slot is taken"
	start.pressed.connect(func() -> void: on_assign.call(tech_id))
	row.add_child(start)
	return row


## A tech the crown already knows.
static func known(tech_id: String, goal_id: String = "") -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(icon(tech_id))
	row.add_child(goal_mark(tech_id, goal_id))
	row.add_child(_name_column(
		tech_id, TechCatalog.era_name(tech_id), Palette.GOLD_PALE, Palette.TEXT_DIM
	))
	return row


## One line of the whole tree is the full-screen chart's node now
## (`TechTreeCanvas`); these rows stay for the two lists the college keeps.


## The series medallion, or an equally wide gap when no plate covers the tech.
static func icon(tech_id: String, size: float = ICON_SIZE) -> Control:
	var texture: Texture2D = TechIcons.texture(tech_id)
	if texture == null:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(size, size)
		return gap
	var picture := TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = Vector2(size, size)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


## "◆" for the goal itself, "◇" for a tech on its prerequisite path, blank
## otherwise; the column is always reserved so names stay aligned.
static func goal_mark(tech_id: String, goal_id: String) -> Control:
	var depth: int = TechOrder.chain_depth(tech_id, goal_id)
	var text: String = ""
	var color: Color = Palette.GOLD_DIM
	if depth == 0:
		text = GOAL_ITSELF
		color = Palette.GOLD_PALE
	elif depth > 0:
		text = GOAL_ON_PATH
	var mark := UiRowBuilder.label(text, 13, color)
	mark.custom_minimum_size = Vector2(MARK_WIDTH, 0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if depth >= 0:
		mark.tooltip_text = (
			"Your goal" if depth == 0
			else "%d step%s from %s" % [
				depth, "" if depth == 1 else "s", TechCatalog.display_name(goal_id)
			]
		)
	return mark


## Name over a small meta line: one column, so the buttons keep their room. A
## purchase row adds the payoff under its price — the catalog's own words, never
## a hover (REQ-P1-05). A row the court would take leads with `▸`, the mark the
## chart sets on that same advance (DR-20261122-19).
static func _name_column(
	tech_id: String, meta: String, title_color: Color, meta_color: Color,
	payoff: String = "", court: bool = false
) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	var title: String = TechCatalog.display_name(tech_id)
	var name_label := UiRowBuilder.label(
		("%s %s" % [COURT_MARK, title]) if court else title, 14, title_color
	)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = TechCatalog.effect_text(tech_id)
	column.add_child(name_label)
	column.add_child(UiRowBuilder.label(meta, 11, meta_color))
	if not payoff.is_empty():
		var line := UiRowBuilder.wrapped_line(payoff, 10, Palette.GOLD)
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(line)
	return column
