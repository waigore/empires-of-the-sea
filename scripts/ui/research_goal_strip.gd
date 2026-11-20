class_name ResearchGoalStrip
extends HBoxContainer
## The college's goal strip: the advance the queue is sorted toward, how far it
## has come, and the Clear action. Presentation only — ResearchPanel owns the
## state and the queue order; this row emits the one intent it carries
## (REQ-P3-01, wiki: tech-tree § Goal slot).
##
## On a phone the strip rides the slots heading instead of standing on a row of
## its own (DR-20261120-03): its tag, its icon and its clear press tighten, and
## the goal's name clips rather than pushing the tree door off the sheet, so the
## room the strip used to spend becomes catalogue rows (REQ-P1-07, REQ-P5-07).

signal clear_pressed

const CLEAR_SIZE: Vector2 = Vector2(64.0, 30.0)
const CLEAR_SIZE_COMPACT: Vector2 = Vector2(44.0, 26.0)
const ICON_PIXELS: float = 30.0
const ICON_PIXELS_COMPACT: float = 22.0

## The goal id last rendered; "" means the queue is unsorted.
var goal: String = ""
var _key: String = ""
## The state and goal the last paint read, so a profile change can repaint the
## same reading without waiting for the panel's next refresh.
var _state: ResearchState = null
var _compact: bool = false


func _init() -> void:
	add_theme_constant_override("separation", 8)


## Rewrites the strip from live research state. A repaint that changes neither
## the goal nor its standing touches no widget.
func render(state: ResearchState, goal_id: String) -> void:
	_state = state
	var standing: String = _standing(state, goal_id)
	var key: String = "%s|%s|%s" % [goal_id, standing, str(_compact)]
	if key == _key:
		return
	_key = key
	goal = goal_id
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_paint(goal_id, standing)


## Phone chrome (DR-20261120-03): the tag and the icon tighten, the clear press
## keeps a thumb, and the name clips in the room the heading row shares.
func set_compact(compact: bool) -> void:
	if compact == _compact:
		return
	_compact = compact
	add_theme_constant_override("separation", 4 if compact else 8)
	# Repaint the reading already on the strip, so a profile change is not a
	# stale face waiting for the next refresh.
	if not _key.is_empty():
		_key = ""
		render(_state, goal)


## Where the strip stands: on its own row under the notice on a wide chart, and in
## the slots heading's own row on a phone, so the college spends one row on chrome
## where it used to spend two (DR-20261120-03). True when it moved: a move re-lays
## every line under it, so the sheet's fit is taken once more after the frame.
func ride(own_row: Container, head_row: Container, compact: bool) -> bool:
	if own_row == null or head_row == null:
		return false
	var host: Container = head_row if compact else own_row
	var moved: bool = get_parent() != host
	if moved:
		var old: Node = get_parent()
		if old != null:
			old.remove_child(self)
		host.add_child(self)
	if host == head_row:
		# The heading, then the goal, then the tree door: the door keeps the
		# row's far edge at every size, and the goal takes the room its name
		# needs between them.
		head_row.move_child(self, maxi(head_row.get_child_count() - 2, 1))
	else:
		# Back on its own row, right above the slots heading it sorts.
		own_row.move_child(self, head_row.get_index())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL if host == head_row else Control.SIZE_FILL
	return moved


func _paint(goal_id: String, standing: String) -> void:
	if not _compact:
		var tag := UiRowBuilder.label("GOAL", 11, Palette.TEXT_DIM)
		tag.custom_minimum_size = Vector2(46, 0)
		add_child(tag)
	if goal_id.is_empty():
		# The prompt explains the empty state; a phone hides the whole strip
		# instead of spending a line on it.
		var hint := UiRowBuilder.label(
			"No goal — set one to sort the queue by the path that reaches it.",
			12, Palette.TEXT_DIM
		)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
		return
	add_child(ResearchRow.icon(
		goal_id, ICON_PIXELS_COMPACT if _compact else ICON_PIXELS
	))
	var name_label := UiRowBuilder.label(
		TechCatalog.display_name(goal_id), 13 if _compact else 14, Palette.GOLD_PALE
	)
	name_label.tooltip_text = TechCatalog.effect_text(goal_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A clipped name keeps its tooltip and the goal id, and never widens the
	# heading row past the sheet's own width.
	name_label.clip_text = _compact
	add_child(name_label)
	var standing_label := UiRowBuilder.label(standing, 10 if _compact else 11, Palette.TEXT_DIM)
	standing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(standing_label)
	var clear := Button.new()
	clear.text = "Clear"
	clear.custom_minimum_size = CLEAR_SIZE_COMPACT if _compact else CLEAR_SIZE
	clear.add_theme_font_size_override("font_size", 11 if _compact else 12)
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
