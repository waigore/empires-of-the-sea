extends GdToolsTest
## Segment tracing and Chaikin smoothing used by coastlines and borders.


func _seg(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b])


func test_trace_joins_connected_segments() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(10, 0), Vector2(10, 10)),
		_seg(Vector2(10, 10), Vector2(0, 10)),
	]
	var paths: Array[PackedVector2Array] = InkPaths.trace(segments)
	assert_eq(paths.size(), 1)
	assert_eq(paths[0].size(), 4)
	assert_eq(paths[0][0], Vector2(0, 0))
	assert_eq(paths[0][3], Vector2(0, 10))


func test_trace_keeps_disconnected_segments_apart() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(50, 50), Vector2(60, 50)),
	]
	assert_eq(InkPaths.trace(segments).size(), 2)


func test_chaikin_keeps_open_endpoints() -> void:
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)
	])
	var smoothed: PackedVector2Array = InkPaths.chaikin(points, 2, false)
	assert_eq(smoothed[0], Vector2(0, 0))
	assert_eq(smoothed[smoothed.size() - 1], Vector2(10, 10))
	assert_gt(smoothed.size(), points.size())


func test_chaikin_short_input_is_unchanged() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	assert_eq(InkPaths.chaikin(points, 2, false), points)


func test_smooth_segments_closes_a_loop() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(10, 0), Vector2(10, 10)),
		_seg(Vector2(10, 10), Vector2(0, 10)),
		_seg(Vector2(0, 10), Vector2(0, 0)),
	]
	var paths: Array[PackedVector2Array] = InkPaths.smooth_segments(segments, 1)
	assert_eq(paths.size(), 1)
	var path: PackedVector2Array = paths[0]
	assert_eq(path[0], path[path.size() - 1])
	assert_gt(path.size(), 8)


func test_smooth_segments_skips_single_points() -> void:
	var segments: Array[PackedVector2Array] = []
	assert_eq(InkPaths.smooth_segments(segments, 2).size(), 0)
