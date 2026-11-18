extends GdToolsTest
## TileEdges: the one province/sea seam walk every charted layer inks from (the
## overlay's outlines, the inset's coast and its crown hairlines). Pure data in,
## world-unit corner pairs out — no node, no drawing (REQ-P3-01, REQ-P3-03).

const Fixture = preload("res://tests/map_fixture.gd")

const UNIT: float = 22.0


func _charted_after_first_region() -> MapModel:
	return Fixture.region()


## A seam pair spans exactly one tile edge of the unit the caller asked for.
func test_a_seam_pair_spans_one_tile_edge() -> void:
	var top: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.TOP, UNIT)
	assert_eq(top, PackedVector2Array([Vector2(44.0, 66.0), Vector2(66.0, 66.0)]))
	var right: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.RIGHT, UNIT)
	assert_eq(right, PackedVector2Array([Vector2(66.0, 66.0), Vector2(66.0, 88.0)]))
	var bottom: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.BOTTOM, UNIT)
	assert_eq(bottom, PackedVector2Array([Vector2(66.0, 88.0), Vector2(44.0, 88.0)]))
	var left: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.LEFT, UNIT)
	assert_eq(left, PackedVector2Array([Vector2(44.0, 88.0), Vector2(44.0, 66.0)]))


## Off-grid steps read the model's sentinel, so the walk's outside test is the
## chart's edge and not a missing-province test.
func test_an_off_chart_tile_reads_as_outside() -> void:
	var model: MapModel = _charted_after_first_region()
	assert_eq(model.province_at(-1, 0), MapModel.NO_ID)
	assert_eq(model.sea_zone_at(model.width, 0), MapModel.NO_ID)


## A closed province outline traces each seam once and stays on that province's
## own tiles.
func test_a_province_outline_keeps_every_seam_once_and_bounded() -> void:
	var model: MapModel = _charted_after_first_region()
	var province: int = Fixture.inland_province(model)
	var mine := func(x: int, y: int) -> bool:
		return model.province_at(x, y) == province
	var seams: Array[PackedVector2Array] = TileEdges.province_seams(model, mine, UNIT)
	assert_gt(seams.size(), 3, "an inland province inks a closed outline")
	var seen: Dictionary = {}
	for path: PackedVector2Array in seams:
		assert_eq(path.size(), 2)
		var key: String = str(path)
		assert_false(seen.has(key), "a seam is inked once")
		seen[key] = true
		for point: Vector2 in path:
			assert_true(point.x >= 0.0 and point.y >= 0.0)
			assert_true(point.x <= float(model.width) * UNIT)
			assert_true(point.y <= float(model.height) * UNIT)


## The subdivisions read only the right and bottom steps, so the coast and the
## province ink never trace the same seam twice on the inset.
func test_division_slots_read_only_the_forward_steps() -> void:
	var model: MapModel = _charted_after_first_region()
	var province: int = Fixture.inland_province(model)
	var mine := func(x: int, y: int) -> bool:
		return model.province_at(x, y) == province
	var forward: Array[PackedVector2Array] = TileEdges.province_seams(
		model, mine, UNIT, TileEdges.Look.OUTSIDE,
		[TileEdges.Edge.RIGHT, TileEdges.Edge.BOTTOM]
	)
	var all_slots: Array[PackedVector2Array] = TileEdges.province_seams(model, mine, UNIT)
	assert_lt(forward.size(), all_slots.size(), "half the slots ink a little over half")
	for path: PackedVector2Array in forward:
		var width: float = absf(path[1].x - path[0].x)
		var height: float = absf(path[1].y - path[0].y)
		assert_true(width < 0.01 or height < 0.01)


## A coast is a land tile's seam against the sea: every seam is one tile edge
## long — never a diagonal — and it always borders charted land.
func test_a_coast_is_every_edge_whose_neighbour_is_land() -> void:
	var model: MapModel = _charted_after_first_region()
	var land := func(x: int, y: int) -> bool:
		return model.is_land(x, y)
	var coast: Array[PackedVector2Array] = TileEdges.province_seams(
		model, land, UNIT, TileEdges.Look.COAST
	)
	assert_gt(coast.size(), 0, "a generated region has a coast")
	for path: PackedVector2Array in coast:
		assert_eq(path.size(), 2)
		var run_along_x: float = absf(path[1].x - path[0].x)
		var run_along_y: float = absf(path[1].y - path[0].y)
		assert_true(run_along_x < 0.01 or run_along_y < 0.01, "a seam is one tile edge")
		assert_almost_eq(maxf(run_along_x, run_along_y), UNIT, 0.01)
		assert_true(_starts_on_land(model, path), "the ink starts on land")


