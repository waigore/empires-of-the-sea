extends RefCounted
## Shared small maps for integration suites. Cached once per Godot worker so
## coverage runs do not regenerate a world per test method (gd-tools clones a
## fresh suite instance each time; underscore fields are not copied from
## before_all).

const SEED: int = 1500
## Single-region generator / canvas fixtures.
const WIDTH: int = 48
const HEIGHT: int = 32
## Two-region world used by MapScreen integration + world setup. The province
## target clamps to its 24/20 floor well before 64x42, so the smaller size keeps
## the same rosters while generating (and painting) far fewer tiles per suite.
const WORLD_WIDTH: int = 56
const WORLD_HEIGHT: int = 38

static var _world: WorldMap = null
static var _region: MapModel = null


static func world() -> WorldMap:
	if _world == null:
		_world = MapGenerator.new().generate_world(SEED, WORLD_WIDTH, WORLD_HEIGHT)
	return _world


static func region() -> MapModel:
	if _region == null:
		_region = MapGenerator.new().generate(SEED, WIDTH, HEIGHT)
	return _region


static func inland_province(model: MapModel) -> int:
	for province: ProvinceState in model.provinces:
		if not province.coastal and province.area > 30:
			return province.id
	return int(model.provinces[0].id)


static func foreign_province(model: MapModel) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			return province.id
	return MapModel.NO_ID


static func owned_resource_tile(model: MapModel, works: LandWorks) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if model.resource_at(tile.x, tile.y) < 0:
				continue
			if works.improvement_at(model, tile) > 0:
				continue
			return tile
	return Vector2i(-1, -1)


static func coastal_land_of(model: MapModel, zone_id: int) -> Vector2i:
	for tile: Vector2i in model.sea_zone_data(zone_id).tiles:
		for offset: Vector2i in CivilianMovement.NEIGHBORS:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if model.is_land(nx, ny):
				return Vector2i(nx, ny)
	return Vector2i(-1, -1)


static func fleet_at_sea(fleets: Array, owner: int) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet.owner == owner and fleet.is_at_sea():
			return fleet
	return null


static func mouse_button(pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


static func mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(400, 300)
	return event


## Ends the turn and declines any rival proposal the AI raises, so a suite that
## is not about consent still reaches the next turn. A call to arms or
## intervention still suspends, exactly as in play.
static func end_turn(play: PlaySession) -> void:
	MapPlayTurn.end_turn(play)
	while DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapPlayTurn.answer_proposal(play, false)


static func attach_screen(
	host: Node,
	faction: int = FactionCatalog.PLAYER_FACTION,
	leader: String = ""
) -> MapScreen:
	var screen: MapScreen = load("res://scenes/map_screen.tscn").instantiate()
	screen.map_width = WORLD_WIDTH
	screen.map_height = WORLD_HEIGHT
	screen.player_faction = faction
	screen.player_leader = leader
	screen.preset_world = world()
	host.add_child(screen)
	return screen
