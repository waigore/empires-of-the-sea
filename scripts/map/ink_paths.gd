class_name InkPaths
extends RefCounted
## Turns a bag of grid-aligned segments into smooth ink polylines.
## Tracing + Chaikin subdivision is what stops province borders and coastlines
## from reading as staircases (REQ-P1-03).


## Joins segments that share endpoints into ordered polylines.
static func trace(
	segments: Array[PackedVector2Array], tolerance: float = 0.6
) -> Array[PackedVector2Array]:
	var adjacency: Dictionary = {}
	for index in segments.size():
		for point: Vector2 in segments[index]:
			var key: Vector2i = _key(point, tolerance)
			if not adjacency.has(key):
				adjacency[key] = [] as Array[int]
			var bucket: Array[int] = adjacency[key]
			bucket.append(index)

	var visited := PackedByteArray()
	visited.resize(segments.size())
	visited.fill(0)

	var paths: Array[PackedVector2Array] = []
	for index in segments.size():
		if visited[index] == 1:
			continue
		visited[index] = 1
		var path := PackedVector2Array([segments[index][0], segments[index][1]])
		_extend(path, segments, adjacency, visited, tolerance, true)
		_extend(path, segments, adjacency, visited, tolerance, false)
		paths.append(path)
	return paths


static func _extend(
	path: PackedVector2Array,
	segments: Array[PackedVector2Array],
	adjacency: Dictionary,
	visited: PackedByteArray,
	tolerance: float,
	forward: bool
) -> void:
	while true:
		var end_point: Vector2 = path[path.size() - 1] if forward else path[0]
		var key: Vector2i = _key(end_point, tolerance)
		var candidates: Array = adjacency.get(key, [])
		var found: int = -1
		for index: int in candidates:
			if visited[index] == 0:
				found = index
				break
		if found < 0:
			return
		visited[found] = 1
		var segment: PackedVector2Array = segments[found]
		var other: Vector2 = segment[1] if _key(segment[0], tolerance) == key else segment[0]
		if forward:
			path.append(other)
		else:
			path.insert(0, other)


## Chaikin corner cutting. Two iterations turn 90-degree steps into soft curves.
static func chaikin(
	points: PackedVector2Array, iterations: int, closed: bool
) -> PackedVector2Array:
	var current: PackedVector2Array = points
	for _iteration in iterations:
		if current.size() < 3:
			break
		var next := PackedVector2Array()
		var count: int = current.size()
		if closed:
			for i in count:
				var a: Vector2 = current[i]
				var b: Vector2 = current[(i + 1) % count]
				next.append(a.lerp(b, 0.25))
				next.append(a.lerp(b, 0.75))
		else:
			next.append(current[0])
			for i in count - 1:
				var a: Vector2 = current[i]
				var b: Vector2 = current[i + 1]
				next.append(a.lerp(b, 0.25))
				next.append(a.lerp(b, 0.75))
			next.append(current[count - 1])
		current = next
	return current


## Trace + smooth in one call. Closed loops are re-closed after smoothing.
static func smooth_segments(
	segments: Array[PackedVector2Array], iterations: int = 2, tolerance: float = 0.6
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for path: PackedVector2Array in trace(segments, tolerance):
		if path.size() < 2:
			continue
		var closed: bool = path[0].distance_to(path[path.size() - 1]) < tolerance
		var points: PackedVector2Array = path
		if closed and points.size() > 2:
			points = points.slice(0, points.size() - 1)
		var smoothed: PackedVector2Array = chaikin(points, iterations, closed)
		if closed and smoothed.size() > 0:
			smoothed.append(smoothed[0])
		result.append(smoothed)
	return result


## A hand-inked version of a smoothed path. Chaikin rounds the corners of a
## traced grid boundary but leaves every long run dead straight, so a border
## still reads as a staircase; this displaces each point along its normal with
## a two-frequency wobble keyed by arc length. Pure and deterministic, so a
## rebuild after an ownership change draws exactly the same line.
static func hand(
	points: PackedVector2Array, amplitude: float, salt: float = 0.0
) -> PackedVector2Array:
	if points.size() < 3 or amplitude <= 0.0:
		return points
	var closed: bool = points[0].distance_to(points[points.size() - 1]) < 0.01
	var result := PackedVector2Array()
	var travel: float = 0.0
	for i in points.size():
		var previous: Vector2 = points[maxi(i - 1, 0)]
		var following: Vector2 = points[mini(i + 1, points.size() - 1)]
		var along: Vector2 = following - previous
		if along.length_squared() < 0.000001:
			along = Vector2.RIGHT
		var normal := Vector2(-along.y, along.x).normalized()
		if i > 0:
			travel += points[i].distance_to(points[i - 1])
		var wobble: float = (
			sin(travel * 0.043 + salt) * 0.62 + sin(travel * 0.17 + salt * 2.3) * 0.38
		)
		result.append(points[i] + normal * wobble * amplitude)
	if closed and result.size() > 1:
		result[result.size() - 1] = result[0]
	return result


static func _key(point: Vector2, tolerance: float) -> Vector2i:
	return Vector2i(
		int(round(point.x / tolerance)),
		int(round(point.y / tolerance))
	)
