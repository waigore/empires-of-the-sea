class_name MarketBatchPress
extends RefCounted
## The market sheet's batch press: one full-width button under a commodity row
## that files `units` as a single order, so a court buying a turn's ration never
## taps Bid ten times (wiki: world-market § Trade orders — one order carries a
## positive integer quantity; REQ-P5-04, REQ-P5-05).
##
## The sibling of the workers ledger's `Recruit ×N` press: the count comes from
## the rules (`MarketBatch`), the single press stays beside it so a batch is
## never forced, and the label names the whole order's ducats so the press is
## never a surprise (REQ-P1-07, REQ-P5-07).

const HEIGHT: float = 38.0
## A phone viewport wants thumb-sized targets, like every other press (REQ-P5-07).
const TOUCH_HEIGHT: float = 44.0


## The label one press prints: the side, the units and the order's whole value.
static func line(side: String, units: int, total: int) -> String:
	if total <= 0:
		return "%s ×%d" % [side, units]
	return "%s ×%d  ·  %d ducats" % [side, units, total]


## One press. `on_press` is the sheet's own intent signal, so the button never
## decides an outcome (REQ-P2-03).
static func build(
	side: String, units: int, commodity: String, total: int, compact: bool,
	on_press: Callable
) -> Button:
	var button := UiRowBuilder.button(
		line(side, units, total), TOUCH_HEIGHT if compact else HEIGHT, 0.0
	)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "Files one order for %d %s — it clears when the turn closes." % [
		units, CommodityCatalog.label(commodity),
	]
	button.pressed.connect(on_press)
	return button


## Adds the press under `row` when the rules allow more than one unit, and
## returns it — null when a single press is the whole order, so a row that can
## only carry one ton reads exactly as it did before (REQ-P1-07). `total` is the
## whole order's ducats as the clearing will charge them (one rounding for the
## deal, never a sum of per-unit roundings).
static func attach(
	row: Control, side: String, units: int, commodity: String, total: int,
	compact: bool, on_press: Callable
) -> Button:
	if units <= 1:
		return null
	var button := build(side, units, commodity, total, compact, on_press)
	row.add_child(button)
	return button
