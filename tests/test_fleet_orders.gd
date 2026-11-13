extends GdToolsTest
## Fleet orders end-to-end through the real map screen (wiki: ships-and-naval).
## Kept separate from test_map_screen so each native suite stays inside the
## coverage runner's per-suite timeout.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_selecting_a_player_fleet_opens_orders() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	assert_true(_screen.hud.panels.is_fleet_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())
	assert_eq(_screen.overlay.move_zones, NavalMovement.destination_zones(_screen.model, fleet))


func test_fleet_dossier_can_dock_left_or_right() -> void:
	var ship: Ship = _player_ship_at_sea()
	_screen.ship_layer.select(ship)
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.LEFT)
	assert_eq(_screen.hud._fleet_wrap.anchor_left, 0.0)
	assert_true(_screen.hud.panels.is_fleet_panel_open())
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)
	assert_eq(_screen.hud._fleet_wrap.anchor_left, 1.0)


func test_transfer_owner_reassigns_a_squadron_and_its_marker() -> void:
	var fleet: FleetState = _screen.ship_layer.fleets[0]
	var from_id: int = fleet.owner
	var to_id: int = 1 if from_id != 1 else 2
	_screen.ship_layer.transfer_owner(from_id, to_id)
	assert_eq(fleet.owner, to_id)
	var marker: Ship = _screen.ship_layer.ship_for(fleet)
	assert_not_null(marker)
	assert_eq(marker.faction, to_id)


func test_ordering_a_move_spends_the_turn_and_reveals_the_zone() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var tile: Vector2i = _screen.model.sea_zones[zone].tiles[0]

	assert_true(MapPlayFleets.try_order(_screen.play, tile))

	assert_eq(fleet.sea_zone, zone)
	assert_true(fleet.moved)
	assert_eq(_screen.overlay.move_zones.size(), 0)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_VISIBLE)
	assert_eq(
		_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)


func test_a_fleet_cannot_move_twice_in_one_turn() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone].tiles[0])
	var zone_after_move: int = fleet.sea_zone
	var next_zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[next_zone].tiles[0]))

	assert_eq(fleet.sea_zone, zone_after_move)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)


func test_docking_puts_the_fleet_in_port() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var ports: Array[int] = NavalMovement.dockable_provinces(_screen.model, fleet)
	assert_gt(ports.size(), 0)
	var province_id: int = ports[0]
	var port: Vector2i = _screen.model.provinces[province_id].port_tile

	assert_true(MapPlayFleets.try_order(_screen.play, port))

	assert_eq(fleet.location, FleetState.Location.IN_PORT)
	assert_eq(fleet.province, province_id)
	if _screen.ship_layer.ships.has(ship):
		assert_true(ship.docked, "the hull sits in port")
	else:
		assert_true(fleet.moved, "the merged squadron is in port")
	assert_eq(_screen.overlay.move_provinces.size(), 0)


func test_the_home_fleet_cannot_be_ordered_to_sail() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))
	assert_eq(_screen.overlay.move_zones.size(), 0, "the home fleet shows no sea orders")
	var zone: int = NavalMovement.province_sea_zones(_screen.model, capital)[0]
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zone_data(zone).tiles[0]))

	assert_eq(home.location, FleetState.Location.IN_PORT)
	assert_eq(home.province, capital)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)


func test_docking_at_the_capital_joins_the_home_fleet() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var sea: FleetState = null
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			sea = fleet
			break
	assert_not_null(sea, "a player squadron is at sea")
	var sea_hulls: Array[String] = sea.hulls.duplicate()
	var home_before: int = home.ship_count()
	sea.sea_zone = NavalMovement.province_sea_zones(_screen.model, capital)[0]
	sea.province = MapModel.NO_ID
	sea.location = FleetState.Location.AT_SEA
	_screen.ship_layer.select(_screen.ship_layer.ship_for(sea))
	var port: Vector2i = _screen.model.province_data(capital).port_tile

	assert_true(MapPlayFleets.try_order(_screen.play, port))

	assert_false(_screen.ship_layer.fleets.has(sea), "the sea-going squadron is gone")
	assert_null(_screen.ship_layer.ship_for(sea), "its marker leaves the map")
	assert_eq(home.ship_count(), home_before + sea_hulls.size())
	for hull_id: String in sea_hulls:
		assert_true(home.hulls.has(hull_id), "instance ids survive the merge")
	var at_capital: int = 0
	for fleet: FleetState in _screen.ship_layer.fleets:
		if (
			fleet.owner == MapScreen.PLAYER_FACTION
			and fleet.is_in_port()
			and fleet.province == capital
		):
			at_capital += 1
	assert_eq(at_capital, 1, "only the home fleet holds the capital port")


func test_enemy_fleets_reject_player_orders() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	_screen.ship_layer.select(enemy)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var zone_before: int = fleet.sea_zone

	assert_false(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone].tiles[0]))

	assert_eq(fleet.sea_zone, zone_before)
	assert_false(fleet.moved)


func test_end_turn_restores_fleet_moves() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone].tiles[0])
	assert_true(fleet.moved)

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_false(fleet.moved)
	assert_gt(_screen.overlay.move_zones.size(), 0)


func test_end_turn_leaves_unknown_tiles_unknown() -> void:
	var zone_id: int = _remote_zone()
	assert_gt(zone_id, -1)
	var tile: Vector2i = _screen.model.sea_zones[zone_id].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_UNKNOWN)


func test_end_turn_refogs_distant_known_waters() -> void:
	var zone_id: int = _remote_zone()
	assert_gt(zone_id, -1)
	var tile: Vector2i = _screen.model.sea_zones[zone_id].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FOGGED)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)


func test_end_turn_reveals_owned_coastal_waters() -> void:
	var zones: Array[int] = []
	for zone: SeaZoneState in _screen.model.sea_zones:
		var zone_id: int = int(zone.id)
		if _screen.visibility.owns_coast(zone_id):
			zones.append(zone_id)
	assert_gt(zones.size(), 0)
	var tile: Vector2i = _screen.model.sea_zones[zones[0]].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(
		_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_VISIBLE)


func test_enemy_markers_follow_fog_intel() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)

	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_false(enemy.visible)

	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_true(enemy.visible)


## A sighted rival flies `*` until the watch spans a turn, and loses the read
## when she slips out of the crown's chart (wiki: ships-and-naval
## § Sighted strength).
func test_a_rivals_strength_waits_for_the_watch_to_close() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	MapPlayFleets.refresh_visibility(_screen.play)

	assert_true(enemy.visible, "she is under the crown's eye")
	assert_false(enemy.strength_known, "a first sighting gives up no weight")
	assert_false(_screen.play.naval_intel.is_revealed(fleet.id, _screen.play.region_index))

	_screen.play.turn += 1
	MapPlayFleets.refresh_visibility(_screen.play)

	assert_true(enemy.strength_known, "still in view next turn, her weight is read")
	assert_true(_screen.play.naval_intel.is_revealed(fleet.id, _screen.play.region_index))

	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	MapPlayFleets.refresh_visibility(_screen.play)

	assert_false(enemy.strength_known, "out of sight is out of knowledge")
	assert_false(_screen.play.naval_intel.is_revealed(fleet.id, _screen.play.region_index),
		"a rival who returns must be watched afresh")


