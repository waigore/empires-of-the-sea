extends GdToolsTest
## Fleet orders end-to-end through the real map screen (wiki: ships-and-naval).
## Kept separate from test_map_screen so each native suite stays inside the
## coverage runner's per-suite timeout.

const Fixture = preload("res://tests/map_fixture.gd")
const NavalFixture = preload("res://tests/naval_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so the cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`).
var mounted: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []
var _screen: MapScreen = null
var _model: MapModel = null


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine)
	_screen = mounted
	# The home-fleet merge cases read a hand-built two-coast chart; the others
	# never touch it (the fixture is a few dozen tiles).
	_model = NavalFixture.build()


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	_screen = null
	pristine = {}


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


## A marker minted after the watch closed keeps the chart's reading. Joining the
## home fleet, crossing a passage or losing a port rebuilds every marker, and a
## rebuild must not hand back a weight the crown has not read (wiki:
## ships-and-naval § Sighted strength).
func test_a_rebuilt_marker_keeps_the_watch() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	MapPlayFleets.refresh_visibility(_screen.play)

	_screen.ship_layer.rebuild_markers()
	var unread: Ship = _screen.ship_layer.ship_for(fleet)
	assert_not_null(unread)
	assert_false(unread.strength_known, "a rebuilt marker still flies *")

	_screen.play.turn += 1
	MapPlayFleets.refresh_visibility(_screen.play)
	_screen.ship_layer.rebuild_markers()
	var read: Ship = _screen.ship_layer.ship_for(fleet)
	assert_not_null(read)
	assert_true(read.strength_known, "a read squadron stays read after a rebuild")


## A rebuilt chart never draws a rival the crown's fog hides, nor reads her
## weight there (wiki: fog-and-exploration § Visibility Levels; ships-and-naval
## § Sighted strength).
func test_a_rebuilt_marker_stays_under_the_fog() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_false(enemy.visible, "the fog keeps her off the chart")

	_screen.ship_layer.rebuild_markers()
	var hidden: Ship = _screen.ship_layer.ship_for(fleet)
	assert_not_null(hidden)
	assert_false(hidden.visible, "a rebuild does not draw her")
	assert_false(hidden.strength_known, "and does not read her weight")


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


## The yard names the hull a crown would buy, not only her price: her own combat
## line and the holds her class carries, the same words THE CROWN'S NAVY prints
## for a hull already afloat (wiki: ships-and-naval § Ship combat and cargo stats;
## REQ-P5-06). A hull the crown cannot launch yet keeps her line too — the study
## that opens her is planned against her numbers.
func test_the_yard_names_the_hull_before_the_crown_pays_for_her() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	MapPlayFleetYard.open(_screen.play)
	var rows: Array[Dictionary] = _screen.hud.panels.fleet_panel._yard._rows
	var by_type: Dictionary = {}
	for row: Dictionary in rows:
		by_type[String(row["type_id"])] = row

	assert_true(by_type.has("carrack"), "the carrack is on the slip")
	assert_eq(
		String((by_type["carrack"] as Dictionary)["line"]),
		NavalStrength.hull_line("carrack") + " · 3 holds for the world market",
		"a merchant names her holds beside her numbers"
	)
	assert_true(by_type.has("frigate"), "a study-locked hull keeps her row")
	assert_eq(
		String((by_type["frigate"] as Dictionary)["line"]),
		NavalStrength.hull_line("frigate") + " · No holds — she fights in the line",
		"a warship names the holds she does not carry"
	)
	assert_eq(
		String(FleetYard.hull_line("indiaman")),
		NavalStrength.hull_line("indiaman") + " · 8 holds for the world market",
		"one reading for the yard and the navy sheet"
	)


## The line reaches the sheet on both the launch rows and the break-up rows, so
## a phone reads the hull's numbers with no hover (REQ-P5-06, REQ-P5-07).
func test_the_shipyard_row_prints_the_hull_numbers() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	MapPlayFleetYard.open(_screen.play)
	var yard: FleetYardBlock = _screen.hud.panels.fleet_panel._yard
	var launch_row: Control = yard._box.get_child(1)
	var first: Dictionary = yard._rows[0]

	assert_true(
		_printed_lines(launch_row).has(String(first["line"])),
		"the launch row prints her numbers under her price"
	)
	yard._fleet = FleetState.in_port(1, 0, 0, ["frigate_1"], {"frigate_1": "frigate"})
	var hull_row: Control = yard._hull_row("frigate_1")
	assert_true(
		_printed_lines(hull_row).has(FleetYard.hull_line("frigate")),
		"the break-up row prints the same line"
	)


## Every wrapped detail line a drawer row carries: the price, the wait and now
## the hull's own numbers.
func _printed_lines(entry: Control) -> Array[String]:
	var out: Array[String] = []
	for child: Node in entry.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


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


## A rival the crown has sighted but not read keeps her muster to herself: the
## dossier prints `??? hulls` with no count, no types and no upkeep bill, and the
## watch closing reveals the composition with the strength (wiki: ships-and-naval
## § Sighted strength).
func test_an_unread_rival_dossier_keeps_her_muster() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	var zone: int = NavalMovement.province_sea_zones(
		_screen.model, _screen.play.capital_province
	)[0]
	fleet.location = FleetState.Location.AT_SEA
	fleet.province = MapModel.NO_ID
	fleet.sea_zone = zone
	var rival: int = 1 if fleet.owner != 1 else 2
	var enemy := FleetState.at_sea(
		78, rival, zone, ["ship_78", "ship_79"], {"ship_78": "frigate", "ship_79": "carrack"}
	)
	_screen.ship_layer.fleets.append(enemy)
	_declare_war(rival)

	MapPlayFleets.show_dossier(_screen.play, enemy)
	var panel: FleetPanel = _screen.hud._fleet_panel

	assert_eq(panel._ships.text, "??? hulls — the fog has not yet given up her muster.")
	assert_false(panel._ships.text.contains("Carrack"), "no hull type leaks")
	assert_false(panel._ships.text.contains("upkeep"), "her bill is not the crown's yet")

	# The watch closes across the turn boundary: her muster joins the reading.
	_screen.play.naval_intel.observe([enemy.id], _screen.play.turn, _screen.play.region_index)
	_screen.play.turn += 1
	_screen.play.naval_intel.observe([enemy.id], _screen.play.turn, _screen.play.region_index)
	MapPlayFleets.show_dossier(_screen.play, enemy)

	assert_true(panel._ships.text.contains("2 ships"), panel._ships.text)
	assert_true(panel._ships.text.contains("Carrack"), panel._ships.text)
	assert_true(panel._ships.text.contains("upkeep"), panel._ships.text)
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


