class_name DiplomacyPower
extends RefCounted
## The published Great Power power score, for the court panel's relative line
## (wiki: diplomacy § Great Power power score). Pure arithmetic over province
## ownership plus the caller's public order of battle, so the panel, the AI's war
## desire and the calendar's declared winner read one formula (REQ-P3-03).
## Kept beside [AiPower]'s weights rather than in [DiplomacyRules] so no rules
## module outgrows the size bar (REQ-P3-01).


## Score for every Great Power: provinces × W_province + round(strength) ×
## W_regiment + hulls × W_ship. `strength` and `ships` map faction id → the
## crown's public order of battle; a court with no field forces scores on land
## alone.
static func public_power(
	world: WorldMap, strength: Dictionary = {}, ships: Dictionary = {}
) -> Dictionary:
	var scores: Dictionary = {}
	if world == null:
		return scores
	for faction_id: int in FactionCatalog.great_power_ids():
		scores[faction_id] = AiPower.score(
			world,
			faction_id,
			int(roundf(float(strength.get(faction_id, 0.0)))),
			int(ships.get(faction_id, 0))
		)
	return scores


## A rival's power against the crown's own: 1.0 is even, 1.4 is 40% stronger. A
## crown that scores nothing yet is measured against 1, so the ratio stays
## finite and no screen divides by zero.
static func power_ratio(mine: int, theirs: int) -> float:
	return float(theirs) / float(maxi(mine, 1))


## The signed share of a rival's power over the crown's, rounded for display:
## +40 for a crown 40% stronger, -20 for one a fifth weaker, 0 when even.
static func power_percent(mine: int, theirs: int) -> int:
	return int(roundf((power_ratio(mine, theirs) - 1.0) * 100.0))
