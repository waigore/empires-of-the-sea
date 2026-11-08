class_name PlatformDisplay
extends RefCounted
## Display policy for touch platforms: one HUD unit == one point (REQ-P1-05).
##
## Godot reports window sizes in physical pixels, so a 15-unit font on a 2.75x
## phone is 5 pt of text no matter how the stretch is configured. Setting the
## window's `content_scale_size` to `window size / screen scale` makes every
## point-sized control (font, margin, touch target) land where a designer
## expects on a phone, a tablet and a Retina desktop alike.
##
## Desktop keeps its pixel window untouched: only handhelds are rescaled.

const MIN_POINTS := Vector2(480.0, 320.0)
const MAX_POINTS := Vector2(1920.0, 1280.0)
const FALLBACK_DPI := 160.0
const MIN_SCALE := 1.0
const MAX_SCALE := 5.0


static func is_handheld() -> bool:
	return OS.has_feature("mobile")


## Applies the point scale to a handheld window; a no-op on desktop.
static func apply(window: Window) -> void:
	if window == null or not is_handheld():
		return
	if window.size.x < 240 or window.size.y < 180:
		# A window that has not been sized yet: the next resize is authoritative.
		return
	var points: Vector2 = point_size(window)
	if points.x < 1.0 or points.y < 1.0:
		return
	window.content_scale_size = Vector2i(roundi(points.x), roundi(points.y))


static func point_size(window: Window) -> Vector2:
	if window == null:
		return Vector2.ZERO
	return point_size_for(Vector2(window.size), screen_scale())


## Pure: physical pixels + one density ratio -> design points, aspect preserved.
static func point_size_for(pixels: Vector2, scale: float) -> Vector2:
	if pixels.x <= 0.0 or pixels.y <= 0.0:
		return Vector2.ZERO
	var points: Vector2 = pixels / clampf(scale, MIN_SCALE, MAX_SCALE)
	var shrink: float = minf(
		1.0, minf(MAX_POINTS.x / points.x, MAX_POINTS.y / points.y)
	)
	var grow: float = maxf(
		1.0, maxf(MIN_POINTS.x / points.x, MIN_POINTS.y / points.y)
	)
	return points * shrink * grow


## Dots per design point: the larger of the reported scale and DPI/160.
## Some Android builds report a base density (an emulator with `wm density`
## overridden reports 1.8 for a 2.625 screen) while `screen_get_dpi()` carries
## the effective one; under-reading makes every control physically tiny, which
## is the failure this whole module exists to prevent.
static func scale_for(reported: float, dpi: float) -> float:
	var scale: float = reported
	if dpi > 0.0:
		scale = maxf(scale, dpi / FALLBACK_DPI)
	if scale <= MIN_SCALE + 0.01:
		scale = 1.0
	return clampf(scale, MIN_SCALE, MAX_SCALE)


static func screen_scale() -> float:
	return scale_for(DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi())


## Screen edges hidden by a notch, rounded corner or system bar, in content
## units (left, top, right, bottom). Zero on desktop and on a clean screen.
static func safe_insets(window: Window) -> Vector4:
	if window == null or not is_handheld():
		return Vector4.ZERO
	var screen: Vector2 = Vector2(DisplayServer.screen_get_size())
	var area: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x <= 0.0 or screen.y <= 0.0 or area.size.x <= 0 or area.size.y <= 0:
		return Vector4.ZERO
	var units: Vector2 = point_size(window)
	var left: float = float(area.position.x) / screen.x * units.x
	var top: float = float(area.position.y) / screen.y * units.y
	var right: float = (screen.x - float(area.position.x + area.size.x)) / screen.x * units.x
	var bottom: float = (screen.y - float(area.position.y + area.size.y)) / screen.y * units.y
	return Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))
