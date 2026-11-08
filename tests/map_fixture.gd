extends RefCounted
## Shared small maps for integration suites. Cached once per Godot worker so
## coverage runs do not regenerate a world per test method (gd-tools clones a
## fresh suite instance each time; underscore fields are not copied from
## before_all).

const SEED: int = 1500
## Single-region generator / canvas fixtures.
const WIDTH: int = 48
const HEIGHT: int = 32
## Two-region world used by MapScreen integration + world setup.
const WORLD_WIDTH: int = 64
const WORLD_HEIGHT: int = 42

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


static func attach_screen(host: Node) -> MapScreen:
	var screen: MapScreen = load("res://scenes/map_screen.tscn").instantiate()
	screen.map_width = WORLD_WIDTH
	screen.map_height = WORLD_HEIGHT
	screen.preset_world = world()
	host.add_child(screen)
	return screen
