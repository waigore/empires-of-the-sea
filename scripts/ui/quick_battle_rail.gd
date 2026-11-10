class_name QuickBattleRail
extends RefCounted
## Drawing helpers for the Quick Battle condition strip: one health chip and
## chevron per regiment, plus the floating damage numbers a blow left. Pure
## painters so [QuickBattleField] stays a view (REQ-P3-01, REQ-P1-07).

const MAX_CHIPS: int = 12
const CHIP_STEP: float = 11.0
const CHIP_HEIGHT: float = 14.0
const FLOATER_SECONDS: float = 1.1


static func draw(
	canvas: CanvasItem,
	attacker: Array,
	attacker_count: int,
	attacker_color: Color,
	defender: Array,
	defender_count: int,
	defender_color: Color,
	width: float,
	height: float
) -> void:
	var base: float = height - 4.0
	_rail(canvas, attacker, attacker_count, 8.0, base, attacker_color)
	var shown: int = mini(maxi(defender_count, defender.size()), MAX_CHIPS)
	_rail(canvas, defender, defender_count, width - 8.0 - float(shown) * CHIP_STEP,
		base, defender_color)


static func _rail(
	canvas: CanvasItem, entries: Array, count: int, x: float, y: float, color: Color
) -> void:
	var shown: int = mini(maxi(count, entries.size()), MAX_CHIPS)
	for index in shown:
		var data: Dictionary = entries[index] if index < entries.size() else {}
		var fraction: float = clampf(float(data.get("fraction", 1.0)), 0.0, 1.0)
		var left: float = x + float(index) * CHIP_STEP
		canvas.draw_rect(
			Rect2(left, y - CHIP_HEIGHT, 8.0, CHIP_HEIGHT), Color(0.06, 0.05, 0.04, 0.78)
		)
		var fill: Color = Palette.HEALTH_HIGH.lerp(Palette.HEALTH_LOW, 1.0 - fraction)
		if fraction > 0.0:
			canvas.draw_rect(
				Rect2(
					left, y - CHIP_HEIGHT + CHIP_HEIGHT * (1.0 - fraction),
					8.0, CHIP_HEIGHT * fraction
				),
				fill.lerp(color, 0.25)
			)
		if int(data.get("medals", 0)) > 0:
			canvas.draw_texture_rect(
				ChromeIcons.texture("chevron"), Rect2(left, y - CHIP_HEIGHT - 9.0, 8.0, 8.0), false
			)


## Damage numbers rise and fade over the side they struck.
static func floaters(canvas: CanvasItem, floaters: Array) -> void:
	var font: Font = UiTheme.serif()
	for floater: Dictionary in floaters:
		var alpha: float = clampf(float(floater["life"]) / FLOATER_SECONDS, 0.0, 1.0)
		var text: String = String(floater["text"])
		var pos: Vector2 = floater["pos"]
		var color: Color = floater["color"]
		canvas.draw_string_outline(
			font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3,
			Color(0.06, 0.05, 0.04, alpha)
		)
		canvas.draw_string(
			font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(color.r, color.g, color.b, alpha)
		)
