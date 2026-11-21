class_name QuickBattleTerms
extends RefCounted
## The battle's written law: its length, its command points, the plan each side
## is given when the crown names none, and the weight a line fights at
## (wiki: quick-battle § Core actions; § The crown's plan; § Cohesion and
## effective strength).
##
## [QuickBattle] and [QuickBattleRounds] conduct the battle and read every one
## of these from here, so a rule change lands in one file and the plate, the
## simulator and the resolver keep one answer. Ask this class directly; the
## orchestrators keep no pass-through copies of its law.
## Pure data and maths: no nodes, no state (REQ-P3-01, REQ-P3-03).

## A battle is fought over this many rounds at most.
const MAX_ROUNDS: int = 3
## Each side spends this many command points a round.
const CP_PER_ROUND: int = 3
## Cohesion runs 0..CEILING for both sides: a line opens at the ceiling and
## spends steps of it, and the multiplier it fights at is cohesion over this
## (wiki: quick-battle § Cohesion and effective strength).
const COHESION_MAX: int = 3
## A line whose horse reaches this share of it takes the field aggressively.
const RIDERS_AGGRESSIVE: float = 0.3


## The plan one side is handed. An explicit defender script wins (the simulator
## and a scripted defence); otherwise the player's chosen plan follows the side
## they command (wiki: quick-battle § The crown's plan).
##
## `line` names the men the battle dealt when it opened. A garrison's own sally
## reads it: the wall answers with its line's RNG ≥ 2 regiments alone, so a
## musket held in reserve gives the parapet no fire and the pike wall still
## sallies (wiki: siege-mechanics § Quick Battle lanes; combat § The line and
## the reserve). Empty keeps the older read for a caller with no line.
static func plan_for(
	side: Array[ArmyState], owner: int, context: Dictionary, is_defender: bool,
	siege: bool = false, line: Array[String] = []
) -> String:
	if is_defender and QuickBattleActions.PLANS.has(String(context.get("defender_battle_plan", ""))):
		return String(context["defender_battle_plan"])
	if owner == int(context.get("player_faction", -1)):
		return QuickBattleActions.normalize_plan(String(context.get("battle_plan", "balanced")))
	## A garrison with no firearm on the wall can only hurt a siege by sallying.
	if is_defender and siege and SiegeLanes.return_fire_share(side, line) <= 0.0:
		return "aggressive"
	return "aggressive" if _horse_share(side) >= RIDERS_AGGRESSIVE \
		else ("defensive" if is_defender else "balanced")


## One side's battle weight: the deployed slice's Σ (FPN + FPM) × chevrons ×
## health, scaled by cohesion and the side's combat modifiers. Emplaced guns
## add their own type's weight, already scaled by their remaining HP (wiki:
## quick-battle § Cohesion and effective strength).
##
## `line` is the slice the battle dealt when it opened: the weight is read over
## **those** survivors, so a reserve behind the line adds no strength even after
## the line has fallen below the deployment limit (wiki: combat § The line and
## the reserve — "a reserve adds no strength"; quick-battle § Cohesion and
## effective strength — "reserves behind the deployment limit never count").
## Empty keeps the older read for a hand-built state.
static func effective_strength(
	side: Array[ArmyState],
	limit: int,
	cohesion: int,
	multiplier: float,
	gun_weight: float = 0.0,
	line: Array[String] = []
) -> float:
	var weight: float = ArmyModifiers.strength(side, limit, multiplier) if line.is_empty() \
		else ArmyForce.line_strength(side, line, multiplier)
	return (
		weight
		* (float(clampi(cohesion, 0, COHESION_MAX)) / float(COHESION_MAX))
		+ gun_weight
	)


## The strongest cavalry share any army in a side can field.
static func _horse_share(side: Array[ArmyState]) -> float:
	var riders: float = 0.0
	for army: ArmyState in side:
		if army != null:
			riders = maxf(riders, army.cavalry_share())
	return riders