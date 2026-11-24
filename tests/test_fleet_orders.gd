# gdlint: disable=max-public-methods
extends GdToolsTest
## One boot for the sea: pure naval rules (yard, hulls, stations, strength,
## retreat, ports, interception, movement, raids) and the live map-screen fleet
## orders that drive them (wiki: ships-and-naval). Folded from test_naval_rules
## so coverage pays one Godot process instead of two (~40 s instrumentation).
## Kept separate from test_a_map_screen so each native suite stays inside the
## coverage runner's per-suite timeout.

const Fixture = preload("res://tests/map_fixture.gd")
const NavalFixture = preload("res://tests/naval_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so live cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`). Pure
## home-merge / combine-gate cases never touch `_screen`, so they skip the
## re-seat (docs/testing.md § Speed rules).
var mounted: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []
## Set when this case has paid for a pristine re-seat; cleared in `before_each`.
var _chart_bound: bool = false
## Naval-rules case setup tag (folded from test_naval_rules).
var _suite_setup: String = ""
## Hand-built two-coast chart for home-merge rules; built lazily so live cases
## never pay `NavalFixture.build()`.
var _naval: MapModel = null


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)
	Fixture.park_screen(mounted)


func before_each() -> void:
	_chart_bound = false
	_naval = null
	Fixture.park_screen(mounted)


func after_each() -> void:
	match _suite_setup:
		"fleet_rosters":
			_teardown_fleet_rosters()
	_suite_setup = ""


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	pristine = {}


## Live cases reach the chart through `_screen` / `_attach()`; pure FleetHomeMerge
## / combine-gate cases that never ask never pay `suite_reset`.
func _attach() -> MapScreen:
	if _chart_bound and is_instance_valid(mounted):
		return mounted
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine, Fixture.world())
	_chart_bound = true
	return mounted


var _screen: MapScreen:
	get:
		return _attach()


var _model: MapModel:
	get:
		if _naval == null:
			_naval = NavalFixture.build()
		return _naval


func test_selecting_a_player_fleet_opens_orders() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	assert_true(_screen.hud.panels.is_fleet_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())
	assert_eq(_screen.overlay.move_zones, NavalMovement.destination_zones(_screen.model, fleet))


## `count` of the crown's sea-going squadrons, all in the first one's water, in
## id order (wiki: ships-and-naval § Fleets in one station).
func _crown_squadrons_in_one_water(count: int) -> Array[FleetState]:
	var squadrons: Array[FleetState] = []
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			squadrons.append(fleet)
		if squadrons.size() == count:
			break
	while squadrons.size() < count:
		var extra: FleetState = _detach_sea_squadron()
		if extra == null:
			break
		squadrons.append(extra)
	assert_eq(squadrons.size(), count, "the fixture floats the squadrons this case needs")
	for fleet: FleetState in squadrons:
		fleet.sea_zone = squadrons[0].sea_zone
	_screen.ship_layer.rebuild_markers()
	return squadrons


## The crown's squadrons in one water fan out, and a tap picks the one under the
## finger instead of whichever marker happened to be drawn last
## (wiki: ships-and-naval § Fleets in one station; DR-20261119-08).
func test_a_tap_picks_the_fanned_squadron_under_the_finger() -> void:
	var pair: Array[FleetState] = _crown_squadrons_in_one_water(2)
	var first: Ship = _screen.ship_layer.ship_for(pair[0])
	var second: Ship = _screen.ship_layer.ship_for(pair[1])
	assert_ne(first.drawn_position(), second.drawn_position(), "each stands at her own step")

	MapPlayInput.on_tapped(_screen.play, first.drawn_position())
	assert_eq(_screen.ship_layer.selected(), first)
	MapPlayInput.on_tapped(_screen.play, second.drawn_position())
	assert_eq(_screen.ship_layer.selected(), second, "the other step picks the other squadron")
	assert_true(second.selected)
	assert_false(first.selected)


## A stacked station hands the crown one command at a time: a second tap on the
## head cycles the stack, and the squadron in hand draws the hull
## (wiki: ships-and-naval § Fleets in one station).
func test_a_second_tap_cycles_the_stack() -> void:
	var rivals: Array[FleetState] = []
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet.owner != MapScreen.PLAYER_FACTION:
			rivals.append(fleet)
		if rivals.size() == 2:
			break
	assert_eq(rivals.size(), 2, "the fixture floats two rival squadrons")
	var seat: int = rivals[0].province
	var zone: int = NavalMovement.province_sea_zones(_screen.model, seat)[0]
	for fleet: FleetState in rivals:
		fleet.location = FleetState.Location.AT_SEA
		fleet.province = MapModel.NO_ID
		fleet.sea_zone = zone
	_screen.ship_layer.rebuild_markers()
	for fleet: FleetState in rivals:
		_screen.ship_layer.ship_for(fleet).visible = true
	_screen.ship_layer.relayout()
	var head: Ship = _screen.ship_layer.ship_for(rivals[0])
	var behind: Ship = _screen.ship_layer.ship_for(rivals[1])
	assert_false(head.covered, "the first rival draws the stack")
	assert_true(behind.covered, "the second rides behind her")

	MapPlayInput.on_tapped(_screen.play, head.drawn_position())
	assert_eq(_screen.ship_layer.fleet_of(_screen.ship_layer.selected()), rivals[0])
	MapPlayInput.on_tapped(_screen.play, head.drawn_position())
	assert_eq(_screen.ship_layer.fleet_of(_screen.ship_layer.selected()), rivals[1],
		"the second tap reads the next squadron in the stack")
	assert_false(_screen.ship_layer.ship_for(rivals[1]).covered, "the squadron in hand draws")
	assert_true(_screen.ship_layer.ship_for(rivals[0]).covered)


## A squadron the row draws hears where she stands in the water, not where she
## stands in a stack she never joined: a crowded station's words count every
## hull the chart draws there (wiki: ships-and-naval § Fleets in one station;
## REQ-P5-05).
func test_a_fanned_squadron_hears_her_place_in_the_station() -> void:
	var pair: Array[FleetState] = _crown_squadrons_in_one_water(2)
	var first: Ship = _screen.ship_layer.ship_for(pair[0])
	assert_true(first.stack.is_empty(), "the row rides no stack")
	_screen.ship_layer.select(first)
	var line: String = MapPlayFleets.selection_line(_screen.play, first, pair[0])
	assert_eq(line, "%d of %d squadrons here — %s" % [
		first.station.find(pair[0].id) + 1, first.station.size(),
		FleetCombine.flagship(pair[0]),
	], "the row's own place is read")


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
	var toasts_before: int = _screen.hud.despatches.box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[next_zone].tiles[0]))

	assert_eq(fleet.sea_zone, zone_after_move)
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts_before + 1)


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
	var toasts_before: int = _screen.hud.despatches.box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zone_data(zone).tiles[0]))

	assert_eq(home.location, FleetState.Location.IN_PORT)
	assert_eq(home.province, capital)
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts_before + 1)


func test_docking_at_the_capital_joins_the_home_fleet() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var sea: FleetState = _sea_squadron()
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

	# Moved clears on the ship begin-turn pass; a full end_turn would also run
	# every rival court under coverage (~10 s) for the same assert
	# (docs/testing.md § Speed rules: one resolved turn / pure path first).
	ShipTurnPass.begin_turn(_screen.ship_layer)
	MapPlayFleets.refresh_options(_screen.play, fleet)

	assert_false(fleet.moved)
	assert_gt(_screen.overlay.move_zones.size(), 0)


## Unknown remotes stay blank, a distant sighting fogging, and owned coasts
## clearing — three fog outcomes, one fog pass under coverage (docs/testing.md
## § Speed rules: one resolved turn per suite when cases share the pass).
func test_end_turn_fog_keeps_unknown_refogs_distant_and_opens_owned_coasts() -> void:
	var occupied: Array[int] = _screen.ship_layer.at_sea_zones(MapScreen.PLAYER_FACTION)
	var remotes: Array[int] = []
	var coasts: Array[int] = []
	for zone: SeaZoneState in _screen.model.sea_zones:
		var zone_id: int = int(zone.id)
		if _screen.visibility.owns_coast(zone_id):
			coasts.append(zone_id)
			continue
		if occupied.has(zone_id):
			continue
		remotes.append(zone_id)
	assert_true(remotes.size() >= 2, "need two remotes for unknown vs known")
	assert_gt(coasts.size(), 0)

	var unknown: Vector2i = _screen.model.sea_zones[remotes[0]].tiles[0]
	var known: Vector2i = _screen.model.sea_zones[remotes[1]].tiles[0]
	var coast: Vector2i = _screen.model.sea_zones[coasts[0]].tiles[0]
	var unknown_i: int = _screen.model.index_of(unknown.x, unknown.y)
	var known_i: int = _screen.model.index_of(known.x, known.y)
	var coast_i: int = _screen.model.index_of(coast.x, coast.y)

	_screen.visibility.lower_to(unknown_i, VisibilityModel.Level.UNKNOWN)
	_screen.visibility.raise_to(known_i, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.visibility.lower_to(coast_i, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [unknown_i, known_i, coast_i])

	# Fog decay alone; skip the full end_turn rival walk under coverage.
	MapPlayFogTurn.resolve(_screen.play)

	assert_eq(_screen.visibility.level_at(unknown.x, unknown.y), VisibilityModel.Level.UNKNOWN)
	assert_eq(_screen.overlay.fog_state_at(unknown.x, unknown.y), MapOverlay.FOG_UNKNOWN)
	assert_eq(_screen.visibility.level_at(known.x, known.y), VisibilityModel.Level.FOGGED)
	assert_eq(_screen.overlay.fog_state_at(known.x, known.y), MapOverlay.FOG_FOGGED)
	assert_eq(
		_screen.visibility.level_at(coast.x, coast.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	assert_eq(_screen.overlay.fog_state_at(coast.x, coast.y), MapOverlay.FOG_VISIBLE)


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
	var toasts_before: int = _screen.hud.despatches.box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _passage_tile(zone_after)))

	assert_eq(fleet.sea_zone, zone_after)
	assert_eq(_screen.region_index, region_after)
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts_before + 1)


func test_a_crossed_fleet_sails_back_on_a_later_turn() -> void:
	var fleet: FleetState = _cross_to_new_world()

	# Crossing spends the move; begin-turn restores it without a rival AI walk.
	ShipTurnPass.begin_turn(_screen.ship_layer)
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
	# Loss pass only — no battle, no rival plan under coverage.
	MapPlayNavalTurn.resolve(_screen.play)

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
	# Loss pass only — the merge already seated the passenger.
	MapPlayNavalTurn.resolve(_screen.play)
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
	var moored: FleetState = _sea_squadron()
	assert_not_null(moored, "the muster has a second player squadron")
	assert_ne(moored, home, "the sea command is not the home fleet")
	moored.location = FleetState.Location.IN_PORT
	moored.province = seat
	moored.sea_zone = MapModel.NO_ID
	moored.moved = false
	# The command already moored at the new seat is the older one there, so it
	# keeps the home role and the old home fleet folds into her.
	home.id = FleetRosters.next_id(_screen.ship_layer.fleets)
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
	var fleet: FleetState = _sea_squadron()
	if fleet == null:
		return _screen.ship_layer.ships[0] if not _screen.ship_layer.ships.is_empty() else null
	return _screen.ship_layer.ship_for(fleet)


## A sea-going player squadron, mustered out of the home fleet when the opening
## muster left every hull at home (issue #1043). Cases that need a second player
## command call this, so each still gets one without restaging the whole chart.
func _sea_squadron() -> FleetState:
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet != null and fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			return fleet
	var detached: FleetState = _detach_sea_squadron()
	if detached != null:
		return detached
	return _screen.ship_layer.home_fleet(_screen.play.capital_province)


## Detaches one of the home squadron's hulls into a sea-going command of her own
## in the water off the seat, or null when the home fleet has no hull to spare.
func _detach_sea_squadron() -> FleetState:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	var zones: Array[int] = NavalMovement.province_sea_zones(_screen.model, capital)
	if home == null or home.ship_count() < 2 or zones.is_empty():
		return null
	var hull_id: String = home.hulls[0]
	var type_id: String = home.type_of(hull_id)
	var hull_name: String = String(home.hull_names.get(hull_id, ""))
	home.remove_hull(hull_id)
	var squadron: FleetState = FleetState.at_sea(
		FleetRosters.next_id(_screen.ship_layer.fleets),
		MapScreen.PLAYER_FACTION,
		zones[0],
		[hull_id],
		{hull_id: type_id}
	)
	if not hull_name.is_empty():
		squadron.hull_names[hull_id] = hull_name
	_screen.ship_layer.fleets.append(squadron)
	_screen.ship_layer.regions.set_region(_screen.region_index, _screen.ship_layer.fleets)
	_screen.ship_layer.rebuild_markers()
	return squadron


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
	var toasts: int = _screen.hud.despatches.box.get_child_count()
	MapPlayBeachhead.establish(_screen.play, fleet, coast)
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts + 1)


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
	## The published example is pinned as a literal, not composed from the live
	## formula: ships-and-naval § Ship muster and the break-up yard prints the
	## carrack's line in full, so a changed weight, stat or hold count has to
	## surface here — and in the page — rather than drift apart silently.
	assert_eq(
		String(FleetYard.hull_line("carrack")),
		(
			"FRP 2 · RNG 1 · ARM 1 · HULL 2 · MV 2 · 2.8 strength"
			+ " · 3 holds for the world market"
		),
		"the carrack's published line, figure for figure"
	)


## A hull the crown already flies may be replaced without her study: the yard
## reads the court's own craft, the same list a rival court's yard reads, so the
## opening muster's Fluyte is never locked behind a tech the crown never needed
## to sail her (issue #484; REQ-P2-03).
func test_the_yard_rebuilds_a_hull_the_crown_already_flies() -> void:
	var play: PlaySession = _screen.play
	var econ: PlayerEconomy = play.economy.economy
	econ.tech_unlocked.clear()
	econ.treasury = 60000
	for commodity: String in ["lumber", "fabric", "castIron", "coal"]:
		econ.stockpile[commodity] = 20
	econ.workers.set_count(WorkerPool.Tier.PEASANT, 20)
	var home: FleetState = _screen.ship_layer.home_fleet(play.capital_province)
	assert_not_null(home, "the fixture moors a home fleet")
	var flown: Array[String] = MapPlayFleetYard.flown(play)
	var gated: String = ""
	for type_id: String in flown:
		if not ShipEconomy.tech_for(type_id).is_empty():
			gated = type_id
			break
	assert_false(gated.is_empty(), "the crown flies a hull her studies have not opened")
	var by_type: Dictionary = {}
	for row: Dictionary in MapPlayFleetYard.rows(play, home):
		by_type[String(row["type_id"])] = row
	assert_true(
		bool((by_type[gated] as Dictionary)["ok"]),
		"%s is the crown's own craft and stays on the slip" % gated
	)

	var hulls: int = _screen.ship_layer.hull_count_all(play.player_faction)
	MapPlayFleetYard.launch(play, gated)
	assert_eq(econ.recruits.pending(RecruitQueue.KIND_SHIP, gated), 1, "the order is filed")
	MapPlayRecruits.complete(play)
	assert_eq(
		_screen.ship_layer.hull_count_all(play.player_faction), hulls + 1,
		"she lands at Build/work without her study"
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
	_lose_the_capital(play)
	assert_eq(int(MapPlayCourt.crown_seat(play)["province"]), -1, "the seat is gone")
	var toasts: int = _screen.hud.despatches.box.get_child_count()

	MapPlayFleetYard.open(play)
	MapPlayFleetYard.launch(play, "carrack")

	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts + 2, "both say why")
	assert_false(_screen.hud.panels.is_fleet_panel_open())


## An inland capital cannot build hulls; the court is told before it pays.
func test_the_yard_needs_a_harbour() -> void:
	var play: PlaySession = _screen.play
	var inland: int = _inland_owned_province()
	assert_gte(inland, 0, "the fixture has an inland province")
	_move_the_seat(play, inland)
	var toasts: int = _screen.hud.despatches.box.get_child_count()

	MapPlayFleetYard.open(play)
	MapPlayFleetYard.launch(play, "carrack")

	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts + 2, "both say why")
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
	var toasts: int = _screen.hud.despatches.box.get_child_count()

	MapPlayFleetYard.launch(play, "carrack")

	assert_eq(_screen.ship_layer.hull_count_all(play.player_faction), hulls)
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts + 1, "the refusal is spoken")


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
	# Two regiments aboard need both hulls: give the squadron exactly two so the
	# break-up would leave nobody to carry them.
	fleet.set_hulls(["loaded_a", "loaded_b"], {"loaded_a": "carrack", "loaded_b": "carrack"})
	var hulls: Array[String] = fleet.hulls.duplicate()
	var toasts: int = _screen.hud.despatches.box.get_child_count()

	MapPlayFleetYard.scrap(play, fleet.hulls[0])

	assert_eq(fleet.hulls, hulls, "the hull stays afloat")
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts + 1, "the refusal is spoken")


## A hull the ledger cannot find is refused rather than silently dropped.
func test_breaking_up_an_unknown_hull_says_why() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	play.selected_province = capital
	play.economy.economy.treasury = 60000
	MapPlayFleetYard.launch(play, "carrack")
	var toasts: int = _screen.hud.despatches.box.get_child_count()

	MapPlayFleetYard.scrap(play, "no_such_hull")

	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts + 1, "the refusal is spoken")


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
	var home_carracks: int = 0
	var seat_home: FleetState = _screen.ship_layer.home_fleet(capital)
	if seat_home != null:
		home_carracks = seat_home.count_of_type("carrack")
	var hulls: int = _screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION)

	MapPlayFleets.on_action(_screen.play, "yard:build:carrack")

	assert_eq(_screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION), hulls, "no hull yet")
	assert_eq(econ.treasury, treasury, "nothing is paid at the press")
	assert_eq(econ.available_peasants(), peasants - 1, "her peasant is reserved")
	assert_eq(econ.recruits.pending(RecruitQueue.KIND_SHIP, "carrack"), 1)

	MapPlayRecruits.complete(_screen.play)

	var fleet: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(fleet, "the launch founds or joins the home fleet")
	assert_eq(fleet.count_of_type("carrack"), home_carracks + 1)
	assert_eq(_screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION), hulls + 1)
	assert_eq(econ.treasury, treasury - ShipEconomy.treasury_cost("carrack"))
	assert_eq(econ.available_peasants(), peasants - 1, "the reservation became the muster")


## The slip's one press lays down a hull for every ready type, Build/work musters
## them all and the press stands down while they wait, so a second press cannot
## double the line (REQ-P5-04, REQ-P5-05; DR-20261118-08).
func test_the_shipyard_lays_down_every_ready_hull_in_one_press() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	play.selected_province = capital
	var econ: PlayerEconomy = play.economy.economy
	econ.treasury = 60000
	for commodity: String in ["lumber", "fabric", "castIron", "coal"]:
		econ.stockpile[commodity] = 40
	econ.workers.set_count(WorkerPool.Tier.PEASANT, 12)
	econ.tech_unlocked["superior_hull_design"] = true
	var hulls: int = _screen.ship_layer.hull_count_all(play.player_faction)
	var ready: Array[String] = FleetYard.batch_types(econ, true, MapPlayFleetYard.flown(play))
	assert_gte(ready.size(), 2, "the slip offers more than one payable hull")

	MapPlayFleetYard.open(play)
	var yard: FleetYardBlock = _screen.hud.panels.fleet_panel._yard
	var press: RaiseBatchPress = yard._batch
	assert_not_null(press, "the slip carries the one press")
	assert_eq(press.text, "Launch all ready (%d)" % ready.size(), "the face names the line")

	press.pressed.emit()
	press.pressed.emit()

	assert_eq(
		econ.recruits.pending_kind(RecruitQueue.KIND_SHIP),
		ready.size(),
		"one order per ready hull"
	)
	assert_true(
		_last_toast().contains("%d hulls are laid down" % ready.size()),
		_last_toast()
	)
	assert_false(press.visible, "every hull waits on her order, so the press stands down")

	MapPlayRecruits.complete(play)

	assert_eq(
		_screen.ship_layer.hull_count_all(play.player_faction),
		hulls + ready.size(),
		"the whole slip launches at Build/work"
	)
	MapPlayFleetYard.open(play)
	assert_true(press.visible, "a paid-off slip offers the next batch")


## The slip with no squadron afloat re-reads its own ledger after a launch: the
## redrawn rows print the orders the press filed and the press stands down, where
## it once kept promising hulls the recruit queue already claimed (REQ-P5-04,
## REQ-P5-05; DR-20261118-08).
func test_the_slip_redraws_after_its_one_press() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	var econ: PlayerEconomy = play.economy.economy
	econ.treasury = 60000
	for commodity: String in ["lumber", "fabric", "castIron", "coal"]:
		econ.stockpile[commodity] = 40
	econ.workers.set_count(WorkerPool.Tier.PEASANT, 12)
	econ.tech_unlocked["superior_hull_design"] = true
	# A squadron away from her port: the capital's slip stands alone.
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture moors a home fleet")
	home.location = FleetState.Location.AT_SEA
	play.selected_province = capital
	var ready: Array[String] = FleetYard.batch_types(
		econ, true, MapPlayFleetYard.flown(play)
	)
	assert_gte(ready.size(), 2, "the slip offers more than one payable hull")
	var pending: int = econ.recruits.pending_kind(RecruitQueue.KIND_SHIP)

	MapPlayFleetYard.open(play)
	var yard: FleetYardBlock = _screen.hud.panels.fleet_panel._yard
	var press: RaiseBatchPress = yard._batch
	assert_eq(press.text, "Launch all ready (%d)" % ready.size(), "the slip names its line")

	press.pressed.emit()
	press.pressed.emit()

	var claimed: int = 0
	for row: Dictionary in yard._rows:
		claimed += int(row["pending"])
		assert_false(bool(row["batch_ready"]), "%s waits on her order" % row["type_id"])
	assert_eq(claimed, econ.recruits.pending_kind(RecruitQueue.KIND_SHIP),
		"the redrawn slip prints every order it holds")
	assert_eq(
		econ.recruits.pending_kind(RecruitQueue.KIND_SHIP), pending + ready.size(),
		"one order per ready hull"
	)
	assert_eq(press.text, "Launch all ready (0)", "the face names an empty slip")
	assert_false(press.visible, "the press stands down once her line waits on orders")

	# The press the slip no longer offers files nothing more.
	press.pressed.emit()
	press.pressed.emit()
	assert_eq(
		econ.recruits.pending_kind(RecruitQueue.KIND_SHIP), pending + ready.size(),
		"a slip with nothing ready files nothing"
	)


## The slip's one press names the line it will file, not the view it stands in: a
## purse that pays the slip's first hull and not its second reads
## `Confirm — launch 1 of N hulls` under a sum line that says which hulls wait
## (REQ-P5-05, REQ-P2-03; DR-20261118-21).
func test_the_shipyard_confirm_names_the_line_the_purse_carries() -> void:
	var play: PlaySession = _screen.play
	play.selected_province = play.capital_province
	var econ: PlayerEconomy = play.economy.economy
	for commodity: String in ["lumber", "fabric", "castIron", "coal"]:
		econ.stockpile[commodity] = 40
	econ.workers.set_count(WorkerPool.Tier.PEASANT, 12)
	econ.tech_unlocked["superior_hull_design"] = true
	econ.treasury = 100000
	var ready: Array[String] = FleetYard.batch_types(
		econ, true, MapPlayFleetYard.flown(play)
	)
	assert_gte(ready.size(), 2, "the slip offers more than one payable hull")

	MapPlayFleetYard.open(play)
	var yard: FleetYardBlock = _screen.hud.panels.fleet_panel._yard
	var press: RaiseBatchPress = yard._batch
	# The slip's own first ready row, read at a purse that pays for anything: the
	# walk then pays that one and stops at the next, because every hull costs
	# something. Each row stays ready on its own at that purse — each is legal —
	# so the view's count and the line's count part company on the sum alone.
	var first: String = ""
	for row: Dictionary in yard._rows:
		if bool(row.get("batch_ready", false)):
			first = String(row["type_id"])
			break
	assert_false(first.is_empty(), "the slip prints a ready row")
	econ.treasury = ShipEconomy.treasury_cost(first)
	MapPlayFleetYard.open(play)

	assert_eq(press.text, "Launch all ready (%d)" % ready.size(), "the face names the view")
	assert_eq(press.carries(), 1, "the line carries the slip's first hull and no more")
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap only arms")
	assert_eq(
		press.text,
		"Confirm — launch 1 of %d hulls" % ready.size(),
		"the confirm names what the purse carries"
	)
	press.pressed.emit()
	assert_eq(
		econ.recruits.pending_kind(RecruitQueue.KIND_SHIP), 1,
		"and the tap files exactly the one the face named"
	)


## The batch speaks the same refusals a single launch does, before anything is
## filed: a lost capital and an inland one both lay down no hull (REQ-P2-03;
## DR-20261118-08).
func test_the_yard_batch_refuses_a_capital_it_cannot_launch_from() -> void:
	var play: PlaySession = _screen.play
	var econ: PlayerEconomy = play.economy.economy
	econ.treasury = 60000
	econ.tech_unlocked["superior_hull_design"] = true
	var pending: int = econ.recruits.pending_kind(RecruitQueue.KIND_SHIP)
	_lose_the_capital(play)
	var toasts: int = _screen.hud.despatches.box.get_child_count()

	MapPlayFleetYard.on_action(play, "yard:launch_all")

	assert_eq(econ.recruits.pending_kind(RecruitQueue.KIND_SHIP), pending, "nothing is filed")
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts + 1, "the refusal is spoken")

	var inland: int = _inland_owned_province()
	assert_gte(inland, 0, "the fixture has an inland province")
	_move_the_seat(play, inland)
	MapPlayFleetYard.launch_all(play)

	assert_eq(econ.recruits.pending_kind(RecruitQueue.KIND_SHIP), pending, "no yard inland")


## The slip names what its whole line costs before it is pressed: the walk's own
## sum and the purse it leaves under the press, and the same sum on the confirm
## face — the opening press used to spend 19,500 of 20,000 ducats unseen
## (REQ-P5-06, REQ-P1-07; DR-20261118-11).
func test_the_slip_names_the_whole_line_before_it_is_pressed() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	play.selected_province = capital
	var econ: PlayerEconomy = play.economy.economy
	econ.treasury = 20000
	for commodity: String in ["lumber", "fabric", "castIron", "coal"]:
		econ.stockpile[commodity] = 40
	econ.workers.set_count(WorkerPool.Tier.PEASANT, 12)
	econ.tech_unlocked["superior_hull_design"] = true
	var craft: Array[String] = MapPlayFleetYard.flown(play)
	var ready: Array[String] = FleetYard.batch_types(econ, true, craft)
	assert_gte(ready.size(), 2, "the slip offers more than one payable hull")

	MapPlayFleetYard.open(play)
	var yard: FleetYardBlock = _screen.hud.panels.fleet_panel._yard
	var press: RaiseBatchPress = yard._batch
	var plan: Dictionary = FleetYard.batch_plan(econ, true, craft)
	var spent: int = int(plan["ducats"])
	assert_eq(spent, _sum_of_prices(ready), "the sum is the ready rows' own prices")
	assert_lt(spent, 20000, "the opening line leaves the purse something")

	# The sheet prints the reading, not a second copy of the arithmetic: the
	# opening line is the one the playtest named (19,500 of the crown's 20,000).
	var caption: String = _sum_label(yard)
	assert_eq(
		caption,
		"19,500 ducats · 4 Lumber · 3 Fabric · 3 workers — the purse keeps 500 of 20,000.",
		"the slip names the line and the purse it leaves"
	)
	assert_eq(caption, RaiseBatchSum.sheet_line(plan), "the sheet prints the plan")

	press.pressed.emit()
	press.pressed.emit()
	assert_true(
		_last_toast().contains(MoneyText.ducats(spent)),
		"the receipt names what it paid: %s" % _last_toast()
	)
	assert_true(_last_toast().contains("%d hulls are laid down" % ready.size()), _last_toast())


## A line the purse cannot carry says so before the press: the walk stops where
## the rules stop and the sheet names how many of the ready hulls wait, and why
## (REQ-P5-06; DR-20261118-11).
func test_the_slip_names_the_hulls_a_short_purse_leaves_waiting() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	play.selected_province = capital
	var econ: PlayerEconomy = play.economy.economy
	for commodity: String in ["lumber", "fabric", "castIron", "coal"]:
		econ.stockpile[commodity] = 40
	econ.workers.set_count(WorkerPool.Tier.PEASANT, 12)
	econ.tech_unlocked["superior_hull_design"] = true
	var craft: Array[String] = MapPlayFleetYard.flown(play)
	var offered: Array[String] = FleetYard.batch_types(econ, true, craft)
	assert_gte(offered.size(), 2, "the slip offers more than one payable hull")
	# The purse pays the first hull of the yard's order and nothing after it.
	econ.treasury = ShipEconomy.treasury_cost(offered[0])
	assert_gte(offered.size(), 2, "the second hull is beyond the purse")

	MapPlayFleetYard.open(play)
	var yard: FleetYardBlock = _screen.hud.panels.fleet_panel._yard
	var plan: Dictionary = FleetYard.batch_plan(econ, true, craft)
	assert_eq(int(plan["filed"]), 1, "the walk stops where the purse does")
	assert_false(String(plan["refusal"]).is_empty(), "the rule's own refusal is read")

	var line: String = _sum_label(yard)
	assert_true(line.contains("of %d wait" % int(plan["count"])), line)
	assert_true(line.contains(String(plan["refusal"])), line)
	assert_true(line.contains(MoneyText.ducats(int(plan["ducats"]))), line)


## The sum of the ready rows' own prices, read the way the yard reads them.
func _sum_of_prices(types: Array[String]) -> int:
	var total: int = 0
	for type_id: String in types:
		total += ShipEconomy.treasury_cost(type_id)
	return total


## The one sum line the slip prints under its launch rows, "" when it prints none.
## A row's own price line also names ducats, so the sum is read by the words only
## it carries: the purse it leaves, or the hulls that wait.
func _sum_label(yard: FleetYardBlock) -> String:
	for child: Node in yard._box.get_children():
		var label := child as Label
		if label == null or not label.visible:
			continue
		if label.text.contains("the purse keeps") or label.text.contains(" wait"):
			return label.text
	return ""


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

	assert_eq(panel._yard._arm.key(), hull_id, "the first tap only arms")
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
	var moved: Array[Dictionary] = ShipTurnPass.settle_port_losses(
		_screen.ship_layer,
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

	var reports: Array[Dictionary] = ShipTurnPass.settle_port_losses(
		_screen.ship_layer, _screen.world, []
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

	var reports: Array[Dictionary] = ShipTurnPass.settle_port_losses(
		_screen.ship_layer,
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


## A landing is a tile: the dossier groups the legal grounds by coast and the
## crown's press puts the crew on the one it named, not the first the rules read
## (wiki: civilian-units § Landing, § Acceptance Criteria; DR-20261118-19).
func test_the_crew_lands_on_the_ground_the_crown_names() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var unit: CivilianState = _screen.civilian_layer.units[0]
	unit.tile = _screen.model.province_tiles(capital)[0]
	unit.moved = false
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))
	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:%d" % unit.id)
	assert_true(unit.is_embarked())

	var coast: Dictionary = {}
	for raw: Variant in MapPlayCivilianVoyage.crew(_screen.play, home)["land"]:
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == capital:
			coast = row
			break
	assert_false(coast.is_empty(), "the capital coast is offered")
	var legal: Array[Vector2i] = CivilianVoyage.landing_tiles_in(
		_screen.model, unit, home, capital
	)
	var grounds: Array = coast.get("tiles", [])
	assert_eq(grounds.size(), legal.size(), "every legal ground is on the row")
	assert_gte(legal.size(), 2, "the capital coast holds more than one ground")
	assert_eq(
		Vector2i(int(grounds[0]["x"]), int(grounds[0]["y"])),
		legal[0],
		"the row reads the rules' own order"
	)

	var chosen: Vector2i = legal[legal.size() - 1]
	assert_ne(chosen, legal[0], "a ground other than the first one read")
	MapPlayCivilianVoyage.on_action(
		_screen.play, "crew:land:%d:%d" % [chosen.x, chosen.y]
	)

	assert_false(unit.is_embarked())
	assert_eq(unit.tile, chosen, "the crown's ground, not the first on the coast")
	assert_true(_screen.civilian_layer.marker_for(unit).visible)


## The block's one press takes every idle crew the hulls hold in one signed line,
## and a berth that fills stops the walk where the rules refuse — naming the crew
## that waits and why (wiki: civilian-units § Boarding; DR-20261119-18).
func test_the_one_press_takes_every_crew_the_hulls_hold() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var tile: Vector2i = _screen.model.province_tiles(capital)[0]
	var idle: Array[CivilianState] = []
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit.owner != _screen.play.player_faction:
			continue
		if unit.is_embarked() or unit.is_working():
			continue
		unit.tile = tile
		unit.moved = false
		idle.append(unit)
	assert_gte(idle.size(), 2, "the fixture holds two idle crews")
	for index in idle.size() - home.ship_count():
		home.add_hull("press_hull_%d" % index)
	assert_gte(
		CivilianVoyage.capacity(home) - home.civilian_count(), idle.size(),
		"the squadron has a berth for every crew"
	)
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))

	var plan: Dictionary = MapPlayCivilianVoyage.crew(_screen.play, home)["embark_batch"]
	assert_eq(int(plan["count"]), idle.size(), "the press counts every row it prints")
	assert_eq(int(plan["filed"]), idle.size(), "every berth is free, so the walk carries all")
	assert_eq(String(plan["refusal"]), "", "nothing waits")
	assert_eq(int(plan["workers"]), 0, "a boarding spends no peasant")
	assert_eq(int(plan["ducats"]), 0, "a boarding spends no purse")

	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:all")
	for unit: CivilianState in idle:
		assert_true(unit.is_embarked(), "one press boards every crew it printed")
		assert_false(_screen.civilian_layer.marker_for(unit).visible, "aboard leaves the map")
	assert_eq(
		MapPlayCivilianVoyage.crew(_screen.play, home)["embark"].size(), 0,
		"the rows are spent"
	)
	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:all")
	assert_eq(
		MapPlayCivilianVoyage.crew(_screen.play, home)["embark_batch"].get("count", 0), 0,
		"a second press has nothing to file"
	)


## A berth short of the crews the block prints stops the walk at the hulls: the
## kingdom confirms the count the rules accept, the rest wait beside the sentence
## the single press would have answered with, and the receipt names it
## (wiki: civilian-units § Boarding; DR-20261119-18).
func test_the_one_press_stops_at_the_berths_the_hulls_hold() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var tile: Vector2i = _screen.model.province_tiles(capital)[0]
	var idle: Array[CivilianState] = []
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit.owner != _screen.play.player_faction or unit.is_embarked() or unit.is_working():
			continue
		unit.tile = tile
		unit.moved = false
		idle.append(unit)
	assert_gte(idle.size(), 2, "the fixture holds two idle crews")
	while home.ship_count() > 1:
		home.remove_hull(String(home.hulls[home.hulls.size() - 1]))
	home.embarked_civilians.clear()
	assert_eq(CivilianVoyage.capacity(home), 1, "one hull, one berth")

	var plan: Dictionary = EmbarkBatch.plan(_screen.model, idle, home)
	assert_eq(int(plan["count"]), idle.size(), "the press counts every row it prints")
	assert_eq(int(plan["filed"]), 1, "the berth carries one crew")
	assert_eq(
		String(plan["refusal"]), "The squadron has 1 hull and cannot carry another civilian.",
		"the walk stops on the berth in the rules' own words"
	)
	assert_eq(
		EmbarkBatch.wait_line(plan),
		"%d of %d wait: The squadron has 1 hull and cannot carry another civilian."
		% [idle.size() - 1, idle.size()],
		"the line under the press names the wait"
	)
	assert_eq(
		EmbarkBatch.receipt(plan, "Madrid"),
		"1 crew is taken aboard at Madrid — the next waits: "
		+ "The squadron has 1 hull and cannot carry another civilian.",
		"the receipt names the crew that waits"
	)
	# A press with no squadron and nothing to read keeps the shape a sheet guards
	# on: no count, no wait, and one sentence for a tap that files nothing.
	var blank: Dictionary = EmbarkBatch.plan(_screen.model, [], null)
	assert_eq(int(blank["count"]), 0, "no squadron, no line")
	assert_eq(EmbarkBatch.receipt(blank, "Madrid"), "No crew could be taken aboard.")
	assert_eq(EmbarkBatch.wait_line(blank), "", "nothing waits where nothing can board")
	assert_eq(
		int(EmbarkBatch.file(_screen.model, [], null, func(_id: String) -> void: pass)["filed"]),
		0,
		"a press with no squadron files nothing"
	)

	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))
	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:all")
	assert_eq(home.civilian_count(), 1, "the press boards the one berth")
	assert_true(idle[0].is_embarked(), "the first crew the block prints")
	assert_false(idle[1].is_embarked(), "the crew the berth refuses stays ashore")


## The crown's own seat reads as one press: the port province holds a whole
## province of legal ground, and a crown that only wants the crew ashore at home
## should not open the list to find it (wiki: civilian-units § Landing;
## DR-20261118-28).
func test_the_home_coast_offers_the_seat_in_one_press() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var unit: CivilianState = null
	for candidate: CivilianState in _screen.civilian_layer.units:
		if candidate.owner == _screen.play.player_faction \
			and candidate.type_id == "explorer":
			unit = candidate
			break
	assert_not_null(unit, "the fixture holds an Explorer")
	unit.tile = _screen.model.province_tiles(capital)[0]
	unit.moved = false
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))
	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:%d" % unit.id)
	assert_true(unit.is_embarked())

	var coast: Dictionary = {}
	for raw: Variant in MapPlayCivilianVoyage.crew(_screen.play, home)["land"]:
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == capital:
			coast = row
			break
	assert_false(coast.is_empty(), "the capital coast is offered")
	assert_gte((coast.get("tiles", []) as Array).size(), 2, "the coast holds several grounds")
	var seat: Dictionary = coast.get("seat", {})
	assert_false(seat.is_empty(), "the docked coast names the crown's own seat")
	var site: Vector2i = _screen.model.province_data(capital).town_site()
	assert_gte(site.x, 0, "the fixture's capital has a town site")
	assert_eq(
		Vector2i(int(seat["x"]), int(seat["y"])), site,
		"the seat is the province's own town"
	)
	assert_true(seat.has("ground"), "the seat prints what the chart reads of it")

	MapPlayCivilianVoyage.on_action(
		_screen.play, "crew:land:%d:%d:%s" % [site.x, site.y, unit.type_id]
	)
	assert_false(unit.is_embarked(), "one press puts the crew ashore")
	assert_eq(unit.tile, site, "on the crown's own seat")


