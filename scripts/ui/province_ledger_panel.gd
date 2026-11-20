class_name ProvinceLedgerPanel
extends LedgerSheet
## The crown's realm: every province it holds in the Old and New World in one
## sheet, read three ways — what it yields, how hard it is to hold and how far
## it sits from the seat — narrowed by chart and ordered by the view's own
## figure, with a Visit action that opens the province's map and dossier (wiki:
## world-model § Provinces and Tiles; capital-and-connectivity).
##
## The projection lives in [ProvinceLedger] and the map hooks in
## [MapPlayProvinces]; this class only renders the rows and asks for the jump
## (REQ-P3-02, REQ-P3-03). The sheet chrome, fade and pause-door park come from
## SheetFrame; the chips, rows and empty notice from LedgerSheet.

## The order the view opens on; a press of another chip reorders the rows.
var _sort: String = ProvinceLedger.SORT_VALUE


func _init() -> void:
	title_text = "THE CROWN'S REALM"
	hint_text = (
		"Visit opens the province's map and dossier. Each view reads the realm "
		+ "as it stands; it never orders a work or a march."
	)
	toggle_action = InputActions.PROVINCE_LEDGER
	_reading = ProvinceLedger.VIEW_ECONOMY


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
		column, "Chart", "View", ProvinceLedger.VIEWS, ProvinceLedger.view_label
	)
	_bar.sort_chosen.connect(_on_sort)


# --- filters -----------------------------------------------------------------


## A sort chip was pressed: the rows keep the same chart and view, only their
## order changes, so the sheet repaints without a fresh harvest walk.
func _on_sort(key: String) -> void:
	_sort = key
	_apply_filter()


func _apply_filter() -> void:
	if not ProvinceLedger.sort_keys(_reading).has(_sort):
		_sort = ProvinceLedger.sort_default(_reading)
	_bar.fill_sort(
		"Order", ProvinceLedger.sort_keys(_reading), ProvinceLedger.sort_label, _sort
	)
	var groups: Array[Dictionary] = ProvinceLedger.groups(_snapshot, _region, _reading, _sort)
	_paint_filtered(groups, ProvinceLedger.count(_snapshot, _region), _heading, _make_row)
	_bar.render_sort(_sort)


# --- rows --------------------------------------------------------------------


func _empty_text() -> String:
	return "No province answers this view. Clear a filter to see the whole realm."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d province%s" % [
		String(group["region_label"]).to_upper(), count, "" if count == 1 else "s"
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := ProvinceLedgerRow.new()
	row.compact = compact
	row.view = _reading
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


## The count line names the view and what orders it, so a crown reads what it is
## looking at before it reads a row (REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = _snapshot.get("counts", {})
	return "Showing %d of %d provinces %s — %d cut off, %d ungarrisoned, %d at works. %s, ordered by %s." % [
		shown,
		int(_snapshot.get("total", 0)),
		LedgerRows.scope_text(_region),
		int(counts.get("cut_off", 0)),
		int(counts.get("ungarrisoned", 0)),
		int(counts.get("works", 0)),
		String(ProvinceLedger.view_label(_reading)),
		String(ProvinceLedger.sort_label(_sort)).to_lower(),
	]


func _visit(region: int, province_id: int) -> void:
	if play == null:
		return
	if MapPlayProvinces.focus(play, region, province_id):
		close()
