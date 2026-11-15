class_name MapPlayFocus
extends RefCounted
## Top-bar force plaques double as a "where are my pieces?" control: each press
## selects the next own squadron or army across every region, swapping the chart
## when the next piece lies elsewhere, and brings it under the camera — the same
## reach the muster roll's Visit has (docs/hud-top-bar.md). Presentation only:
## the jump runs through MapPlayForceLedger and selection through the map's own
## helpers, so dossiers and move overlays stay in one place (REQ-P1-05).

const KIND_FLEET := "fleet"
const KIND_ARMY := "army"
const NO_ID: int = -1


static func bind(play: PlaySession) -> void:
	if play == null or play.hud == null:
		return
	play.hud.fleet_status_pressed.connect(func() -> void: focus_next(play, KIND_FLEET))
	play.hud.army_status_pressed.connect(func() -> void: focus_next(play, KIND_ARMY))


static func focus_next(play: PlaySession, kind: String) -> void:
	if play == null or play.hud == null:
		return
	var pieces: Array[Dictionary] = _pieces(play, kind)
	if pieces.is_empty():
		play.hud.toast(_empty_toast(kind))
		return
	# A piece the chart cannot reach (its marker is gone) must not stall the
	# cycle, so the press walks on to the next one before it gives up.
	var start: int = _index_after(pieces, play.region_index, _current_id(play, kind))
	for step: int in pieces.size():
		var piece: Dictionary = pieces[(start + step) % pieces.size()]
		if MapPlayForceLedger.focus(
			play, int(piece["region"]), _ledger_kind(kind), int(piece["id"])
		):
			return
	play.hud.toast(_empty_toast(kind))


# --- the cycle ---------------------------------------------------------------


## Every own piece of one kind, region by region and id by id, so the cycle
## walks the whole empire and wraps back onto the chart it started from.
static func _pieces(play: PlaySession, kind: String) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	if kind == KIND_FLEET:
		var fleets: MapRegionTable = play.ship_layer.regions if play.ship_layer != null else null
		_collect(fleets, play.player_faction, KIND_FLEET, pieces)
	else:
		var armies: MapRegionTable = play.army_layer.regions if play.army_layer != null else null
		_collect(armies, play.player_faction, KIND_ARMY, pieces)
	return pieces


static func _collect(
	table: MapRegionTable, faction: int, kind: String, pieces: Array[Dictionary]
) -> void:
	if table == null:
		return
	for region: int in table.region_ids():
		var ids: Array[int] = []
		for raw: Variant in _stored(table, region):
			var id: int = _own_id(raw, faction, kind)
			if id != NO_ID:
				ids.append(id)
		ids.sort()
		for id: int in ids:
			pieces.append({"region": region, "id": id})


## The roster id of one stored piece when the crown owns it and the plaque cycle
## should reach it; `NO_ID` otherwise. An embarked army is left out — its hulls
## answer for it in the squadron cycle (wiki: ships-and-naval § Naval transport).
static func _own_id(raw: Variant, faction: int, kind: String) -> int:
	if kind == KIND_FLEET:
		var fleet := raw as FleetState
		if fleet == null or fleet.owner != faction:
			return NO_ID
		return fleet.id
	var army := raw as ArmyState
	if army == null or army.owner != faction or army.is_embarked():
		return NO_ID
	return army.id


static func _stored(table: MapRegionTable, region: int) -> Array:
	var stored: Variant = table.value(region, [])
	return stored if stored is Array else []


## The slot after the current selection, wrapping; an unknown or off-chart
## selection starts the cycle at the first piece.
static func _index_after(pieces: Array[Dictionary], region: int, current: int) -> int:
	for index: int in pieces.size():
		var piece: Dictionary = pieces[index]
		if int(piece["id"]) == current and int(piece["region"]) == region:
			return (index + 1) % pieces.size()
	return 0


static func _current_id(play: PlaySession, kind: String) -> int:
	if kind == KIND_FLEET:
		var ship: Ship = play.ship_layer.selected() if play.ship_layer != null else null
		return ship.fleet_id if ship != null else NO_ID
	var army: ArmyState = play.army_layer.selected_army if play.army_layer != null else null
	return army.id if army != null else NO_ID


static func _ledger_kind(kind: String) -> String:
	return ForceLedger.KIND_SQUADRON if kind == KIND_FLEET else ForceLedger.KIND_ARMY


## The plaque reads "Where are my pieces?" with no region qualifier, so an empty
## press means the crown holds none anywhere — not merely on the shown chart.
static func _empty_toast(kind: String) -> String:
	if kind == KIND_FLEET:
		return "No squadron in the crown's service"
	return "No army in the crown's service"
