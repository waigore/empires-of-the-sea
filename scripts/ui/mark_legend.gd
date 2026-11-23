class_name MarkLegend
extends RefCounted
## The sentence that says what the court's `▸` means, mounted where the mark is
## read (REQ-P1-07, REQ-P5-07; DR-20261123-03, DR-20261123-08).
##
## A sheet's footer hint is dropped on a compact profile, so a mark explained
## only there is a mark a phone cannot read — and a card or a drawer that keeps
## no footer at all explains it nowhere. One home for the dress: the size, the
## colour, the wrap and the rule that the sentence stands only while the reading
## that paints the mark names a row. A surface names its own words (the mark
## says something different on the estates card and on the yard) and hands its
## own reading's answer, so the sentence and the glyph can never disagree
## (REQ-P3-01, REQ-P5-06).

## The step the sentence prints at: the footer hint's own, so a legend never
## outshouts the reading it explains.
const PIXELS: int = 10


## The sentence, wrapped and dim, hidden until a mark stands. Null when the
## surface names no words — a sheet whose rows wear no mark. `host` takes it
## where the mark is read; a block that mounts its legend on demand hands none
## and adds it itself.
static func make(words: String, host: Container = null) -> Label:
	if words.is_empty():
		return null
	var legend := UiRowBuilder.wrapped_line(words, PIXELS, Palette.TEXT_DIM)
	legend.visible = false
	if host != null:
		host.add_child(legend)
	return legend


## Stands the sentence beside the marks it explains, or stands it down: a quiet
## surface never explains a glyph it does not print (REQ-P5-06).
static func stand(legend: Label, shown: bool) -> void:
	if legend != null:
		legend.visible = shown
