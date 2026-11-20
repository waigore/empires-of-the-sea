extends GdToolsTest
## Pure: the shared lens wash bake. Every coloured band a reading prints must sit
## on the map's soft tile lines instead of on a hard axis-aligned rectangle
## (issue #1156, REQ-P1-03).

const TILE: float = MapLens.TILE_SIZE
const WASH: float = 0.70
const VEIL: float = 0.62
const SLACK: float = 0.01
const BANDS: Array[String] = ["own", "war"]


## One read wavelength of the sway, so a test can watch an edge bow.
func test_a_reading_bakes_one_texture_over_its_runs() -> void:
	var bake: WashBake = _bake({"war": [Rect2(2.0, 3.0, 4.0, 1.0)]}, ["war"])
	assert_not_null(bake.texture, "the reading baked")
	# The bake carries one tile of margin on every side for the swayed edge.
	assert_almost_eq(bake.rect.position.x, 1.0 * TILE, SLACK)
	assert_almost_eq(bake.rect.size.x, 6.0 * TILE, SLACK)
	assert_almost_eq(bake.rect.size.y, 3.0 * TILE, SLACK)
	var image: Image = bake.texture.get_image()
	assert_eq(image.get_width(), 6 * WashBake.TEXELS)
	assert_eq(image.get_height(), 3 * WashBake.TEXELS)
	# A texel in the middle of the run wears the band's ink over the reading's
	# veil, folded into one translucent layer.
	var inside: Color = image.get_pixel(8, 6)
	assert_almost_eq(inside.a, WASH + VEIL * (1.0 - WASH), SLACK)
	assert_almost_eq(inside.r, _ink(_tint("war")).r, SLACK)
	assert_almost_eq(inside.g, _ink(_tint("war")).g, SLACK)
	# Outside the run — the margin, and the far corner — nothing is painted.
	assert_almost_eq(image.get_pixel(0, 0).a, 0.0, 0.02)


## The band lands on its own tiles: one tile of margin either side of the run
## stays bare, so a reading never paints the ground beside it.
func test_a_band_lands_on_its_own_tiles() -> void:
	var bake: WashBake = _bake({"war": [Rect2(2.0, 3.0, 4.0, 1.0)]}, ["war"])
	var image: Image = bake.texture.get_image()
	var row: int = 6
	assert_almost_eq(image.get_pixel(3, row).a, 0.0, 0.02, "the margin stays bare")
	assert_gt(image.get_pixel(4, row).a, 0.5, "the band starts on its first tile")
	assert_gt(image.get_pixel(19, row).a, 0.5, "the band reaches its last tile")
	assert_almost_eq(image.get_pixel(20, row).a, 0.0, 0.02, "the band stops there")


## A wash edge is no ruler line: the band's top bows with the chart's hand-inked
## tiles, so a coloured province does not read as a cut block.
func test_a_band_edge_bows_like_drawn_ink() -> void:
	var bake: WashBake = _bake({"own": [Rect2(0.0, 0.0, 14.0, 1.0)]}, ["own"])
	var image: Image = bake.texture.get_image()
	var top: int = 1
	var bottom: int = image.get_height() - 1
	var lowest: int = bottom
	var highest: int = top
	for column in range(WashBake.TEXELS, 14 * WashBake.TEXELS):
		var row: int = _first_inked(image, column, top, bottom)
		lowest = mini(lowest, row)
		highest = maxi(highest, row)
	assert_gt(highest, lowest, "the edge changes row along the run")


## Two bands side by side meet on one line: the bake never leaves a pale texel
## between them, so no seam runs through the reading.
func test_two_bands_meet_without_a_seam() -> void:
	var bake: WashBake = _bake(
		{"own": [Rect2(0.0, 0.0, 10.0, 1.0)], "war": [Rect2(0.0, 1.0, 10.0, 1.0)]}, BANDS
	)
	var image: Image = bake.texture.get_image()
	for column in range(WashBake.TEXELS, 10 * WashBake.TEXELS):
		var first: int = _first_inked(image, column, 0, image.get_height() - 1)
		var last: int = _last_inked(image, column, 0, image.get_height() - 1)
		for row in range(first, last):
			assert_gt(
				image.get_pixel(column, row).a, 0.0,
				"no bare texel between the bands at %d,%d" % [column, row]
			)


## Each band keeps its own ink: two neighbours never bake the same colour.
func test_each_band_keeps_its_own_ink() -> void:
	var bake: WashBake = _bake(
		{"own": [Rect2(0.0, 0.0, 8.0, 1.0)], "war": [Rect2(0.0, 1.0, 8.0, 1.0)]}, BANDS
	)
	var image: Image = bake.texture.get_image()
	var own: Color = image.get_pixel(6, 6)
	var war: Color = image.get_pixel(6, 12)
	assert_gt(absf(own.r - war.r) + absf(own.g - war.g) + absf(own.b - war.b), 0.1)


## An uncharted region bakes nothing at all, and drawing it stays a no-op.
func test_a_reading_with_no_runs_bakes_nothing() -> void:
	var bake: WashBake = _bake({}, BANDS)
	assert_null(bake.texture)


## The same chart bakes the very same texels, so a repaint after a border moves
## redraws the reading it drew before.
func test_the_same_reading_bakes_the_same_texels() -> void:
	var runs := {"own": [Rect2(0.0, 0.0, 9.0, 1.0), Rect2(1.0, 2.0, 5.0, 1.0)]}
	var first: WashBake = _bake(runs, ["own"])
	var second: WashBake = _bake(runs, ["own"])
	assert_eq(first.texture.get_image().get_data(), second.texture.get_image().get_data())


# --- helpers -----------------------------------------------------------------


func _bake(runs: Dictionary, bands: Array) -> WashBake:
	return WashBake.of(runs, bands, _tint, WASH, VEIL, TILE)


func _tint(band: String) -> Color:
	match band:
		"own":
			return Color(0.22, 0.36, 0.62)
		"war":
			return Color(0.66, 0.18, 0.16)
	return Color(0.5, 0.47, 0.39)


## The band's ink over the reading's veil: the one layer the bake stores.
func _ink(tint: Color) -> Color:
	var paper: Color = Palette.paper(1.0)
	var alpha: float = WASH + VEIL * (1.0 - WASH)
	var under: float = VEIL * (1.0 - WASH)
	return Color(
		(tint.r * WASH + paper.r * under) / alpha,
		(tint.g * WASH + paper.g * under) / alpha,
		(tint.b * WASH + paper.b * under) / alpha,
		alpha
	)


func _first_inked(image: Image, column: int, from: int, to: int) -> int:
	for row in range(from, to + 1):
		if image.get_pixel(column, row).a > 0.04:
			return row
	return to


func _last_inked(image: Image, column: int, from: int, to: int) -> int:
	for row in range(to, from - 1, -1):
		if image.get_pixel(column, row).a > 0.04:
			return row
	return from
