class_name MapGrove
extends RefCounted
## A stand of woods stands as a grove, not as one speck per tile.
##
## `MapCanvasMarks` (via the plan) used to lay two independent hash-scattered
## stamps on every wooded tile, so a forest read as loose trees dropped at
## random on the chart with nothing tying one tile's canopy to the next (issue
## #1007: woods look random). This module lays a tile's stamps as one small
## stand: a crown tree at the tile's middle with smaller companions set around
## it, the ring spun and sized by the tile's own hash so no two groves repeat,
## and every spot kept inside `REACH` of the tile centre so a grove never spills
## onto the ground of the tile beside it. A tile walled by the same woodland on
## all four sides carries one companion more than a tree standing alone, so a
## block thickens inland and thins at its edge — the shape a wood has on the
## ground.
##
## Pure and deterministic (`REQ-P3-03`): the plan can be built headless, and the
## same chart always lays the same groves.

## How far a spot may sit from the tile's centre, in tiles. Half a tile is where
## a neighbour's canopy begins, so this keeps each grove on its own ground.
const REACH: float = 0.30
## The crown tree's share of the tile: the tallest stamp is a little under a
## tile wide, which is what reads as a canopy at play zoom.
const CROWN_SCALE_MIN: float = 0.80
const CROWN_SCALE_SPAN: float = 0.16
## A companion's share of the tile: undergrowth and the next tree over.
const FRINGE_SCALE_MIN: float = 0.38
const FRINGE_SCALE_SPAN: float = 0.16
## The ring is squashed vertically so a stand reads as ground seen at an angle,
## the same way the atlas draws its hills.
const RING_SQUASH: float = 0.74


## The stamps one wooded tile lays. `dense` is true when the tile is walled by
## the same woodland on all four sides (`MapGrove.walled`).
static func stamps(kind: String, x: int, y: int, dense: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({
		"kind": kind,
		"dx": (MapGlyphs.hash01(x + 41, y + 3) - 0.5) * REACH * 0.5,
		"dy": (MapGlyphs.hash01(x + 11, y + 67) - 0.5) * REACH * 0.5,
		"scale": CROWN_SCALE_MIN + MapGlyphs.hash01(x + 5, y + 9) * CROWN_SCALE_SPAN,
		"flip": MapGlyphs.hash01(x + 13, y + 3) > 0.5,
	})
	var count: int = 3 if dense else 2
	for i in range(1, count):
		out.append(_companion(kind, x, y, i, count))
	return out


## One stamp of the ring around the crown tree. The ring is spun by the tile's
## own hash, so two groves never stand their companions in the same order.
static func _companion(kind: String, x: int, y: int, index: int, count: int) -> Dictionary:
	var spin: float = MapGlyphs.hash01(x + 91, y + 17) * TAU
	var angle: float = spin + TAU * float(index) / float(count)
	return {
		"kind": kind,
		"dx": cos(angle) * REACH,
		"dy": sin(angle) * REACH * RING_SQUASH,
		"scale": FRINGE_SCALE_MIN + MapGlyphs.hash01(x + 61 + index * 7, y + 29) * FRINGE_SCALE_SPAN,
		"flip": MapGlyphs.hash01(x + 17 + index * 3, y + 7) > 0.5,
	}


## The marks a high-ground tile lays: `least`..`most` peaks or humps spun around
## the tile's own centre, each inside `REACH`, so a ridge reads as one landform
## and never spills onto the ground of the tile beside it (issue #1007). Hill and
## mountain stamps take their own hash salts, so a ridge never mirrors the grove
## standing next to it.
static func cluster(
	kind: String, x: int, y: int, least: int, most: int, size_lo: float, size_hi: float
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spin: float = MapGlyphs.hash01(x + 71, y + 53) * TAU
	var count: int = clampi(
		least + int(MapGlyphs.hash01(x + 5, y + 9) * float(most - least + 1)), least, most
	)
	for i in count:
		var angle: float = spin + TAU * float(i) / float(count)
		var reach: float = REACH * (0.55 + MapGlyphs.hash01(x + i * 7, y + i * 13) * 0.45)
		out.append({
			"kind": kind,
			"dx": cos(angle) * reach,
			"dy": sin(angle) * reach * RING_SQUASH,
			"scale": size_lo + MapGlyphs.hash01(x + i * 11, y + i * 5) * (size_hi - size_lo),
			"flip": MapGlyphs.hash01(x + i, y + i * 3) > 0.5,
		})
	return out


## Whether a tile is walled by its own woodland: the same terrain on all four
## sides. A wood's edge thins because its last trees stand in the open.
static func walled(p_model: MapModel, x: int, y: int) -> bool:
	var terrain: int = p_model.terrain_at(x, y)
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if p_model.terrain_at(x + step.x, y + step.y) != terrain:
			return false
	return true
