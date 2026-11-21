class_name SpyLedgerRow
extends LedgerRow
## One spy in the crown's intelligence sheet: the province it stands in, the
## duty it holds there in one word, the sentence that duty buys and a Visit
## action that opens the spy's map and dossier (wiki: civilian-units § Spy;
## DR-20261115-10). The Visit seal is a thumb-sized door, so a phone needs no
## hover (REQ-P5-01, REQ-P5-04). The skeleton and the Visit seal come from
## LedgerRow; presentation only, SpyLedger owns every reading.

signal visit_pressed(region: int, unit_id: int)


## The duty and where it stands are the row's whole reading, so they read one
## step louder than a ledger's place line.
func _detail_pixels() -> int:
	return 12


func _detail_color() -> Color:
	return Palette.TEXT


func _fill() -> void:
	var duty: String = String(data.get("duty", SpyLedger.DUTY_IDLE))
	_name.text = "Spy — %s" % String(data.get("province_name", "Open country"))
	_chip.text = SpyLedger.duty_word(duty)
	_paint_chip(Palette.GOLD if duty == SpyLedger.DUTY_SHADOW else Palette.GOLD_DIM)
	_detail.text = "%s  ·  %s" % [
		String(data.get("duty_text", "")), String(data.get("region_label", ""))
	]
	_visit.tooltip_text = "Open this spy on the map"


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("unit_id", -1)))
