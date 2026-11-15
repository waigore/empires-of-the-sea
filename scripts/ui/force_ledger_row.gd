class_name ForceLedgerRow
extends LedgerRow
## One army or squadron in the muster roll: its medallion, where it stands, what
## it carries and a Visit action that opens its map and dossier. The row itself
## is also a tap target, so a phone needs no hover (REQ-P5-01, REQ-P5-04). The
## skeleton, the tap and the Visit door come from LedgerRow.

signal visit_pressed(region: int, kind: String, id: int)

var _icon: Icon = null
var _standing: Label = null
var _reading: Label = null


func _build_icon() -> Control:
	_icon = Icon.new(_icon_kind(), 40.0 if compact else 46.0, Palette.GOLD)
	return _icon


func _build_state(state: VBoxContainer) -> void:
	state.add_theme_constant_override("separation", 3)
	state.custom_minimum_size = Vector2(190, 0)
	state.visible = not compact
	_standing = UiRowBuilder.wrapped_line("", 12, Palette.TEXT)
	state.add_child(_standing)
	_reading = UiRowBuilder.wrapped_line("", 11, Palette.TEXT_DIM)
	state.add_child(_reading)


func _fill() -> void:
	var kind: String = String(data.get("kind", ForceLedger.KIND_ARMY))
	_name.text = String(data.get("title", "Force"))
	_chip.text = kind.to_upper()
	_paint_chip(Palette.GOLD if kind == ForceLedger.KIND_SQUADRON else Palette.GOLD_DIM)
	var place: String = String(data.get("place", "Open country"))
	_detail.text = "%s  ·  %s" % [place, String(data.get("region_label", "Uncharted"))]
	if compact:
		_detail.text = "%s  ·  %s  ·  %s" % [
			place,
			String(data.get("line", "")),
			String(data.get("region_label", "Uncharted")),
		]
	_standing.text = String(data.get("line", ""))
	_reading.text = String(data.get("state", ""))
	_visit.tooltip_text = "Open %s on the map" % place


func _on_visit() -> void:
	visit_pressed.emit(
		int(data.get("region", 0)),
		String(data.get("kind", ForceLedger.KIND_ARMY)),
		int(data.get("id", -1))
	)


func _icon_kind() -> String:
	var kind: String = String(data.get("kind", ForceLedger.KIND_ARMY))
	return "anchor" if kind == ForceLedger.KIND_SQUADRON else "crest"
