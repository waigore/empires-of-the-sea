class_name BattlePlateAssets
extends RefCounted
## Shared plate art paths and the texture shelf the ground, wall and figure
## painters read. One cache so a panorama, a wall segment and a gun never reload
## the same path twice (REQ-P3-01).

## Fraction of plate height where the armies stand on open ground.
const GROUND: float = 0.74

## Each panorama is painted with its horizon at a known fraction of its height;
## the plate is cover-fitted and anchored on that line so the armies stand on
## the painted field at any aspect (the overlay is wide, the simulator tall).
const PLATES: Dictionary = {
	"open": {"path": "res://assets/art/battle/ground_open.jpg", "horizon": 0.445},
	"hill": {"path": "res://assets/art/battle/ground_hill.jpg", "horizon": 0.600},
	"woods": {"path": "res://assets/art/battle/ground_woods.jpg", "horizon": 0.520},
	"town": {"path": "res://assets/art/battle/ground_town.jpg", "horizon": 0.510},
	"marsh": {"path": "res://assets/art/battle/ground_marsh.jpg", "horizon": 0.550},
}
const WALLS: Array[String] = [
	"",
	"res://assets/art/battle/wall_wood.png",
	"res://assets/art/battle/wall_stone.png",
	"res://assets/art/battle/wall_modern.png",
]
const SOLDIER: String = "res://assets/art/battle/soldier.png"
const CANNON: String = "res://assets/art/battle/cannon.png"
const HORSE: String = "res://assets/art/battle/horse.png"
const RUBBLE: String = "res://assets/art/battle/rubble.png"

static var _cache: Dictionary = {}


static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Texture2D
	var tex: Texture2D = load(path) as Texture2D
	_cache[path] = tex
	return tex
