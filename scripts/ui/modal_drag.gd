class_name ModalDrag
extends RefCounted
## Makes an opened plate movable by its own chrome, so the chart underneath can
## be read while the plate stays up (REQ-P1-07). A plate that covers the fleet
## or the province the player is reading can be pushed aside instead of closed.
##
## Godot routes a touch press to the GUI as a mouse press (the project keeps the
## engine's touch→mouse emulation), so one pointer path serves desktop and
## mobile. Offsets are absolute from the press point, so a doubled event can
## never double the move.
##
## Two ways to carry the move:
##  - the mover's `position` (a Control's position setter shifts its offsets, so
##    a full-rect margin and a docked wrap both keep their size), or
##  - an applier the owner passes, for a plate that repaints its own rect on
##    every fit (the Gazette).

const GRIP_SIZE := Vector2(18.0, 24.0)
## Meta key holding the helper on the mover, so a re-anchored plate can reset it.
const META: String = "modal_drag"

var _host: Control = null
var _mover: Control = null
var _panel: Control = null
var _apply: Callable = Callable()
var _offset: Vector2 = Vector2.ZERO
var _base: Vector2 = Vector2.ZERO
var _press_at: Vector2 = Vector2.ZERO
var _start: Vector2 = Vector2.ZERO
var _min: Vector2 = Vector2.ZERO
var _max: Vector2 = Vector2.ZERO
var _dragging: bool = false


## `grabs` carry the drag (a header row, or the plate itself); `panel` is what
## must stay on screen and defaults to the mover; `apply` replaces the position
## move when the owner paints the offset itself.
static func attach(
	host: Control,
	mover: Control,
	grabs: Array[Control],
	panel: Control = null,
	apply: Callable = Callable()
) -> ModalDrag:
	var drag := ModalDrag.new()
	drag._host = host
	drag._mover = mover
	drag._panel = panel if panel != null else mover
	drag._apply = apply
	mover.set_meta(META, drag)
	for grab: Control in grabs:
		if grab == null:
			continue
		grab.mouse_filter = Control.MOUSE_FILTER_STOP
		grab.mouse_default_cursor_shape = Control.CURSOR_DRAG
		grab.gui_input.connect(drag._on_gui_input.bind(grab))
	return drag


## Puts a plate back where its owner laid it out: a reopened dossier docks where
## the layout says, so the next drag starts from that place, not the last one.
static func reset_on(mover: Control) -> void:
	if mover == null or not mover.has_meta(META):
		return
	var drag: ModalDrag = mover.get_meta(META) as ModalDrag
	if drag != null:
		drag.reset()


## The six-dot grip a plate's header carries: drawn, not a font glyph, so no
## typeface can decide whether the affordance appears.
static func grip() -> Control:
	var handle := Grip.new()
	handle.name = "Grip"
	handle.tooltip_text = "Drag to move this plate"
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle.custom_minimum_size = GRIP_SIZE
	handle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return handle


func reset() -> void:
	# A plate that was never moved is already where its owner put it; painting
	# here would move a fresh wrap to the base captured before any press.
	if _offset == Vector2.ZERO and not _dragging:
		return
	_offset = Vector2.ZERO
	_dragging = false
	_paint()


func offset() -> Vector2:
	return _offset


func is_dragging() -> bool:
	return _dragging


func _on_gui_input(event: InputEvent, grab: Control) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_begin(button.position)
		else:
			_dragging = false
		grab.accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		_move((event as InputEventMouseMotion).position)
		grab.accept_event()


func _begin(at: Vector2) -> void:
	_dragging = true
	_press_at = at
	_start = _offset
	# A dock slide still running would keep writing the docked offsets under the
	# drag, so the press takes the plate off the tween first.
	PanelDock.stop_slide(_mover)
	# The base is re-derived each press, so a plate the layout re-anchored while
	# it was open still moves from where it actually stands.
	_base = _mover.position - _offset
	var host_rect: Rect2 = _host.get_global_rect()
	var panel_rect: Rect2 = _panel.get_global_rect()
	_min = host_rect.position - panel_rect.position
	_max = host_rect.end - panel_rect.end
	# A plate larger than the host cannot be kept inside it; it stays put on the
	# axis that does not fit instead of jumping to one edge.
	for axis: int in [0, 1]:
		if _max[axis] < _min[axis]:
			_min[axis] = 0.0
			_max[axis] = 0.0


func _move(at: Vector2) -> void:
	var delta: Vector2 = at - _press_at
	_offset = _start + Vector2(
		clampf(delta.x, _min.x, _max.x), clampf(delta.y, _min.y, _max.y)
	)
	_paint()


func _paint() -> void:
	if _apply.is_valid():
		_apply.call(_offset)
		return
	_mover.position = _base + _offset


class Grip extends Control:
	func _draw() -> void:
		for row: int in 3:
			for col: int in 2:
				draw_circle(
					Vector2(6.0 + col * 6.0, 6.0 + row * 6.0), 1.6, Palette.GOLD_DIM
				)