## The dossier prints ??? for a rival the crown has sighted but not read, and
## names the watch that would earn her weight.
func test_a_sighted_rivals_dossier_withholds_her_maths() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	MapPlayFleets.refresh_visibility(_screen.play)
	_screen.ship_layer.select(enemy)
	var block: FleetStrengthSection = _screen.hud._fleet_panel._strength

	assert_true(block.visible, "the block names the squadron")
	assert_true(block._strength.text.contains("???"), block._strength.text)
	assert_false(block._pool.text.contains("Hull pool"),
		"the hull pool is not the crown's to know")
	assert_true(block._pool.visible, "the block still says how the weight is earned")
	assert_true(block._pool.text.contains("watch"), block._pool.text)
	assert_true(block._strength.text.contains("strength"), block._strength.text)

	_screen.play.turn += 1
	MapPlayFleets.refresh_visibility(_screen.play)
	MapPlayFleets.show_dossier(_screen.play, fleet)

	assert_true(block._strength.text.contains("strength ="), block._strength.text)
	assert_false(block._strength.text.contains("???"), block._strength.text)
	assert_true(block._pool.visible, "a read squadron shows her full maths")
	assert_true(block._pool.text.contains("Hull pool"), block._pool.text)


## The seal's chart switch hides a region's squadrons from the view, not from
## the crown's water: a read rival keeps her weight when the crown looks at the
## other hemisphere (wiki: ships-and-naval § Sighted strength).
func test_a_read_rival_keeps_her_weight_across_the_chart_switch() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	MapPlayFleets.refresh_visibility(_screen.play)
	_screen.play.turn += 1
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_true(_screen.play.naval_intel.is_revealed(fleet.id, FactionCatalog.OLD_WORLD))

	_screen.load_region(FactionCatalog.NEW_WORLD)

	assert_true(_screen.play.naval_intel.is_revealed(fleet.id, FactionCatalog.OLD_WORLD),
		"another chart is not another water")

	_screen.load_region(FactionCatalog.OLD_WORLD)
	var marker: Ship = _screen.ship_layer.ship_for(fleet)

	assert_true(_screen.play.naval_intel.is_revealed(fleet.id, FactionCatalog.OLD_WORLD))
	assert_not_null(marker)
	assert_true(marker.strength_known, "her plate still prints the weight she gave")


## The watch closing is a beat: her weight appears on the plate, so the court is
## told that it was read (wiki: ships-and-naval § Sighted strength).
func test_the_watch_closing_names_the_read() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	MapPlayFleets.refresh_visibility(_screen.play)
	var before: Array[String] = _toast_texts()

	_screen.play.turn += 1
	MapPlayFleets.refresh_visibility(_screen.play)

	var named: String = ""
	for text: String in _toast_texts():
		if before.has(text) or not text.contains("is read"):
			continue
		if text.contains(FactionCatalog.name_of(fleet.owner)):
			named = text
	assert_false(named.is_empty(), "the closing watch speaks and names her court")
	assert_true(named.contains("strength"), named)


func test_a_fleet_crosses_the_passage_into_the_new_world() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	var zone: int = _old_world_passage()
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = zone
	fleet.province = MapModel.NO_ID
	_screen.ship_layer.select(ship)
	var link: Dictionary = _screen.world.warp_partner(FactionCatalog.OLD_WORLD, zone)

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zone_data(zone).tiles[0]))

	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD, "the view follows the fleet")
	assert_eq(_screen.model.region_id, FactionCatalog.NEW_WORLD)
	assert_eq(fleet.sea_zone, int(link["to_zone"]))
	assert_true(fleet.moved)
	assert_true(_screen.ship_layer.fleets.has(fleet), "it sails the New World now")
	assert_false(_roster(FactionCatalog.OLD_WORLD).has(fleet), "it left the Old World roster")
	assert_eq(_screen.ship_layer.selected(), _screen.ship_layer.ship_for(fleet))
	assert_eq(_zone_fog(fleet.sea_zone), MapOverlay.FOG_VISIBLE, "arrival waters reveal")
	assert_true(_unique_fleet_ids(), "both rosters keep distinct fleet ids")


func test_a_crossed_fleet_cannot_cross_again_this_turn() -> void:
	var fleet: FleetState = _cross_to_new_world()
	var zone_after: int = fleet.sea_zone
	var region_after: int = _screen.region_index
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _passage_tile(zone_after)))

	assert_eq(fleet.sea_zone, zone_after)
	assert_eq(_screen.region_index, region_after)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)


func test_a_crossed_fleet_sails_back_on_a_later_turn() -> void:
	var fleet: FleetState = _cross_to_new_world()

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_false(fleet.moved, "the passage crossing spent only that turn's move")
	var zone: int = fleet.sea_zone

	assert_true(MapPlayFleets.try_order(_screen.play, _passage_tile(zone)))

	assert_eq(_screen.region_index, FactionCatalog.OLD_WORLD)
	assert_true(_roster(FactionCatalog.OLD_WORLD).has(fleet))
	assert_true(_screen.world.is_warp_zone(FactionCatalog.OLD_WORLD, fleet.sea_zone))


func test_the_fleet_dossier_names_the_passage() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = _old_world_passage()

	_screen.ship_layer.select(ship)

	assert_true(_screen.hud._fleet_panel._hint.text.contains("Passage"))
	assert_true(_screen.hud._fleet_panel._hint.text.contains("New World"))


## A colonist aboard a squadron that crosses the Passage keeps its seat: the
## entry follows into the New World roster and the end-of-turn loss pass must
## not drown it (wiki: civilian-units § Overseas deployment; DR-20261109-17).
func test_a_colonist_crosses_the_passage_and_survives_the_loss_pass() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	var zone: int = _old_world_passage()
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = zone
	fleet.province = MapModel.NO_ID
	var colonist: CivilianState = _passenger(fleet)
	_screen.ship_layer.select(ship)

	assert_true(MapPlayFleets.try_order(_screen.play, _passage_tile(zone)))
	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_true(colonist.is_embarked(), "the colonist is still aboard after the crossing")
	assert_eq(colonist.embarked_fleet, fleet.id, "its seat is the renumbered squadron")
	assert_true(
		CivilianVoyageMap.by_id(_screen.civilian_layer, colonist.id) == colonist,
		"the colonist stays on the roster"
	)


