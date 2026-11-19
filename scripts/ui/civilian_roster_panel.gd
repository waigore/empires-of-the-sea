class_name CivilianRosterPanel
extends LedgerSheet
## Whole-empire civilian roster (REQ-P5-01, REQ-P5-03): every unit in the Old
## and New World in one ledger, filtered by region or craft, with a Visit action
## that opens the unit's map and dossier. The data projection lives in
## CivilianRoster; this class only renders rows and emits no rules calls. The
## sheet chrome, fade and pause-door park come from SheetFrame; the rows and
## their empty notice from LedgerSheet. Its own head carries three filter rows
## (world, craft, orders), so it builds those from the head instead of the
## two-row [LedgerFilterBar].

var _head: CivilianRosterHead = null
var _type: String = CivilianRosterHead.TYPE_ALL
var _status: String = CivilianRoster.STATUS_ALL


func _init() -> void:
	title_text = "THE CROWN'S PEOPLE"
	hint_text = (
		"Visit opens the civilian's map and dossier. Filter by world, craft or "
		+ "who waits for orders; the C key opens this roster from anywhere on the map."
		+ " Find the next crew that waits takes you to an idle one, in either world."
	)
	toggle_action = InputActions.CIVILIAN_ROSTER


func refresh() -> void:
	if play == null or play.world == null or play.civilian_layer == null:
		return
	_snapshot = CivilianRoster.snapshot(
		play.world, play.civilian_layer.regions, play.player_faction
	)
	_head.render(_snapshot, _region, _type, _status)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return CivilianIcon.new("explorer", 42.0)


func _can_open() -> bool:
	return super._can_open() and play.civilian_layer != null


func _build_body(column: VBoxContainer) -> void:
	_head = CivilianRosterHead.new()
	_head.filter_changed.connect(_on_head_filter)
	_head.find_idle_pressed.connect(_find_idle)
	column.add_child(_head)
	_build_rows(column)


func _apply_profile(compact: bool, narrow: bool) -> void:
	super._apply_profile(compact, narrow)
	if _head != null:
		_head.set_compact(compact)


# --- rows --------------------------------------------------------------------


func _on_head_filter(region_key: String, type_id: String, status_key: String) -> void:
	_region = region_key
	_type = type_id
	_status = status_key
	_head.render(_snapshot, _region, _type, _status)
	_apply_filter()


func _apply_filter() -> void:
	var groups: Array[Dictionary] = CivilianRoster.groups(
		_snapshot, _region, _type, _status
	)
	var shown: int = CivilianRoster.count(_snapshot, _region, _type, _status)
	_paint_filtered(groups, shown, _heading, _make_row)


## The civilian roster's headings name the province as well as the chart: a
## crew is posted on a tile, so the ground it stands on is part of the reading.
func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %s  ·  %d civilian%s" % [
		String(group["region_label"]).to_upper(),
		String(group["province_name"]).to_upper(),
		count,
		"" if count == 1 else "s",
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := CivilianRosterRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


func _subtitle_text(shown: int) -> String:
	var scope: String = "in both worlds"
	if _region == LedgerRows.REGION_OLD:
		scope = "in the Old World"
	elif _region == LedgerRows.REGION_NEW:
		scope = "in the New World"
	var craft: String = ""
	if not _type.is_empty():
		craft = " · %s only" % CivilianCatalog.display_name(_type)
	var orders: String = ""
	if _status != CivilianRoster.STATUS_ALL:
		orders = " · %s only" % CivilianRoster.status_label(_status).to_lower()
	return "Showing %d of %d civilians %s%s%s. %s" % [
		shown, int(_snapshot.get("total", 0)), scope, craft, orders, _tail_text()
	]


## The line under the count says what the view is for, so the idle reading never
## reads like the whole roster (REQ-P5-05).
func _tail_text() -> String:
	if _status == CivilianRoster.STATUS_IDLE:
		return "Every one of them waits for an order."
	if _status == CivilianRoster.STATUS_WORKING:
		return "Their orders are paid and running."
	return "Idle crews wait for orders."


## An empty view names the filter that emptied it, so a crown never reads a
## filter for a lost unit (REQ-P5-05).
func _empty_text() -> String:
	if _status == CivilianRoster.STATUS_IDLE:
		return "No idle crews — every civilian in this view has an order."
	if _status == CivilianRoster.STATUS_WORKING:
		return "No civilian in this view is at work. Clear the filter to see who waits."
	return (
		"No civilians answer this view. Train another at the capital, or clear "
		+ "a filter."
	)


func _visit(region: int, unit_id: int) -> void:
	if play == null:
		return
	if MapPlayCivilianRoster.focus(play, region, unit_id):
		close()


## The chore's own door: the next crew that waits is brought under the camera and
## its dossier opened, the chart swapping when it lies on the other world, and
## the sheet steps aside so the crown sees the crew it was sent to (REQ-P5-03).
## The walk starts after the crew already selected, so pressing again covers the
## whole column; the receipt names the crew and how many still wait behind it.
func _find_idle() -> void:
	if play == null or play.civilian_layer == null:
		return
	var selected: CivilianState = play.civilian_layer.selected_unit
	var unit_id: int = selected.id if selected != null else -1
	var next: Dictionary = CivilianRoster.next_idle(_snapshot, play.region_index, unit_id)
	if next.is_empty():
		play.hud.toast(CivilianRoster.IDLE_NONE)
		return
	if not MapPlayCivilianRoster.focus(play, int(next["region"]), int(next["unit_id"])):
		play.hud.toast(CivilianRoster.IDLE_NONE)
		return
	close()
	play.hud.toast(
		CivilianRoster.idle_receipt(next, int(_snapshot.get("idle", 0)) - 1)
	)