## The capital slip names the crown that holds it, not the legacy default: a
## court sailing as England reads her own yard (wiki: game-setup § Human/AI slot
## assignment; REQ-P2-03 — a sheet never answers for another crown).
func test_the_capital_slip_names_the_crown_that_holds_it() -> void:
	var province: int = _screen.capital_province
	var data: ProvinceState = _screen.model.province_data(province)
	var before: int = data.owner
	data.owner = 1
	_screen.hud._fleet_panel.refresh_slip(_screen.model, province, [], true)
	var title: String = _screen.hud._fleet_panel._header.title.text
	assert_true(title.contains("ENGLAND"), title)
	data.owner = before


# --- home-fleet merge --------------------------------------------------------
## The one-tap join a squadron moored at the crown's seat can take, the docking
## absorption it shares, and the dossier row and report the player meets (wiki:
## ships-and-naval § Home Fleet — membership and state). Merged from
## test_home_merge: the rules cases read the two-coast fixture and the dossier
## cases drive the one mounted chart.


func test_the_home_fleet_is_the_squadron_at_the_seat() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var at_sea := FleetState.at_sea(3, 0, 0)
	var roster: Array[FleetState] = [at_sea, home]

	assert_eq(FleetHomeMerge.home_fleet(_model, roster, 0), home)
	assert_null(FleetHomeMerge.home_fleet(_model, roster, 1), "a rival's port is not a home fleet")


func test_a_moored_squadron_joins_the_home_fleet() -> void:
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var stray := FleetState.in_port(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	stray.hull_names["ship_b"] = "Santa Ana"
	var roster: Array[FleetState] = [home, stray]

	assert_true(bool(FleetHomeMerge.can_join(_model, roster, stray)["ok"]))
	var joined: Dictionary = FleetHomeMerge.join(_model, roster, stray)

	assert_true(bool(joined["ok"]))
	assert_eq(joined["fleet"], home)
	assert_eq(int(joined["hulls"]), 1)
	assert_eq(roster.size(), 1, "the sea-going squadron leaves the roster")
	assert_eq(home.hulls, ["ship_a", "ship_b"], "instance ids survive in order")
	assert_eq(home.hull_names["ship_b"], "Santa Ana", "a hull keeps the name it flies")
	assert_eq(home.count_of_type("fluyte"), 1)


func test_a_squadron_at_sea_is_told_to_moor_first() -> void:
	var home := FleetState.in_port(2, 0, 0)
	var at_sea := FleetState.at_sea(3, 0, 0)
	var roster: Array[FleetState] = [home, at_sea]

	var check: Dictionary = FleetHomeMerge.can_join(_model, roster, at_sea)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("capital port"))


func test_a_lone_squadron_has_nothing_to_join() -> void:
	var home := FleetState.in_port(2, 0, 0)
	var roster: Array[FleetState] = [home]

	var check: Dictionary = FleetHomeMerge.can_join(_model, roster, home)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("only squadron"))


func test_a_port_that_is_not_the_seat_cannot_join() -> void:
	_model.provinces[1].owner = 0
	var home := FleetState.in_port(2, 0, 0)
	var other := FleetState.in_port(3, 0, 1)
	var roster: Array[FleetState] = [home, other]

	assert_false(bool(FleetHomeMerge.can_join(_model, roster, other)["ok"]))
	assert_eq(roster.size(), 2, "a refusal mutates nothing")


func test_a_second_army_goes_ashore_from_the_merge() -> void:
	var home := FleetState.in_port(2, 0, 0)
	home.embarked_army = 11
	var stray := FleetState.in_port(3, 0, 0)
	stray.embarked_army = 12
	var roster: Array[FleetState] = [home, stray]

	var joined: Dictionary = FleetHomeMerge.join(_model, roster, stray)

	assert_eq(home.embarked_army, 11, "the home fleet keeps its own troops")
	assert_eq(int(joined["displaced"]), 12, "the second army is reported for landing")


func test_the_oldest_squadron_at_the_seat_absorbs_the_rest() -> void:
	var older := FleetState.in_port(4, 0, 0)
	var newer := FleetState.in_port(7, 0, 0)
	var incoming := FleetState.at_sea(9, 0, 0)
	var roster: Array[FleetState] = [newer, incoming, older]

	NavalMovement.apply_move(_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_model, roster, incoming)

	assert_eq(merge.get("fleet"), older, "one home fleet per seat: the oldest")
	assert_eq(roster.size(), 2)


func test_settle_folds_every_extra_squadron_into_the_home_fleet() -> void:
	var home := FleetState.in_port(2, 0, 0)
	var first := FleetState.in_port(3, 0, 0)
	var second := FleetState.in_port(5, 0, 0)
	var roster: Array[FleetState] = [home, first, second]

	var reports: Array[Dictionary] = FleetHomeMerge.settle(_model, roster, 0)

	assert_eq(reports.size(), 2)
	assert_eq(roster.size(), 1, "one squadron per capital port")
	assert_eq(home.ship_count(), 3, "every hull keeps its instance id")
	assert_eq(int(reports[0]["into"]), 2)
	assert_eq(FleetHomeMerge.settle(_model, roster, 0).size(), 0, "the pass is idempotent")


