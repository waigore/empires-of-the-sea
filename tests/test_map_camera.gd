extends GdToolsTest
## Camera input: every way the player pans and zooms (REQ-P1-05, REQ-P4-02).

const MAP := Vector2(2816.0, 1848.0)

var _camera: MapCamera = null


func before_each() -> void:
	InputActions.ensure_actions()
	_camera = MapCamera.new()
	_camera.map_size = MAP
	_camera.position = MAP * 0.5
	_camera.zoom = Vector2.ONE * 1.2
	_camera.target_zoom = 1.2
	add_child(_camera)


func after_each() -> void:
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null


func test_wheel_zooms_in_and_out() -> void:
	var before: float = _camera.target_zoom
	_camera._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(300, 200)))
	assert_gt(_camera.target_zoom, before)
	var zoomed: float = _camera.target_zoom
	_camera._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(300, 200)))
	assert_lt(_camera.target_zoom, zoomed)


func test_zoom_keeps_the_cursor_anchored() -> void:
	var anchor := Vector2(900.0, 300.0)
	var world_before: Vector2 = CameraMath.screen_to_world(
		_camera.position, _camera.zoom.x, anchor, _camera.viewport_size()
	)
	_camera.zoom_by(1.5, anchor)
	for _step in 8:
		_camera._process(0.1)
	var world_after: Vector2 = CameraMath.screen_to_world(
		_camera.position, _camera.zoom.x, anchor, _camera.viewport_size()
	)
	assert_lt(world_after.distance_to(world_before), 3.0)


func test_magnify_gesture_zooms() -> void:
	var event := InputEventMagnifyGesture.new()
	event.factor = 1.3
	event.position = Vector2(640, 640)
	var before: float = _camera.target_zoom
	_camera._unhandled_input(event)
	assert_gt(_camera.target_zoom, before)


func test_pan_gesture_moves_the_camera() -> void:
	var event := InputEventPanGesture.new()
	event.delta = Vector2(40, 0)
	event.position = Vector2(640, 640)
	var before: Vector2 = _camera.position
	_camera._unhandled_input(event)
	assert_lt(_camera.position.x, before.x)


func test_drag_marks_dragging_and_tracks_distance() -> void:
	_camera._unhandled_input(_button(true, Vector2(400, 400)))
	assert_true(_camera.is_dragging())
	_camera._unhandled_input(_motion(Vector2(30, 0)))
	assert_gt(_camera.drag_distance(), 0.0)
	_camera._unhandled_input(_button(false, Vector2(430, 400)))
	assert_false(_camera.is_dragging())


func test_click_emits_tapped_with_world_position() -> void:
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	_camera._unhandled_input(_button(false, Vector2(701, 500)))
	assert_eq(captured.size(), 1)
	var expected: Vector2 = CameraMath.screen_to_world(
		_camera.position, _camera.zoom.x, Vector2(701, 500), _camera.viewport_size()
	)
	assert_almost_eq(captured[0].x, expected.x, 0.5)
	assert_almost_eq(captured[0].y, expected.y, 0.5)


func test_drag_does_not_emit_tapped() -> void:
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	_camera._unhandled_input(_motion(Vector2(80, 0)))
	_camera._unhandled_input(_button(false, Vector2(780, 500)))
	assert_eq(captured.size(), 0)


func test_drag_keeps_inertia_after_release() -> void:
	_camera._unhandled_input(_button(true, Vector2(700, 500)))
	for _step in 4:
		_camera._unhandled_input(_motion(Vector2(40, 0)))
	var released_at: Vector2 = _camera.position
	_camera._unhandled_input(_button(false, Vector2(860, 500)))
	_camera._process(0.1)
	assert_ne(_camera.position, released_at)


func test_touch_tap_emits_tapped() -> void:
	var captured: Array[Vector2] = []
	_camera.tapped.connect(func(world: Vector2) -> void: captured.append(world))
	_camera._unhandled_input(_touch(0, true, Vector2(500, 500)))
	_camera._unhandled_input(_touch(0, false, Vector2(502, 501)))
	assert_eq(captured.size(), 1)


func test_two_finger_pinch_zooms() -> void:
	_camera._unhandled_input(_touch(0, true, Vector2(400, 400)))
	_camera._unhandled_input(_touch(1, true, Vector2(500, 400)))
	var before: float = _camera.target_zoom
	_camera._unhandled_input(_screen_drag(1, Vector2(120, 0), Vector2(620, 400)))
	assert_gt(_camera.target_zoom, before)


func test_single_finger_drag_pans() -> void:
	var before: Vector2 = _camera.position
	_camera._unhandled_input(_touch(0, true, Vector2(400, 400)))
	_camera._unhandled_input(_screen_drag(0, Vector2(-60, -30), Vector2(340, 370)))
	assert_ne(_camera.position, before)


func test_keyboard_pan_moves_the_camera() -> void:
	var before: Vector2 = _camera.position
	Input.action_press(InputActions.PAN_RIGHT)
	_camera._process(0.2)
	Input.action_release(InputActions.PAN_RIGHT)
	assert_gt(_camera.position.x, before.x)


func test_focus_on_settles_at_a_clamped_target() -> void:
	_camera.focus_on(Vector2(2600, 1700), 0.9)
	for _step in 30:
		_camera._process(0.2)
	var expected: Vector2 = CameraMath.clamp_center(
		Vector2(2600, 1700), _camera.zoom.x, _camera.viewport_size(), MAP
	)
	assert_lt(_camera.position.distance_to(expected), 2.0)
	assert_almost_eq(_camera.zoom.x, 0.9, 0.001)


func test_zoom_buttons_step_and_clamp() -> void:
	var before: float = _camera.target_zoom
	_camera.zoom_in()
	assert_gt(_camera.target_zoom, before)
	for _step in 40:
		_camera.zoom_in()
	assert_almost_eq(_camera.target_zoom, MapCamera.MAX_ZOOM, 0.0001)
	for _step in 80:
		_camera.zoom_out()
	assert_almost_eq(_camera.target_zoom, _camera.min_zoom(), 0.0001)


func _wheel(button: MouseButton, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = position
	return event


func _button(pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(400, 400)
	return event


func _touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event


func _screen_drag(index: int, relative: Vector2, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.relative = relative
	event.position = position
	return event
