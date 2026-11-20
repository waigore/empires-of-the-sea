class_name CloseSeal
extends Button
## The one close control every dismissible panel wears: an antique medallion
## pinned to the panel header's right, so a player always finds the same door and
## no sheet invents a text "Close" of its own (docs/ui-panels.md).
##
## The seal is chrome, not a rule: it carries no state and knows no panel. A
## sheet connects its `pressed` to the panel's own close signal, and Escape and
## Back keep working beside it (REQ-P1-05, REQ-P1-07, REQ-P5-07, REQ-P3-01).

## A thumb finds the seal on a phone and a pointer finds it on the chart: the
## same floor everywhere, so no header can shrink the door below a tap
## (REQ-P1-05).
const SIZE: Vector2 = Vector2(44.0, 44.0)
## The medallion draws at the shell icons' 22-point scale.
const GLYPH_PIXELS: int = 22
const TIP: String = "Close"


## One seal in the shell's medallion family. Every panel builds its close door
## here, so the glyph, the target and the words are written once.
static func make(tip: String = TIP) -> CloseSeal:
	var seal := CloseSeal.new()
	seal.name = "CloseSeal"
	seal.tooltip_text = tip
	seal.custom_minimum_size = SIZE
	seal.size_flags_horizontal = Control.SIZE_SHRINK_END
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ChromeIcons.apply(seal, "close", GLYPH_PIXELS)
	return seal