## A division is only a seam between two charted crowned provinces: coast and
## fog never ink a border of their own.
func test_a_division_leaves_coast_and_fog_to_their_own_ink() -> void:
	var model: MapModel = _charted_after_first_region()
	var every_tile := func(_x: int, _y: int) -> bool:
		return true
	var divide := func(x: int, y: int) -> bool:
		return model.province_at(x, y) != MapModel.NO_ID
	var divided: Array[PackedVector2Array] = TileEdges.province_seams(
		model, divide, UNIT, TileEdges.Look.DIVIDE
	)
	assert_gt(divided.size(), 0, "crowned provinces share borders")
	for path: PackedVector2Array in divided:
		var a: Vector2 = path[0]
		var b: Vector2 = path[1]
		var step: Vector2 = (b - a).normalized()
		var mid: Vector2 = (a + b) * 0.5
		# The pair runs along the seam; the two crowns sit a half tile either
		# side of it, and both of them must be charted land.
		var side: Vector2 = Vector2(step.y, step.x) * UNIT * 0.5
		var left: Vector2i = Vector2i(
			int(floorf((mid.x + side.x) / UNIT)), int(floorf((mid.y + side.y) / UNIT))
		)
		var right: Vector2i = Vector2i(
			int(floorf((mid.x - side.x) / UNIT)), int(floorf((mid.y - side.y) / UNIT))
		)
		assert_true(model.is_land(left.x, left.y), "a division runs between crowned land")
		assert_true(model.is_land(right.x, right.y), "a division runs between crowned land")
		assert_ne(model.province_at(left.x, left.y), model.province_at(right.x, right.y))
	var whole_chart: Array[PackedVector2Array] = TileEdges.province_seams(
		model, every_tile, UNIT, TileEdges.Look.DIVIDE
	)
	assert_gte(whole_chart.size(), divided.size(), "a wider reading keeps every crowned seam")


## A neighbour reading lets a caller leave a step to another ink: the inset's
## fog hides its own seams rather than drawing a border into the unknown.
func test_a_neighbour_reading_can_leave_a_step_to_other_ink() -> void:
	var model: MapModel = _charted_after_first_region()
	var province: int = Fixture.inland_province(model)
	var mine := func(x: int, y: int) -> bool:
		return model.province_at(x, y) == province
	var every_step := func(_x: int, _y: int) -> bool:
		return true
	var only_east := func(x: int, y: int) -> bool:
		return x >= model.width / 2
	var clipped: Array[PackedVector2Array] = TileEdges.province_seams(
		model, mine, UNIT, TileEdges.Look.OUTSIDE, [], only_east
	)
	for path: PackedVector2Array in clipped:
		for point: Vector2 in path:
			assert_true(point.x / UNIT >= model.width / 2.0 - 1.0, "a clipped step stays out of the left half")
	var unclipped: Array[PackedVector2Array] = TileEdges.province_seams(
		model, mine, UNIT, TileEdges.Look.OUTSIDE, [], every_step
	)
	assert_gte(unclipped.size(), clipped.size(), "reading every neighbour keeps at least the clipped seams")


## The land tile a coast seam belongs to: the pair is vertical on the left or
## right of a tile and horizontal on its top or bottom, so the owner is the
## land side of it.
func _starts_on_land(model: MapModel, path: PackedVector2Array) -> bool:
	var mid: Vector2 = (path[0] + path[1]) * 0.5
	var near := Vector2i(int(floorf(mid.x / UNIT)), int(floorf(mid.y / UNIT)))
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if model.is_land(near.x + dx, near.y + dy):
				return true
	return false


## No chart, no ink: a layer mounted before its region builds gets an empty list.
func test_a_missing_or_unmeasured_chart_inks_nothing() -> void:
	var everywhere := func(_x: int, _y: int) -> bool:
		return true
	var model: MapModel = _charted_after_first_region()
	var empty_chart: MapModel = MapModel.new()
	var inks: Dictionary = {
		"a sea with no chart": TileEdges.sea_seams(null, everywhere, UNIT).size(),
		"a province with no chart": TileEdges.province_seams(null, everywhere, UNIT).size(),
		"the walk with no chart": TileEdges.seams(null, everywhere, Callable(), TileEdges.Look.COAST, UNIT).size(),
		"the walk with no region reading": TileEdges.seams(
			model, everywhere, Callable(), TileEdges.Look.OUTSIDE, UNIT
		).size(),
		"the walk with no tile reading": TileEdges.seams(
			model, Callable(), model.province_at, TileEdges.Look.COAST, UNIT
		).size(),
		"an inset that has not measured its tile": TileEdges.province_seams(model, everywhere, 0.0).size(),
		"a chart that was never generated": TileEdges.sea_seams(empty_chart, everywhere, UNIT).size(),
	}
	assert_eq(empty_chart.width * empty_chart.height, 0, "an empty chart has no tiles")
	for case: String in inks.keys():
		assert_eq(int(inks[case]), 0, "%s inks nothing" % case)


## Every slot of the wheel, so the hill, the wall, the coast and the step that
## leaves the chart all ink on the side they belong to.
func test_each_edge_step_points_at_its_neighbour() -> void:
	assert_eq(TileEdges.step(TileEdges.Edge.TOP), Vector2i(0, -1))
	assert_eq(TileEdges.step(TileEdges.Edge.RIGHT), Vector2i(1, 0))
	assert_eq(TileEdges.step(TileEdges.Edge.BOTTOM), Vector2i(0, 1))
	assert_eq(TileEdges.step(TileEdges.Edge.LEFT), Vector2i(-1, 0))
	assert_eq(TileEdges.ALL_EDGES.size(), 4)


## A sea zone inks its own ring: every zone's border draws, and none of them is
## drawn twice for the same tile.
func test_a_sea_zone_inks_its_own_ring() -> void:
	var model: MapModel = _charted_after_first_region()
	var zone: SeaZoneState = model.sea_zones[0]
	var mine := func(x: int, y: int) -> bool:
		return model.sea_zone_at(x, y) == zone.id
	var seams: Array[PackedVector2Array] = TileEdges.sea_seams(model, mine, UNIT)
	assert_gt(seams.size(), 3, "a sea zone inks a closed ring")
	var seen: Dictionary = {}
	for path: PackedVector2Array in seams:
		assert_eq(path.size(), 2)
		var key: String = str(path)
		assert_false(seen.has(key), "a zone seam is inked once")
		seen[key] = true
