class_name ProvinceLedgerRow
extends LedgerRow
## One province in the crown's realm, read the way the sheet's view asks: what
## it yields (economy), how hard it is to hold (defence) or how far it sits from
## the seat (connectivity). The medallion and the Visit seal stay the ledger's
## own, so a phone needs no hover (REQ-P5-01, REQ-P5-04); every figure arrives
## in the row dictionary and this class only names it.

signal visit_pressed(region: int, province_id: int)

## Which of the realm's three readings this row prints; the sheet sets it
## before `setup`.
var view: String = ProvinceLedger.VIEW_ECONOMY

var _icon: Icon = null


func _build_icon() -> Control:
	_icon = Icon.new(_icon_kind(), 40.0 if compact else 46.0, Palette.GOLD)
	return _icon


func _build_state(state: VBoxContainer) -> void:
	_reading_column(state, 12, 200)


func _fill() -> void:
	_name.text = String(data.get("name", "Province"))
	var chip: Dictionary = _chip_reading()
	_chip.text = String(chip["text"])
	_paint_chip(chip["color"])
	_place_detail(String(data.get("place", "Inland")), String(data.get("line", "")))
	_standing.text = _standing_text()
	_reading.text = _reading_text()
	_visit.tooltip_text = "Open %s on the map" % String(data.get("name", "the province"))


func _icon_kind() -> String:
	return "crown" if bool(data.get("capital", false)) else "compass"


# --- the chip ----------------------------------------------------------------


## The one word the row carries, read in the view's own terms: what the estates
## are doing, the band an attack would meet, or where the province stands.
func _chip_reading() -> Dictionary:
	match view:
		ProvinceLedger.VIEW_DEFENCE:
			return _defence_chip()
		ProvinceLedger.VIEW_CONNECTIVITY:
			return _connectivity_chip()
	return _economy_chip()


func _economy_chip() -> Dictionary:
	var economy: Dictionary = data.get("economy", {})
	if bool(economy.get("working", false)):
		return {"text": "WORKS", "color": Palette.GOLD_DIM}
	if int(economy.get("estates", 0)) == 0:
		return {"text": "NO ESTATES", "color": Palette.TEXT_DIM}
	if int(economy.get("developed", 0)) == 0:
		return {"text": "VACANT", "color": Palette.SURVEY_BUILDING}
	if int(economy.get("headroom", 0)) == 0:
		return {"text": "MAXED", "color": Palette.GOLD}
	return {"text": "GROWING", "color": Palette.GOLD_DIM}


## The band the defence lens paints, so the realm and the map agree about what
## would meet an attack.
func _defence_chip() -> Dictionary:
	var band: String = String((data.get("defence", {}) as Dictionary).get("band", ""))
	match band:
		DefenceSurvey.BAND_CITADEL:
			return {"text": "CITADEL", "color": Palette.GOLD}
		DefenceSurvey.BAND_WALLED:
			return {"text": "WALLED", "color": Palette.GOLD_DIM}
		DefenceSurvey.BAND_HELD:
			return {"text": "HELD", "color": Palette.SURVEY_BUILDING}
	return {"text": "OPEN", "color": Palette.CRIMSON}


func _connectivity_chip() -> Dictionary:
	var link: Dictionary = data.get("connectivity", {})
	if bool(link.get("seat", false)):
		return {"text": "SEAT", "color": Palette.GOLD}
	if not bool(link.get("linked", false)):
		return {"text": "CUT OFF", "color": Palette.CRIMSON}
	if not bool(link.get("same_chart", true)):
		return {"text": "OVERSEAS", "color": Palette.SURVEY_BUILDING}
	return {"text": "HELD", "color": Palette.GOLD_DIM}


# --- the two reading lines ---------------------------------------------------


func _standing_text() -> String:
	match view:
		ProvinceLedger.VIEW_DEFENCE:
			return "Defence %d" % int((data.get("defence", {}) as Dictionary).get("figure", 0))
		ProvinceLedger.VIEW_CONNECTIVITY:
			return _hops_text()
	var economy: Dictionary = data.get("economy", {})
	var estates: int = int(economy.get("estates", 0))
	return "%d estate%s · %d developed · %d to raise" % [
		estates,
		"" if estates == 1 else "s",
		int(economy.get("developed", 0)),
		int(economy.get("headroom", 0)),
	]


func _reading_text() -> String:
	match view:
		ProvinceLedger.VIEW_DEFENCE:
			return _defence_text()
		ProvinceLedger.VIEW_CONNECTIVITY:
			return _connectivity_text()
	return _economy_text()


## The economy's second line: the harvest and what it is worth at today's sell,
## then the kinds it gathers, so a crown reads its richest province first.
func _economy_text() -> String:
	var economy: Dictionary = data.get("economy", {})
	var parts: PackedStringArray = [
		"%d units gathered" % int(economy.get("output", 0)),
		"%s at today's sell" % MoneyText.ducats(int(economy.get("value", 0))),
	]
	var kinds: String = _kinds_text(economy.get("by_kind", {}) as Dictionary)
	if not kinds.is_empty():
		parts.append(kinds)
	return " · ".join(parts)


## The defence's second line: the same terms the figure was built from, so the
## one number is never a black box (REQ-P2-03).
func _defence_text() -> String:
	var defence: Dictionary = data.get("defence", {})
	var town: int = int(data.get("town", 0))
	var parts: PackedStringArray = [
		("Town %d" % town) if town > 0 else "No town",
		"%d strength ×%.2f %s" % [
			roundi(float(defence.get("strength", 0.0))),
			float(defence.get("multiplier", 1.0)),
			String(defence.get("terrain_name", "ground")).to_lower(),
		]
	]
	var fort: int = int(defence.get("fort", 0))
	if fort > 0:
		parts.append("Fort %d %s" % [fort, String(defence.get("fort_name", ""))])
	if float(defence.get("emplaced", 0.0)) > 0.0:
		parts.append("%d guns emplaced" % int(defence.get("guns", 0)))
	var hospital: int = int(defence.get("hospital", 0))
	if hospital > 0:
		parts.append("Hospital %d" % hospital)
	return " · ".join(parts)


## The connectivity's second line: the road to the seat, then the chart it sits
## on, so a cut-off or overseas holding never hides behind its hop count.
func _connectivity_text() -> String:
	var link: Dictionary = data.get("connectivity", {})
	var parts: PackedStringArray = [String(data.get("state", ""))]
	if not bool(link.get("same_chart", true)):
		parts.append("Across the sea from the seat")
	return " · ".join(parts)


func _hops_text() -> String:
	var link: Dictionary = data.get("connectivity", {})
	if bool(link.get("seat", false)):
		return "The seat — 0 hops"
	var hops: int = int(link.get("hops", -1))
	if hops < 0:
		return "No land road to the seat"
	return "%d hop%s from the seat" % [hops, "" if hops == 1 else "s"]


## "12 timber · 4 ore": the kinds a province gathers, in the published order.
func _kinds_text(by_kind: Dictionary) -> String:
	var parts: PackedStringArray = []
	for kind: String in ResourceTypes.ORDER:
		var units: int = int(by_kind.get(kind, 0))
		if units > 0:
			parts.append("%d %s" % [units, String(ResourceTypes.NAMES.get(kind, kind))])
	return " · ".join(parts)


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("id", -1)))