## The press names the crew as well as the ground: two kinds aboard one squadron
## read one line each, and the press lands the kind the crown read — a Builder
## first aboard does not step off a press that names the Explorer (wiki:
## civilian-units § Landing; DR-20261118-19).
func test_the_press_lands_the_crew_kind_it_named() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	if home.ship_count() < 2:
		home.add_hull("ship_two")
	assert_gte(home.ship_count(), 2, "two hulls can carry two crews")
	var builder: CivilianState = null
	var explorer: CivilianState = null
	var tile: Vector2i = _screen.model.province_tiles(capital)[0]
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit.owner != _screen.play.player_faction:
			continue
		if unit.type_id == "builder" and builder == null:
			builder = unit
		elif unit.type_id == "explorer" and explorer == null:
			explorer = unit
	assert_not_null(builder, "the fixture holds a Builder")
	assert_not_null(explorer, "the fixture holds an Explorer")
	for unit: CivilianState in [builder, explorer]:
		unit.tile = tile
		unit.moved = false
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))
	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:%d" % builder.id)
	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:%d" % explorer.id)
	assert_true(builder.is_embarked() and explorer.is_embarked(), "both crews board")

	var rows: Array = MapPlayCivilianVoyage.crew(_screen.play, home)["land"]
	var kinds: Array[String] = [] as Array[String]
	for raw: Variant in rows:
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == capital:
			kinds.append(String(row.get("crew", "")))
	assert_true(kinds.has("builder"), "the Builder reads his own line")
	assert_true(kinds.has("explorer"), "the Explorer reads her own line")

	var legal: Array[Vector2i] = CivilianVoyage.landing_tiles_in(
		_screen.model, explorer, home, capital
	)
	var chosen: Vector2i = legal[0]
	MapPlayCivilianVoyage.on_action(
		_screen.play, "crew:land:%d:%d:explorer" % [chosen.x, chosen.y]
	)

	assert_false(explorer.is_embarked(), "the Explorer takes the press")
	assert_eq(explorer.tile, chosen, "on the ground the row named")
	assert_true(builder.is_embarked(), "the Builder stays aboard his own press")
	assert_eq(home.civilian_count(), 1, "one crew left aboard")


## A press that names a crew the ground refuses says so by name, instead of
## landing a different crew the crown did not read (wiki: civilian-units
## § Landing; DR-20261118-19).
func test_a_crew_the_ground_refuses_is_named_in_the_refusal() -> void:
	var capital: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(home, "the fixture founds a home fleet")
	var builder: CivilianState = null
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit.owner == _screen.play.player_faction and unit.type_id == "builder":
			builder = unit
			break
	assert_not_null(builder, "the fixture holds a Builder")
	builder.tile = _screen.model.province_tiles(capital)[0]
	builder.moved = false
	_screen.ship_layer.select(_screen.ship_layer.ship_for(home))
	MapPlayCivilianVoyage.on_action(_screen.play, "crew:embark:%d" % builder.id)
	assert_true(builder.is_embarked())

	# A ground another crown holds: the Builder's own rule bars it, so the press
	# reports the crew it named instead of landing someone else.
	var foreign: Vector2i = Vector2i(-1, -1)
	for y in _screen.model.height:
		for x in _screen.model.width:
			if not _screen.model.is_land(x, y):
				continue
			var province: int = _screen.model.province_at(x, y)
			if province == MapModel.NO_ID or province == capital:
				continue
			if _screen.model.owner_at(x, y) != _screen.play.player_faction:
				foreign = Vector2i(x, y)
				break
		if foreign.x >= 0:
			break
	assert_gte(foreign.x, 0, "the fixture holds ground another crown owns")
	MapPlayCivilianVoyage.land(_screen.play, home, foreign, "builder")
	assert_true(builder.is_embarked(), "a refused ground lands no crew")
	assert_true(
		_last_toast().contains("Builder"),
		"the refusal names the crew the press did: %s" % _last_toast()
	)


## The ground prints only what the crown's own chart and the prospecting rule
## allow: no terrain of an uncharted tile and no mineral no Explorer has
## prospected (wiki: fog-and-exploration § Prospect-Required Resources,
## § What a landing reveals; DR-20261118-23).
func test_a_ground_names_only_what_the_chart_has_reached() -> void:
	var model: MapModel = _screen.model
	var visibility: VisibilityModel = _screen.play.visibility
	var plain: Vector2i = Vector2i(-1, -1)
	var mineral: Vector2i = Vector2i(-1, -1)
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y):
				continue
			var resource: int = model.resource_at(x, y)
			if resource < 0 or not ImprovementCatalog.known(resource):
				continue
			if ImprovementCatalog.needs_prospecting(resource):
				if mineral.x < 0:
					mineral = Vector2i(x, y)
			elif plain.x < 0:
				plain = Vector2i(x, y)
	assert_gte(plain.x, 0, "the fixture holds a tile with a workable resource")
	var index: int = model.index_of(plain.x, plain.y)
	visibility.raise_to(index, VisibilityModel.Level.FOGGED)
	assert_eq(
		MapPlayCivilianVoyage.ground_label(_screen.play, plain),
		String(MapModel.TERRAIN_LABELS.get(model.terrain_at(plain.x, plain.y), "")),
		"a fogged ground names its terrain alone"
	)
	visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	assert_eq(
		MapPlayCivilianVoyage.ground_label(_screen.play, plain), "",
		"an uncharted ground names nothing"
	)
	assert_eq(
		MapPlayCivilianVoyage.ground_label(_screen.play, Vector2i(-1, -1)), "",
		"no tile, no line"
	)
	if mineral.x < 0:
		return
	visibility.raise_to(
		model.index_of(mineral.x, mineral.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	var label: String = MapPlayCivilianVoyage.ground_label(_screen.play, mineral)
	assert_false(
		label.contains("·"),
		"an unprospected mineral keeps its terrain alone: %s" % label
	)


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
	var result: Dictionary = ShipYardOps.scrap_hull(
		_screen.ship_layer, home, hull_id, _screen.play.economy.economy
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
	# A losing zone also reads the way out of the fight: the published retreat
	# chance, over the court whose line beats her (wiki: ships-and-naval
	# § Naval Retreat Formula; DR-20261124-06).
	var ours: Array = []
	for other: FleetState in _screen.ship_layer.fleets:
		if other.owner == fleet.owner and other.is_at_sea() and other.sea_zone == fleet.sea_zone:
			ours.append(other)
	var way: float = NavalRetreat.chance(ours, [enemy], FleetState.Mission.NONE)

	assert_true(block._zone.text.contains("Beaten here by"), block._zone.text)
	assert_true(
		block._zone.text.contains("%d%% to slip into" % int(round(way * 100.0))),
		block._zone.text
	)
	# A crown that holds the edge rolls no retreat, so the line goes.
	enemy.set_hulls(["ship_77"], {"ship_77": "fluyte"})
	MapPlayFleets.show_dossier(_screen.play, fleet)

	assert_false(block._zone.text.contains("Beaten here by"), block._zone.text)
	# No safe water beside the zone: the sheet names the rout instead.
	assert_true(
		block._zone_line({
			"own": 3.0, "foe": 9.0, "retreat": {"ok": false, "court": rival},
		}).contains("no adjacent water is safe"),
		"a shut sea road reads as a rout"
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
## intent — event; DR-20261111-01). Pure diplomacy — no chart re-seat under
## coverage (docs/testing.md § Speed rules; land battle twin in army_orders).
func test_a_sea_fight_leaves_a_word_at_the_rivals_court() -> void:
	var player: int = MapScreen.PLAYER_FACTION
	var rival: int = 2
	var state := DiplomacyState.new()
	state.ensure_relation(player, rival, 1)
	DiplomacyRules.declare_war(state, player, rival)
	assert_true(
		DialogueEvents.record_naval_battle(
			state,
			{
				"zone": 1,
				"attacker": player,
				"defender": rival,
				"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
				"retreat": {},
			},
			player
		),
		"a verdict on the water is kept"
	)

	var spoken: Dictionary = DialogueEvents.for_pair(state, player, rival)
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
		if fleet != null and fleet.owner != MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			return ship
	# The opening muster moors every rival at home (issue #1043): put one
	# squadron in the water so the watch and order cases have a subject.
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet == null or fleet.owner == MapScreen.PLAYER_FACTION:
			continue
		var home: int = fleet.province
		var zones: Array[int] = NavalMovement.province_sea_zones(_screen.model, home)
		if zones.is_empty():
			continue
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = zones[0]
		fleet.province = MapModel.NO_ID
		_screen.ship_layer.rebuild_markers()
		return _screen.ship_layer.ship_for(fleet)
	return _screen.ship_layer.ships[0]


## Every line the court's toasts currently show.
func _toast_texts() -> Array[String]:
	var texts: Array[String] = []
	for panel: Node in _screen.hud.despatches.box.get_children():
		for label: Label in panel.find_children("*", "Label", true, false):
			texts.append(label.text)
	return texts


## Whether any plate the court reads carries this phrase.
func _heard(phrase: String) -> bool:
	for text: String in _toast_texts():
		if text.contains(phrase):
			return true
	return false


## A province another crown holds, for the yard's "capital must be in hand" row.
func _unowned_province() -> int:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner != _screen.play.player_faction and province.owner != MapModel.NO_ID:
			return province.id
	return -1


## Takes the crown's seat, the way a conquest does: another court holds the seat
## province and the flag goes with the court (wiki: capital-and-connectivity
## § Capital loss and reassignment).
func _lose_the_capital(play: PlaySession) -> void:
	var province: int = int(MapPlayCourt.crown_seat(play)["province"])
	if province < 0:
		return
	var seat: ProvinceState = play.model.province_data(province)
	seat.owner = play.model.province_owner(_unowned_province())
	CapitalLoss.clear_seat(seat)


## Moves the crown's seat to another owned province, as reassignment does
## (wiki: capital-and-connectivity § Capital loss and reassignment).
func _move_the_seat(play: PlaySession, province: int) -> void:
	var model: MapModel = play.model
	var current: int = int(MapPlayCourt.crown_seat(play)["province"])
	if current >= 0:
		CapitalLoss.clear_seat(model.province_data(current))
	var seat: ProvinceState = model.province_data(province)
	seat.owner = play.player_faction
	seat.capital = true
	seat.capital_tile = CapitalLoss.town_tile(seat)


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
	var home: FleetState = _rival_home(roster, rival, seat)
	var stray := FleetState.in_port(
		FleetRosters.next_id(roster), rival, seat, ["ship_91"], {"ship_91": "fluyte"}
	)
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


## A seat merge changes the station, so the chart must read it: the squadron that
## joined leaves the water (her marker is dropped, not left to draw), the home
## fleet flies the hulls she brought, and the row closes up behind her
## (wiki: ships-and-naval § Home Fleet, § Fleets in one station; DR-20261119-17).
func test_a_seat_merge_leaves_the_chart_in_step() -> void:
	var play: PlaySession = _screen.play
	var region: int = play.region_index
	var rival: int = -1
	var seat: int = MapModel.NO_ID
	for faction: int in FactionCatalog.great_power_ids():
		if faction == MapScreen.PLAYER_FACTION:
			continue
		var found: int = play.world.capital_province_of(region, faction)
		if found != MapModel.NO_ID:
			rival = faction
			seat = found
			break
	assert_gte(rival, 0, "a rival seats a capital on the shown chart")
	var roster: Array[FleetState] = MapPlayCourt.region_fleets(play, region)
	var home: FleetState = _rival_home(roster, rival, seat)
	var kept: int = home.ship_count()
	var stray := FleetState.in_port(
		FleetRosters.next_id(roster), rival, seat, ["ship_911"], {"ship_911": "fluyte"}
	)
	roster.append(stray)
	play.ship_layer.regions.set_region(region, roster)
	play.ship_layer.attach_marker(stray)
	var stray_marker: Ship = play.ship_layer.markers.find(stray.id)
	assert_not_null(stray_marker, "the docked squadron is drawn at the seat")

	assert_gte(MapPlayHomeMerge.settle_seats(play), 1, "the docked squadron joins")

	assert_null(play.ship_layer.markers.find(stray.id),
		"the merged-away squadron leaves the chart")
	var home_marker: Ship = play.ship_layer.markers.find(home.id)
	assert_not_null(home_marker, "the home fleet keeps her marker")
	assert_eq(home.ship_count(), kept + 1, "her hulls include the one that joined")
	assert_eq(home_marker.hull_count, home.ship_count(),
		"the badge flies the hulls she now carries")
	assert_false(home_marker.stack.has(stray.id),
		"the station's row closes up behind the squadron that left")


## A crown whose own squadron is folded at the turn's close reads the line it
## would have read had it docked by hand: the seat merge is never silent
## (REQ-P5-05; wiki: ships-and-naval § Home Fleet; DR-20261119-17).
func test_the_close_names_the_crowns_own_seat_merge() -> void:
	var stray: FleetState = _stray_at_the_seat()
	var home: FleetState = _screen.play.ship_layer.home_fleet(_screen.play.capital_province)
	assert_not_null(home, "the fixture founds a home fleet")

	assert_gte(MapPlayHomeMerge.settle_seats(_screen.play), 1, "the stray joins at the close")

	assert_null(_screen.ship_layer.markers.find(stray.id), "her marker leaves the seat")
	assert_has(_last_toast(), "joins the home fleet", "the court reads the merge once")


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
	var home: FleetState = _rival_home(roster, rival, seat)
	var stray := FleetState.in_port(
		FleetRosters.next_id(roster), rival, seat, ["ship_93"], {"ship_93": "fluyte"}
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
	var fleet: FleetState = _sea_squadron()
	assert_not_null(fleet, "the fixture sails a player squadron")
	assert_ne(fleet, _screen.ship_layer.home_fleet(capital), "a sea command, not home")
	fleet.sea_zone = NavalMovement.province_sea_zones(_screen.model, capital)[0]
	fleet.province = MapModel.NO_ID
	fleet.location = FleetState.Location.AT_SEA
	return fleet


## The rival's own home fleet at its seat: the opening muster already moors one
## (issue #1043), so the merge cases join it rather than founding a second.
func _rival_home(roster: Array[FleetState], rival: int, seat: int) -> FleetState:
	for fleet: FleetState in roster:
		if fleet != null and fleet.owner == rival and fleet.is_in_port() and fleet.province == seat:
			return fleet
	var made: FleetState = FleetState.in_port(
		FleetRosters.next_id(roster), rival, seat, ["ship_90"], {"ship_90": "fluyte"}
	)
	roster.append(made)
	return made


func _last_toast() -> String:
	var box: VBoxContainer = _screen.hud.despatches.box
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
	var toasts_before: int = _screen.hud.despatches.box.get_child_count()

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
	# Two lines reach the court: the detach, and the place the squadron she keeps
	# now holds in the water (wiki: ships-and-naval § Fleets in one station).
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts_before + 2)
	assert_true(
		_last_toast().contains("as a squadron of her own"),
		"the news names the detach: '%s'" % _last_toast()
	)
	assert_true(
		_heard("squadrons here"),
		"the court hears where the squadron she keeps now stands"
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
	var toasts_before: int = _screen.hud.despatches.box.get_child_count()

	MapPlayFleets.on_action(_screen.play, "split:not_aboard")

	assert_eq(_screen.ship_layer.fleets.size(), roster_before, "no command is founded")
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts_before + 1)
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
	var toasts_before: int = _screen.hud.despatches.box.get_child_count()

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
	assert_eq(_screen.hud.despatches.box.get_child_count(), toasts_before + 2)
	assert_true(
		_last_toast().contains("joins"),
		"the news names the combine: '%s'" % _last_toast()
	)
	assert_true(
		_heard("squadrons here"),
		"the court hears where the joined command now stands"
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
			if int(FleetDrawer.row_of(press).get("fleet", -1)) == fleet_id:
				return press
	return null


## A press carries the whole row it answers for under one key, so a drive reads
## the row's fields; a press from outside the drawer carries none (REQ-P3-02).
func test_a_press_carries_its_row_and_a_stranger_carries_none() -> void:
	assert_eq(FleetDrawer.row_of(null), {}, "no press, no row")
	var stranger := Button.new()
	assert_eq(FleetDrawer.row_of(stranger), {}, "a press with no row carries none")
	stranger.set_meta(FleetDrawer.ROW_KEY, "a plain tag is not a row")
	assert_eq(FleetDrawer.row_of(stranger), {}, "a tag that is no dictionary carries none")
	stranger.set_meta(FleetDrawer.ROW_KEY, {"fleet": 7})
	assert_eq(int(FleetDrawer.row_of(stranger).get("fleet", -1)), 7, "the row rides the press")
	stranger.free()


# --- the opening muster and shared-water markers (issue #1043) ---------------


## Every Great Power opens with one command, moored in port at its own capital,
## carrying all of its opening hulls: no opening squadron starts at sea.
func test_the_opening_muster_moors_one_home_fleet_per_power() -> void:
	var by_owner: Dictionary = {}
	for fleet: FleetState in _screen.ship_layer.fleets:
		assert_false(by_owner.has(fleet.owner), "one squadron per Great Power")
		by_owner[fleet.owner] = fleet
	assert_eq(by_owner.size(), FactionCatalog.great_power_ids().size())
	for power: int in FactionCatalog.great_power_ids():
		var fleet: FleetState = by_owner[power]
		assert_true(fleet.is_in_port(), "every opening squadron moors at home")
		assert_eq(
			fleet.province,
			WorldBootstrap.capital_province(_screen.model, power),
			"each home fleet holds its own capital"
		)
	var home: FleetState = _screen.ship_layer.home_fleet(_screen.play.capital_province)
	assert_not_null(home, "the crown's home fleet holds the seat")
	if home != null:
		assert_eq(
			home.ship_count(), FleetMuster.PLAYER_HULLS.size(),
			"every crown hull rides the one home fleet"
		)


# --- the court's own pick (DR-20261120-04) ----------------------------------


## A pure session on the two-coast chart: the crown's court, at war or at peace,
## with the squadron roster handed in. No screen is mounted, so the pick's cases
## never pay a re-seat.
func _pick_play(at_war: bool) -> PlaySession:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(0, 1, 1)
	if at_war:
		state.relation(0, 1).at_war = true
	var play := PlaySession.new()
	play.player_faction = 0
	play.map_seed = 1500
	play.turn = 1
	play.model = _model
	play.diplomacy = state
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = _model
	return play


## Puts one roster on the chart the session shows, the way the layer stores it.
func _pick_roster(play: PlaySession, fleets: Array[FleetState]) -> void:
	play.ship_layer.fleets.assign(fleets)
	play.ship_layer.regions.set_region(_model.region_id, play.ship_layer.fleets)


## At war, the crown's home squadron is given the sortie the published policy
## takes out of the seat's port — the water and the strength the planner counted
## pass through the words unchanged.
func test_the_courts_pick_sails_the_home_squadron_at_a_hostile_beside_the_seat() -> void:
	var play: PlaySession = _pick_play(true)
	var own: FleetState = FleetState.in_port(0, 0, 0, ["h0"], {"h0": "frigate"})
	var foe: FleetState = FleetState.at_sea(1, 1, 0, ["h1"], {"h1": "sloop"})
	_pick_roster(play, [own, foe] as Array[FleetState])

	var pick: Dictionary = MapPlayFleetPick.pick(play, own)

	assert_eq(String(pick.get("kind", "")), AiNavalPlanner.KIND_SORTIE, "the sortie")
	assert_eq(int(pick.get("zone", -1)), 0, "into the water beside the seat")
	var line: String = String(pick.get("line", ""))
	assert_eq(
		line,
		"the court would sortie into the Mar Caribe — a hostile squadron there, counted at %d strength"
			% int(pick.get("threat", 0)),
		"the words name the water and the planner's own count"
	)
	assert_true(MapPlayFleetPick.line(play, own).begins_with("The court would sortie"), "one sentence")
	assert_eq(own.location, FleetState.Location.IN_PORT, "a reading: she is still in port")
	assert_false(own.moved, "and she has not sailed")
	play.ship_layer.free()


## At peace there is no station to keep: the pick is the road home, and a harbour
## that borders her water means the dock itself.
func test_the_courts_pick_brings_a_peaceful_squadron_home() -> void:
	var play: PlaySession = _pick_play(false)
	var own: FleetState = FleetState.at_sea(0, 0, 0, ["h0"], {"h0": "galleon"})
	_pick_roster(play, [own] as Array[FleetState])

	var pick: Dictionary = MapPlayFleetPick.pick(play, own)

	assert_eq(String(pick.get("kind", "")), AiNavalPlanner.KIND_HOME)
	assert_true(bool(pick.get("dock", false)), "Cádiz borders her water")
	assert_eq(int(pick.get("province", -1)), 0)
	assert_eq(String(pick.get("line", "")), "the court would dock her at %s" % _model.province_name(0))
	assert_eq(own.sea_zone, 0, "a reading: she is still at sea")
	play.ship_layer.free()


## A warship with no squadron to fight works the enemy's trade, so the pick names
## the coast's water and the leg that begins the station.
func test_the_courts_pick_works_the_enemys_trade_with_nothing_to_fight() -> void:
	var play: PlaySession = _pick_play(true)
	var own: FleetState = FleetState.at_sea(0, 0, 0, ["h0"], {"h0": "sloop"})
	_pick_roster(play, [own] as Array[FleetState])

	var pick: Dictionary = MapPlayFleetPick.pick(play, own)

	assert_eq(String(pick.get("kind", "")), AiNavalPlanner.KIND_RAID)
	assert_eq(int(pick.get("zone", -1)), 1, "Coro's water, one step on")
	assert_eq(
		String(pick.get("line", "")),
		"the court would sail for the %s — the first leg toward a hostile coast, to work its trade"
			% _model.sea_zone_name(1),
		"the words name the leg, not a station it has not reached"
	)
	assert_eq(own.sea_zone, 0, "nothing sails")
	play.ship_layer.free()


## The holds come before any hunt: a squadron carrying the tonnage its court has
## nowhere else is sent home, and the line says why (issue #530).
func test_the_courts_pick_brings_the_holds_home_first() -> void:
	var play: PlaySession = _pick_play(true)
	var own: FleetState = FleetState.at_sea(0, 0, 1, ["h0"], {"h0": "carrack"})
	_pick_roster(play, [own] as Array[FleetState])

	var pick: Dictionary = MapPlayFleetPick.pick(play, own)

	assert_eq(String(pick.get("kind", "")), AiNavalPlanner.KIND_HOME)
	assert_eq(String(pick.get("reason", "")), AiNavalPlanner.REASON_TRADE)
	var line: String = String(pick.get("line", ""))
	assert_true(line.begins_with("the court would sail for the "), line)
	assert_true(line.ends_with("— the holds come first, and the crown keeps none ashore"), line)
	assert_eq(own.sea_zone, 1, "nothing sails")
	play.ship_layer.free()


## The pick is only for a squadron the court would still order: a rival's hull, a
## squadron that has sailed, one carrying an expedition, and a session whose court
## runs no planner all carry none.
func test_the_courts_pick_names_no_squadron_the_court_would_leave_alone() -> void:
	var play: PlaySession = _pick_play(true)
	var own: FleetState = FleetState.in_port(0, 0, 0, ["h0"], {"h0": "frigate"})
	var rival: FleetState = FleetState.at_sea(1, 1, 0, ["h1"], {"h1": "sloop"})
	var expedition: FleetState = FleetState.at_sea(2, 0, 1, ["h2"], {"h2": "frigate"})
	expedition.embarked_army = 4
	_pick_roster(play, [own, rival, expedition] as Array[FleetState])

	assert_false(MapPlayFleetPick.pick(play, own).is_empty(), "the crown's own squadron takes one")
	assert_true(MapPlayFleetPick.pick(play, rival).is_empty(), "a rival answers to her own court")
	own.moved = true
	assert_true(MapPlayFleetPick.pick(play, own).is_empty(), "a hull that has sailed is not re-ordered")
	own.moved = false
	assert_true(
		MapPlayFleetPick.pick(play, expedition).is_empty(),
		"the invasion planner steers an expedition"
	)
	play.ai_mode = AiControl.NOOP
	assert_true(MapPlayFleetPick.pick(play, own).is_empty(), "no planner, no advice")
	play.ship_layer.free()


## The pick reads nothing it cannot: no session, no squadron, no charts of
## diplomacy, a campaign already decided, and a squadron the region table stores
## but the chart does not draw all answer empty rather than guessing a water.
func test_the_courts_pick_reads_nothing_without_a_session_to_read() -> void:
	var play: PlaySession = _pick_play(false)
	var own: FleetState = FleetState.at_sea(0, 0, 0, ["h0"], {"h0": "galleon"})
	_pick_roster(play, [own] as Array[FleetState])
	assert_true(MapPlayFleetPick.pick(null, own).is_empty(), "no session, no pick")
	assert_true(MapPlayFleetPick.pick(play, null).is_empty(), "no squadron, no pick")
	var bare := PlaySession.new()
	bare.player_faction = 0
	bare.model = _model
	assert_true(MapPlayFleetPick.pick(bare, own).is_empty(), "no fleet layer, no pick")
	bare.ship_layer = ShipLayer.new()
	bare.ship_layer.model = _model
	bare.ship_layer.fleets.assign([own])
	assert_true(MapPlayFleetPick.pick(bare, own).is_empty(), "no diplomacy, no pick")
	play.campaign_halted = true
	assert_true(MapPlayFleetPick.pick(play, own).is_empty(), "a decided campaign orders nothing")
	play.campaign_halted = false
	# The region table stores her while the chart draws nothing: the loop finds
	# her chart, and a session with no world for it answers empty.
	play.ship_layer.fleets.clear()
	var stored: Dictionary = {0: [own]}
	var lonely := PlaySession.new()
	lonely.player_faction = 0
	lonely.model = null
	lonely.diplomacy = play.diplomacy
	lonely.ship_layer = ShipLayer.new()
	lonely.ship_layer.fleets.assign([])
	lonely.ship_layer.regions.set_region(0, stored[0])
	assert_true(
		MapPlayFleetPick.pick(lonely, own).is_empty(),
		"a chart the session does not hold answers nothing"
	)
	var world := WorldMap.new()
	world.add_region(_model)
	lonely.world = world
	lonely.ship_layer.regions.set_region(0, [FleetState.at_sea(0, 0, 0, ["h0"], {"h0": "galleon"})])
	var found: Dictionary = MapPlayFleetPick.pick(lonely, lonely.ship_layer.regions.value(0)[0])
	assert_false(found.is_empty(), "the world's own chart answers for a region off screen")
	play.ship_layer.free()
	bare.ship_layer.free()
	lonely.ship_layer.free()


## Two squadrons of the crown plan together, and each picks her own order: the
## plan's other rows are skipped, never handed to the wrong hull.
func test_the_courts_pick_hands_each_squadron_its_own_order() -> void:
	var play: PlaySession = _pick_play(false)
	var first: FleetState = FleetState.at_sea(0, 0, 0, ["h0"], {"h0": "galleon"})
	var second: FleetState = FleetState.at_sea(1, 0, 1, ["h1"], {"h1": "fluyte"})
	_pick_roster(play, [first, second] as Array[FleetState])

	var one: Dictionary = MapPlayFleetPick.pick(play, first)
	var two: Dictionary = MapPlayFleetPick.pick(play, second)

	assert_false(one.is_empty(), "the first squadron is ordered home")
	assert_false(two.is_empty(), "and so is the second")
	assert_true(
		String(one.get("line", "")).contains(_model.province_name(0)),
		"each line names her own harbour: " + String(one.get("line", ""))
	)
	assert_eq(String(two.get("kind", "")), AiNavalPlanner.KIND_HOME, "the second is sent home")
	assert_eq(int(two.get("zone", -1)), 0, "her own leg, one water back toward the seat")
	assert_true(
		String(two.get("line", "")).ends_with("the first leg home"),
		"the second reads her own leg: " + String(two.get("line", ""))
	)
	assert_eq(first.sea_zone, 0, "nothing sailed")
	assert_eq(second.sea_zone, 1, "nothing sailed")
	play.ship_layer.free()


## Every wording the pick can print: one sentence per kind and per reason the
## policy carries, and nothing at all for an order or a chart that names no place
## (wiki: ships-and-naval § Missions and Movement; DR-20261120-04).
func test_the_picks_words_name_each_sail_and_its_reason() -> void:
	var model: MapModel = _model
	var water: String = model.sea_zone_name(0)
	var port: String = model.province_name(0)
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "sortie", "zone": 0, "threat": 3}),
		"the court would sortie into the %s — a hostile squadron there, counted at 3 strength"
			% water
	)
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "pursue", "zone": 0}),
		"the court would pursue into the %s" % water,
		"an order that counted no strength names no figure"
	)
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "home", "dock": true, "province": 0}),
		"the court would dock her at %s" % port
	)
	assert_eq(
		MapPlayFleetPickWords.line(
			model, {"kind": "home", "dock": false, "zone": 0, "reason": "overstretched: no new raid"}
		),
		"the court would sail for the %s — the first leg home — two fronts, so the court opens"
			% water + " no new raid",
		"the footing's own reason"
	)
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "convoy", "zone": 0}),
		"the court would convoy her toward the %s — the first leg home with the holds" % water,
		"a merchant's leg reads as a convoy (issue #1258)"
	)
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "convoy", "dock": true, "province": 0}),
		"the court would convoy her home to %s" % port
	)
	assert_eq(
		MapPlayPickProse.sentence("the court would dock her at %s" % port),
		"The court would dock her at %s." % port
	)
	assert_eq(MapPlayPickProse.sentence(""), "", "no words, no sentence")
	assert_eq(MapPlayFleetPickWords.line(model, {}), "", "no order, no line")
	assert_eq(MapPlayFleetPickWords.line(model, {"kind": "unknown"}), "", "no kind, no line")
	assert_eq(MapPlayFleetPickWords.line(null, {"kind": "home"}), "", "no chart, no line")
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "sortie", "zone": -1, "threat": 2}), "",
		"a fight in no water is not worded"
	)
	assert_eq(MapPlayFleetPickWords.line(model, {"kind": "raid", "zone": -1}), "", "nor a raid")
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "home", "dock": true, "province": -1}), "",
		"a dock with no harbour is not worded"
	)
	assert_eq(
		MapPlayFleetPickWords.line(model, {"kind": "home", "dock": false, "zone": -1}), "",
		"nor a homeward leg in no water"
	)


# --- the court's own yard claim (DR-20261121-02) -----------------------------


## A pure session on the two-coast chart with the crown's own ledger: at war or
## at peace, a purse, the studies it knows and the hulls each side flies. No
## screen is mounted, so the yard-claim cases never pay a re-seat.
func _yard_play(
	at_war: bool,
	treasury: int,
	techs: Dictionary,
	own_types: Array,
	foe_types: Array = []
) -> PlaySession:
	var play: PlaySession = _pick_play(at_war)
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()
	controller.economy.treasury = treasury
	controller.economy.tech_unlocked = techs.duplicate()
	play.economy = controller
	var roster: Array[FleetState] = []
	if not own_types.is_empty():
		var hulls: Array[String] = []
		var types: Dictionary = {}
		for index in own_types.size():
			hulls.append("own_%d" % index)
			types["own_%d" % index] = String(own_types[index])
		roster.append(FleetState.in_port(0, 0, 0, hulls, types))
	if not foe_types.is_empty():
		var foe_hulls: Array[String] = []
		var foe: Dictionary = {}
		for index in foe_types.size():
			foe_hulls.append("foe_%d" % index)
			foe["foe_%d" % index] = String(foe_types[index])
		roster.append(FleetState.in_port(1, 1, 0, foe_hulls, foe))
	play.ship_layer.fleets.assign(roster)
	play.ship_layer.regions.set_region(_model.region_id, play.ship_layer.fleets)
	return play


## The yard's own claim names the hull it would lay, priced exactly as her slip
## row prices her — and lays nothing: the purse, the hulls and the queue stand.
func test_the_yard_pick_lays_the_hull_the_slip_can_pay() -> void:
	var play: PlaySession = _yard_play(true, 20000, {}, ["sloop"], ["sloop", "sloop"])

	var pick: Dictionary = MapPlayYardPick.pick(play)

	assert_eq(String(pick.get("kind", "")), MapPlayYardPick.KIND_LAY)
	assert_eq(String(pick.get("type", "")), "sloop", "the hull her own yard would lay")
	assert_eq(String(pick.get("line", "")), MapPlayYardPickWords.lay_line("sloop"))
	assert_eq(
		MapPlayYardPick.line(play),
		"The court would lay a Sloop — 5,500 ducats · 1 Lumber · 1 Fabric · 1 worker.",
		"one sentence, the slip row's own price line"
	)
	assert_eq(play.economy.economy.treasury, 20000, "a reading: not a ducat spent")
	play.ship_layer.free()
	play.economy.free()


## The yard refuses and a study is why: the claim names the hull it is saving for
## and the door the college would open for her, so both sheets read one chain.
func test_the_yard_pick_names_the_study_that_opens_the_hull_it_saves_for() -> void:
	var play: PlaySession = _yard_play(true, 20000, {}, [], [])
	var study: String = AiNavy.unlock_tech(play.economy.economy, [] as Array[String])
	assert_false(study.is_empty(), "a warship's door is a study")

	var pick: Dictionary = MapPlayYardPick.pick(play)

	assert_eq(String(pick.get("kind", "")), MapPlayYardPick.KIND_STUDY)
	assert_eq(String(pick.get("type", "")), "sloop", "the cheapest hull the chest saves toward")
	assert_eq(String(pick.get("study", "")), study)
	assert_eq(
		String(pick.get("line", "")),
		"the court is saving for a Sloop — the study %s opens her"
			% TechCatalog.display_name(study)
	)
	play.ship_layer.free()
	play.economy.free()


## A hull the studies open but the purse cannot pay: the line names the shortfall
## as a figure, so a saving crown reads what it is saving and what it holds.
func test_the_yard_pick_names_the_purse_it_is_filling() -> void:
	var play: PlaySession = _yard_play(true, 100, {"navigation": true}, [])

	var pick: Dictionary = MapPlayYardPick.pick(play)

	assert_eq(String(pick.get("kind", "")), MapPlayYardPick.KIND_SAVING)
	assert_eq(String(pick.get("type", "")), "sloop")
	assert_eq(int(pick.get("price", 0)), ShipEconomy.treasury_cost("sloop"))
	assert_eq(
		String(pick.get("line", "")),
		"the court is saving for a Sloop — the purse holds 100 ducats of 5,500 ducats"
	)
	play.ship_layer.free()
	play.economy.free()


## A hull the studies open and the purse can pay, held back by the stores: the
## line names the yard's own refusal, never a purse that is already full
## (wiki: ships-and-naval § Ship build economy; DR-20261121-02).
func test_the_yard_pick_names_the_stores_that_hold_the_hull_back() -> void:
	var play: PlaySession = _yard_play(true, 20000, {"navigation": true}, [])
	play.economy.economy.stockpile["lumber"] = 0
	play.economy.economy.stockpile["fabric"] = 0

	var pick: Dictionary = MapPlayYardPick.pick(play)

	assert_eq(String(pick.get("kind", "")), MapPlayYardPick.KIND_STORES)
	assert_eq(String(pick.get("type", "")), "sloop")
	assert_eq(
		String(pick.get("line", "")),
		"the court would lay a Sloop — the yard cannot: Insufficient materials"
	)
	assert_eq(
		MapPlayYardPick.line(play),
		"The court would lay a Sloop — the yard cannot: Insufficient materials.",
		"the yard's own gate, not a purse that is not short"
	)
	assert_false(
		MapPlayYardPick.line(play).contains("purse"),
		"a funded court is never told it is saving"
	)
	assert_eq(
		MapPlayYardPickWords.gate_line("sloop", ""), "",
		"no gate worded, no line"
	)
	assert_eq(play.economy.economy.treasury, 20000, "a reading: not a ducat spent")
	play.ship_layer.free()
	play.economy.free()


## A hull the studies open and the stores cover, held back by the pool: the line
## names the missing hand, which is the gate the yard itself refuses on.
func test_the_yard_pick_names_the_free_hand_that_holds_the_hull_back() -> void:
	var play: PlaySession = _yard_play(true, 20000, {"navigation": true}, [], ["sloop"])
	play.economy.economy.workers = WorkerPool.make(0)

	var pick: Dictionary = MapPlayYardPick.pick(play)

	assert_eq(String(pick.get("kind", "")), MapPlayYardPick.KIND_STORES)
	assert_eq(
		String(pick.get("line", "")),
		"the court would lay a Sloop — the yard cannot: Insufficient workers"
	)
	assert_eq(play.economy.economy.treasury, 20000, "a reading: not a ducat spent")
	play.ship_layer.free()
	play.economy.free()


## The claim speaks only while the court means to lay a hull: a navy that already
## matches its enemies, a session that runs no planner, a decided campaign and a
## session with no ledger carry none.
func test_the_yard_pick_names_no_hull_a_court_does_not_mean_to_lay() -> void:
	var settled: PlaySession = _yard_play(false, 20000, {"navigation": true}, ["sloop"])
	assert_true(MapPlayYardPick.pick(settled).is_empty(), "a matched navy at peace claims nothing")
	settled.ship_layer.free()
	settled.economy.free()
	var play: PlaySession = _yard_play(true, 20000, {}, [], [])
	play.ai_mode = AiControl.NOOP
	assert_true(MapPlayYardPick.pick(play).is_empty(), "no planner, no claim")
	play.ai_mode = AiControl.FULL
	play.campaign_halted = true
	assert_true(MapPlayYardPick.pick(play).is_empty(), "a decided campaign lays nothing")
	play.campaign_halted = false
	assert_false(MapPlayYardPick.pick(play).is_empty(), "the same court, undecided, claims one")
	assert_true(MapPlayYardPick.pick(null).is_empty(), "no session, no claim")
	var bare := PlaySession.new()
	bare.player_faction = 0
	assert_true(MapPlayYardPick.pick(bare).is_empty(), "no ledger, no claim")
	play.ship_layer.free()
	play.economy.free()


## One ready row's worth of slip, enough for the drawer to open on: the case reads
## the advice line, not the launch rule.
func _slip_row() -> Dictionary:
	return {
		"type_id": "sloop",
		"name": "Sloop",
		"ok": true,
		"reason": "",
		"cost_text": ShipEconomy.cost_text("sloop"),
		"line": FleetYard.hull_line("sloop"),
		"batch_ready": false,
	}


## The drawer prints the claim under its launch heading, in the pick's own words,
## marks the hull it names, and a rival's slip prints neither (REQ-P5-03,
## REQ-P2-03, DR-20261122-12).
func test_the_yard_drawer_prints_the_courts_claim_under_its_heading() -> void:
	var yard := FleetYardBlock.new()
	add_child(yard)
	var pick: Dictionary = {
		"kind": MapPlayYardPick.KIND_LAY,
		"type": "sloop",
		"line": MapPlayYardPickWords.lay_line("sloop"),
	}
	var rows: Array[Dictionary] = [_slip_row()]
	yard.show_rows(null, rows, true, true, pick)

	assert_eq(
		yard.pick_line(), MapPlayPickProse.sentence_of(pick),
		"the drawer words the claim it was handed"
	)
	assert_eq(yard.mark_type(), "sloop", "the mark is the pick's own hull")
	assert_eq(
		yard.legend_text(), FleetYardBlock.MARK_LEGEND,
		"the slip says what its mark means"
	)
	assert_true(yard.legend_shown(), "the legend stands while a hull is named")
	var printed: Array[String] = []
	for child: Node in yard._box.get_children():
		var label := child as Label
		if label != null:
			printed.append(label.text)
	assert_true(
		printed.has(yard.pick_line()), "the claim stands on the slip: %s" % str(printed)
	)
	assert_eq(
		_yard_row_name(yard, rows, "sloop"),
		"%s Sloop" % FleetYardBlock.COURT_MARK,
		"the hull the line names wears the mark"
	)

	var plain: Dictionary = {
		"kind": MapPlayYardPick.KIND_LAY,
		"type": "schooner",
		"line": MapPlayYardPickWords.lay_line("sloop"),
	}
	yard.show_rows(null, rows, true, true, plain)
	assert_eq(
		_yard_row_name(yard, rows, "sloop"), "Sloop",
		"a hull the line does not name keeps its plain name"
	)

	yard.show_rows(null, rows, true, true, {})
	assert_eq(yard.pick_line(), "", "an empty read prints no claim")
	assert_false(yard.legend_shown(), "and the legend leaves the slip's list")
	assert_eq(yard._legend.get_parent(), null, "so the list holds no stray sentence")

	yard.show_rows(null, rows, false, true, pick)
	assert_eq(yard.pick_line(), "", "a rival answers to her own court")
	assert_eq(yard.mark_type(), "", "and marks no hull")
	assert_false(yard.legend_shown(), "and explains no glyph")
	yard.queue_free()