func test_the_dossier_offers_a_one_tap_join_at_the_seat() -> void:
	var stray: FleetState = _stray_at_the_seat()
	_screen.ship_layer.select(_screen.ship_layer.ship_for(stray))

	var row: Dictionary = MapPlayHomeMerge.row(_screen.play, stray)
	var panel: FleetPanel = _screen.hud._fleet_panel

	assert_true(bool(row["ok"]), "a moored squadron can join")
	assert_eq(String(row["label"]), "Join the home fleet")
	assert_true(String(row["note"]).contains("home fleet"))
	assert_true(panel._merge_box.visible, "the dossier shows the row")
	assert_false(panel._yard._button.visible, "the join takes the yard's place, not more height")
	assert_eq(panel._status.text, String(row["note"]), "the note rides the status line")


func test_joining_keeps_the_player_on_the_home_fleet() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var stray: FleetState = _stray_at_the_seat()
	var hulls_before: int = home.ship_count()
	var stray_hulls: int = stray.ship_count()
	_screen.ship_layer.select(_screen.ship_layer.ship_for(stray))

	MapPlayHomeMerge.join(_screen.play)

	assert_false(_screen.ship_layer.fleets.has(stray), "the sea-going squadron is gone")
	assert_null(_screen.ship_layer.ship_for(stray), "its marker leaves the map")
	assert_eq(home.ship_count(), hulls_before + stray_hulls)
	assert_eq(
		_screen.ship_layer.fleet_of(_screen.ship_layer.selected()), home,
		"the dossier follows the hulls"
	)
	assert_eq(_screen.hud._fleet_panel._status.text, "Home fleet")
	assert_true(_last_toast().contains("home fleet at"), "the report names the merge")


func test_docking_at_the_seat_names_the_hulls_and_holds() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var sea: FleetState = _moored_squadron_at_the_seat()
	sea.location = FleetState.Location.AT_SEA
	sea.province = MapModel.NO_ID
	sea.moved = false
	_screen.ship_layer.select(_screen.ship_layer.ship_for(sea))
	var hulls: int = sea.ship_count()

	var hulls_before: int = home.ship_count()
	assert_true(
		MapPlayFleets.try_order(_screen.play, _screen.model.province_data(capital).port_tile)
	)

	assert_false(_screen.ship_layer.fleets.has(sea), "the sea-going squadron is gone")
	assert_eq(home.ship_count(), hulls_before + hulls)
	var report: String = _last_toast()
	assert_true(report.contains("%d hull" % hulls), "the report counts the hulls that joined")
	assert_true(report.contains("cargo hold"), "the report names the holds she carries")


func test_the_home_dossier_shows_her_holds() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))

	var row: Dictionary = MapPlayHomeMerge.row(_screen.play, home)
	var panel: FleetPanel = _screen.hud._fleet_panel

	assert_true(bool(row.get("home", false)))
	assert_true(String(row["holds_text"]).contains("cargo hold"))
	assert_false(bool(row.get("ok", false)), "the home fleet offers no join button")
	assert_true(panel._ships.text.contains("cargo hold"), "the dossier names the holds")
	assert_eq(panel._status.text, "Home fleet")


func test_a_squadron_at_sea_sees_the_merge_before_it_docks() -> void:
	var capital: int = _screen.play.capital_province
	var sea: FleetState = _moored_squadron_at_the_seat()
	sea.location = FleetState.Location.AT_SEA
	sea.province = MapModel.NO_ID
	sea.sea_zone = NavalMovement.province_sea_zones(_screen.model, capital)[0]
	_screen.ship_layer.select(_screen.ship_layer.ship_for(sea))

	var row: Dictionary = MapPlayHomeMerge.row(_screen.play, sea)

	assert_false(bool(row.get("ok", false)), "the nudge is not a button")
	assert_true(String(row["note"]).contains("joins the home fleet"))


func test_a_transitional_save_repairs_on_load() -> void:
	var stray: FleetState = _stray_at_the_seat()

	MapPlayHomeMerge.repair(_screen.play)

	assert_false(_screen.ship_layer.fleets.has(stray), "one squadron per capital port")
	assert_null(_screen.ship_layer.ship_for(stray))
	assert_true(_last_toast().contains("rejoined the home fleet"))


## A rival planner that only moves hulls (invasion, voyage, cargo) leaves the
## squadron standing beside the home fleet at the seat; the turn's own pass folds
## it in, so the seat never ends a turn holding two (wiki: ships-and-naval
## § Home Fleet — "any naval move that docks at the capital resolves by merging").
func test_the_turn_folds_a_docked_rival_into_the_home_fleet() -> void:
	var rival: int = _merge_rival()
	var region: int = -1
	var seat: int = MapModel.NO_ID
	for index in _screen.play.world.region_count():
		var found: int = _screen.play.world.capital_province_of(index, rival)
		if found != MapModel.NO_ID:
			region = index
			seat = found
			break
	assert_gte(seat, 0, "the rival seats a capital on the chart")
	var roster: Array[FleetState] = MapPlayCourt.region_fleets(_screen.play, region)
	var home := FleetState.in_port(
		FleetRosters.next_id(roster), rival, seat, ["ship_90"], {"ship_90": "fluyte"}
	)
	var stray := FleetState.in_port(
		FleetRosters.next_id(roster) + 1, rival, seat, ["ship_91"], {"ship_91": "fluyte"}
	)
	roster.append(home)
	roster.append(stray)
	_screen.play.ship_layer.regions.set_region(region, roster)
	assert_eq(_squadrons_at(roster, rival, seat), 2)

	var joined: int = MapPlayHomeMerge.settle_seats(_screen.play)

	assert_gte(joined, 1, "the docked squadron joins the home fleet")
	var after: Array[FleetState] = MapPlayCourt.region_fleets(_screen.play, region)
	assert_eq(_squadrons_at(after, rival, seat), 1)
	assert_true(_hulls_at(after, rival, seat).has("ship_91"),
		"the hull keeps its instance id through the merge")
	assert_eq(MapPlayHomeMerge.settle_seats(_screen.play), 0, "the pass is idempotent")


