class_name LedgerList
extends RefCounted
## The body a crown ledger prints under its filters: one gold heading per chart
## group and the rows it holds — or, for a sheet that reads one ungrouped pool
## (the crown's command), the rows alone. The clear that keeps the empty notice,
## the heading dress and the one phone-size decision are written once, so a new
## sheet inherits them instead of copying them (REQ-P3-01, RUB-P3-01,
## REQ-P1-07).
##
## Presentation only: the sheet names its heading and mints its own row, so the
## figures stay in the projection and the press stays an intent (REQ-P3-02).

const HEADING_PIXELS: int = 11


## Clears `list` for a repaint, keeping the empty notice that lives in it.
static func clear(list: VBoxContainer, keep: Control) -> void:
	for child: Node in list.get_children():
		if child == keep:
			continue
		list.remove_child(child)
		child.queue_free()


## True when the chart is a phone's: a row is built at phone sizes once, never
## resized after the fact.
static func is_compact(list: Control) -> bool:
	return HudLayout.is_compact(list.get_viewport_rect().size)


## Paints every group: a heading from `heading(group, count)` and the rows it
## holds, each minted by `row(raw, compact)`. A sheet that needs a standing line
## under its heading returns its own Control from `heading`.
static func fill(
	list: VBoxContainer,
	keep: Control,
	groups: Array[Dictionary],
	heading: Callable,
	row: Callable
) -> void:
	clear(list, keep)
	var compact: bool = is_compact(list)
	for group: Dictionary in groups:
		var rows: Array = group["rows"]
		list.add_child(heading.call(group, rows.size()))
		_append(list, rows, row, compact)


## The one-line gold heading most sheets print; a sheet with more to say builds
## its own Control instead.
static func heading(text: String) -> Label:
	return UiRowBuilder.label(text, HEADING_PIXELS, Palette.GOLD_DIM)


## Paints rows with no heading between them: one reading, printed straight down.
static func flat(
	list: VBoxContainer, keep: Control, rows: Array, row: Callable
) -> void:
	clear(list, keep)
	_append(list, rows, row, is_compact(list))


static func _append(list: VBoxContainer, rows: Array, row: Callable, compact: bool) -> void:
	for raw: Variant in rows:
		list.add_child(row.call(raw, compact))
