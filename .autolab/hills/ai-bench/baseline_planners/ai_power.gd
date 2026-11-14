class_name MainlineAiPower
extends RefCounted
## Great Power power score and relative-power bands (wiki: diplomacy
## § Great Power power score, § GP AI policy for war vs. relations).
## Pure arithmetic over province ownership plus caller-supplied unit counts, so
## war desire can be scored headlessly (REQ-P3-03).

const RELATIVE_STRONG: float = 1.35
const RELATIVE_EVEN: float = 0.85
const BONUS_STRONG: int = 30
const BONUS_EVEN: int = 5
const BONUS_WEAK: int = -25


## `powerScore = provinceCount × W_province + round(regimentStrength) × W_regiment
## + shipCount × W_ship` (wiki defaults 10 / 1 / 5, overridable per profile).
static func score(
	world: WorldMap,
	faction: int,
	regiments: int = 0,
	ships: int = 0,
	weights: Dictionary = {}
) -> int:
	if world == null:
		return 0
	var province_count: int = DiplomacyRules.provinces_owned(world, faction)
	var w_province: int = int(
		weights.get(
			"province", MainlineAiParameterRegistry.default_of("diplomacy.power_province_weight")
		)
	)
	var w_regiment: int = int(
		weights.get(
			"regiment", MainlineAiParameterRegistry.default_of("diplomacy.power_regiment_weight")
		)
	)
	var w_ship: int = int(
		weights.get("ship", MainlineAiParameterRegistry.default_of("diplomacy.power_ship_weight"))
	)
	return province_count * w_province + int(roundf(float(regiments))) * w_regiment + ships * w_ship


## Relative power band: attackerPower / max(1, targetPower).
static func relative_band(attacker_power: int, target_power: int) -> Dictionary:
	var relative: float = float(attacker_power) / float(maxi(1, target_power))
	var bonus: int = BONUS_EVEN
	if relative >= RELATIVE_STRONG:
		bonus = BONUS_STRONG
	elif relative < RELATIVE_EVEN:
		bonus = BONUS_WEAK
	return {"relative": relative, "bonus": bonus}