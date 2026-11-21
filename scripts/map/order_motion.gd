class_name OrderMotion
extends RefCounted
## The chart's one language for "this marker has an order" (issue #1198;
## REQ-P1-04, REQ-P5-05). Own civilians, standards and squadrons borrow it, so a
## busy unit reads at a glance and keeps reading as the order it holds: a march
## leans a step along its heading and churns a wake astern, while work and a
## station breathe in place and walk a bead around the mark. The halo is painted
## before the marker's own art and held low, so no silhouette is ever hidden
## (REQ-P5-06). Idle own units and every rival never paint it.

enum Order { NONE, MOVE, WORK }

## A march keeps a quicker beat than work; both stay slow enough to read quiet.
const MOVE_RATE: float = 5.0
const WORK_RATE: float = 1.9
## The step a marching marker leans along its heading, in chart pixels.
const STEP: float = 1.6
## Beat of the halo ring at its widest, in chart pixels.
const BREATH: float = 1.8


## 0..1 beat of the order loop; an idle marker never beats.
static func beat(order: int, time: float, phase: float) -> float:
	if order == Order.NONE:
		return 0.0
	var rate: float = MOVE_RATE if order == Order.MOVE else WORK_RATE
	return 0.5 + 0.5 * sin(time * rate + phase)


## The body's own offset this frame: a march leans a step forward, a work or a
## station holds its berth. Applied at draw time, so a tap still lands where the
## marker is picked — the same rule the fleet's station row follows.
static func drift(order: int, time: float, phase: float, heading: Vector2) -> Vector2:
	if order != Order.MOVE:
		return Vector2.ZERO
	var lean: Vector2 = heading.normalized()
	if lean == Vector2.ZERO:
		return Vector2.ZERO
	return lean * STEP * beat(order, time, phase)


## Paints the order halo at `at` for a marker of `radius`. Pass it before the
## marker's own art so the mark stays crisp: the ring says busy, the silhouette
## still says what the unit is.
static func paint(
	canvas: CanvasItem,
	at: Vector2,
	radius: float,
	order: int,
	time: float,
	phase: float,
	heading: Vector2 = Vector2.RIGHT
) -> void:
	if order == Order.NONE:
		return
	var pulse: float = beat(order, time, phase)
	var glow: Color = Palette.GOLD_PALE
	glow.a = 0.16 + 0.20 * pulse
	canvas.draw_arc(at, radius + pulse * BREATH, 0.0, TAU, 28, glow, 1.2, true)
	if order == Order.MOVE:
		_wake(canvas, at, radius, heading, pulse)
		return
	# Work and station: a brass bead walks the rim, so a crew at work reads as
	# turning in place while a march reads as leaving.
	var angle: float = time * 1.7 + phase
	var bead: Color = Palette.GOLD
	bead.a = 0.5 + 0.4 * pulse
	canvas.draw_circle(at + Vector2(cos(angle), sin(angle)) * radius, 1.6, bead)


## Two strokes sliding astern of a marching marker: the water she leaves.
static func _wake(
	canvas: CanvasItem, at: Vector2, radius: float, heading: Vector2, pulse: float
) -> void:
	var astern: Vector2 = -heading.normalized()
	if astern == Vector2.ZERO:
		astern = Vector2.LEFT
	for index in 2:
		var shade: Color = Palette.GOLD_PALE
		shade.a = 0.34 - float(index) * 0.12
		var slip: float = radius + 2.0 + float(index) * 2.6 + pulse * 1.4
		canvas.draw_line(at + astern * slip, at + astern * (slip + 2.6), shade, 1.2, true)
