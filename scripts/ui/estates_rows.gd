class_name EstatesRows
extends RefCounted
## How the estates door paints its province groups and rows. Kept out of
## [ImprovementPanel] so the door stays under the P3 size bar (REQ-P3-01);
## presentation only — every reading comes from [EstateLedger], and every row
## is an [ImprovementRow] that emits intents (REQ-P3-02, REQ-P3-03).


## Clears `host` and fills it with the groups the current province and chip
## reading leave. `marks` are the counsel pick's own tile keys; a row whose tile
## is among them wears the court's mark (DR-20261122-04). `heading_compact` is
## the plate profile; `row_compact` is the viewport geometry the rows fold to.
## Empty when nothing matches — the door still says so, so a chip press never
## leaves a blank page (REQ-P5-03).
static func fill(
	host: VBoxContainer,
	snapshot: Dictionary,
	province_id: int,
	filter_key: String,
	marks: Dictionary,
	heading_compact: bool,
	row_compact: bool,
	on_build: Callable,
	on_cancel: Callable,
	on_focus: Callable
) -> void:
	clear(host)
	if host == null:
		return
	var groups: Array[Dictionary] = EstateLedger.grouped(snapshot)
	var shown: int = 0
	for group: Dictionary in EstateLedger.in_province(groups, province_id):
		var rows: Array[Dictionary] = EstateLedger.matching(group["rows"], filter_key)
		if rows.is_empty():
			continue
		shown += rows.size()
		add_group(
			host, group, rows, marks, heading_compact, row_compact,
			on_build, on_cancel, on_focus
		)
	if shown == 0:
		var empty := Label.new()
		empty.text = "No estates match this view."
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		host.add_child(empty)


## One province heading and its estate rows, in the order the ledger prints them.
static func add_group(
	host: VBoxContainer,
	group: Dictionary,
	rows: Array[Dictionary],
	marks: Dictionary,
	heading_compact: bool,
	row_compact: bool,
	on_build: Callable,
	on_cancel: Callable,
	on_focus: Callable
) -> void:
	var heading := Label.new()
	heading.text = "%s  ·  %d estate%s  ·  %d producing" % [
		String(group["name"]).to_upper(),
		rows.size(),
		"" if rows.size() == 1 else "s",
		int(group["producing"]),
	]
	heading.add_theme_font_size_override("font_size", 10 if heading_compact else 11)
	heading.add_theme_color_override("font_color", Palette.GOLD_DIM)
	host.add_child(heading)
	for row: Dictionary in rows:
		var item := ImprovementRow.new()
		item.compact = row_compact
		# The row wears the mark when the reading names its tile, keyed the way
		# the pick keys its own estates (DR-20261122-04).
		item.court = marks.has(row.get("tile", CivilianState.NO_TILE))
		if on_build.is_valid():
			item.build_pressed.connect(on_build)
		if on_cancel.is_valid():
			item.cancel_pressed.connect(on_cancel)
		if on_focus.is_valid():
			item.focus_pressed.connect(on_focus)
		host.add_child(item)
		item.setup(row)


## Drops every child the list still holds so a chip press or a profile change
## can paint a fresh reading.
static func clear(host: VBoxContainer) -> void:
	if host == null:
		return
	for child: Node in host.get_children():
		host.remove_child(child)
		child.queue_free()


## Masthead line under the estates title: one province when the chart asked for
## it, the whole realm otherwise (REQ-P1-07).
static func subtitle(model: MapModel, province_id: int) -> String:
	if province_id >= 0 and model != null:
		return "%s · every resource tile in this province." % model.province_name(province_id)
	return "Every owned resource tile, its works and its road to the crown."