## One launch row's name label, by the row the yard gives that hull.
func _yard_row_name(
	yard: FleetYardBlock, rows: Array[Dictionary], type_id: String
) -> String:
	var wanted: int = -1
	for index: int in rows.size():
		if String(rows[index].get("type_id", "")) == type_id:
			wanted = index
			break
	if wanted < 0:
		return ""
	var seen: int = 0
	for child: Node in yard._box.get_children():
		if not (child is VBoxContainer) or child.is_queued_for_deletion():
			continue
		if seen == wanted:
			var top := (child as VBoxContainer).get_child(0) as HBoxContainer
			return (top.get_child(1) as Label).text
		seen += 1
	return ""


## The claim the pure cases prove reaches the live slip: a crown at war with no
## fighting hull afloat, a full purse and the study that opens her cheapest
## warship, and the drawer prints the pick the reading returns (DR-20261121-02).
func test_the_live_capital_slip_prints_the_claim_the_court_would_take() -> void:
	var play: PlaySession = _screen.play
	_declare_war(1)
	play.economy.economy.treasury = 60000
	play.economy.economy.tech_unlocked["navigation"] = true
	for region: int in play.ship_layer.regions.region_ids():
		var kept: Array[FleetState] = []
		for raw: Variant in play.ship_layer.regions.value(region, []):
			var fleet: FleetState = raw
			if fleet != null and fleet.owner != play.player_faction:
				kept.append(fleet)
		play.ship_layer.regions.set_region(region, kept)
	play.selected_province = play.capital_province

	MapPlayFleetYard.open(play)

	var line: String = MapPlayYardPick.line(play)
	assert_false(line.is_empty(), "a court with no hull claims one")
	assert_eq(_screen.hud.panels.fleet_panel._yard.pick_line(), line, "the slip prints it")


## The claim's three sentences, word for word: the hull the yard would lay priced
## by her own row, the hull saved for against the purse, and the study that opens
## her (DR-20261121-02).
func test_the_yard_picks_words_name_each_hull_and_its_gate() -> void:
	assert_eq(
		MapPlayYardPickWords.lay_line("sloop"),
		"the court would lay a Sloop — %s" % ShipEconomy.cost_text("sloop"),
		"the price is her row's own"
	)
	assert_eq(
		MapPlayYardPickWords.saving_line("sloop", 5500, 2400),
		"the court is saving for a Sloop — the purse holds 2,400 ducats of 5,500 ducats"
	)
	assert_eq(
		MapPlayYardPickWords.study_line("sloop", "navigation"),
		"the court is saving for a Sloop — the study Navigation opens her"
	)
	assert_eq(
		MapPlayPickProse.sentence("the court would lay a Sloop — 5,500 ducats"),
		"The court would lay a Sloop — 5,500 ducats."
	)
	assert_eq(MapPlayPickProse.sentence(""), "", "no words, no sentence")


# --- the voyage pick (DR-20261121-08) ---------------------------------------


## A pure session with a New World beside the two-coast chart: the crown's seat
## at Cádiz, an idle Explorer at the harbour and a free squadron in port, with a
## ledger so the voyage plan has a purse to read. No screen is mounted.
func _voyage_play() -> PlaySession:
	var home: MapModel = NavalFixture.build()
	var abroad: MapModel = NavalFixture.build()
	abroad.region_id = FactionCatalog.NEW_WORLD
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(abroad)
	var play := PlaySession.new()
	play.player_faction = 0
	play.map_seed = 1500
	play.turn = 1
	play.world = world
	play.model = home
	play.region_index = home.region_id
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	play.diplomacy.ensure_relation(0, 1, 1)
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = home
	play.civilian_layer = CivilianLayer.new()
	play.ai = AiState.new()
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()
	play.economy = controller
	return play


## The crown's colonist waits at the harbour and a free squadron is in port: the
## block names the boarding the court's own voyage plan would take, and boards
## nobody (wiki: civilian-units § Overseas deployment; DR-20261121-08).
func test_the_voyage_pick_boards_the_colonist_the_court_would_send() -> void:
	var play: PlaySession = _voyage_play()
	var fleet: FleetState = FleetState.in_port(0, 0, 0, ["h0"], {"h0": "fluyt"})
	var explorer: CivilianState = CivilianState.create(1, 0, "explorer", Vector2i(1, 0))
	_pick_roster(play, [fleet] as Array[FleetState])
	play.civilian_layer.units.assign([explorer] as Array[CivilianState])
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)

	var pick: Dictionary = MapPlayVoyagePick.pick(play, fleet)

	assert_eq(String(pick.get("kind", "")), MapPlayVoyagePick.KIND_EMBARK, "the boarding")
	assert_eq(int(pick.get("fleet", -1)), fleet.id, "the plan names this squadron")
	assert_eq(int(pick.get("unit", -1)), explorer.id, "and the crew it would take")
	assert_eq(String(pick.get("crew", "")), "explorer")
	assert_eq(
		String(pick.get("line", "")),
		"the court would take an Explorer aboard at %s" % _model.province_name(0),
		"the words name the crew and the harbour"
	)
	assert_eq(
		MapPlayVoyagePick.line(play, fleet),
		"The court would take an Explorer aboard at %s." % _model.province_name(0),
		"one sentence"
	)
	assert_eq(explorer.embarked_fleet, -1, "a reading: nobody boards")
	assert_false(fleet.moved, "and no hull sails")
	play.ship_layer.free()


## A landing names the ground, not the coast: the pick carries the province the
## tile stands in, so the passenger block can mark the coast the step would take
## (wiki: civilian-units § Landing; DR-20261122-21).
func test_the_voyage_pick_carries_the_coast_a_landing_stands_on() -> void:
	var play: PlaySession = _voyage_play()
	var fleet: FleetState = FleetState.in_port(0, 0, 0, ["h0"], {"h0": "fluyt"})
	var explorer: CivilianState = CivilianState.create(1, 0, "explorer", Vector2i(1, 0))
	_pick_roster(play, [fleet] as Array[FleetState])
	play.civilian_layer.units.assign([explorer] as Array[CivilianState])
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)

	var tile := Vector2i(5, 1)
	var pick: Dictionary = MapPlayVoyagePick._words(
		play, fleet, 0,
		{"kind": "land", "fleet": fleet.id, "unit": explorer.id, "tile": tile}
	)

	assert_eq(String(pick.get("kind", "")), MapPlayVoyagePick.KIND_LAND, "the landing")
	assert_eq(
		int(pick.get("province", -1)), play.model.province_at(tile.x, tile.y),
		"the coast the tile stands in travels beside the ground"
	)
	assert_eq(int(pick.get("unit", -1)), explorer.id, "and the crew it would put ashore")
	assert_true(
		String(pick.get("line", "")).begins_with(
			"the court would put an Explorer ashore at (5, 1)"
		),
		"the words name the ground"
	)
	assert_eq(explorer.embarked_fleet, -1, "a reading: nobody lands")
	play.ship_layer.free()


## The pick is only for a squadron the court would still order: a rival's hull, a
## squadron that has sailed, a crown with no ledger and a decided campaign all
## carry none.
func test_the_voyage_pick_names_no_squadron_the_court_would_leave_alone() -> void:
	var play: PlaySession = _voyage_play()
	var fleet: FleetState = FleetState.in_port(0, 0, 0, ["h0"], {"h0": "fluyt"})
	var rival: FleetState = FleetState.in_port(1, 1, 1, ["h1"], {"h1": "sloop"})
	var explorer: CivilianState = CivilianState.create(1, 0, "explorer", Vector2i(1, 0))
	_pick_roster(play, [fleet, rival] as Array[FleetState])
	play.civilian_layer.units.assign([explorer] as Array[CivilianState])
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)

	assert_false(MapPlayVoyagePick.pick(play, fleet).is_empty(), "the crown's own squadron takes one")
	assert_true(MapPlayVoyagePick.pick(play, rival).is_empty(), "a rival answers to her own court")
	fleet.moved = true
	assert_true(MapPlayVoyagePick.pick(play, fleet).is_empty(), "a hull that has sailed is not re-ordered")
	fleet.moved = false
	play.economy = null
	assert_true(MapPlayVoyagePick.pick(play, fleet).is_empty(), "no ledger, no voyage plan")
	play.economy = EconomyController.new()
	play.economy.economy = PlayerEconomy.starting()
	play.campaign_halted = true
	assert_true(MapPlayVoyagePick.pick(play, fleet).is_empty(), "a decided campaign sails nothing")
	play.campaign_halted = false
	assert_true(MapPlayVoyagePick.pick(null, fleet).is_empty(), "no session, no pick")
	assert_true(MapPlayVoyagePick.pick(play, null).is_empty(), "no squadron, no pick")
	play.ship_layer.free()


## The voyage's own words, step by step: the water a carrying squadron sails, the
## harbour a free one makes for, the Passage it crosses and the ground it lands
## on — every figure the plan's own (DR-20261121-08).
func test_the_voyage_words_name_each_step_the_plan_takes() -> void:
	var model: MapModel = _model
	assert_eq(
		MapPlayPickProse.sentence(MapPlayVoyagePickWords.line(model, {
			"kind": "sail", "zone": 0, "carrying": true,
		})),
		"The court would sail her for the %s — the first leg to the Passage." % (
			model.sea_zone_name(0)
		)
	)
	assert_eq(
		MapPlayVoyagePickWords.line(model, {
			"kind": "sail", "zone": 1, "carrying": false, "harbour": 0,
		}),
		"the court would sail her for the %s — the first leg to %s, where the voyage musters" % [
			model.sea_zone_name(1), model.province_name(0)
		]
	)
	assert_eq(
		MapPlayVoyagePickWords.line(model, {"kind": "dock", "province": 0}),
		"the court would dock her at %s — the harbour the voyage musters at" % (
			model.province_name(0)
		)
	)
	assert_eq(
		MapPlayVoyagePickWords.line(model, {"kind": "cross", "crew": "explorer"}),
		"the court would cross the Passage with an Explorer aboard"
	)
	assert_eq(
		MapPlayVoyagePickWords.line(model, {
			"kind": "land", "crew": "explorer", "tile": Vector2i(5, 1),
			"ground": "Plains · grain",
		}),
		"the court would put an Explorer ashore at (5, 1) — Plains · grain"
	)
	assert_eq(
		MapPlayVoyagePickWords.line(model, {"kind": "land", "crew": "explorer", "tile": Vector2i(5, 1)}),
		"the court would put an Explorer ashore at (5, 1)",
		"an uncharted ground names the tile alone"
	)
	assert_eq(MapPlayVoyagePickWords.line(model, {"kind": "unknown"}), "", "no step, no words")
	assert_eq(MapPlayVoyagePickWords.line(null, {"kind": "dock", "province": 0}), "", "no chart, no words")


# --- the court's own expedition reading (DR-20261122-20) ---------------------


## One chart of the expedition's world: a four-wide coast under one sea zone. The
## crown's Old World seat and the Tribe's New World coast are built the same way;
## only the owner tells them apart.
func _expedition_region(region: int, owner: int) -> MapModel:
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = region
	model.region_key = FactionCatalog.REGION_KEYS[region]
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			var index: int = model.index_of(x, y)
			model.terrain[index] = MapModel.Terrain.PLAINS
			model.province[index] = 0
			tiles.append(Vector2i(x, y))
	for x in 4:
		var water: int = model.index_of(x, 2)
		model.terrain[water] = MapModel.Terrain.OCEAN
		model.sea_zone[water] = 0
	var province := ProvinceState.create(
		0, "Coast", tiles, Vector2(1.5, 0.5), tiles.size(), owner, false
	)
	province.coastal = true
	model.provinces = [province]
	var sea: Array[Vector2i] = []
	for x in 4:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Passage Water", sea, Vector2(1.5, 2.0), 4)]
	return model


## The two-chart world the expedition cases sail: the crown's seat coast in the
## Old World, a Tribe's coast in the New, linked both ways by the Passage.
func _expedition_world() -> WorldMap:
	var world := WorldMap.new()
	world.add_region(_expedition_region(WorldMap.OLD_WORLD, MapScreen.PLAYER_FACTION))
	world.add_region(_expedition_region(WorldMap.NEW_WORLD, 9))
	world.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return world


## The expedition the cases read: a squadron at sea carrying a two-regiment host.
func _expedition_pair() -> Dictionary:
	var army: ArmyState = ArmyState.muster(
		1, MapScreen.PLAYER_FACTION, 0, false, ["pikemen", "squires"], 10
	)
	var fleet: FleetState = FleetState.at_sea(
		1, MapScreen.PLAYER_FACTION, 0, ["h1"], {"h1": "frigate"}
	)
	fleet.embarked_army = army.id
	return {"fleet": fleet, "army": army}


## A session on that world with the squadron and her host stored on `region`'s
## chart the way the layers store them. No screen is mounted, so the reading pays
## no re-seat.
func _expedition_play(
	world: WorldMap, region: int, fleet: FleetState, army: ArmyState
) -> PlaySession:
	var model: MapModel = world.region(region)
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(MapScreen.PLAYER_FACTION, 9, 1)
	# The pick reads a war crossing: a Tribal coast is a target only under a
	# declaration (wiki: diplomacy § War required for hostile actions).
	state.relation(MapScreen.PLAYER_FACTION, 9).at_war = true
	var play := PlaySession.new()
	play.player_faction = MapScreen.PLAYER_FACTION
	play.map_seed = 1500
	play.turn = 0
	play.world = world
	play.model = model
	play.diplomacy = state
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = model
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(region, [fleet])
	play.army_layer = ArmyLayer.new()
	play.army_layer.model = model
	play.army_layer.armies = [army]
	play.army_layer.regions.set_region(region, [army])
	return play


## The step is worded in the rule book's own names: the water she sails, the
## Passage she crosses, the coast she marks and the landing it opens.
func test_the_expeditions_words_name_every_step() -> void:
	var model: MapModel = _expedition_region(WorldMap.NEW_WORLD, 9)
	var coast: String = model.province_name(0)
	assert_eq(
		MapPlayExpeditionPick.words(model, {"kind": "sail", "zone": 0}),
		"the court would sail the expedition for the %s" % model.sea_zone_name(0)
	)
	assert_eq(
		MapPlayExpeditionPick.words(model, {"kind": "cross", "zone": 0}),
		"the court would cross the Passage with the host aboard"
	)
	assert_eq(
		MapPlayExpeditionPick.words(model, {"kind": "beachhead", "province": 0}),
		"the court would mark a beachhead on the coast of %s — the landing opens next turn"
			% coast
	)
	assert_eq(
		MapPlayExpeditionPick.words(model, {"kind": "land", "province": 0}),
		"the court would land the host at %s" % coast
	)
	assert_eq(MapPlayExpeditionPick.words(model, {"kind": "beachhead"}), "", "no coast, no line")
	assert_eq(MapPlayExpeditionPick.words(model, {"kind": "sail"}), "", "no water, no line")
	assert_eq(
		MapPlayExpeditionPick.words(model, {"kind": "embark", "province": 0}), "",
		"boarding is a sail the naval pick words, not a step of hers"
	)
	assert_eq(MapPlayExpeditionPick.words(model, {}), "", "no step, no words")
	assert_eq(
		MapPlayExpeditionPick.words(null, {"kind": "land", "province": 0}), "",
		"no chart, no words"
	)


## The coast the published policy would mark beside her is read as the step and
## its row, and the reading marks nothing on the chart or the squadron.
func test_the_expedition_reads_the_coast_the_policy_would_mark() -> void:
	var world: WorldMap = _expedition_world()
	var pair: Dictionary = _expedition_pair()
	var play: PlaySession = _expedition_play(
		world, WorldMap.NEW_WORLD, pair["fleet"], pair["army"]
	)
	var fleet: FleetState = pair["fleet"]
	var coast: String = world.region(WorldMap.NEW_WORLD).province_name(0)

	var pick: Dictionary = MapPlayExpeditionPick.pick(play, fleet)

	assert_eq(String(pick.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD, "the site")
	assert_eq(int(pick.get("province", -1)), 0, "the Tribe's coast")
	assert_eq(
		String(pick.get("line", "")),
		"the court would mark a beachhead on the coast of %s — the landing opens next turn"
			% coast
	)
	assert_eq(MapPlayExpeditionPick.marked_coast(pick), 0, "the row the line names")
	assert_eq(
		MapPlayExpeditionPick.line(play, fleet),
		"The court would mark a beachhead on the coast of %s — the landing opens next turn."
			% coast,
		"one sentence, capital and full stop"
	)
	assert_false(fleet.has_beachhead(), "a reading marks no site")
	assert_false(fleet.moved, "and sails nothing")
	play.ship_layer.free()
	play.army_layer.free()


## Home waters: the policy's next step is the Passage, and the line says so.
func test_the_expedition_reads_the_crossing_it_would_make() -> void:
	var world: WorldMap = _expedition_world()
	var pair: Dictionary = _expedition_pair()
	var play: PlaySession = _expedition_play(
		world, WorldMap.OLD_WORLD, pair["fleet"], pair["army"]
	)

	var pick: Dictionary = MapPlayExpeditionPick.pick(play, pair["fleet"])

	assert_eq(String(pick.get("kind", "")), AiInvasionPlanner.KIND_CROSS)
	assert_eq(String(pick.get("line", "")), "the court would cross the Passage with the host aboard")
	assert_eq(MapPlayExpeditionPick.marked_coast(pick), -1, "a crossing marks no coast")
	play.ship_layer.free()
	play.army_layer.free()


## A ready site: the step is the landing it opens, and the site it names is
## already marked, so it is no row.
func test_the_expedition_reads_the_landing_the_site_opens() -> void:
	var world: WorldMap = _expedition_world()
	var pair: Dictionary = _expedition_pair()
	var fleet: FleetState = pair["fleet"]
	fleet.beachhead_province = 0
	fleet.beachhead_turn = 0
	var play: PlaySession = _expedition_play(world, WorldMap.NEW_WORLD, fleet, pair["army"])
	play.turn = 1

	var pick: Dictionary = MapPlayExpeditionPick.pick(play, fleet)

	assert_eq(String(pick.get("kind", "")), AiInvasionPlanner.KIND_LAND)
	assert_eq(int(pick.get("province", -1)), 0)
	assert_eq(
		String(pick.get("line", "")),
		"the court would land the host at %s"
			% world.region(WorldMap.NEW_WORLD).province_name(0)
	)
	assert_eq(MapPlayExpeditionPick.marked_coast(pick), -1, "the site is no row")
	assert_eq(fleet.embarked_army, (pair["army"] as ArmyState).id, "a reading lands nobody")
	play.ship_layer.free()
	play.army_layer.free()


## The reading is only for the squadron the court would still plan: a squadron
## with no host aboard belongs to the naval pick, a rival answers to her own
## court, a hull that has sailed keeps her step, a second expedition is not the
## one the pass steers, and a session with no planner or no host roster reads
## nothing.
func test_the_expedition_pick_names_no_squadron_the_court_would_leave_alone() -> void:
	var world: WorldMap = _expedition_world()
	var pair: Dictionary = _expedition_pair()
	var play: PlaySession = _expedition_play(
		world, WorldMap.NEW_WORLD, pair["fleet"], pair["army"]
	)
	var fleet: FleetState = pair["fleet"]
	assert_false(MapPlayExpeditionPick.pick(play, fleet).is_empty(), "the expedition takes a step")
	assert_true(MapPlayExpeditionPick.pick(play, null).is_empty(), "no squadron, no pick")
	assert_true(MapPlayExpeditionPick.pick(null, fleet).is_empty(), "no session, no pick")

	var empty: FleetState = FleetState.at_sea(2, MapScreen.PLAYER_FACTION, 0, ["h2"], {"h2": "frigate"})
	play.ship_layer.regions.set_region(WorldMap.NEW_WORLD, [fleet, empty])
	assert_true(
		MapPlayExpeditionPick.pick(play, empty).is_empty(),
		"a squadron with no host aboard is the naval pick's"
	)
	var rival: FleetState = FleetState.at_sea(3, 2, 0, ["h3"], {"h3": "frigate"})
	rival.embarked_army = (pair["army"] as ArmyState).id
	play.ship_layer.regions.set_region(WorldMap.NEW_WORLD, [fleet, rival])
	assert_true(MapPlayExpeditionPick.pick(play, rival).is_empty(), "a rival answers to her own court")
	play.ship_layer.regions.set_region(WorldMap.NEW_WORLD, [fleet])

	fleet.moved = true
	assert_true(
		MapPlayExpeditionPick.pick(play, fleet).is_empty(),
		"a hull that has sailed is not re-planned"
	)
	fleet.moved = false

	var second: FleetState = FleetState.at_sea(2, MapScreen.PLAYER_FACTION, 0, ["h2"], {"h2": "frigate"})
	second.embarked_army = (pair["army"] as ArmyState).id
	play.ship_layer.regions.set_region(WorldMap.NEW_WORLD, [fleet, second])
	assert_true(
		MapPlayExpeditionPick.pick(play, second).is_empty(),
		"the pass steers one expedition a court"
	)
	play.ship_layer.regions.set_region(WorldMap.NEW_WORLD, [fleet])

	play.ai_mode = AiControl.NOOP
	assert_true(MapPlayExpeditionPick.pick(play, fleet).is_empty(), "no planner, no advice")
	play.ai_mode = AiControl.FULL
	play.observer_mode = true
	assert_true(MapPlayExpeditionPick.pick(play, fleet).is_empty(), "an observer has no crown's page")
	play.observer_mode = false
	play.campaign_halted = true
	assert_true(
		MapPlayExpeditionPick.pick(play, fleet).is_empty(),
		"a decided campaign orders nothing"
	)
	play.campaign_halted = false
	play.army_layer.free()
	play.army_layer = null
	assert_true(MapPlayExpeditionPick.pick(play, fleet).is_empty(), "no host roster, no reading")
	play.ship_layer.free()

# --- folded: naval rules (one boot with fleet orders) -------------------
## Pure sea rules that used to pay their own coverage Godot boot
## (~40 s under instrumentation). They share this suite's process; live
## fleet cases keep the mounted chart above.

const fleet_names_NavalFixture = preload("res://tests/naval_fixture.gd")
const naval_transport_AiFixture = preload("res://tests/ai_fixture.gd")
const fleet_rosters_NavalFixture = preload("res://tests/naval_fixture.gd")
const fleet_sortie_NavalFixture = preload("res://tests/naval_fixture.gd")
const fleet_missions_NavalFixture = preload("res://tests/naval_fixture.gd")
const naval_retreat_NavalFixture = preload("res://tests/naval_fixture.gd")
const naval_port_loss_Fixture = preload("res://tests/naval_fixture.gd")
const naval_interception_NavalFixture = preload("res://tests/naval_fixture.gd")

const FACTIONS: Array[String] = ["España", "England", "France", "Portugal"]
const SEAT: int = 0
const HARBOUR: int = 1

var _econ: PlayerEconomy
var _fleet_names_econ: PlayerEconomy
var _markers: ShipMarkers = null
var _fleet_sortie_model: MapModel = null
var _fleet_missions_model: MapModel = null
var _naval_retreat_model: MapModel = null
var _naval_interception_model: MapModel = null

func _setup_fleet_yard() -> void:
	_suite_setup = "fleet_yard"
	_econ = PlayerEconomy.starting()
	_econ.treasury = 60000

func _setup_fleet_names() -> void:
	_suite_setup = "fleet_names"
	_fleet_names_econ = PlayerEconomy.starting()
	_fleet_names_econ.treasury = 60000

func _setup_fleet_rosters() -> void:
	_suite_setup = "fleet_rosters"
	_markers = ShipMarkers.new()
	_markers.model = fleet_rosters_NavalFixture.build()

func _setup_fleet_sortie() -> void:
	_suite_setup = "fleet_sortie"
	_fleet_sortie_model = fleet_sortie_NavalFixture.build()

func _setup_fleet_missions() -> void:
	_suite_setup = "fleet_missions"
	_fleet_missions_model = fleet_missions_NavalFixture.build()

func _setup_naval_retreat() -> void:
	_suite_setup = "naval_retreat"
	_naval_retreat_model = naval_retreat_NavalFixture.build()

func _setup_naval_interception() -> void:
	_suite_setup = "naval_interception"
	_naval_interception_model = naval_interception_NavalFixture.build()

func _teardown_fleet_rosters() -> void:
	_markers.clear()
	_markers = null

# --- test_fleet_yard ---

func test_launch_pays_the_row_and_one_peasant() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	var treasury: int = _econ.treasury
	var peasants: int = _econ.available_peasants()
	var lumber: int = _econ.quantity("lumber")
	var fabric: int = _econ.quantity("fabric")

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.hulls, ["ship_9"])
	assert_eq(fleet.type_of("ship_9"), "carrack")
	assert_eq(_econ.treasury, treasury - ShipEconomy.treasury_cost("carrack"))
	assert_eq(_econ.available_peasants(), peasants - 1)
	assert_eq(_econ.quantity("lumber"), lumber - 2)
	assert_eq(_econ.quantity("fabric"), fabric - 1)

func test_a_locked_hull_names_its_tech_and_spends_nothing() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	var treasury: int = _econ.treasury
	var peasants: int = _econ.available_peasants()

	var result: Dictionary = FleetYard.launch(_econ, fleet, "frigate", "ship_9")

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("Requires"))
	assert_true(String(result["reason"]).contains("Advanced Hull Design"))
	assert_eq(fleet.ship_count(), 0)
	assert_eq(_econ.treasury, treasury)
	assert_eq(_econ.available_peasants(), peasants)

func test_research_unlocks_the_hull() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.tech_unlocked["advanced_hull_design"] = true

	var result: Dictionary = FleetYard.launch(_econ, fleet, "frigate", "ship_9")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.type_of("ship_9"), "frigate")

func test_no_peasant_refuses_the_launch_and_spends_nothing() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	var treasury: int = _econ.treasury

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient workers")
	assert_eq(fleet.ship_count(), 0)
	assert_eq(_econ.treasury, treasury)

func test_insufficient_materials_refuse_the_launch() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.stockpile["lumber"] = 1

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient materials")
	assert_eq(fleet.ship_count(), 0)

func test_the_breaker_yard_returns_one_peasant() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1", "ship_2"], {"ship_2": "sloop"})
	var peasants: int = _econ.available_peasants()

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_2")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.hulls, ["ship_1"])
	assert_eq(_econ.available_peasants(), peasants + 1)
	assert_false(bool(result["retired"]))
	assert_eq(_econ.treasury, 60000, "no treasury is refunded")

func test_breaking_up_the_last_hull_retires_the_squadron() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1"])

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_1")

	assert_true(bool(result["ok"]))
	assert_true(bool(result["retired"]))
	assert_false(fleet.is_afloat())

func test_a_hull_must_belong_to_the_fleet() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1"])

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_99")

	assert_false(bool(result["ok"]))
	assert_eq(fleet.hulls, ["ship_1"])

func test_rows_lead_with_payable_hulls_and_reason_the_locked_ones() -> void:
	_setup_fleet_yard()
	var rows: Array[Dictionary] = FleetYard.rows(_econ, true)

	assert_eq(rows.size(), ShipEconomy.ENTRIES.size())
	assert_true(bool(rows[0]["ok"]), "a payable row leads the yard")
	var locked: int = 0
	for row: Dictionary in rows:
		if not bool(row["ok"]):
			locked += 1
			assert_false(String(row["reason"]).is_empty())
	assert_gt(locked, 0, "era hulls stay locked without research")

## A court flies a hull her studies never opened — the opening muster's Fluyte —
## so the yard offers her without the tech, the same gate the rival courts read
## (issue #484; REQ-P2-03).
func test_a_flown_hull_stays_on_the_slip_without_her_tech() -> void:
	_setup_fleet_yard()
	var by_type: Dictionary = {}
	for row: Dictionary in FleetYard.rows(_econ, true, ["fluyte"]):
		by_type[String(row["type_id"])] = row

	assert_true(bool((by_type["fluyte"] as Dictionary)["ok"]), "her own craft is on the slip")
	assert_false(bool((by_type["frigate"] as Dictionary)["ok"]), "a hull never flown waits")

func test_an_absent_home_port_blocks_every_row() -> void:
	_setup_fleet_yard()
	var rows: Array[Dictionary] = FleetYard.rows(_econ, false)

	for row: Dictionary in rows:
		assert_false(bool(row["ok"]))
		assert_eq(String(row["reason"]), "Launch hulls at your capital port.")

## The yard's one press walks the slip's order and reserves what each hull order
## spends, so a press never files a launch the Build/work pass would refuse
## (REQ-P2-03, REQ-P5-04; DR-20261118-08).
func test_the_yard_batch_reserves_the_ledger_each_hull_spends() -> void:
	_setup_fleet_yard()
	_econ.tech_unlocked["superior_hull_design"] = true
	var types: Array[String] = ["carrack", "fluyte"]

	var result: Dictionary = FleetYard.queue_all(_econ, true, types)

	assert_eq(int(result["filed"]), 2, "every payable hull files")
	assert_eq(String(result["refusal"]), "", "nothing is refused")
	assert_eq(
		_econ.recruits.pending_kind(RecruitQueue.KIND_SHIP), 2, "one order per hull"
	)
	assert_eq(
		_econ.available_peasants(),
		PlayerEconomy.START_PEASANTS - 2,
		"each hull reserves her peasant"
	)

	# Cash: the carrack's price leaves the fluyte short.
	_econ = PlayerEconomy.starting()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.treasury = ShipEconomy.treasury_cost("carrack")
	result = FleetYard.queue_all(_econ, true, types)
	assert_eq(int(result["filed"]), 1, "only what the purse covers")
	assert_eq(String(result["refusal"]), "Insufficient treasury")

	# Materials: the carrack takes the last bolt of cloth.
	_econ = PlayerEconomy.starting()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.treasury = 60000
	_econ.stockpile["fabric"] = 1
	result = FleetYard.queue_all(_econ, true, types)
	assert_eq(int(result["filed"]), 1, "only what the stores cover")
	assert_eq(String(result["refusal"]), "Insufficient materials")

	# Hands: the queue reserves the peasant, so the second hull finds none.
	_econ = PlayerEconomy.starting()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.treasury = 60000
	_econ.workers = WorkerPool.make(1)
	result = FleetYard.queue_all(_econ, true, types)
	assert_eq(int(result["filed"]), 1, "only what the pool covers")
	assert_eq(String(result["refusal"]), "Insufficient workers")

## The slip's one press reads only rows no waiting order claims, and only at the
## crown's own capital port, so a second press never doubles a hull already under
## orders (DR-20261118-08).
func test_the_yard_batch_skips_a_hull_already_under_orders() -> void:
	_setup_fleet_yard()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.queue_build(RecruitQueue.KIND_SHIP, "carrack")

	var ready: Array[String] = FleetYard.batch_types(_econ, true)

	assert_false(ready.has("carrack"), "a hull under orders is not re-filed")
	assert_true(ready.has("fluyte"), "a row nothing claims still stands ready")
	assert_true(FleetYard.batch_types(_econ, false).is_empty(), "no slip away from home")
	var away: Dictionary = FleetYard.queue_all(_econ, false, ["fluyte"])
	assert_eq(int(away["filed"]), 0, "nothing is laid down away from home")
	assert_eq(String(away["refusal"]), FleetYard.NOT_AT_HOME, "the gate speaks its row's words")

func test_every_hull_names_a_real_tech_or_none() -> void:
	_setup_fleet_yard()
	for type_id: String in ShipEconomy.ENTRIES.keys():
		var tech: String = ShipEconomy.tech_for(type_id)
		if type_id == "carrack":
			assert_eq(tech, "", "the carrack never needs research")
			continue
		assert_false(tech.is_empty(), type_id)
		assert_true(TechCatalog.known(tech), tech)

func test_cost_text_reads_as_a_yard_ledger() -> void:
	_setup_fleet_yard()
	var text: String = ShipEconomy.cost_text("carrack")

	assert_true(text.contains("8,000 ducats"))
	assert_true(text.contains("2 Lumber"))
	assert_true(text.contains("1 Fabric"))
	assert_true(text.contains("1 worker"))

func test_hull_firepower_sums_into_ship_strength() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1", "ship_2"], {"ship_2": "sloop"})

	assert_eq(ShipStats.firepower("carrack"), 2)
	assert_eq(ShipStats.firepower("sloop"), 2)
	# The dossier's strength is the resolver's weighted figure, never Σ FRP: a
	# carrack is 2.75 and a sloop 3.25 (wiki: § Naval Strength Aggregation).
	assert_almost_eq(NavalStrength.strength(fleet), 6.0, 0.0001)
	assert_almost_eq(NavalStrength.strength(null), 0.0, 0.0001)
	assert_almost_eq(NavalCombat.side_strength([fleet]), 6.0, 0.0001)

# --- test_fleet_yard_block ---

func _rows() -> Array[Dictionary]:
	return [
		{
			"type_id": "carrack",
			"name": "Carrack",
			"cost_text": "8000",
			"ok": true,
			"reason": "",
		},
		{
			"type_id": "frigate",
			"name": "Frigate",
			"cost_text": "",
			"ok": false,
			"reason": "no peasants",
		},
	]

## Every button whose face starts with `prefix`; `exact` keeps only a button
## whose face is the prefix itself, so the slip's own row presses can be read
## apart from the one batch press under them (DR-20261118-08).
func _buttons(block: FleetYardBlock, prefix: String, exact: bool = false) -> Array[String]:
	var out: Array[String] = []
	for node: Node in block.find_children("*", "Button", true, false):
		var text: String = (node as Button).text
		if text.begins_with(prefix) and (not exact or text == prefix):
			out.append(text)
	return out

func test_the_slip_lists_launches_and_opens_at_once() -> void:
	var block := FleetYardBlock.new()
	add_child(block)

	block.show_slip(_rows(), true)

	assert_true(block._button.visible, "a player with rows gets the yard")
	assert_true(block._open, "the capital slip opens the drawer")
	assert_eq(block._button.text, "Close shipyard")
	assert_eq(_buttons(block, "Launch", true), ["Launch", "Launch"], "one press per hull")
	# The slip's own one press stands hidden while nothing on it is ready.
	assert_eq(_buttons(block, "Launch all ready"), ["Launch all ready (0)"])
	assert_false((block._batch as Control).visible, "nothing ready, no batch press")
	block.free()

func test_a_foreign_yard_shows_nothing() -> void:
	var block := FleetYardBlock.new()
	add_child(block)

	block.show_slip(_rows(), false)

	assert_false(block._button.visible, "no orders for another crown")
	assert_false(block._scroll.visible)
	block.free()

func test_a_join_hides_the_yard_and_keeps_the_rows() -> void:
	var block := FleetYardBlock.new()
	add_child(block)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	block.show_rows(fleet, _rows(), true, true)
	assert_true(block._open, "the fleet opens on the yard")
	block.set_offer_join(true)

	assert_false(block._button.visible, "the join takes the yard's place")
	assert_false(block._scroll.visible, "a hidden drawer takes no height")
	assert_eq(block._rows.size(), 2, "the rows stay for when the join is passed")
	block.free()

func test_a_scrap_asks_once_then_emits() -> void:
	var block := FleetYardBlock.new()
	add_child(block)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var emitted: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: emitted.append(action))
	block.show_rows(fleet, _rows(), true, true)

	block.on_scrap_pressed("ship_1")

	assert_eq(block._arm.key(), "ship_1", "the first tap arms")
	assert_eq(emitted, [] as Array[String], "arming sends nothing")

	block.on_scrap_pressed("ship_1")

	assert_eq(emitted, ["yard:scrap:ship_1"])
	assert_eq(block._arm.key(), "", "a confirmed scrap clears the arm")
	block.free()

# --- test_fleet_names ---

func test_a_launch_christens_the_hull_from_its_crown() -> void:
	_setup_fleet_names()
	var fleet := FleetState.empty_in_port(3, 0, 1)

	var result: Dictionary = FleetYard.launch(_fleet_names_econ, fleet, "carrack", "ship_1")

	assert_true(bool(result["ok"]), String(result["reason"]))
	var name: String = String(result["name"])
	assert_true(
		ShipNames.pool_for(0).has(name),
		"Spain christens from its own pool, got '%s'" % name
	)
	assert_eq(ShipNames.of(fleet, "ship_1"), name, "the name is kept on the hull")

func test_the_same_crown_squadron_and_hull_always_name_alike() -> void:
	_setup_fleet_names()
	var first := FleetState.empty_in_port(3, 0, 1)
	var second := FleetState.empty_in_port(3, 0, 1)

	first.add_hull("ship_7", "carrack")
	second.add_hull("ship_7", "carrack")

	assert_eq(ShipNames.of(first, "ship_7"), ShipNames.of(second, "ship_7"))
	assert_true(
		ShipNames.pool_for(0).has(ShipNames.of(first, "ship_7")),
		"a reloaded fleet speaks the same name"
	)

func test_a_squadron_never_flies_the_same_name_twice() -> void:
	_setup_fleet_names()
	var fleet := FleetState.empty_in_port(3, 0, 1)
	for index in range(14):
		fleet.add_hull("ship_%d" % index, "carrack")

	var names: Array[String] = []
	var numbered: bool = false
	for hull_id: String in fleet.hulls:
		var name: String = ShipNames.of(fleet, hull_id)
		assert_false(name.is_empty())
		assert_false(names.has(name), "'%s' flies twice" % name)
		if name.ends_with(" II"):
			numbered = true
		names.append(name)
	assert_eq(names.size(), fleet.ship_count())
	# Past the ten-name pool the repeats are numbered, never duplicated.
	assert_true(numbered, "a repeat is numbered, not duplicated")

func test_a_crown_with_no_pool_still_names_its_hulls() -> void:
	_setup_fleet_names()
	var fleet := FleetState.empty_in_port(2, 9, 5)
	fleet.add_hull("ship_1", "sloop")

	assert_true(ShipNames.GENERIC.has(ShipNames.of(fleet, "ship_1")))

func test_a_saved_hull_keeps_the_name_it_was_given() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 1, 4, ["ship_2", "ship_5"], {})
	var before: Dictionary = {}
	for hull_id: String in fleet.hulls:
		before[hull_id] = ShipNames.of(fleet, hull_id)

	var restored: FleetState = FleetState.from_dict(fleet.to_dict())

	for hull_id: String in restored.hulls:
		assert_eq(ShipNames.of(restored, hull_id), String(before[hull_id]))
	assert_eq(restored.to_dict()["hull_names"], fleet.to_dict()["hull_names"])

func test_a_hull_saved_before_names_existed_is_christened_on_load() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 1, 4, ["ship_2", "ship_5"], {})
	var legacy: Dictionary = fleet.to_dict()
	legacy.erase("hull_names")

	var restored: FleetState = FleetState.from_dict(legacy)

	assert_eq(restored.ship_count(), 2)
	for hull_id: String in restored.hulls:
		assert_eq(
			ShipNames.of(restored, hull_id),
			ShipNames.of(fleet, hull_id),
			"the load speaks the name the hull would have flown"
		)

