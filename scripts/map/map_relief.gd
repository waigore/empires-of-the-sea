class_name MapRelief
extends RefCounted
## Bakes the land wash at sub-tile resolution (RES texels per tile).
##
## The map grid is one value per tile, and magnifying that with linear filtering
## turns every province into a 22 px colour smear with a half-tile soft coast.
## This class resamples the grid into a painted field instead: the shore is
## `MapCoastField`'s reading (signed distance plus the basin's reach), which
## gives a crisp beach, a shoal veil and a wet-sand line, while fbm noise breaks
## the flat terrain fills into painterly patches. The shader then owns everything
## finer than a bake texel (hillshade, engraved contours, paper tooth).
##
## Pure data and `Image` output: no nodes, so it bakes headless and in tests.

## Bake texels per tile. Six puts a texel at 3.7 world px, so even at the
## closest camera zoom one texel stays under ten screen pixels.
const RES: int = 6

## Sand inside the shore, in tiles. Wide enough to read as a beach at fit zoom.
const BEACH_SPAN: float = 0.58
## Pale shoal water outside the shore, in tiles.
const SHOAL_SPAN: float = 1.55
## A narrow basin's veil never spans more than this share of the deepest water
## within `MapCoastField.REACH`, so the veil stops short of the middle instead
## of flooding a gulf from shore to shore.
const NARROW_SHARE: float = 0.62
## The thinnest shelf a narrow channel keeps along its shore, in tiles.
const MIN_SHOAL_SPAN: float = 0.42

const SAND: Color = Color(0.890, 0.843, 0.678)
const SAND_WET: Color = Color(0.706, 0.639, 0.471)
## Shoal water on the chart, kept in the sea's own cool family: a shelf that is
## paler than the water but never as green as the grass it sits beside (#456).
const SHOAL: Color = Color(0.443, 0.612, 0.655)
const SHOAL_DEEP: Color = Color(0.298, 0.443, 0.506)
## Sounding lines: the darker aqua bars an atlas draws inside its shallows.
const SHOAL_RING: Color = Color(0.243, 0.373, 0.435)

## Terrain height fed to the hillshade, indexed by MapModel.Terrain.
const TERRAIN_HEIGHT: Array[float] = [0.0, 0.0, 0.20, 0.32, 0.60, 0.95, 0.26, 0.16, 0.24]
## How strongly each terrain takes the ridge noise, indexed by MapModel.Terrain.
const TERRAIN_ROUGH: Array[float] = [0.0, 0.0, 0.10, 0.16, 0.45, 1.00, 0.22, 0.12, 0.20]

var color: Image = null
var relief: Image = null
## White where the ground is land, transparent over water: the drop shadow.
var shadow: Image = null
var scale: int = RES
var width: int = 0
var height: int = 0
## The shore this bake paints from: one coastline reading, not a private copy
## (MapCoastField).
var coast: MapCoastField = null

var _model: MapModel = null
var _base: PackedColorArray = PackedColorArray()
var _hb: PackedFloat32Array = PackedFloat32Array()
var _rough: PackedFloat32Array = PackedFloat32Array()
var _drift: PackedByteArray = PackedByteArray()
## Broad tonal drift over several tiles, so a province is never one flat fill.
var _broad: PackedByteArray = PackedByteArray()
var _tooth: PackedByteArray = PackedByteArray()
var _ridge: PackedByteArray = PackedByteArray()

## Bilinear corner scratch for one tile's texel rows and columns. Allocated once
## per bake: a bake paints thousands of tiles and must not allocate per tile
## (REQ-P4-04).
var _x0s: PackedInt32Array = PackedInt32Array()
var _x1s: PackedInt32Array = PackedInt32Array()
var _fxs: PackedFloat32Array = PackedFloat32Array()
var _y0s: PackedInt32Array = PackedInt32Array()
var _y1s: PackedInt32Array = PackedInt32Array()
var _fys: PackedFloat32Array = PackedFloat32Array()


func build(model: MapModel, owner_tint: float) -> void:
	_model = model
	width = maxi(model.width * RES, 1)
	height = maxi(model.height * RES, 1)
	coast = MapCoastField.build(model)
	_collect(model, owner_tint)
	_noise_layers()
	_paint()


## The un-noised base colour of one tile: terrain washed toward its crown.
func tile_color(tile: Vector2i) -> Color:
	if _base.is_empty():
		return Color(0.0, 0.0, 0.0, 0.0)
	if tile.x < 0 or tile.y < 0 or tile.x >= _model.width or tile.y >= _model.height:
		return Color(0.0, 0.0, 0.0, 0.0)
	return _base[tile.y * _model.width + tile.x]


## Signed distance to the shore in tiles at a sub-tile position: the field's own
## reading, so the ink, the paint and callers never disagree about the coast.
func coast_at(tile: Vector2) -> float:
	if coast == null:
		return 0.0
	return coast.coast_at(tile)