## Docking at the seat folds the squadron into the home fleet; its passengers
## move with the hulls and stay in the dossier (wiki: ships-and-naval § Home
## Fleet; DR-20261109-17).
func test_a_colonist_reaches_the_home_fleet_when_the_squadron_moors() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the opening muster moors a home squadron")
	var zones: Array[int] = NavalMovement.province_sea_zones(_screen.model, capital)
	assert_gt(zones.size(), 0, "the seat has a sea zone")
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	if fleet == home:
		return
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = zones[0]
	fleet.province = MapModel.NO_ID
	fleet.moved = false
	var colonist: CivilianState = _passenger(fleet)
	_screen.ship_layer.select(ship)

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.province_tiles(capital)[0]))
	assert_true(home.has_civilian(colonist.id), "the home fleet takes the passenger")
	assert_false(_screen.ship_layer.fleets.has(fleet), "the sea-going squadron merges away")
	assert_eq(int(MapPlayCivilianVoyage.crew(_screen.play, home)["count"]), 1)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(colonist.embarked_fleet, home.id, "the passenger rides the home fleet")
	assert_true(
		CivilianVoyageMap.by_id(_screen.civilian_layer, colonist.id) == colonist,
		"the colonist stays on the roster"
	)


## The crossing is the squadron's sail: the dossier lets go of the station and
## the landing site rather than naming a coast on the other map (wiki:
## ships-and-naval § Missions and Movement; § Naval transport).
func test_a_crossing_drops_the_dossier_station_and_the_landing_site() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	var zone: int = _old_world_passage()
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = zone
	fleet.province = MapModel.NO_ID
	fleet.moved = false
	fleet.mission = FleetState.Mission.PATROL
	fleet.blockade_province = MapModel.NO_ID
	var choice: Array = _hostile_coast(zone)
	assert_false(choice.is_empty(), "the passage borders a foreign coast")
	var coast: int = int(choice[0])
	_declare_war(_screen.model.province_owner(coast))
	fleet.beachhead_province = coast
	fleet.beachhead_turn = _screen.play.turn
	_screen.ship_layer.select(ship)
	assert_true(
		MapPlayFleetMissions.note(_screen.play, fleet).contains("Beachhead"),
		"the dossier shows the landing site before the crossing"
	)

	assert_true(MapPlayFleets.try_order(_screen.play, _passage_tile(zone)))

	assert_eq(fleet.mission, FleetState.Mission.NONE, "the station stays behind")
	assert_false(fleet.has_beachhead(), "the landing site stays behind")
	assert_eq(MapPlayFleetMissions.note(_screen.play, fleet), "")


## Two armies cannot share one squadron: docking at the seat keeps the home
## army aboard and lands the arriving one at the port rather than drowning it
## (wiki: ships-and-naval § Naval transport — landing at the port province).
func test_a_docking_merge_lands_the_surplus_army() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the opening muster moors a home squadron")
	var zones: Array[int] = NavalMovement.province_sea_zones(_screen.model, capital)
	assert_gt(zones.size(), 0, "the seat has a sea zone")
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	if fleet == home:
		return
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = zones[0]
	fleet.province = MapModel.NO_ID
	fleet.moved = false
	var kept := ArmyState.muster(90, _screen.play.player_faction, capital, false, ["pikemen"], 900)
	var arriving := ArmyState.muster(
		91, _screen.play.player_faction, capital, false, ["pikemen"], 910
	)
	_screen.play.army_layer.armies.append(kept)
	_screen.play.army_layer.armies.append(arriving)
	home.embarked_army = kept.id
	kept.embarked_fleet = home.id
	fleet.embarked_army = arriving.id
	arriving.embarked_fleet = fleet.id
	_screen.ship_layer.select(ship)

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.province_tiles(capital)[0]))

	assert_eq(home.embarked_army, kept.id, "the home army stays aboard")
	assert_eq(arriving.province, capital, "the surplus army goes ashore")
	assert_eq(arriving.embarked_fleet, -1)
	assert_not_null(_screen.play.army_layer.marker_for(arriving))


## A re-moored home squadron keeps its troops; a second army goes ashore at the
## new seat instead of drowning in the merge (wiki: ships-and-naval § Ports that
## change hands; DR-20261109-11).
func test_a_re_mooring_lands_the_surplus_army() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the opening muster moors a home squadron")
	var seat: int = _owned_coastal_except(_screen.model, capital)
	assert_gte(seat, 0, "the fixture owns another coast")
	var moored: FleetState = null
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet != home and fleet.owner == MapScreen.PLAYER_FACTION:
			moored = fleet
			break
	assert_not_null(moored, "the muster has a second player squadron")
	moored.location = FleetState.Location.IN_PORT
	moored.province = seat
	moored.sea_zone = MapModel.NO_ID
	moored.moved = false
	var kept := ArmyState.muster(92, play.player_faction, capital, false, ["pikemen"], 920)
	var surplus := ArmyState.muster(93, play.player_faction, seat, false, ["pikemen"], 930)
	play.army_layer.armies.append(kept)
	play.army_layer.armies.append(surplus)
	home.embarked_army = kept.id
	kept.embarked_fleet = home.id
	moored.embarked_army = surplus.id
	surplus.embarked_fleet = moored.id

	MapPlayFleets.settle_ports(play, [{
		"faction": MapScreen.PLAYER_FACTION,
		"lost": capital,
		"province": seat,
		"region": _screen.region_index,
	}])

	assert_false(_screen.ship_layer.fleets.has(home), "the home squadron is absorbed")
	assert_eq(moored.embarked_army, surplus.id, "the moored army stays aboard")
	assert_eq(kept.province, seat, "the absorbed army goes ashore at the new seat")
	assert_eq(kept.embarked_fleet, -1)


## The port verdict is reported, and a stranded squadron sorts out (wiki:
## ships-and-naval § Ports that change hands; DR-20261109-11).
func test_the_port_verdict_is_reported() -> void:
	var fleet: FleetState = _screen.ship_layer.home_fleet(_screen.play.capital_province)
	assert_not_null(fleet, "the opening muster moors a home squadron")
	var province: int = fleet.province
	var data: ProvinceState = _screen.model.province_data(province)
	var old_owner: int = data.owner
	data.owner = 1

	MapPlayFleets.settle_ports(_screen.play, [])

	data.owner = old_owner

	assert_true(fleet.is_at_sea(), "the stranded squadron sorts out")
	assert_not_null(_screen.ship_layer.ship_for(fleet))


## A re-mooring with no squadron at the new seat is reported, and the helpers
## tolerate a bare session (wiki: ships-and-naval § Ports that change hands;
## DR-20261109-12).
func test_a_re_mooring_without_a_moored_squadron_is_reported() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the opening muster moors a home squadron")
	var seat: int = _owned_coastal_except(_screen.model, capital)
	assert_gte(seat, 0, "the fixture owns another coast")

	MapPlayFleets.settle_ports(play, [{
		"faction": MapScreen.PLAYER_FACTION,
		"lost": capital,
		"province": seat,
		"region": _screen.region_index,
	}])

	assert_eq(home.province, seat, "the home squadron re-moors")
	var bare := PlaySession.new()
	MapPlayPortLoss.settle(bare, [])
	MapPlayPortLoss.put_ashore(bare, 1, 0)
	MapPlayPortLoss.put_ashore(play, 999, seat)


