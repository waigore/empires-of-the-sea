class_name MapPlayFogTurn
extends RefCounted
## End-of-turn fog decay for every region (wiki: fog-and-exploration). Knowledge
## decays off-screen too; only the shown region's fog texture is repainted.


static func resolve(play: PlaySession) -> void:
	if play.visibility_by_region.is_empty():
		return
	for index in play.world.region_count():
		var visibility: VisibilityModel = play.visibility_by_region.get(index, null)
		if visibility == null:
			continue
		var at_sea: Array = []
		for fleet: FleetState in _fleets_of(play, index):
			if fleet.owner == play.player_faction and fleet.is_at_sea():
				at_sea.append(fleet.sea_zone)
		var held: Array = CivilianMovement.held_provinces(
			play.world.region(index), _civilians_of(play, index), play.player_faction
		)
		var changed: Array = visibility.end_of_turn(at_sea, held)
		if index == play.region_index and not changed.is_empty():
			play.overlay.sync_visibility(visibility, changed)


## Live roster for the shown region; stored table for the other.
static func _fleets_of(play: PlaySession, index: int) -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	if play.ship_layer == null:
		return fleets
	if index == play.region_index:
		return play.ship_layer.fleets
	fleets.assign(play.ship_layer.regions.value(index, []))
	return fleets


static func _civilians_of(play: PlaySession, index: int) -> Array[CivilianState]:
	var units: Array[CivilianState] = []
	if play.civilian_layer == null:
		return units
	if index == play.region_index:
		return play.civilian_layer.units
	units.assign(play.civilian_layer.regions.value(index, []))
	return units
