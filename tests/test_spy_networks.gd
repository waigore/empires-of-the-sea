extends GdToolsTest
## Espionage rules (wiki: civilian-units § Spy; fog-and-exploration § Explorer vs
## Spy; DR-20261110-03): which rival courts a posted Spy shadows, and how much
## research their finished work hands over.

const Fixture = preload("res://tests/civilian_fixture.gd")

## Fixture province 1 belongs to Great Power 1; province 0 to the player.
const PLAYER: int = 0
const RIVAL: int = 1
const MINOR: int = 6

var _model: MapModel = null


func before_each() -> void:
	_model = Fixture.build()


func _spy(tile: Vector2i, owner: int = PLAYER) -> CivilianState:
	return CivilianState.create(1, owner, "spy", tile)


func test_a_spy_on_a_rival_great_powers_land_shadows_that_court() -> void:
	# (3, 1) sits in province 1, owned by Great Power 1.
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(3, 1))], PLAYER
	)
	assert_eq(rivals, [RIVAL])


func test_a_spy_on_the_crowns_own_land_shadows_nobody() -> void:
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(1, 1))], PLAYER
	)
	assert_eq(rivals, [], "own soil is no rival court")


func test_minor_nations_and_tribes_are_not_research_rivals() -> void:
	var model: MapModel = Fixture.build_minor()
	# build_minor() province 1 belongs to Minor Nation 6.
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		model, [_spy(Vector2i(2, 1))], PLAYER
	)
	assert_eq(rivals, [], "the wiki names rival Great Powers only")
	assert_eq(model.province_owner(1), MINOR, "fixture sanity")


func test_two_spies_in_one_court_shadow_it_once() -> void:
	var units: Array[CivilianState] = [
		_spy(Vector2i(3, 0)), _spy(Vector2i(3, 1)),
	]
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(_model, units, PLAYER)
	assert_eq(rivals, [RIVAL], "one court, one share")


func test_each_shadowed_court_counts_its_own_land() -> void:
	var model: MapModel = _three_courts_map()
	var units: Array[CivilianState] = [
		_spy(Vector2i(2, 1)), _spy(Vector2i(4, 1)),
	]
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(model, units, PLAYER)
	assert_eq(rivals, [RIVAL, 2], "ascending, one entry per court")
	assert_eq(SpyNetworks.rival_names(rivals), "England, France")


func test_a_deed_putting_land_in_a_crowns_hands_counts_as_its_land() -> void:
	# An England-owned deed inside Genoa's province makes England the host.
	var model: MapModel = Fixture.build_minor()
	assert_true(model.purchase_tile(Vector2i(3, 1), RIVAL))
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		model, [_spy(Vector2i(3, 1))], PLAYER
	)
	assert_eq(rivals, [RIVAL])


func test_an_offscreen_spy_reads_nothing() -> void:
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(99, 99))], PLAYER
	)
	assert_eq(rivals, [])


func test_a_boost_lands_only_on_techs_the_shadowed_court_already_knows() -> void:
	var boost: Dictionary = SpyNetworks.research_boost(
		[RIVAL], {RIVAL: {"navigation": true, "land_enclosure": false}}
	)
	assert_eq(SpyNetworks.boost_for(boost, "navigation"), 15)
	assert_eq(SpyNetworks.boost_for(boost, "land_enclosure"), 0, "locked tech")
	assert_eq(SpyNetworks.boost_for(boost, "saw_mill"), 0, "unknown tech")


func test_two_shadowed_courts_stack_on_a_shared_advance() -> void:
	var boost: Dictionary = SpyNetworks.research_boost(
		[RIVAL, 2],
		{
			RIVAL: {"navigation": true},
			2: {"navigation": true, "saw_mill": true},
		}
	)
	assert_eq(SpyNetworks.boost_for(boost, "navigation"), 30)
	assert_eq(SpyNetworks.boost_for(boost, "saw_mill"), 15)


func test_no_rivals_means_no_boost() -> void:
	assert_true(SpyNetworks.research_boost([], {}).is_empty())
	assert_eq(SpyNetworks.boost_for({}, "navigation"), 0)


## Six tiles wide: the crown's province, England's, then France's.
func _three_courts_map() -> MapModel:
	var model := MapModel.new()
	model.setup(6, 3)
	var mine: Array[Vector2i] = []
	var england: Array[Vector2i] = []
	var france: Array[Vector2i] = []
	for y in 3:
		for x in 6:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 2:
				model.province[model.index_of(x, y)] = 0
				mine.append(tile)
			elif x < 4:
				model.province[model.index_of(x, y)] = 1
				england.append(tile)
			else:
				model.province[model.index_of(x, y)] = 2
				france.append(tile)
	var provinces: Array[ProvinceState] = [
		ProvinceState.create(0, "Cádiz", mine, Vector2(0.5, 1.0), mine.size(), PLAYER, true),
		ProvinceState.create(1, "Plymouth", england, Vector2(2.5, 1.0), england.size(), 1, false),
		ProvinceState.create(2, "Brest", france, Vector2(4.5, 1.0), france.size(), 2, false),
	]
	model.provinces = provinces
	return model
