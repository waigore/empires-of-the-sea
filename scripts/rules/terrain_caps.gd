class_name TerrainCaps
extends RefCounted
## Terrain hard caps on extraction (wiki: extraction-and-improvements
## § Terrain extraction hard caps). A hard cap is applied after the tech cap and
## clamps, never raises, so the effective cap is min(tech-allowed, terrain).

## Scrub forest timber is the published hard cap; no other terrain caps a
## resource in the current ruleset.
const HARD_CAPS: Dictionary = {
	MapModel.Terrain.SCRUB_FOREST: {"timber": 1},
}


## Hard level for this terrain and commodity; MAX_IMPROVEMENT when none applies.
static func hard_cap(terrain: int, commodity: String) -> int:
	var row: Dictionary = HARD_CAPS.get(terrain, {})
	return int(row.get(commodity, LandWorks.MAX_IMPROVEMENT))


## Tech cap clamped by the terrain hard cap for extraction and build checks.
static func extraction_cap(terrain: int, commodity: String, tech_cap: int) -> int:
	return mini(maxi(tech_cap, 0), hard_cap(terrain, commodity))


static func limits(terrain: int, commodity: String, level: int) -> bool:
	return level > hard_cap(terrain, commodity)
