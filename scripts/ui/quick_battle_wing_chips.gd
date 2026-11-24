class_name QuickBattleWingChips
extends RefCounted
## The wing chips over each line of the Quick Battle plate: left, centre and
## right, inked in the side's colour, dimmed when empty and struck through when
## broken, so a collapse reads at a glance while the despatch says it in words
## (wiki: quick-battle § Wings and collapse; REQ-P1-07). Pure painters so
## [QuickBattleField] stays a thin view (REQ-P3-01, REQ-P2-03).

## The chips are drawn at a size the plate can carry: a short plate (a handset's)
## grows them so three chips still read, a tall plate keeps the published size
## (REQ-P1-07).
const CHIP_SCALE_HEIGHT: float = 300.0
const CHIP_SCALE_MAX: float = 1.5


## Whether a line's chips are drawn at all. A line that holds wings keeps them
## on the plate even when every one has emptied — that is the collapse the chips
## exist to show — while a line with no wings (a garrison behind a wall, an older
## record) draws none (wiki: quick-battle § Wings and collapse).
static func wings_shown(held: Dictionary, broken: Array) -> bool:
	if not broken.is_empty():
		return true
	for wing: String in QuickBattleWings.WINGS:
		if int(held.get(wing, 0)) > 0:
			return true
	return false


## How much the wing chips grow on a plate too short to read them at the
## published size: 1.0 on a tall plate, up to [constant CHIP_SCALE_MAX] on a
## handset's (REQ-P1-07).
static func chip_scale(height: float) -> float:
	return clampf(CHIP_SCALE_HEIGHT / maxf(height, 1.0), 1.0, CHIP_SCALE_MAX)


## Three chips over one line, centred on [param centre].
static func draw(
	canvas: CanvasItem, centre: Vector2, held: Dictionary, broken: Array,
	color: Color, plate_height: float
) -> void:
	if not wings_shown(held, broken):
		return
	var scale: float = chip_scale(plate_height)
	var chip: float = 8.0 * scale
	var gap: float = 4.0 * scale
	var span: float = float(QuickBattleWings.WINGS.size()) * (chip + gap) - gap
	var origin: float = centre.x - span * 0.5
	for index in QuickBattleWings.WINGS.size():
		var wing: String = QuickBattleWings.WINGS[index]
		var held_now: int = int(held.get(wing, 0))
		var x: float = origin + float(index) * (chip + gap)
		var down: bool = broken.has(wing)
		var ink: Color = color if held_now > 0 else color.darkened(0.6)
		ink.a = 0.85
		if down:
			ink = Color(0.86, 0.24, 0.18, 0.95)
		canvas.draw_rect(
			Rect2(x, centre.y, chip, 4.0 * scale), ink, held_now > 0 and not down
		)
		if down:
			canvas.draw_line(
				Vector2(x - scale, centre.y + 5.0 * scale),
				Vector2(x + chip + scale, centre.y - scale),
				Color(0.98, 0.86, 0.70, 0.9), 1.4 * scale
			)
