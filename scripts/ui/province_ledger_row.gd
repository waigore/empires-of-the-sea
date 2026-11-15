class_name ProvinceLedgerRow
extends LedgerRow
## One province in the crown's ledger: its medallion, where it stands, what it
## is built to, what it lacks and a Visit action that opens its map and dossier.
## The row itself is also a tap target, so a phone needs no hover (REQ-P5-01,
## REQ-P5-04). The skeleton, the tap and the Visit door come from LedgerRow;
## presentation only, every figure arrives in the row dictionary.

signal visit_pressed(region: int, province_id: int)

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
	_name.text = String(data.get("name", "Province"))
	var chip: Dictionary = _chip_reading()
	_chip.text = String(chip["text"])
	_paint_chip(chip["color"])
	var place: String = String(data.get("place", "Inland"))
	_detail.text = "%s  ·  %s" % [place, String(data.get("region_label", "Uncharted"))]
	if compact:
		_detail.text = "%s  ·  %s  ·  %s" % [
			place,
			String(data.get("line", "")),
			String(data.get("region_label", "Uncharted")),
		]
	_standing.text = String(data.get("line", ""))
	_reading.text = String(data.get("state", ""))
	_visit.tooltip_text = "Open %s on the map" % String(data.get("name", "the province"))


## The one word the row carries: the seat, else the first thing it lacks, so a
## crown reads its worst province before its name (REQ-P5-03).
func _chip_reading() -> Dictionary:
	if bool(data.get("capital", false)):
		return {"text": "SEAT", "color": Palette.GOLD}
	var flags: Array = data.get("flags", [])
	if flags.has(ProvinceLedger.FILTER_CUT):
		return {"text": "CUT OFF", "color": Palette.CRIMSON}
	if flags.has(ProvinceLedger.FILTER_UNGARRISONED):
		return {"text": "UNGARRISONED", "color": Palette.SURVEY_BUILDING}
	if flags.has(ProvinceLedger.FILTER_WORKS):
		return {"text": "WORKS", "color": Palette.GOLD_DIM}
	return {"text": "HELD", "color": Palette.GOLD_DIM}


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("id", -1)))


func _icon_kind() -> String:
	return "crown" if bool(data.get("capital", false)) else "compass"