## A docking move folds where it happens, not only at the next turn's pass: an
## AI planner that only moves hulls still leaves the seat holding one squadron
## (wiki: ships-and-naval § Home Fleet — "any naval move that docks at the
## capital resolves by merging").
func test_a_docking_move_folds_into_the_home_fleet_at_once() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var sea: FleetState = _moored_squadron_at_the_seat()
	var roster: Array[FleetState] = _screen.ship_layer.fleets
	var hulls_before: int = home.ship_count()
	var hulls: int = sea.ship_count()

	assert_true(bool(NavalMovement.apply_move(
		_screen.model, sea, FleetState.Location.IN_PORT, capital
	).get("ok", false)), "the squadron docks")

	var merged: Dictionary = MapPlayHomeMerge.fold(
		_screen.play, _screen.model, roster, sea
	)

	assert_eq(merged.get("fleet"), home, "the fold names the home fleet")
	assert_false(roster.has(sea), "the docked squadron is struck off the roster")
	assert_eq(home.ship_count(), hulls_before + hulls, "every hull keeps sailing")
	assert_eq(_squadrons_at(roster, MapScreen.PLAYER_FACTION, capital), 1,
		"one squadron in port at the seat")


## A fold that finds an army already aboard lands the docking squadron's army at
## the port: one squadron carries one army (wiki: ships-and-naval § Naval
## transport), so the struck-off squadron's soldier must not drown in the roster.
func test_a_fold_lands_the_army_it_cannot_keep_aboard() -> void:
	var capital: int = _screen.play.capital_province
	var play: PlaySession = _screen.play
	var home: FleetState = play.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var kept := ArmyState.muster(180, MapScreen.PLAYER_FACTION, capital, false, ["pikemen"], 1800)
	var surplus := ArmyState.muster(181, MapScreen.PLAYER_FACTION, capital, false, ["pikemen"], 1810)
	play.army_layer.armies.append(kept)
	play.army_layer.armies.append(surplus)
	home.embarked_army = kept.id
	kept.embarked_fleet = home.id
	var sea: FleetState = _moored_squadron_at_the_seat()
	sea.embarked_army = surplus.id
	surplus.embarked_fleet = sea.id
	surplus.province = MapModel.NO_ID

	NavalMovement.apply_move(_screen.model, sea, FleetState.Location.IN_PORT, capital)
	MapPlayHomeMerge.fold(play, _screen.model, play.ship_layer.fleets, sea)

	assert_eq(surplus.embarked_fleet, -1, "the surplus army goes ashore")
	assert_eq(surplus.province, capital, "it lands at the port")
	assert_eq(home.embarked_army, kept.id, "the home squadron keeps its own army")


## The army a merge keeps aboard rides the squadron that now holds her hulls: her
## id is stored on the squadron that carries her (wiki: ships-and-naval
## § Naval transport), so the court's book, the OOB and the invasion pass read a
## live seat instead of the squadron the merge struck off.
func test_a_fold_moves_a_kept_armys_seat_to_the_home_fleet() -> void:
	var capital: int = _screen.play.capital_province
	var play: PlaySession = _screen.play
	var home: FleetState = play.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	home.embarked_army = -1
	var carried := ArmyState.muster(
		182, MapScreen.PLAYER_FACTION, MapModel.NO_ID, false, ["pikemen"], 1820
	)
	play.army_layer.armies.append(carried)
	var sea: FleetState = _moored_squadron_at_the_seat()
	sea.embarked_army = carried.id
	carried.embarked_fleet = sea.id

	assert_true(bool(NavalMovement.apply_move(
		_screen.model, sea, FleetState.Location.IN_PORT, capital
	).get("ok", false)), "the squadron docks")
	MapPlayHomeMerge.fold(play, _screen.model, play.ship_layer.fleets, sea)

	assert_eq(home.embarked_army, carried.id, "the home squadron carries her now")
	assert_true(
		MapPlayForceLedger.focus(
			play, play.region_index, ForceLedger.KIND_ARMY, carried.id
		),
		"the book reaches a hull marker for the carried army"
	)
	assert_eq(
		play.ship_layer.fleet_of(play.ship_layer.selected()), home,
		"the book opens the squadron she rides, not the one struck off"
	)
	assert_eq(carried.embarked_fleet, home.id, "the army answers the squadron she rides")


## The one-tap join moves the seat the same way: the dossier button is the
## player's own merge, so a carried army must follow the hulls there too.
func test_joining_the_home_fleet_moves_a_kept_armys_seat() -> void:
	var capital: int = _screen.play.capital_province
	var play: PlaySession = _screen.play
	var home: FleetState = play.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	home.embarked_army = -1
	var carried := ArmyState.muster(
		183, MapScreen.PLAYER_FACTION, MapModel.NO_ID, false, ["pikemen"], 1830
	)
	play.army_layer.armies.append(carried)
	var stray: FleetState = _stray_at_the_seat()
	stray.embarked_army = carried.id
	carried.embarked_fleet = stray.id
	play.ship_layer.select(play.ship_layer.ship_for(stray))

	MapPlayHomeMerge.join(play)

	assert_false(play.ship_layer.fleets.has(stray), "the moored squadron is folded in")
	assert_eq(carried.embarked_fleet, home.id, "the army answers the home fleet")


## A missing play, chart or roster leaves the harbour alone (the headless pass
## must not crash when a harness tears the session down mid-turn).
func test_settle_seats_guards_a_missing_play() -> void:
	assert_eq(MapPlayHomeMerge.settle_seats(null), 0)
	var bare := PlaySession.new()
	assert_eq(MapPlayHomeMerge.settle_seats(bare), 0, "no ship layer yet")
	bare.ship_layer = ShipLayer.new()
	assert_eq(MapPlayHomeMerge.settle_seats(bare), 0, "no world yet")


