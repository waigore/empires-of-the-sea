class_name CommodityIcons
extends RefCounted
## One brass medallion per commodity (assets/art/goods), cut in the same family
## as the shell and tech plates: thick beveled ring, dark espresso field,
## top-left light. Every screen that names a good shows its own plate, so
## grain, wool and timber stop sharing a generic pictogram (REQ-P1-02;
## tools/art/goods-medallions.md).

const DIR: String = "res://assets/art/goods/"
## A ledger row is 38 px high; a 24 px medallion reads beside a 14 pt label.
const ROW_SIZE: int = 24
## Estate lines sit tighter, under a 14 pt title.
const LINE_SIZE: int = 18

static var _cache: Dictionary = {}


## The medallion for a commodity, or null when the catalog has no plate for it.
static func texture(commodity_id: String) -> Texture2D:
	if not CommodityCatalog.known(commodity_id):
		return null
	var path: String = DIR + commodity_id + ".png"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## A medallion sized for a row, or an empty gap of the same width when the plate
## is missing: one absent file leaves a hole instead of shifting the columns
## (REQ-P3-02).
static func badge(commodity_id: String, size: int = ROW_SIZE) -> Control:
	var art: Texture2D = texture(commodity_id)
	if art == null:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(size, size)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return gap
	var out := TextureRect.new()
	out.texture = art
	out.custom_minimum_size = Vector2(size, size)
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	out.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


## A fixed-width name cell: the medallion then the good's label, so every row in
## a column starts its text at the same x and the header stays aligned above it.
static func cell(
	commodity_id: String,
	width: float,
	font_size: int = 14,
	ink: Color = Palette.TEXT
) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(badge(commodity_id, ROW_SIZE))
	var text := UiRowBuilder.label(CommodityCatalog.label(commodity_id), font_size, ink)
	text.clip_text = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	return box
