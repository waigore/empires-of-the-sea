class_name FactionHeraldry
extends RefCounted
## One coat of arms per court: a field in the crown's own heraldic colour, a
## charged shield and a bordure that reads the court's rank (wiki: diplomacy
## § The court sheet; DR-20261118-30). Every other entity type already carries
## its own medallion — a regiment, a hull, a crew, a good, a study, a worker
## tier — while the court, the thing the whole game is about, read as a colour
## wash and a name. The chart's wash and the arms read the same colour, so a
## province on the map and its court on a sheet never disagree (REQ-P1-08,
## REQ-P2-03).
##
## Pure data: no nodes, no drawing, no rules (REQ-P3-03). The shield is drawn by
## [FactionCrest] from [FactionCrestMarks]; the catalog owns the colours and the
## names.

## The charges a shield may bear, in the order the catalog deals them out. Kept
## heavy and simple so a 22-point shield still reads at a glance (REQ-P1-07).
const CHARGES: Array[String] = [
	"cross", "saltire", "chevron", "pale", "fess", "bend",
	"tower", "anchor", "sun", "star", "fleur", "tree",
	"crescent", "lozenge", "wave", "arrow", "roundel", "bars",
]

## How a second tincture divides the field. The charges are dealt in one pass
## over the catalog, so a court past the last charge is told apart by its
## division instead of repeating the shield above it.
const DIVISIONS: Array[String] = ["plain", "quarterly", "per_bend"]

## What a court's rank paints around its shield: a Great Power wears a bright
## bordure, a Minor Nation a dim one, and a Tribe none at all — the heraldic
## ladder the court sheet already sorts by (wiki: factions § Types).
const BORDURE_GREAT_POWER: Color = Palette.GOLD
const BORDURE_MINOR: Color = Palette.GOLD_DIM
const BORDURE_TRIBE: Color = Palette.INK_SOFT

static var _positions: Dictionary = {}


## A court's arms: the field, the charge, the tincture and the bordure it is
## drawn in. An unknown court (no catalog row) reads empty, so a caller never
## paints arms for a faction the game does not know.
static func blazon(faction_id: int) -> Dictionary:
	var position: int = position_of(faction_id)
	if position < 0:
		return {}
	var field: Color = FactionCatalog.color_of(faction_id)
	var charge: String = CHARGES[position % CHARGES.size()]
	var division: String = DIVISIONS[
		(position / CHARGES.size()) % DIVISIONS.size()
	]
	return {
		"faction": faction_id,
		"name": FactionCatalog.name_of(faction_id),
		"field": field,
		"charge": charge,
		"division": division,
		"tincture": tincture_on(field),
		"party": party_of(field),
		"bordure": bordure_for(FactionCatalog.type_of(faction_id)),
	}


## The court's place in the shared catalog, `-1` when the catalog has no row
## for it. Read once and kept, so a list of twenty courts costs one walk.
static func position_of(faction_id: int) -> int:
	if _positions.is_empty():
		var index: int = 0
		for faction: Dictionary in FactionCatalog.all():
			_positions[int(faction["id"])] = index
			index += 1
	return int(_positions.get(faction_id, -1))


## The brightness a field must fall under to carry a gold charge: above it the
## field is a metal, and a metal takes a colour (the sheet's ink) instead.
const METAL_LINE: float = 0.45


## The ink a charge is drawn in on a field, by the rule of tincture: a metal (the
## pale gold) over a colour, a colour (the sheet's ink) over a metal. A light
## field takes ink — except a cool or green one, where gold still reads and ink
## would sink into it (REQ-P1-07).
static func tincture_on(field: Color) -> Color:
	if luminance(field) < METAL_LINE:
		return Palette.GOLD_PALE
	return Palette.INK if field.r > field.b else Palette.GOLD_PALE


## The second colour a divided field is cut with: the field pulled toward its
## own metal, so the division parts a shield without breaking the one colour a
## court owns.
static func party_of(field: Color) -> Color:
	var metal: Color = Palette.GOLD_PALE if luminance(field) <= 0.52 else Palette.INK
	return field.lerp(metal, 0.42)


## The colour a rank wears around its shield.
static func bordure_for(type: int) -> Color:
	match type:
		FactionCatalog.Type.GREAT_POWER:
			return BORDURE_GREAT_POWER
		FactionCatalog.Type.MINOR_NATION:
			return BORDURE_MINOR
		FactionCatalog.Type.TRIBE:
			return BORDURE_TRIBE
	return Palette.INK_LINE


## How bright a colour reads, in the 0..1 range every contrast choice is made
## against (sRGB weights: the eye is greenest).
static func luminance(color: Color) -> float:
	return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
