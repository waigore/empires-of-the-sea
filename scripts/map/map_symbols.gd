class_name MapSymbols
extends RefCounted
## Painted map stamps: the trees, peaks, hamlets, anchor and hull that dress the
## chart (assets/art/map, recipe in tools/art/map-symbols.md).
##
## `MapCanvas` asks this class to draw a planned glyph first and only falls back
## to the ink vectors in `MapGlyphs` when a texture is missing, so a headless
## build without imported art still draws a complete map. Symbols are generated
## as cut-outs on magenta, keyed to alpha and downsampled once; they are drawn
## from the mip-mapped source, never re-scaled on the CPU.

const DIR: String = "res://assets/art/map/"
## One or more painted variants per planned glyph kind; a variant is chosen
## from the stamp position so a forest never repeats one sprite.
const STAMPS: Dictionary = {
	"tree": ["tree.png", "tree_b.png", "tree_c.png"],
	"scrub": ["conifer.png", "tree_b.png"],
	"conifer": ["conifer.png", "tree_b.png"],
	"mountain": ["mountain.png", "mountain_b.png", "mountain_c.png"],
	"hill": ["hill.png", "hill_b.png"],
	"dune": ["dune.png"],
	"field": ["field.png"],
	"reed": ["reed.png"],
	"grass": ["grass.png"],
	"town": ["town.png"],
	"capital": ["capital.png"],
	"port": ["port.png"],
	"ship": ["ship.png"],
}
## Marks that are scenery rather than a place: they take a small jitter in turn
## and a soft shadow, so a scattered province never reads as one stamp repeated.
const SCENERY: Array[String] = [
	"tree", "scrub", "conifer", "mountain", "hill", "dune", "field", "reed", "grass",
]
## Ink of the pennant a capital flies, so ownership reads on the chart.
const BANNER_INK: Color = Color(0.149, 0.118, 0.082, 0.78)
## How far a stamp is dimmed at most, by position hash, toward the parchment.
const TONE_SPREAD: float = 0.14

static var _cache: Dictionary = {}


## The painted stamp for a glyph kind (or null when the art is not imported).
static func texture(kind: String, at: Vector2 = Vector2.ZERO) -> Texture2D:
	var files: Array = STAMPS.get(kind, [])
	if files.is_empty():
		return null
	var file: String = String(files[_variant(at, files.size())])
	var path: String = DIR + file
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path] as Texture2D


## Draws one planned glyph. Returns false when no painted stamp exists for its
## kind, so the caller can keep the vector fallback.
static func stamp(canvas: CanvasItem, glyph: Dictionary) -> bool:
	var kind: String = String(glyph.get("kind", ""))
	var at: Vector2 = glyph.get("position", Vector2.ZERO)
	var size: float = float(glyph.get("size", 0.0))
	if size <= 0.0:
		return false
	var tex: Texture2D = texture(kind, at)
	if tex == null:
		return false
	var flip: float = -1.0 if bool(glyph.get("flip", false)) else 1.0
	var scenery: bool = SCENERY.has(kind)
	var turn: float = _detail(at, 3) * 0.16 - 0.08 if scenery else 0.0
	var tone: float = 1.0 - _detail(at, 5) * TONE_SPREAD
	var rect := Rect2(-size * 0.5, -size * 0.5, size, size)
	canvas.draw_set_transform(at, turn, Vector2(flip, 1.0))
	# A soft silhouette shadow, offset down-right like the ink shadows the atlas
	# uses, so the stamp sits on the wash instead of hovering over it. A place
	# takes a heavier one: its pale walls need the separation a grove does not.
	var shade: float = 0.11 if scenery else 0.22
	canvas.draw_texture_rect(
		tex, Rect2(rect.position + Vector2(size * 0.05, size * 0.07), rect.size),
		false, Color(0.10, 0.07, 0.03, shade)
	)
	canvas.draw_texture_rect(tex, rect, false, Color(tone, tone * 0.985, tone * 0.94, 0.96))
	if kind == "capital":
		_banner(canvas, size, int(glyph.get("owner", MapModel.NO_ID)))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## A pennant on the keep: the one mark that says whose crown the citadel serves
## (the star the ink fallback draws plays the same part).
static func _banner(canvas: CanvasItem, size: float, owner: int) -> void:
	var foot := Vector2(size * 0.34, -size * 0.24)
	var top: Vector2 = foot + Vector2(0.0, -size * 0.42)
	canvas.draw_line(foot, top, BANNER_INK, 1.3, true)
	if owner == MapModel.NO_ID:
		return
	var flag: Color = Palette.faction_color(owner)
	flag.a = 0.95
	canvas.draw_colored_polygon(
		PackedVector2Array([top, top + Vector2(size * 0.30, size * 0.09), top + Vector2(0.0, size * 0.19)]),
		flag
	)
	canvas.draw_polyline(
		PackedVector2Array([top, top + Vector2(size * 0.30, size * 0.09), top + Vector2(0.0, size * 0.19)]),
		BANNER_INK, 0.8, true
	)


static func _variant(at: Vector2, count: int) -> int:
	if count <= 1:
		return 0
	return int(MapGlyphs.hash01(int(at.x), int(at.y)) * float(count)) % count


## One stable 0..1 value per stamp position and salt: drives variant choice,
## tone and the tiny turn, without a generator that would desync the plan.
static func _detail(at: Vector2, salt: int) -> float:
	return MapGlyphs.hash01(int(at.x) + salt * 31, int(at.y) + salt * 17)
