class_name ArmyGarrison
extends RefCounted
## Mutual-annihilation garrison recovery (wiki: combat § Outcomes, § Garrison
## recovery type). Split from [ArmyCombat] so the battle chain stays inside the
## P3 size bar; the recovered levies are minted as era-best infantry.

## Share of the defender's opening regiments that reforms, at least one.
const RECOVERY_SHARE: float = 0.2
## A Great Power reforms at 4, a Minor Nation at the parity level the caller
## passes, a Tribe at 1 (wiki: combat § Garrison recovery type; factions
## § Minor military parity).
const GREAT_POWER_ERA: int = 4
const MINOR_ERA: int = 1


## Restores 20% (ceil, at least one, never above the initial count) of the
## defender's starting regiments as the era's most advanced infantry.
static func recover(
	armies: Array[ArmyState], province: int, defender: int, initial: int,
	context: Dictionary = {}
) -> Dictionary:
	if initial <= 0:
		return {"count": 0, "type": ""}
	var count: int = clampi(ceili(float(initial) * RECOVERY_SHARE), 1, initial)
	var type_id: String = RegimentCatalog.garrison_type_for(era_for(defender, context))
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	var army := ArmyState.muster(
		ArmyCommand.next_army_id(armies),
		defender,
		province,
		false,
		types,
		ArmyCommand.next_unit_number(armies)
	)
	armies.append(army)
	return {"count": count, "type": type_id}


## Effective military era for garrison recovery (wiki: combat § Garrison
## recovery type; factions § Minor military parity). A crown with no parity
## data still reforms at its own level.
static func era_for(faction_id: int, context: Dictionary = {}) -> int:
	if FactionCatalog.type_of(faction_id) == FactionCatalog.Type.GREAT_POWER:
		return GREAT_POWER_ERA
	if FactionCatalog.has_military_parity(faction_id):
		return maxi(int(context.get("parity_era", MINOR_ERA)), MINOR_ERA)
	return MINOR_ERA