func test_a_merge_keeps_every_hull_name() -> void:
	_setup_fleet_names()
	var home := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var returning := FleetState.at_sea(5, 1, 2, ["ship_4"], {})
	var expected: String = ShipNames.of(returning, "ship_4")
	var home_name: String = ShipNames.of(home, "ship_1")

	home.merge_from(returning)

	assert_eq(ShipNames.of(home, "ship_4"), expected)
	assert_eq(ShipNames.of(home, "ship_1"), home_name)

## Two squadrons christen apart, so a merge can put one name on two hulls: the
## hull that already flew it keeps it and the joined hull gives way, because a
## squadron's names are pairwise distinct (wiki: naming § Ship names;
## DR-20261111-07). Playtest: a hull launched at the seat while the home squadron
## was at sea founded a new home fleet, and the returning squadron merged into
## her — the squadron then flew two hulls named "San Mateo".
func test_a_merge_never_puts_one_name_on_two_hulls() -> void:
	_setup_fleet_names()
	var home := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var returning := FleetState.at_sea(5, 1, 2, ["ship_4"], {})
	home.hull_names["ship_1"] = "San Mateo"
	returning.hull_names["ship_4"] = "San Mateo"

	home.merge_from(returning)

	assert_eq(ShipNames.of(home, "ship_1"), "San Mateo", "the receiving hull keeps her name")
	var settled: String = ShipNames.of(home, "ship_4")
	assert_ne(settled, "San Mateo", "the joined hull gives way to the name she joined")
	assert_true(
		ShipNames.pool_for(home.owner).has(settled), "she takes a name from her crown's pool"
	)
	assert_eq(
		String(home.hull_names.get("ship_4", "")), settled,
		"the settled name is written to the squadron, so a reload speaks it"
	)
	var restored: FleetState = FleetState.from_dict(home.to_dict())
	assert_eq(ShipNames.of(restored, "ship_4"), settled, "the save carries the settled name")
	# The same merge settles alike: the joined hull does not draw a new name on
	# every load or every fight (wiki: naming § Ship names — deterministic).
	var again_home := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var again_returning := FleetState.at_sea(5, 1, 2, ["ship_4"], {})
	again_home.hull_names["ship_1"] = "San Mateo"
	again_returning.hull_names["ship_4"] = "San Mateo"
	again_home.merge_from(again_returning)
	assert_eq(ShipNames.of(again_home, "ship_4"), settled, "the same merge settles alike")

## A save written while two hulls of one squadron shared a name is repaired on
## load, the way it repairs a hull that carries no name at all (wiki: naming
## § Ship names — the N hulls a squadron flies have N pairwise distinct names).
func test_a_save_with_two_hulls_of_one_name_is_settled_on_load() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 1, 4, ["ship_2", "ship_5"], {})
	var saved: Dictionary = fleet.to_dict()
	saved["hull_names"] = {"ship_2": "Trinidad", "ship_5": "Trinidad"}

	var restored: FleetState = FleetState.from_dict(saved)

	assert_eq(ShipNames.of(restored, "ship_2"), "Trinidad", "the first hull keeps the name")
	assert_ne(ShipNames.of(restored, "ship_5"), "Trinidad", "the second hull is christened again")
	assert_true(ShipNames.pool_for(restored.owner).has(ShipNames.of(restored, "ship_5")))

func test_scrapping_names_the_hull_it_breaks() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 0, 1, ["ship_1", "ship_2"], {})
	var doomed: String = ShipNames.of(fleet, "ship_2")

	var result: Dictionary = FleetYard.scrap(_fleet_names_econ, fleet, "ship_2")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(String(result["name"]), doomed)
	assert_false(fleet.hull_names.has("ship_2"), "a broken hull keeps no name")

func test_an_unnamed_hull_reads_a_name_without_a_write() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 0, 1, [], {})
	fleet.hulls.append("ship_9")
	fleet.hull_types["ship_9"] = "carrack"

	var name: String = ShipNames.of(fleet, "ship_9")

	assert_false(name.is_empty())
	assert_false(fleet.hull_names.has("ship_9"), "a read never stores work of its own")

## The dossier's own line counts hulls in the singular when it carries one: "1
## ship", never "1 ships" (REQ-P1-07, read at a phone's size).
func test_the_dossier_counts_one_hull_in_the_singular() -> void:
	_setup_fleet_names()
	var panel := FleetPanel.new()
	add_child(panel)
	var fleet := FleetState.in_port(3, 1, 0, ["ship_1"], {})

	panel.refresh(fleet_names_NavalFixture.build(), FleetDossierOpening.of(fleet, true))

	var line: String = ""
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains("Carrack") and text.contains("upkeep"):
			line = text
	assert_true(line.begins_with("1 ship · "), "the dossier reads '%s'" % line)

	var carried := FleetDossierOpening.of(fleet, true)
	carried.carried = 1
	carried.crew = {"count": 1}
	panel.refresh(fleet_names_NavalFixture.build(), carried)
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains("carrying"):
			line = text
	assert_true(line.contains("carrying 1 regiment · 1 colonist"), "the dossier reads '%s'" % line)
	panel.free()

## The deck prices the room a boarding leaves: one hull carries one regiment or
## one colonist, so a sheet counts what the hulls are not already carrying
## (wiki: ships-and-naval § Naval transport, § Civilian passengers;
## DR-20261124-14).
func test_the_deck_reads_the_room_a_boarding_leaves() -> void:
	var fleet := FleetState.in_port(3, 1, 0, ["ship_1", "ship_2", "ship_3"], {})

	var empty: Dictionary = DeckRead.read(fleet)
	assert_eq(int(empty["hulls"]), 3)
	assert_eq(int(empty["free"]), 3)
	assert_eq(DeckRead.room_text(empty), "room for 3 more")
	assert_eq(DeckRead.deck_text(empty), "3 hulls, all free")

	fleet.add_civilian(11)
	var one: Dictionary = DeckRead.read(fleet, 1)
	assert_eq(int(one["aboard"]), 2, "a regiment and a colonist take two berths")
	assert_eq(int(one["free"]), 1)
	assert_eq(DeckRead.room_text(one), "room for 1 more")
	assert_eq(DeckRead.deck_text(one), "3 hulls, 1 free")

	var over: Dictionary = DeckRead.read(fleet, 5)
	assert_eq(int(over["free"]), 0, "a deck is never read past its hulls")
	assert_eq(DeckRead.room_text(over), "no room aboard")
	assert_eq(DeckRead.deck_text(over), "3 hulls, no room aboard")

	var none: Dictionary = DeckRead.read(null)
	assert_false(bool(none["known"]), "no squadron, no deck")
	assert_eq(DeckRead.room_text(none), "", "an unknown deck prints nothing")
	assert_eq(DeckRead.deck_text(none), "")

	# A squadron the sea has emptied keeps no deck to read.
	var bare := FleetState.new()
	bare.id = 4
	bare.owner = 1
	assert_false(bool(DeckRead.read(bare)["known"]), "a squadron with no hull has no deck")
	assert_eq(DeckRead.room_text(DeckRead.read(bare)), "", "and prints no room")


## The dossier's own line names the room her hulls leave, so a crown reads what a
## host or a colonist still fits before she orders either aboard (wiki:
## ships-and-naval § Naval transport; DR-20261124-14).
func test_the_dossier_names_the_room_aboard() -> void:
	_setup_fleet_names()
	var panel := FleetPanel.new()
	add_child(panel)
	var fleet := FleetState.in_port(3, 1, 0, ["ship_1", "ship_2"], {})

	panel.refresh(fleet_names_NavalFixture.build(), FleetDossierOpening.of(fleet, true))
	assert_true(_muster_text(panel).contains("room for 2 more"), _muster_text(panel))

	var carried := FleetDossierOpening.of(fleet, true)
	carried.carried = 2
	panel.refresh(fleet_names_NavalFixture.build(), carried)
	assert_true(_muster_text(panel).contains("no room aboard"), _muster_text(panel))
	panel.free()


## The composition line naming the hulls and the food they eat.
func _muster_text(panel: FleetPanel) -> String:
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains("upkeep"):
			return text
	return ""

## The dossier names the hull, and the break-up confirmation names what it breaks
## (REQ-P1-03, REQ-P5-04).
func test_the_dossier_and_the_break_up_name_the_hull() -> void:
	_setup_fleet_names()
	var panel := FleetPanel.new()
	add_child(panel)
	var fleet := FleetState.in_port(3, 1, 0, ["ship_1"], {})
	var hull_name: String = ShipNames.of(fleet, "ship_1")
	var rows: Array[Dictionary] = [
		{
			"type_id": "carrack",
			"name": "Carrack",
			"cost_text": "8000",
			"ok": true,
			"reason": "",
		},
	]

	var yarded := FleetDossierOpening.of(fleet, true)
	yarded.yard_rows = rows
	panel.refresh(fleet_names_NavalFixture.build(), yarded)
	panel.set_yard_open(true)

	var printed: bool = false
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains(hull_name) and text.contains("Carrack"):
			printed = true
	assert_true(printed, "the hull row prints '%s — Carrack'" % hull_name)

	var confirm: Button = null
	for node: Node in panel.find_children("*", "Button", true, false):
		if (node as Button).text == "Break up":
			confirm = node as Button
	assert_not_null(confirm, "the hull offers a break-up")
	panel._on_scrap_pressed("ship_1")
	for node: Node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "Confirm scrap":
			confirm = button
	assert_eq(confirm.text, "Confirm scrap", "the first tap only arms")
	assert_true(
		confirm.tooltip_text.contains(hull_name),
		"the confirmation names the hull: '%s'" % confirm.tooltip_text
	)
	panel.free()

# --- test_fleet_rosters ---

func _regions() -> MapRegionTable:
	var regions := MapRegionTable.new()
	regions.set_region(0, [
		FleetState.at_sea(0, 1, 0, ["a", "b"]), FleetState.in_port(1, 1, 2, ["c"])
	])
	regions.set_region(1, [FleetState.at_sea(4, 2, 5, ["d"])])
	return regions

func test_every_region_contributes_to_the_hull_count() -> void:
	_setup_fleet_rosters()
	var regions := _regions()
	assert_eq(FleetRosters.hulls_afloat(regions, 1), 3)
	assert_eq(FleetRosters.hulls_afloat(regions, 2), 1)
	assert_eq(FleetRosters.hulls_afloat(MapRegionTable.new(), 1), 0)

func test_next_id_avoids_ids_used_in_any_region() -> void:
	_setup_fleet_rosters()
	var regions := _regions()
	assert_eq(FleetRosters.next_id_all(regions), 5)
	assert_eq(FleetRosters.next_id_all(MapRegionTable.new()), 0)

func test_all_returns_one_typed_roster_per_region() -> void:
	_setup_fleet_rosters()
	var regions := _regions()
	var rosters: Array[Array] = FleetRosters.all(regions)
	assert_eq(rosters.size(), 2)
	assert_eq(rosters[1].size(), 1)

## A passenger's seat is read from the squadron that lists it — a sunken or
## missing squadron keeps none (wiki: ships-and-naval § Naval transport).
func test_carried_seats_come_from_the_squadron_rosters() -> void:
	_setup_fleet_rosters()
	var regions := MapRegionTable.new()
	var crowded := FleetState.at_sea(0, 1, 0, ["a", "b"])
	crowded.add_civilian(7)
	crowded.embarked_army = 11
	var sunk := FleetState.empty_in_port(3, 1, 2)
	sunk.add_civilian(8)
	sunk.embarked_army = 12
	regions.set_region(0, [crowded, null, sunk])
	var other := FleetState.in_port(4, 2, 2, ["d"])
	other.add_civilian(9)
	regions.set_region(1, [other])

	assert_eq(
		FleetRosters.carried_civilians(regions), {7: 0, 9: 4},
		"a sunk hull's passenger has no seat"
	)
	assert_eq(FleetRosters.carried_armies(regions), {11: 0})
	assert_eq(FleetRosters.carried_civilians(MapRegionTable.new()), {})

func test_removing_the_selected_marker_clears_the_selection() -> void:
	_setup_fleet_rosters()
	var fleet := FleetState.at_sea(3, 1, 0)
	var ship: Ship = _markers.make(fleet)
	_markers.selected_ship = ship
	_markers.remove(ship)
	assert_eq(_markers.ships.size(), 0)
	assert_null(_markers.selected_ship)
	assert_eq(_markers.find(3), null)

func test_clear_frees_every_marker() -> void:
	_setup_fleet_rosters()
	_markers.make(FleetState.at_sea(0, 1, 0))
	_markers.make(FleetState.in_port(1, 2, 2))
	_markers.selected_ship = _markers.ships[0]
	_markers.clear()
	assert_eq(_markers.ships.size(), 0)
	assert_null(_markers.selected_ship)

# --- test_fleet_sortie ---

func _home() -> FleetState:
	return FleetState.in_port(
		1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"}
	)

func test_the_home_squadron_may_only_sail_from_its_capital() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	var at_sea: FleetState = FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	var outside: FleetState = FleetState.in_port(3, 0, 1, ["d"], {"d": "fluyte"})

	assert_true(NavalMovement.is_home_fleet(_fleet_sortie_model, home))
	assert_eq(FleetSortie.zones(_fleet_sortie_model, home), [0])
	assert_true(bool(FleetSortie.can_sortie(_fleet_sortie_model, home, 0)["ok"]))
	assert_false(bool(FleetSortie.can_sortie(_fleet_sortie_model, at_sea, 0)["ok"]))
	assert_false(bool(FleetSortie.can_sortie(_fleet_sortie_model, outside, 0)["ok"]))
	assert_eq(FleetSortie.zones(_fleet_sortie_model, at_sea), [] as Array[int])

func test_a_sortie_needs_a_move_a_hull_and_a_bordering_zone() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	home.moved = true
	assert_true(String(FleetSortie.can_sortie(_fleet_sortie_model, home, 0)["reason"]).contains("already sailed"))

	var empty: FleetState = FleetState.empty_in_port(4, 0, 0)
	assert_true(String(FleetSortie.can_sortie(_fleet_sortie_model, empty, 0)["reason"]).contains("no hulls"))

	var fresh: FleetState = _home()
	assert_true(String(FleetSortie.can_sortie(_fleet_sortie_model, fresh, 1)["reason"]).contains("does not border"))
	assert_false(bool(FleetSortie.can_sortie(null, fresh, 0)["ok"]))

func test_the_sortie_spends_the_move_and_turns_home_into_a_normal_squadron() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	var result: Dictionary = FleetSortie.apply(_fleet_sortie_model, home, 0)

	assert_true(bool(result["ok"]))
	assert_true(home.is_at_sea())
	assert_eq(home.sea_zone, 0)
	assert_eq(home.province, MapModel.NO_ID)
	assert_true(home.moved)
	assert_false(NavalMovement.is_home_fleet(_fleet_sortie_model, home))

func test_the_home_holds_leave_with_the_squadron_and_return_when_it_moors() -> void:
	_setup_fleet_sortie()
	var world := WorldMap.new()
	world.add_region(_fleet_sortie_model)
	var home: FleetState = _home()
	var fleets: Dictionary = {0: [home]}

	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)

	FleetSortie.apply(_fleet_sortie_model, home, 0)
	assert_eq(TradeCargo.capacity(world, fleets, 0), 0, "at sea the holds are away")

	NavalMovement.begin_turn([home])
	assert_true(bool(NavalMovement.apply_move(
		_fleet_sortie_model, home, FleetState.Location.IN_PORT, 0
	)["ok"]))
	assert_true(NavalMovement.is_home_fleet(_fleet_sortie_model, home))
	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)

func test_colonists_keep_their_seats_through_a_sortie() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	home.add_civilian(11)
	home.add_civilian(12)

	FleetSortie.apply(_fleet_sortie_model, home, 0)

	assert_eq(home.embarked_civilians, [11, 12])
	assert_eq(home.civilian_count(), 2)

func test_a_squadron_never_breaks_a_hull_out_from_under_its_colonists() -> void:
	_setup_fleet_sortie()
	var home: FleetState = FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	home.add_civilian(11)
	assert_false(bool(NavalDeck.can_scrap(home, null)["ok"]))
	home.add_hull("b", "carrack")
	assert_true(bool(NavalDeck.can_scrap(home, null)["ok"]))

func test_troops_cannot_board_a_squadron_carrying_colonists() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	home.add_civilian(11)
	var army: ArmyState = ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	var result: Dictionary = NavalTransport.can_embark(_fleet_sortie_model, army, home)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("colonists"))

# --- test_fleet_missions ---

func _war(a: int, b: int) -> bool:
	return a != b

func _peace(_a: int, _b: int) -> bool:
	return false

func test_a_patrol_station_spends_the_move_and_persists() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.PATROL)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.mission, FleetState.Mission.PATROL)
	assert_true(fleet.moved, "taking a station spends the turn's move")
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet).contains("patrol"))
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved, "the next turn restores the move")
	assert_eq(fleet.mission, FleetState.Mission.PATROL, "the station persists")

func test_the_home_fleet_and_docked_squadrons_cannot_take_a_station() -> void:
	_setup_fleet_missions()
	var home := FleetState.in_port(2, 0, 0)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, home, FleetState.Mission.PATROL
	)["reason"].contains("home fleet"))
	var docked := FleetState.in_port(3, 0, 1)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, docked, FleetState.Mission.PATROL
	)["reason"].contains("at sea"))
	var moved := FleetState.at_sea(4, 0, 0)
	moved.moved = true
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, moved, FleetState.Mission.PATROL
	)["reason"].contains("already moved"))
	var same := FleetState.at_sea(5, 0, 0)
	same.mission = FleetState.Mission.PATROL
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, same, FleetState.Mission.PATROL
	)["reason"].contains("already holds"))
	var empty := FleetState.at_sea(6, 0, 0)
	empty.hulls = []
	empty.hull_types = {}
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, empty, FleetState.Mission.PATROL
	)["reason"].contains("no hulls"))
	assert_false(bool(FleetMissions.can_assign(null, home, FleetState.Mission.PATROL)["ok"]))
	assert_false(bool(FleetMissions.can_assign(
		_fleet_missions_model, home, FleetState.Mission.MOVE
	)["ok"]))

func test_a_blockade_needs_a_hostile_coast_in_the_zone() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	assert_eq(FleetMissions.blockade_targets(_fleet_missions_model, fleet, _war), [1])
	var result: Dictionary = FleetMissions.assign(
		_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.blockade_province, 1)
	assert_true(FleetMissions.is_blockading(_fleet_missions_model, fleet, _war))
	assert_false(FleetMissions.is_blockading(_fleet_missions_model, fleet, _peace))
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet).contains("Blockading Coro"))
	var far := FleetState.at_sea(2, 0, 0)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, far, FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("border"))
	var own := FleetState.at_sea(3, 0, 0)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, own, FleetState.Mission.BLOCKADE, 0, _war
	)["reason"].contains("enemy coast"))
	var missing := FleetState.at_sea(4, 0, 1)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, missing, FleetState.Mission.BLOCKADE, 99, _war
	)["reason"].contains("enemy province"))
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, FleetState.at_sea(5, 0, 1), FleetState.Mission.BLOCKADE, 1, _peace
	)["reason"].contains("declared war"))
	var same := FleetState.at_sea(6, 0, 1)
	same.mission = FleetState.Mission.BLOCKADE
	same.blockade_province = 1
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, same, FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("already blockades"))
	_fleet_missions_model.province_data(1).owner = MapModel.NO_ID
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, FleetState.at_sea(7, 0, 1), FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("no crown"))

func test_blockade_targets_are_the_hostile_coasts_beside_the_zone() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(FleetMissions.blockade_targets(_fleet_missions_model, fleet, _war), [])
	assert_eq(FleetMissions.blockade_targets(null, fleet, _war), [])
	var docked := FleetState.in_port(2, 0, 1)
	assert_eq(FleetMissions.blockade_targets(_fleet_missions_model, docked, _war), [])

## A coast that runs along two waters while its harbour faces only one: the case
## the blockade's water gate turns on (wiki: ships-and-naval § Missions and
## Movement — "the blockading fleet must be in a sea zone adjacent to that
## province's port").
func _port_gate_model() -> MapModel:
	var model := MapModel.new()
	model.setup(6, 5)
	var riva_tiles: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2),
	]
	for tile: Vector2i in riva_tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
	# The port's water (east) and a second water along the same coast (south).
	for tile: Vector2i in [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2)]:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	for tile: Vector2i in [Vector2i(1, 2), Vector2i(2, 3)]:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 1
	var riva := ProvinceState.create(0, "Riva", riva_tiles, Vector2(1.0, 1.0), 6, 1)
	riva.port_tile = Vector2i(2, 0)
	model.provinces = [riva]
	model.sea_zones = [
		SeaZoneState.create(
			0, "East Water",
			[Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2)], Vector2(3.0, 1.0), 3
		),
		SeaZoneState.create(
			1, "South Water", [Vector2i(1, 2), Vector2i(2, 3)], Vector2(1.5, 2.5), 2
		),
	]
	return model

func test_a_blockade_stands_in_the_water_its_port_faces() -> void:
	var model: MapModel = _port_gate_model()
	assert_eq(NavalMovement.province_sea_zones(model, 0), [0, 1], "the coast runs on both")
	assert_eq(
		NavalMovement.port_sea_zones(model, 0), [0],
		"the harbour faces the east water alone"
	)
	var away := FleetState.at_sea(1, 0, 1)
	var refused: Dictionary = FleetMissions.can_assign(
		model, away, FleetState.Mission.BLOCKADE, 0, _war
	)
	assert_false(bool(refused["ok"]), "the far water holds no blockade of that port")
	assert_true(String(refused["reason"]).contains("port"))
	assert_eq(FleetMissions.blockade_targets(model, away, _war), [])
	away.mission = FleetState.Mission.BLOCKADE
	away.blockade_province = 0
	assert_false(
		FleetMissions.is_blockading(model, away, _war),
		"a blockade off the port's water does not stand"
	)
	var beside := FleetState.at_sea(2, 0, 0)
	assert_eq(FleetMissions.blockade_targets(model, beside, _war), [0])
	var assigned: Dictionary = FleetMissions.assign(
		model, beside, FleetState.Mission.BLOCKADE, 0, _war
	)
	assert_true(bool(assigned["ok"]), String(assigned.get("reason", "")))
	assert_true(FleetMissions.is_blockading(model, beside, _war))
	assert_eq(NavalMovement.port_sea_zones(null, 0), [])
	assert_eq(NavalMovement.port_sea_zones(model, 99), [])

func test_a_portless_coast_keeps_its_whole_water() -> void:
	var model: MapModel = _port_gate_model()
	model.province_data(0).port_tile = Vector2i(-1, -1)
	assert_eq(
		NavalMovement.port_sea_zones(model, 0), [0, 1],
		"a map with no harbour reads the coast"
	)
	var away := FleetState.at_sea(1, 0, 1)
	assert_true(bool(FleetMissions.can_assign(
		model, away, FleetState.Mission.BLOCKADE, 0, _war
	)["ok"]), "no port to face, so both waters blockade")

func test_a_blockade_out_of_the_ports_water_seals_nothing() -> void:
	var model: MapModel = _port_gate_model()
	var world := WorldMap.new()
	world.add_region(model)
	var away := FleetState.at_sea(1, 0, 1)
	away.mission = FleetState.Mission.BLOCKADE
	away.blockade_province = 0
	var far: Blockades = Blockades.read(world, {0: [away]}, 1, 0, 0, _war)
	assert_false(far.seals(0, 0), "that water never reaches the harbour")
	assert_false(far.any())
	var beside := FleetState.at_sea(2, 0, 0)
	beside.mission = FleetState.Mission.BLOCKADE
	beside.blockade_province = 0
	var near: Blockades = Blockades.read(world, {0: [beside]}, 1, 0, 0, _war)
	assert_true(near.seals(0, 0), "the port's own water seals the coast")

func test_a_normal_move_clears_the_station() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.PATROL)
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	var result: Dictionary = NavalMovement.apply_move(
		_fleet_missions_model, fleet, FleetState.Location.AT_SEA, 1
	)
	assert_true(bool(result["ok"]))
	assert_eq(fleet.mission, FleetState.Mission.NONE)
	assert_eq(fleet.blockade_province, MapModel.NO_ID)

func test_the_strongest_station_identifies_a_group() -> void:
	_setup_fleet_missions()
	var patrol := FleetState.at_sea(1, 0, 0)
	patrol.mission = FleetState.Mission.PATROL
	var blockade := FleetState.at_sea(2, 0, 1)
	blockade.mission = FleetState.Mission.BLOCKADE
	blockade.blockade_province = 1
	assert_eq(
		FleetMissions.station_mission(_fleet_missions_model, [patrol], _war),
		FleetState.Mission.PATROL
	)
	assert_eq(
		FleetMissions.station_mission(_fleet_missions_model, [patrol, blockade], _war),
		FleetState.Mission.BLOCKADE
	)
	assert_eq(
		FleetMissions.station_mission(_fleet_missions_model, [blockade], _peace),
		FleetState.Mission.NONE
	)

## The station line follows the same gate the interception does: a blockade
## whose coast is ours, or at peace, attempts nothing, so the dossier must not
## claim it does (REQ-P2-03).
func test_a_blockade_note_follows_the_station_gate() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading Coro"))
	# The crown takes the coast it was blockading.
	_fleet_missions_model.province_data(1).owner = 0
	assert_false(FleetMissions.is_blockading(_fleet_missions_model, fleet, _war))
	assert_false(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading"))
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("lapsed"))
	# Peace ends a blockade just as surely as capture.
	_fleet_missions_model.province_data(1).owner = 1
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _peace).contains("lapsed"))
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading"))
	# A station with no coast or map still names the station plainly.
	var legacy := FleetState.at_sea(2, 0, 1)
	legacy.mission = FleetState.Mission.BLOCKADE
	assert_true(FleetMissions.status_note(null, legacy).contains("the enemy coast"))

func test_station_ids_round_trip_and_labels_read_plainly() -> void:
	_setup_fleet_missions()
	assert_eq(FleetMissions.id_of(FleetState.Mission.PATROL), "patrol")
	assert_eq(FleetMissions.from_id("patrol"), FleetState.Mission.PATROL)
	assert_eq(FleetMissions.id_of(FleetState.Mission.BLOCKADE), "blockade")
	assert_eq(FleetMissions.from_id("blockade"), FleetState.Mission.BLOCKADE)
	assert_eq(FleetMissions.id_of(FleetState.Mission.DEFEND), "defend")
	assert_eq(FleetMissions.from_id("defend"), FleetState.Mission.DEFEND)
	assert_eq(FleetMissions.label(FleetState.Mission.BLOCKADE), "Blockade")
	assert_eq(FleetMissions.from_id("nonsense"), FleetState.Mission.NONE)
	assert_eq(FleetMissions.label(FleetState.Mission.NONE), "No station")
	assert_true(FleetMissions.is_stationary(FleetState.Mission.PATROL))
	assert_false(FleetMissions.is_stationary(FleetState.Mission.MOVE))

func test_a_defend_station_holds_and_names_its_orders() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = FleetMissions.assign(
		_fleet_missions_model, fleet, FleetState.Mission.DEFEND
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.mission, FleetState.Mission.DEFEND)
	assert_true(fleet.moved)
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet).contains("Holding station"))
	assert_true(String(result["message"]).contains("holds station"))

func test_a_lapsed_blockade_stops_claiming_the_station() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading Coro"))
	var peace: String = FleetMissions.status_note(_fleet_missions_model, fleet, _peace)
	assert_true(peace.contains("lapsed"), peace)
	_fleet_missions_model.province_data(1).owner = 0
	var taken: String = FleetMissions.status_note(_fleet_missions_model, fleet, _war)
	assert_true(taken.contains("lapsed"), taken)
	assert_false(FleetMissions.is_blockading(_fleet_missions_model, fleet, _war))

func test_mission_and_blockade_survive_a_save_round_trip() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	var saved: FleetState = FleetState.from_dict(fleet.to_dict())
	assert_eq(saved.mission, FleetState.Mission.BLOCKADE)
	assert_eq(saved.blockade_province, 1)
	var legacy: FleetState = FleetState.from_dict({"id": 9, "owner": 0})
	assert_eq(legacy.mission, FleetState.Mission.NONE)
	assert_eq(legacy.blockade_province, MapModel.NO_ID)

## Marking a landing site spends the move, so the squadron never sailed into
## the zone and cannot seize the initiative from the fleet that did (wiki:
## ships-and-naval § Missions and Movement — Beachhead is stationary).
func test_a_beachhead_squadron_is_stationary() -> void:
	_setup_fleet_missions()
	var marker := FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	marker.mission = FleetState.Mission.BEACHHEAD
	marker.beachhead_province = 1
	marker.beachhead_turn = 1
	marker.moved = true
	var mover := FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "carrack"})
	mover.moved = true

	assert_true(FleetMissions.is_stationary(FleetState.Mission.BEACHHEAD))
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[marker, mover], Callable(), {"interception_roll": 0.99}
	)

	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 1, "the squadron that sailed in attacks")

# --- test_naval_strength ---

func _naval_strength_squadron() -> FleetState:
	return FleetState.at_sea(
		4, 0, 1, ["ship_1", "ship_2", "ship_3"],
		{"ship_1": "carrack", "ship_2": "carrack", "ship_3": "frigate"}
	)

func test_the_squadron_totals_every_hull() -> void:
	var row: Dictionary = NavalStrength.squadron(_naval_strength_squadron())
	var totals: Dictionary = row["totals"]

	assert_eq(int(row["count"]), 3)
	assert_eq(int(totals["frp"]), 2 + 2 + 4)
	assert_eq(int(totals["rng"]), 1 + 1 + 3)
	assert_eq(int(totals["arm"]), 1 + 1 + 2)
	assert_eq(int(totals["hull"]), 2 + 2 + 4)
	assert_eq(int(totals["mv"]), 2 + 2 + 3)

func test_rows_aggregate_distinct_hulls_of_one_type() -> void:
	var rows: Array = NavalStrength.squadron(_naval_strength_squadron())["types"]

	assert_eq(rows.size(), 2, "two types, three hulls")
	assert_eq(String(rows[0]["type_id"]), "carrack")
	assert_eq(int(rows[0]["count"]), 2)
	assert_eq(String(rows[1]["type_id"]), "frigate")
	assert_eq(int(rows[1]["count"]), 1)
	assert_false(bool(rows[0]["warship"]))
	assert_true(bool(rows[1]["warship"]))

func test_strength_and_pool_match_the_resolver() -> void:
	var fleet: FleetState = _naval_strength_squadron()
	var row: Dictionary = NavalStrength.squadron(fleet)

	assert_almost_eq(float(row["strength"]), 2.75 + 2.75 + 5.8, 0.0001)
	assert_almost_eq(float(row["strength"]), NavalCombat.side_strength([fleet]), 0.0001)
	assert_almost_eq(
		float(row["durability"]), NavalCombat.side_durability([fleet]), 0.0001
	)
	assert_almost_eq(NavalStrength.strength(null), 0.0, 0.0001)
	assert_almost_eq(NavalStrength.durability(null), 0.0, 0.0001)

func test_an_empty_squadron_reads_as_nothing() -> void:
	var row: Dictionary = NavalStrength.squadron(FleetState.empty_in_port(9, 0, 1))

	assert_eq(int(row["count"]), 0)
	assert_almost_eq(float(row["strength"]), 0.0, 0.0001)
	assert_eq((row["types"] as Array).size(), 0)
	assert_eq(int((row["totals"] as Dictionary)["frp"]), 0)

func test_the_formula_names_every_weight() -> void:
	var row: Dictionary = NavalStrength.squadron(_naval_strength_squadron())
	var formula: String = String(row["formula"])

	assert_true(formula.contains("FRP 8"), formula)
	assert_true(formula.contains("RNG 5×0.4"), formula)
	assert_true(formula.contains("ARM 4×0.15"), formula)
	assert_true(formula.contains("MV 7×0.1"), formula)
	# 2.2 + 2.2 + 4.8: the pool is summed per hull, never 8 × (1 + 4/10).
	assert_almost_eq(float(row["durability"]), 9.2, 0.0001)
	assert_true(String(row["pool"]).contains("9.2"), String(row["pool"]))

func test_a_hull_line_names_its_own_numbers() -> void:
	assert_eq(
		NavalStrength.hull_line("frigate"),
		"FRP 4 · RNG 3 · ARM 2 · HULL 4 · MV 3 · 5.8 strength"
	)


## A crown whose leader publishes a naval row fights at that multiplier, and a
## land or court leader never touches the sea (wiki: leader-bonuses § When
## Bonuses Apply — the naval exception is de Ruyter's row only).
func test_de_ruyter_lifts_only_his_own_side_at_sea() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "carrack"})
	var mine_base: float = NavalCombat.side_strength([mine])
	var theirs_base: float = NavalCombat.side_strength([theirs])
	var led: Array[Dictionary] = NavalCombat.resolve_turn(
		[mine, theirs], Callable(), {"leaders": {0: "de_ruyter", 1: "napoleon"}}
	)
	assert_eq(led.size(), 1, "two hostile sides in one zone fight")
	var record: Dictionary = led[0]
	assert_eq(int(record["attacker"]), 0, "the lower owner id opens the fight")
	assert_almost_eq(float(record["attacker_strength"]), mine_base * 1.15, 0.0001,
		"de Ruyter's squadron fights 15% stronger")
	assert_almost_eq(float(record["defender_strength"]), theirs_base, 0.0001,
		"a court without a naval row fights as published")


func test_a_sea_fight_without_leaders_fights_as_published() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "frigate"})
	var published: float = NavalCombat.side_strength([mine])
	var plain: Array[Dictionary] = NavalCombat.resolve_turn([mine, theirs])
	assert_eq(plain.size(), 1)
	assert_almost_eq(
		float(plain[0]["attacker_strength"]), published, 0.0001,
		"no leader context leaves the published strength alone"
	)

func test_an_edge_wins_and_an_even_split_is_a_draw() -> void:
	var win: Dictionary = NavalStrength.odds(60.0, 40.0)
	assert_eq(NavalStrength.outcome_of(win), NavalStrength.OUTCOME_WIN)
	assert_eq(NavalStrength.share_text(win), "60%")

	var loss: Dictionary = NavalStrength.odds(40.0, 60.0)
	assert_eq(NavalStrength.outcome_of(loss), NavalStrength.OUTCOME_LOSS)

	# The resolver calls anything inside ±3% of an even split a stalemate, so the
	# boundary itself is a draw (wiki: § Naval Combat Resolution).
	assert_eq(
		NavalStrength.outcome_of(NavalStrength.odds(53.0, 47.0)),
		NavalStrength.OUTCOME_DRAW
	)
	assert_eq(
		NavalStrength.outcome_of(NavalStrength.odds(53.1, 46.9)),
		NavalStrength.OUTCOME_WIN
	)
	assert_almost_eq(NavalStrength.need(), 0.53, 0.0001)

func test_no_strength_anywhere_is_a_draw() -> void:
	var even: Dictionary = NavalStrength.odds(0.0, 0.0)

	assert_eq(NavalStrength.outcome_of(even), NavalStrength.OUTCOME_DRAW)
	assert_almost_eq(float(even["share"]), 0.5, 0.0001)

func test_the_zone_sums_friend_and_hostile_sides() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var second: FleetState = FleetState.at_sea(2, 0, 0, ["ship_2"], {"ship_2": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "frigate"})
	var far: FleetState = FleetState.at_sea(4, 1, 1, ["ship_4"], {"ship_4": "frigate"})
	var moored: FleetState = FleetState.in_port(5, 1, 1, ["ship_5"], {"ship_5": "frigate"})

	var row: Dictionary = NavalStrength.zone([mine, second, theirs, far, moored], mine)

	assert_almost_eq(float(row["own"]), 5.5, 0.0001, "two of ours fight as one side")
	assert_almost_eq(float(row["foe"]), 5.8, 0.0001, "the other zone and the port stay out")
	assert_eq(int(row["own_hulls"]), 2)
	assert_eq(int(row["foe_hulls"]), 1)
	assert_true((row["foes"] as Array).has(1))
	assert_eq(NavalStrength.outcome_of(row), NavalStrength.OUTCOME_DRAW)


## The dossier's share reads the crown's leader exactly as the resolver does, so
## a de Ruyter squadron's printed odds are the odds it strikes (REQ-P2-03).
func test_the_zone_share_reads_the_published_naval_row() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "carrack"})
	var published: float = NavalCombat.side_strength([mine])
	var plain: Dictionary = NavalStrength.zone([mine, theirs], mine)
	assert_almost_eq(float(plain["own"]), published, 0.0001)
	var led: Dictionary = NavalStrength.zone(
		[mine, theirs], mine, Callable(), {}, {0: "de_ruyter", 1: "napoleon"}
	)
	assert_almost_eq(float(led["own"]), published * 1.15, 0.0001)
	assert_almost_eq(
		float(led["foe"]), published, 0.0001, "a land leader never touches the sea"
	)


func test_a_peaceful_flag_is_no_threat() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "frigate"})
	var peace := func(_a: int, _b: int) -> bool: return false

	var row: Dictionary = NavalStrength.zone([mine, theirs], mine, peace)

	assert_almost_eq(float(row["foe"]), 0.0, 0.0001)
	assert_eq((row["foes"] as Array).size(), 0)

func test_a_moored_squadron_gets_no_odds() -> void:
	var moored: FleetState = FleetState.in_port(5, 0, 1, ["ship_5"], {"ship_5": "frigate"})

	assert_eq(NavalStrength.zone([moored], moored).size(), 0)
	assert_eq(NavalStrength.zone([], null).size(), 0)

func test_the_zone_falls_back_to_the_squadron_it_was_asked_about() -> void:
	var lone: FleetState = FleetState.at_sea(7, 0, 1, ["ship_7"], {"ship_7": "sloop"})

	var row: Dictionary = NavalStrength.zone([], lone)

	assert_almost_eq(float(row["own"]), 3.25, 0.0001)
	assert_eq(int(row["own_hulls"]), 1)

# --- test_naval_retreat ---

func _naval_retreat_fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet

func _naval_retreat_squadron(id: int, owner: int, zone: int, type_id: String, count: int) -> FleetState:
	var types: Array = []
	for _index in count:
		types.append(type_id)
	return _naval_retreat_fleet(id, owner, zone, types)

func test_retreat_chance_follows_the_wiki_formula() -> void:
	_setup_naval_retreat()
	var beaten := _naval_retreat_squadron(1, 1, 0, "fluyte", 1)
	var victor := _naval_retreat_squadron(2, 0, 0, "carrack", 1)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.NONE), 0.6, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.PATROL), 0.5, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.BLOCKADE), 0.4, 0.0001
	)
	var fast := _naval_retreat_squadron(3, 1, 0, "sloop", 1)
	assert_almost_eq(
		NavalRetreat.chance([fast], [victor], FleetState.Mission.NONE), 0.7, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([victor], [fast], FleetState.Mission.NONE), 0.5, 0.0001
	)

func test_a_retreat_needs_an_adjacent_friendly_or_neutral_zone() -> void:
	_setup_naval_retreat()
	var beaten := _naval_retreat_squadron(1, 1, 0, "carrack", 1)
	var victor := _naval_retreat_squadron(2, 0, 0, "carrack", 3)
	var hostile := _naval_retreat_squadron(3, 2, 1, "carrack", 1)
	var fleets: Array = [victor, beaten, hostile]
	var owners: Array[int] = [1]
	assert_eq(
		NavalRetreat.safe_zones(_naval_retreat_model, 0, owners, fleets),
		[] as Array[int],
		"the only neighbouring zone is hostile"
	)
	fleets.erase(hostile)
	assert_eq(
		NavalRetreat.safe_zones(_naval_retreat_model, 0, owners, fleets),
		[1] as Array[int]
	)

