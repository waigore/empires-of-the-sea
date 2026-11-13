class_name MapPlayForceLedger
extends RefCounted
## Jumps from the muster roll to one force: swaps region when needed, selects
## the army or squadron and centres the camera. Presentation only — selection
## flows through the map's own helpers, so dossiers and move overlays keep one
## source (REQ-P1-05, REQ-P3-02).
##
## An embarked army has no marker of its own, so visiting it selects the
## squadron that carries it instead of pointing the camera at an empty sea.

const NO_ID: int = -1


static func focus(play: PlaySession, region: int, kind: String, id: int) -> bool:
	if play == null or play.world == null:
		return false
	var same_region: bool = region == play.region_index
	if not same_region:
		play.switch_region(region)
		MapPlayDiplomacy.sync_first_contact(play)
		MapPlayDiplomacy.refresh(play)
	if kind == ForceLedger.KIND_SQUADRON:
		return _select_fleet(play, id, same_region)
	return _select_army(play, id, same_region)


static func _select_army(play: PlaySession, army_id: int, settled: bool) -> bool:
	var army: ArmyState = _find_army(play, army_id)
	if army == null:
		return false
	# Aboard a squadron: the marker the court can reach is the hulls', not the
	# standard's (wiki: ships-and-naval § Naval transport).
	if army.embarked_fleet != NO_ID:
		return _select_fleet(play, army.embarked_fleet, settled)
	if play.army_layer == null:
		return false
	play.army_layer.select(army)
	var marker: ArmyMarker = play.army_layer.marker_for(army)
	if marker != null and play.camera != null:
		play.camera.focus_on(marker.position, maxf(play.camera.target_zoom, 0.95), not settled)
	MapPlayInput.on_view_changed(play)
	return true


static func _select_fleet(play: PlaySession, fleet_id: int, settled: bool) -> bool:
	if play.ship_layer == null:
		return false
	var marker: Ship = _marker_for(play, fleet_id)
	if marker == null:
		return false
	play.ship_layer.select(marker)
	if play.camera != null:
		play.camera.focus_on(marker.position, maxf(play.camera.target_zoom, 0.95), not settled)
	MapPlayInput.on_view_changed(play)
	return true


static func _find_army(play: PlaySession, army_id: int) -> ArmyState:
	if play.army_layer == null:
		return null
	for army: ArmyState in play.army_layer.armies:
		if army != null and army.id == army_id:
			return army
	return null


static func _marker_for(play: PlaySession, fleet_id: int) -> Ship:
	for marker: Ship in play.ship_layer.ships:
		if marker != null and marker.fleet_id == fleet_id:
			return marker
	return null
