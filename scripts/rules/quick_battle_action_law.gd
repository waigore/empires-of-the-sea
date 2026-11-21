class_name QuickBattleActionLaw
extends RefCounted
## The written law of a quick battle's actions: the three plans and the orders
## each one scripts, what an order costs in command points, how hard it strikes
## and how much it costs the side that walks it, the guard it raises, the
## cohesion step it spends, and the words the despatch prints for it (wiki:
## quick-battle § Core actions; § The crown's plan; § Cohesion and effective
## strength).
##
## [QuickBattleActions] resolves a blow and [QuickBattleRounds] spends the
## points, and both read every number from here, so a rule change lands in one
## file and the plate, the simulator and the resolver keep one answer. Ask this
## class directly; the resolvers keep no pass-through copies of its law.
## Pure data and maths: no nodes, no state (REQ-P3-01, REQ-P3-03).

## Attacker scripts. The defender has its own: a sally is a **Sortie** order,
## not an assault on a wall it is standing on (wiki: siege-mechanics § Gates).
const PLANS: Dictionary = {
	"aggressive": ["maneuver", "assault"], "balanced": ["volley", "entrench", "volley"],
	"defensive": ["fall_back", "volley"],
}
const DEFENDER_PLANS: Dictionary = {
	"aggressive": ["entrench", "sortie"], "balanced": ["volley", "entrench"],
	"defensive": ["fall_back", "volley"],
}
## A garrison in the open has no gate to sally from: the sortie slot becomes
## volley fire so a defender script still spends its CP.
const DEFENDER_FIELD_PLANS: Dictionary = {
	"aggressive": ["entrench", "volley", "volley"], "balanced": ["volley", "entrench"],
	"defensive": ["fall_back", "volley"],
}
const ACTION_CP: Dictionary = {
	"volley": 1, "entrench": 1, "maneuver": 1, "assault": 2, "sortie": 2, "fall_back": 2,
}
const ACTION_DAMAGE: Dictionary = {
	"volley": 0.12, "assault": 0.26, "sortie": 0.22,
	"entrench": 0.0, "maneuver": 0.0, "fall_back": 0.0,
}
const ACTION_SELF: Dictionary = {
	"volley": 0.0, "assault": 0.10, "sortie": 0.08,
	"entrench": 0.0, "maneuver": 0.0, "fall_back": 0.0,
}
const ACTION_GUARD: Dictionary = {
	"volley": 0.0, "assault": 0.0, "sortie": 0.0, "entrench": 0.45,
	"maneuver": 0.0, "fall_back": 0.25,
}
const ACTION_LABEL: Dictionary = {
	"volley": "Volley fire", "assault": "Assault", "sortie": "Sortie",
	"entrench": "Entrench", "maneuver": "Maneuver", "fall_back": "Fall back",
}
## The steps of cohesion a stance takes off the side walking it: a manoeuvre costs
## one while the line is under pressure — it has already lost men — and none on an
## intact line, and a fall back trades one for the space it gives. Every other
## stance costs none, and none of them ever returns a step (wiki: quick-battle
## § Turn structure and actions). The ground is not charged twice: a blow into
## broken ground is already the weaker for it (`SiegeGround.terrain_scale`,
## DR-20261120-07).
const ACTION_COHESION: Dictionary = {"maneuver": 1, "fall_back": 1}
## Why a paid step reads as it does in the despatch.
const COHESION_WHY: Dictionary = {
	"maneuver": "under pressure", "fall_back": "the line gives ground",
}


## The orders one side's plan scripts this battle: the attacker's plan, or the
## garrison's own (a walled garrison may sally, one in the open may not).
static func actions_for(
	plan: String, is_defender: bool = false, siege: bool = false
) -> Array:
	if is_defender:
		var script: Dictionary = DEFENDER_PLANS if siege else DEFENDER_FIELD_PLANS
		return (script.get(plan, script["balanced"]) as Array).duplicate()
	return (PLANS.get(plan, PLANS["balanced"]) as Array).duplicate()


## The one gate every plan value passes: the three published stances, anything
## else (an old save, a typo, a scenario) is `balanced` (wiki: quick-battle
## § The crown's plan — "Any other value is balanced"; DR-20261110-33).
static func normalize_plan(plan: String) -> String:
	return plan if PLANS.has(plan) else "balanced"


## What one order costs the side that walks it, in command points.
static func cp_cost(action: String) -> int:
	return int(ACTION_CP.get(action, 0))


## The share of the enemy line an order's blow carries before the line, the
## guard, the ground and a flank scale it.
static func damage_share(action: String) -> float:
	return float(ACTION_DAMAGE.get(action, 0.0))


## The share of its own line an order costs the side that launches it.
static func self_share(action: String) -> float:
	return float(ACTION_SELF.get(action, 0.0))


## The guard an order raises for the side that keeps its ground.
static func guard_of(action: String) -> float:
	return float(ACTION_GUARD.get(action, 0.0))


## The words the despatch prints for an order.
static func label_of(action: String) -> String:
	return String(ACTION_LABEL.get(action, action))


## The steps of cohesion a stance takes off the side walking it: a manoeuvre
## costs one only while the line is under pressure — it has already lost men —
## and none on an intact line.
static func cohesion_cost(acted: String, me: Dictionary) -> int:
	if acted == "maneuver" and (me.get("lost", []) as Array).is_empty():
		return 0
	return int(ACTION_COHESION.get(acted, 0))


## Why a stance cost the step it did, in the words the despatch prints.
static func cohesion_why(acted: String) -> String:
	return String(COHESION_WHY.get(acted, ""))