func _passenger(fleet: FleetState, type_id: String = "explorer") -> CivilianState:
	var unit: CivilianState = _screen.civilian_layer.add_unit(
		_screen.play.player_faction, type_id, CivilianState.NO_TILE
	)
	unit.embark_on(fleet.id)
	fleet.add_civilian(unit.id)
	return unit


func _cross_to_new_world() -> FleetState:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = _old_world_passage()
	fleet.province = MapModel.NO_ID
	_screen.ship_layer.select(ship)
	MapPlayFleets.try_order(_screen.play, _passage_tile(fleet.sea_zone))
	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD)
	return fleet


func _old_world_passage() -> int:
	var zones: Array[int] = _screen.world.warp_zones(FactionCatalog.OLD_WORLD)
	assert_gt(zones.size(), 0, "the Old World has a passage")
	return zones[0]


func _passage_tile(zone_id: int) -> Vector2i:
	return _screen.model.sea_zone_data(zone_id).tiles[0]


func _zone_fog(zone_id: int) -> int:
	var tile: Vector2i = _passage_tile(zone_id)
	return _screen.overlay.fog_state_at(tile.x, tile.y)


func _roster(region: int) -> Array[FleetState]:
	var stored: Array[FleetState] = []
	stored.assign(_screen.ship_layer.regions.value(region, []))
	return stored


func _unique_fleet_ids() -> bool:
	var seen: Dictionary = {}
	for fleet: FleetState in _screen.ship_layer.fleets:
		if seen.has(fleet.id):
			return false
		seen[fleet.id] = true
	return true


func _player_ship_at_sea() -> Ship:
	for ship: Ship in _screen.ship_layer.ships:
		var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			return ship
	return _screen.ship_layer.ships[0]


# --- the beachhead mission ----------------------------------------------------


func _hostile_coast(zone_id: int = MapModel.NO_ID) -> Array:
	for zone: SeaZoneState in _screen.model.sea_zones:
		if zone_id != MapModel.NO_ID and int(zone.id) != zone_id:
			continue
		for province: int in NavalMovement.provinces_by_zone(_screen.model, zone.id):
			var owner: int = _screen.model.province_owner(province)
			if owner != _screen.play.player_faction and owner != MapModel.NO_ID:
				return [province, zone.id]
	return []


## Declares war on `owner` so its coast reads as a landing site to the dossier.
func _declare_war(owner: int) -> void:
	if _screen.play.diplomacy == null:
		_screen.play.diplomacy = DiplomacyState.new()
	_screen.play.diplomacy.ensure_relation(_screen.play.player_faction, owner, _screen.play.turn)
	var war: Dictionary = DiplomacyRules.declare_war(
		_screen.play.diplomacy, _screen.play.player_faction, owner, false
	)
	assert_true(bool(war.get("ok", false)), String(war.get("reason", "")))


## The dossier offers the hostile coasts beside the zone, marking one spends the
## move, and the landing note follows the one-turn timer (wiki: ships-and-naval
## § Missions and Movement; DR-20261109-13).
func test_the_dossier_marks_a_beachhead_and_counts_the_turn() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.owner = _screen.play.player_faction
	fleet.location = FleetState.Location.AT_SEA
	fleet.province = MapModel.NO_ID
	fleet.moved = false
	fleet.clear_beachhead()
	var choice: Array = _hostile_coast()
	assert_false(choice.is_empty(), "the fixture has a foreign coast")
	var coast: int = int(choice[0])
	fleet.sea_zone = int(choice[1])
	fleet.moved = false
	var owner: int = _screen.model.province_owner(coast)
	_declare_war(owner)
	_screen.ship_layer.select(ship)

	var rows: Array[Dictionary] = MapPlayBeachhead.rows(_screen.play, fleet)
	assert_gt(rows.size(), 0, "the hostile coast is offered by name")
	assert_eq(MapPlayBeachhead.rows(_screen.play, null).size(), 0)
	assert_eq(MapPlayBeachhead.note(_screen.play, null), "")

	MapPlayFleets.on_action(_screen.play, "beachhead:%d" % coast)

	assert_eq(fleet.beachhead_province, coast)
	assert_eq(fleet.beachhead_turn, _screen.play.turn)
	assert_true(fleet.moved, "marking spends the fleet's move")
	assert_true(MapPlayBeachhead.note(_screen.play, fleet).contains("opens next turn"))
	assert_eq(MapPlayBeachhead.rows(_screen.play, fleet).size(), 0)
	# The dossier prints the station note once; the hint under it says what the
	# site costs instead of repeating the same sentence (REQ-P5-06).
	var hint: String = MapPlayFleetMissions.hint(_screen.play, fleet)
	assert_false(hint.is_empty(), "a held site has a hint")
	assert_ne(hint, MapPlayBeachhead.note(_screen.play, fleet))
	assert_true(hint.contains("drops the site"))
	assert_true(_screen.hud.panels.fleet_panel._mission.visible)
	_screen.play.turn += 1
	assert_true(MapPlayBeachhead.note(_screen.play, fleet).contains("no troops"))
	assert_true(MapPlayFleetMissions.hint(_screen.play, fleet).contains("lapses"))
	var army := ArmyState.muster(99, _screen.play.player_faction, 0, false, ["pikemen"], 990)
	_screen.play.army_layer.armies.append(army)
	army.embarked_fleet = fleet.id
	fleet.embarked_army = army.id
	MapPlayFleets.show_dossier(_screen.play, fleet)
	assert_true(MapPlayBeachhead.note(_screen.play, fleet).contains("land the troops"))
	assert_true(MapPlayFleetMissions.hint(_screen.play, fleet).contains("Landing spends the site"))
	assert_gt(MapPlayFleets.landing_rows(_screen.play, fleet).size(), 0)

	MapPlayFleets.on_action(_screen.play, "land:%d" % coast)

	assert_eq(army.province, coast, "the army storms ashore")
	assert_false(fleet.has_beachhead(), "the landing consumes the marker")
	assert_eq(MapPlayBeachhead.note(_screen.play, fleet), "")
	fleet.beachhead_province = coast
	fleet.beachhead_turn = _screen.play.turn - 2
	assert_true(MapPlayBeachhead.note(_screen.play, fleet).contains("lapsed"))
	var toasts: int = _screen.hud._toast_box.get_child_count()
	MapPlayBeachhead.establish(_screen.play, fleet, coast)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts + 1)


# --- troops aboard (wiki: ships-and-naval § Naval transport) -----------------


