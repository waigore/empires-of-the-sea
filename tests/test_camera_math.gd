extends GdToolsTest
## Camera clamping and anchoring maths.

const VIEWPORT := Vector2(1280.0, 720.0)
const MAP := Vector2(2816.0, 1848.0)


func test_clamp_center_keeps_view_inside_map() -> void:
	var clamped: Vector2 = CameraMath.clamp_center(Vector2(-500, -500), 1.0, VIEWPORT, MAP)
	assert_almost_eq(clamped.x, VIEWPORT.x * 0.5, 0.01)
	assert_almost_eq(clamped.y, VIEWPORT.y * 0.5, 0.01)

	clamped = CameraMath.clamp_center(Vector2(99999, 99999), 1.0, VIEWPORT, MAP)
	assert_almost_eq(clamped.x, MAP.x - VIEWPORT.x * 0.5, 0.01)
	assert_almost_eq(clamped.y, MAP.y - VIEWPORT.y * 0.5, 0.01)


func test_clamp_center_allows_interior_positions() -> void:
	var target := Vector2(1400.0, 900.0)
	assert_eq(CameraMath.clamp_center(target, 1.0, VIEWPORT, MAP), target)


func test_clamp_center_centres_small_map() -> void:
	var small := Vector2(400.0, 200.0)
	var clamped: Vector2 = CameraMath.clamp_center(Vector2(0, 0), 1.0, VIEWPORT, small)
	assert_almost_eq(clamped.x, 200.0, 0.01)
	assert_almost_eq(clamped.y, 100.0, 0.01)


func test_zoom_anchor_keeps_world_point_under_cursor() -> void:
	var center := Vector2(1400.0, 900.0)
	var anchor := Vector2(1000.0, 200.0)
	var before: Vector2 = CameraMath.screen_to_world(center, 0.6, anchor, VIEWPORT)
	var moved: Vector2 = CameraMath.zoom_anchor(center, 0.6, 1.2, anchor, VIEWPORT)
	var after: Vector2 = CameraMath.screen_to_world(moved, 1.2, anchor, VIEWPORT)
	assert_almost_eq(after.x, before.x, 0.01)
	assert_almost_eq(after.y, before.y, 0.01)


func test_fit_zoom_fits_whole_map() -> void:
	var zoom: float = CameraMath.fit_zoom(VIEWPORT, MAP)
	var expected: float = minf(VIEWPORT.x / MAP.x, VIEWPORT.y / MAP.y)
	assert_almost_eq(zoom, expected, 0.0001)


func test_fit_cover_covers_the_viewport() -> void:
	var zoom: float = CameraMath.fit_cover(VIEWPORT, MAP)
	assert_almost_eq(zoom, maxf(VIEWPORT.x / MAP.x, VIEWPORT.y / MAP.y), 0.0001)
	var tall := Vector2(720.0, 1600.0)
	assert_almost_eq(CameraMath.fit_cover(tall, MAP), 1600.0 / MAP.y, 0.0001)


func test_fit_cover_handles_zero_map() -> void:
	assert_eq(CameraMath.fit_cover(VIEWPORT, Vector2.ZERO), 1.0)


func test_fit_zoom_handles_zero_map() -> void:
	assert_eq(CameraMath.fit_zoom(VIEWPORT, Vector2.ZERO), 1.0)


func test_screen_world_round_trip() -> void:
	var world := Vector2(1234.0, 567.0)
	var screen: Vector2 = CameraMath.world_to_screen(Vector2(1000, 800), 1.7, world, VIEWPORT)
	var back: Vector2 = CameraMath.screen_to_world(Vector2(1000, 800), 1.7, screen, VIEWPORT)
	assert_almost_eq(back.x, world.x, 0.01)
	assert_almost_eq(back.y, world.y, 0.01)
