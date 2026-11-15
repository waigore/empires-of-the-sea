class_name ProvinceLedgerPanel
extends LedgerSheet
## The crown's provinces: every province it holds in the Old and New World in
## one ledger, narrowed by chart and by what the province lacks, with a Visit
## action that opens the province's map and dossier (wiki: world-model
## § Provinces and Tiles; DR-20261115-09). The projection lives in
## [ProvinceLedger] and the map hooks in [MapPlayProvinces]; this class only
## renders rows and asks for the jump (REQ-P3-02, REQ-P3-03). The sheet chrome,
## fade and pause-door park come from SheetFrame; the chips, rows and empty
## notice from LedgerSheet.

## The realm prints each province's town level; the towns sheet is the step
## that raises it, so the door sits on the reading that raises the question
## (DR-20261115-12).
signal towns_pressed


func _init() -> void:
	title_text = "THE CROWN'S PROVINCES"
	hint_text = (
		"Visit opens the province's map and dossier. The roll reads each "
		+ "province as it stands; it never orders a work or a march."
	)
	toggle_action = InputActions.PROVINCE_LEDGER


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both charts for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = MapPlayProvinces.snapshot(play)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("compass", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Chart", "Reading", ProvinceLedger.FILTERS, ProvinceLedger.filter_label,
		_towns_door
	)


## The door to the crown's towns: the realm prints the level, the towns sheet
## prints the step that raises it, and the press is one reach from here
## (REQ-P5-01, REQ-P5-04; DR-20261115-12). A full-width row keeps it a
## thumb-sized tap on a phone sheet.
func _towns_door() -> Control:
	var door := Button.new()
	door.text = "Towns ›"
	door.tooltip_text = "Every town the crown holds, and the step that raises it (B)"
	door.custom_minimum_size = Vector2(0, 34)
	door.add_theme_font_size_override("font_size", 12)
	door.pressed.connect(func() -> void: towns_pressed.emit())
	return door


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = ProvinceLedger.groups(_snapshot, _region, _reading)
	var shown: int = ProvinceLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


func _empty_text() -> String:
	return "No province answers this view. Clear a filter to see the whole realm."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d province%s" % [
		String(group["region_label"]).to_upper(), count, "" if count == 1 else "s"
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := ProvinceLedgerRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


## The count line names the filter and what the view means, so a crown reads
## what it is looking at before it reads a row (REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = ProvinceLedger.filter_counts(_snapshot, _region)
	var line: String = "Showing %d of %d provinces %s — %d cut off, %d ungarrisoned, %d at works." % [
		shown,
		int(_snapshot.get("total", 0)),
		LedgerRows.scope_text(_region),
		int(counts.get(ProvinceLedger.FILTER_CUT, 0)),
		int(counts.get(ProvinceLedger.FILTER_UNGARRISONED, 0)),
		int(counts.get(ProvinceLedger.FILTER_WORKS, 0)),
	]
	if _reading != ProvinceLedger.FILTER_ALL:
		line += " Reading: %s only." % ProvinceLedger.filter_label(_reading).to_lower()
	return line


func _visit(region: int, province_id: int) -> void:
	if play == null:
		return
	if MapPlayProvinces.focus(play, region, province_id):
		close()
