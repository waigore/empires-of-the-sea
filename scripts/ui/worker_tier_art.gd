class_name WorkerTierArt
extends RefCounted
## One medallion per worker tier, struck in the tier's own metal: wrought iron
## for peasants, copper for apprentices, blued steel for journeymen and gold for
## masters. The ring, field and lighting are the shell's, so the plate belongs to
## the same family as the commodity and civilian art while the rank still reads
## by colour alone (REQ-P1-08; tools/art/unit-medallions.md).

const DIR: String = "res://assets/art/workers/"
## Tier ids in WorkerPool.Tier order (PEASANT, APPRENTICE, JOURNEYMAN, MASTER).
const IDS: Array[String] = ["peasant", "apprentice", "journeyman", "master"]
## A desktop roster row is 38 px high, a phone row 44 px (REQ-P1-05).
const MARK_SIZE: int = 32
const MARK_COMPACT: int = 34

static var _cache: Dictionary = {}


## The art id of a tier, or "" outside the roster.
static func tier_id(tier: int) -> String:
	if tier < 0 or tier >= IDS.size():
		return ""
	return IDS[tier]


## The tier's plate, or null when the id is off the roster or the file is absent.
static func medallion(tier: int) -> Texture2D:
	var art_id: String = tier_id(tier)
	if art_id.is_empty():
		return null
	var path: String = DIR + art_id + ".png"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## The tier's plate at row size; an absent file leaves a gap of the same width so
## the row's columns never shift.
static func badge(tier: int, size: int = MARK_SIZE) -> UnitMedallion:
	return UnitMedallion.new(medallion(tier), float(size))