func test_a_successful_retreat_moves_the_beaten_squadron() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _naval_retreat_model, "fleets": fleets, "retreat_roll": 0.0}
	)
	var retreat: Dictionary = battles[0]["retreat"]
	assert_true(bool(retreat["success"]))
	assert_eq(int(retreat["zone"]), 1)
	assert_eq(weak.sea_zone, 1)
	assert_eq(weak.ship_count(), 1, "the squadron slips away intact")
	assert_true(weak.moved)
	assert_eq((battles[0]["defender_lost"] as Array).size(), 0)

func test_a_failed_retreat_is_a_rout() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _naval_retreat_model, "fleets": fleets, "retreat_roll": 0.99}
	)
	var retreat: Dictionary = battles[0]["retreat"]
	assert_false(bool(retreat["success"]))
	assert_eq(weak.ship_count(), 0)
	assert_eq(int((battles[0]["defender_lost"] as Array).size()), 1)

func test_a_retreating_side_abandons_its_station() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	weak.mission = FleetState.Mission.DEFEND
	weak.beachhead_province = 1
	weak.beachhead_turn = 3
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _naval_retreat_model, "fleets": fleets, "retreat_roll": 0.0}
	)
	assert_true(bool((battles[0]["retreat"] as Dictionary)["success"]))
	assert_eq(weak.mission, FleetState.Mission.NONE)
	assert_false(weak.has_beachhead())

func test_without_a_model_the_loser_is_still_routed() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	assert_eq((battles[0]["retreat"] as Dictionary).size(), 0)
	assert_eq(weak.ship_count(), 0)

func test_the_despatch_names_the_withdrawal() -> void:
	_setup_naval_retreat()
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": [],
		"retreat": {"success": true, "beaten": 1, "zone": 4},
	}
	assert_eq(
		BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"England withdraws from the Windward Passage — España holds the zone"
	)


## The dossier's way out reads the retreat the turn would roll — the published
## chance, the haven the rules steer her into and the enemy station that sets the
## aggression — and says so plainly when no adjacent water is safe (wiki:
## ships-and-naval § Naval Retreat Formula; DR-20261124-06).
func test_the_retreat_preview_reads_the_way_the_pass_rolls() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	var fleets: Array = [strong, weak]

	var offer: Dictionary = NavalRetreat.preview(
		_naval_retreat_model, 0, [weak], [strong], fleets
	)

	assert_true(bool(offer.get("ok", false)), "open water offers a way out")
	assert_almost_eq(
		float(offer.get("chance", 0.0)),
		NavalRetreat.chance([weak], [strong], FleetState.Mission.NONE),
		0.0001,
		"one formula, read by the sheet and rolled by the pass"
	)
	assert_eq(int(offer.get("zone", -1)), 1, "the haven is the safe water beside it")
	assert_eq(String(offer.get("zone_name", "")), "Golfo de México", "the haven is named")

	# The enemy's station sets the aggression the pass would charge.
	strong.mission = FleetState.Mission.PATROL
	assert_almost_eq(
		float(NavalRetreat.preview(
			_naval_retreat_model, 0, [weak], [strong], fleets
		).get("chance", 0.0)),
		0.5,
		0.0001,
		"a patrol costs the beaten side 10%"
	)
	strong.mission = FleetState.Mission.NONE

	# A hostile holding the only sea road shuts the way out: a rout is certain.
	var shut_by := _naval_retreat_squadron(3, 2, 1, "carrack", 1)
	fleets.append(shut_by)
	var shut: Dictionary = NavalRetreat.preview(
		_naval_retreat_model, 0, [weak], [strong], fleets
	)
	assert_false(bool(shut.get("ok", true)), "no safe water is no retreat")
	assert_eq(String(shut.get("reason", "")), "no safe adjacent zone")
	# The attempt reads the same refusal.
	assert_eq(
		String(NavalRetreat.attempt(
			_naval_retreat_model, 0, [weak], [strong], fleets
		).get("reason", "")),
		"no safe adjacent zone"
	)
	# No chart, no reading.
	assert_eq(NavalRetreat.preview(null, 0, [weak], [strong], fleets), {})


## A zone the crown would lose reads the way out beside its odds, over the court
## whose side would beat her; a zone she holds, or one the fog leaves unread,
## reads none — a retreat is rolled only for the beaten side (wiki:
## ships-and-naval § Naval Retreat Formula, § Sighted strength; DR-20261124-06).
func test_the_zone_reads_the_way_out_of_a_fight_the_crown_loses() -> void:
	_setup_naval_retreat()
	var weak := _naval_retreat_squadron(1, 0, 0, "carrack", 1)
	var strong := _naval_retreat_squadron(2, 1, 0, "carrack", 3)
	var fleets: Array = [weak, strong]

	var zone: Dictionary = NavalStrength.zone(
		fleets, weak, Callable(), {}, {}, Callable(), _naval_retreat_model
	)

	assert_eq(int(zone.get("outcome", 0)), NavalStrength.OUTCOME_LOSS, "a losing water")
	var offer: Dictionary = zone.get("retreat", {})
	assert_false(offer.is_empty(), "the losing water reads the way out")
	assert_true(bool(offer.get("ok", true)), "open water beside it")
	assert_eq(int(offer.get("court", -1)), 1, "the court that would beat her is named")
	assert_eq(int(offer.get("zone", -1)), 1, "and the haven it would take")

	# Two courts in the water: the sheet prices the stronger side, which is the
	# one that would beat her.
	fleets.append(_naval_retreat_squadron(3, 2, 0, "fluyte", 1))
	assert_eq(
		int((NavalStrength.zone(
			fleets, weak, Callable(), {}, {}, Callable(), _naval_retreat_model
		).get("retreat", {}) as Dictionary).get("court", -1)),
		1,
		"the strongest hostile court is the one priced"
	)
	fleets.pop_back()

	# The same water read from the winning side: no retreat is rolled for her.
	var won: Dictionary = NavalStrength.zone(
		fleets, strong, Callable(), {}, {}, Callable(), _naval_retreat_model
	)
	assert_eq(int(won.get("outcome", 0)), NavalStrength.OUTCOME_WIN)
	assert_false(won.has("retreat"), "a crown that holds the edge hears nothing")

	# An unread rival leaves the water undecided, and the line waits on the fog.
	var unread: Dictionary = NavalStrength.zone(
		fleets, weak, Callable(), {}, {},
		func(_other: FleetState) -> bool: return false,
		_naval_retreat_model
	)
	assert_true(bool(unread.get("unread", false)))
	assert_false(unread.has("retreat"), "the fog withholds the way out too")

	# No chart: the odds still read, the haven cannot be named.
	assert_false(
		NavalStrength.zone(fleets, weak, Callable(), {}, {}, Callable()).has("retreat"),
		"a haven needs a chart"
	)

# --- test_naval_port_loss ---

func test_a_squadron_in_a_captured_port_sorts_out_to_the_lowest_zone() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	model.province_data(SEAT).owner = 1

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_eq(reports.size(), 1)
	assert_false(bool(reports[0]["scuttled"]))
	assert_eq(int(reports[0]["zone"]), 0)
	assert_true(fleet.is_at_sea())
	assert_eq(fleet.sea_zone, 0)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved, "the sortie spends the squadron's move")

func test_a_squadron_with_no_coast_is_scuttled() -> void:
	var model: MapModel = _inland_chart()
	var fleet: FleetState = FleetState.in_port(1, 1, HARBOUR, ["ship_1"])

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_eq(reports.size(), 1)
	assert_true(bool(reports[0]["scuttled"]))
	assert_eq(int(reports[0]["zone"]), MapModel.NO_ID)
	assert_true(fleet.is_afloat(), "the report keeps the hull list for the toast")

func test_an_empty_slip_is_dropped_without_a_report() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var slip: FleetState = FleetState.empty_in_port(1, 0, SEAT)
	model.province_data(SEAT).owner = 1
	var roster: Array[FleetState] = [slip]

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, roster)

	assert_true(reports.is_empty())
	assert_true(roster.is_empty())

func test_an_owned_port_keeps_its_squadron_moored() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_true(reports.is_empty())
	assert_true(fleet.is_in_port())
	assert_eq(fleet.province, SEAT)

func test_a_seaboard_seat_re_moors_the_home_squadron() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	model.province_data(HARBOUR).owner = 0

	var result: Dictionary = NavalPortLoss.relocate_home(model, [fleet], 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 0)
	assert_eq((result["moved"] as Array).size(), 1)
	assert_eq(fleet.province, HARBOUR)
	assert_true(fleet.is_in_port())
	assert_eq(fleet.hulls, ["ship_1"])

func test_an_inland_seat_leaves_the_home_squadron_to_sort_out() -> void:
	var model: MapModel = _inland_chart()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])

	var result: Dictionary = NavalPortLoss.relocate_home(model, [fleet], 0, SEAT, HARBOUR)

	assert_true((result["moved"] as Array).is_empty())
	assert_eq(fleet.province, SEAT, "the eviction pass owns the inland fallback")
	model.province_data(SEAT).owner = 1
	NavalPortLoss.evict_stranded(model, [fleet])
	assert_true(fleet.is_at_sea())
	assert_eq(fleet.sea_zone, 0)

func test_a_squadron_at_the_new_seat_absorbs_the_home_squadron() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var home: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	var moored: FleetState = FleetState.in_port(2, 0, HARBOUR, ["ship_2"])
	model.province_data(HARBOUR).owner = 0
	var roster: Array[FleetState] = [home, moored]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 1)
	assert_eq(roster.size(), 1)
	assert_eq(roster[0], moored)
	assert_eq(moored.hulls, ["ship_2", "ship_1"])

## The re-mooring is administrative: the absorbed squadron keeps its colonists
## and troops, and a second army goes ashore at the new seat instead of being
## lost (wiki: ships-and-naval § Ports that change hands; DR-20261109-11).
func test_the_absorbed_squadron_keeps_its_passengers() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var home: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1", "ship_2"])
	var moored: FleetState = FleetState.in_port(2, 0, HARBOUR, ["ship_3", "ship_4"])
	model.province_data(HARBOUR).owner = 0
	home.add_civilian(11)
	home.embarked_army = 21
	var roster: Array[FleetState] = [home, moored]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 1)
	assert_true(moored.has_civilian(11), "the colonist rides the absorbed hulls")
	assert_eq(moored.embarked_army, 21, "the troops stay aboard")
	assert_true((result["ashore"] as Array).is_empty())

	# A second army cannot share the squadron: the surplus is reported for the
	# landing at the new seat, never dropped with the merged-away hulls.
	moored.embarked_army = 31
	var second: FleetState = FleetState.in_port(3, 0, SEAT, ["ship_5"])
	second.embarked_army = 32
	var other: Dictionary = NavalPortLoss.relocate_home(
		model, [second, moored], 0, SEAT, HARBOUR
	)

	assert_eq(moored.embarked_army, 31, "the moored squadron keeps its own army")
	assert_eq((other["ashore"] as Array), [32] as Array[int])

func test_an_empty_home_slip_is_dropped_on_the_move() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var slip: FleetState = FleetState.empty_in_port(1, 0, SEAT)
	var roster: Array[FleetState] = [slip]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_true((result["moved"] as Array).is_empty())
	assert_true(roster.is_empty())

func test_settlement_sorts_out_and_reports_every_region() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var regions := MapRegionTable.new()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	regions.set_region(0, [fleet])
	model.province_data(SEAT).owner = 1

	var result: Dictionary = FleetPortSettlement.settle(world, regions, [])

	assert_eq((result["regions"] as Array), [0])
	assert_eq((result["reports"] as Array).size(), 1)
	assert_eq((result["sorties"] as Array).size(), 1)
	assert_true(fleet.is_at_sea())

## A squadron that sorts out of a captured port in the other chart enters that
## water exactly as a sail order does, so the crown charts the zone even though
## the court is looking at the other chart (wiki: ships-and-naval § Ports that
## change hands — "The entry reveals the zone for its owner like any move").
func test_a_sort_out_in_the_other_chart_charts_the_zone() -> void:
	var play: PlaySession = _two_chart_session()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	play.ship_layer.regions.set_region(1, [fleet])
	play.world.region(1).province_data(SEAT).owner = 1

	MapPlayPortLoss.settle(play, [])

	assert_true(fleet.is_at_sea(), "the port fell, so the squadron sorts out")
	assert_eq(fleet.sea_zone, 0)
	var chart: VisibilityModel = play.visibility_by_region.get(1, null)
	assert_not_null(chart, "the other chart is minted for the entry")
	if chart == null:
		return
	for tile: Vector2i in play.world.region(1).sea_zone_data(0).tiles:
		assert_eq(
			chart.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE,
			"the entered zone's water is charted"
		)
	# The strict coastal ring comes with the water, as any sail order charts it.
	assert_eq(chart.level_at(1, 0), VisibilityModel.Level.FULLY_VISIBLE)
	# The shown chart is the ship layer's own signal, so nothing is minted here.
	assert_false(play.visibility_by_region.has(0))

## A re-mooring is administrative and charts nothing, a rival's sortie is not
## the crown's reading, and a scuttled squadron enters no water at all.
func test_only_the_crowns_own_sort_out_charts_the_other_chart() -> void:
	var play: PlaySession = _two_chart_session()
	var reports: Array[Dictionary] = [
		{"fleet": 1, "owner": 1, "province": SEAT, "zone": 0, "scuttled": false, "region": 1},
		{"fleet": 2, "owner": 0, "from": SEAT, "to": HARBOUR, "region": 1},
		{"fleet": 3, "owner": 0, "province": SEAT, "zone": MapModel.NO_ID, "scuttled": true, "region": 1},
	]

	MapPlayPortLoss.chart_sorties(play, reports)

	assert_false(play.visibility_by_region.has(1), "no chart is minted for nothing")

## Two charts, the crown looking at the old one: the fixture's chart twice, the
## second standing in for the New World. The layer knows both rosters.
func _two_chart_session() -> PlaySession:
	var old_world: MapModel = naval_port_loss_Fixture.build()
	var new_world: MapModel = naval_port_loss_Fixture.build()
	new_world.region_id = 1
	var world := WorldMap.new()
	world.add_region(old_world)
	world.add_region(new_world)
	var play := PlaySession.new()
	play.world = world
	play.model = old_world
	play.player_faction = 0
	play.region_index = 0
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.player_faction = 0
	return play

## The chart helper's own guards: the shown region hands back the session's
## model, a region the world does not have mints nothing, and a session with no
## world or no reports is a no-op.
func test_the_chart_helper_guards_what_it_cannot_chart() -> void:
	var play: PlaySession = _two_chart_session()
	var shown := VisibilityModel.new()
	shown.setup(play.model, 0)
	play.visibility = shown

	assert_eq(MapPlayFogTurn.chart(play, 0), shown, "the shown chart is the session's")
	assert_eq(MapPlayFogTurn.chart(play, 9), null, "no such region")
	assert_eq(MapPlayFogTurn.chart(null, 0), null, "no session")
	var bare := PlaySession.new()
	bare.player_faction = 0
	assert_eq(MapPlayFogTurn.chart(bare, 1), null, "no world to cut a chart from")
	MapPlayPortLoss.chart_sorties(null, [])
	MapPlayPortLoss.chart_sorties(bare, [{"owner": 0, "zone": 0, "region": 1}])
	assert_true(bare.visibility_by_region.is_empty(), "nothing is charted without a world")

## A sort-out the crown is already looking at is the ship layer's own signal,
## and a report with no zone enters no water.
func test_a_shown_chart_sort_out_and_a_zoneless_report_chart_nothing() -> void:
	var play: PlaySession = _two_chart_session()
	var reports: Array[Dictionary] = [
		{"fleet": 1, "owner": 0, "province": SEAT, "zone": 0, "scuttled": false, "region": 0},
		{"fleet": 2, "owner": 0, "province": SEAT, "zone": MapModel.NO_ID, "scuttled": false, "region": 1},
	]

	MapPlayPortLoss.chart_sorties(play, reports)

	assert_true(play.visibility_by_region.is_empty(), "neither report charts a chart")

func test_settlement_re_moors_a_reassigned_home_squadron() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var regions := MapRegionTable.new()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	regions.set_region(0, [fleet])
	model.province_data(HARBOUR).owner = 0

	var result: Dictionary = FleetPortSettlement.settle(
		world,
		regions,
		[{"faction": 0, "lost": SEAT, "province": HARBOUR, "region": 0}]
	)

	assert_eq(fleet.province, HARBOUR)
	assert_eq((result["reports"] as Array).size(), 1)
	assert_true((result["sorties"] as Array).is_empty())

## A 7x3 chart: province 0 is coastal, province 1 is ringed by neutral land so
## it has no sea zone, and the only water is the bay beside province 0.
func _inland_chart() -> MapModel:
	var model := MapModel.new()
	model.setup(7, 3)
	_land(model, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], 0)
	_land(model, [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1)], 1)
	for tile: Vector2i in [
		Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 0),
		Vector2i(5, 1), Vector2i(5, 2),
	]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	var water: Array[Vector2i] = [
		Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2),
	]
	for tile: Vector2i in water:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	var seat := ProvinceState.create(
		0, "Seat", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		Vector2(0.5, 0.5), 4, 0, true
	)
	var inland := ProvinceState.create(
		1, "Inland", [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1)],
		Vector2(3.5, 0.5), 4, 0, false
	)
	model.provinces = [seat, inland]
	model.sea_zones = [SeaZoneState.create(0, "Bay", water, Vector2(0.5, 2.0), 5)]
	return model

func _land(model: MapModel, tiles: Array, province_id: int) -> void:
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = province_id

# --- test_naval_interception ---

func _naval_interception_fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet

func _naval_interception_squadron(id: int, owner: int, zone: int, type_id: String, count: int) -> FleetState:
	var types: Array = []
	for _index in count:
		types.append(type_id)
	return _naval_interception_fleet(id, owner, zone, types)

func test_interception_chance_follows_the_wiki_formula() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance([sloop], [fluyte], FleetState.Mission.PATROL),
		0.5 * 4.0 / 7.0,
		0.0001
	)
	assert_almost_eq(
		NavalInterception.chance([sloop], [fluyte], FleetState.Mission.BLOCKADE),
		0.9 * 4.0 / 7.0,
		0.0001
	)
	assert_eq(
		NavalInterception.chance([], [fluyte], FleetState.Mission.PATROL), 0.0
	)
	assert_eq(
		NavalInterception.chance([sloop], [], FleetState.Mission.PATROL), 0.0
	)

func test_interception_chance_is_clamped() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var many_fluytes := _naval_interception_squadron(2, 1, 0, "fluyte", 30)
	assert_almost_eq(
		NavalInterception.chance([sloop], [many_fluytes], FleetState.Mission.PATROL),
		NavalInterception.MIN_CHANCE,
		0.0001
	)
	var raiders := _naval_interception_squadron(3, 0, 0, "raider", 20)
	var one_fluyte := _naval_interception_squadron(4, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance([raiders], [one_fluyte], FleetState.Mission.BLOCKADE),
		NavalInterception.MAX_CHANCE,
		0.0001
	)

func test_the_roll_is_deterministic_and_in_range() -> void:
	_setup_naval_interception()
	var first: float = NavalInterception.roll(1500, 4, 2, 0, 1)
	assert_almost_eq(first, NavalInterception.roll(1500, 4, 2, 0, 1), 0.0001)
	assert_gte(first, 0.0)
	assert_lt(first, 1.0)
	assert_ne(first, NavalInterception.roll(1501, 4, 2, 0, 1))

func test_attempts_follow_the_roll() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	var hit: Dictionary = NavalInterception.attempt(
		0, [sloop], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.0
	)
	var miss: Dictionary = NavalInterception.attempt(
		0, [sloop], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.99
	)
	assert_true(bool(hit["ok"]))
	assert_false(bool(miss["ok"]))
	assert_true(bool(NavalInterception.attempt(
		0, [], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.0
	)["ok"]) == false)

func test_a_successful_patrol_interception_makes_the_patroller_attacker() -> void:
	_setup_naval_interception()
	var patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, mover], Callable(), {"interception_roll": 0.0}
	)
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 0)
	assert_true(bool(battles[0]["intercepted"]))
	assert_almost_eq(
		float(battles[0]["interception_chance"]), 0.5 * 4.0 / 7.0, 0.0001
	)

func test_a_failed_interception_leaves_the_mover_as_attacker() -> void:
	_setup_naval_interception()
	var patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, mover], Callable(), {"interception_roll": 0.99}
	)
	assert_eq(int(battles[0]["attacker"]), 1)
	assert_false(bool(battles[0]["intercepted"]))

func test_a_blockade_intercepts_on_the_higher_factor() -> void:
	_setup_naval_interception()
	var blockader := _naval_interception_squadron(1, 0, 1, "sloop", 1)
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var mover := _naval_interception_squadron(2, 1, 1, "fluyte", 1)
	mover.moved = true
	var context: Dictionary = {"model": _naval_interception_model, "interception_roll": 0.45}
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[blockader, mover], Callable(), context
	)
	assert_true(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 0)
	# The same roll misses a patrol's lower chance in the same waters.
	var patrol := _naval_interception_squadron(3, 0, 1, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var other := _naval_interception_squadron(4, 1, 1, "fluyte", 1)
	other.moved = true
	var misses: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, other], Callable(), context
	)
	assert_false(bool(misses[0]["intercepted"]))
	assert_eq(int(misses[0]["attacker"]), 1)

func test_a_defending_squadron_does_not_intercept() -> void:
	_setup_naval_interception()
	var defender := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	defender.mission = FleetState.Mission.DEFEND
	var mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[defender, mover], Callable(), {"interception_roll": 0.0}
	)
	assert_false(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 1)

## One station reading for the whole water: the combat pass rolls the holders,
## the trade pass raids with the squadrons whose orders work the station, and a
## water of bystanders holds no station at all. The coast a raid works and the
## hostile groups off it live here too, so the dossier, the catch and the prize
## all read one home (DR-20261120-01, DR-20261120-02; REQ-P3-01).
func test_one_station_reading_serves_the_catch_and_the_prize() -> void:
	_setup_naval_raid()
	var patrol := _naval_raid_fleet(1, 0, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var sailing := _naval_raid_fleet(2, 0, 1, ["sloop"])
	sailing.mission = FleetState.Mission.DEFEND
	var water: Array = [patrol, sailing]
	var kept: Array = NavalStation.group_from(_naval_raid_model, water)
	assert_eq(kept.size(), 1, "a Defend squadron holds nothing")
	assert_eq(kept[0], patrol)
	assert_true(NavalStation.works(_naval_raid_model, patrol))
	assert_false(
		NavalStation.works(_naval_raid_model, sailing),
		"a squadron holding no station works no price"
	)
	assert_eq(
		NavalStation.group(_naval_raid_model, water, 1, 0).size(), 1,
		"the station of the water is the same reading"
	)
	assert_eq(
		NavalStation.group(_naval_raid_model, water, 0, 0).size(), 0,
		"a squadron in another water is no part of this station"
	)
	# A fleet at sea stands on her own when the roster holds no consort.
	assert_eq(NavalStation.group_of(_naval_raid_model, water, patrol).size(), 1)
	assert_eq(NavalStation.group_of(_naval_raid_model, water, null).size(), 0)
	# The coast a trade raid works: Coro's waters (zone 1) and only those.
	var coasts: Array[int] = NavalStation.coast_zones(_naval_raid_model, 1)
	assert_true(coasts.has(1), "Coro's coast opens zone 1")
	assert_false(coasts.has(0), "Cádiz's sea is not Coro's coast")
	# Hostile stations off that coast: a Patrol works it; a Defend does not;
	# only_owner keeps a prize raid to one crown's colours.
	var foe := _naval_raid_fleet(3, 2, 1, ["frigate"])
	foe.mission = FleetState.Mission.PATROL
	var off_coast: Array = [patrol, sailing, foe]
	var groups: Dictionary = NavalStation.hostile_groups(
		_naval_raid_model, off_coast, 1, Callable()
	)
	assert_eq(groups.size(), 2, "two crowns hold stations off Coro")
	assert_true(groups.has(Vector2i(1, 0)), "owner 0's patrol works the coast")
	assert_true(groups.has(Vector2i(1, 2)), "owner 2's patrol works the coast")
	assert_eq((groups[Vector2i(1, 0)] as Array).size(), 1, "Defend is no station")
	var prize_only: Dictionary = NavalStation.hostile_groups(
		_naval_raid_model, off_coast, 1, Callable(), 2
	)
	assert_eq(prize_only.size(), 1, "a prize raid keeps the crown's own colours")
	assert_true(prize_only.has(Vector2i(1, 2)))
	# A doomed blockade (its coast taken back) works nothing.
	patrol.mission = FleetState.Mission.BLOCKADE
	patrol.blockade_province = 1
	assert_true(NavalStation.works(_naval_raid_model, patrol))
	var taken: int = _naval_raid_model.province_data(1).owner
	_naval_raid_model.province_data(1).owner = 0
	assert_false(NavalStation.works(_naval_raid_model, patrol), "her own shore blocks nothing")
	_naval_raid_model.province_data(1).owner = taken

func test_only_the_station_holders_join_the_roll() -> void:
	_setup_naval_interception()
	var patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var holding := _naval_interception_squadron(2, 0, 0, "ship_of_the_line", 2)
	holding.mission = FleetState.Mission.DEFEND
	var mover := _naval_interception_squadron(3, 1, 0, "carrack", 1)
	mover.moved = true
	# A Defend squadron's intercept ratings must not turn the patrol's 0.33 roll
	# into a 0.40 hit; the mover keeps the initiative in this battle.
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, holding, mover], Callable(), {"interception_roll": 0.35}
	)
	assert_false(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 1)
	assert_almost_eq(
		float(battles[0]["interception_chance"]), 0.5 * 4.0 / 6.0, 0.0001
	)

## Crown-tech query: `owner` holds Privateering Companies, nobody else does.
func _charter(owner: int) -> Callable:
	return func(crown: int, tech_id: String) -> bool:
		return crown == owner and tech_id == NavalInterception.PRIVATEERING_TECH

func test_privateers_multiply_the_intercept_score() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	var plain: float = NavalInterception.chance(
		[sloop], [fluyte], FleetState.Mission.PATROL
	)
	var chartered: float = NavalInterception.chance(
		[sloop], [fluyte], FleetState.Mission.PATROL, _charter(0)
	)
	assert_almost_eq(plain, 0.5 * 4.0 / 7.0, 0.0001)
	# Σintercept 4 × 1.25 = 5 against the same flee score of 3.
	assert_almost_eq(chartered, 0.5 * 5.0 / 8.0, 0.0001)
	assert_gt(chartered, plain)

func test_only_the_interceptors_charter_counts() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	# The target's own privateers never help the interceptor.
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, _charter(1)
		),
		0.5 * 4.0 / 7.0,
		0.0001
	)
	# A crown without the tech gets the plain table.
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, _charter(4)
		),
		0.5 * 4.0 / 7.0,
		0.0001
	)

func test_a_privateer_patrol_wins_a_roll_a_plain_one_misses() -> void:
	_setup_naval_interception()
	# 0.30 lies between the plain 4/14 and the chartered 5/16.
	var plain_patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	plain_patrol.mission = FleetState.Mission.PATROL
	var plain_mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	plain_mover.moved = true
	var plain: Array[Dictionary] = NavalCombat.resolve_turn(
		[plain_patrol, plain_mover], Callable(), {"interception_roll": 0.30}
	)
	assert_false(bool(plain[0]["intercepted"]))
	var chartered_patrol := _naval_interception_squadron(3, 0, 0, "sloop", 1)
	chartered_patrol.mission = FleetState.Mission.PATROL
	var chartered_mover := _naval_interception_squadron(4, 1, 0, "fluyte", 1)
	chartered_mover.moved = true
	var chartered: Array[Dictionary] = NavalCombat.resolve_turn(
		[chartered_patrol, chartered_mover],
		Callable(),
		{"interception_roll": 0.30, "has_tech": _charter(0)}
	)
	assert_true(bool(chartered[0]["intercepted"]))
	assert_eq(int(chartered[0]["attacker"]), 0)

## A crown in the full-AI observer answers from its own AI ledger: no human
## ledger resolves there, so the charter must still count (REQ-P2-03).
func test_the_observer_crown_earns_its_privateer_charter() -> void:
	_setup_naval_interception()
	var play := PlaySession.new()
	play.player_faction = 0
	play.observer_mode = true
	play.ai = AiState.new()
	play.ai.economy_for(0).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, play.has_tech
		),
		0.5 * 5.0 / 8.0,
		0.0001
	)

func test_the_dossier_reads_the_privateer_charter() -> void:
	_setup_naval_interception()
	var play := PlaySession.new()
	play.player_faction = 0
	play.model = _naval_interception_model
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	var fleet := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	fleet.mission = FleetState.Mission.PATROL
	assert_false(MapPlayFleetMissions.note(play, fleet).contains("Privateers"))
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	var note: String = MapPlayFleetMissions.note(play, fleet)
	assert_true(note.contains("On patrol"))
	assert_true(note.contains("Privateers"))
	assert_true(note.contains("+25%"))
	# A squadron in port can take no station, so the charter is not dangled.
	var docked := FleetState.in_port(2, 0, 0, ["home_1"], {"home_1": "fluyte"})
	assert_false(MapPlayFleetMissions.note(play, docked).contains("Privateers"))
	economy.free()

# --- test_naval_movement ---
## Sea-going fleet movement and docking (wiki: ships-and-naval, map-topology).

const naval_movement_NavalFixture = preload("res://tests/naval_fixture.gd")
var _naval_movement_model: MapModel = null

func _setup_naval_movement() -> void:
	_suite_setup = "naval_movement"
	_naval_movement_model = naval_movement_NavalFixture.build()


func test_province_sea_zones_lists_adjacent_water() -> void:
	_setup_naval_movement()
	assert_eq(NavalMovement.province_sea_zones(_naval_movement_model, 0), [0])
	assert_eq(NavalMovement.province_sea_zones(_naval_movement_model, 1), [1])
	assert_eq(NavalMovement.province_sea_zones(_naval_movement_model, 99), [])


func test_owned_provinces_by_zone() -> void:
	_setup_naval_movement()
	assert_eq(NavalMovement.owned_provinces_by_zone(_naval_movement_model, 0, 0), [0])
	assert_eq(NavalMovement.owned_provinces_by_zone(_naval_movement_model, 1, 0), [])
	assert_eq(NavalMovement.owned_provinces_by_zone(_naval_movement_model, 0, 1), [])


## One reading says where a court's seat harbour and home harbour are: the seat
## when it has a port, else the lowest-id own harbour, else NO_ID (wiki:
## ships-and-naval § Home Fleet, § Cargo holds and capacity).
func test_seat_and_home_harbour_read_the_same_seat() -> void:
	_setup_naval_movement()
	var model: MapModel = _naval_movement_model
	assert_eq(NavalMovement.seat_harbour(model, 0), 0)
	assert_eq(NavalMovement.home_harbour(model, 0), 0)
	# A court with a harbour but no capital seat still musters somewhere.
	assert_eq(NavalMovement.seat_harbour(model, 1), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(model, 1), 1)
	assert_eq(NavalMovement.seat_harbour(model, 9), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(model, 9), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(null, 0), MapModel.NO_ID)


## The seat outranks a lower-id harbour, and an inland seat falls back to the
## lowest-id own harbour rather than reading NO_ID.
func test_home_harbour_prefers_the_seat_then_the_lowest_id() -> void:
	_setup_naval_movement()
	var model: MapModel = _naval_movement_model
	model.provinces[1].owner = 0
	assert_eq(NavalMovement.home_harbour(model, 0), 0, "the seat outranks province 1")
	model.provinces[0].port_tile = Vector2i(-1, -1)
	assert_eq(NavalMovement.seat_harbour(model, 0), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(model, 0), 1, "an inland seat falls back to a port")


## The chart keeps the sea zone on the water, not on the quay, so a sheet that
## reads the port tile's own zone names no water at all. One reading answers the
## water the harbour opens on — the zone beside the quay — and the realm row, the
## province dossier and the observatory all name it (wiki:
## capital-and-connectivity § Blockade; DR-20261124-05).
func test_harbour_zone_reads_the_water_beside_the_quay() -> void:
	_setup_naval_movement()
	var model: MapModel = _naval_movement_model
	assert_eq(model.sea_zone_at(1, 0), MapModel.NO_ID, "the quay sits on land")
	assert_eq(NavalMovement.harbour_zone(model, 0), 0, "the Mar Caribe beside it")
	assert_eq(
		ProvinceLedger.harbour_name(model, model.province_data(0)), "Mar Caribe",
		"the sheet names the water, not a bare separator"
	)
	assert_eq(NavalMovement.port_sea_zones(model, 0), [0], "and the gate stands there")
	# A province with no port tile opens on no water at all.
	model.province_data(0).port_tile = Vector2i(-1, -1)
	assert_eq(NavalMovement.harbour_zone(model, 0), MapModel.NO_ID)
	assert_eq(ProvinceLedger.harbour_name(model, model.province_data(0)), "")
	assert_eq(NavalMovement.harbour_zone(null, 0), MapModel.NO_ID)
	assert_eq(NavalMovement.harbour_zone(model, 99), MapModel.NO_ID)


## A quay the chart keeps in the water faces the water it stands in: the sheet
## names that zone and a blockade may stand in it, though no orthogonal tile of
## the quay is water (wiki: ships-and-naval § Missions and Movement — the
## blockading fleet stands in a sea zone adjacent to the port; DR-20261124-05).
func test_a_quay_in_the_water_faces_its_own_zone() -> void:
	var model := MapModel.new()
	model.setup(5, 3)
	var land: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if tile == Vector2i(2, 1):
				continue
			model.province[model.index_of(x, y)] = 0
			land.append(tile)
	# A channel one tile wide: its water touches land on every side.
	model.terrain[model.index_of(2, 1)] = MapModel.Terrain.OCEAN
	model.sea_zone[model.index_of(2, 1)] = 0
	var province := ProvinceState.create(0, "Riva", land, Vector2(2.0, 1.0), land.size(), 0, true)
	province.port_tile = Vector2i(2, 1)
	model.provinces = [province]
	model.sea_zones = [
		SeaZoneState.create(0, "Canal", [Vector2i(2, 1)], Vector2(2.0, 1.0), 1)
	]
	assert_eq(NavalMovement.harbour_zone(model, 0), 0, "the quay's own water")
	assert_eq(ProvinceLedger.harbour_name(model, province), "Canal")
	assert_eq(
		NavalMovement.port_sea_zones(model, 0), [0],
		"a quay in the water faces the water it stands in"
	)
	assert_true(
		bool(FleetMissions.can_assign(
			model, FleetState.at_sea(1, 1, 0), FleetState.Mission.BLOCKADE, 0, _war
		)["ok"]),
		"the blockade stands in that water"
	)


func test_sea_fleet_moves_one_adjacent_zone() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(NavalMovement.destination_zones(_naval_movement_model, fleet), [1])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["entered_zone"]), 1)
	assert_eq(fleet.sea_zone, 1)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved)


func test_same_zone_is_not_a_move() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_false(bool(result["ok"]))
	assert_eq(fleet.sea_zone, 0)
	assert_false(fleet.moved)


func test_fleet_may_move_only_once_per_turn() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	NavalMovement.apply_move(_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1)
	var second: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_false(bool(second["ok"]))
	assert_eq(fleet.sea_zone, 1)
	assert_true(String(second["reason"]).contains("already moved"))


func test_begin_turn_restores_the_move() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	NavalMovement.apply_move(_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1)
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved)
	var check: Dictionary = NavalMovement.can_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_true(bool(check["ok"]))


func test_docking_requires_ownership() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 1
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("owns"))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)


func test_docking_requires_adjacent_coast() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 0
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("border"))


func test_fleet_docks_at_a_harbour() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(NavalMovement.dockable_provinces(_naval_movement_model, fleet), [0])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 0
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["entered_zone"]), -1)
	assert_eq(fleet.location, FleetState.Location.IN_PORT)
	assert_eq(fleet.province, 0)
	assert_eq(fleet.sea_zone, MapModel.NO_ID)


func test_port_fleet_undocks_into_adjacent_zone() -> void:
	_setup_naval_movement()
	# Province 1 is a non-capital port, so this is a sea-going squadron.
	var fleet := FleetState.in_port(2, 0, 1)
	assert_eq(NavalMovement.destination_zones(_naval_movement_model, fleet), [1])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1
	)

	assert_true(bool(result["ok"]))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)
	assert_eq(fleet.sea_zone, 1)
	assert_eq(fleet.province, MapModel.NO_ID)


func test_port_fleet_cannot_move_to_another_port() -> void:
	_setup_naval_movement()
	var fleet := FleetState.in_port(2, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 1
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("already in port"))


func test_province_without_a_harbour_cannot_be_entered() -> void:
	_setup_naval_movement()
	_naval_movement_model.provinces[0].port_tile = Vector2i(-1, -1)
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_false(NavalMovement.has_harbour(_naval_movement_model, 0))
	assert_eq(NavalMovement.dockable_provinces(_naval_movement_model, fleet), [])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 0
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("harbour"))


func test_unknown_zone_is_rejected() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 99
	)
	assert_false(bool(result["ok"]))
	assert_eq(fleet.sea_zone, 0)


func test_valid_destinations_match_the_location() -> void:
	_setup_naval_movement()
	var sea: Dictionary = NavalMovement.valid_destinations(
		_naval_movement_model, FleetState.at_sea(1, 0, 0)
	)
	assert_eq(sea["sea_zones"], [1])
	assert_eq(sea["provinces"], [0])

	var port: Dictionary = NavalMovement.valid_destinations(
		_naval_movement_model, FleetState.in_port(2, 0, 1)
	)
	assert_eq(port["sea_zones"], [1])
	assert_eq(port["provinces"], [])


func test_the_home_fleet_never_sails() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0)
	assert_true(NavalMovement.is_home_fleet(_naval_movement_model, home))
	assert_eq(NavalMovement.destination_zones(_naval_movement_model, home), [])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, home, FleetState.Location.AT_SEA, 0
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("home fleet"))
	assert_eq(home.location, FleetState.Location.IN_PORT)
	assert_eq(home.province, 0)


func test_docking_at_the_capital_merges_into_the_home_fleet() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "sloop"})
	var roster: Array[FleetState] = [home, incoming]

	var dock: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0
	)
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)
	var merged: FleetState = merge.get("fleet") as FleetState

	assert_true(bool(dock["ok"]))
	assert_eq(merged, home)
	assert_eq(roster.size(), 1)
	assert_eq(home.hulls, ["ship_a", "ship_b"], "instance ids survive in order")
	assert_eq(home.type_of("ship_b"), "sloop")


func test_merging_never_duplicates_a_hull_instance() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_a", "ship_b"], {"ship_b": "fluyte"})
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0)
	NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)

	assert_eq(home.hulls, ["ship_a", "ship_b"])
	assert_eq(home.count_of_type("carrack"), 1)


func test_docking_at_a_non_capital_port_does_not_merge() -> void:
	_setup_naval_movement()
	_naval_movement_model.provinces[1].owner = 0
	var home := FleetState.in_port(2, 0, 0)
	var incoming := FleetState.at_sea(3, 0, 1)
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 1)

	assert_false(NavalMovement.is_home_fleet(_naval_movement_model, incoming))
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)
	assert_null(merge.get("fleet"))
	assert_eq(roster.size(), 2)


