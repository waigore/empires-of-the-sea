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
		var spies: Array = CivilianMovement.spy_provinces(
			play.world.region(index), _civilians_of(play, index), play.player_faction
		)
		var changed: Array = visibility.end_of_turn(at_sea, held, spies)
		if index == play.region_index and not changed.is_empty():
			play.overlay.sync_visibility(visibility, changed)


## The crown's chart for one region, set up on first use. A rule that charts
## water while the court looks at the other chart (a squadron sorting out of a
## captured port) must not lose the entry because the chart was never opened:
## the model is minted here with the region's own baseline, exactly as the first
## visit would (wiki: fog-and-exploration § Initial Visibility; ships-and-naval
## § Ports that change hands). Null when the region does not exist.
static func chart(play: PlaySession, region: int) -> VisibilityModel:
	if play == null:
		return null
	var stored: VisibilityModel = play.visibility_by_region.get(region, null)
	if stored != null:
		return stored
	if region == play.region_index:
		# The shown region's model is the session's own; it is built by the map
		# setup pass and never minted a second time here.
		if play.visibility != null:
			play.visibility_by_region[region] = play.visibility
		return play.visibility
	if play.world == null:
		return null
	var model: MapModel = play.world.region(region)
	if model == null:
		return null
	var visibility := VisibilityModel.new()
	visibility.setup(model, play.player_faction)
	visibility.apply_initial()
	play.visibility_by_region[region] = visibility
	return visibility


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
