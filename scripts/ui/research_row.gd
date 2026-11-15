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


## A researchable tech the crown can start now (or reason it cannot). `goal_id`
## lights the goal mark and the goal button reads back which tech is the goal.
static func available(
	state: ResearchState,
	tech_id: String,
	on_assign: Callable,
	goal_id: String = "",
	on_goal: Callable = Callable()
) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(icon(tech_id))
	row.add_child(goal_mark(tech_id, goal_id))
	row.add_child(_name_column(
		tech_id,
		"%s · %d RP" % [TechCatalog.era_name(tech_id), TechCatalog.cost(tech_id)],
		Palette.TEXT,
		Palette.TEXT_DIM
	))

	if on_goal.is_valid():
		var is_goal: bool = tech_id == goal_id
		var goal := UiRowBuilder.button(
			"Goal " + GOAL_ITSELF if is_goal else "Goal", 0.0, 0.0
		)
		goal.custom_minimum_size = Vector2(80, ROW_HEIGHT)
		goal.tooltip_text = (
			"Clear the goal" if is_goal else "Steer the queue toward this advance"
		)
		if is_goal:
			goal.add_theme_color_override("font_color", Palette.GOLD_PALE)
		goal.pressed.connect(func() -> void: on_goal.call(tech_id))
		row.add_child(goal)

	var start := UiRowBuilder.button("Research", 0.0, 0.0)
	start.custom_minimum_size = Vector2(92, ROW_HEIGHT)
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


## One line of the whole tree: the advance, where it stands for this crown, and
## the goal door. The blocking sentence sits under the name as its own wrapped
## line, so a touch player reads why an advance is shut without a hover
## (REQ-P1-05, REQ-P5-03). A locked row is dimmed, never disabled: aiming at a
## distant advance is how the road is read.
static func catalog(
	state: ResearchState, tech_id: String, goal_id: String, on_goal: Callable
) -> Control:
	var kind: int = TechPlan.state_of(state, tech_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS

	var row := UiRowBuilder.row(ROW_HEIGHT)
	box.add_child(row)
	row.add_child(icon(tech_id))
	row.add_child(goal_mark(tech_id, goal_id))
	var title_color: Color = Palette.TEXT
	match kind:
		TechPlan.State.KNOWN:
			title_color = Palette.GOLD_PALE
		TechPlan.State.STUDYING:
			title_color = Palette.GOLD
		TechPlan.State.LOCKED:
			title_color = Palette.TEXT_DIM
	row.add_child(_name_column(
		tech_id,
		"%s · %d RP" % [TechCatalog.era_name(tech_id), TechCatalog.cost(tech_id)],
		title_color,
		Palette.TEXT_DIM
	))

	var is_goal: bool = tech_id == goal_id
	var goal := UiRowBuilder.button(
		"Goal " + GOAL_ITSELF if is_goal else "Goal", 0.0, 0.0
	)
	goal.custom_minimum_size = Vector2(80, ROW_HEIGHT)
	goal.tooltip_text = (
		"Clear the goal" if is_goal else "Steer the queue toward this advance"
	)
	if is_goal:
		goal.add_theme_color_override("font_color", Palette.GOLD_PALE)
	goal.pressed.connect(func() -> void: on_goal.call(tech_id))
	row.add_child(goal)

	var note_color: Color = Palette.TEXT_DIM
	if kind == TechPlan.State.OPEN:
		note_color = Palette.GOLD_DIM
	var note := HBoxContainer.new()
	note.add_theme_constant_override("separation", 8)
	note.mouse_filter = Control.MOUSE_FILTER_PASS
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(ICON_SIZE + MARK_WIDTH, 0)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(indent)
	var line := UiRowBuilder.wrapped_line(TechPlan.reason(state, tech_id), 11, note_color)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_child(line)
	box.add_child(note)
	return box


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
	if depth >= 0:
		mark.tooltip_text = (
			"Your goal" if depth == 0
			else "%d step%s from %s" % [
				depth, "" if depth == 1 else "s", TechCatalog.display_name(goal_id)
			]
		)
	return mark


## Name over a small meta line: one column, so the buttons keep their room.
static func _name_column(
	tech_id: String, meta: String, title_color: Color, meta_color: Color
) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	var name_label := UiRowBuilder.label(TechCatalog.display_name(tech_id), 14, title_color)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = TechCatalog.effect_text(tech_id)
	column.add_child(name_label)
	column.add_child(UiRowBuilder.label(meta, 11, meta_color))
	return column