func test_fleet_state_defaults_to_one_hull() -> void:
	_setup_naval_movement()
	var sea := FleetState.at_sea(4, 2, 0)
	assert_eq(sea.ship_count(), 1)
	assert_eq(sea.hulls, ["ship_4"])
	assert_true(sea.is_at_sea())

	var port := FleetState.in_port(5, 1, 0, ["ship_a", "ship_b"])
	assert_eq(port.ship_count(), 2)
	assert_true(port.is_in_port())
	assert_false(port.moved)


func test_fleet_hulls_keep_their_catalog_types() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(6, 0, 0, ["ship_6"], {"ship_6": "sloop"})
	assert_eq(fleet.type_of("ship_6"), "sloop")
	# Unmapped and unknown hulls count as the default carrack.
	assert_eq(fleet.type_of("ship_unknown"), "carrack")
	var legacy := FleetState.in_port(7, 0, 0, ["ship_7"])
	assert_eq(legacy.type_of("ship_7"), "carrack")
	assert_eq(legacy.count_of_type("carrack"), 1)


func test_fleet_hulls_can_be_added_removed_and_summarised() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(8, 0, 0, ["ship_8"], {"ship_8": "carrack"})
	fleet.add_hull("ship_9", "galleon")
	fleet.add_hull("ship_9", "sloop")
	assert_eq(fleet.ship_count(), 2)
	assert_eq(fleet.count_of_type("galleon"), 1)
	assert_eq(fleet.hull_summary(), "1 Carrack · 1 Galleon")
	assert_true(fleet.remove_hull("ship_8"))
	assert_false(fleet.remove_hull("ship_8"))
	assert_eq(fleet.hull_summary(), "1 Galleon")
	assert_true(fleet.is_afloat())
	fleet.remove_hull("ship_9")
	assert_false(fleet.is_afloat())


# --- naval transport (wiki: ships-and-naval § Naval transport) ----------------


func _naval_movement_transport_pair() -> Array:
	var fleet := FleetState.in_port(3, 0, 0, ["ship_3"])
	var army := ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	return [army, fleet]


func test_one_hull_carries_one_regiment() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	assert_eq(NavalDeck.capacity(fleet), 1)
	assert_true(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	assert_true(bool(NavalTransport.embark(_naval_movement_model, army, fleet)["ok"]))
	assert_eq(army.province, MapModel.NO_ID)
	assert_true(army.moved)
	assert_eq(army.embarked_fleet, fleet.id)
	assert_eq(fleet.embarked_army, army.id)


func test_transport_capacity_refuses_an_army_larger_than_the_squadron() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var fleet: FleetState = pair[1]
	var army := ArmyState.muster(8, 0, 0, false, ["pikemen", "pikemen"], 800)
	var check: Dictionary = NavalTransport.can_embark(_naval_movement_model, army, fleet)
	assert_false(bool(check["ok"]))
	assert_eq(
		String(check["reason"]),
		"The squadron has 1 hull and cannot carry 2 regiments.",
		"one hull reads singular"
	)


func test_the_home_army_never_boards() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var fleet: FleetState = pair[1]
	var home := ArmyState.muster(8, 0, 0, true, ["pikemen"], 800)
	var check: Dictionary = NavalTransport.can_embark(_naval_movement_model, home, fleet)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Home Army"))


func test_boarding_needs_a_fleet_in_this_port() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var elsewhere := FleetState.in_port(4, 0, 1, ["ship_4"])
	var check: Dictionary = NavalTransport.can_embark(_naval_movement_model, army, elsewhere)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("not in this port"))


func test_an_embarked_army_lands_on_an_owned_coast() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_true(bool(NavalTransport.disembark(_naval_movement_model, army, fleet, 0)["ok"]))
	assert_eq(army.province, 0)
	assert_eq(army.embarked_fleet, -1)
	assert_eq(fleet.embarked_army, -1)
	assert_true(army.moved)


func test_a_hostile_landing_needs_a_beachhead() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	var check: Dictionary = NavalTransport.disembark(_naval_movement_model, army, fleet, 1)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("beachhead"))


## A squadron that keeps afloat on fewer hulls keeps only the men her deck still
## holds: one hull carries one regiment, so a sunk hull drowns hers (wiki:
## ships-and-naval § Naval transport; § Naval Combat Resolution — a victor still
## loses hulls to the beaten side's strength).
func test_a_sunk_hull_takes_her_regiment_with_her() -> void:
	var fleet := FleetState.at_sea(5, 0, 0, ["ship_5", "ship_6", "ship_7"])
	var army := ArmyState.muster(11, 0, 0, false, ["pikemen", "knights", "musketeers"], 1100)
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	fleet.remove_hull("ship_7")
	var drowned: Dictionary = NavalDeck.trim_aboard(fleet, army)
	var men: Array = drowned["regiments"]
	assert_eq(men.size(), 1, "one hull lost, one regiment drowned")
	assert_eq(army.count(), 2)
	assert_eq(String(men[0]), "unit_1100", "the weakest colours drowns first")
	assert_false(army.regiments.has("unit_1100"))
	assert_eq(fleet.embarked_army, army.id, "the men left aboard still ride her")
	assert_eq(NavalDeck.aboard(fleet, army), 2, "one hull, one man")
	assert_eq(
		NavalDeck.drown_news(drowned),
		["1 regiment went down with the sunk hulls — the deck could not hold them"],
		"the bar names the one regiment it lost"
	)


## A deck the sea empties carries no army any more, and the standard leaves with
## the men (wiki: military-armies § Dismissing regiments — an embarked army that
## retires leaves the deck with the field).
func test_a_deck_that_empties_puts_the_standard_aside() -> void:
	var fleet := FleetState.at_sea(6, 0, 0, ["ship_8"])
	var army := ArmyState.muster(12, 0, 0, false, ["pikemen"], 1200)
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	fleet.remove_hull("ship_8")
	NavalDeck.trim_aboard(fleet, army)
	assert_true(army.is_empty())
	assert_eq(fleet.embarked_army, -1, "an empty deck carries no army")
	assert_eq(army.embarked_fleet, -1, "and no man is still aboard")


## A raid sinks a merchant hull under the colonists she carries (wiki:
## ships-and-naval § Civilian passengers — one hull carries one civilian).
func test_a_sunk_hull_takes_her_colonist_with_her() -> void:
	var fleet := FleetState.in_port(7, 0, 0, ["ship_9", "ship_10", "ship_11"])
	fleet.add_civilian(21)
	fleet.add_civilian(22)
	fleet.add_civilian(23)
	fleet.remove_hull("ship_11")
	var drowned: Dictionary = NavalDeck.trim_aboard(fleet, null)
	var colonists: Array = drowned["civilians"]
	assert_eq(colonists.size(), 1, "one hull lost, one colonist drowned")
	assert_eq(int(colonists[0]), 23, "the last hand aboard drowns first")
	assert_eq(fleet.civilian_count(), 2)
	assert_eq(NavalDeck.aboard(fleet, null), 2)
	assert_eq(NavalDeck.drown_news(drowned), ["A colonist went down with a sunk hull"])


## The turn's close reads every deck: whichever loss took the hull — a battle's
## sinking or a raid's prize — the men it leaves without a deck go down, and a
## standard the sea emptied retires off the roster.
func test_the_deck_is_reconciled_after_the_hulls_are_lost() -> void:
	var layer := ArmyLayer.new()
	var army := ArmyState.muster(13, 0, 0, false, ["pikemen", "knights"], 1300)
	var fleet := FleetState.at_sea(8, 0, 0, ["ship_12"])
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	var roster: Array[ArmyState] = [army]
	layer.regions.set_region(0, roster)
	var rows: Array[Dictionary] = ArmyTransport.reconcile_aboard(layer, [fleet])
	assert_eq(rows.size(), 1, "the squadron that drowned a man is named")
	assert_eq(int(rows[0]["owner"]), 0)
	assert_eq(army.count(), 1)
	assert_eq(fleet.embarked_army, army.id, "one man still rides her")
	fleet.remove_hull("ship_12")
	ArmyTransport.reconcile_aboard(layer, [fleet])
	assert_eq(fleet.embarked_army, -1)
	var left: Array = layer.regions.value(0, [])
	assert_true(left.is_empty(), "the emptied standard retires")
	layer.free()


## The turn's close reads every deck on both charts: a squadron afloat on fewer
## hulls than men drowns the surplus, whichever loss took the hull (wiki:
## ships-and-naval § Naval transport — "each hull carries one regiment").
func test_the_turn_close_reads_every_deck() -> void:
	var world: WorldMap = naval_transport_AiFixture.land_world([0])
	var layer := ArmyLayer.new()
	var army := ArmyState.muster(14, 0, 0, false, ["pikemen", "knights", "musketeers"], 1400)
	var fleet := FleetState.at_sea(9, 0, 0, ["ship_13", "ship_14"])
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	var roster: Array[ArmyState] = [army]
	layer.regions.set_region(0, roster)
	var ships := ShipLayer.new()
	ships.regions.set_region(0, [fleet] as Array[FleetState])
	var play := PlaySession.new()
	play.world = world
	play.player_faction = 0
	play.army_layer = layer
	play.ship_layer = ships
	var rows: Array[Dictionary] = MapPlayNavalTurn.reconcile_decks(play)
	assert_eq(rows.size(), 1, "two hulls could not hold three regiments")
	assert_eq(army.count(), 2)
	assert_eq(fleet.embarked_army, army.id)
	assert_true(MapPlayNavalTurn.reconcile_decks(play).is_empty(), "a full deck is silent")
	layer.free()
	ships.free()


## A raid's prize sinks a merchant hull under the colonist she carries: the turn
## close takes the drowned hand out of play then and there, so the crown counts
## no passenger the sea has taken and the next naval watch has no second loss to
## announce (wiki: ships-and-naval § Naval transport — a hull sent down by a raid
## takes her colonist with her, the last hand aboard first; § Civilian
## passengers; § Losses).
func test_a_raid_drowns_her_colonist_out_of_the_roster() -> void:
	var world: WorldMap = naval_transport_AiFixture.land_world([0])
	var fleet := FleetState.in_port(7, 0, 0, ["ship_9", "ship_10"])
	var first := CivilianState.create(21, 0, "colonist", CivilianState.NO_TILE)
	first.embarked_fleet = fleet.id
	fleet.add_civilian(first.id)
	var last := CivilianState.create(22, 0, "colonist", CivilianState.NO_TILE)
	last.embarked_fleet = fleet.id
	fleet.add_civilian(last.id)
	var civilians := CivilianLayer.new()
	var roster: Array[CivilianState] = [first, last]
	civilians.regions.set_region(0, roster)
	var ships := ShipLayer.new()
	ships.regions.set_region(0, [fleet] as Array[FleetState])
	var play := PlaySession.new()
	play.world = world
	play.player_faction = 0
	play.army_layer = ArmyLayer.new()
	play.ship_layer = ships
	play.civilian_layer = civilians
	# The raid: one hull of two goes down.
	fleet.remove_hull("ship_10")
	var rows: Array[Dictionary] = MapPlayNavalTurn.reconcile_decks(play)
	assert_eq(rows.size(), 1, "the squadron that drowned a colonist is named")
	assert_eq(int((rows[0]["civilians"] as Array)[0]), 22, "the last hand aboard drowns first")
	assert_eq(fleet.civilian_count(), 1, "the deck keeps the hand it still holds")
	assert_true(
		CivilianVoyageMap.by_id(civilians, 22) == null,
		"the drowned colonist leaves the roster at once"
	)
	assert_eq(civilians.regions.value(0, []).size(), 1, "one hand still musters")
	assert_true(
		CivilianVoyageMap.drop_lost(civilians, FleetRosters.carried_civilians(ships.regions)).is_empty(),
		"the next naval watch has no drowned hand left to announce"
	)
	# No ids and no layer take nobody, and a hand the trim did not name is never
	# taken: the roster answers only the loss it was told.
	assert_true(CivilianVoyageMap.drown(civilians, []).is_empty(), "an empty loss takes nobody")
	assert_true(CivilianVoyageMap.drown(null, [22]).is_empty(), "a court with no roster drowns nobody")
	# The shown region's own list answers the same way, and its marker leaves
	# with the hand (wiki: ships-and-naval § Losses).
	var shown := CivilianLayer.new()
	shown.model = world.region(0)
	var crew: Array[CivilianState] = [
		CivilianState.create(31, 0, "colonist", Vector2i(0, 0)),
	]
	shown.units = crew
	shown.regions.set_region(0, crew)
	assert_true(CivilianVoyageMap.drown(shown, [32]).is_empty(), "a stranger is no loss")
	assert_eq(CivilianVoyageMap.drown(shown, [31]).size(), 1, "the drowned hand leaves the shown list")
	assert_true(shown.units.is_empty(), "the map keeps no marker for a drowned hand")
	shown.free()
	play.army_layer.free()
	ships.free()
	civilians.free()


## A marked beachhead opens the hostile coast on the following turn only, and
## the landing consumes it (wiki: ships-and-naval § Missions and Movement).
func test_beachhead_opens_a_hostile_coast_on_the_following_turn() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_eq(NavalTransport.hostile_coasts(_naval_movement_model, fleet), [1])
	var marked: Dictionary = NavalTransport.establish_beachhead(_naval_movement_model, fleet, 1, 5)
	assert_true(bool(marked["ok"]))
	assert_true(fleet.moved)
	assert_eq(fleet.beachhead_province, 1)
	assert_eq(fleet.beachhead_turn, 5)
	assert_false(bool(NavalTransport.beachhead_ready(fleet, 5)))
	assert_true(bool(NavalTransport.beachhead_ready(fleet, 6)))
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet, 5), [])
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet, 6), [1])
	# A site already held names its own wait rather than asking for a beachhead.
	var early: Dictionary = NavalTransport.disembark(_naval_movement_model, army, fleet, 1, 5)
	assert_false(bool(early["ok"]))
	assert_true(String(early["reason"]).contains("opens next turn"))
	assert_false(bool(NavalTransport.disembark(_naval_movement_model, army, fleet, 1, 5)["ok"]))
	assert_true(bool(NavalTransport.disembark(_naval_movement_model, army, fleet, 1, 6)["ok"]))
	assert_eq(army.province, 1)
	assert_eq(army.embarked_fleet, -1)
	assert_true(army.moved)
	assert_false(fleet.has_beachhead())
	# The landing is an invasion: the army is a contestant in the province.
	var armies: Array[ArmyState] = [army]
	assert_eq(ArmyCombat.contested_provinces(_naval_movement_model, armies), [1])


## A site open by the clock but no longer a hostile shore names the loss, not a
## wait: the coast changed hands or the war ended, so no turn will open it.
func test_a_lapsed_beachhead_names_the_loss_not_a_wait() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_true(bool(NavalTransport.establish_beachhead(
		_naval_movement_model, fleet, 1, 5
	)["ok"]))
	# The war ends before the site opens.
	var peace: Callable = func(_a: int, _b: int) -> bool: return false
	var lapsed: Dictionary = NavalTransport.disembark(
		_naval_movement_model, army, fleet, 1, 6, peace
	)
	assert_false(bool(lapsed["ok"]))
	assert_true(String(lapsed["reason"]).contains("lapsed"), String(lapsed["reason"]))
	assert_false(String(lapsed["reason"]).contains("opens next turn"))


func test_beachhead_lasts_one_full_turn_then_expires() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(3, 0, 1, ["ship_3"])
	fleet.moved = false
	assert_true(bool(NavalTransport.establish_beachhead(_naval_movement_model, fleet, 1, 5)["ok"]))
	var fleets: Array[FleetState] = [fleet]
	NavalTransport.expire_beachheads(fleets, 5)
	assert_true(fleet.has_beachhead())
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved)
	assert_true(bool(NavalTransport.beachhead_ready(fleet, 6)))
	NavalTransport.expire_beachheads(fleets, 6)
	assert_false(fleet.has_beachhead())


## A marker whose coast changes hands or whose war ends has no hostile landing
## left; the rules gate the landing, so the marker must not promise one.
func test_a_beachhead_target_must_stay_a_hostile_shore() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(3, 0, 1, ["ship_3"])
	fleet.moved = false
	assert_true(bool(NavalTransport.establish_beachhead(_naval_movement_model, fleet, 1, 5)["ok"]))
	assert_true(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	_naval_movement_model.province_data(1).owner = 0
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	_naval_movement_model.province_data(1).owner = 1
	var peaceful := func(_a: int, _b: int) -> bool: return false
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet, peaceful))
	assert_true(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	fleet.sea_zone = 0
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	assert_false(NavalTransport.beachhead_target_valid(null, fleet))
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, null))


func test_beachhead_refusals_cover_each_gate() -> void:
	_setup_naval_movement()
	var own_coast := FleetState.at_sea(3, 0, 0, ["ship_3"])
	assert_false(bool(NavalTransport.can_establish_beachhead(_naval_movement_model, own_coast, 0)["ok"]))
	var moved := FleetState.at_sea(4, 0, 1, ["ship_4"])
	moved.moved = true
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, moved, 1)["reason"]
	).contains("already moved"))
	var docked := FleetState.in_port(5, 0, 0, ["ship_5"])
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, docked, 1)["reason"]
	).contains("at sea"))
	var empty := FleetState.at_sea(6, 0, 1, [] as Array[String])
	empty.hulls = []
	empty.hull_types = {}
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, empty, 1)["reason"]
	).contains("no hulls"))
	var far := FleetState.at_sea(7, 0, 0, ["ship_7"])
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, far, 1)["reason"]
	).contains("border"))
	var peaceful := func(_a: int, _b: int) -> bool: return false
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, own_coast, 1, 0, peaceful)["reason"]
	).contains("declared war"))
	assert_false(bool(NavalTransport.can_establish_beachhead(null, own_coast, 1)["ok"]))
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, own_coast, 99)["reason"]
	).contains("not a province"))
	assert_false(bool(NavalTransport.establish_beachhead(_naval_movement_model, moved, 1, 0)["ok"]))
	assert_false(bool(NavalTransport.beachhead_ready(null, 0)))
	assert_false(NavalTransport.beachhead_allows(null, null, 1))
	assert_false(NavalTransport.beachhead_allows(_naval_movement_model, null, 1))
	assert_eq(NavalTransport.hostile_coasts(null, own_coast).size(), 0)
	assert_eq(NavalTransport.hostile_coasts(_naval_movement_model, own_coast).size(), 0)
	var own_mark := FleetState.at_sea(8, 0, 0, ["ship_8"])
	own_mark.beachhead_province = 0
	own_mark.beachhead_turn = 4
	assert_false(NavalTransport.beachhead_allows(_naval_movement_model, own_mark, 0, 5))
	var mixed: Array[FleetState] = [null]
	NavalTransport.expire_beachheads(mixed, 5)


func test_landing_requires_the_fleet_to_border_the_coast() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	var check: Dictionary = NavalTransport.disembark(_naval_movement_model, army, fleet, 0)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("border"))


func test_landing_provinces_follow_the_sea_zone() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet), [0])
	fleet.sea_zone = 1
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet), [])


func test_breaking_up_a_hull_cannot_strand_the_troops() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	assert_false(bool(NavalDeck.can_scrap(fleet, army)["ok"]))
	fleet.add_hull("ship_5")
	assert_true(bool(NavalDeck.can_scrap(fleet, army)["ok"]))


func test_transport_state_survives_a_save_round_trip() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.beachhead_province = 1
	fleet.beachhead_turn = 5
	var saved_army: ArmyState = ArmyState.from_dict(army.to_dict())
	var saved_fleet: FleetState = FleetState.from_dict(fleet.to_dict())
	assert_eq(saved_army.embarked_fleet, fleet.id)
	assert_eq(saved_army.province, MapModel.NO_ID)
	assert_eq(saved_fleet.embarked_army, army.id)
	assert_eq(saved_fleet.beachhead_province, 1)
	assert_eq(saved_fleet.beachhead_turn, 5)


func _transport_layer(army: ArmyState) -> ArmyLayer:
	var layer := ArmyLayer.new()
	layer.model = _naval_movement_model
	var armies: Array[ArmyState] = [army]
	layer.armies = armies
	layer.regions.set_region(_naval_movement_model.region_id, layer.armies)
	return layer


func test_an_embarked_army_follows_its_fleet_between_regions() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	ArmyTransport.move_to_region(layer, army.id, 1)
	assert_eq(layer.armies.size(), 0)
	var destination: Array[ArmyState] = []
	destination.assign(layer.regions.value(1, []))
	assert_eq(destination.size(), 1)
	assert_true(destination[0] == army)
	layer.free()


func test_a_passage_leaves_no_ghost_on_the_old_roster() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	## A turn pass that hands the table its own list (the land turn's Home Army
	## recall does) must not let a passage leave the army standing on both charts:
	## a save would then hold it twice (wiki: campaign-persistence — a save holds
	## armies and regiments; ships-and-naval § Naval transport).
	var filed: Array[ArmyState] = []
	filed.assign(layer.armies)
	layer.regions.set_region(_naval_movement_model.region_id, filed)
	ArmyTransport.move_to_region(layer, army.id, 1)
	var home: Array[ArmyState] = []
	home.assign(layer.regions.value(_naval_movement_model.region_id, []))
	assert_eq(home.size(), 0, "the army leaves the chart it sailed from")
	assert_eq(ArmyTransport.region_of(layer, army), 1, "and stands on the chart it reached")
	layer.free()


func test_the_roster_store_guards_a_missing_layer_and_a_bare_chart() -> void:
	ArmyTransport.publish(null)
	var filed: Array[ArmyState] = []
	ArmyTransport.store(null, 0, filed)
	var bare := ArmyLayer.new()
	ArmyTransport.store(bare, 0, filed)
	assert_true(is_same(bare.regions.value(0, []), filed), "a stored list is the table's")
	ArmyTransport.publish(bare)
	assert_eq(bare.armies.size(), 0, "a chart with no model publishes nothing")
	bare.free()


func test_a_sunk_squadrons_army_leaves_the_roster() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, {})
	assert_eq(lost.size(), 1)
	assert_true(lost[0] == army)
	assert_eq(layer.armies.size(), 0)
	layer.free()


func test_a_live_squadron_keeps_its_army() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	var live: Dictionary = {}
	live[army.id] = fleet.id
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, live)
	assert_eq(lost.size(), 0)
	assert_eq(layer.armies.size(), 1)
	layer.free()


func test_embarkation_refusals_cover_each_gate() -> void:
	_setup_naval_movement()
	var fleet := FleetState.in_port(3, 0, 0, ["ship_3"])
	var army := ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, null, fleet)["ok"]))
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, null)["ok"]))
	var foreign := ArmyState.muster(8, 1, 0, false, ["pikemen"], 800)
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, foreign, fleet)["ok"]))
	var empty := ArmyState.muster(9, 0, 0, false, [], 900)
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, empty, fleet)["ok"]))
	army.embarked_fleet = 5
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	army.embarked_fleet = -1
	army.moved = true
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	army.moved = false
	fleet.location = FleetState.Location.AT_SEA
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	fleet.location = FleetState.Location.IN_PORT
	fleet.moved = true
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	fleet.moved = false
	fleet.embarked_army = 9
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	fleet.embarked_army = -1
	assert_false(bool(NavalTransport.can_embark(null, army, fleet)["ok"]))


func test_landing_refusals_cover_each_gate() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, null, fleet, 0)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, null, 0)["ok"]))
	var outsider := ArmyState.muster(8, 0, 0, false, ["pikemen"], 800)
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, outsider, fleet, 0)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 99)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 1)["ok"]))
	_naval_movement_model.province_data(1).owner = 0
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 1)["ok"]))
	_naval_movement_model.province_data(1).owner = 1
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 0)["ok"]))
	fleet.sea_zone = 0
	assert_true(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 0)["ok"]))


func test_port_landing_and_scrap_gates() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet), [0])
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, null), [])
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, FleetState.at_sea(4, 0, 0)), [0])
	assert_true(bool(NavalDeck.can_scrap(null, army)["ok"]))
	assert_false(bool(NavalDeck.can_scrap(fleet, null)["ok"]))


func test_transport_layer_lookups_and_refusals() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	var layer: ArmyLayer = _transport_layer(army)
	assert_null(ArmyTransport.army_by_id(layer, -1))
	assert_null(ArmyTransport.army_by_id(layer, 999))
	assert_true(ArmyTransport.army_by_id(layer, army.id) == army)
	assert_eq(ArmyTransport.region_of(layer, army), _naval_movement_model.region_id)
	assert_false(bool(ArmyTransport.embark(layer, army, FleetState.at_sea(3, 0, 0))["ok"]))
	assert_false(bool(ArmyTransport.disembark(layer, null, 0)["ok"]))
	assert_false(bool(ArmyTransport.disembark(layer, fleet, 0)["ok"]))
	ArmyTransport.move_to_region(layer, 999, 1)
	ArmyTransport.remove_from(layer, army, _naval_movement_model.region_id)
	assert_eq(layer.armies.size(), 0)
	layer.free()


## A merge may leave an army pointing at a squadron the chart no longer holds;
## seat_carried rewrites that seat onto the squadron that keeps the troops
## (wiki: military-armies § The muster roll). Guards stay quiet when the layer,
## the squadron or the embarked id is missing.
func test_seat_carried_rewrites_a_lagging_army_pointer() -> void:
	_setup_naval_movement()
	var army := ArmyState.create(7, 0, 0, false, ["unit_7"], {"unit_7": "pikemen"})
	army.embarked_fleet = 99
	var layer: ArmyLayer = _transport_layer(army)
	var fleet := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	fleet.embarked_army = army.id

	ArmyTransport.seat_carried(null, fleet)
	ArmyTransport.seat_carried(layer, null)
	var empty := FleetState.in_port(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	ArmyTransport.seat_carried(layer, empty)
	assert_eq(army.embarked_fleet, 99, "an empty deck does not rewrite a seat")

	empty.embarked_army = 999
	ArmyTransport.seat_carried(layer, empty)
	assert_eq(army.embarked_fleet, 99, "a missing army id is a no-op")

	ArmyTransport.seat_carried(layer, fleet)
	assert_eq(army.embarked_fleet, fleet.id, "the army answers the squadron that carries her")
	ArmyTransport.seat_carried(layer, fleet)
	assert_eq(army.embarked_fleet, fleet.id, "an already-correct seat stays put")
	layer.free()


func test_transport_layer_same_region_move_is_a_no_op() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	ArmyTransport.move_to_region(layer, army.id, _naval_movement_model.region_id)
	assert_eq(layer.armies.size(), 1)
	ArmyTransport.move_to_region(layer, army.id, 1)
	assert_eq(ArmyTransport.region_of(layer, army), 1)
	layer.free()


func test_drop_lost_leaves_unembarked_armies_alone() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var grounded := ArmyState.muster(11, 0, 0, false, ["pikemen"], 1100)
	var layer: ArmyLayer = _transport_layer(army)
	layer.armies.append(grounded)
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, {})
	assert_eq(lost.size(), 1)
	assert_eq(layer.armies.size(), 1)
	assert_true(layer.armies[0] == grounded)
	layer.free()


## The squadron's own roster names the troops it carries; the army's
## back-pointer may lag a merge, and that must not block the landing
## (wiki: ships-and-naval § Naval transport; DR-20261109-17).
func test_an_army_lands_after_its_squadron_was_merged() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	var army := ArmyState.create(7, 0, 0, false, ["unit_7"], {"unit_7": "pikemen"})
	army.embarked_fleet = incoming.id
	incoming.embarked_army = army.id
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)
	var merged: FleetState = merge.get("fleet") as FleetState

	assert_eq(merged.embarked_army, army.id, "the home fleet keeps the troops")
	assert_eq(army.embarked_fleet, incoming.id, "the army's own pointer lags")
	var check: Dictionary = NavalTransport.can_disembark(_naval_movement_model, army, merged, 0)
	assert_true(bool(check.get("ok", false)), String(check.get("reason", "")))


## One squadron carries one army: a merge keeps the target's troops and reports
## the surplus army so the layer can land it at the port (wiki: ships-and-naval
## § Naval transport).
func test_a_merge_keeps_one_army_and_reports_the_other() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	home.embarked_army = 10
	incoming.embarked_army = 11
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)

	assert_eq(home.embarked_army, 10, "the moored army stays aboard")
	assert_eq(int(merge["displaced"]), 11, "the surplus army is reported")
	assert_eq(incoming.embarked_army, -1, "the merged-away squadron is emptied")

# --- test_naval_raid ---
## Cargo raids by patrol/blockade squadrons (wiki: ships-and-naval § Trade and
## Transport Interception; DR-20261109-16).

const naval_raid_NavalFixture = preload("res://tests/naval_fixture.gd")
var _naval_raid_model: MapModel = null

func _setup_naval_raid() -> void:
	_suite_setup = "naval_raid"
	_naval_raid_model = naval_raid_NavalFixture.build()
	# Each coast is a crown's own seat: the rival's home fleet lies in port at
	# Coro, and only a capital's harbour is a home fleet (wiki: ships-and-naval
	# § Home Fleet — a ship is home only in port at the capital; § Cargo holds and
	# capacity — the home squadron's merchant hulls are the only holds at risk).
	_naval_raid_model.province_data(1).capital = true


func _naval_raid_fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet


func _naval_raid_raider(mission: int = FleetState.Mission.PATROL) -> FleetState:
	var fleet := FleetState.at_sea(1, 1, 0, ["raider_1"], {"raider_1": "frigate"})
	fleet.mission = mission
	return fleet


func test_a_patrol_raider_skims_a_share_of_the_imports() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0
	)
	assert_true(bool(result["ok"]))
	assert_gt(int(result["lost_total"]), 0)
	assert_gt(int((result["losses"] as Dictionary)["grain"]), 0)
	assert_between(float(result["efficiency"]), NavalRaid.MIN_EFFICIENCY, NavalRaid.MAX_EFFICIENCY)
	assert_almost_eq(float(result["chance"]), 0.5 * 5.0 / 8.0, 0.0001)


func test_escorts_cut_the_raid_chance() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var alone: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	home.add_hull("home_2", "sloop")
	var escorted: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	assert_lt(float(escorted["chance"]), float(alone["chance"]))
	assert_false(bool(escorted["ok"]))


func test_peace_and_distant_raiders_do_not_raid() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var peace := func(_a: int, _b: int) -> bool: return false
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 5}, peace, 1, 1, 0.0
	)["ok"]))
	raider.sea_zone = 1
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 5}, Callable(), 1, 1, 0.0
	)["ok"]))
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, null, {"grain": 5}, Callable(), 1, 1, 0.0
	)["ok"]))
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {}, Callable(), 1, 1, 0.0
	)["ok"]))


func test_a_blockade_raider_earns_the_bonus() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var patrol := _naval_raid_raider()
	var blockade := _naval_raid_raider(FleetState.Mission.BLOCKADE)
	blockade.blockade_province = 0
	var patrolled: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, patrol], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	var stopped: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, blockade], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	assert_gt(float(stopped["chance"]), float(patrolled["chance"]))
	assert_almost_eq(
		float(stopped["chance"]), float(patrolled["chance"]) * NavalRaid.BLOCKADE_BONUS,
		0.0001
	)


func test_privateers_improve_the_raid_chance() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var plain: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	var charter := func(owner: int, tech_id: String) -> bool:
		return owner == 1 and tech_id == NavalInterception.PRIVATEERING_TECH
	var chartered: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99, charter
	)
	assert_almost_eq(float(plain["chance"]), 0.5 * 5.0 / 8.0, 0.0001)
	# Σintercept 5 × 1.25 = 6.25 against the same flee score of 3.
	assert_almost_eq(float(chartered["chance"]), 0.5 * 6.25 / 9.25, 0.0001)
	assert_gt(float(chartered["chance"]), float(plain["chance"]))


## In the full-AI observer every crown answers from its AI ledger; the human
## ledger is frozen and must not answer for the observed crown (REQ-P2-03).
func test_the_observer_answers_tech_from_each_crowns_ledger() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.player_faction = 0
	play.observer_mode = true
	play.ai = AiState.new()
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_false(
		play.has_tech(0, NavalInterception.PRIVATEERING_TECH),
		"the human ledger does not resolve in the observer"
	)
	play.ai.economy_for(0).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	play.ai.economy_for(1).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(2, NavalInterception.PRIVATEERING_TECH))
	economy.free()


func test_the_session_answers_tech_for_the_human_and_rivals() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.player_faction = 0
	play.ai = AiState.new()
	assert_false(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	play.ai.economy_for(1).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(0, ""))
	economy.free()


func test_losses_never_exceed_the_imports() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 1}, Callable(), 1, 1, 0.0
	)
	assert_eq(int(result["lost_total"]), 1)
	assert_eq(int((result["losses"] as Dictionary)["grain"]), 1)


func test_a_blockade_bonus_does_not_cross_zones() -> void:
	_setup_naval_raid()
	# Both coasts answer to the victim, so both zones border its shore.
	_naval_raid_model.province_data(1).owner = 0
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var patrol := _naval_raid_fleet(1, 1, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var blockader := _naval_raid_fleet(2, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var lone: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, patrol], 0, home, {"grain": 10}, Callable(), 1, 1, 0.3,
		Callable(), 0.99
	)
	assert_false(bool(lone["ok"]), "a lone patrol in the far zone misses at 0.30")
	var both: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, patrol, blockader], 0, home, {"grain": 10}, Callable(), 1, 1, 0.3,
		Callable(), 0.99
	)
	assert_true(bool(both["ok"]))
	assert_eq(int(both["zone"]), 0, "the blockading squadron raids in its own zone")
	assert_almost_eq(
		float(both["chance"]),
		NavalInterception.chance([blockader], [home], FleetState.Mission.PATROL)
		* NavalRaid.BLOCKADE_BONUS,
		0.0001
	)


## The wiki weighs the raiders off the crown's coast together and lets the best
## one roll: "off its own coast it suffers the single best raid of the turn"
## (ships-and-naval § Trade and Transport Interception; DR-20261111-20 § Change —
## "the raiders off its coast are weighed together and the best one rolls").
## A weaker squadron in a lower zone must not take the raid the stronger one
## earns, in its own water and at its own efficiency.
func test_the_best_raider_off_the_coast_takes_the_raid() -> void:
	_setup_naval_raid()
	# Both coasts answer to the victim, so both zones border its shore.
	_naval_raid_model.province_data(1).owner = 0
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var weak := _naval_raid_fleet(1, 1, 0, ["sloop"])
	weak.mission = FleetState.Mission.PATROL
	var strong := _naval_raid_fleet(2, 2, 1, ["frigate"])
	strong.mission = FleetState.Mission.PATROL
	var best_chance: float = NavalRaid.trade_chance([strong], home, FleetState.Mission.PATROL)
	var weak_chance: float = NavalRaid.trade_chance([weak], home, FleetState.Mission.PATROL)
	# The strongest raid's own price, read before any hull leaves the water.
	var best_eff: float = float(
		NavalRaid.preview([strong], home, {"grain": 10}, FleetState.Mission.PATROL)["efficiency"]
	)
	assert_lt(weak_chance, best_chance, "the frigate earns the better raid")
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, weak, strong], 0, home, {"grain": 10},
		Callable(), 1, 1, 0.2
	)
	assert_true(bool(result["ok"]))
	assert_eq(int(result["raider"]), 2, "the stronger court's squadron rolls")
	assert_eq(int(result["zone"]), 1, "in her own water, not the weaker group's")
	assert_almost_eq(float(result["chance"]), best_chance, 0.0001)
	assert_almost_eq(
		float(result["efficiency"]), best_eff, 0.0001,
		"the strongest raid's efficiency is what the crown meets",
	)


## One roll decides the raid: a lucky weaker squadron cannot take cargo in a
## turn the best squadron's own roll missed (ships-and-naval § Trade and
## Transport Interception; DR-20261111-20).
func test_one_roll_decides_the_crowns_raid() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(1).owner = 0
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var weak := _naval_raid_fleet(1, 1, 0, ["sloop"])
	weak.mission = FleetState.Mission.PATROL
	var strong := _naval_raid_fleet(2, 2, 1, ["frigate"])
	strong.mission = FleetState.Mission.PATROL
	var best_chance: float = NavalRaid.trade_chance([strong], home, FleetState.Mission.PATROL)
	var weak_chance: float = NavalRaid.trade_chance([weak], home, FleetState.Mission.PATROL)
	# A seed where the best group's own roll misses and the weaker group's lands.
	var seed_value: int = 1
	while seed_value < 20000 and not (
		NavalInterception.roll(seed_value, 4, 1, 2, NavalRaid.ROLL_TAG) >= best_chance
		and NavalInterception.roll(seed_value, 4, 0, 1, NavalRaid.ROLL_TAG) < weak_chance
	):
		seed_value += 1
	assert_lt(seed_value, 20000, "the seed search finds the case")
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, weak, strong], 0, home, {"grain": 10},
		Callable(), seed_value, 4
	)
	assert_false(
		bool(result["ok"]), "the best squadron's one roll is the turn's raid"
	)


func test_the_market_reports_this_turns_imports() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 5000
	assert_true(bool(market.buy(economy, "grain", 3)["ok"]))
	assert_eq(int(market.imports_this_turn().get("grain", 0)), 3)
	assert_eq(market.bought_units(), 3)


## The live order: the crown's bid is filled by the turn's clearing, and the
## cargo it bought is what the next raid pass takes. A price pass that emptied
## the book left the raid with nothing (wiki: ships-and-naval § Trade and
## Transport Interception; DR-20261111-17).
func test_the_map_raid_pass_takes_the_cargo_the_clearing_bought() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.map_seed = 1
	while NavalInterception.roll(play.map_seed, play.turn, 0, 1, 77) >= 0.3:
		play.map_seed += 1
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.treasury = 5000
	play.ship_layer = ships
	play.economy = economy
	var submit: Dictionary = MarketOrders.submit(
		economy.market, 0, "grain", MarketOrder.SIDE_BID, 4,
		{
			"cargo_free": 4,
			"treasury": economy.economy.treasury,
			"buy_price": economy.market.buy_price("grain", 0),
		}
	)
	assert_true(bool(submit["ok"]), String(submit.get("reason", "")))
	MarketClearing.clear(economy.market, null, {0: economy.economy}, {0: 4})
	var before: int = economy.economy.quantity("grain")
	assert_eq(
		int(economy.market.imports_for(0).get("grain", 0)), 4,
		"the clearing's purchase is cargo afloat"
	)

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_true(bool(result.get("ok", false)))
	assert_gt(int(result.get("taken", 0)), 0)
	assert_lt(economy.economy.quantity("grain"), before)
	assert_true(
		economy.market.importing_factions().is_empty(),
		"the raid pass is the cargo book's one reader and closes it"
	)
	ships.free()
	economy.free()


## The lane carries the raid the crown suffers, the one that takes the crown's
## own cargo; a prize the crown's stations took reads on the Gazette's sheet
## (wiki: hud-toasts). Rings are drawn for every report either way.
func test_only_the_raid_on_the_crown_reaches_the_lane() -> void:
	var hud := DespatchHud.new()
	add_child(hud)
	var play := PlaySession.new()
	play.player_faction = 0
	play.hud = hud
	var incoming: Dictionary = {
		"kind": "incoming", "raider": 1, "zone_name": "Mar Caribe",
		"taken": 3, "losses": {"grain": 3}, "hulls_lost": [],
	}
	var prize: Dictionary = {
		"kind": "prize", "raider": 0, "victim": 2, "zone_name": "Mar Caribe",
		"taken": 2, "losses": {"timber": 2}, "hulls_lost": [],
	}

	MapPlayRaids._report(play, [incoming, prize])

	assert_eq(hud.toasts.size(), 1, "one raid is the crown's news")
	assert_true(
		hud.toasts[0].contains("England seizes 3 grain off the Mar Caribe"),
		hud.toasts[0]
	)
	hud.free()


