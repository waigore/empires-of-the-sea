class_name ArmyGarrison
extends RefCounted
## Mutual-annihilation garrison recovery (wiki: combat § Outcomes, § Garrison
## recovery type). Split from [ArmyCombat] so the battle chain stays inside the
## P3 size bar; the recovered levies are minted as era-best infantry.

## Share of the defender's opening regiments that reforms, at least one.
const RECOVERY_SHARE: float = 0.2
## Great Power military era; Minors/Tribes fight at 1 (wiki: factions).
const GREAT_POWER_ERA: int = 4
const MINOR_ERA: int = 1


## Restores 20% (ceil, at least one, never above the initial count) of the
## defender's starting regiments as the era's most advanced infantry.
static func recover(
	armies: Array[ArmyState], province: int, defender: int, initial: int
) -> Dictionary:
	if initial <= 0:
		return {"count": 0, "type": ""}
	var count: int = clampi(ceili(float(initial) * RECOVERY_SHARE), 1, initial)
	var type_id: String = RegimentCatalog.garrison_type_for(era_for(defender))
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


static func era_for(faction_id: int) -> int:
	if FactionCatalog.type_of(faction_id) == FactionCatalog.Type.GREAT_POWER:
		return GREAT_POWER_ERA
	return MINOR_ERA
