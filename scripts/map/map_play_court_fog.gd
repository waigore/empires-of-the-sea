class_name MapPlayCourtFog
extends RefCounted
## Rival charts through a turn (wiki: fog-and-exploration; DR-20261110-21).
##
## Builds each court's models, notes every sea zone a rival squadron enters and
## every beach a rival lands on, and runs the end-of-turn decay per court and
## region. The human's own pass stays in MapPlayFogTurn; both read the same
## VisibilityModel, so the AI never plans against a tile it has not charted
## (REQ-P2-03, REQ-P3-03).


## Hands the session its courts' charts. Runs on every region load, but a
## court's grid is only cut the first time a rule reads it (`CourtCharts`), so a
## mounted campaign pays for the fog somebody actually looked at.
static func build(play: PlaySession) -> void:
	if play == null or play.world == null:
		return
	if play.court_charts == null:
		play.court_charts = CourtCharts.new()
	play.court_charts.setup(play.world, play.player_faction, play.visibility_by_region)


## A court's own view of one region, or null before its chart was built.
static func view_for(play: PlaySession, faction: int, region: int) -> VisibilityModel:
	if play == null or play.court_charts == null:
		return null
	return play.court_charts.model_for(faction, region)


## Every court's docket as its own chart reads it: a rival counts the garrisons
## and hulls it has charted, never a crown's whole order of battle (wiki:
## military-armies § Docket; DR-20261112-09). Empty before the charts exist, so
## a session without layers keeps reading the published numbers.
static func oob_readings(play: PlaySession) -> Dictionary:
	if play == null or play.court_charts == null:
		return {}
	if play.army_layer == null or play.ship_layer == null:
		return {}
	var courts: Array[int] = FactionCatalog.great_power_ids()
	return OobReadings.by_court(
		play.court_charts, play.army_layer.regions, play.ship_layer.regions, courts
	)


## Commodities a court has charted (and, for minerals, prospected): the gate on
## its discovery techs, which a rival earns only by exploring (wiki: tech-tree
## § Discovery; DR-20261109-20).
static func research_revealed(play: PlaySession, faction: int) -> Dictionary:
	if play == null or play.court_charts == null or play.civilian_layer == null:
		return {}
	var home: int = FactionCatalog.region_of(faction)
	var works: LandWorks = play.civilian_layer.works_regions.value(home, null)
	return TechDiscovery.revealed(
		play.world, play.court_charts.regions_of(faction), works, faction
	)


## A squadron entering a zone charts its water and the strict coastal ring, for
## its own court only (wiki: ships-and-naval § Ship Reveal Mechanic).
static func note_fleet_entry(
	play: PlaySession, region: int, fleet: FleetState, zone: int
) -> void:
	if play == null or fleet == null or zone < 0:
		return
	if play.court_charts == null:
		return
	var changed: Array = play.court_charts.reveal_sea_zone(fleet.owner, region, zone)
	_sync_owner(play, region, fleet.owner, changed)


## A civilian going ashore charts the landing tile and its orthogonal
## neighbours for its own court (wiki: fog-and-exploration § New World arrival).
static func note_landing(
	play: PlaySession, region: int, owner: int, tile: Vector2i
) -> void:
	if play == null or tile.x < 0:
		return
	if play.court_charts == null:
		return
	var changed: Array = play.court_charts.reveal_landing(owner, region, tile)
	_sync_owner(play, region, owner, changed)


## End-of-turn fog decay for every rival in every region (wiki: fog-and-exploration
## § Fog Decay, § Distant sea zone fog). Own provinces, coastal water, a fleet at
## sea and a crew ashore hold what the court knows, exactly as for the player.
static func resolve(play: PlaySession) -> void:
	if play == null or play.world == null or play.court_charts == null:
		return
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		for index in play.world.region_count():
			var view: VisibilityModel = play.court_charts.model_for(faction, index)
			if view == null:
				continue
			var at_sea: Array = []
			for fleet: FleetState in _fleets(play, index):
				if fleet.owner == faction and fleet.is_at_sea():
					at_sea.append(fleet.sea_zone)
			var held: Array = CivilianMovement.held_provinces(
				play.world.region(index), _civilians(play, index), faction
			)
			view.end_of_turn(at_sea, held)


## The human court's fog is painted by the map own passes; a rival's reveal only
## needs the overlay when the on-screen region happens to belong to the human
## (full-AI observer, where the human slot also runs on the AI planners).
static func _sync_owner(
	play: PlaySession, region: int, owner: int, changed: Array
) -> void:
	if changed.is_empty() or owner != play.player_faction:
		return
	if play.overlay == null or play.model == null or play.model.region_id != region:
		return
	var view: VisibilityModel = play.court_charts.model_for(owner, region)
	if view != null:
		play.overlay.sync_visibility(view, changed)


## Live roster for the shown region; stored table for the others.
static func _fleets(play: PlaySession, region: int) -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	if play.ship_layer == null:
		return fleets
	if play.model != null and play.model.region_id == region:
		return play.ship_layer.fleets
	fleets.assign(play.ship_layer.regions.value(region, []))
	return fleets


static func _civilians(play: PlaySession, region: int) -> Array[CivilianState]:
	var units: Array[CivilianState] = []
	if play.civilian_layer == null:
		return units
	if play.model != null and play.model.region_id == region:
		return play.civilian_layer.units
	units.assign(play.civilian_layer.regions.value(region, []))
	return units
