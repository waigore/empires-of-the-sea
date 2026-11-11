class_name ArmyBands
extends RefCounted
## Auto-resolve's ratio bands and outcome wording (wiki: combat § Auto-resolve
## ratio bands and loss fractions). Split from [ArmyCombat] so the battle chain
## stays inside the P3 size bar; the table is the single source of truth.

## A band's `min` is inclusive unless `exclusive` says otherwise; the wiki's
## `0.67 < ratio < 1.0` row must not claim ratio == 0.67, which belongs to the
## `ratio <= 0.67` defender-victory band.
##
## The first row is the wiki's morale row: a winning attacker whose morale is
## lower than the defender's fights a blunted battle between 1.5 and 4.0 to one —
## heavier losses, and a stalemate instead of a capture even when the garrison
## is wiped (wiki: combat § Auto-resolve ratio bands — the "blunted" row).
const BANDS: Array[Dictionary] = [
	{
		"min": 1.5,
		"max": 4.0,
		"morale": "lower",
		"attacker": 0.6,
		"defender": 0.4,
		"blunted": true,
	},
	{"min": 1.5, "attacker": 0.15, "defender": 1.0},
	{"min": 1.0, "attacker": 0.3, "defender": 0.6},
	{"min": 0.67, "attacker": 0.5, "defender": 0.4, "exclusive": true},
	{"min": 0.0, "attacker": 1.0, "defender": 0.15},
]


## The band one exchange fights under. `attacker_morale` and `defender_morale`
## are the sides' feeding multipliers (1.0 / 0.75 / 0.5): equal or higher
## attacker morale leaves every published row unchanged, and the morale row
## claims only `ratio < 4.0`.
static func for_ratio(
	ratio: float,
	attacker_morale: float = 1.0,
	defender_morale: float = 1.0
) -> Dictionary:
	var hungrier: bool = attacker_morale < defender_morale
	for band: Dictionary in BANDS:
		var low: float = float(band["min"])
		if bool(band.get("exclusive", false)):
			if ratio <= low:
				continue
		elif ratio < low:
			continue
		if band.has("max") and ratio >= float(band["max"]):
			continue
		if String(band.get("morale", "")) == "lower" and not hungrier:
			continue
		return band
	return BANDS[BANDS.size() - 1]
