class_name ColonyLedgerRow
extends LedgerRow
## One colony in the crown's ledger: the people, the court that bought it, where
## they stand, the subsidy they take and what bars their trade (wiki: diplomacy
## § GP–Tribe Rules — Join Empire, § Boycott; DR-20261117-02). Presentation only
## — [ColonyLedger] owns every figure.
##
## The row visits the colony's own capital province (a Tribe keeps its land, so
## its seat is a place on the chart) and is a tap target for it, so a phone needs
## no hover (REQ-P5-01, REQ-P5-04). The skeleton, the chip and the Visit door are
## LedgerRow's.

signal visit_pressed(region: int, province_id: int)

var _icon: TextureRect = null


func _build_icon() -> Control:
	_icon = TextureRect.new()
	_icon.texture = ChromeIcons.texture("globe")
	_icon.custom_minimum_size = Vector2(36, 36) if compact else Vector2(42, 42)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _icon


func _wants_visit() -> bool:
	return int(data.get("province", ColonyLedger.NO_ID)) != ColonyLedger.NO_ID


func _build_state(state: VBoxContainer) -> void:
	_reading_column(state, 12, 178)


func _fill() -> void:
	_name.text = String(data.get("name", "A colony"))
	var chip: Dictionary = _chip_reading()
	_chip.text = String(chip["text"])
	_paint_chip(chip["color"])
	var provinces: int = int(data.get("provinces", 0))
	var reading: String = "%d province%s · %s" % [
		provinces, "" if provinces == 1 else "s", String(data.get("terms", ""))
	]
	_place_detail(
		"%s — colony of %s" % [
			String(data.get("place", "No province")), String(data.get("suzerain_name", "—"))
		],
		reading
	)
	_standing.text = String(data.get("standing", ""))
	_reading.text = reading
	if _visit != null:
		_visit.tooltip_text = "Open %s on the map" % String(data.get("place", "the colony"))


## The one word the row carries: the crown's own first, then the bar on its
## trade, then the subsidy it takes — so a crown reads what it can still do
## before what was done to it (REQ-P5-03).
func _chip_reading() -> Dictionary:
	var flags: Array = data.get("flags", [])
	if flags.has(ColonyLedger.FILTER_OURS):
		return {"text": "OURS", "color": Palette.GOLD}
	if flags.has(ColonyLedger.FILTER_SEALED):
		return {"text": "SEALED", "color": Palette.CRIMSON}
	if flags.has(ColonyLedger.FILTER_SUBSIDY):
		return {"text": "PAYS", "color": Palette.SURVEY_BUILDING}
	return {"text": "COLONY", "color": Palette.GOLD_DIM}


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("province", -1)))