## A boarding repaints the open fleet dossier at once: the crown is told its
## squadron carries troops without touching another order (REQ-P5-05).
func test_boarding_repaints_the_fleet_dossier() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	var fleet: FleetState = _screen.ship_layer.home_fleet(capital)
	if fleet == null:
		fleet = FleetState.in_port(90, play.player_faction, capital, ["ship_90"], {})
		_screen.ship_layer.fleets.append(fleet)
		_screen.ship_layer.rebuild_markers()
	fleet.moved = false
	var army := ArmyState.muster(91, play.player_faction, capital, false, ["pikemen"], 910)
	play.army_layer.armies.append(army)
	play.army_layer.selected_army = army
	_screen.ship_layer.select(_screen.ship_layer.ship_for(fleet))
	MapPlayFleets.select(play, _screen.ship_layer.ship_for(fleet))
	assert_false(_screen.hud.panels.fleet_panel._ships.text.contains("carrying"))

	MapPlayArmies.embark(play, army)

	assert_eq(fleet.embarked_army, army.id)
	assert_true(
		_screen.hud.panels.fleet_panel._ships.text.contains("carrying 1 regiment"),
		"the dossier reads '%s'" % _screen.hud.panels.fleet_panel._ships.text
	)


# --- stations (wiki: ships-and-naval § Missions and Movement) ----------------


## The dossier offers the zone stations; taking one spends the move and the
## station survives into the next turn (DR-20261109-16).
func test_the_dossier_offers_a_patrol_and_taking_it_spends_the_move() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.mission = FleetState.Mission.NONE
	fleet.blockade_province = MapModel.NO_ID
	fleet.moved = false
	fleet.clear_beachhead()
	_screen.ship_layer.select(ship)
	var offered: bool = false
	for row: Dictionary in MapPlayFleetMissions.rows(_screen.play, fleet):
		if String(row.get("action", "")) == "mission:patrol":
			offered = true
	assert_true(offered, "the dossier offers patrol")
	assert_true(_screen.hud.panels.fleet_panel._mission.visible)

	MapPlayFleets.on_action(_screen.play, "mission:patrol")

	assert_eq(fleet.mission, FleetState.Mission.PATROL)
	assert_true(fleet.moved, "a station spends the turn's move")
	assert_true(MapPlayFleetMissions.note(_screen.play, fleet).contains("patrol"))
	assert_true(_screen.hud.panels.fleet_panel._mission.visible)


func test_sailing_away_clears_the_station() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.mission = FleetState.Mission.NONE
	fleet.moved = false
	_screen.ship_layer.select(ship)
	MapPlayFleets.on_action(_screen.play, "mission:patrol")
	assert_eq(fleet.mission, FleetState.Mission.PATROL)

	fleet.moved = false
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var tile: Vector2i = _screen.model.sea_zones[zone].tiles[0]

	assert_true(MapPlayFleets.try_order(_screen.play, tile))

	assert_eq(fleet.mission, FleetState.Mission.NONE)
	assert_eq(fleet.blockade_province, MapModel.NO_ID)


func test_the_dossier_offers_a_blockade_on_a_hostile_coast() -> void:
	var choice: Array = _hostile_coast()
	assert_false(choice.is_empty(), "the fixture has a foreign coast")
	var coast: int = int(choice[0])
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.owner = _screen.play.player_faction
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = int(choice[1])
	fleet.province = MapModel.NO_ID
	fleet.mission = FleetState.Mission.NONE
	fleet.moved = false
	fleet.clear_beachhead()
	var owner: int = _screen.model.province_owner(coast)
	if _screen.play.diplomacy == null:
		_screen.play.diplomacy = DiplomacyState.new()
	_screen.play.diplomacy.ensure_relation(
		_screen.play.player_faction, owner, _screen.play.turn
	)
	DiplomacyRules.declare_war(
		_screen.play.diplomacy, _screen.play.player_faction, owner, false
	)
	_screen.ship_layer.select(ship)
	var action: String = "mission:blockade:%d" % coast
	var offered: bool = false
	for row: Dictionary in MapPlayFleetMissions.rows(_screen.play, fleet):
		if String(row.get("action", "")) == action:
			offered = true
	assert_true(offered, "the hostile coast is a blockade target")

	MapPlayFleets.on_action(_screen.play, action)

	assert_eq(fleet.mission, FleetState.Mission.BLOCKADE)
	assert_eq(fleet.blockade_province, coast)
	assert_true(FleetMissions.is_blockading(
		_screen.model, fleet, MapPlayBeachhead.hostile(_screen.play)
	))


## A blockade whose coast changes hands has lapsed: the rules attempt no
## interception, so the dossier must not promise one (REQ-P2-03).
func test_a_lapsed_blockade_reads_as_lapsed_in_the_dossier() -> void:
	var choice: Array = _hostile_coast()
	assert_false(choice.is_empty(), "the fixture has a foreign coast")
	var coast: int = int(choice[0])
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.owner = _screen.play.player_faction
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = int(choice[1])
	fleet.province = MapModel.NO_ID
	fleet.mission = FleetState.Mission.NONE
	fleet.moved = false
	fleet.clear_beachhead()
	var owner: int = _screen.model.province_owner(coast)
	if _screen.play.diplomacy == null:
		_screen.play.diplomacy = DiplomacyState.new()
	_screen.play.diplomacy.ensure_relation(
		_screen.play.player_faction, owner, _screen.play.turn
	)
	DiplomacyRules.declare_war(
		_screen.play.diplomacy, _screen.play.player_faction, owner, false
	)
	_screen.ship_layer.select(ship)
	MapPlayFleets.on_action(_screen.play, "mission:blockade:%d" % coast)
	assert_true(MapPlayFleetMissions.note(_screen.play, fleet).contains("Blockading"))

	# The crown's own army takes the coast the squadron blockades.
	_screen.model.province_data(coast).owner = _screen.play.player_faction
	var note: String = MapPlayFleetMissions.note(_screen.play, fleet)

	assert_false(note.contains("Blockading"), "the station no longer intercepts")
	assert_true(note.contains("lapsed"))
	_screen.model.province_data(coast).owner = owner


## The landing line follows the same gate the landing does: a white peace
## before the ready turn leaves nothing to land on (REQ-P2-03).
func test_a_beachhead_note_lapses_when_the_war_ends() -> void:
	var choice: Array = _hostile_coast()
	assert_false(choice.is_empty(), "the fixture has a foreign coast")
	var coast: int = int(choice[0])
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.owner = _screen.play.player_faction
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = int(choice[1])
	fleet.province = MapModel.NO_ID
	fleet.mission = FleetState.Mission.NONE
	fleet.moved = false
	fleet.clear_beachhead()
	var owner: int = _screen.model.province_owner(coast)
	if _screen.play.diplomacy == null:
		_screen.play.diplomacy = DiplomacyState.new()
	_screen.play.diplomacy.ensure_relation(
		_screen.play.player_faction, owner, _screen.play.turn
	)
	DiplomacyRules.declare_war(
		_screen.play.diplomacy, _screen.play.player_faction, owner, false
	)
	var marked: Dictionary = NavalTransport.establish_beachhead(
		_screen.model, fleet, coast, _screen.play.turn, MapPlayBeachhead.hostile(_screen.play)
	)
	assert_true(bool(marked.get("ok", false)), String(marked.get("reason", "")))
	assert_true(MapPlayBeachhead.note(_screen.play, fleet).contains("opens next turn"))

	DiplomacyRules.make_peace(
		_screen.play.diplomacy,
		_screen.play.player_faction,
		owner,
		DiplomacyRules.DECISION_ACCEPT
	)
	var note: String = MapPlayBeachhead.note(_screen.play, fleet)

	assert_false(note.contains("opens next turn"))
	assert_true(note.contains("lapsed"))


