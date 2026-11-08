class_name CameraMath
extends RefCounted
## Pure camera maths so pan/zoom limits are testable without a viewport (REQ-P3-04).


## Keeps the camera centre inside the map, or centres the map when it is smaller
## than the viewport on an axis.
static func clamp_center(
	center: Vector2, zoom: float, viewport: Vector2, map_size: Vector2
) -> Vector2:
	var safe_zoom: float = maxf(zoom, 0.001)
	var half: Vector2 = viewport / (2.0 * safe_zoom)
	var result: Vector2 = center
	if map_size.x <= half.x * 2.0:
		result.x = map_size.x * 0.5
	else:
		result.x = clampf(center.x, half.x, map_size.x - half.x)
	if map_size.y <= half.y * 2.0:
		result.y = map_size.y * 0.5
	else:
		result.y = clampf(center.y, half.y, map_size.y - half.y)
	return result


## Returns the camera centre that keeps the world point under `anchor_screen`
## fixed while the zoom changes.
static func zoom_anchor(
	center: Vector2,
	old_zoom: float,
	new_zoom: float,
	anchor_screen: Vector2,
	viewport: Vector2
) -> Vector2:
	var safe_old: float = maxf(old_zoom, 0.001)
	var safe_new: float = maxf(new_zoom, 0.001)
	var offset: Vector2 = anchor_screen - viewport * 0.5
	var world_before: Vector2 = center + offset / safe_old
	return world_before - offset / safe_new


## Zoom that fits the whole map inside the viewport with optional padding.
static func fit_zoom(viewport: Vector2, map_size: Vector2, padding: float = 0.0) -> float:
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return 1.0
	var usable: Vector2 = viewport - Vector2(padding, padding) * 2.0
	usable.x = maxf(usable.x, 1.0)
	usable.y = maxf(usable.y, 1.0)
	return minf(usable.x / map_size.x, usable.y / map_size.y)


## Smallest zoom at which the map still covers the whole viewport, so a tall or
## square window never shows empty space past the map edge.
static func fit_cover(viewport: Vector2, map_size: Vector2) -> float:
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return 1.0
	return maxf(viewport.x / map_size.x, viewport.y / map_size.y)


## Screen point (pixels) to world point for a camera centred on `center`.
static func screen_to_world(
	center: Vector2, zoom: float, screen: Vector2, viewport: Vector2
) -> Vector2:
	return center + (screen - viewport * 0.5) / maxf(zoom, 0.001)


## World point to screen point for a camera centred on `center`.
static func world_to_screen(
	center: Vector2, zoom: float, world: Vector2, viewport: Vector2
) -> Vector2:
	return (world - center) * maxf(zoom, 0.001) + viewport * 0.5
