class_name NavalLedgerRow
extends LedgerRow
## One hull in the crown's navy: her medallion, the class she is, her own combat
## line, the holds she carries and a Visit action that opens her squadron's map
## and dossier (wiki: ships-and-naval § Ship combat and cargo stats;
## DR-20261115-14). A hull's orders are her squadron's, so the row prints what is
## hers alone and the sheet headings carry the station. The skeleton and the
## Visit seal come from LedgerRow; so do the two-line state column and the place
## line every force row wears.

signal visit_pressed(region: int, fleet_id: int)

var _medallion: TextureRect = null


func _build_icon() -> Control:
	var art: Texture2D = ShipArt.medallion(String(data.get("type", ShipStats.DEFAULT_TYPE)))
	if art == null:
		return Icon.new("anchor", 40.0 if compact else 46.0, Palette.GOLD)
	_medallion = TextureRect.new()
	_medallion.texture = art
	_medallion.custom_minimum_size = Vector2(40, 40) if compact else Vector2(46, 46)
	_medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return _medallion


func _build_state(state: VBoxContainer) -> void:
	_reading_column(state, 11, 196)


func _fill() -> void:
	_name.text = String(data.get("name", "A hull"))
	_chip.text = String(data.get("role_label", "HULL"))
	_paint_chip(
		Palette.GOLD if String(data.get("role", "")) == NavalLedger.READING_WARSHIP
		else Palette.GOLD_DIM
	)
	_place_detail(String(data.get("place", "In port")), String(data.get("class", "")))
	_standing.text = String(data.get("line", ""))
	_reading.text = String(data.get("state", ""))
	_visit.tooltip_text = "Open %s's squadron on the map" % String(data.get("fleet_title", "her"))


func _on_visit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("fleet", -1)))