# --- the naval yard -----------------------------------------------------------


func test_the_capital_dossier_opens_the_shipyard() -> void:
	var capital: int = _screen.play.capital_province
	assert_gte(capital, 0, "the fixture crowns a capital")

	_screen.play.selected_province = capital
	MapPlayFleetYard.open(_screen.play)

	assert_true(_screen.hud.panels.is_fleet_panel_open())
	assert_true(_screen.hud.panels.fleet_panel._yard._open)
	assert_false(_screen.hud.panels.fleet_panel._yard._rows.is_empty())


## The province dossier's Shipyard row routes straight to the yard helper.
func test_the_province_dossier_routes_to_the_shipyard() -> void:
	var play: PlaySession = _screen.play
	play.selected_province = play.capital_province

	MapPlayInput.on_panel_action(play, "shipyard")

	assert_true(_screen.hud.panels.is_fleet_panel_open())
	assert_true(_screen.hud.panels.fleet_panel._yard._open)


## The yard claims its own orders only: the fleet dispatcher hands it every
## dossier press, so a foreign intent must fall through untouched (REQ-P3-02).
func test_the_shipyard_claims_only_its_own_intents() -> void:
	assert_false(MapPlayFleetYard.on_action(_screen.play, "mission:patrol"))
	assert_false(MapPlayFleetYard.on_action(_screen.play, "land:0"))
	assert_true(MapPlayFleetYard.on_action(_screen.play, "yard:scrap:no_such_hull"))


## A rival's squadron carries no slip: the yard is the crown's own capital.
func test_a_rival_squadron_carries_no_yard_rows() -> void:
	var rival: FleetState = FleetState.in_port(
		999, 999, 0, ["frigate_1"], {"frigate_1": "frigate"}
	)
	assert_true(
		MapPlayFleetYard.rows(_screen.play, rival).is_empty(),
		"no slip for a rival's hull"
	)


## A lost capital says why instead of opening a slip the crown cannot use.
func test_the_yard_refuses_a_capital_the_crown_lost() -> void:
	var play: PlaySession = _screen.play
	play.capital_province = _unowned_province()
	assert_gte(play.capital_province, 0, "the fixture has a province another crown holds")
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayFleetYard.open(play)
	MapPlayFleetYard.launch(play, "carrack")

	assert_eq(_screen.hud._toast_box.get_child_count(), toasts + 2, "both say why")
	assert_false(_screen.hud.panels.is_fleet_panel_open())


## An inland capital cannot build hulls; the court is told before it pays.
func test_the_yard_needs_a_harbour() -> void:
	var play: PlaySession = _screen.play
	play.capital_province = _inland_owned_province()
	assert_gte(play.capital_province, 0, "the fixture has an inland province")
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayFleetYard.open(play)
	MapPlayFleetYard.launch(play, "carrack")

	assert_eq(_screen.hud._toast_box.get_child_count(), toasts + 2, "both say why")
	assert_false(_screen.hud.panels.is_fleet_panel_open())


## With no home fleet afloat the dossier still opens on the slip, so the first
## launch has a row to press.
func test_the_slip_shows_before_any_home_fleet() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture moors a home fleet")
	home.location = FleetState.Location.AT_SEA
	play.selected_province = capital

	MapPlayFleetYard.open(play)

	assert_true(_screen.hud.panels.is_fleet_panel_open())
	assert_true(_screen.hud.panels.fleet_panel._yard._open)
	assert_false(_screen.hud.panels.fleet_panel._yard._rows.is_empty())


## A poor treasury refuses the launch and keeps the crown's peasants ashore.
func test_a_launch_the_treasury_refuses_says_why() -> void:
	var play: PlaySession = _screen.play
	play.selected_province = play.capital_province
	var econ: PlayerEconomy = play.economy.economy
	econ.treasury = 0
	var hulls: int = _screen.ship_layer.hull_count_all(play.player_faction)
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayFleetYard.launch(play, "carrack")

	assert_eq(_screen.ship_layer.hull_count_all(play.player_faction), hulls)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts + 1, "the refusal is spoken")


## Two regiments aboard need both hulls: the break-up is refused, not half done.
func test_a_loaded_squadron_cannot_be_broken_up() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	play.selected_province = capital
	play.economy.economy.treasury = 60000
	MapPlayFleetYard.launch(play, "carrack")
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	assert_not_null(fleet, "the launch selects the yard's squadron")
	var army := ArmyState.muster(
		98, play.player_faction, capital, false, ["pikemen", "pikemen"], 980
	)
	play.army_layer.armies.append(army)
	army.embarked_fleet = fleet.id
	fleet.embarked_army = army.id
	var hulls: Array[String] = fleet.hulls.duplicate()
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayFleetYard.scrap(play, fleet.hulls[0])

	assert_eq(fleet.hulls, hulls, "the hull stays afloat")
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts + 1, "the refusal is spoken")


## A hull the ledger cannot find is refused rather than silently dropped.
func test_breaking_up_an_unknown_hull_says_why() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	play.selected_province = capital
	play.economy.economy.treasury = 60000
	MapPlayFleetYard.launch(play, "carrack")
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayFleetYard.scrap(play, "no_such_hull")

	assert_eq(_screen.hud._toast_box.get_child_count(), toasts + 1, "the refusal is spoken")


## Every launch row and every hull row leads with its own plate, so the yard
## reads as the same hulls the fleet roster lists (tools/art/unit-medallions.md).
func test_shipyard_rows_carry_the_hull_medallion() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	MapPlayFleetYard.open(_screen.play)
	var yard: FleetYardBlock = _screen.hud.panels.fleet_panel._yard

	var first: Dictionary = yard._rows[0]
	var launch_row: HBoxContainer = yard._box.get_child(1).get_child(0)
	var plate: UnitMedallion = launch_row.get_child(0) as UnitMedallion
	assert_not_null(plate, "the launch row opens with a plate")
	assert_eq(plate.texture, ShipArt.medallion(String(first["type_id"])))

	yard._fleet = FleetState.in_port(1, 0, 0, ["frigate_1"], {"frigate_1": "frigate"})
	var hull_row: HBoxContainer = yard._hull_row("frigate_1").get_child(0)
	assert_eq(
		(hull_row.get_child(0) as UnitMedallion).texture,
		ShipArt.medallion("frigate"),
		"the break-up row wears the hull's own plate"
	)


