class_name MapCamera
extends Camera2D
## Map camera: drag / trackpad / touch panning with inertia, wheel / pinch /
## keyboard zoom anchored under the cursor, and hard map-edge clamping.

signal view_changed
signal tapped(world_position: Vector2)

const MIN_ZOOM: float = 0.32
const MAX_ZOOM: float = 2.6
const ZOOM_STEP: float = 1.14
const TAP_SLOP: float = 9.0

var map_size: Vector2 = Vector2(2816.0, 1848.0)
var target_zoom: float = 0.6
var pan_speed: float = 1150.0
var inertia_damping: float = 5.0
var zoom_smoothing: float = 11.0

var _velocity: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_distance: float = 0.0
var _touches: Dictionary = {}
var _pinch_distance: float = 0.0
var _anchored: bool = false
var _anchor_screen: Vector2 = Vector2.ZERO
var _anchor_world: Vector2 = Vector2.ZERO
var _focus_target: Vector2 = Vector2.ZERO
var _has_focus_target: bool = false
var _last_emitted_position: Vector2 = Vector2.INF
var _last_emitted_zoom: float = -1.0


func _ready() -> void:
	enabled = true
	zoom = Vector2.ONE * target_zoom


func configure(size: Vector2) -> void:
	map_size = size
	position = CameraMath.clamp_center(position, zoom.x, viewport_size(), map_size)


func viewport_size() -> Vector2:
	return get_viewport_rect().size


## The map must always cover the viewport, so the floor is whichever is larger:
## the art-directed minimum or the cover fit for this window shape.
func min_zoom() -> float:
	return maxf(MIN_ZOOM, CameraMath.fit_cover(viewport_size(), map_size))


func is_dragging() -> bool:
	return _dragging


func drag_distance() -> float:
	return _drag_distance


func focus_on(world_position: Vector2, p_zoom: float = -1.0, instant: bool = false) -> void:
	if p_zoom > 0.0:
		target_zoom = clampf(p_zoom, min_zoom(), MAX_ZOOM)
	_anchored = false
	_velocity = Vector2.ZERO
	_focus_target = CameraMath.clamp_center(
		world_position, target_zoom, viewport_size(), map_size
	)
	_has_focus_target = true
	if instant:
		zoom = Vector2.ONE * target_zoom
		position = _focus_target
		_has_focus_target = false


func zoom_by(factor: float, anchor_screen: Vector2) -> void:
	var new_zoom: float = clampf(target_zoom * factor, min_zoom(), MAX_ZOOM)
	if is_equal_approx(new_zoom, target_zoom):
		return
	_anchor_screen = anchor_screen
	_anchor_world = CameraMath.screen_to_world(
		position, zoom.x, anchor_screen, viewport_size()
	)
	_anchored = true
	_has_focus_target = false
	target_zoom = new_zoom


func zoom_in() -> void:
	zoom_by(ZOOM_STEP, viewport_size() * 0.5)


func zoom_out() -> void:
	zoom_by(1.0 / ZOOM_STEP, viewport_size() * 0.5)


func _process(delta: float) -> void:
	var viewport: Vector2 = viewport_size()

	var direction: Vector2 = Input.get_vector(
		InputActions.PAN_LEFT, InputActions.PAN_RIGHT, InputActions.PAN_UP, InputActions.PAN_DOWN
	)
	if direction != Vector2.ZERO:
		_has_focus_target = false
		_anchored = false
		_velocity = Vector2.ZERO
		position += direction * pan_speed * delta / maxf(zoom.x, 0.001)

	if not _dragging and _velocity.length_squared() > 1.0:
		position += _velocity * delta
		_velocity *= exp(-inertia_damping * delta)
		if _velocity.length_squared() < 4.0:
			_velocity = Vector2.ZERO

	if _has_focus_target:
		var weight: float = 1.0 - exp(-7.0 * delta)
		position = position.lerp(_focus_target, weight)
		if position.distance_to(_focus_target) < 0.6:
			position = _focus_target
			_has_focus_target = false

	var current_zoom: float = zoom.x
	if not is_equal_approx(current_zoom, target_zoom):
		var weight: float = 1.0 - exp(-zoom_smoothing * delta)
		current_zoom = lerpf(current_zoom, target_zoom, weight)
		if absf(current_zoom - target_zoom) < 0.0008:
			current_zoom = target_zoom
		zoom = Vector2.ONE * current_zoom
	zoom = Vector2.ONE * clampf(zoom.x, min_zoom(), MAX_ZOOM)

	if _anchored:
		position = _anchor_world - (_anchor_screen - viewport * 0.5) / maxf(zoom.x, 0.001)
		if is_equal_approx(zoom.x, target_zoom):
			_anchored = false

	position = CameraMath.clamp_center(position, zoom.x, viewport, map_size)

	var moved: bool = position.distance_to(_last_emitted_position) > 0.4
	var zoomed: bool = absf(zoom.x - _last_emitted_zoom) > 0.0005
	if moved or zoomed:
		_last_emitted_position = position
		_last_emitted_zoom = zoom.x
		view_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		zoom_by(event.factor, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		_has_focus_target = false
		_anchored = false
		position -= event.delta * 26.0 / maxf(zoom.x, 0.001)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_by(ZOOM_STEP, event.position)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_by(1.0 / ZOOM_STEP, event.position)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_distance = 0.0
				_velocity = Vector2.ZERO
				_has_focus_target = false
				_anchored = false
			else:
				_dragging = false
				if _drag_distance < TAP_SLOP:
					tapped.emit(
						CameraMath.screen_to_world(
							position, zoom.x, event.position, viewport_size()
						)
					)
				get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _dragging:
		return
	var delta_world: Vector2 = -event.relative / maxf(zoom.x, 0.001)
	position += delta_world
	_drag_distance += event.relative.length()
	_velocity = _velocity.lerp(delta_world * 60.0, 0.35)
	if _velocity.length() > 2400.0:
		_velocity = _velocity.normalized() * 2400.0
	get_viewport().set_input_as_handled()


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_dragging = true
			_drag_distance = 0.0
			_velocity = Vector2.ZERO
			_has_focus_target = false
			_anchored = false
		elif _touches.size() == 2:
			_pinch_distance = _touch_distance()
	else:
		_touches.erase(event.index)
		if _touches.is_empty():
			_dragging = false
			if _drag_distance < TAP_SLOP * 1.6:
				tapped.emit(
					CameraMath.screen_to_world(
						position, zoom.x, event.position, viewport_size()
					)
				)
		elif _touches.size() == 1:
			_pinch_distance = 0.0
	get_viewport().set_input_as_handled()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		var distance: float = _touch_distance()
		if _pinch_distance > 0.0 and distance > 0.0:
			zoom_by(distance / _pinch_distance, _touch_center())
		_pinch_distance = distance
	else:
		position -= event.relative / maxf(zoom.x, 0.001)
		_drag_distance += event.relative.length()
	get_viewport().set_input_as_handled()


func _touch_distance() -> float:
	var points: Array = _touches.values()
	if points.size() < 2:
		return 0.0
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _touch_center() -> Vector2:
	var points: Array = _touches.values()
	if points.is_empty():
		return viewport_size() * 0.5
	var sum: Vector2 = Vector2.ZERO
	for point: Vector2 in points:
		sum += point
	return sum / float(points.size())
