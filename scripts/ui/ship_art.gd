class_name ShipArt
extends RefCounted
## Generated medallion art for the hull catalogue. One texture per ship type,
## cut on the same brass frame as the shell icons. Missing art returns null so
## the views can fall back to a plain disc (REQ-P4-04).

const DIR: String = "res://assets/art/ships/"

static var _cache: Dictionary = {}


## Painted hull medallion (128 px, transparent outside the round rim).
static func medallion(type_id: String) -> Texture2D:
	var path: String = DIR + ShipStats.normalize(type_id) + ".png"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]