## A launch is a BuildUnitOrder: the yard queues the hull and reserves her
## peasant, and Build/work pays the row and moors her in the home fleet
## (wiki: ships-and-naval § Ship build economy; workers-and-population
## § Phase placement, § Peasant reservation).
func test_launching_queues_the_hull_and_pays_it_in_build_work() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	var econ: PlayerEconomy = _screen.play.economy.economy
	econ.treasury = 60000
	var treasury: int = econ.treasury
	var peasants: int = econ.available_peasants()
	var hulls: int = _screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION)

	MapPlayFleets.on_action(_screen.play, "yard:build:carrack")

	assert_eq(_screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION), hulls, "no hull yet")
	assert_eq(econ.treasury, treasury, "nothing is paid at the press")
	assert_eq(econ.available_peasants(), peasants - 1, "her peasant is reserved")
	assert_eq(econ.recruits.pending(RecruitQueue.KIND_SHIP, "carrack"), 1)

	MapPlayRecruits.complete(_screen.play)

	var fleet: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(fleet, "the launch founds or joins the home fleet")
	assert_eq(fleet.count_of_type("carrack"), 1)
	assert_eq(_screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION), hulls + 1)
	assert_eq(econ.treasury, treasury - ShipEconomy.treasury_cost("carrack"))
	assert_eq(econ.available_peasants(), peasants - 1, "the reservation became the muster")


func test_breaking_up_a_hull_asks_once() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	_screen.play.economy.economy.treasury = 60000
	MapPlayFleets.on_action(_screen.play, "yard:build:carrack")
	var fleet: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(fleet, "the yard founds the home fleet")
	var hull_id: String = fleet.hulls[fleet.hulls.size() - 1]
	var panel: FleetPanel = _screen.hud.panels.fleet_panel

	panel._on_scrap_pressed(hull_id)

	assert_eq(panel._yard._armed_hull, hull_id, "the first tap only arms")
	assert_true(fleet.hulls.has(hull_id))

	panel._on_scrap_pressed(hull_id)

	assert_false(fleet.hulls.has(hull_id), "the second tap scraps")


func test_a_captured_port_sorts_the_home_squadron_out() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	var fleet: FleetState = _screen.ship_layer.fleets[0]
	fleet.owner = MapScreen.PLAYER_FACTION
	fleet.location = FleetState.Location.IN_PORT
	fleet.province = capital
	fleet.sea_zone = MapModel.NO_ID
	fleet.moved = false
	var zone: int = NavalPortLoss.sortie_zone(_screen.model, capital)
	assert_gte(zone, 0, "the fixture capital is coastal")
	var seat: int = _owned_coastal_except(_screen.model, capital)
	assert_gte(seat, 0, "the fixture owns another coast")
	# A seat move first re-moors the home squadron away from the captured port.
	var moved: Array[Dictionary] = _screen.ship_layer.settle_port_losses(
		_screen.world,
		[{
			"faction": MapScreen.PLAYER_FACTION,
			"lost": capital,
			"province": seat,
			"region": _screen.region_index,
		}]
	)
	assert_false(moved.is_empty())
	assert_eq(fleet.province, seat)
	# Older saves can still keep a stranding squadron: give it back to the port.
	fleet.province = capital
	var data: ProvinceState = _screen.model.province_data(capital)
	var old_owner: int = data.owner
	data.owner = 1

	var reports: Array[Dictionary] = _screen.ship_layer.settle_port_losses(
		_screen.world, []
	)
	data.owner = old_owner

	assert_false(reports.is_empty())
	assert_true(fleet.is_at_sea())
	assert_eq(fleet.sea_zone, zone)
	assert_not_null(_screen.ship_layer.ship_for(fleet))


func test_a_reassigned_seat_re_moors_the_home_squadron() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	var fleet: FleetState = _screen.ship_layer.fleets[0]
	fleet.owner = MapScreen.PLAYER_FACTION
	fleet.location = FleetState.Location.IN_PORT
	fleet.province = capital
	fleet.sea_zone = MapModel.NO_ID
	var seat: int = _owned_coastal_except(_screen.model, capital)
	assert_gte(seat, 0, "the fixture owns another coast")

	var reports: Array[Dictionary] = _screen.ship_layer.settle_port_losses(
		_screen.world,
		[{
			"faction": MapScreen.PLAYER_FACTION,
			"lost": capital,
			"province": seat,
			"region": _screen.region_index,
		}]
	)

	assert_false(reports.is_empty())
	assert_eq(fleet.province, seat)
	assert_true(fleet.is_in_port())


func test_the_home_dossier_ships_a_colonist_and_can_sortie() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var unit: CivilianState = _screen.civilian_layer.units[0]
	unit.tile = _screen.model.province_tiles(capital)[0]
	unit.moved = false
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))

	var crew: Dictionary = MapPlayCivilianVoyage.crew(_screen.play, home)
	assert_eq(int(crew["count"]), 0)
	assert_gt(crew["embark"].size(), 0, "the idle colonist is offered")
	assert_gt(crew["sortie"].size(), 0, "the home squadron can put to sea")

	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:%d" % unit.id)
	assert_true(unit.is_embarked())
	assert_eq(int(MapPlayCivilianVoyage.crew(_screen.play, home)["count"]), 1)
	assert_false(_screen.civilian_layer.marker_for(unit).visible, "aboard leaves the map")

	MapPlayCivilianVoyage.on_action(_screen.play, "crew:land:%d" % capital)
	assert_false(unit.is_embarked())
	assert_true(_screen.civilian_layer.marker_for(unit).visible)
	assert_eq(unit.embarked_fleet, -1)

	var zone: int = int(MapPlayCivilianVoyage.crew(_screen.play, home)["sortie"][0]["zone"])
	MapPlayCivilianVoyage.on_action(_screen.play, "sortie:%d" % zone)
	assert_true(home.is_at_sea())
	assert_false(NavalMovement.is_home_fleet(_screen.model, home))


## A squadron of several hulls flies them: the marker's escorts, hull badge and
## strength gauge follow every launch and breaking up (wiki: ships-and-naval
## § Naval Strength Aggregation Formula).
func test_a_squadron_marker_counts_its_hulls_and_strength() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	_screen.play.economy.economy.treasury = 60000
	MapPlayFleets.on_action(_screen.play, "yard:build:carrack")
	MapPlayRecruits.complete(_screen.play)
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the launch founds or joins the home fleet")
	var marker: Ship = _screen.ship_layer.ship_for(home)
	assert_not_null(marker, "the home squadron keeps a marker")
	assert_eq(marker.hull_count, home.ship_count())
	assert_almost_eq(marker.strength, NavalStrength.strength(home), 0.0001)
	assert_gt(marker.hull_count, 1, "the fixture's home fleet plus one launch")

	var hull_id: String = home.hulls[home.hulls.size() - 1]
	var count_before: int = home.ship_count()
	var result: Dictionary = _screen.ship_layer.scrap_hull(
		home, hull_id, _screen.play.economy.economy
	)

	assert_true(bool(result.get("ok", false)), String(result.get("reason", "")))
	assert_eq(home.ship_count(), count_before - 1)
	assert_eq(marker.hull_count, home.ship_count(), "the marker drops the broken hull")
	assert_almost_eq(marker.strength, NavalStrength.strength(home), 0.0001)