## A torn-down army layer must not crash the merge's re-seat (REQ-P3-02
## headless turn close): the play-side wrapper returns before it asks the
## transport book to rewrite a seat.
func test_home_merge_seat_carried_guards_a_missing_army_layer() -> void:
	var home := FleetState.in_port(1, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	home.embarked_army = 7
	MapPlayHomeMerge._seat_carried(null, home)
	var bare := PlaySession.new()
	bare.army_layer = null
	MapPlayHomeMerge._seat_carried(bare, home)


## When two armies ride the merge, the surplus lands ashore (wiki: ships-and-naval
## § Home Fleet). put_ashore stays quiet when no HUD is mounted, so the same
## landing works headless.
func test_settle_seats_lands_a_displaced_army() -> void:
	var play: PlaySession = _screen.play
	var rival: int = _merge_rival()
	var region: int = -1
	var seat: int = MapModel.NO_ID
	for index in play.world.region_count():
		var found: int = play.world.capital_province_of(index, rival)
		if found != MapModel.NO_ID:
			region = index
			seat = found
			break
	assert_gte(seat, 0, "the rival seats a capital on the chart")
	var roster: Array[FleetState] = MapPlayCourt.region_fleets(play, region)
	var home := FleetState.in_port(
		FleetRosters.next_id(roster), rival, seat, ["ship_92"], {"ship_92": "fluyte"}
	)
	var stray := FleetState.in_port(
		FleetRosters.next_id(roster) + 1, rival, seat, ["ship_93"], {"ship_93": "fluyte"}
	)
	var kept := ArmyState.muster(190, rival, seat, false, ["pikemen"], 1900)
	var surplus := ArmyState.muster(191, rival, seat, false, ["pikemen"], 1910)
	play.army_layer.armies.append(kept)
	play.army_layer.armies.append(surplus)
	home.embarked_army = kept.id
	kept.embarked_fleet = 999
	stray.embarked_army = surplus.id
	surplus.embarked_fleet = stray.id
	roster.append(home)
	roster.append(stray)
	play.ship_layer.regions.set_region(region, roster)

	assert_gte(MapPlayHomeMerge.settle_seats(play), 1)
	assert_eq(surplus.embarked_fleet, -1, "the surplus army goes ashore")
	assert_eq(surplus.province, seat)
	assert_eq(
		kept.embarked_fleet, home.id,
		"the army the home squadron keeps rides it, not the seat it lost"
	)

	# The HUD-null path: same landing, no toast (REQ-P3-02 headless turn close).
	var quiet := PlaySession.new()
	quiet.army_layer = play.army_layer
	quiet.hud = null
	var second := ArmyState.muster(192, rival, seat, false, ["pikemen"], 1920)
	quiet.army_layer.armies.append(second)
	second.embarked_fleet = 1
	MapPlayPortLoss.put_ashore(quiet, second.id, seat)
	assert_eq(second.embarked_fleet, -1)
	assert_eq(second.province, seat)


## The first rival court in the catalog: the one the fixture's chart seats.
func _merge_rival() -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != MapScreen.PLAYER_FACTION:
			return faction
	return 1


func _squadrons_at(fleets: Array, owner: int, province: int) -> int:
	var count: int = 0
	for raw: Variant in fleets:
		var fleet: FleetState = raw as FleetState
		if fleet == null or fleet.owner != owner or not fleet.is_in_port():
			continue
		if fleet.province == province:
			count += 1
	return count


## Every hull id a court keeps in port at one province.
func _hulls_at(fleets: Array, owner: int, province: int) -> Array[String]:
	var hulls: Array[String] = []
	for raw: Variant in fleets:
		var fleet: FleetState = raw as FleetState
		if fleet == null or fleet.owner != owner or not fleet.is_in_port():
			continue
		if fleet.province != province:
			continue
		for hull_id: String in fleet.hulls:
			hulls.append(hull_id)
	return hulls


## A player squadron parked at the crown's seat *without* the merge: the
## transitional shape a save written before the merge has.
func _stray_at_the_seat() -> FleetState:
	var capital: int = _screen.play.capital_province
	var stray := FleetState.in_port(
		FleetRosters.next_id(_screen.ship_layer.fleets),
		MapScreen.PLAYER_FACTION,
		capital,
		["ship_90"],
		{"ship_90": "fluyte"}
	)
	_screen.ship_layer.fleets.append(stray)
	_screen.ship_layer.rebuild_markers()
	return stray


## A sea-going player squadron moved into the sea zone off the capital.
func _moored_squadron_at_the_seat() -> FleetState:
	var capital: int = _screen.play.capital_province
	var fleet: FleetState = Fixture.fleet_at_sea(
		_screen.ship_layer.fleets, MapScreen.PLAYER_FACTION
	)
	assert_not_null(fleet, "the fixture sails a player squadron")
	fleet.sea_zone = NavalMovement.province_sea_zones(_screen.model, capital)[0]
	fleet.province = MapModel.NO_ID
	fleet.location = FleetState.Location.AT_SEA
	return fleet


func _last_toast() -> String:
	var box: VBoxContainer = _screen.hud._toast_box
	assert_gt(box.get_child_count(), 0, "a report was raised")
	var plate: Control = box.get_child(box.get_child_count() - 1) as Control
	for child: Node in plate.get_children():
		if child is Label:
			return (child as Label).text
	return ""


# --- detaching a hull into a squadron of her own (DR-20261116-12) ------------


func test_a_hull_detaches_from_the_selected_squadron() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.add_hull("split_ship", "sloop")
	_screen.ship_layer.select(ship)
	var roster_before: int = _screen.ship_layer.fleets.size()
	var hulls_before: int = fleet.ship_count()
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	MapPlayFleets.on_action(_screen.play, "split:split_ship")

	assert_eq(_screen.ship_layer.fleets.size(), roster_before + 1, "a command of her own")
	assert_eq(fleet.ship_count(), hulls_before - 1, "the squadron keeps her other hulls")
	var split: FleetState = null
	for other: FleetState in _screen.ship_layer.fleets:
		if other != fleet and other.hulls.has("split_ship"):
			split = other
	assert_not_null(split, "the new squadron is on the roster")
	assert_eq(split.sea_zone, fleet.sea_zone, "she keeps her station")
	assert_not_null(_screen.ship_layer.ship_for(split), "she flies a marker of her own")
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)
	assert_true(
		_toast_texts().back().contains("as a squadron of her own"),
		"the news names the detach: '%s'" % _toast_texts().back()
	)
	assert_eq(
		_screen.ship_layer.fleet_of(_screen.ship_layer.selected()), fleet,
		"the player keeps the squadron she split in view"
	)