# --- a raid takes cargo and may sink a merchant hull (DR-20261111-17) --------


func test_a_raid_sinks_a_merchant_hull() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_true(bool(result["ok"]))
	assert_eq((result["hulls_lost"] as Array).size(), 1)
	assert_eq(home.hulls.size(), 0, "the merchant went down")
	var sunk: Dictionary = (result["hulls_lost"] as Array)[0]
	assert_eq(String(sunk["type_id"]), "fluyte")
	assert_false(String(sunk["name"]).is_empty(), "the despatch can name her")
	assert_almost_eq(float(result["hull_chance"]), 0.4, 0.0001, "base 0.2 × civilian 2")
	assert_almost_eq(float(result["hull_roll"]), 0.0, 0.0001)
	assert_eq(raider.hulls.size(), 1, "the raider risks no hull of its own")


func test_a_raid_can_miss_the_hull_and_keep_every_sail() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.99
	)
	assert_true(bool(result["ok"]), "the cargo still goes")
	assert_true((result["hulls_lost"] as Array).is_empty())
	assert_eq(home.hulls.size(), 1, "the merchant came home")


func test_escorts_cut_the_hull_loss() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var alone: Dictionary = NavalRaid.preview(
		[raider], home, {"grain": 10}, FleetState.Mission.PATROL
	)
	assert_almost_eq(float(alone["hull_chance"]), 0.4, 0.0001)
	assert_eq(String(alone["hull_at_risk"]), "fluyte")
	home.add_hull("home_2", "sloop")
	var escorted: Dictionary = NavalRaid.preview(
		[raider], home, {"grain": 10}, FleetState.Mission.PATROL
	)
	assert_almost_eq(float(escorted["hull_chance"]), 0.2, 0.0001, "a sloop halves it")
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.3
	)
	assert_true(bool(result["ok"]))
	assert_true(
		(result["hulls_lost"] as Array).is_empty(),
		"the roll that would sink her alone misses under escort"
	)
	assert_eq(home.hulls.size(), 2)


## The convoy reading is the raid's own escort cover, in the raid's own words: a
## crown can read what its warships buy before the turn closes (wiki:
## ships-and-naval § Trade and Transport Interception; DR-20261124-04).
func test_the_convoy_read_is_the_raids_own_escort_cover() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var alone: Dictionary = ConvoyRead.read(home)
	assert_true(bool(alone["known"]))
	assert_eq(int(alone["warships"]), 0)
	assert_almost_eq(float(alone["cover"]), NavalHullLoss.escort_factor(home), 0.0001)
	assert_true(String(alone["line"]).begins_with("CONVOY  no warship covers the holds"))
	assert_true(
		String(alone["line"]).contains("sinks a Fluyte on 40%"),
		"the bare published chance, in the raid's own figures"
	)

	# A carrack and a Fluyte are three hull points of cargo; one sloop is two of
	# escort, so the cover is 2 / 3 × 0.3 = 0.2 — under the cap, so the words name
	# the share rather than the cap.
	home.set_hulls(
		["home_1", "home_3", "home_2"],
		{"home_1": "fluyte", "home_3": "carrack", "home_2": "sloop"}
	)

	var escorted: Dictionary = ConvoyRead.read(home)
	assert_eq(int(escorted["warships"]), 1)
	assert_almost_eq(float(escorted["cover"]), 0.2, 0.0001, "one sloop of 3 hull against 2")
	assert_true(String(escorted["line"]).contains("1 warship cuts a raid on the holds by 20%"))
	assert_true(
		String(escorted["line"]).contains("sinks a Fluyte on 32%"),
		"the same hull chance the raid rolls under escort"
	)
	assert_almost_eq(
		float(escorted["hull_chance"]), NavalHullLoss.chance(home), 0.0001,
		"one reading: the sheet and the raid price one hull"
	)


## The cover stops at the published cap and the words say so, instead of
## promising a share the formula never pays (DR-20261124-04).
func test_a_convoy_at_the_cap_names_the_cap() -> void:
	var home := FleetState.in_port(
		10, 0, 0, ["home_1", "home_2"], {"home_1": "fluyte", "home_2": "sloop"}
	)
	# One hull each: escort 2 against cargo 1 reads 0.6, past the 0.5 cap.
	assert_almost_eq(float(ConvoyRead.read(home)["cover"]), 0.5, 0.0001)
	assert_true(bool(ConvoyRead.read(home)["capped"]))
	var line: String = String(ConvoyRead.read(home)["line"])
	assert_true(line.contains("all the cover a convoy takes (50%)"))
	assert_true(line.contains("sinks a Fluyte on 20%"), "0.2 × (1 − 0.5) × 2.0")


## A squadron with no merchant hull offers no prize, so there is no convoy to
## read: the sheet prints nothing rather than a zero (REQ-P1-07).
func test_a_warship_only_squadron_reads_no_convoy() -> void:
	var line := FleetState.in_port(10, 0, 0, ["w"], {"w": "sloop"})
	var read: Dictionary = ConvoyRead.read(line)
	assert_false(bool(read["known"]))
	assert_eq(String(read["line"]), "")
	assert_eq(String(read["tip"]), "", "no row, no hover")
	var empty: Dictionary = ConvoyRead.read(null)
	assert_false(bool(empty["known"]))
	assert_eq(String(empty["line"]), "")


func test_the_richest_merchant_hull_is_the_one_taken() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(
		10, 0, 0, ["home_1", "home_2"], {"home_1": "carrack", "home_2": "fluyte"}
	)
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_eq((result["hulls_lost"] as Array).size(), 1)
	assert_eq(home.hulls, ["home_1"] as Array[String], "the 4-hold fluyte is the prize")
	assert_eq(String(((result["hulls_lost"] as Array)[0] as Dictionary)["type_id"]), "fluyte")


## A tie on cargo goes to the lower instance id, not to whichever hull the
## roster happens to list first — a squadron that absorbed another is not in id
## order (wiki: ships-and-naval § Trade and Transport Interception — "the
## richest hold is taken (largest cargoHold, lower instance id on a tie)").
func test_a_cargo_tie_takes_the_lower_instance_id() -> void:
	_setup_naval_raid()
	var merged := FleetState.in_port(
		10, 0, 0, ["ship_9", "ship_2"], {"ship_9": "fluyte", "ship_2": "fluyte"}
	)
	assert_eq(String(NavalHullLoss.at_risk(merged)["id"]), "ship_2")
	var ten := FleetState.in_port(
		11, 0, 0, ["ship_10", "ship_9"], {"ship_10": "fluyte", "ship_9": "fluyte"}
	)
	assert_eq(
		String(NavalHullLoss.at_risk(ten)["id"]), "ship_9",
		"the hull number decides, not the string order"
	)
	var plain := FleetState.in_port(
		12, 0, 0, ["home_9", "home_2"], {"home_9": "fluyte", "home_2": "fluyte"}
	)
	assert_eq(
		String(NavalHullLoss.at_risk(plain)["id"]), "home_2",
		"ids off the ship_<n> pattern still break the tie the same way"
	)
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [merged, raider], 0, merged, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_eq((result["hulls_lost"] as Array).size(), 1)
	assert_eq(merged.hulls, ["ship_9"] as Array[String], "the lower-id hull left the fleet")


func test_a_warship_is_never_the_prize() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "sloop"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_true(bool(result["ok"]))
	assert_eq(float(result["hull_chance"]), 0.0, "no civilian hull to take")
	assert_true((result["hulls_lost"] as Array).is_empty())
	assert_eq(home.hulls.size(), 1, "the escort is not a prize")


## A court with no home fleet in port offers no civilian hull to price.
func test_a_missing_home_fleet_prices_no_hull() -> void:
	_setup_naval_raid()
	assert_eq(NavalHullLoss.chance(null), 0.0)
	assert_eq(NavalHullLoss.escort_factor(null), 0.0)
	assert_true(NavalHullLoss.at_risk(null).is_empty())
	assert_eq(NavalRaid.hull_loss_chance(null), 0.0)


func test_a_prize_sinks_the_rivals_merchant_hull() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0, 0.0
	)
	assert_eq(raids.size(), 1)
	assert_eq((raids[0]["hulls_lost"] as Array).size(), 1)
	assert_eq(laden.hulls.size(), 0, "the rival's merchant went down as prize")
	assert_gt(int(raids[0]["lost_total"]), 0, "and her cargo went with her")


func test_a_prize_takes_the_rivals_cargo_off_its_home_naval_raid_fleet() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0, 0.99
	)
	assert_eq(raids.size(), 1)
	assert_eq(int(raids[0]["victim"]), 1)
	assert_eq(int(raids[0]["raider"]), 0)
	assert_gt(int(raids[0]["lost_total"]), 0)
	assert_true((raids[0]["hulls_lost"] as Array).is_empty())
	assert_eq(laden.hulls.size(), 1, "a prize need not cost the merchant a hull")


func test_a_prize_needs_a_declared_war() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var peace := func(_a: int, _b: int) -> bool: return false
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, peace, 1, 1, Callable(), 0.0
	)
	assert_true(raids.is_empty(), "peace takes no prize")


func test_a_prize_comes_only_from_the_crowns_own_squadrons() -> void:
	_setup_naval_raid()
	var rival_ship := _naval_raid_fleet(1, 2, 1, ["sloop"])
	rival_ship.mission = FleetState.Mission.BLOCKADE
	rival_ship.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [rival_ship, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0
	)
	assert_true(raids.is_empty(), "another crown's blockade is not the crown's prize")


func test_a_prize_rolls_on_its_own_salt() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var seed_value: int = 1
	var expected: float = NavalInterception.roll(
		seed_value, 3, 1, 0, NavalRaid.PRIZE_TAG_BASE + 1
	)
	while expected >= 0.2:
		seed_value += 1
		expected = NavalInterception.roll(
			seed_value, 3, 1, 0, NavalRaid.PRIZE_TAG_BASE + 1
		)
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), seed_value, 3
	)
	assert_eq(raids.size(), 1)
	assert_almost_eq(float(raids[0]["roll"]), expected, 0.0001)


func test_the_market_keeps_each_crowns_cargo_apart() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var mine: PlayerEconomy = PlayerEconomy.starting()
	var rival: PlayerEconomy = PlayerEconomy.starting()
	mine.treasury = 5000
	rival.treasury = 5000
	assert_true(bool(market.buy(mine, "grain", 2, 0)["ok"]))
	assert_true(bool(market.buy(rival, "timber", 3, 1)["ok"]))
	assert_eq(int(market.imports_for(0).get("grain", 0)), 2)
	assert_eq(int(market.imports_for(0).get("timber", 0)), 0)
	assert_eq(int(market.imports_for(1).get("timber", 0)), 3)
	assert_eq(
		int(market.imports_this_turn().get("grain", 0)), 2,
		"price discovery still pools every buyer's demand"
	)
	var expected: Array[int] = [0, 1]
	assert_eq(market.importing_factions(), expected)


## The cargo the auction filled is afloat until the raid pass has read it: a
## price pass that emptied the book left hostile squadrons nothing to take
## (wiki: ships-and-naval § Trade and Transport Interception — "the victim's own
## purchases this turn"; DR-20261111-17).
func test_the_cargo_book_outlives_the_price_pass_and_closes_at_the_raid() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var mine: PlayerEconomy = PlayerEconomy.starting()
	mine.treasury = 5000
	assert_true(bool(market.buy(mine, "grain", 2, 0)["ok"]))
	market.advance_prices()
	assert_eq(
		int(market.imports_for(0).get("grain", 0)), 2,
		"price discovery does not empty the cargo the raid pass reads"
	)
	assert_eq(market.importing_factions(), [0] as Array[int])
	market.book.close_cargo()
	assert_true(market.imports_for(0).is_empty())
	assert_true(market.importing_factions().is_empty())


## A bid staged on the book is only cargo once the clearing fills it, and it is
## afloat for the next raid pass (the live path: no direct buy record).
func test_a_filled_bid_leaves_its_cargo_afloat_for_the_raid_pass() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 5000
	var submit: Dictionary = MarketOrders.submit(
		market, 0, "grain", MarketOrder.SIDE_BID, 3,
		{"cargo_free": 4, "treasury": economy.treasury, "buy_price": market.buy_price("grain", 0)}
	)
	assert_true(bool(submit["ok"]), String(submit.get("reason", "")))
	MarketClearing.clear(market, null, {0: economy}, {0: 4})
	assert_eq(economy.quantity("grain"), PlayerEconomy.starting().quantity("grain") + 3)
	assert_eq(
		int(market.imports_for(0).get("grain", 0)), 3,
		"the clearing's purchase is the tonnage the next raid pass reads"
	)
	assert_eq(market.importing_factions(), [0] as Array[int])


func test_a_saved_book_keeps_each_crowns_cargo() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var rival: PlayerEconomy = PlayerEconomy.starting()
	rival.treasury = 5000
	assert_true(bool(market.buy(rival, "timber", 3, 1)["ok"]))
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	restored = WorldMarket.from_dict(
		JSON.parse_string(JSON.stringify(restored.to_dict())) as Dictionary
	)
	assert_eq(int(restored.imports_for(1).get("timber", 0)), 3)
	assert_true(bool(restored.buy(rival, "timber", 1, 1)["ok"]))
	assert_eq(int(restored.imports_for(1).get("timber", 0)), 4, "a reload keeps filling the row")


func test_the_map_pass_pays_the_crown_for_its_blockade() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var blockader := _naval_raid_fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	var rival: PlayerEconomy = play.ledger_for(1)
	rival.add("grain", 6)
	var rival_before: int = rival.quantity("grain")
	var crown_before: int = economy.economy.quantity("grain")
	play.map_seed = 1
	var salt: int = NavalRaid.PRIZE_TAG_BASE + 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[blockader], laden, FleetState.Mission.BLOCKADE
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(laden)
	while NavalInterception.roll(play.map_seed, 1, 1, 0, salt) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 1, 0, 0, NavalRaid.HULL_PRIZE_TAG_BASE + 1
			) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_gt(int(result.get("prize", 0)), 0)
	assert_gt(
		economy.economy.quantity("grain"), crown_before,
		"the prize lands in the crown's stockpile"
	)
	assert_lt(rival.quantity("grain"), rival_before, "the rival's cargo is what paid for it")
	assert_eq(laden.hulls.size(), 1, "the merchant hull came home this time")
	assert_eq(int(result.get("sunk", 0)), 0)
	ships.free()
	economy.free()


## A prize takes the rival's merchant hull too: the home fleet loses her and her
## holds with the cargo (DR-20261111-17).
func test_the_map_pass_sinks_the_rivals_merchant_hull() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var blockader := _naval_raid_fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	play.ledger_for(1).add("grain", 6)
	play.map_seed = 1
	var salt: int = NavalRaid.PRIZE_TAG_BASE + 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[blockader], laden, FleetState.Mission.BLOCKADE
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(laden)
	while NavalInterception.roll(play.map_seed, 1, 1, 0, salt) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 1, 0, 0, NavalRaid.HULL_PRIZE_TAG_BASE + 1
			) >= hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_eq(int(result.get("sunk", 0)), 1, "the raid sent one merchant down")
	assert_eq(laden.hulls.size(), 0, "her holds are gone with her")
	var report: Dictionary = (result["reports"] as Array)[0]
	assert_eq((report["hulls_lost"] as Array).size(), 1)
	assert_true(
		String(((report["hulls_lost"] as Array)[0] as Dictionary)["name"]).length() > 0,
		"the despatch names the ship"
	)
	ships.free()
	economy.free()


func test_the_crown_loses_only_its_own_cargo_to_raiders() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	home.mission = FleetState.Mission.NONE
	home.moved = false
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.add("grain", 20)
	play.economy = economy
	economy.market.record_import("grain", 4, 0)
	economy.market.record_import("grain", 40, 1)
	var before: int = economy.economy.quantity("grain")
	play.map_seed = 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[raider], home, FleetState.Mission.PATROL
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 0, 1, 0, NavalRaid.HULL_TAG
			) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	var taken: int = int(result.get("taken", 0))
	assert_gt(taken, 0)
	assert_lte(taken, 4, "the rival's forty units were never the crown's cargo")
	assert_eq(economy.economy.quantity("grain"), before - taken)
	assert_eq(home.hulls.size(), 1, "this raid pinched cargo and missed the hull")
	assert_eq(int(result.get("sunk", 0)), 0)
	ships.free()
	economy.free()


## The other side of the same draw: the crown's merchant is sent down, with the
## holds she carried (DR-20261111-17).
func test_the_map_pass_sinks_the_crowns_merchant_hull() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.add("grain", 20)
	play.economy = economy
	economy.market.record_import("grain", 4, 0)
	play.map_seed = 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[raider], home, FleetState.Mission.PATROL
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 0, 1, 0, NavalRaid.HULL_TAG
			) >= hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_eq(int(result.get("sunk", 0)), 1, "the raiders sank a merchant")
	assert_eq(home.hulls.size(), 0, "her holds leave the home fleet with her")
	var report: Dictionary = (result["reports"] as Array)[0]
	assert_eq(String(report["kind"]), "incoming")
	assert_eq((report["hulls_lost"] as Array).size(), 1)
	ships.free()
	economy.free()



## A hull a raid sends down leaves the chart with her: the marker stops flying
## her the moment the rules take her, not on the next rebuild (wiki:
## ships-and-naval § Trade and Transport Interception — "a sunk hull leaves the
## fleet with her name and holds at once").
func test_the_marker_stops_flying_a_hull_a_raid_sank() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var home := FleetState.in_port(
		10, 0, 0, ["ship_2", "ship_9"], {"ship_2": "fluyte", "ship_9": "fluyte"}
	)
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	ships.rebuild_markers()
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.add("grain", 20)
	play.economy = economy
	economy.market.record_import("grain", 4, 0)
	play.map_seed = 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[raider], home, FleetState.Mission.PATROL
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 0, 1, 0, NavalRaid.HULL_TAG
			) >= hull_chance:
		play.map_seed += 1
	var marker: Ship = ships.ship_for(home)
	assert_eq(marker.hull_count, 2, "both hulls fly before the raid")

	MapPlayRaids.resolve(play)

	assert_eq(home.hulls.size(), 1, "one merchant went down")
	assert_eq(
		ships.ship_for(home).hull_count, 1, "the marker drops the hull the raid sank"
	)
	ships.free()
	economy.free()


func test_the_dossier_prices_the_prize_before_the_move() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.turn = 1
	play.ai = AiState.new()
	var blockader := _naval_raid_fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	play.map_seed = 1
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	var note: String = MapPlayFleetMissions.prize_note(play, blockader)
	var odds: Dictionary = NavalRaid.preview(
		[blockader], laden, {"grain": 6}, FleetState.Mission.BLOCKADE
	)
	assert_true(note.contains("Prize:"))
	assert_true(
		note.contains("sinks a Fluyte"),
		"the dossier prices the merchant hull as well as the cargo"
	)
	assert_true(note.contains("40%"), "base 0.2 × civilian 2 with no escort")
	assert_true(
		note.contains("%d%%" % int(round(float(odds["chance"]) * 100.0))),
		"the dossier reads the chance the rules roll"
	)
	assert_true(note.contains("~%d" % int(odds["expected"])))
	# Cargo afloat lasts until the raid pass has read it: a price pass alone does
	# not empty the book (wiki: ships-and-naval § Trade and Transport
	# Interception).
	economy.market.advance_prices()
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("Prize:"),
		"the dossier still prices cargo the clearing left afloat"
	)
	economy.market.book.close_cargo()
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("no cargo afloat")
	)
	# A crown that has taken the coast blockades its own shore: no prize.
	economy.market.record_import("grain", 4, 1)
	_naval_raid_model.province_data(1).owner = 0
	assert_eq(MapPlayFleetMissions.prize_note(play, blockader), "")
	_naval_raid_model.province_data(1).owner = 1
	# A rival whose merchant hulls are at sea has no laden home fleet to raid.
	laden.location = FleetState.Location.AT_SEA
	laden.sea_zone = 1
	laden.province = MapModel.NO_ID
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("at sea")
	)
	economy.free()


# --- the dossier's prize reading (DR-20261120-01) ---------------------------


## A wired session for the dossier's price: the crown's stations, the rival's
## laden home fleet in port at Coro, and the rival's cargo book.
func _prize_session(stations: Array[FleetState], laden: FleetState) -> PlaySession:
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.turn = 1
	play.ai = AiState.new()
	var fleets: Array[FleetState] = []
	fleets.append_array(stations)
	fleets.append(laden)
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	play.map_seed = 1
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	return play


## The patrol rests at sea and raids the same water a blockade does, at the
## patrol factor: the dossier must price it (wiki: ships-and-naval § Trade and
## Transport Interception — "Hostile Patrol or Blockade squadrons … raid").
func test_the_dossier_prices_the_patrol_that_raids_too() -> void:
	_setup_naval_raid()
	var patrol := _naval_raid_fleet(1, 0, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var play := _prize_session([patrol], laden)
	play.economy.market.record_import("grain", 6, 1)
	var note: String = MapPlayFleetMissions.prize_note(play, patrol)
	var patrol_odds: Dictionary = NavalRaid.preview(
		[patrol], laden, {"grain": 6}, FleetState.Mission.PATROL
	)
	assert_true(note.contains("Prize:"), "a patrol raids trade, so the dossier prices it")
	assert_true(note.contains("Coro"), "the patrol names the coast it works")
	assert_true(
		note.contains("%d%%" % int(round(float(patrol_odds["chance"]) * 100.0))),
		"the price is the patrol factor the raid rolls"
	)
	assert_true(note.contains("sinks a Fluyte"), "the merchant hull is priced too")
	# The same coast blockaded rolls the blockade bonus, so the two prices differ.
	patrol.mission = FleetState.Mission.BLOCKADE
	patrol.blockade_province = 1
	var blockader_odds: Dictionary = NavalRaid.preview(
		[patrol], laden, {"grain": 6}, FleetState.Mission.BLOCKADE
	)
	assert_gt(
		float(blockader_odds["chance"]), float(patrol_odds["chance"]),
		"a blockade raiding the same coast rolls harder than a patrol"
	)
	assert_true(
		MapPlayFleetMissions.prize_note(play, patrol).contains(
			"%d%%" % int(round(float(blockader_odds["chance"]) * 100.0))
		),
		"the blockade's own price follows its station"
	)
	play.economy.free()


## The hull the raid would sink is named with the article its name asks for: the
## catalogue's Indiaman opens on a vowel, so the price reads "sinks an Indiaman"
## and never "a Indiaman" (wiki: ships-and-naval § Trade and Transport
## Interception).
func test_the_prize_names_its_hull_with_the_article_it_asks_for() -> void:
	_setup_naval_raid()
	var patrol := _naval_raid_fleet(1, 0, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var laden := FleetState.in_port(
		20, 1, 1, ["rival_1", "rival_2"],
		{"rival_1": "indiaman", "rival_2": "frigate"}
	)
	var play := _prize_session([patrol], laden)
	play.economy.market.record_import("grain", 6, 1)
	var note: String = MapPlayFleetMissions.prize_note(play, patrol)
	assert_true(note.contains("sinks an Indiaman"), note)
	assert_false(note.contains("a Indiaman"), "the article follows the hull's own name")
	assert_eq(MapPlayFleetMissions.with_article("Indiaman"), "an Indiaman")
	assert_eq(MapPlayFleetMissions.with_article("Galleon"), "a Galleon")
	play.economy.free()


## The pass rolls every station the crown holds in the water as one group, so the
## price is the group's, never one hull's.
func test_the_dossier_prices_the_whole_group_in_the_zone() -> void:
	_setup_naval_raid()
	var patrol := _naval_raid_fleet(1, 0, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var consort := _naval_raid_fleet(2, 0, 1, ["sloop"])
	consort.mission = FleetState.Mission.PATROL
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var play := _prize_session([patrol, consort], laden)
	play.economy.market.record_import("grain", 6, 1)
	var alone: Dictionary = NavalRaid.preview(
		[patrol], laden, {"grain": 6}, FleetState.Mission.PATROL
	)
	var together: Dictionary = NavalRaid.preview(
		[patrol, consort], laden, {"grain": 6}, FleetState.Mission.PATROL
	)
	assert_gt(
		float(together["chance"]), float(alone["chance"]),
		"two stations in one water raid harder than one"
	)
	var note: String = MapPlayFleetMissions.prize_note(play, patrol)
	assert_true(
		note.contains("%d%%" % int(round(float(together["chance"]) * 100.0))),
		"the dossier prices the group the raid rolls"
	)
	assert_false(
		note.contains("%d%% to take" % int(round(float(alone["chance"]) * 100.0))),
		"the sheet never prices one hull while the pass rolls two"
	)
	# A third station in another water is no part of this group.
	var elsewhere := _naval_raid_fleet(3, 0, 0, ["sloop"])
	elsewhere.mission = FleetState.Mission.PATROL
	play.ship_layer.fleets.append(elsewhere)
	assert_true(
		MapPlayFleetMissions.prize_note(play, patrol).contains(
			"%d%%" % int(round(float(together["chance"]) * 100.0))
		),
		"a station in another zone is not in the group"
	)
	play.economy.free()


## The raid needs a declared war (wiki: ships-and-naval § Raids cut both ways —
## "against a declared enemy"), so a coast the crown is at peace with prices no
## prize even under a standing blockade.
func test_a_coast_at_peace_prices_no_prize() -> void:
	_setup_naval_raid()
	var blockader := _naval_raid_fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var play := _prize_session([blockader], laden)
	play.diplomacy = DiplomacyState.new()
	play.economy.market.record_import("grain", 6, 1)
	assert_eq(
		MapPlayFleetMissions.prize_note(play, blockader), "",
		"peace offers no prize"
	)
	# Declared war: the same station prices the same coast.
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("Prize:"),
		"the declared war opens the raid"
	)
	play.economy.free()


# --- the dossier's interception reading (DR-20261120-02) --------------------


## A rival squadron afloat in the crown's station water, read across a turn so
## the crown may weigh her (wiki: ships-and-naval § Sighted strength).
func _moor_unread_squadron(play: PlaySession, rival: FleetState) -> void:
	play.naval_intel.observe([rival.id], 0, 0)
	play.naval_intel.observe([rival.id], 1, 0)


## The station's own chance to intercept a hostile squadron that stays in the
## water is published (§ Naval Interception Probability) and rolled by the combat
## pass, so the dossier prices it before the move — at the station's own factor,
## over the squadrons that hold it (DR-20261120-02).
func test_the_dossier_prices_the_interception_before_the_move() -> void:
	_setup_naval_raid()
	var patrol := _naval_raid_fleet(1, 0, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var rival := _naval_raid_fleet(20, 1, 1, ["fluyte", "fluyte"])
	var play := _prize_session([patrol], rival)
	_moor_unread_squadron(play, rival)
	var expected: float = NavalInterception.chance(
		[patrol], [rival], FleetState.Mission.PATROL, play.has_tech
	)
	var note: String = MapPlayFleetMissions.interception_note(play, patrol)
	assert_true(note.contains("Interception:"), "a patrol prices what it catches")
	assert_true(
		note.contains("%d%%" % int(round(expected * 100.0))),
		"the dossier reads the chance the pass rolls"
	)
	assert_true(note.contains("2 hulls"), "the hulls at risk are named")
	# An unread rival is priced by nothing: the line waits on the fog instead of
	# promising a share the chart withholds (§ Sighted strength).
	var stranger := _naval_raid_fleet(21, 1, 1, ["fluyte"])
	play.ship_layer.fleets.append(stranger)
	assert_true(
		MapPlayFleetMissions.interception_note(play, patrol).contains("the fog has not read"),
		"an unread squadron leaves the odds unknown"
	)
	play.ship_layer.fleets.erase(stranger)
	# The ruling is the rules': a hostile squadron it has read, roped to the same
	# group the combat pass rolls.
	assert_true(
		MapPlayFleetMissions.note(play, patrol).contains("Interception:"),
		"the station line carries the catch"
	)
	play.economy.free()


## Nothing to catch, no station and another court's water: the line is silent.
func test_the_interception_line_holds_its_tongue() -> void:
	_setup_naval_raid()
	var defender := _naval_raid_fleet(1, 0, 1, ["sloop"])
	defender.mission = FleetState.Mission.DEFEND
	var rival := _naval_raid_fleet(20, 1, 1, ["fluyte"])
	var play := _prize_session([defender], rival)
	_moor_unread_squadron(play, rival)
	assert_eq(
		MapPlayFleetMissions.interception_note(play, defender), "",
		"a squadron holding no station catches nothing"
	)
	var patrol := _naval_raid_fleet(2, 0, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	play.ship_layer.fleets.append(patrol)
	# A rival in another water is no part of this station's catch.
	rival.sea_zone = 0
	assert_eq(
		MapPlayFleetMissions.interception_note(play, patrol), "",
		"a squadron in another water is not caught here"
	)
	# A declared peace catches nobody: the combat pass spills no blood at peace.
	play.diplomacy = DiplomacyState.new()
	rival.sea_zone = 1
	assert_eq(
		MapPlayFleetMissions.interception_note(play, patrol), "",
		"peace leaves nothing to intercept"
	)
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	assert_true(
		MapPlayFleetMissions.interception_note(play, patrol).contains("Interception:"),
		"the declared war opens the roll"
	)
	play.economy.free()


# --- rival-on-rival raids + prize cargo (DR-20261111-20) ----------------------


## A wired one-region play session: the crown's ledger plus the rival ledgers a
## prize raid writes to. `fleets` is the region roster every pass reads.
func _naval_raid_session(fleets: Array[FleetState]) -> PlaySession:
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.map_seed = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	return play


## First seed where `raider`'s prize roll on `victim` lands: cargo comes aboard
## and the hull draw misses (or hits), as the test asks.
func _naval_raid_seed_for_prize(
	play: PlaySession, raider: FleetState, home: FleetState, victim: int, sink_hull: bool
) -> void:
	var salt: int = NavalRaid.PRIZE_TAG_BASE + victim
	var hull_salt: int = NavalRaid.HULL_PRIZE_TAG_BASE + victim
	var chance: float = NavalRaid.trade_chance([raider], home, raider.mission)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while true:
		var cargo: float = NavalInterception.roll(
			play.map_seed, play.turn, raider.sea_zone, raider.owner, salt
		)
		var hull: float = NavalInterception.roll(
			play.map_seed, play.turn, raider.sea_zone, raider.owner, 0, hull_salt
		)
		if cargo < chance and (hull < hull_chance) == sink_hull:
			return
		play.map_seed += 1


## The other coast belongs to a rival, and the rival's blockade pays the rival:
## the crown is not a party to the war and takes neither cargo nor a despatch.
func test_a_rival_blockade_lands_its_prize_in_the_rival_ledger() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(0).owner = 2
	var blockader := _naval_raid_fleet(1, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var laden := FleetState.in_port(20, 2, 0, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([blockader, laden])
	play.diplomacy.ensure_relation(1, 2, 1)
	DiplomacyRules.declare_war(play.diplomacy, 1, 2, false)
	play.economy.market.record_import("grain", 6, 2)
	var victim: PlayerEconomy = play.ledger_for(2)
	victim.add("grain", 6)
	var victim_before: int = victim.quantity("grain")
	var raider: PlayerEconomy = play.ledger_for(1)
	var raider_before: int = raider.quantity("grain")
	var crown_before: int = play.economy.economy.quantity("grain")
	_naval_raid_seed_for_prize(play, blockader, laden, 2, false)

	var result: Dictionary = MapPlayRaids.resolve(play)

	var prize: int = int(result.get("rival_prize", 0))
	assert_gt(prize, 0, "a rival's blockade takes a rival's cargo")
	assert_eq(raider.quantity("grain"), raider_before + prize, "the prize is the raider's")
	assert_eq(victim.quantity("grain"), victim_before - prize, "and it leaves the victim's stockpile")
	assert_eq(
		play.economy.economy.quantity("grain"), crown_before,
		"the crown was never a party to that war"
	)
	assert_true((result["reports"] as Array).is_empty(), "no despatch to a stranger")
	var rival_raids: Array = result["rival_raids"] as Array
	assert_eq(rival_raids.size(), 1)
	var raid: Dictionary = rival_raids[0] as Dictionary
	assert_eq(String(raid["kind"]), "rival")
	assert_eq(int(raid["raider"]), 1)
	assert_eq(int(raid["victim"]), 2)
	assert_eq(laden.hulls.size(), 1, "the hull draw missed this turn")
	play.ship_layer.free()
	play.economy.free()


## A victim's laden hulls ride at risk only as its **home fleet**, in port at its
## own seat: merchant hulls waiting at a colony quay are no home fleet, so a
## blockade off that coast takes neither cargo nor hull from them (wiki:
## ships-and-naval § Cargo holds and capacity — "the home squadron's merchant
## hulls are the only holds"; § Home Fleet — a ship is home only in port at the
## capital).
func test_a_colony_quay_is_no_home_fleet_to_raid() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(0).owner = 2
	# The rival holds this coast but sits nowhere on it: a holding, not a seat.
	_naval_raid_model.province_data(0).capital = false
	var blockader := _naval_raid_fleet(1, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var laden := FleetState.in_port(20, 2, 0, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([blockader, laden])
	play.diplomacy.ensure_relation(1, 2, 1)
	DiplomacyRules.declare_war(play.diplomacy, 1, 2, false)
	play.economy.market.record_import("grain", 6, 2)
	var victim: PlayerEconomy = play.ledger_for(2)
	victim.add("grain", 6)
	var before: int = victim.quantity("grain")
	# A seed whose cargo roll **lands**: the null result must be the home-fleet
	# reading, never a missed die.
	_naval_raid_seed_for_prize(play, blockader, laden, 2, false)

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_eq(int(result.get("rival_prize", 0)), 0, "a colony quay is no home fleet")
	assert_eq(victim.quantity("grain"), before, "the victim keeps its ton")
	assert_eq(laden.hulls.size(), 1, "and no hull is drawn")
	assert_true((result["rival_raids"] as Array).is_empty(), "no raid to report")
	play.ship_layer.free()
	play.economy.free()


func test_two_rivals_at_peace_take_no_prize() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(0).owner = 2
	var blockader := _naval_raid_fleet(1, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var laden := FleetState.in_port(20, 2, 0, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([blockader, laden])
	play.diplomacy.ensure_relation(1, 2, 1)
	play.economy.market.record_import("grain", 6, 2)
	play.ledger_for(2).add("grain", 6)
	var raider: PlayerEconomy = play.ledger_for(1)
	var raider_before: int = raider.quantity("grain")
	var victim_before: int = play.ledger_for(2).quantity("grain")

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_eq(int(result.get("rival_prize", 0)), 0)
	assert_eq(raider.quantity("grain"), raider_before, "peace takes no prize")
	assert_eq(play.ledger_for(2).quantity("grain"), victim_before, "the rival keeps its cargo")
	assert_eq(laden.hulls.size(), 1)
	assert_true((result["rival_raids"] as Array).is_empty())
	play.ship_layer.free()
	play.economy.free()


## The same raid that skims cargo can send the victim's merchant down, and the
## hull leaves the rival's home fleet without a peasant or a coin returned.
func test_a_rival_prize_sinks_the_victims_merchant_hull() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(0).owner = 2
	var blockader := _naval_raid_fleet(1, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var laden := FleetState.in_port(20, 2, 0, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([blockader, laden])
	play.diplomacy.ensure_relation(1, 2, 1)
	DiplomacyRules.declare_war(play.diplomacy, 1, 2, false)
	play.economy.market.record_import("grain", 6, 2)
	play.ledger_for(2).add("grain", 6)
	_naval_raid_seed_for_prize(play, blockader, laden, 2, true)

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_gt(int(result.get("rival_prize", 0)), 0, "her cargo went with her")
	assert_eq(laden.hulls.size(), 0, "the rival's merchant is gone")
	var raid: Dictionary = (result["rival_raids"] as Array)[0] as Dictionary
	assert_eq((raid["hulls_lost"] as Array).size(), 1)
	assert_true(
		String(((raid["hulls_lost"] as Array)[0] as Dictionary)["name"]).length() > 0,
		"a rival's loss still carries the ship's name"
	)
	play.ship_layer.free()
	play.economy.free()


## The crown suffers one raid a turn through `_incoming`; a rival's blockade off
## its coast is never also a prize raid writing into the rival's ledger.
func test_the_crown_is_never_a_rivals_prize() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	var play := _naval_raid_session([home, raider])
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	play.economy.economy.add("grain", 20)
	play.economy.market.record_import("grain", 4, 0)
	var rival: PlayerEconomy = play.ledger_for(1)
	var rival_before: int = rival.quantity("grain")
	var crown_before: int = play.economy.economy.quantity("grain")
	var cargo_chance: float = NavalRaid.trade_chance(
		[raider], home, FleetState.Mission.PATROL
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 0, 1, 0, NavalRaid.HULL_TAG
			) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	var taken: int = int(result.get("taken", 0))
	assert_gt(taken, 0, "the crown loses the one raid its coast suffers")
	assert_eq(play.economy.economy.quantity("grain"), crown_before - taken)
	assert_eq(rival.quantity("grain"), rival_before, "the raider took no prize off the crown")
	assert_true((result["rival_raids"] as Array).is_empty())
	play.ship_layer.free()
	play.economy.free()


## Two crowns blockading one coast each take their own prize: the rolls are
## salted per raider and the tonnage lands in each raider's own ledger.
func test_two_blockades_share_the_victims_cargo_apart() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var rival := _naval_raid_fleet(2, 2, 1, ["sloop"])
	rival.mission = FleetState.Mission.BLOCKADE
	rival.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([crown, rival, laden])
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	play.diplomacy.ensure_relation(2, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 2, 1, false)
	play.economy.market.record_import("grain", 6, 1)
	var victim: PlayerEconomy = play.ledger_for(1)
	victim.add("grain", 6)
	var victim_before: int = victim.quantity("grain")
	var partner: PlayerEconomy = play.ledger_for(2)
	var partner_before: int = partner.quantity("grain")
	var crown_before: int = play.economy.economy.quantity("grain")
	var salt: int = NavalRaid.PRIZE_TAG_BASE + 1
	var hull_salt: int = NavalRaid.HULL_PRIZE_TAG_BASE + 1
	var chance: float = NavalRaid.trade_chance([crown], laden, FleetState.Mission.BLOCKADE)
	var hull_chance: float = NavalRaid.hull_loss_chance(laden)
	while NavalInterception.roll(play.map_seed, 1, 1, 0, salt) >= chance \
			or NavalInterception.roll(play.map_seed, 1, 1, 2, salt) >= chance \
			or NavalInterception.roll(play.map_seed, 1, 1, 0, 0, hull_salt) < hull_chance \
			or NavalInterception.roll(play.map_seed, 1, 1, 2, 0, hull_salt) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	var prize: int = int(result.get("prize", 0))
	var rival_prize: int = int(result.get("rival_prize", 0))
	assert_gt(prize, 0, "the crown's blockade pays the crown")
	assert_gt(rival_prize, 0, "the rival's blockade pays the rival")
	assert_eq(play.economy.economy.quantity("grain"), crown_before + prize)
	assert_eq(partner.quantity("grain"), partner_before + rival_prize)
	assert_eq(victim.quantity("grain"), victim_before - prize - rival_prize)
	assert_eq(laden.hulls.size(), 1, "both hull draws missed")
	play.ship_layer.free()
	play.economy.free()


# --- the sea's despatch (wiki: ships-and-naval § Naval Combat Resolution) -----

const DESPATCH_NAMES: Array[String] = ["España", "England"]


func _dispatch_battle() -> Dictionary:
	return {
		"attacker": 0,
		"defender": 1,
		"attacker_strength": 182.0,
		"defender_strength": 121.0,
		"attacker_before": 6,
		"defender_before": 4,
		"attacker_hulls": [
			"galleon", "galleon", "galleon", "galleon", "sloop", "sloop",
		],
		"defender_hulls": ["carrack", "carrack", "carrack", "carrack"],
		"attacker_lost": ["ship_9"],
		"attacker_lost_names": ["San Juan"],
		"defender_lost": ["a", "b", "c", "d"],
		"defender_lost_names": ["Trinidad", "Concepcion"],
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"retreat": {},
	}


func test_the_record_carries_the_hulls_each_side_flew() -> void:
	var strong := FleetState.at_sea(
		1, 0, 0, ["ship_1", "ship_2", "ship_3"],
		{"ship_1": "galleon", "ship_2": "galleon", "ship_3": "sloop"}
	)
	strong.moved = true
	var weak := FleetState.at_sea(2, 1, 0, ["ship_4"], {"ship_4": "carrack"})
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	var battle: Dictionary = battles[0]
	assert_eq(
		battle["attacker_hulls"], ["galleon", "galleon", "sloop"] as Array[String],
		"the attacker's hulls, by type, in roster order"
	)
	assert_eq(battle["defender_hulls"], ["carrack"] as Array[String])
	assert_eq((battle["attacker_hulls"] as Array).size(), int(battle["attacker_before"]))


func test_the_despatch_groups_the_hulls_by_type() -> void:
	var battle: Dictionary = _dispatch_battle()
	var groups: Array[Dictionary] = NavalDispatch.groups(battle, NavalDispatch.ATTACKER)
	assert_eq(groups.size(), 2, "one medallion per type")
	assert_eq(String(groups[0]["type"]), "galleon", "the biggest group leads")
	assert_eq(int(groups[0]["count"]), 4)
	assert_eq(int(groups[1]["count"]), 2)
	assert_eq(
		NavalDispatch.groups_text(battle, NavalDispatch.ATTACKER),
		"4 Galleon and 2 Sloop"
	)
	assert_eq(NavalDispatch.hull_count(battle, NavalDispatch.DEFENDER), 4)


func test_the_despatch_strikes_the_share_the_resolver_struck() -> void:
	var battle: Dictionary = _dispatch_battle()
	assert_eq(NavalDispatch.strength(battle, NavalDispatch.ATTACKER), 182)
	assert_eq(NavalDispatch.share_percent(battle), 60)
	var maths: String = NavalDispatch.maths_line(battle, DESPATCH_NAMES)
	assert_true(maths.contains("Strength 182 against 121"))
	assert_true(maths.contains("share 60 of 100"), "the share is printed, not guessed")
	assert_true(maths.contains("better than 53"), "the bar the rules use is named")


func test_the_despatch_names_the_meeting_and_the_dead() -> void:
	var battle: Dictionary = _dispatch_battle()
	var opening: String = NavalDispatch.opening(battle, "Mar Caribe", DESPATCH_NAMES)
	assert_true(opening.contains("España's 6 hulls (4 Galleon and 2 Sloop)"))
	assert_true(opening.contains("England's 4 (4 Carrack)"))
	assert_true(opening.contains("in the Mar Caribe"))
	var beats: Array[String] = NavalDispatch.beats(battle, "Mar Caribe", DESPATCH_NAMES)
	assert_eq(beats.size(), 5, "the meeting, the maths, two losses, the verdict")
	assert_eq(beats[2], "España loses 1 ship (San Juan).")
	assert_eq(beats[3], "England loses 4 ships (Trinidad, Concepcion).")
	assert_eq(
		NavalDispatch.outcome_text(battle, "Mar Caribe", DESPATCH_NAMES),
		"España holds the Mar Caribe"
	)


func test_a_withdrawal_and_a_standoff_are_told_differently() -> void:
	var battle: Dictionary = _dispatch_battle()
	battle["retreat"] = {"success": true, "beaten": 1}
	assert_eq(
		NavalDispatch.outcome_text(battle, "Mar Caribe", DESPATCH_NAMES),
		"England withdraws — España holds the Mar Caribe"
	)
	battle["retreat"] = {}
	battle["outcome"] = NavalCombat.Outcome.STALEMATE
	assert_eq(
		NavalDispatch.outcome_text(battle, "Mar Caribe", DESPATCH_NAMES),
		"Neither colour holds the Mar Caribe"
	)
	assert_true(
		NavalDispatch.closing(battle, DESPATCH_NAMES).contains("neither holds the zone")
	)


func test_a_record_without_hull_types_still_tells_the_meeting() -> void:
	var battle: Dictionary = _dispatch_battle()
	battle.erase("attacker_hulls")
	battle.erase("defender_hulls")
	battle["attacker_before"] = 6
	battle["defender_before"] = 4
	var opening: String = NavalDispatch.opening(battle, "", DESPATCH_NAMES)
	assert_eq(opening, "España's 6 hulls meet England's 4 at sea.")
	assert_eq(
		NavalDispatch.headline(battle, "", DESPATCH_NAMES), "España against England"
	)


# --- the turn pass raises the plate for the crown's own fight -----------------

const despatch_NavalFixture = preload("res://tests/naval_fixture.gd")


class DespatchHud extends GameHud:
	var dispatched: Array[String] = []
	var toasts: Array[String] = []

	func toast(text: String, _icon_name: String = "") -> void:
		toasts.append(text)

	func toast_plate_line(text: String, _icon_name: String = "") -> void:
		toasts.append(text)

	func show_naval_dispatch(_battle: Dictionary, zone: String) -> void:
		dispatched.append(zone)


## One session with two hostile squadrons in the Caribbean, and a stub court that
## records what the pass told it.
func _despatch_play(hud: GameHud, fleets: Array[FleetState]) -> PlaySession:
	var model: MapModel = despatch_NavalFixture.build()
	var play := PlaySession.new()
	play.model = model
	play.player_faction = 0
	play.turn = 1
	play.map_seed = 7
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	play.diplomacy.ensure_relation(0, 2, 1)
	play.diplomacy.ensure_relation(1, 2, 1)
	var ships := ShipLayer.new()
	ships.model = model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(model)
	play.world = world
	var armies := ArmyLayer.new()
	armies.model = model
	armies.regions.set_region(model.region_id, [] as Array[ArmyState])
	play.army_layer = armies
	var civilians := CivilianLayer.new()
	civilians.model = model
	civilians.regions.set_region(model.region_id, [] as Array[CivilianState])
	play.civilian_layer = civilians
	play.hud = hud
	return play


func test_the_crowns_sea_fight_opens_the_despatch_plate() -> void:
	var strong := FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "galleon"})
	strong.moved = true
	var weak := FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "carrack"})
	var hud := DespatchHud.new()
	add_child(hud)
	var play: PlaySession = _despatch_play(hud, [strong, weak] as Array[FleetState])
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)

	var battles: Array[Dictionary] = MapPlayNavalTurn.resolve(play)

	assert_eq(battles.size(), 1, "two hostile squadrons in one zone fight")
	assert_eq(hud.dispatched.size(), 1, "the crown's fight opens the plate")
	assert_eq(hud.dispatched[0], "Mar Caribe", "the plate names the water")
	assert_eq(hud.toasts.size(), 1, "the despatch line still reaches the court")
	hud.free()
	play.ship_layer.free()


func test_a_rivals_sea_fight_stays_the_courts_news_alone() -> void:
	var strong := FleetState.at_sea(1, 1, 0, ["ship_1"], {"ship_1": "galleon"})
	strong.moved = true
	var weak := FleetState.at_sea(2, 2, 0, ["ship_2"], {"ship_2": "carrack"})
	var hud := DespatchHud.new()
	add_child(hud)
	var play: PlaySession = _despatch_play(hud, [strong, weak] as Array[FleetState])
	# Only the rivals strike each other: the crown keeping its peace hears news.
	DiplomacyRules.declare_war(play.diplomacy, 1, 2, false)

	var battles: Array[Dictionary] = MapPlayNavalTurn.resolve(play)

	assert_eq(battles.size(), 1, "the rivals fight")
	assert_true(hud.dispatched.is_empty(), "the crown's plate is not raised for them")
	assert_true(hud.toasts.is_empty(), "a rival's fight is the Gazette's news")
	hud.free()
	play.ship_layer.free()


## A drowned regiment reaches the lane only when it was the crown's own: a
## rival's loss at sea is its own court's news (wiki: hud-toasts).
func test_a_drowned_rival_regiment_stays_off_the_lane() -> void:
	var hud := DespatchHud.new()
	add_child(hud)
	var play: PlaySession = _despatch_play(hud, [] as Array[FleetState])
	var rival: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, false, ["peasant_levies"] as Array[String], 9),
	]
	rival[0].embarked_fleet = 99
	play.army_layer.regions.set_region(play.model.region_id, rival)

	MapPlayNavalTurn.resolve(play)

	assert_true(hud.toasts.is_empty(), "a rival's drowned men are its own news")
	var mine: Array[ArmyState] = [
		ArmyState.muster(2, 0, 0, false, ["peasant_levies"] as Array[String], 8),
	]
	mine[0].embarked_fleet = 99
	play.army_layer.regions.set_region(play.model.region_id, mine)

	MapPlayNavalTurn.resolve(play)

	assert_eq(hud.toasts.size(), 1, "the crown's own loss is told")
	assert_true(hud.toasts[0].contains("went down"), hud.toasts[0])
	hud.free()
	play.ship_layer.free()



# --- from test_naval_intel.gd ---
## The crown's watch over rival squadrons.
## The crown's watch over rival squadrons (wiki: ships-and-naval
## § Sighted strength; DR-20261113-20, `NavalIntel`).
## The rule is plain state: a rival sighted this turn is unread until she is
## still in view at a later turn's opening, and leaving the crown's chart starts
## the watch over. The watch is kept per chart, because fleet ids are minted per
## roster and id 5 stands for a different squadron on each map.

const FLEET: int = 41
const OTHER: int = 42
const OLD_WORLD: int = FactionCatalog.OLD_WORLD
const NEW_WORLD: int = FactionCatalog.NEW_WORLD


func test_a_first_sighting_is_unread() -> void:
	var intel := NavalIntel.new()

	assert_eq(intel.observe([FLEET], 5, OLD_WORLD), [])
	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "a first sighting gives up no weight")


func test_the_same_turn_refreshes_do_not_read_her() -> void:
	var intel := NavalIntel.new()

	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET, OTHER], 5, OLD_WORLD)
	intel.observe([FLEET], 5, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "the watch needs a turn boundary")
	assert_false(intel.is_revealed(OTHER, OLD_WORLD))


func test_a_rival_still_in_view_next_turn_is_read_once() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)

	assert_eq(intel.observe([FLEET], 6, OLD_WORLD), [FLEET])
	assert_true(intel.is_revealed(FLEET, OLD_WORLD), "a squadron watched across a turn is read")
	assert_eq(intel.observe([FLEET], 7, OLD_WORLD), [], "the news is told once")
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))


