class_name RegimentMiniatures
extends RefCounted
## The battle plate's per-type miniatures: one painted sprite per land regiment
## type (see tools/art/regiment_miniatures.py), the formation slots they stand
## in, and the caption that names the composition on the field. Pure painters
## and pure data, so [QuickBattleField] stays a thin view (REQ-P3-01) and no
## rule outcome is decided here (REQ-P2-03).

const DIR: String = "res://assets/art/battle/regiments/"
## A standing foot figure's sprite height in pixels. Every miniature is painted
## on this one scale, so a gun draws lower than a man and a rider taller; the
## view only names the height of a foot soldier.
const FIGURE_HEIGHT: float = 200.0
const FALLBACK: String = "res://assets/art/battle/soldier.png"
## A type-less record (an old report, or a plate fixture) draws the musketeer.
const FALLBACK_ASPECT: float = 0.48
## Types named on the plate before the caption elides the rest.
const MAX_NAMED: int = 6

static var _cache: Dictionary = {}


static func art_path(type_id: String) -> String:
	return DIR + RegimentCatalog.normalize(type_id) + ".png"


static func has_art(type_id: String) -> bool:
	return ResourceLoader.exists(art_path(type_id))


## The type's miniature, or the shared musketeer when a type has no art yet.
static func texture(type_id: String) -> Texture2D:
	var path: String = art_path(type_id)
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	var tex: Texture2D = _cache[path] as Texture2D
	if tex != null:
		return tex
	if not _cache.has(FALLBACK):
		_cache[FALLBACK] = load(FALLBACK) if ResourceLoader.exists(FALLBACK) else null
	return _cache[FALLBACK] as Texture2D


## How wide the type's miniature is when it stands `soldier_h` tall.
static func width(type_id: String, soldier_h: float) -> float:
	var aspect: float = FALLBACK_ASPECT
	var tex: Texture2D = texture(type_id)
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	return soldier_h * aspect


## The formation as the plate stands it: one slot per shown regiment, grouped
## by type so the line reads in blocks and each block answers the caption's
## left-to-right order. Stable within a round and between rounds, so a
## regiment never jumps places as its neighbours fall.
static func slots(entries: Array, count: int, limit: int) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	for index in clampi(count, 0, limit):
		var entry: Dictionary = {}
		if index < entries.size() and typeof(entries[index]) == TYPE_DICTIONARY:
			entry = entries[index] as Dictionary
		typed.append({
			"type": String(entry.get("type", "")),
			"entry": entry,
			"record": index,
		})
	typed.sort_custom(_before)
	return typed


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var left: String = _sort_name(String(a["type"]))
	var right: String = _sort_name(String(b["type"]))
	if left == right:
		return int(a["record"]) < int(b["record"])
	return left < right


## An unnamed slot sorts first, so the caption's named blocks stay contiguous.
static func _sort_name(type_id: String) -> String:
	return "" if type_id.is_empty() else RegimentCatalog.display_name(type_id)


## Uniform gap for the line: guns and riders take more room than a file of
## musketeers, so the widest miniature sets the step.
static func spacing(slots: Array[Dictionary], soldier_h: float) -> float:
	var widest: float = 0.0
	for slot: Dictionary in slots:
		widest = maxf(widest, width(String(slot["type"]), 1.0))
	return soldier_h * clampf(widest * 0.70, 0.66, 1.30)


