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
##
## The reformed standard and its men are new instances, so they take their ids
## from the crown's own cursors (`context["ids"]`, seeded by the map layer from
## the saved `next_army` / `next_regiment`). A pass with no cursors — a battle
## simulation or a hand-built roster — falls back to the roster's own scan. A
## scan alone is not enough on the map: a region's roster never holds another
## chart's ids, so minting above the local maximum reuses an id that is still
## standing elsewhere, and the next split or muster hands out the same one.
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
	var army_id: int = ArmyCommand.next_army_id(armies)
	var first_unit: int = ArmyCommand.next_unit_number(armies)
	var cursors: Dictionary = context.get("ids", {}) as Dictionary
	if not cursors.is_empty():
		# Above both the cursor and everything still standing, so a stale cursor
		# can never mint an id a live army already wears.
		army_id = maxi(int(cursors.get("army", army_id)), army_id)
		first_unit = maxi(int(cursors.get("regiment", first_unit)), first_unit)
		cursors["army"] = army_id + 1
		cursors["regiment"] = first_unit + count
	var army := ArmyState.muster(
		army_id,
		defender,
		province,
		false,
		types,
		first_unit
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
