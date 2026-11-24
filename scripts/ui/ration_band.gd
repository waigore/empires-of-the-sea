class_name RationBand
extends Label
## One dossier's ration band: the share of the bill the crown's last Consumption
## fed, dressed, worded and gated in one place (wiki: combat § Feeding modifiers;
## workers-and-population § Consumption — naval combat; DR-20261124-02,
## DR-20261124-15).
##
## The field's standard and the sea's squadron read the same ladder, but each
## owns its own words: `ArmyRationRead` names the bill and the engagements, and
## `NavyRationRead` names the hulls and the sea battles. So the sheet hands over
## its rule's three reads — the line, the tip and the multiplier — and this
## label owns only the dress every sheet shares: the fold, the hidden face until
## a reading stands, the tip beside the words, and the gold a hungry crown wears
## so the bite is seen before the next fight. A `NO_READING` band prints no row,
## because another court's larder is not the crown's to read (REQ-P3-01,
## REQ-P5-06, REQ-P5-07).

## A band in the surface's own size, hidden until a reading stands: the fold, the
## dim ink and the empty face every sheet's band wears, so no sheet restates them.
## The sheet mounts it where the strength line it scales sits.
static func make(pixels: int) -> RationBand:
	var band := RationBand.new()
	band.add_theme_font_size_override("font_size", pixels)
	band.add_theme_color_override("font_color", Palette.TEXT_DIM)
	band.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	band.visible = false
	return band


## Prints the rule's own line for the coverage the opening carried, or stands
## the row down. `line`, `tip` and `multiplier` are the sheet's rule — the three
## reads that word one ladder — so this band never restates the rule and never
## contradicts the figure the resolver scales by.
static func show_line(
	band: RationBand, coverage: float, line: Callable, tip: Callable, multiplier: Callable
) -> void:
	var words: String = String(line.call(coverage))
	band.text = words
	band.visible = not words.is_empty()
	band.tooltip_text = String(tip.call(coverage))
	var hungry: bool = coverage >= 0.0 and float(multiplier.call(coverage)) < 1.0
	band.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if hungry else Palette.TEXT_DIM
	)


## The band's words, for tests and tooling (REQ-P3-02). Empty when the sheet
## holds no reading for the force on show.
static func text_of(band: RationBand) -> String:
	return "" if band == null or not band.visible else band.text
