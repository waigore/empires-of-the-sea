class_name CivilianRosterRow
extends LedgerRow
## One civilian in the roster: painted medallion, posting, order status and a
## Visit action that opens the unit's map. The row itself is also a tap target
## (REQ-P5-01, REQ-P5-04). The skeleton, the tap and the Visit door come from
## LedgerRow.

signal visit_pressed(region: int, unit_id: int)

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
	_name.text = String(data.get("role", "Civilian"))
	_chip.text = "AT WORK" if working else "IDLE"
	_paint_chip(Palette.GOLD if working else Color(0.66, 0.60, 0.46))
	_detail.text = "%s  ·  %s  ·  tile %d, %d" % [
		String(data.get("province_name", "Open country")),
		String(data.get("region_label", "Uncharted")),
		Vector2i(data.get("tile", Vector2i.ZERO)).x,
		Vector2i(data.get("tile", Vector2i.ZERO)).y,
	]
	if compact:
		_detail.text = "%s  ·  %s  ·  %s" % [
			String(data.get("province_name", "Open country")),
			String(data.get("region_label", "Uncharted")),
			String(data.get("short_status", "Idle")),
		]
	_status.text = String(data.get("status_text", ""))
	_progress.visible = working and not compact
	_progress.value = float(data.get("progress", 0.0))
	_visit.tooltip_text = "Open %s on the map" % String(data.get("province_name", "this unit"))


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("unit_id", -1)))
