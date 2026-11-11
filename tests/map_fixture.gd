extends RefCounted
## Shared small maps for integration suites. Cached once per Godot worker so
## coverage runs do not regenerate a world per test method (gd-tools clones a
## fresh suite instance each time; underscore fields are not copied from
## before_all).

const SEED: int = 1500
const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
## Single-region generator / canvas fixtures.
const WIDTH: int = 48
const HEIGHT: int = 32
## Two-region world used by MapScreen integration + world setup. The province
## target clamps to its 24/20 floor long before this size, so it keeps the same
## rosters (60 Old World / 30 New World provinces, 8 sea zones and passages, 6
## crowned capitals) while painting far fewer tiles per mounted screen. Two
## floors hold it here: sides stay at or above `SaveCodec.MIN_MAP_SIDE` (32) or
## a slot written from this world would not validate, and a crown needs ~16 free
## land tiles for the turn-100 advanced-start civilians (44x32 leaves the
## tightest crown 32).
const WORLD_WIDTH: int = 44
const WORLD_HEIGHT: int = 32

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


## Answers any rival proposal so a suite that only asserts the turn's outcome
## is not held by the court gate (wiki: diplomacy § Court proposals).
static func settle(play: PlaySession) -> void:
	while DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapCourtOrders.apply(
			play, DiplomacyProposals.KIND_REFUSE, play.player_faction, ""
		)


## Ownership, seats and tile deeds of the shared world as it was generated.
## Suites that hand provinces to a crown or buy deeds call this once, then
## `restore(world, snapshot)` in `before_each`/`after_each`, so the shared map
## stays a fresh world without paying for generation per case.
static func snapshot(world: WorldMap) -> Array:
	var rows: Array = []
	for region: MapModel in world.regions:
		rows.append(region.ownership.to_dict())
		var provinces: Array = []
		for province: ProvinceState in region.provinces:
			provinces.append([province, province.owner, province.capital])
		rows.append(provinces)
	return rows


static func restore(world: WorldMap, snapshot: Array) -> void:
	if world == null or snapshot.is_empty():
		return
	for index in world.region_count():
		var region: MapModel = world.region(index)
		region.ownership.apply_dict(snapshot[index * 2])
		for row: Array in snapshot[index * 2 + 1]:
			var province: ProvinceState = row[0]
			province.owner = int(row[1])
			province.capital = bool(row[2])


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


static func attach_screen(
	host: Node,
	faction: int = FactionCatalog.PLAYER_FACTION,
	leader: String = ""
) -> MapScreen:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_width = WORLD_WIDTH
	screen.map_height = WORLD_HEIGHT
	screen.player_faction = faction
	screen.player_leader = leader
	screen.preset_world = world()
	host.add_child(screen)
	return screen


## Reopens a saved session on the shared world. The preset is what keeps a
## reload from regenerating the map — SaveCodec applies the save's ownership,
## resources and deeds on top of the same world it would have generated.
static func open_save(host: Node, data: Dictionary, save_dir: String = "") -> MapScreen:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_width = WORLD_WIDTH
	screen.map_height = WORLD_HEIGHT
	screen.save_dir = save_dir
	screen.preset_world = world()
	screen.pending_save = data
	host.add_child(screen)
	return screen
