class_name AutoSiege
extends RefCounted
## Fort gun-loss on the auto-resolve path (wiki: siege-mechanics § Emplaced
## Artillery; DR-20261110-22).
## Auto-resolve keeps a fort's emplaced pieces as one aggregate battery, so the
## counter-battery is read from the besieging artillery train instead of named
## guns: one emplaced piece falls per gun's weight of that train. Reaching the
## last gun drops the fort a level, even when the attack is repelled — the same
## rule Quick Battle applies to its virtual pieces (REQ-P2-03, REQ-P3-03).


## Σ of the deployed artillery's rank: the slice and the chevron/wound maths the
## exchange itself reads, so a mauled train answers with less.
static func artillery_weight(side: Array[ArmyState], limit: int) -> float:
	var total: float = 0.0
	for entry: Dictionary in ArmyModifiers.deployed(side, limit):
		var army: ArmyState = entry["army"]
		if RegimentCatalog.is_artillery(army.type_of(String(entry["id"]))):
			total += float(entry["rank"])
	return total


## One emplaced piece's strength in the defender's researched line (Royal →
## Heavy → Siege): the aggregate proxy's unit of account.
static func gun_weight(tech_unlocked: Dictionary) -> float:
	return maxf(1.0, RegimentCatalog.strength(FortRules.emplaced_type(tech_unlocked)))


## Whole pieces only: an auto-resolved exchange keeps no wounded battery
## between turns, so a partial gun does not carry over.
static func guns_silenced(
	level: int, tech_unlocked: Dictionary, attacking: Array[ArmyState], atk_limit: int
) -> int:
	var pieces: int = FortRules.guns(level)
	if pieces <= 0:
		return 0
	var weight: float = artillery_weight(attacking, atk_limit)
	if weight <= 0.0:
		return 0
	return mini(pieces, floori(weight / gun_weight(tech_unlocked)))


## Reads the battery after an auto-resolved exchange and writes the downgrade
## when the last gun is silenced (a captured province keeps whatever walls and
## guns survive). Empty in the open field, so a field report carries no siege
## block.
static func resolve(
	model: MapModel,
	province: int,
	level: int,
	defender: int,
	attacking: Array[ArmyState],
	atk_limit: int,
	context: Dictionary
) -> Dictionary:
	if not FortRules.is_siege(level):
		return {}
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var unlocked: Dictionary = tech.get(defender, {}) as Dictionary
	var guns: Array[Dictionary] = QuickBattleBattery.make(level, context, defender)
	var silenced: int = guns_silenced(level, unlocked, attacking, atk_limit)
	if silenced > 0:
		QuickBattleBattery.hit(guns, silenced * int(QuickBattleBattery.GUN_HP))
	var downgraded: bool = QuickBattleBattery.downgrade_fort(model, province, level, guns)
	var alive: int = QuickBattleBattery.alive(guns)
	return {
		"guns_start": guns.size(),
		"guns_left": alive,
		"guns_lost": guns.size() - alive,
		"gun_type": FortRules.emplaced_type(unlocked),
		"fort_before": level,
		"fort_downgraded": downgraded,
		"fort_after": FortRules.level_at(model, province),
	}
