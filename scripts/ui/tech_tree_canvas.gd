class_name TechTreeCanvas
extends Control
## The college's chart: every advance placed by `TechTreeLayout`, its
## prerequisite edges drawn behind the nodes, and the aimed advance's ancestor
## cone lit gold so a reader can see what still stands on the road
## (wiki: tech-tree § Prerequisites; DR-20261115-15). The canvas owns the
## selection and the pan; the panel owns the goal and the reading.
##
## Panning: the chart sits in a scroll view, and a drag on the open chart (a
## thumb on a phone, a held button on a desktop) moves it, so a 115-node graph
## is reachable on both (REQ-P1-05, REQ-P1-07).

signal node_pressed(tech_id: String)
signal node_hovered(tech_id: String)

const EDGE_INK: Color = Color(0.45, 0.38, 0.26, 0.55)
const EDGE_LIT: Color = Color(0.925, 0.827, 0.478, 0.95)
const EDGE_WIDTH: float = 1.5
const EDGE_LIT_WIDTH: float = 2.5

var _nodes: Dictionary = {}
var _state: ResearchState = null
var _goal: String = ""
## The advance the court's own policy would open, marked `▸` (DR-20261121-20).
var _court: String = ""
var _selected: String = ""
## The aimed advance and every prerequisite above it; empty when nothing aims.
var _cone: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = TechTreeLayout.bounds()
	size = custom_minimum_size


## Repaints the chart from live research state. The nodes are built once, so a
## goal or counsel change rewrites their ink and touches no widget (REQ-P1-05).
## `court` marks the advance the court's own policy would open; "" marks none.
func present(state: ResearchState, goal: String = "", court: String = "") -> void:
	_state = state
	_goal = TechOrder.normalize(goal)
	_court = TechOrder.normalize(court)
	if _nodes.is_empty():
		_build()
	_repaint()
	queue_redraw()


## Lights the advance's whole road: the node, its ancestors and the edges
## between them. "" clears the highlight.
func select(tech_id: String) -> void:
	_selected = TechOrder.normalize(tech_id)
	_cone = TechTreeLayout.ancestors(_selected)
	_repaint()
	queue_redraw()


func selected() -> String:
	return _selected


func node(tech_id: String) -> TechTreeNode:
	return _nodes.get(tech_id) as TechTreeNode


func node_count() -> int:
	return _nodes.size()


# --- drawing -----------------------------------------------------------------


func _draw() -> void:
	for edge: Dictionary in TechTreeLayout.edges():
		var from: TechTreeNode = node(String(edge["from"]))
		var to: TechTreeNode = node(String(edge["to"]))
		if from == null or to == null:
			continue
		var lit: bool = (
			_cone.has(String(edge["from"])) and _cone.has(String(edge["to"]))
		)
		_draw_edge(
			from.position + Vector2(from.size.x, from.size.y * 0.5),
			to.position + Vector2(0.0, to.size.y * 0.5),
			lit
		)


## One right-angle road between two nodes: out of the prerequisite, across the
## gap, and into the dependent. Square corners read as a chart, not a web.
func _draw_edge(start: Vector2, end: Vector2, lit: bool) -> void:
	var middle: float = (start.x + end.x) * 0.5
	var points: PackedVector2Array = PackedVector2Array([
		start, Vector2(middle, start.y), Vector2(middle, end.y), end,
	])
	draw_polyline(
		points,
		EDGE_LIT if lit else EDGE_INK,
		EDGE_LIT_WIDTH if lit else EDGE_WIDTH,
		true
	)


# --- building ----------------------------------------------------------------


func _build() -> void:
	var places: Dictionary = TechTreeLayout.positions()
	for tech_id: String in TechCatalog.ids():
		var item := TechTreeNode.new()
		item.setup(tech_id)
		item.position = places[tech_id] as Vector2
		item.size = item.custom_minimum_size
		item.pressed.connect(func() -> void: node_pressed.emit(tech_id))
		item.hovered.connect(func(id: String) -> void: node_hovered.emit(id))
		add_child(item)
		_nodes[tech_id] = item


func _repaint() -> void:
	for tech_id: Variant in _nodes.keys():
		var node: TechTreeNode = _nodes[tech_id]
		node.paint(
			_state, _goal, _cone.has(String(tech_id)), String(tech_id) == _court
		)


# --- panning -----------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	var moved: Vector2 = Vector2.ZERO
	if event is InputEventScreenDrag:
		moved = (event as InputEventScreenDrag).relative
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			moved = (event as InputEventMouseMotion).relative
	if moved == Vector2.ZERO:
		return
	_pan(moved)
	accept_event()


func _pan(by: Vector2) -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null:
		return
	scroll.scroll_horizontal -= int(by.x)
	scroll.scroll_vertical -= int(by.y)
