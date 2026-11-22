class_name SpyLedgerRow
extends LedgerRow
## One spy in the crown's intelligence sheet: the province it stands in, the
## duty it holds there in one word, the sentence that duty buys and a Visit
## action that opens the spy's map and dossier (wiki: civilian-units § Spy;
## DR-20261115-10). The Visit seal is a thumb-sized door, so a phone needs no
## hover (REQ-P5-01, REQ-P5-04). The skeleton and the Visit seal come from
## LedgerRow; presentation only, SpyLedger owns every reading.

signal visit_pressed(region: int, unit_id: int)

## The mark the counsel reads by: a spy the court's own espionage pass would walk
## or screen this turn wears it before the one duty word its posting earns
## (DR-20261122-18).
const COURT_MARK: String = "▸"

## Whether the court would give this spy an order this turn; the sheet sets it
## before `setup` from its own reading.
var court: bool = false


## The duty and where it stands are the row's whole reading, so they read one
## step louder than a ledger's place line.
func _detail_pixels() -> int:
	return 12


func _detail_color() -> Color:
	return Palette.TEXT


func _fill() -> void:
	var duty: String = String(data.get("duty", SpyLedger.DUTY_IDLE))
	var place: String = String(data.get("province_name", "Open country"))
	# The counsel's mark leads the name, so a crown finds the spy the court would
	# walk or screen among a busy network (DR-20261122-18).
	_name.text = ("%s Spy — %s" % [COURT_MARK, place]) if court else "Spy — %s" % place
	_chip.text = SpyLedger.duty_word(duty)
	_paint_chip(Palette.GOLD if duty == SpyLedger.DUTY_SHADOW else Palette.GOLD_DIM)
	_detail.text = "%s  ·  %s" % [
		String(data.get("duty_text", "")), String(data.get("region_label", ""))
	]
	_visit.tooltip_text = "Open this spy on the map"


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("unit_id", -1)))
