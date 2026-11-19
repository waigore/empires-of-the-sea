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

## The steps a realm reading is one press from: the roll prints each province's
## town level, its fort and its ward, so the sheets that raise them sit under
## the reading that asks (DR-20261115-12, DR-20261116-01, DR-20261116-02). Each
## door names its sheet by the HUD's door key.


func _init() -> void:
	title_text = "THE CROWN'S PROVINCES"
	hint_text = (
		"Visit opens the province's map and dossier. The roll reads each "
		+ "province as it stands; it never orders a work or a march."
	)
	toggle_action = InputActions.PROVINCE_LEDGER


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
		_doors
	)


## The doors a step is one reach from the reading that raises it: the realm
## prints the town level, the fort and the ward, so the towns, walls and
## hospitals sheets are the steps that raise them (REQ-P5-01, REQ-P5-04;
## DR-20261115-12, DR-20261116-01, DR-20261116-02). Full-width rows keep each a
## thumb-sized tap on a phone; the dress and the key press are SheetFrame's.
func _doors() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_door(
		"Towns ›", "Every town the crown holds, and the step that raises it (B)",
		HudLedgerDoors.TOWNS
	))
	row.add_child(_door(
		"Walls ›", "Every wall the crown holds, and the step that raises it (V)",
		HudLedgerDoors.WALLS
	))
	row.add_child(_door(
		"Hospitals ›", "Every ward the crown holds, and the step that raises it",
		HudLedgerDoors.HOSPITALS
	))
	return row


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = ProvinceLedger.groups(_snapshot, _region, _reading)
	var shown: int = ProvinceLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


func _empty_text() -> String:
	return "No province answers this view. Clear a filter to see the whole realm."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d province%s" % [
		String(group["region_label"]).to_upper(), count, MoneyText.plural(count)
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
