extends GdToolsTest
## Province-graph queries (`ProvinceGraph`) and the Minor share's pocket pass:
## components, connectivity, land hops and ownership tallies over an induced set
## (wiki: game-setup, map-topology). Pure rules, so one row of tiles per case.

## Non-underscore so before_all state is copied onto each test instance.
var grid: MapModel = null


func before_all() -> void:
	grid = _grid_owners(9, 1, [])


func test_components_split_a_set_into_its_landmasses_largest_first() -> void:
	# Runs 0-1-2 and 6-7-8 are equal-sized and apart.
	assert_eq(_components([0, 1, 2, 6, 7, 8]), [[0, 1, 2], [6, 7, 8]])
	# The longer run comes first whatever its ids are.
	assert_eq(_components([0, 1, 4, 5, 6, 7]), [[4, 5, 6, 7], [0, 1]])


func test_components_of_an_empty_set_is_no_landmass() -> void:
	assert_eq(_components([]), [])


func test_a_set_is_connected_only_when_nothing_sits_apart() -> void:
	assert_true(ProvinceGraph.is_contiguous(grid, [4, 5, 6, 7]), "one run")
	assert_true(ProvinceGraph.is_contiguous(grid, [3]), "one province holds")
	assert_false(ProvinceGraph.is_contiguous(grid, [0, 1, 8]), "an island splits it")
	assert_false(ProvinceGraph.is_contiguous(grid, []), "no land is no holding")


func test_hops_count_land_steps_from_the_source() -> void:
	assert_eq(ProvinceGraph.hops(grid, [0, 1, 2, 3], 0), {0: 0, 1: 1, 2: 2, 3: 3})
	# A source outside the set reaches nothing.
	assert_eq(ProvinceGraph.hops(grid, [0, 1], 9), {})


func test_owner_counts_and_unowned_read_one_set() -> void:
	# Tile 0 and 1 belong to court 2, tile 2 to court 3, the rest are open.
	var model: MapModel = _grid_owners(3, 1, [2, 2, 3])
	assert_eq(ProvinceGraph.owner_counts(model, [0, 1, 2]), {2: 2, 3: 1})
	assert_eq(ProvinceGraph.unowned(model, [0, 1, 2]), [])
	model.province_data(1).owner = MapModel.NO_ID
	assert_eq(ProvinceGraph.unowned(model, [0, 1, 2]), [1], "open land, ascending")


## A cove a Minor Nation seals is too small to seat a Great Power, so the
## bordering court takes it and the pool comes back without it
## (wiki: game-setup § Minor Nation assignment).
func test_a_sealed_cove_joins_the_bordering_minor() -> void:
	# 10 owns tile 0, 11 owns tile 1; pocket tiles 2-3 sit on the bottom row
	# beside 10's tile, and no Great Power is left to take them.
	var model: MapModel = _grid_owners(2, 2, [10, 11, MapModel.NO_ID, MapModel.NO_ID])
	var pool: Array = MinorShare.absorb_pockets(model, _ids(model), [10, 11], 0)
	assert_eq(model.province_data(2).owner, 10, "the bordering court takes the cove")
	assert_eq(model.province_data(3).owner, 10, "the whole cove follows")
	assert_true(pool.is_empty(), "nothing is left for the Great Powers")
	assert_true(model.province_data(2).population > 0, "a taken pocket is settled")


## A court that cannot take a pocket leaves it open rather than vanish land.
func test_a_pocket_with_no_minor_border_stays_open() -> void:
	var model: MapModel = _grid_owners(2, 2, [10, 11, MapModel.NO_ID, MapModel.NO_ID])
	var pool: Array = MinorShare.absorb_pockets(model, _ids(model), [] as Array[int], 0)
	assert_eq(pool, [2, 3], "no taker, no change")
	assert_eq(model.province_data(2).owner, MapModel.NO_ID, "the cove keeps no owner")


func _components(ids: Array) -> Array:
	return ProvinceGraph.components(grid, ids)


## One-tile provinces on a square grid; `owners` is row-major (index -> owner).
func _grid_owners(width: int, height: int, owners: Array) -> MapModel:
	var model: MapModel = MapModel.new()
	model.setup(width, height)
	var provinces: Array[ProvinceState] = []
	for y in height:
		for x in width:
			var index: int = model.index_of(x, y)
			model.terrain[index] = MapModel.Terrain.PLAINS
			model.province[index] = index
			var tiles: Array[Vector2i] = [Vector2i(x, y)]
			var owner: int = int(owners[index]) if index < owners.size() else MapModel.NO_ID
			provinces.append(ProvinceState.create(
				index, "P%d" % index, tiles, Vector2(x + 0.5, y + 0.5), 1, owner
			))
	model.provinces = provinces
	return model


func _ids(model: MapModel) -> Array:
	return range(model.provinces.size())
