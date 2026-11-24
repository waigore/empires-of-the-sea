class_name PressNote
extends RefCounted
## The one line under a crew press: what the order spends, how long it waits and
## what it buys while the press is open, and the rules' own refusal while it is
## shut — printed, never hovered, so a phone reads what a tap costs and why it is
## dead (wiki: civilian-units § Work Order Summary; REQ-P1-05, REQ-P5-05,
## REQ-P5-07; DR-20261125-08).
##
## One home for the shape the province dossier's Build road and Lay railroad
## presses print. A press whose price, wait and gate live only in a tooltip
## reads as a greyed button with no word why on a handset, which keeps no hover.

## A shut press's clause on the dark dossier sheet: crimson lifted toward white,
## so the gate stays legible on a phone (REQ-P1-07).
const GATE_INK := Color(0.765, 0.460, 0.460)


## The note line itself: a wrapped label under the press, hidden until a press
## paints it.
static func line(width: float = 0.0) -> Label:
	var note := UiRowBuilder.wrapped_line("", 11, Palette.GOLD, width)
	note.visible = false
	return note


## What an open press spends and buys: `1 lumber + 1 cast iron · 1 turn — an
## Engineer lays the last road tile to Timber`. Every figure is the caller's, read
## off the rules that charge the order; a price the order waives prints its wait
## alone.
static func step(price: String, turns: int, buys: String) -> String:
	var wait: int = maxi(turns, 1)
	var parts: PackedStringArray = PackedStringArray()
	if not price.is_empty():
		parts.append(price)
	parts.append("%d turn%s" % [wait, "" if wait == 1 else "s"])
	return "%s — %s" % [" · ".join(parts), buys]


## Paints one note: the open step in the sheet's gold, the shut gate in the
## gate's ink, and nothing at all when the caller has no reading to print.
static func paint(note: Label, text: String, open: bool) -> void:
	if note == null:
		return
	note.text = text
	note.visible = not text.is_empty()
	note.add_theme_color_override(
		"font_color", Palette.GOLD if open else GATE_INK
	)
