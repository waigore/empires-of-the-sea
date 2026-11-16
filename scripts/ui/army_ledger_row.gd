class_name ArmyLedgerRow
extends LedgerRow
## One regiment in the crown's army: its medallion, the class it is, its own
## stat line, the condition it holds and a Visit action that opens its standard's
## map and dossier (wiki: military-armies § The regiments behind an army;
## DR-20261116-16). A regiment's orders are its standard's, so the row prints
## what is the regiment's own and the sheet headings carry the standing. The
## skeleton, the tap and the Visit door come from LedgerRow.

signal visit_pressed(region: int, army_id: int)

var _medallion: UnitMedallion = null
var _standing: Label = null
var _reading: Label = null


func _build_icon() -> Control:
	_medallion = UnitMedallion.of_regiment(
		String(data.get("type", RegimentCatalog.DEFAULT_TYPE)), 40.0 if compact else 46.0
	)
	return _medallion


func _build_state(state: VBoxContainer) -> void:
	state.add_theme_constant_override("separation", 3)
	state.custom_minimum_size = Vector2(196, 0)
	state.visible = not compact
	_standing = UiRowBuilder.wrapped_line("", 11, Palette.TEXT)
	state.add_child(_standing)
	_reading = UiRowBuilder.wrapped_line("", 11, Palette.TEXT_DIM)
	state.add_child(_reading)


func _fill() -> void:
	_name.text = String(data.get("name", "A regiment"))
	_chip.text = String(data.get("role_label", "FOOT"))
	_paint_chip(
		Palette.GOLD if String(data.get("reading", "")) == ArmyLedger.READING_FOOT
		else Palette.GOLD_DIM
	)
	var place: String = String(data.get("place", "In the field"))
	var reading: String = String(data.get("state", ""))
	_detail.text = "%s  ·  %s" % [place, String(data.get("region_label", "Uncharted"))]
	if compact:
		_detail.text = "%s  ·  %s  ·  %s" % [
			place, String(data.get("class", "")), String(data.get("region_label", "Uncharted"))
		]
	_standing.text = String(data.get("line", ""))
	_reading.text = reading
	_visit.tooltip_text = "Open the %s on the map" % String(data.get("army_title", "standard"))


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("army", -1)))
