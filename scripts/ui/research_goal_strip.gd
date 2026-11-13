class_name ResearchGoalStrip
extends HBoxContainer
## The college's goal strip: the advance the queue is sorted toward, how far it
## has come, and the Clear action. Presentation only — ResearchPanel owns the
## state and the queue order; this row emits the one intent it carries
## (REQ-P3-01, wiki: tech-tree § Goal slot).

signal clear_pressed

## The goal id last rendered; "" means the queue is unsorted.
var goal: String = ""
var _key: String = ""


func _init() -> void:
	add_theme_constant_override("separation", 8)


## Rewrites the strip from live research state. A repaint that changes neither
## the goal nor its standing touches no widget.
func render(state: ResearchState, goal_id: String) -> void:
	var standing: String = _standing(state, goal_id)
	var key: String = "%s|%s" % [goal_id, standing]
	if key == _key:
		return
	_key = key
	goal = goal_id
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var tag := _label("GOAL", 11, Palette.TEXT_DIM)
	tag.custom_minimum_size = Vector2(46, 0)
	add_child(tag)
	if goal.is_empty():
		# The prompt explains the empty state; a phone hides the whole strip
		# instead of spending a line on it.
		var hint := _label(
			"No goal — set one to sort the queue by the path that reaches it.",
			12, Palette.TEXT_DIM
		)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
		return
	add_child(ResearchRow.icon(goal, 30.0))
	var name_label := _label(TechCatalog.display_name(goal), 14, Palette.GOLD_PALE)
	name_label.tooltip_text = TechCatalog.effect_text(goal)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(name_label)
	var standing_label := _label(standing, 11, Palette.TEXT_DIM)
	standing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(standing_label)
	var clear := Button.new()
	clear.text = "Clear"
	clear.custom_minimum_size = Vector2(64, 30)
	clear.add_theme_font_size_override("font_size", 12)
	clear.tooltip_text = "Keep the goal out of the queue's order"
	clear.pressed.connect(func() -> void: clear_pressed.emit())
	add_child(clear)


## How far the goal has come: known, in a slot with its RP, or not yet begun.
static func _standing(state: ResearchState, goal_id: String) -> String:
	if state == null or goal_id.is_empty():
		return ""
	if state.is_unlocked(goal_id):
		return "reached"
	if state.is_active(goal_id):
		return "%d / %d RP" % [state.progress_of(goal_id), TechCatalog.cost(goal_id)]
	return "%d RP" % TechCatalog.cost(goal_id)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
