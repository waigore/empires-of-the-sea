class_name CivilianRosterRow
extends LedgerRow
## One civilian in the roster: painted medallion, posting, order status and a
## Visit action that opens the unit's map. The Visit seal is a thumb-sized door
## (REQ-P5-01, REQ-P5-04). The skeleton and the Visit seal come from LedgerRow.

signal visit_pressed(region: int, unit_id: int)

## The mark the counsel reads by: a crew the court's own civilian pass would put
## to work this turn wears it before its craft (DR-20261122-06).
const COURT_MARK: String = "▸"

## Whether the court would put this crew to work this turn; the roster sets it
## before `setup` from its own reading.
var court: bool = false

var _icon: CivilianIcon = null
var _status: Label = null
var _progress: ProgressBar = null


func _build_icon() -> Control:
	_icon = CivilianIcon.new(String(data.get("type_id", "explorer")), 44.0 if compact else 52.0)
	return _icon


func _build_state(state: VBoxContainer) -> void:
	state.add_theme_constant_override("separation", 4)
	state.custom_minimum_size = Vector2(190, 0)
	state.visible = not compact
	_status = UiRowBuilder.wrapped_line("", 12, Palette.TEXT)
	state.add_child(_status)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 5)
	_progress.add_theme_stylebox_override(
		"background", UiTheme.box(Color(0.28, 0.23, 0.16, 0.9), Color(0, 0, 0, 0), 0, 2, Vector4.ZERO)
	)
	_progress.add_theme_stylebox_override(
		"fill", UiTheme.box(Palette.GOLD, Palette.GOLD_PALE, 0, 2, Vector4.ZERO)
	)
	state.add_child(_progress)


func _fill() -> void:
	var working: bool = bool(data.get("working", false))
	var aboard: bool = bool(data.get("aboard", false))
	var role: String = String(data.get("role", "Civilian"))
	# The counsel's mark leads the craft, so a crown finds the crews the court
	# would put to work among twenty rows (DR-20261122-06).
	_name.text = ("%s %s" % [COURT_MARK, role]) if court else role
	# A crew aboard a squadron is off the map and takes no order, so the chip
	# names that duty instead of calling it idle (wiki: civilian-units
	# § Overseas deployment).
	_chip.text = "AT WORK" if working else ("ABOARD" if aboard else "IDLE")
	_paint_chip(Palette.GOLD if working else Color(0.66, 0.60, 0.46))
	_detail.text = _detail_text(aboard)
	_status.text = String(data.get("status_text", ""))
	_progress.visible = working and not compact
	_progress.value = float(data.get("progress", 0.0))
	_visit.tooltip_text = "Open %s on the map" % String(data.get("province_name", "this unit"))


## The posting line. A crew aboard a squadron has no map tile, so it names the
## duty and the chart instead of a tile that does not exist (wiki: civilian-units
## § Overseas deployment).
func _detail_text(aboard: bool) -> String:
	var place: String = String(data.get("province_name", "Open country"))
	var region: String = String(data.get("region_label", "Uncharted"))
	if aboard:
		return "%s  ·  Aboard a squadron" % region
	if compact:
		return "%s  ·  %s  ·  %s" % [place, region, String(data.get("short_status", "Idle"))]
	var tile: Vector2i = data.get("tile", Vector2i.ZERO)
	return "%s  ·  %s  ·  tile %d, %d" % [place, region, tile.x, tile.y]


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("unit_id", -1)))
