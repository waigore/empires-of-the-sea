extends GdToolsTest
## Which resources count as discovered for a player (wiki: tech-tree
## § Discovery prerequisites; fog-and-exploration).

const Fixture = preload("res://tests/civilian_fixture.gd")

var _world: WorldMap = null
var _model: MapModel = null
var _view: VisibilityModel = null
var _works: LandWorks = null


func before_each() -> void:
	_model = Fixture.build()
	_world = WorldMap.new()
	_world.add_region(_model)
	_works = LandWorks.new()
	_view = VisibilityModel.new()
	_view.setup(_model, 0)
	_view.apply_initial()


func test_revealed_tiles_discover_their_resource() -> void:
	var found: Dictionary = TechDiscovery.revealed(_world, {0: _view}, _works, 0)
	assert_true(found.has("timber"))
	# The region opens charted (every tile starts fogged), so foreign grain is
	# known too; only prospected minerals stay hidden until an Explorer digs.
	assert_true(found.has("grain"))
	assert_false(found.has("horses"), "no tile holds horses on this map")


func test_prospect_minerals_need_prospecting() -> void:
	var found: Dictionary = TechDiscovery.revealed(_world, {0: _view}, _works, 0)
	assert_false(found.has("iron"))
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	found = TechDiscovery.revealed(_world, {0: _view}, _works, 0)
	assert_true(found.has("iron"))


func test_an_unseen_tile_reveals_nothing() -> void:
	var view := VisibilityModel.new()
	view.setup(_model, 0)
	view.levels.fill(VisibilityModel.Level.UNKNOWN)
	var found: Dictionary = TechDiscovery.revealed(_world, {0: view}, _works, 0)
	assert_eq(found, {})


func test_missing_world_or_region_is_harmless() -> void:
	assert_eq(TechDiscovery.revealed(null, {}, _works, 0), {})
	assert_eq(TechDiscovery.revealed(_world, {}, _works, 0), {})
