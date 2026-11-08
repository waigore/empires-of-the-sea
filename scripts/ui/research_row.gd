class_name ResearchRow
extends RefCounted
## Row builders for the research ledger (REQ-P3-02). The panel owns state and
## signals; these helpers only assemble one line of widgets per row.

const ROW_HEIGHT: float = 40.0
const NAME_WIDTH: float = 210.0


## One occupied slot: tech, progress, funding cycle and cancel.
static func slot(
	state: ResearchState,
	index: int,
	on_cancel: Callable,
	on_funding: Callable
) -> Control:
	var tech_id: String = state.tech_at(index)
	if tech_id.is_empty():
		return _empty_slot(index)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 8)

	var name_label := _label(TechCatalog.display_name(tech_id), 14, Palette.TEXT)
	name_label.tooltip_text = TechCatalog.effect_text(tech_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var progress := _label(
		"%d / %d" % [state.progress_of(tech_id), TechCatalog.cost(tech_id)], 13, Palette.GOLD_PALE
	)
	progress.custom_minimum_size = Vector2(96, 0)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(progress)

	var funding := _button(ResearchFunding.label(state.funding_at(index)))
	funding.custom_minimum_size = Vector2(104, ROW_HEIGHT)
	funding.tooltip_text = "%d ducats and %d RP per turn" % [
		ResearchFunding.gold(state.funding_at(index)),
		ResearchFunding.rp(state.funding_at(index)),
	]
	funding.pressed.connect(func() -> void: on_funding.call(index))
	row.add_child(funding)

	var cancel := _button("Cancel")
	cancel.custom_minimum_size = Vector2(78, ROW_HEIGHT)
	cancel.tooltip_text = "Abandon the study; all progress is lost"
	cancel.pressed.connect(func() -> void: on_cancel.call(index))
	row.add_child(cancel)
	return row


## A researchable tech the crown can start now (or reason it cannot).
static func available(state: ResearchState, tech_id: String, on_assign: Callable) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 8)

	var name_label := _label(TechCatalog.display_name(tech_id), 14, Palette.TEXT)
	name_label.tooltip_text = TechCatalog.effect_text(tech_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var era := _label(TechCatalog.era_name(tech_id), 11, Palette.TEXT_DIM)
	era.custom_minimum_size = Vector2(104, 0)
	era.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(era)

	var cost := _label("%d RP" % TechCatalog.cost(tech_id), 12, Palette.TEXT_DIM)
	cost.custom_minimum_size = Vector2(78, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cost)

	var start := _button("Research")
	start.custom_minimum_size = Vector2(96, ROW_HEIGHT)
	start.disabled = state.free_slot() < 0
	if start.disabled:
		start.tooltip_text = "Every research slot is taken"
	start.pressed.connect(func() -> void: on_assign.call(tech_id))
	row.add_child(start)
	return row


## A tech the crown already knows.
static func known(tech_id: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 8)

	var name_label := _label(TechCatalog.display_name(tech_id), 14, Palette.GOLD_PALE)
	name_label.tooltip_text = TechCatalog.effect_text(tech_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var era := _label(TechCatalog.era_name(tech_id), 11, Palette.TEXT_DIM)
	era.custom_minimum_size = Vector2(104, 0)
	era.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(era)
	return row


static func _empty_slot(index: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var name_label := _label("Slot %d — idle" % (index + 1), 14, Palette.TEXT_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	return row


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 13)
	return button