## Per-tile paint: colour already washed toward the crown, plus the height and
## roughness the hillshade and the contours need. Water tiles keep alpha 0, so a
## bilinear read of the grid only ever pulls land colour inland.
func _collect(model: MapModel, owner_tint: float) -> void:
	var n: int = model.width * model.height
	_base.resize(n)
	_hb.resize(n)
	_rough.resize(n)
	for y in model.height:
		for x in model.width:
			var i: int = y * model.width + x
			var terrain: int = model.terrain[i]
			_hb[i] = TERRAIN_HEIGHT[terrain]
			_rough[i] = TERRAIN_ROUGH[terrain]
			if not model.is_land(x, y):
				_base[i] = Color(0.0, 0.0, 0.0, 0.0)
				continue
			var tint: Color = Palette.terrain_color(terrain)
			var owner: int = model.owner_at(x, y)
			if owner != MapModel.NO_ID:
				tint = tint.lerp(FactionCatalog.color_of(owner), owner_tint)
			_base[i] = Color(tint.r, tint.g, tint.b, 1.0)


func _noise_layers() -> void:
	_broad = _sample_noise(7, 1.0 / 700.0, 3, false)
	_drift = _sample_noise(5, 1.0 / 150.0, 3, false)
	_tooth = _sample_noise(23, 1.0 / 13.0, 2, false)
	_ridge = _sample_noise(41, 1.0 / 62.0, 3, true)


## One noise field baked to bytes by the engine, so the paint loop only ever
## indexes memory instead of calling into the noise object per texel.
func _sample_noise(
	seed_value: int, frequency: float, octaves: int, ridged: bool
) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	var image: Image = noise.get_image(width, height, false, false, true)
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()


## Resamples the tile grid texel by texel: coast band, beach, shoal and paint.
## Whole blocks of deep water are left fully transparent, which is most of an
## ocean map.
func _paint() -> void:
	var tw: int = _model.width
	var th: int = _model.height
	var bw: int = width
	var bh: int = height
	var px := PackedByteArray()
	var hx := PackedByteArray()
	var mx := PackedByteArray()
	px.resize(bw * bh * 4)
	hx.resize(bw * bh * 4)
	mx.resize(bw * bh * 4)
	var deep_at: float = -(SHOAL_SPAN + 1.1)
	_x0s.resize(RES)
	_x1s.resize(RES)
	_fxs.resize(RES)
	_y0s.resize(RES)
	_y1s.resize(RES)
	_fys.resize(RES)
	for ty in th:
		_axis(ty, th, _y0s, _y1s, _fys)
		for tx in tw:
			if coast.is_deep_water(tx, ty, deep_at):
				continue
			_paint_tile(tx, ty, px, hx, mx)
	color = Image.create_from_data(bw, bh, false, Image.FORMAT_RGBA8, px)
	relief = Image.create_from_data(bw, bh, false, Image.FORMAT_RGBA8, hx)
	shadow = Image.create_from_data(bw, bh, false, Image.FORMAT_RGBA8, mx)