func test_the_dossier_offers_the_split_and_the_home_fleet_says_why_not() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.add_hull("split_ship", "sloop")

	_screen.ship_layer.select(ship)

	assert_true(_screen.hud._fleet_panel._split._button.visible, "the drawer is offered")

	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	home.add_hull("home_ship", "sloop")
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))

	assert_false(
		_screen.hud._fleet_panel._split._button.visible,
		"the home squadron keeps the seat"
	)
	assert_true(_screen.hud._fleet_panel._split._note.visible, "the reason is on the sheet")
	assert_true(_screen.hud._fleet_panel._split._note.text.contains("home squadron"))


func test_a_refused_detach_names_the_gate_and_moves_nothing() -> void:
	var ship: Ship = _player_ship_at_sea()
	_screen.ship_layer.select(ship)
	var roster_before: int = _screen.ship_layer.fleets.size()
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	MapPlayFleets.on_action(_screen.play, "split:not_aboard")

	assert_eq(_screen.ship_layer.fleets.size(), roster_before, "no command is founded")
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)
	assert_true(
		_toast_texts().back().contains("not aboard"),
		"the refusal names the hull: '%s'" % _toast_texts().back()
	)


func test_the_receipt_reads_a_hull_in_port_with_no_name() -> void:
	var fleet := FleetState.in_port(3, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})

	var line: String = MapPlayFleetSplit.line(
		_screen.play, fleet, {"name": "", "type": "fluyte"}
	)

	assert_true(line.begins_with("Fluyte detaches at "), line)
	assert_true(line.ends_with("as a squadron of her own."), line)


## A split repaints every marker, and a repainted marker must keep the chart's
## own reading: the closer chart prints the strength to one decimal and scales
## the silhouette in (wiki: ships-and-naval § Sighted strength, REQ-P1-07).
func test_a_split_keeps_the_charts_close_reading_on_every_marker() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.add_hull("split_ship", "sloop")
	_screen.ship_layer.set_zoom(1.4)
	var close_scale: float = clampf(1.0 / 1.4, 0.6, 1.0)
	_screen.ship_layer.select(ship)
	assert_true(_screen.ship_layer.ship_for(fleet).detail, "the close chart is reading")

	MapPlayFleets.on_action(_screen.play, "split:split_ship")

	assert_gt(_screen.ship_layer.fleets.size(), 1, "the split founded a command")
	for marker: Ship in _screen.ship_layer.ships:
		assert_true(marker.detail, "marker %d keeps the one-decimal reading" % marker.fleet_id)
		assert_almost_eq(marker.scale.x, close_scale, 0.001, "marker %d keeps the chart's scale" % marker.fleet_id)
	# A marker minted by the yard or a region mount reads the chart the same way.
	_screen.ship_layer.set_zoom(0.6)
	_screen.ship_layer.rebuild_markers()
	for marker: Ship in _screen.ship_layer.ships:
		assert_false(marker.detail, "fit zoom prints the whole number")
		assert_almost_eq(marker.scale.x, 1.0, 0.001, "fit zoom draws the full silhouette")


# --- combining two squadrons in one station (DR-20261116-13) -----------------


## A second sea-going squadron of the crown's in `zone`, on the roster and drawn.
func _partner_cmd(zone: int, hulls: Array[String]) -> FleetState:
	var types: Dictionary = {}
	for hull_id: String in hulls:
		types[hull_id] = "sloop"
	var partner: FleetState = FleetState.at_sea(
		FleetRosters.next_id(_screen.ship_layer.fleets),
		MapScreen.PLAYER_FACTION, zone, hulls, types
	)
	_screen.ship_layer.fleets.append(partner)
	_screen.ship_layer.rebuild_markers()
	return partner


func test_two_squadrons_in_one_zone_combine_into_the_one_that_keeps_the_station() -> void:
	var fleet: FleetState = _screen.ship_layer.fleet_of(_player_ship_at_sea())
	fleet.mission = FleetState.Mission.PATROL
	var partner: FleetState = _partner_cmd(fleet.sea_zone, ["partner_a", "partner_b"])
	partner.moved = true
	var partner_ship: Ship = _screen.ship_layer.ship_for(partner)
	var kept_name: String = String(partner.hull_names.get("partner_a", ""))
	var roster_before: int = _screen.ship_layer.fleets.size()
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	_screen.ship_layer.select(partner_ship)
	MapPlayFleets.on_action(_screen.play, "combine:%d" % fleet.id)

	assert_eq(_screen.ship_layer.fleets.size(), roster_before - 1, "one command leaves")
	assert_null(FleetRosters.find(_screen.ship_layer.fleets, partner.id), "the emptied command is retired")
	assert_eq(fleet.ship_count(), 3, "every hull joins the squadron that keeps the station")
	assert_eq(fleet.type_of("partner_a"), "sloop", "a hull keeps her catalog type")
	assert_false(kept_name.is_empty(), "the fixture christened the joining hull")
	assert_eq(String(fleet.hull_names.get("partner_a", "")), kept_name, "she keeps the name she flew")
	assert_null(_screen.ship_layer.ship_for(partner), "her marker is retired")
	assert_eq(fleet.mission, FleetState.Mission.PATROL, "the station stays with the squadron")
	assert_true(fleet.moved, "a hull that has sailed does not sail again")
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)
	assert_true(
		_toast_texts().back().contains("joins"),
		"the news names the combine: '%s'" % _toast_texts().back()
	)
	assert_eq(
		_screen.ship_layer.fleet_of(_screen.ship_layer.selected()), fleet,
		"the player keeps the squadron that keeps the station in view"
	)


