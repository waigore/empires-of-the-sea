class_name MapPlayCivilianRoster
extends RefCounted
## Jumps from the roster to one civilian: swaps region when needed, selects the
## unit and centres the camera. Presentation only — no rules are applied
## (REQ-P3-02).


static func focus(play: PlaySession, region: int, unit_id: int) -> bool:
	if play == null or play.world == null or play.civilian_layer == null:
		return false
	var same_region: bool = region == play.region_index
	if not same_region:
		play.switch_region(region)
		MapPlayDiplomacy.sync_first_contact(play)
		MapPlayDiplomacy.refresh(play)
	var unit: CivilianState = _find(play, unit_id)
	if unit == null:
		return false
	play.civilian_layer.select(unit)
	if play.camera != null:
		var point: Vector2 = MapGeo.tile_center(
			unit.tile.x, unit.tile.y, PlaySession.TILE_SIZE
		)
		play.camera.focus_on(point, maxf(play.camera.target_zoom, 0.95), not same_region)
	MapPlayInput.on_view_changed(play)
	return true


static func _find(play: PlaySession, unit_id: int) -> CivilianState:
	for unit: CivilianState in play.civilian_layer.units:
		if unit != null and unit.id == unit_id:
			return unit
	return null