## The types the line shows, each with the regiments standing in it.
static func counts(slots: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for slot: Dictionary in slots:
		var type_id: String = String(slot["type"])
		if type_id.is_empty():
			continue
		if groups.is_empty() or String(groups[groups.size() - 1]["type"]) != type_id:
			groups.append({"type": type_id, "count": 0})
		groups[groups.size() - 1]["count"] = int(groups[groups.size() - 1]["count"]) + 1
	return groups


## "2 Pikemen · Musketeers · Culverin" — the line's composition, in the order
## the blocks stand. Empty when the record names no type at all.
static func caption(slots: Array[Dictionary], max_named: int = MAX_NAMED) -> String:
	var groups: Array[Dictionary] = counts(slots)
	var parts: Array[String] = []
	for index in mini(groups.size(), max_named):
		parts.append(_group_text(groups[index]))
	if groups.size() > max_named:
		parts.append("…")
	return " · ".join(PackedStringArray(parts))


static func _group_text(group: Dictionary) -> String:
	var name: String = RegimentCatalog.display_name(String(group["type"]))
	var count: int = int(group["count"])
	return name if count <= 1 else "%d %s" % [count, name]


## Draws a side's composition under its line, in the side's colours. Two lines
## at most: a long muster wraps rather than loses its types, and whatever is
## still over the room is elided, so a narrow phone plate never runs into the
## other side's caption. The miniatures carry the full identity regardless.
static func draw_caption(
	canvas: CanvasItem, text: String, centre: Vector2, max_width: float, colour: Color,
	font_size: int, max_lines: int = 2
) -> void:
	if text.is_empty() or max_width <= 8.0:
		return
	var font: Font = UiTheme.serif()
	var rows: Array[String] = caption_rows(text, max_width, font, font_size, max_lines)
	for index in rows.size():
		var span: float = _measure(rows[index], font, font_size)
		var y: float = centre.y + float(index) * (font_size + 3)
		var pos := Vector2(centre.x - span * 0.5, y)
		## A nameplate, not floating letters: the ground behind a caption can be
		## grass, haze or a sunlit wall, and a phone is read outdoors.
		canvas.draw_rect(
			Rect2(pos.x - 4.0, y - float(font_size) * 0.95, span + 8.0,
				float(font_size) * 1.30),
			Color(0.07, 0.06, 0.05, 0.66)
		)
		canvas.draw_rect(
			Rect2(pos.x - 4.0, y - float(font_size) * 0.95, span + 8.0, 1.0),
			Color(colour.r, colour.g, colour.b, 0.85)
		)
		canvas.draw_string_outline(
			font, pos, rows[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3,
			Color(0.05, 0.04, 0.03, 0.9)
		)
		canvas.draw_string(
			font, pos, rows[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			colour.lightened(0.55)
		)


## The caption laid into at most `max_lines` rows of `max_width`. Whole type
## groups stay together; a row that runs out of room ends in an ellipsis.
static func caption_rows(
	text: String, max_width: float, font: Font, font_size: int, max_lines: int = 2
) -> Array[String]:
	var rows: Array[String] = []
	var kept: Array[String] = []
	var groups: PackedStringArray = text.split(" · ")
	for raw: String in groups:
		var candidate: Array[String] = kept.duplicate()
		candidate.append(raw)
		if _measure(_join(candidate), font, font_size) <= max_width:
			kept = candidate
			continue
		if kept.is_empty():
			## One group is wider than the room: cut it and stop.
			rows.append(_ellipsis(raw, max_width, font, font_size))
			return rows
		rows.append(_join(kept))
		kept = [raw]
		if rows.size() >= max_lines:
			rows[rows.size() - 1] = _ellipsis(
				rows[rows.size() - 1], max_width, font, font_size
			)
			return rows
	if not kept.is_empty():
		rows.append(_join(kept))
	return rows


static func _join(parts: Array[String]) -> String:
	return " · ".join(PackedStringArray(parts))


## The caption cut down to the room it has: whole type groups are dropped from
## the end, then the last word, and an ellipsis marks the cut.
static func fit(text: String, max_width: float, font: Font, font_size: int) -> String:
	var rows: Array[String] = caption_rows(text, max_width, font, font_size, 1)
	return rows[0] if not rows.is_empty() else ""


static func _ellipsis(text: String, max_width: float, font: Font, font_size: int) -> String:
	var body: String = text
	while body.length() > 1 and _measure(body + "…", font, font_size) > max_width:
		body = body.substr(0, body.length() - 1)
	return body.strip_edges() + "…"


static func _measure(text: String, font: Font, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