func test_a_rival_not_seen_at_the_boundary_is_read_at_the_next_one() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([], 6, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD),
		"slipping out of view starts the watch over")
	intel.observe([FLEET], 7, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "a fresh sighting is unread again")
	assert_eq(intel.observe([FLEET], 8, OLD_WORLD), [FLEET])


func test_leaving_view_forgets_the_read() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))

	intel.observe([], 7, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "out of sight is out of knowledge")
	assert_eq(intel.watched(OLD_WORLD), [], "no squadrons under the eye")


func test_a_gap_in_the_watch_does_not_read_her() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([], 6, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "the second sighting is still this turn")


func test_the_watch_survives_a_save() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET, OTHER], 6, OLD_WORLD)
	var restored: NavalIntel = NavalIntel.from_dict(intel.to_dict())

	assert_true(restored.is_revealed(FLEET, OLD_WORLD), "a read squadron stays read")
	assert_false(restored.is_revealed(OTHER, OLD_WORLD), "an unread squadron stays unread")
	assert_eq(restored.watched(OLD_WORLD), [FLEET, OTHER], "both stay under the eye")
	assert_eq(restored.observe([OTHER], 7, OLD_WORLD), [OTHER], "the clock resumes")


## Fleet ids are minted per roster, so the same id stands for another squadron on
## the other chart: a read earned on one map must never hand over the other's
## weight, and looking away must not clear the watch behind it.
func test_each_chart_keeps_its_own_watch() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))

	assert_false(intel.is_revealed(FLEET, NEW_WORLD),
		"a New World squadron of the same id is not the Old World one")

	intel.observe([FLEET], 7, NEW_WORLD)

	assert_true(intel.is_revealed(FLEET, OLD_WORLD),
		"another chart is not another water")
	assert_false(intel.is_revealed(FLEET, NEW_WORLD),
		"the New World watch starts from her own sighting")
	assert_eq(intel.watched(NEW_WORLD), [FLEET])

	var restored: NavalIntel = NavalIntel.from_dict(intel.to_dict())
	assert_true(restored.is_revealed(FLEET, OLD_WORLD), "both watches ride the save")
	assert_false(restored.is_revealed(FLEET, NEW_WORLD))


## A save written before the watch was kept per chart carries one flat watch; it
## belonged to the chart the court stood on.
func test_a_flat_watch_from_an_older_save_lands_on_its_own_chart() -> void:
	var legacy: Dictionary = {"seen": {FLEET: 5}, "revealed": [FLEET]}
	var restored: NavalIntel = NavalIntel.from_dict(legacy, NEW_WORLD)

	assert_true(restored.is_revealed(FLEET, NEW_WORLD))
	assert_false(restored.is_revealed(FLEET, OLD_WORLD))
	assert_eq(NavalIntel.from_dict(legacy).watched(NEW_WORLD), [],
		"a flat watch with no chart to sit on is dropped, not guessed")


func test_a_save_without_a_watch_resumes_empty() -> void:
	assert_eq(NavalIntel.from_dict({}).watched(OLD_WORLD), [])
	assert_eq(NavalIntel.from_dict(null).watched(OLD_WORLD), [])
	assert_false(NavalIntel.from_dict({"seen": "stale"}, OLD_WORLD).is_revealed(FLEET, OLD_WORLD))
	assert_false(
		NavalIntel.from_dict({"regions": "stale"}, OLD_WORLD).is_revealed(FLEET, OLD_WORLD)
	)


func test_a_dossier_reads_a_rival_only_once_her_watch_closes() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	var my_fleet := FleetState.at_sea(1, 0, 7, ["hull_1"], {"hull_1": "carrack"})
	var rival := FleetState.at_sea(FLEET, 1, 7, ["hull_2"], {"hull_2": "carrack"})
	var known := func(other: FleetState) -> bool: return intel.is_revealed(other.id, OLD_WORLD)

	var unread: Dictionary = NavalStrength.dossier(
		[my_fleet, rival], my_fleet, Callable(), {}, {}, known
	)
	assert_true(bool((unread["zone"] as Dictionary).get("unread", false)),
		"an unread rival weighs nothing in the odds")

	intel.observe([FLEET], 6, OLD_WORLD)
	var read: Dictionary = NavalStrength.dossier(
		[my_fleet, rival], my_fleet, Callable(), {}, {}, known
	)
	assert_false(bool((read["zone"] as Dictionary).get("unread", false)))
	assert_gt(float(read["zone"]["foe"]), 0.0, "a read rival counts in the zone")


func test_a_sighted_rival_dossier_is_fogged() -> void:
	var fogged: Dictionary = NavalStrength.fogged()

	assert_eq(int(fogged["count"]), 1, "the block still shows")
	assert_false(bool(fogged["known"]))
	assert_almost_eq(float(fogged["strength"]), 0.0, 0.0001, "no weight leaks")


# --- the shared war query (from test_hostility_rules) ---
## The naval rules and the rival planners read one hostility predicate
## and one at-war membership set (REQ-P3-03, REQ-P3-04).

func test_a_faction_is_never_hostile_to_itself() -> void:
	assert_false(Hostility.between(Callable(), 3, 3))
	assert_false(Hostility.between(func(_a: int, _b: int) -> bool: return true, 3, 3))


func test_an_unset_query_keeps_every_other_faction_hostile() -> void:
	assert_true(Hostility.between(Callable(), 1, 2))


func test_a_set_query_decides_the_pair() -> void:
	var at_war: Callable = func(a: int, b: int) -> bool: return a == 1 and b == 2
	assert_true(Hostility.between(at_war, 1, 2))
	assert_false(Hostility.between(at_war, 2, 1))


func test_no_court_reads_no_known_wars() -> void:
	assert_true(Hostility.owners(null, 1).is_empty())


func test_owners_lists_every_court_at_war() -> void:
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(1, 2).at_war = true
	state.ensure_relation(1, 3).at_war = false
	var hostile: Dictionary = Hostility.owners(state, 1)
	assert_true(hostile.has(2))
	assert_false(hostile.has(3))
	assert_false(hostile.has(1))


# --- test_fleet_passes ---

## The sea's node-free passes: a turn's battles resolve in every region and the
## drowned leave their roster, while the roster surgery a hand-over, a passage
## and a battle need lives in FleetRosters, where the layer, the save and the AI
## read the same list (wiki: map-topology § two regions; ships-and-naval § Naval
## Combat, § Ports that change hands).

const passes_NavalFixture = preload("res://tests/naval_fixture.gd")
const OWNER: int = 0
const RIVAL: int = 1
const CARIBBEAN: int = 0


func test_every_region_fights_and_names_its_battle() -> void:
	var world: WorldMap = _passes_world()
	var regions: MapRegionTable = _passes_regions()

	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, regions, _passes_war, {"seed": 7, "turn": 3}
	)

	assert_true(battles.size() >= 1, "two crowns at war in one zone fight")
	for battle: Dictionary in battles:
		assert_eq(int(battle["region"]), 0, "only the Old World's zone is contested")
	assert_eq(
		(regions.value(1, []) as Array).size(), 2,
		"a region with no battle keeps the roster it had"
	)


func test_a_beaten_squadron_leaves_its_region() -> void:
	var world: WorldMap = _passes_world()
	var regions: MapRegionTable = _passes_regions()

	NavalBattles.resolve_region_turn(world, regions, _passes_war, {"seed": 7, "turn": 3})

	var old_world: Array[FleetState] = []
	old_world.assign(regions.value(0, []))
	assert_eq(old_world.size(), 1, "the lone hull goes down and its squadron leaves the roster")
	assert_eq(old_world[0].owner, OWNER, "the victor keeps the sea")
	assert_true(old_world[0].is_afloat())


func test_no_hostility_leaves_the_sea_alone() -> void:
	var world: WorldMap = _passes_world()
	var regions: MapRegionTable = _passes_regions()

	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, regions, _passes_peace, {"seed": 7, "turn": 3}
	)

	assert_true(battles.is_empty(), "peace spills no blood")
	assert_eq((regions.value(0, []) as Array).size(), 2, "both squadrons keep the sea")


## --- roster surgery ---------------------------------------------------------


func test_prune_drops_a_squadron_with_no_hulls() -> void:
	var live: FleetState = FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"])
	var sunk: FleetState = FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_2"])
	sunk.hulls.clear()
	var roster: Array[FleetState] = [live, sunk, null]

	FleetRosters.prune(roster)

	assert_eq(roster.size(), 2, "a hauled-out squadron leaves")
	assert_eq(roster[0], live, "the live command keeps its berth")
	assert_null(roster[1], "a null slot is not the same as a sunk one: only hulls decide")


func test_hand_over_recolours_or_retires_a_crowns_squadrons() -> void:
	var roster: Array[FleetState] = [
		FleetState.at_sea(1, RIVAL, CARIBBEAN, ["ship_1"]),
		FleetState.at_sea(2, OWNER, CARIBBEAN, ["ship_2"]),
	]

	FleetRosters.hand_over(roster, RIVAL, OWNER)

	assert_eq(roster.size(), 2, "an absorption keeps every hull")
	assert_eq(roster[0].owner, OWNER, "the loser's colours change")

	FleetRosters.hand_over(roster, OWNER, MapModel.NO_ID)

	assert_true(roster.is_empty(), "a terminal fall retires every squadron it owned")


func test_a_passage_renumbers_the_crossing_squadron() -> void:
	var regions: MapRegionTable = _passes_regions()
	var from: Array[FleetState] = []
	from.assign(regions.value(0, []))
	var crossing: FleetState = from[0]

	var destination: Array[FleetState] = FleetRosters.hand_to_region(
		regions, 0, crossing, 1, from
	)

	assert_eq(destination.size(), 3, "the squadron lands in the other roster")
	assert_eq(int((regions.value(0, []) as Array).size()), 1, "and leaves the one it sailed from")
	assert_eq(crossing.id, 5, "it takes the next free id across every region")
	var ids: Array[int] = []
	for region: Array in FleetRosters.all(regions):
		for fleet: FleetState in region:
			ids.append(fleet.id)
	ids.sort()
	assert_eq(ids, [2, 3, 4, 5] as Array[int], "both rosters list every hull and no id twice")


func test_zones_at_sea_lists_each_zone_once() -> void:
	var roster: Array[FleetState] = [
		FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"]),
		FleetState.at_sea(2, OWNER, CARIBBEAN, ["ship_2"]),
		FleetState.at_sea(3, OWNER, 1, ["ship_3"]),
		FleetState.at_sea(4, RIVAL, 1, ["ship_4"]),
		FleetState.in_port(5, OWNER, 0, ["ship_5"]),
	]

	assert_eq(
		FleetRosters.zones_at_sea(roster, OWNER), [CARIBBEAN, 1] as Array[int],
		"one entry per zone the crown holds, and no port"
	)
	assert_true(FleetRosters.zones_at_sea(roster, 9).is_empty(), "a crown at no sea holds no zone")


func test_each_visits_every_region_roster() -> void:
	var regions: MapRegionTable = _passes_regions()
	var seen: Array[int] = []

	FleetRosters.each(
		regions, func(roster: Array[FleetState]) -> void: seen.append(roster.size())
	)

	seen.sort()
	assert_eq(seen, [2, 2] as Array[int], "every stored roster is visited once")


## --- berths -----------------------------------------------------------------


func test_prune_drops_the_marker_of_a_sunk_squadron() -> void:
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	var kept: FleetState = FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"])
	var sunk: FleetState = FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_2"])
	var kept_marker: Ship = markers.make(kept)
	var sunk_marker: Ship = markers.make(sunk)
	markers.selected_ship = sunk_marker

	markers.prune([kept] as Array[FleetState])

	assert_eq(markers.ships.size(), 1, "only the squadron still on the roster keeps a marker")
	assert_eq(markers.ships[0], kept_marker)
	assert_null(markers.selected_ship, "a selection cannot outlive the hull that wore it")
	markers.remove(kept_marker)


func test_a_port_berth_prefers_the_registered_tile() -> void:
	var model: MapModel = passes_NavalFixture.build()

	assert_eq(
		ShipMarkers.port_position(model, 0),
		MapGeo.tile_center(1, 0, ShipMarkers.TILE_SIZE),
		"the harbour tile is the berth"
	)
	model.provinces[0].port_tile = Vector2i(-1, -1)
	assert_eq(
		ShipMarkers.port_position(model, 0),
		model.province_center(0) * ShipMarkers.TILE_SIZE,
		"a province with no harbour tile berths at its centre"
	)


## --- fleets in one station (wiki: ships-and-naval § Fleets in one station;
## DR-20261119-08) ------------------------------------------------------------


## Four of the crown's squadrons and one rival, all in the Mar Caribe, in id
## order: 1-3 stand in the row, 4 leads the stack, 5 rides behind her.
func _station_fleets() -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	for index in 5:
		var owner: int = RIVAL if index == 4 else OWNER
		fleets.append(FleetState.at_sea(index + 1, owner, CARIBBEAN, ["ship_%d" % (index + 1)]))
	return fleets


## The crown's squadrons in one water fan out in a short row; the rest of hers
## and every rival's ride one stack whose head draws the hull, so a rival is
## never a nation row of her own.
func test_a_shared_station_fans_the_crown_out_and_stacks_the_rest() -> void:
	var fleets: Array[FleetState] = _station_fleets()
	var plan: Dictionary = FleetLanes.plan(fleets, OWNER)
	var lanes: Dictionary = plan["lanes"]
	var stacks: Dictionary = plan["stacks"]

	# Four slots: the crown's three in a row, then the stack the rest ride.
	assert_eq(lanes.size(), 4, "three fan steps and one stack head")
	assert_eq(lanes[1], Vector2(-1.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_eq(lanes[2], Vector2(-0.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_eq(lanes[3], Vector2(0.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_eq(lanes[4], Vector2(1.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_false(lanes.has(5), "the rival behind the head draws no hull of her own")
	assert_eq(int(plan["fronts"]["sea:0"]), 4, "the crown's fourth draws the stack")
	assert_eq(stacks[4].size(), 2, "her fourth and the rival walk one cycle")
	assert_eq(int(stacks[4][1]), 5, "the cycle keeps the station's own order")


## A station of rivals only is one stack, never a row: the crown reads their
## courts through the cycle, one command at a time.
func test_a_station_of_rivals_is_one_stack() -> void:
	var fleets: Array[FleetState] = [
		FleetState.at_sea(7, RIVAL, CARIBBEAN, ["a"]),
		FleetState.at_sea(8, 2, CARIBBEAN, ["b"]),
	]
	var plan: Dictionary = FleetLanes.plan(fleets, OWNER)

	assert_eq((plan["lanes"] as Dictionary).size(), 1, "one hull for the whole water")
	assert_eq((plan["stacks"] as Dictionary)[7].size(), 2)
	assert_false((plan["lanes"] as Dictionary).has(8), "the second rival is covered")


## The markers take the plan: each fanned squadron draws at her own step, a
## covered squadron draws no hull, and the head wears the pennants of the courts
## stacked behind her.
func test_the_markers_lay_the_row_out_and_cover_the_stack() -> void:
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	var fleets: Array[FleetState] = _station_fleets()
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.layout(fleets, OWNER)
	var first: Ship = markers.find(1)
	var second: Ship = markers.find(2)
	var head: Ship = markers.find(4)
	var behind: Ship = markers.find(5)

	assert_lt(first.drawn_position().x, second.drawn_position().x, "the row runs left to right")
	assert_false(first.covered)
	assert_false(head.covered, "the head of the stack draws the hull")
	assert_true(behind.covered, "the squadron behind her draws none")
	assert_true(head.shows_hull())
	assert_false(behind.shows_hull())
	assert_eq(head.pips.size(), 1, "one pennant for the court behind her")
	assert_eq(int(head.pips[0]), RIVAL, "and it flies that court's colour")
	assert_true(behind.pips.is_empty() or behind.pips.size() == 1)

	# The plate prints on the squadron in the crown's hand, and always on a rival
	# the fog has not read (wiki: ships-and-naval § Fleets in one station,
	# § Sighted strength).
	assert_false(first.shows_plate(), "a read squadron out of hand keeps her figure back")
	first.set_selected(true)
	assert_true(first.shows_plate(), "the squadron in hand prints it")
	behind.set_intel(false)
	assert_true(behind.shows_plate(), "an unread rival's plate still says the fog withholds it")


## The crown's selection comes to the head of her stack, so the squadron she is
## reading keeps drawing the hull; a rival the fog withholds never takes it.
func test_the_selection_leads_the_stack_and_the_fog_keeps_her_hidden() -> void:
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	var fleets: Array[FleetState] = []
	for index in 3:
		fleets.append(FleetState.at_sea(index + 1, RIVAL, CARIBBEAN, ["ship_%d" % index]))
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.layout(fleets, OWNER)
	assert_eq(int(markers.find(1).stack[0]), 1, "the first rival draws the stack")

	markers.selected_ship = markers.find(3)
	markers.layout(fleets, OWNER)
	assert_false(markers.find(3).covered, "the squadron in hand draws the hull")
	assert_true(markers.find(1).covered)
	assert_eq(int(markers.find(3).stack.find(3)), 2, "her place in the cycle never moves")

	# The fog takes the first rival: the head passes to the next one drawn.
	markers.find(1).visible = false
	markers.selected_ship = null
	markers.layout(fleets, OWNER)
	assert_true(markers.find(1).covered, "a rival under the fog is never handed the hull")
	assert_false(markers.find(2).covered)
	assert_eq(markers.next_in_stack(markers.find(2)).fleet_id, 3, "the cycle skips her")


## A shared station's reading order names every squadron the chart draws there —
## the crown's row first, then the stack behind it — and never one the fog
## withholds, so a tap on the row still says which command of the water is in
## hand (wiki: ships-and-naval § Fleets in one station).
func test_a_shared_station_names_every_hull_the_chart_draws() -> void:
	var fleets: Array[FleetState] = _station_fleets()
	var plan: Dictionary = FleetLanes.plan(fleets, OWNER)
	var stations: Dictionary = plan["stations"]

	assert_eq((stations[1] as Array).size(), 5, "four of the crown's and the rival")
	assert_eq(int((stations[1] as Array)[0]), 1, "the row leads the reading")
	assert_eq(int((stations[1] as Array)[3]), 4, "the stack stands after the row")

	# The fog's rival is not counted, and her colour rides no pennant.
	var fogged: Array[int] = [5]
	var hidden_plan: Dictionary = FleetLanes.plan(fleets, OWNER, -1, fogged)
	var hidden_stations: Dictionary = hidden_plan["stations"] as Dictionary
	assert_eq((hidden_stations[1] as Array).size(), 4, "the unseen rival is not counted")
	assert_false((hidden_stations[1] as Array).has(5), "and holds no place in the order")

	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.find(5).visible = false
	markers.layout(fleets, OWNER)
	assert_eq(markers.find(4).station.size(), 4, "the head reads what the chart draws")
	assert_true(markers.find(4).pips.is_empty(), "an unseen court wears no pennant")


## The crown's row keeps its own reading when the stack is empty: a fanned
## squadron is told her place among the water's commands, not her place in a
## cycle she never joined (wiki: ships-and-naval § Fleets in one station).
func test_a_fanned_squadron_still_reads_her_station() -> void:
	var fleets: Array[FleetState] = []
	for index in 2:
		fleets.append(FleetState.at_sea(index + 1, OWNER, CARIBBEAN, ["ship_%d" % index]))
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.layout(fleets, OWNER)
	var first: Ship = markers.find(1)
	assert_true(first.stack.is_empty(), "a row of two rides no stack")
	assert_eq(first.station.size(), 2, "the station's reading still holds both hulls")
	assert_eq(int(first.station[0]), 1)


## --- fixtures ---------------------------------------------------------------


## Two Old-World charts: region 0 is at war over the Caribbean with four carracks
## against one sloop, region 1 keeps two squadrons of one crown in company.
func _passes_world() -> WorldMap:
	var world := WorldMap.new()
	for index in 2:
		var model: MapModel = passes_NavalFixture.build()
		model.region_id = index
		world.add_region(model)
	return world


func _passes_regions() -> MapRegionTable:
	var regions := MapRegionTable.new()
	var strong: Array[FleetState] = [
		FleetState.at_sea(
			1, OWNER, CARIBBEAN, ["ship_1", "ship_2", "ship_3", "ship_4"],
			{"ship_1": "carrack", "ship_2": "carrack", "ship_3": "carrack", "ship_4": "carrack"}
		),
	]
	var weak: Array[FleetState] = [
		FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_5"], {"ship_5": "sloop"}),
	]
	var company: Array[FleetState] = [
		FleetState.at_sea(3, RIVAL, CARIBBEAN, ["ship_6"], {"ship_6": "carrack"}),
		FleetState.at_sea(4, RIVAL, CARIBBEAN, ["ship_7"], {"ship_7": "carrack"}),
	]
	var old_world: Array[FleetState] = []
	old_world.append_array(strong)
	old_world.append_array(weak)
	regions.set_region(0, old_world)
	regions.set_region(1, company)
	return regions


## The court's war query: the two crowns of the Old World are at war.
func _passes_war(a: int, b: int) -> bool:
	return (a == OWNER and b == RIVAL) or (a == RIVAL and b == OWNER)


## The same query in peacetime: no pair is hostile.
func _passes_peace(_a: int, _b: int) -> bool:
	return false

# --- fleet_split ---

## A sea-going squadron of three hulls, mixed types, moored nowhere.
func _split_fleet() -> FleetState:
	return FleetState.at_sea(
		2, 0, 0, ["ship_1", "ship_2", "ship_3"],
		{"ship_1": "carrack", "ship_2": "sloop", "ship_3": "fluyte"}
	)

func test_a_hull_detaches_into_a_squadron_of_her_own() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	var fleets: Array[FleetState] = [fleet]
	var flown: String = ShipNames.of(fleet, "ship_2")

	var result: Dictionary = FleetSplit.detach(
		_fleet_sortie_model, fleets, fleet, "ship_2", 9
	)

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.hulls, ["ship_1", "ship_3"], "the squadron keeps her other hulls")
	var split: FleetState = result["fleet"] as FleetState
	assert_not_null(split)
	assert_eq(split.id, 9, "she takes the id the roster offered")
	assert_eq(split.hulls, ["ship_2"], "the detached hull flies alone")
	assert_eq(split.type_of("ship_2"), "sloop", "she keeps her catalog type")
	assert_eq(ShipNames.of(split, "ship_2"), flown, "she keeps the name she flew")
	assert_true(split.is_at_sea())
	assert_eq(split.sea_zone, fleet.sea_zone, "she stands in the same water")
	assert_eq(fleets.size(), 2, "the roster keeps both commands")
	assert_eq(String(result["name"]), flown)

func test_the_new_squadron_takes_no_station_and_keeps_the_readiness() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	fleet.moved = true
	fleet.mission = FleetState.Mission.PATROL
	fleet.beachhead_province = 1
	fleet.beachhead_turn = 4
	fleet.add_civilian(11)
	var fleets: Array[FleetState] = [fleet]

	var result: Dictionary = FleetSplit.detach(
		_fleet_sortie_model, fleets, fleet, "ship_3", 9
	)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var split: FleetState = result["fleet"] as FleetState
	assert_true(split.moved, "a hull that has sailed does not sail again")
	assert_eq(split.mission, FleetState.Mission.NONE, "the station stays with the squadron")
	assert_eq(split.blockade_province, MapModel.NO_ID)
	assert_false(split.has_beachhead(), "a landing site is one squadron's")
	assert_eq(split.civilian_count(), 0, "the colonists stay aboard the squadron")
	assert_eq(fleet.civilian_count(), 1)

func test_a_squadron_of_one_hull_has_nothing_to_detach() -> void:
	_setup_fleet_sortie()
	var fleet := FleetState.at_sea(2, 0, 0, ["ship_1"])
	var fleets: Array[FleetState] = [fleet]

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, fleet, "ship_1")

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("one hull"))
	assert_eq(fleets.size(), 1)

func test_a_hull_that_is_not_aboard_is_refused() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	var fleets: Array[FleetState] = [fleet]

	var result: Dictionary = FleetSplit.detach(
		_fleet_sortie_model, fleets, fleet, "ship_99", 9
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("not aboard"))
	assert_eq(fleet.hulls.size(), 3, "nothing leaves the squadron")
	assert_eq(fleets.size(), 1, "no command is founded")

func test_the_home_squadron_keeps_the_seat() -> void:
	_setup_fleet_sortie()
	var home := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})
	var moored := FleetState.in_port(4, 1, 0, ["c", "d"], {"c": "fluyte", "d": "carrack"})

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, home, "a")

	assert_true(NavalMovement.is_home_fleet(_fleet_sortie_model, home))
	assert_false(bool(check["ok"]), "only the home fleet lies in port at the seat")
	assert_true(String(check["reason"]).contains("home squadron"))
	assert_true(
		bool(FleetSplit.can_detach(_fleet_sortie_model, moored, "c")["ok"]),
		"a squadron in a foreign port may still split"
	)

func test_a_hull_leaves_only_when_the_passengers_fit() -> void:
	_setup_fleet_sortie()
	var crowded := FleetState.at_sea(
		2, 0, 0, ["ship_1", "ship_2"], {"ship_1": "carrack", "ship_2": "sloop"}
	)
	crowded.add_civilian(11)
	crowded.add_civilian(12)

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, crowded, "ship_1")

	assert_false(bool(check["ok"]), "two colonists need two hulls")
	assert_true(String(check["reason"]).contains("2 passengers"))
	crowded.add_hull("ship_3", "carrack")
	assert_true(bool(FleetSplit.can_detach(_fleet_sortie_model, crowded, "ship_1")["ok"]))

func test_troops_aboard_hold_the_squadron_whole() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	fleet.embarked_army = 7

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, fleet, "ship_1")

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Land the troops"))

func test_the_rows_read_every_hull_and_name_her() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()

	var rows: Array[Dictionary] = FleetSplit.rows(_fleet_sortie_model, fleet)

	assert_eq(rows.size(), 3, "every hull of the squadron is on the list")
	for row: Dictionary in rows:
		assert_true(bool(row["ok"]), String(row["reason"]))
		assert_eq(String(row["name"]), ShipNames.of(fleet, String(row["hull"])))
		assert_false(String(row["type_name"]).is_empty())
	assert_eq(FleetSplit.rows(_fleet_sortie_model, null), [] as Array[Dictionary])

func test_the_split_drawer_lists_every_hull_and_files_one_tap() -> void:
	_setup_fleet_sortie()
	var block := FleetSplitBlock.new()
	add_child(block)
	var fleet: FleetState = _split_fleet()
	var emitted: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: emitted.append(action))

	block.show_rows(_fleet_sortie_model, fleet, true, false)

	assert_true(block._button.visible, "a squadron of three hulls may split")
	assert_false(block._scroll.visible, "the drawer waits for a tap")
	assert_eq(block._note.text, FleetSplit.NOTE, "the rule sits on the sheet")
	block.set_open(true)
	assert_true(block._scroll.visible)
	var detaches: Array[Button] = []
	for node: Node in block.find_children("*", "Button", true, false):
		if (node as Button).text == "Detach":
			detaches.append(node as Button)
	assert_eq(detaches.size(), 3, "every hull offers her own detach")
	var hull_name: String = ShipNames.of(fleet, "ship_1")
	var printed: bool = false
	for node: Node in block.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains(hull_name) and text.contains("Carrack"):
			printed = true
	assert_true(printed, "the row prints '%s — Carrack'" % hull_name)
	detaches[0].pressed.emit()
	assert_eq(emitted, ["split:ship_1"], "the tap hands the hull to the dossier")
	block.free()

func test_the_split_drawer_names_the_gate_instead_of_a_press() -> void:
	_setup_fleet_sortie()
	var block := FleetSplitBlock.new()
	add_child(block)
	var home := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})

	block.show_rows(_fleet_sortie_model, home, true, false)

	assert_false(block._button.visible, "the home squadron keeps the seat")
	assert_true(block._note.visible, "the reason is on the sheet, not in a hover")
	assert_true(block._note.text.contains("home squadron"), block._note.text)
	block.show_rows(_fleet_sortie_model, home, false, false)
	assert_false(block._note.visible, "a rival's squadron reads nothing")
	block.free()

func test_a_squadron_of_one_hull_shows_no_drawer() -> void:
	_setup_fleet_sortie()
	var block := FleetSplitBlock.new()
	add_child(block)
	var fleet := FleetState.at_sea(2, 0, 0, ["ship_1"])

	block.show_rows(_fleet_sortie_model, fleet, true, false)

	assert_false(block._button.visible)
	assert_false(block._note.visible, "nothing to explain on a single hull")
	block.free()