## The army a combine keeps aboard rides the squadron that now holds her hulls.
## The emptied command leaves the roster, so a seat left on her names a squadron
## no chart holds: the muster roll loses the water she stands in and its own
## press finds no marker (wiki: military-armies § The muster roll — an embarked
## army stands under the squadron that carries it).
func test_a_combine_re_seats_the_army_it_carries() -> void:
	var fleet: FleetState = _screen.ship_layer.fleet_of(_player_ship_at_sea())
	var partner: FleetState = _partner_cmd(fleet.sea_zone, ["partner_a"])
	var army: ArmyState = ArmyState.muster(
		_screen.play.army_layer.next_army, MapScreen.PLAYER_FACTION,
		_screen.play.capital_province, false, ["infantry"],
		_screen.play.army_layer.next_regiment
	)
	_screen.play.army_layer.armies.append(army)
	army.province = MapModel.NO_ID
	army.embarked_fleet = partner.id
	partner.embarked_army = army.id

	_screen.ship_layer.select(_screen.ship_layer.ship_for(partner))
	MapPlayFleets.on_action(_screen.play, "combine:%d" % fleet.id)

	assert_eq(fleet.embarked_army, army.id, "the troops come aboard the kept squadron")
	assert_eq(army.embarked_fleet, fleet.id, "the army's seat follows her hulls")
	assert_true(
		MapPlayForceLedger.focus(
			_screen.play, _screen.play.region_index, ForceLedger.KIND_ARMY, army.id
		),
		"the muster roll's press finds the squadron that carries her"
	)


func test_the_dossier_offers_the_combine_only_beside_another_squadron() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)

	# A roster that holds only her offers nothing: no neighbour, no press.
	var alone: Array[FleetState] = [fleet]
	assert_true(
		FleetCombine.rows(_screen.model, alone, fleet).is_empty(),
		"alone in her water"
	)

	_screen.ship_layer.select(ship)
	var before: int = _screen.hud._fleet_panel._combine._rows.size()

	_partner_cmd(fleet.sea_zone, ["partner_a"])
	_screen.ship_layer.select(_screen.ship_layer.ship_for(fleet))

	assert_eq(
		_screen.hud._fleet_panel._combine._rows.size(), before + 1,
		"the squadron beside her is offered"
	)
	assert_true(_screen.hud._fleet_panel._combine._button.visible, "the drawer is offered")
	assert_true(_screen.hud._fleet_panel._combine._note.visible, "the rule is on the sheet")


func test_a_combine_refuses_two_armies_and_an_army_with_colonists() -> void:
	var fleet := FleetState.at_sea(21, 0, 7, ["a"], {"a": "sloop"})
	var target := FleetState.at_sea(22, 0, 7, ["b", "c"], {"b": "sloop", "c": "sloop"})
	fleet.embarked_army = 3
	target.embarked_army = 4
	assert_true(
		String(FleetCombine.can_combine(null, fleet, target)["reason"]).contains("armies"),
		"one army per squadron"
	)

	fleet.embarked_army = -1
	fleet.embarked_civilians = [8]
	assert_true(
		String(FleetCombine.can_combine(null, fleet, target)["reason"]).contains("colonists"),
		"a squadron carrying an army carries no colonists"
	)
	target.embarked_army = -1
	fleet.embarked_army = 3
	fleet.embarked_civilians = []
	target.embarked_civilians = [9]
	assert_true(
		String(FleetCombine.can_combine(null, fleet, target)["reason"]).contains("colonists"),
		"the gate reads both decks"
	)


func test_a_combine_refuses_the_home_fleet_a_beachhead_and_another_station() -> void:
	var home: FleetState = _screen.ship_layer.home_fleet(_screen.play.capital_province)
	assert_not_null(home, "the fixture founds a home fleet")
	var stray := FleetState.in_port(
		900, MapScreen.PLAYER_FACTION, home.province, ["stray"], {"stray": "sloop"}
	)
	assert_true(
		String(FleetCombine.can_combine(_screen.model, stray, home)["reason"]).contains("home fleet"),
		"the home fleet takes her joiners through Join the home fleet"
	)
	assert_true(
		String(FleetCombine.can_combine(_screen.model, home, stray)["reason"]).contains("home fleet"),
		"a home squadron does not fold into a sea-going one either"
	)

	var fleet := FleetState.at_sea(23, 0, 7, ["a"], {"a": "sloop"})
	var target := FleetState.at_sea(24, 0, 7, ["b"], {"b": "sloop"})
	fleet.beachhead_province = 5
	assert_true(
		String(FleetCombine.can_combine(null, fleet, target)["reason"]).contains("beachhead"),
		"a beachhead belongs to the squadron that holds it"
	)

	var elsewhere := FleetState.at_sea(25, 0, 8, ["c"], {"c": "sloop"})
	assert_true(
		String(FleetCombine.can_combine(null, target, elsewhere)["reason"]).contains("same sea zone"),
		"squadrons combine only in one station"
	)


func test_the_combine_receipt_names_both_flagships() -> void:
	var fleet: FleetState = _screen.ship_layer.fleet_of(_player_ship_at_sea())

	var line: String = MapPlayFleetCombine.line(
		_screen.play, fleet, {"name": "San Salvador", "into": "Trinidad"}
	)

	assert_true(line.begins_with("San Salvador joins Trinidad in the "), line)
	assert_true(
		line.ends_with("one squadron of %d." % fleet.ship_count()), line
	)


