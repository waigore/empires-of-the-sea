class_name ChartTap
extends RefCounted
## One chart tap, however many input paths deliver it (REQ-P3-04).
##
## A chart is tapped through two paths: the camera's `tapped` signal (the
## desktop pointer's favourite) and a screen-space catcher's `gui_input` (the
## path every platform delivers). Android also sends an emulated mouse click
## beside every touch, and a touch and a mouse press share no slot: one stream's
## press must never erase the other's start. So each stream keeps its own press,
## a release close to its press is a tap, and the same tap seen twice in one
## frame is answered once.
##
## Pure: no nodes, no viewport. The page feeds it screen points and asks it for
## the world point to answer.

## A finger (or cursor) that travels farther than this between press and release
## is a pan, not a tap.
const SLOP: float = 12.0
## Two answers to the same tap land within this many world units of each other.
const MERGE_DISTANCE: float = 0.5

## One press slot per input stream: a touch and the emulated mouse click beside
## it are separate streams, so neither can erase the other's start.
var _touch_start: Vector2 = Vector2.INF
var _touch_index: int = -1
var _mouse_start: Vector2 = Vector2.INF
var _answered_frame: int = -1
var _answered_world: Vector2 = Vector2.INF


## Remembers a touch press, or answers its release. Returns the screen point of
## a tap, or `Vector2.INF` when the event is not a tap (a drag, a pinch, or a
## release with no press of its own).
func touch(pressed: bool, index: int, position: Vector2) -> Vector2:
	if pressed:
		_touch_start = position
		_touch_index = index
		return Vector2.INF
	if index != _touch_index:
		return Vector2.INF
	var start: Vector2 = _touch_start
	_touch_start = Vector2.INF
	_touch_index = -1
	return _tap_point(start, position)


## Remembers a left-button press, or answers its release. Same contract as
## `touch`.
func mouse(pressed: bool, position: Vector2) -> Vector2:
	if pressed:
		_mouse_start = position
		return Vector2.INF
	if _mouse_start == Vector2.INF:
		return Vector2.INF
	var start: Vector2 = _mouse_start
	_mouse_start = Vector2.INF
	return _tap_point(start, position)


## True when this world point is the same tap as the last one answered in this
## frame, so the second path to see it stays silent.
func is_repeat(frame: int, world_position: Vector2) -> bool:
	return (
		frame == _answered_frame
		and world_position.distance_to(_answered_world) < MERGE_DISTANCE
	)


## Records the tap answered this frame.
func mark_answered(frame: int, world_position: Vector2) -> void:
	_answered_frame = frame
	_answered_world = world_position


## A release close to its press is a tap; anything farther belongs to the pans.
func _tap_point(start: Vector2, position: Vector2) -> Vector2:
	if start == Vector2.INF or position.distance_to(start) > SLOP:
		return Vector2.INF
	return position
