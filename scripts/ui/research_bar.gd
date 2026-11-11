class_name ResearchBar
extends Control
## One research slot's study gauge in the college ledger (REQ-P1-05 — the gold a
## slot spends is never silent; REQ-P1-07 — the ledger reads at a glance).
##
## The gauge draws three things: the points already banked, the share the next
## Research phase adds at the slot's funding, and the mark where that share
## lands. It animates itself so a funding change runs the preview forward instead
## of repainting the sheet: a slow sheen crosses the banked points and the
## leading edge eases to its new place.

## Height of the drawn gauge; the Control keeps its own box for centring.
const HEIGHT: float = 12.0
const TRACK_RADIUS: int = 4
## Seconds the fill takes to run from its old value to a new one.
const GROW_TIME: float = 0.5
## Seconds one sheen sweep spends crossing the banked points.
const SHEEN_TIME: float = 2.4

var _cost: int = 1
var _target: int = 0
var _next: int = 0
var _paid: bool = true
var _shown: float = 0.0
var _sheen: float = 0.0
var _tween: Tween = null
var _track: StyleBoxFlat = null


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track = UiTheme.box(
		Color(0.15, 0.12, 0.09), Palette.INK_LINE, 1, TRACK_RADIUS, Vector4.ZERO
	)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_sheen = fmod(_sheen + delta / SHEEN_TIME, 1.0)
	queue_redraw()


## Arms the gauge: points banked, the cost to meet, and what the next phase is
## expected to add. `paid` false is a slot the treasury cannot cover — the band
## turns crimson and earns nothing (wiki: tech-tree § Research Model). `animate`
## off jumps straight to the value, for a load or a first paint.
func set_progress(
	progress: int, cost: int, next_gain: int, paid: bool = true, animate: bool = true
) -> void:
	_cost = maxi(cost, 1)
	_target = clampi(progress, 0, _cost)
	_paid = paid
	_next = maxi(next_gain, 0) if paid else 0
	if not animate or not is_inside_tree():
		_shown = float(_target)
		queue_redraw()
		return
	if is_equal_approx(_shown, float(_target)):
		queue_redraw()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_shown", float(_target), GROW_TIME)


# --- read-only views ---------------------------------------------------------


## Points the slot has banked, as the last repaint set them.
func target_progress() -> int:
	return _target


## Points the next Research phase is expected to add (0 when unpaid).
func next_gain() -> int:
	return _next


func cost() -> int:
	return _cost


## Banked share of the cost, 0..1 — the animated fill, not the tween target.
func fraction() -> float:
	return clampf(_shown / float(_cost), 0.0, 1.0)


## Where the next phase lands, 0..1.
func next_fraction() -> float:
	return clampf(float(_target + _next) / float(_cost), 0.0, 1.0)


func is_paid() -> bool:
	return _paid


# --- drawing -----------------------------------------------------------------


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var height: float = minf(HEIGHT, size.y)
	var top: float = (size.y - height) * 0.5
	var track := Rect2(Vector2(0.0, top), Vector2(size.x, height))
	draw_style_box(_track, track)
	var banked: float = size.x * fraction()
	var land: float = size.x * next_fraction()
	_draw_preview(top, height, banked, land)
	_draw_fill(top, height, banked)
	_draw_ticks(top, height)
	if _next > 0 and _target < _cost:
		var mark_x: float = clampf(land, 1.5, size.x - 1.5)
		draw_line(
			Vector2(mark_x, top + 0.5), Vector2(mark_x, top + height - 0.5),
			Color(Palette.GOLD_PALE, 0.75), 1.0
		)


## The share the next phase adds, breathing so the gauge reads as live.
func _draw_preview(top: float, height: float, banked: float, land: float) -> void:
	if _target >= _cost or land - banked <= 0.5:
		return
	var ink: Color = Palette.CRIMSON if not _paid else Palette.GOLD
	ink.a = 0.15 + 0.08 * sin(_sheen * TAU)
	draw_rect(
		Rect2(Vector2(banked, top + 1.0), Vector2(land - banked, height - 2.0)), ink
	)


func _draw_fill(top: float, height: float, banked: float) -> void:
	if banked <= 1.0:
		return
	var width: float = banked - 1.0
	var bottom: float = top + height - 1.0
	draw_polygon(
		PackedVector2Array([
			Vector2(1.0, top + 1.0),
			Vector2(1.0 + width, top + 1.0),
			Vector2(1.0 + width, bottom),
			Vector2(1.0, bottom),
		]),
		PackedColorArray([
			Palette.GOLD_PALE, Palette.GOLD_PALE, Palette.GOLD_DIM, Palette.GOLD_DIM,
		])
	)
	# A soft sheen, so a funded study visibly works between turns.
	var centre: float = width * _sheen + 1.0
	var left: float = maxf(centre - 6.0, 1.0)
	var right: float = minf(centre + 6.0, banked - 1.0)
	if right - left > 0.5:
		draw_rect(
			Rect2(Vector2(left, top + 1.0), Vector2(right - left, height - 2.0)),
			Color(1.0, 0.97, 0.86, 0.16)
		)
	draw_line(
		Vector2(1.0, top + 1.4), Vector2(1.0 + width, top + 1.4),
		Color(1.0, 0.98, 0.9, 0.30), 1.0
	)


## Quarter marks, so a glance reads how much of the cost is left.
func _draw_ticks(top: float, height: float) -> void:
	for step: float in [0.25, 0.5, 0.75]:
		var x: float = size.x * step
		if x <= 2.0 or x >= size.x - 2.0:
			continue
		draw_line(
			Vector2(x, top + 1.0), Vector2(x, top + height - 1.0),
			Color(1.0, 1.0, 1.0, 0.07), 1.0
		)
