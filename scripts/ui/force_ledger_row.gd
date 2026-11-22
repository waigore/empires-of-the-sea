class_name ForceLedgerRow
extends LedgerRow
## One army or squadron in the muster roll: its medallion, where it stands, what
## it carries and a Visit action that opens its map and dossier. The Visit seal
## is a thumb-sized door, so a phone needs no hover (REQ-P5-01, REQ-P5-04). The
## skeleton and the Visit seal come from LedgerRow; so do the two-line state
## column and the place line every force row wears.

signal visit_pressed(region: int, kind: String, id: int)

## The mark the counsel reads by: a force the court's own staff would send this
## turn wears it before its name (DR-20261122-03).
const COURT_MARK: String = "▸"

## Whether the court would send this force this turn; the roll sets it before
## `setup` from the muster's own reading.
var court: bool = false

var _icon: Icon = null


func _build_icon() -> Control:
	_icon = Icon.new(_icon_kind(), 40.0 if compact else 46.0, Palette.GOLD)
	return _icon


func _build_state(state: VBoxContainer) -> void:
	_reading_column(state, 12, 190)


func _fill() -> void:
	var kind: String = String(data.get("kind", ForceLedger.KIND_ARMY))
	var title: String = String(data.get("title", "Force"))
	# The counsel's mark leads the name, so a crown finds the forces her staff
	# would send among a long muster (DR-20261122-03).
	_name.text = (
		"%s %s" % [COURT_MARK, title] if court else title
	)
	_chip.text = kind.to_upper()
	_paint_chip(Palette.GOLD if kind == ForceLedger.KIND_SQUADRON else Palette.GOLD_DIM)
	var place: String = String(data.get("place", "Open country"))
	_place_detail(place, String(data.get("line", "")))
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
