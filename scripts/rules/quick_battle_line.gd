class_name QuickBattleLine
extends RefCounted
## The line a quick battle deals each side when it opens (wiki: quick-battle
## § Battlefield layout; § Wings and collapse; combat § The line and the reserve).
##
## A side fights with the men its line was dealt, not with every regiment it
## owns: a reserve behind the line is dealt nowhere, so it adds no strength,
## takes no casualties, pays no charge and draws no fire. One module owns that
## reading — which wing a blow falls into, what is still standing there, how
## heavy the blow lands, and which men it may break — so the actions, the
## garrison's battery and the round gate read the same line (REQ-P3-01,
## REQ-P3-03).
##
## Pure data and maths: no nodes, no state beyond the dictionaries it is handed.

## The wings of one side's dict, as dealt when the battle opened.
const WINGS_KEY: String = "wings"


## The line a side was dealt when the battle opened, as the typed id list the
## army rules read. Empty for a state dealt no line (a hand-built one, a record
## made before the line was dealt).
static func line_of(side_state: Dictionary) -> Array[String]:
	var line: Array[String] = []
	line.assign(side_state.get("line", []) as Array)
	return line


## The wing this blow falls into: fire on the fullest part of the enemy line, a
## charge on the thinnest. "" when the action strikes no wing at all, or when the
## enemy line holds nobody (wiki: quick-battle § Wings and collapse).
static func wing_for(side_state: Dictionary, action: String) -> String:
	var held: Dictionary = QuickBattleWings.counts(wings_of(side_state))
	return QuickBattleWings.target(held, action)


## The wing's own dict of a side, or `{}` for a garrison behind a wall or a
## record made before wings existed.
static func wings_of(side_state: Dictionary) -> Dictionary:
	return side_state.get(WINGS_KEY, {}) as Dictionary


## Regiments of one side's line still standing. The line is the battle's whole
## fighting strength: a side whose line is gone has nothing left to fight with
## (wiki: combat § The line and the reserve; quick-battle § Wings and collapse).
## A state dealt no line (a hand-built one, a record before the line was dealt)
## reads its whole side, exactly as before.
static func standing_of(side_state: Dictionary) -> int:
	var line: Array[String] = line_of(side_state)
	if line.is_empty():
		var whole: Array[ArmyState] = []
		whole.assign(side_state.get("side", []) as Array)
		return ArmyForce.side_regiments(whole)
	var standing: Dictionary = QuickBattleWings.standing_ids(side_state)
	var count: int = 0
	for regiment_id: String in line:
		if standing.has(regiment_id):
			count += 1
	return count


## Regiments of one side still standing, read by battle state and side key: the
## round gate's reading of [method standing_of].
static func standing(state: Dictionary, key: String) -> int:
	return standing_of(state.get(key, {}) as Dictionary)


## The men a blow may break: the line the battle dealt when it opened, so a
## reserve stands through it whatever the line loses (wiki: combat § The line and
## the reserve — "a reserve takes no casualties"). A state with no line (a
## hand-built one, a record made before the line was dealt) keeps the older read,
## the strongest `limit` of the side as it stands.
static func losses(
	armies: Array[ArmyState], side: Array[ArmyState], wanted: int, side_state: Dictionary
) -> Array[String]:
	var line: Array[String] = line_of(side_state)
	return ArmyForce.apply_losses(
		armies, side, wanted, 0 if not line.is_empty() else int(side_state["limit"]),
		Callable(), line
	)


## Breaks `wanted` men of one side's line, into the wing the blow fell on alone:
## a line with no wings (a hand-built state, a record before wings existed) is
## bled as one deployed slice, exactly as before (wiki: quick-battle § Wings and
## collapse). Returns the ids broken.
static func break_men(
	armies: Array[ArmyState],
	side: Array[ArmyState],
	wanted: int,
	side_state: Dictionary,
	wing: String
) -> Array[String]:
	var wings: Dictionary = wings_of(side_state)
	if wing.is_empty() or wings.is_empty():
		return losses(armies, side, wanted, side_state)
	return ArmyForce.apply_losses(
		armies, side, wanted, 0, Callable(), QuickBattleWings.ids(wings, wing)
	)


## The weight one side lands with a blow: the men its line was dealt when the
## battle opened ([method ArmyForce.line_strength]), so a reserve never steps up
## into the slice after casualties and adds strength it never carried (wiki:
## combat § The line and the reserve). A state dealt no line keeps the older
## read, the strongest `limit` of the side as it stands.
static func weight(side: Array[ArmyState], side_state: Dictionary) -> float:
	var line: Array[String] = line_of(side_state)
	var multiplier: float = multiplier_of(side_state)
	if line.is_empty():
		return ArmyModifiers.strength(side, int(side_state["limit"]), multiplier)
	return ArmyForce.line_strength(side, line, multiplier)


## A side's combat multiplier from its modifier bundle; an unmodified side
## (tests, a hand-built state) fights at 1.0.
static func multiplier_of(side_state: Dictionary) -> float:
	var mods: Dictionary = side_state.get("mods", {}) as Dictionary
	return float(mods.get("multiplier", 1.0))