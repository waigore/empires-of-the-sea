class_name CivilianArt
extends RefCounted
## Generated medallion art for the civilian roster. One texture per type, plus a
## pixelized marker cut for the map. Missing art returns null so the views can
## fall back to the hand-drawn vector glyph (REQ-P4-04).

const DIR: String = "res://assets/art/civilians/"

static var _cache: Dictionary = {}


## Painted roster medallion (128 px, transparent outside the round rim).
static func medallion(type_id: String) -> Texture2D:
	return _texture(type_id, "")


static func _texture(type_id: String, suffix: String) -> Texture2D:
	var key: String = "%s%s" % [type_id, suffix]
	if _cache.has(key):
		return _cache[key]
	var path: String = "%s%s%s.png" % [DIR, type_id, suffix]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_cache[key] = texture
	return texture
