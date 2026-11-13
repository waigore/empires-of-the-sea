class_name MapPlayWiring
extends RefCounted
## Connects the map's view signals to the play steps that answer them
## (REQ-P3-02). Views emit intents; a MapPlay* helper owns each step; the
## screen mounts this once instead of holding a wall of anonymous lambdas, so
## every wire names its owner and a new view control adds one line here.
##
## Host-only wires stay on MapScreen: the pause menu's save/load/menu seals and
## the region seal, which parks the whole frame around `MapPlayRegion`.


## Wires every mounted view in `play` to its play step. Safe to call once after
## `PlaySession.bind_views`; a missing view is skipped rather than fatal.
static func connect_views(play: PlaySession) -> void:
	if play == null:
		return
	if play.camera != null:
		_connect_camera(play, play.camera)
	if play.hud != null:
		_connect_bar(play, play.hud)
	if play.ship_layer != null:
		_connect_fleets(play, play.ship_layer)
	if play.army_layer != null:
		_connect_armies(play, play.army_layer)
	if play.civilian_layer != null:
		_connect_civilians(play, play.civilian_layer)
	if play.improvements != null:
		_connect_improvements(play, play.improvements)


## Camera taps and pans: a tap is a map intent, a pan re-reads hover.
static func _connect_camera(play: PlaySession, camera: MapCamera) -> void:
	camera.tapped.connect(
		func(world_position: Vector2) -> void: MapPlayInput.on_tapped(play, world_position)
	)
	camera.view_changed.connect(MapPlayInput.on_view_changed.bind(play))


## The cartouche bar, the dossiers' orders and the seals that open a ledger.
static func _connect_bar(play: PlaySession, hud: GameHud) -> void:
	hud.end_turn_pressed.connect(MapPlayTurn.end_turn.bind(play))
	if play.camera != null:
		hud.zoom_in_pressed.connect(play.camera.zoom_in)
		hud.zoom_out_pressed.connect(play.camera.zoom_out)
	hud.minimap_jump.connect(
		func(point: Vector2) -> void: MapPlayInput.on_minimap_jump(play, point)
	)
	hud.focus_capital_pressed.connect(MapPlaySetup.focus_capital.bind(play))
	hud.diplomacy_pressed.connect(MapPlayDiplomacy.open.bind(play))
	hud.diplomacy_order.connect(
		func(kind: String, target: int, arg: String) -> void:
			MapCourtOrders.apply(play, kind, target, arg)
	)
	hud.panel_action.connect(
		func(action: String) -> void: MapPlayInput.on_panel_action(play, action)
	)
	hud.panel_closed.connect(MapPlayInput.deselect.bind(play))
	hud.army_action.connect(
		func(action: String) -> void: MapPlayArmies.on_action(play, action)
	)
	hud.army_closed.connect(MapPlayInput.deselect.bind(play))
	hud.fleet_action.connect(
		func(action: String) -> void: MapPlayFleets.on_action(play, action)
	)
	hud.fleet_closed.connect(MapPlayInput.deselect.bind(play))
	hud.civilian_action.connect(
		func(action: String) -> void: MapPlayCivilians.on_action(play, action)
	)
	hud.civilian_cancel.connect(MapPlayCivilians.on_cancel.bind(play))
	hud.civilian_closed.connect(MapPlayInput.deselect.bind(play))


## Squadrons: a tap selects, a landed order reports, a passage swaps the chart.
static func _connect_fleets(play: PlaySession, ships: ShipLayer) -> void:
	ships.zone_entered.connect(
		func(zone_id: int, ship: Ship) -> void:
			MapPlayFleets.on_zone_entered(play, zone_id, ship)
	)
	ships.ship_selected.connect(
		func(ship: Ship) -> void: MapPlayFleets.select(play, ship)
	)
	ships.fleet_moved.connect(
		func(fleet: FleetState, result: Dictionary) -> void:
			MapPlayFleets.on_moved(play, fleet, result)
	)
	ships.warp_crossed.connect(
		func(fleet: FleetState, result: Dictionary) -> void:
			MapPlayWarp.on_crossed(play, fleet, result)
	)


## Armies: the standard selects, the march reports; a cleared tap closes the
## dossier so the province sheet can open instead.
static func _connect_armies(play: PlaySession, armies: ArmyLayer) -> void:
	armies.army_selected.connect(
		func(army: ArmyState) -> void:
			if army != null:
				MapPlayArmies.select(play, army)
			else:
				MapPlayArmies.hide_dossier(play)
	)
	armies.army_moved.connect(
		func(army: ArmyState, result: Dictionary) -> void:
			MapPlayArmies.on_moved(play, army, result)
	)


## Civilians: a unit tap opens its orders, a finished march redraws the survey.
static func _connect_civilians(play: PlaySession, civilians: CivilianLayer) -> void:
	civilians.unit_selected.connect(
		func(unit: CivilianState) -> void: MapPlayCivilians.select(play, unit)
	)
	civilians.unit_moved.connect(
		func(unit: CivilianState, result: Dictionary) -> void:
			MapPlayCivilians.on_moved(play, unit, result)
	)


## The improvement sheet: its orders and the focus that centres the tile.
static func _connect_improvements(play: PlaySession, improvements: ImprovementPanel) -> void:
	improvements.action_pressed.connect(
		func(action: String, tile: Vector2i) -> void:
			MapPlayImprovements.on_action(play, action, tile)
	)
	improvements.focus_pressed.connect(
		func(tile: Vector2i) -> void: MapPlayImprovements.on_action(play, "focus", tile)
	)