## One coastal tile's texels: bilinear reads of the field, the terrain colour and
## the noise layers, written straight into the three baked images' bytes.
func _paint_tile(
	tx: int, ty: int, px: PackedByteArray, hx: PackedByteArray, mx: PackedByteArray
) -> void:
	var tw: int = _model.width
	var bw: int = width
	var sd: PackedFloat32Array = coast.sd
	var basin: PackedFloat32Array = coast.reach
	_axis(tx, tw, _x0s, _x1s, _fxs)
	for sy in RES:
		var fy: float = _fys[sy]
		var row_lo: int = _y0s[sy] * tw
		var row_hi: int = _y1s[sy] * tw
		var out_y: int = ty * RES + sy
		for sx in RES:
			var fx: float = _fxs[sx]
			var i00: int = row_lo + _x0s[sx]
			var i10: int = row_lo + _x1s[sx]
			var i01: int = row_hi + _x0s[sx]
			var i11: int = row_hi + _x1s[sx]
			var at: int = (out_y * bw + tx * RES + sx) * 4
			var w00: float = (1.0 - fx) * (1.0 - fy)
			var w10: float = fx * (1.0 - fy)
			var w01: float = (1.0 - fx) * fy
			var w11: float = fx * fy
			var c00: Color = _base[i00]
			var c10: Color = _base[i10]
			var c01: Color = _base[i01]
			var c11: Color = _base[i11]
			var a00: float = c00.a * w00
			var a10: float = c10.a * w10
			var a01: float = c01.a * w01
			var a11: float = c11.a * w11
			var drift: float = float(_drift[at]) / 255.0 - 0.5
			var broad: float = float(_broad[at]) / 255.0 - 0.5
			var tooth: float = float(_tooth[at]) / 255.0 - 0.5
			var shore: float = (
				sd[i00] * w00 + sd[i10] * w10 + sd[i01] * w01 + sd[i11] * w11
				+ drift * 0.30 + tooth * 0.10
			)
			var land: float = smoothstep(-0.055, 0.075, shore)
			var red: float = 0.0
			var green: float = 0.0
			var blue: float = 0.0
			var covered: float = a00 + a10 + a01 + a11
			if covered > 0.002:
				red = (c00.r * a00 + c10.r * a10 + c01.r * a01 + c11.r * a11) / covered
				green = (c00.g * a00 + c10.g * a10 + c01.g * a01 + c11.g * a11) / covered
				blue = (c00.b * a00 + c10.b * a10 + c01.b * a01 + c11.b * a11) / covered
			var tone: float = 1.0 + broad * 0.20 + drift * 0.075 + tooth * 0.045
			red *= tone * (1.0 + broad * 0.05)
			green *= tone
			blue *= tone * (1.0 - broad * 0.055)
			var sand: float = (
				clampf(smoothstep(BEACH_SPAN + drift * 0.34, 0.02, shore), 0.0, 1.0) * 0.92
			)
			red = lerpf(red, SAND.r, sand)
			green = lerpf(green, SAND.g, sand)
			blue = lerpf(blue, SAND.b, sand)
			var wet: float = clampf(smoothstep(0.20, -0.04, shore), 0.0, 1.0) * 0.55
			red = lerpf(red, SAND_WET.r, wet)
			green = lerpf(green, SAND_WET.g, wet)
			blue = lerpf(blue, SAND_WET.b, wet)
			# Basin-capped veil: narrow water keeps a thin shelf + open middle.
			var reach: float = (
				basin[i00] * w00 + basin[i10] * w10
				+ basin[i01] * w01 + basin[i11] * w11
			)
			var veil: float = clampf(reach * NARROW_SHARE, MIN_SHOAL_SPAN, SHOAL_SPAN)
			var shoal: float = smoothstep(-veil, -0.02, shore) * (0.34 + tooth * 0.26)
			var pale: float = clampf(
				smoothstep(-veil, -minf(0.75, veil * 0.5), shore), 0.0, 1.0
			)
			var water_r: float = lerpf(SHOAL_DEEP.r, SHOAL.r, pale)
			var water_g: float = lerpf(SHOAL_DEEP.g, SHOAL.g, pale)
			var water_b: float = lerpf(SHOAL_DEEP.b, SHOAL.b, pale)
			# Sounding rings fade where the veil is too narrow for a bar.
			var depth: float = -shore
			var band: float = absf(fposmod(depth / 0.52, 1.0) - 0.5)
			var ring: float = smoothstep(0.40, 0.50, band)
			ring *= clampf(1.0 - depth / (veil + 0.3), 0.0, 1.0)
			ring *= smoothstep(0.60, 1.10, veil) * 0.42
			water_r = lerpf(water_r, SHOAL_RING.r, ring)
			water_g = lerpf(water_g, SHOAL_RING.g, ring)
			water_b = lerpf(water_b, SHOAL_RING.b, ring)
			red = lerpf(water_r, red, land)
			green = lerpf(water_g, green, land)
			blue = lerpf(water_b, blue, land)
			var alpha: float = clampf(maxf(land, shoal * (1.0 - land) * 0.66), 0.0, 1.0)
			px[at] = int(clampf(red, 0.0, 1.0) * 255.0)
			px[at + 1] = int(clampf(green, 0.0, 1.0) * 255.0)
			px[at + 2] = int(clampf(blue, 0.0, 1.0) * 255.0)
			px[at + 3] = int(alpha * 255.0)
			var rough: float = (
				_rough[i00] * w00 + _rough[i10] * w10
				+ _rough[i01] * w01 + _rough[i11] * w11
			)
			var base_h: float = (
				_hb[i00] * w00 + _hb[i10] * w10 + _hb[i01] * w01 + _hb[i11] * w11
			)
			var ridge: float = float(_ridge[at]) / 255.0 - 0.5
			var height_at: float = base_h + ridge * 0.50 * rough + tooth * 0.05
			var shade: int = int(clampf(height_at, 0.0, 1.0) * 255.0)
			hx[at] = shade
			hx[at + 1] = shade
			hx[at + 2] = shade
			hx[at + 3] = 255
			mx[at] = 255
			mx[at + 1] = 255
			mx[at + 2] = 255
			mx[at + 3] = int(alpha * 255.0)


## Bilinear corner pair for one sub-texel column or row along an axis.
func _axis(
	at: int, count: int, lo: PackedInt32Array, hi: PackedInt32Array, frac: PackedFloat32Array
) -> void:
	for s in RES:
		var g: float = float(at) + (float(s) + 0.5) / float(RES) - 0.5
		var base: int = int(floor(g))
		frac[s] = clampf(g - float(base), 0.0, 1.0)
		lo[s] = clampi(base, 0, count - 1)
		hi[s] = clampi(base + 1, 0, count - 1)