## The in-port wording of the receipt, and a combine the roster cannot find: the
## toast is the gate's own reason and nothing moves (REQ-P5-05).
func test_a_combine_with_no_squadron_beside_and_the_in_port_receipt() -> void:
	var fleet: FleetState = _screen.ship_layer.fleet_of(_player_ship_at_sea())
	var port := FleetState.in_port(910, 0, 3, ["c"], {"c": "sloop"})
	assert_true(
		MapPlayFleetCombine.line(_screen.play, port, {"name": "A", "into": "B"})
			.begins_with("A joins B at "),
		"a squadron in port is named by her province"
	)

	_screen.ship_layer.select(_screen.ship_layer.ship_for(fleet))
	var roster_before: int = _screen.ship_layer.fleets.size()
	MapPlayFleets.on_action(_screen.play, "combine:99999")

	assert_eq(_screen.ship_layer.fleets.size(), roster_before, "nothing moves")
	assert_true(
		_toast_texts().back().contains("Choose another"),
		"the refusal names the gate: '%s'" % _toast_texts().back()
	)


## The drawer opened: one press per squadron beside her, and the press folds the
## selected squadron into the one whose row it is (REQ-P5-04).
func test_the_combine_drawer_files_the_press() -> void:
	var fleet: FleetState = _screen.ship_layer.fleet_of(_player_ship_at_sea())
	var partner: FleetState = _partner_cmd(fleet.sea_zone, ["partner_a"])
	var fleet_hulls: Array[String] = []
	fleet_hulls.assign(fleet.hulls)
	_screen.ship_layer.select(_screen.ship_layer.ship_for(fleet))
	var block: FleetCombineBlock = _screen.hud._fleet_panel._combine

	block.set_open(true)

	assert_true(block.is_open(), "the drawer opens")
	var press: Button = _combine_press(block, partner.id)
	assert_not_null(press, "the partner carries her own press")
	press.pressed.emit()

	assert_null(
		FleetRosters.find(_screen.ship_layer.fleets, fleet.id),
		"the press folded the selected squadron in"
	)
	for hull_id: String in fleet_hulls:
		assert_true(
			partner.hulls.has(hull_id),
			"hull %s joined the squadron that keeps the station" % hull_id
		)
	assert_eq(
		_screen.ship_layer.fleet_of(_screen.ship_layer.selected()), partner,
		"the player keeps the squadron that keeps the station in view"
	)


## A neighbour the rules hold back keeps her row and prints why (REQ-P1-07).
func test_the_combine_drawer_names_a_held_back_neighbour() -> void:
	var fleet: FleetState = _screen.ship_layer.fleet_of(_player_ship_at_sea())
	fleet.embarked_civilians = [77]
	_partner_cmd(fleet.sea_zone, ["partner_a"])
	var carrying: FleetState = _partner_cmd(fleet.sea_zone, ["partner_b"])
	carrying.embarked_army = 5
	_screen.ship_layer.select(_screen.ship_layer.ship_for(fleet))
	var block: FleetCombineBlock = _screen.hud._fleet_panel._combine

	block.set_open(true)

	var held: Button = _combine_press(block, carrying.id)
	assert_not_null(held, "the held-back squadron keeps her row")
	assert_true(held.disabled, "her press is refused")
	assert_true(held.tooltip_text.contains("colonists"), held.tooltip_text)
	assert_true(block._button.visible, "a joinable neighbour keeps the drawer offered")


## The gates that never move a hull, read straight off the rules module.
func test_the_combine_gates_that_never_move_a_hull() -> void:
	var none: Array[FleetState] = []
	assert_true(FleetCombine.rows(null, none, null).is_empty(), "no squadron, no rows")

	var fleet := FleetState.at_sea(31, 0, 7, ["a"], {"a": "sloop"})
	var rival := FleetState.at_sea(32, 1, 7, ["b"], {"b": "sloop"})
	assert_true(
		String(FleetCombine.can_combine(null, null, fleet)["reason"]).contains("no squadron"),
		"a caller with no squadron"
	)
	assert_true(
		String(FleetCombine.can_combine(null, fleet, null)["reason"]).contains("Choose another"),
		"no target"
	)
	assert_true(
		String(FleetCombine.can_combine(null, fleet, fleet)["reason"]).contains("Choose another"),
		"herself"
	)
	assert_true(
		String(FleetCombine.can_combine(null, fleet, rival)["reason"]).contains("own squadrons"),
		"a rival's squadron never folds in"
	)
	var slip := FleetState.empty_in_port(33, 0, 3)
	var port := FleetState.in_port(34, 0, 3, ["c"], {"c": "sloop"})
	assert_true(
		String(FleetCombine.can_combine(null, slip, port)["reason"]).contains("slip with no hulls"),
		"an empty slip combines nothing"
	)
	assert_true(
		String(FleetCombine.can_combine(null, port, slip)["reason"]).contains("slip with no hulls"),
		"nor takes a hull aboard by combining"
	)
	assert_eq(FleetCombine.flagship(slip), "", "a slip flies no flagship")
	assert_false(FleetCombine.same_station(fleet, null), "no neighbour, no station")

	var roster: Array[FleetState] = [fleet, rival]
	var refused: Dictionary = FleetCombine.combine(null, roster, fleet, rival)
	assert_false(bool(refused["ok"]), "a refused combine moves nothing")
	assert_eq(roster.size(), 2, "both commands stay on the roster")
	assert_false(FleetCombine.flagship(null).length() > 0, "no squadron, no name")


## The press a row carries for `fleet_id`, or null when she has no row.
func _combine_press(block: FleetCombineBlock, fleet_id: int) -> Button:
	for entry: Node in block._box.get_children():
		for press: Button in entry.find_children("*", "Button", true, false):
			if int(press.get_meta("combine_id", -1)) == fleet_id:
				return press
	return null
