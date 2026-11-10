class_name ArmyBands
extends RefCounted
## Auto-resolve's ratio bands and outcome wording (wiki: combat § Auto-resolve
## ratio bands and loss fractions). Split from [ArmyCombat] so the battle chain
## stays inside the P3 size bar; the table is the single source of truth.

## A band's `min` is inclusive unless `exclusive` says otherwise; the wiki's
## `0.67 < ratio < 1.0` row must not claim ratio == 0.67, which belongs to the
## `ratio <= 0.67` defender-victory band.
const BANDS: Array[Dictionary] = [
	{"min": 1.5, "attacker": 0.15, "defender": 1.0},
	{"min": 1.0, "attacker": 0.3, "defender": 0.6},
	{"min": 0.67, "attacker": 0.5, "defender": 0.4, "exclusive": true},
	{"min": 0.0, "attacker": 1.0, "defender": 0.15},
]


static func for_ratio(ratio: float) -> Dictionary:
	for band: Dictionary in BANDS:
		var low: float = float(band["min"])
		if bool(band.get("exclusive", false)):
			if ratio > low:
				return band
		elif ratio >= low:
			return band
	return BANDS[BANDS.size() - 1]