## The printed strength needs the closer chart; fit zoom keeps the silhouettes.
func test_the_zoom_sets_the_marker_detail() -> void:
	var ship: Ship = _screen.ship_layer.ships[0]

	_screen.ship_layer.set_zoom(1.0)
	assert_true(ship.detail)

	_screen.ship_layer.set_zoom(0.5)
	assert_false(ship.detail)


## The dossier prints the arithmetic the resolver fights with, not a bare score.
func test_the_fleet_dossier_prints_the_combat_maths() -> void:
	var ship: Ship = _player_ship_at_sea()
	_screen.ship_layer.select(ship)
	var block: FleetStrengthSection = _screen.hud._fleet_panel._strength

	assert_true(block.visible, "a squadron with hulls shows its strength")
	assert_true(block._strength.text.contains("strength ="), block._strength.text)
	assert_true(block._strength.text.contains("FRP"), block._strength.text)
	assert_true(block._pool.text.contains("Hull pool"), block._pool.text)
	assert_true(block._pool.text.contains("53%"), block._pool.text)
	assert_false(block._zone.visible, "empty water needs no odds line")


## A hostile squadron in the same water shows the share of strength each side
## holds, so the court knows what the turn's battle would decide. An unread
## rival withholds the share until the crown's watch closes (wiki:
## ships-and-naval § Sighted strength).
func test_a_contested_zone_shows_the_share_of_strength() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.location = FleetState.Location.AT_SEA
	fleet.province = MapModel.NO_ID
	fleet.sea_zone = NavalMovement.province_sea_zones(
		_screen.model, _screen.play.capital_province
	)[0]
	var rival: int = 1 if fleet.owner != 1 else 2
	var enemy := FleetState.at_sea(
		77, rival, fleet.sea_zone, ["ship_77"], {"ship_77": "frigate"}
	)
	_screen.ship_layer.fleets.append(enemy)
	_declare_war(rival)

	_screen.ship_layer.select(ship)
	var block: FleetStrengthSection = _screen.hud._fleet_panel._strength

	assert_true(block._zone.text.contains("not yet read"), block._zone.text)
	assert_eq(
		block._zone.get_theme_color("font_color"),
		Palette.GOLD_PALE,
		"an unread rival leaves the water undecided"
	)

	# The watch closes across the turn boundary: her weight joins the odds.
	_screen.play.naval_intel.observe([enemy.id], _screen.play.turn, _screen.play.region_index)
	_screen.play.turn += 1
	_screen.play.naval_intel.observe([enemy.id], _screen.play.turn, _screen.play.region_index)
	MapPlayFleets.show_dossier(_screen.play, fleet)

	assert_true(block._zone.text.contains("you hold"), block._zone.text)
	assert_true(block._zone.text.contains("against"), block._zone.text)
	# A rival line of the line outweighs the squadron: the verdict turns red.
	enemy.set_hulls(["ship_77", "ship_78", "ship_79"], {"ship_77": "frigate",
		"ship_78": "frigate", "ship_79": "ship_of_the_line"})
	MapPlayFleets.show_dossier(_screen.play, fleet)

	assert_eq(
		block._zone.get_theme_color("font_color"),
		Palette.HEALTH_LOW,
		"a losing share reads as a loss"
	)
	_screen.ship_layer.fleets.erase(enemy)


## The marker's art path draws a squadron at both chart zooms: escorts, badge,
## the strength plate and the printed number, plus the unread rival's `*`
## (REQ-P1-03, RUB-P1-04).
func test_the_marker_draws_a_squadron_at_both_zooms() -> void:
	var marker := Ship.new()
	_screen.add_child(marker)
	marker.set_squadron(3, 12.8)
	marker.docked = true
	marker.set_selected(true)
	marker.detail = true
	marker.queue_redraw()
	await get_tree().process_frame

	marker.docked = false
	marker.detail = false
	marker.set_squadron(1, 2.75)
	marker.queue_redraw()
	await get_tree().process_frame

	# An unread rival flies the mark instead of her weight.
	marker.set_squadron(4, 31.5)
	marker.set_intel(false)
	marker.queue_redraw()
	await get_tree().process_frame

	assert_false(marker.strength_known)
	assert_eq(marker.hull_count, 4, "an unread squadron still flies her hulls")
	marker.set_intel(true)
	assert_true(marker.strength_known)
	marker.set_squadron(1, 2.75)
	assert_eq(marker.hull_count, 1)
	assert_almost_eq(marker.strength, 2.75, 0.0001)
	marker.queue_free()


## A sea fight the crown fought leaves a word at the rival's court: the booking
## reads a zone as water, not a province (wiki: dialogue-and-mood § Design
## intent — event; DR-20261111-01).
func test_a_sea_fight_leaves_a_word_at_the_rivals_court() -> void:
	var rival: int = 2
	DiplomacyRules.declare_war(
		_screen.play.diplomacy, _screen.play.player_faction, rival
	)
	_screen.play.emit_battle_resolved([
		{
			"zone": 1, "attacker": _screen.play.player_faction, "defender": rival,
			"outcome": NavalCombat.Outcome.SIDE1_VICTORY, "retreat": {},
		},
	] as Array[Dictionary])

	var spoken: Dictionary = DialogueEvents.for_pair(
		_screen.play.diplomacy, _screen.play.player_faction, rival
	)
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_EVENT, "the water answers")
	assert_eq(String(spoken["point"]), "event/sea_lost", "the beaten court owns it")


func _owned_coastal_except(model: MapModel, skip: int) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner != MapScreen.PLAYER_FACTION or province.id == skip:
			continue
		if not NavalMovement.province_sea_zones(model, province.id).is_empty():
			return province.id
	return -1


func _enemy_ship() -> Ship:
	for ship: Ship in _screen.ship_layer.ships:
		var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner != MapScreen.PLAYER_FACTION:
			return ship
	return _screen.ship_layer.ships[0]


## Every line the court's toasts currently show.
func _toast_texts() -> Array[String]:
	var texts: Array[String] = []
	for panel: Node in _screen.hud._toast_box.get_children():
		for label: Label in panel.find_children("*", "Label", true, false):
			texts.append(label.text)
	return texts


func _remote_zone() -> int:
	var occupied: Array[int] = _screen.ship_layer.at_sea_zones(MapScreen.PLAYER_FACTION)
	for zone: SeaZoneState in _screen.model.sea_zones:
		var zone_id: int = int(zone.id)
		if _screen.visibility.owns_coast(zone_id) or occupied.has(zone_id):
			continue
		return zone_id
	return -1


## A province another crown holds, for the yard's "capital must be in hand" row.
func _unowned_province() -> int:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner != _screen.play.player_faction and province.owner != MapModel.NO_ID:
			return province.id
	return -1


## An owned province with no harbour, for the yard's "no harbour" row.
func _inland_owned_province() -> int:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner != _screen.play.player_faction:
			continue
		if not NavalMovement.has_harbour(_screen.model, province.id):
			return province.id
	return -1
