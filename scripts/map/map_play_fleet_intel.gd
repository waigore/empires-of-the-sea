class_name MapPlayFleetIntel
extends RefCounted
## The crown's watch over rival squadrons: whether the chart draws a fleet at
## all, whether her weight is read, and the news a closing watch earns (wiki:
## ships-and-naval § Sighted strength; fog-and-exploration § Visibility Levels).
## MapPlayFleets keeps selection, sail and dock orders; this module is the one
## reading of fog, intel and charted coast, so a marker minted by a merge, a
## passage or a captured port asks the same question the dossier does
## (REQ-P3-01, REQ-P3-02).


## Whether the crown may read a squadron's fighting weight: its own squadrons
## always, a rival's only once the watch has spanned a turn on this chart
## (wiki: ships-and-naval § Sighted strength).
static func strength_read(play: PlaySession, fleet: FleetState) -> bool:
	if fleet == null or fleet.owner == play.player_faction:
		return true
	return play.naval_intel.is_revealed(fleet.id, play.region_index)


## Which squadrons in a zone the crown can weigh; an unread rival contributes
## no figure to the odds (wiki: ships-and-naval § Sighted strength).
static func intel_filter(play: PlaySession) -> Callable:
	return func(other: FleetState) -> bool:
		return strength_read(play, other)


## What the crown's chart says of one squadron: whether she is drawn at all and,
## for a rival, whether her weight is read. Installed on the layer so a marker
## minted by a merge, a passage or a captured port starts where the chart stands
## instead of handing back intel the fog withholds (wiki: ships-and-naval
## § Sighted strength; fog-and-exploration § Visibility Levels).
static func view_filter(play: PlaySession) -> Callable:
	return func(fleet: FleetState) -> Dictionary:
		return {"drawn": _known(play, fleet), "read": strength_read(play, fleet)}


## A sail into a zone charts what it can see: the fog opens a ring around the
## marker and a first sighting of the coast earns a despatch.
static func on_zone_entered(play: PlaySession, zone_id: int, ship: Ship) -> void:
	if ship == null or ship.faction != play.player_faction or play.visibility == null:
		return
	## A court whose leader publishes the charting lean charts one further land
	## ring on the coast (wiki: leader-bonuses § Bonus Table — Henry).
	var rings: int = LeaderCatalog.coastal_rings(
		String(play.leaders.get(play.player_faction, ""))
	)
	var changed: Array = play.visibility.reveal_sea_zone(zone_id, rings)
	if not changed.is_empty():
		play.overlay.sync_visibility(play.visibility, changed)
	_announce_charted_coast(play, changed)
	refresh_visibility(play)


## Re-reads the chart's watch on every marker: fog hides or draws each squadron
## and a rival under the eye for a full turn is read, while one that slipped
## away is unread again (wiki: ships-and-naval § Sighted strength).
static func refresh_visibility(play: PlaySession) -> void:
	if play == null or play.ship_layer == null:
		return
	# A marker minted later (a merge, a passage, a captured port) asks the same
	# chart this refresh just read, so a rebuild cannot hand back what the fog
	# withholds (wiki: ships-and-naval § Sighted strength).
	play.ship_layer.crown_view = view_filter(play)
	var in_view: Array[int] = []
	for ship: Ship in play.ship_layer.ships:
		var fleet: FleetState = play.ship_layer.fleet_of(ship)
		if fleet == null:
			continue
		var known: bool = _known(play, fleet)
		ship.visible = known
		if known and fleet.owner != play.player_faction:
			in_view.append(fleet.id)
	# One refresh of the crown's watch on this chart: a rival seen at the last
	# close and still under the same eye is read now, and one that slipped away
	# is unread again. The other chart's watch is untouched — a rival there never
	# left the crown's water (wiki: ships-and-naval § Sighted strength).
	var revealed: Array[int] = play.naval_intel.observe(in_view, play.turn, play.region_index)
	for ship: Ship in play.ship_layer.ships:
		var fleet: FleetState = play.ship_layer.fleet_of(ship)
		if fleet != null:
			ship.set_intel(strength_read(play, fleet))
	# The rows are laid after the fog's answer: a stack whose head the chart no
	# longer draws hands the hull to the next squadron it can see
	# (wiki: ships-and-naval § Fleets in one station).
	play.ship_layer.relayout()
	# The watch closing is a beat the court should hear: her weight appears on the
	# plate, and a player who never saw the rule would otherwise watch a number
	# arrive from nowhere.
	for fleet_id: int in revealed:
		var fleet: FleetState = FleetRosters.find(play.ship_layer.fleets, fleet_id)
		if fleet != null and play.hud != null:
			play.hud.toast(read_line(play, fleet))


## "Portugal's squadron in the Mar Egeo is read — 5.5 strength.": the news the
## closing watch earns (wiki: ships-and-naval § Sighted strength).
static func read_line(play: PlaySession, fleet: FleetState) -> String:
	var where: String = "at %s" % play.model.province_name(fleet.province)
	if fleet.is_at_sea():
		where = "in the %s" % play.model.sea_zone_name(fleet.sea_zone)
	return "%s's squadron %s is read — %.1f strength." % [
		FactionCatalog.name_of(fleet.owner), where, NavalStrength.strength(fleet),
	]


## First sighting of a province's coast earns a quiet note, once per province.
static func _announce_charted_coast(play: PlaySession, changed: Array) -> void:
	for raw: Variant in changed:
		var index: int = int(raw)
		var y: int = int(floor(float(index) / float(play.model.width)))
		var x: int = index - y * play.model.width
		if not play.model.is_land(x, y):
			continue
		var province_id: int = play.model.province_at(x, y)
		if province_id == MapModel.NO_ID or play.charted_provinces.has(province_id):
			continue
		play.charted_provinces[province_id] = true
		play.hud.toast("The coast of %s is charted" % play.model.province_name(province_id))
		play.screen.emit_coast_charted(province_id)
		return


static func _known(play: PlaySession, fleet: FleetState) -> bool:
	if fleet.owner == play.player_faction or play.visibility == null:
		return true
	var tile: Vector2i = _tile(play, fleet)
	if tile.x < 0:
		return true
	return play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE


## The tile a squadron is drawn on: the first tile of its sea zone, or its
## port's berth.
static func _tile(play: PlaySession, fleet: FleetState) -> Vector2i:
	if fleet.is_at_sea():
		var zone: SeaZoneState = play.model.sea_zone_data(fleet.sea_zone)
		var tiles: Array = zone.tiles if zone != null else []
		if tiles.is_empty():
			return Vector2i(-1, -1)
		return tiles[0]
	var data: ProvinceState = play.model.province_data(fleet.province)
	return data.port_tile if data != null else Vector2i(-1, -1)
