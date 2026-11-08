class_name MapPlayTurn
extends RefCounted
## End-of-turn resolution, capital framing, and the capital tile lookup.
## Combat and visibility rules stay in their own modules; this reports them.


static func end_turn(screen: MapScreen) -> void:
	MapPlayCivilians.resolve_work(screen)
	_resolve_naval_combat(screen)
	_resolve_visibility(screen)
	screen.ship_layer.begin_turn()
	screen.civilian_layer.begin_turn()
	MapPlayFleets.refresh_visibility(screen)
	screen.turn += 1
	var year: int = TurnTime.year_for_turn(screen.turn)
	screen.economy.resolve_turn()
	screen.treasury = screen.economy.economy.treasury
	screen.income = screen.economy.projected_income()
	screen.prestige += 1
	screen.hud.set_turn(screen.turn, year)
	screen.hud.set_prestige(screen.prestige)
	screen.hud.toast("Turn %d — %d" % [screen.turn, year])
	var selected: Ship = screen.ship_layer.selected_ship
	if selected != null:
		var fleet: FleetState = screen.ship_layer.fleet_of(selected)
		if fleet != null:
			screen.hud.show_fleet(screen.model, fleet, fleet.owner == MapScreen.PLAYER_FACTION)
			MapPlayFleets.refresh_options(screen, fleet)
	if screen.civilian_layer.selected_unit != null:
		MapPlayCivilians.refresh_panel(screen)
	screen.improvements.refresh_if_open()
	screen.turn_ended.emit(screen.turn)


static func focus_capital(screen: MapScreen) -> void:
	screen.camera.focus_on(capital_world(screen), 0.7)


## World position of the ruler's seat: the capital tile from the capital-choice
## phase, falling back to the province centre when the map has no capital.
static func capital_world(screen: MapScreen) -> Vector2:
	if screen.capital_tile.x >= 0:
		return MapGeo.tile_center(screen.capital_tile.x, screen.capital_tile.y, MapScreen.TILE_SIZE)
	if screen.capital_province >= 0:
		return screen.model.province_center(screen.capital_province) * MapScreen.TILE_SIZE
	return Vector2.ZERO


static func capital_tile(screen: MapScreen, province_id: int) -> Vector2i:
	var data: Dictionary = screen.model.province_data(province_id)
	if data.is_empty():
		return CapitalChoice.NO_TILE
	return Vector2i(data.get("capital_tile", CapitalChoice.NO_TILE))


## Fleets that end movement in the same sea zone fight (wiki: ships-and-naval
## § Naval Combat). Rules resolve the battle; this only prunes markers and
## reports the outcome.
static func _resolve_naval_combat(screen: MapScreen) -> void:
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(screen.ship_layer.fleets)
	if battles.is_empty():
		return
	screen.ship_layer.prune_destroyed()
	for battle: Dictionary in battles:
		var zone: String = screen.model.sea_zone_name(int(battle["zone"]))
		screen.hud.toast(BattleReport.describe(battle, zone, MapGenerator.FACTION_NAMES))
	screen.hud.set_fleets(screen.ship_layer.hull_count(MapScreen.PLAYER_FACTION))
	screen.battle_resolved.emit(battles)


## End-of-turn visibility pass (wiki: fog-and-exploration). Zones with a fleet at
## sea stay visible; charted coasts fade until an explorer holds them.
static func _resolve_visibility(screen: MapScreen) -> void:
	if screen.visibility == null:
		return
	var at_sea: Array = []
	for ship: Ship in screen.ship_layer.ships:
		if ship.faction == MapScreen.PLAYER_FACTION and ship.zone >= 0:
			at_sea.append(ship.zone)
	var held: Array = CivilianMovement.held_provinces(
		screen.model, screen.civilian_layer.units, MapScreen.PLAYER_FACTION
	)
	var changed: Array = screen.visibility.end_of_turn(at_sea, held)
	if not changed.is_empty():
		screen.overlay.sync_visibility(screen.visibility, changed)
