class_name WashBake
extends RefCounted
## One reading's colour wash, rasterised once into a texture (REQ-P1-03,
## REQ-P4-01). A lens hands its merged runs here instead of painting a rectangle
## per run: the bands are filled at sub-tile resolution with their edges swaying
## like the chart's hand-inked tiles, so the linear filter feathers every edge
## into the ground and a whole reading costs one draw call.
##
## The veil of paper that keeps a band's ink true is folded into the same texels,
## so the reading draws as one layer — no two runs ever overprint each other, and
## a boundary between bands can never show a seam.
##
## Pure drawing: it reads the projection's runs and nothing else, so a lens stays
## a view over its snapshot (REQ-P3-03).

## Bake texels per tile. Four puts the filter's feather near a fifth of a tile —
## soft on screen and still crisp at close zoom.
const TEXELS: int = 4
## A band edge sways this share of a tile, so a wash never cuts a dead-straight
## angle across the chart's curved ground.
const SWAY: float = 0.18

var texture: ImageTexture = null
## The world rectangle the bake covers, one tile wide of its runs for the sway.
var rect: Rect2 = Rect2()


## Bakes every run of one reading. `tint_for` names a band's ink; the reading's
## veil is folded in, so `draw` needs one call.
static func of(
	runs: Dictionary,
	bands: Array,
	tint_for: Callable,
	wash_alpha: float,
	veil_alpha: float,
	tile_size: float
) -> WashBake:
	var bake := WashBake.new()
	var bounds: Rect2 = _bounds(runs, bands)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or tile_size <= 0.0:
		return bake
	bake.rect = Rect2(bounds.position * tile_size, bounds.size * tile_size)
	var texel: float = tile_size / float(TEXELS)
	var image: Image = Image.create(
		int(bounds.size.x) * TEXELS, int(bounds.size.y) * TEXELS, false,
		Image.FORMAT_RGBA8
	)
	var paper: Color = Palette.paper(1.0)
	image.fill(Color(paper.r, paper.g, paper.b, 0.0))
	for band: String in bands:
		var ink: Color = _ink(tint_for.call(band), wash_alpha, veil_alpha)
		for raw: Variant in runs.get(band, []):
			_fill(image, raw, bounds, tile_size, texel, ink)
	bake.texture = ImageTexture.create_from_image(image)
	return bake


## Paints the reading: the chart's whole wash in one translucent draw.
func draw(canvas: CanvasItem, reveal: float) -> void:
	if texture == null:
		return
	canvas.draw_texture_rect(texture, rect, false, Color(1.0, 1.0, 1.0, reveal))


## Fills one run a tile column at a time, merging neighbouring columns that share
## a top and a bottom line so a reading bakes in a few hundred fills. Each top and
## bottom rides the run's own tile line, and the sway is keyed by the tile's place
## on the chart, so the run above and the run below draw the very same curve
## between them (REQ-P1-03).
static func _fill(
	image: Image,
	run: Rect2,
	bounds: Rect2,
	tile_size: float,
	texel: float,
	ink: Color
) -> void:
	var amplitude: float = tile_size * SWAY
	var top: float = run.position.y * tile_size
	var bottom: float = run.end.y * tile_size
	var origin: Vector2 = bounds.position * tile_size
	var first: int = maxi(
		int(round((run.position.x * tile_size - origin.x) / texel)), 0
	)
	var last: int = mini(
		int(round((run.end.x * tile_size - origin.x) / texel)), image.get_width()
	)
	var span_start: int = first
	var span_top: int = -1
	var span_bottom: int = -1
	var column: int = first
	while column < last:
		var along: float = origin.x + float(column) * texel
		var row_top: int = clampi(int(round(
			(top + _sway(along, top, amplitude) - origin.y) / texel
		)), 0, image.get_height() - 1)
		var row_bottom: int = clampi(int(round(
			(bottom + _sway(along, bottom, amplitude) - origin.y) / texel
		)), row_top + 1, image.get_height())
		if row_top != span_top or row_bottom != span_bottom:
			if span_top >= 0:
				image.fill_rect(
					Rect2i(
						span_start, span_top, column - span_start,
						span_bottom - span_top
					),
					ink
				)
			span_start = column
			span_top = row_top
			span_bottom = row_bottom
		column += TEXELS
	if span_top >= 0:
		image.fill_rect(
			Rect2i(span_start, span_top, last - span_start, span_bottom - span_top),
			ink
		)


## The texel rectangle every run of the reading occupies, one tile of margin so a
## swayed edge never leaves the bake.
static func _bounds(runs: Dictionary, bands: Array) -> Rect2:
	var box := Rect2()
	var seen: bool = false
	for band: String in bands:
		for raw: Variant in runs.get(band, []):
			var run: Rect2 = raw
			if run.size.x <= 0.0 or run.size.y <= 0.0:
				continue
			box = run if not seen else box.merge(run)
			seen = true
	if not seen:
		return Rect2()
	return box.grow(1.0)


## The band's ink over the reading's veil, folded into one translucent colour:
## the veil first, then the tint, so drawing the reading once reads the same as
## the two layers it replaces.
static func _ink(tint: Color, wash_alpha: float, veil_alpha: float) -> Color:
	var paper: Color = Palette.paper(1.0)
	var alpha: float = wash_alpha + veil_alpha * (1.0 - wash_alpha)
	if alpha <= 0.0:
		return Color(tint.r, tint.g, tint.b, 0.0)
	var under: float = veil_alpha * (1.0 - wash_alpha)
	return Color(
		(tint.r * wash_alpha + paper.r * under) / alpha,
		(tint.g * wash_alpha + paper.g * under) / alpha,
		(tint.b * wash_alpha + paper.b * under) / alpha,
		alpha
	)


## The ink sway of one edge at `along`. Two frequencies, keyed by the edge's own
## place on the chart, so the line is stable across repaints.
static func _sway(along: float, edge: float, amplitude: float) -> float:
	return (
		sin(along * 0.043 + edge * 0.31) * 0.62
		+ sin(along * 0.17 + edge * 0.77) * 0.38
	) * amplitude
