class_name WorkerPool
extends RefCounted
## Industrial labour in the capital (wiki: workers-and-population). Workers are a
## population model, not map units: they supply labour to production and eat from
## the central stockpile. Pure data so consumption and production stay headless.

enum Tier { PEASANT, APPRENTICE, JOURNEYMAN, MASTER }

const TIER_COUNT: int = 4

## Labour, food and luxury per worker by tier (wiki: workers-and-population § Tiers).
const LABOUR_PER_WORKER: Array[int] = [1, 4, 6, 8]
const FOOD_PER_WORKER: Array[int] = [1, 2, 2, 2]
const LUXURY_PER_TIER: Array[String] = ["", "refinedSugar", "cigars", "furHats"]

const TIER_NAMES: Array[String] = ["Peasants", "Apprentices", "Journeymen", "Masters"]
## One worker of a tier, for copy that names a single demotion or recruit.
const TIER_ONE: Array[String] = ["Peasant", "Apprentice", "Journeyman", "Master"]

## Recruit / train rows (wiki: workers-and-population § Costs, v1 authoritative).
const RECRUIT_TREASURY: Array[int] = [0, 200, 500, 1000]
const RECRUIT_MATERIAL: Array[String] = ["fabric", "paper", "paper", "paper"]
const RECRUIT_QUANTITY: Array[int] = [2, 2, 5, 10]
## Every trained tier is converted from one peasant (no direct tier-to-tier training).
const RECRUIT_CONSUMES_PEASANTS: Array[bool] = [false, true, true, true]

const TIER_TECHS: Array[Array] = [
	[],
	["apprentice_workers", "sugar_refining"],
	["trained_journeymen", "cigar_production"],
	["master_artisans", "hat_production"],
]

var counts: Array[int] = [0, 0, 0, 0]


static func make(
	peasants: int, apprentices: int = 0, journeymen: int = 0, masters: int = 0
) -> WorkerPool:
	var pool := WorkerPool.new()
	pool.set_count(Tier.PEASANT, peasants)
	pool.set_count(Tier.APPRENTICE, apprentices)
	pool.set_count(Tier.JOURNEYMAN, journeymen)
	pool.set_count(Tier.MASTER, masters)
	return pool


func count(tier: int) -> int:
	if tier < 0 or tier >= TIER_COUNT:
		return 0
	return counts[tier]


func set_count(tier: int, value: int) -> void:
	if tier < 0 or tier >= TIER_COUNT:
		return
	counts[tier] = maxi(value, 0)


func add(tier: int, amount: int) -> void:
	set_count(tier, count(tier) + amount)


## Removes one worker of a tier; false when the pool has none.
func remove(tier: int, amount: int = 1) -> bool:
	if tier < 0 or tier >= TIER_COUNT or count(tier) < amount:
		return false
	counts[tier] -= amount
	return true


func total() -> int:
	var sum: int = 0
	for tier in TIER_COUNT:
		sum += counts[tier]
	return sum


func labour() -> int:
	var sum: int = 0
	for tier in TIER_COUNT:
		sum += counts[tier] * LABOUR_PER_WORKER[tier]
	return sum


func food_demand() -> int:
	var sum: int = 0
	for tier in TIER_COUNT:
		sum += counts[tier] * FOOD_PER_WORKER[tier]
	return sum


static func is_trained(tier: int) -> bool:
	return tier > Tier.PEASANT and tier < TIER_COUNT


static func luxury_for(tier: int) -> String:
	if tier < 0 or tier >= TIER_COUNT:
		return ""
	return LUXURY_PER_TIER[tier]


static func tier_name(tier: int) -> String:
	if tier < 0 or tier >= TIER_COUNT:
		return "Workers"
	return TIER_NAMES[tier]


## "Apprentice" — one worker of the tier, for a single recruit or demotion.
static func tier_one(tier: int) -> String:
	if tier < 0 or tier >= TIER_COUNT:
		return "Worker"
	return TIER_ONE[tier]


static func required_techs(tier: int) -> Array:
	if tier < 0 or tier >= TIER_COUNT:
		return []
	return TIER_TECHS[tier]


static func techs_unlocked(tier: int, tech_unlocked: Dictionary) -> bool:
	for tech: String in required_techs(tier):
		if not bool(tech_unlocked.get(tech, false)):
			return false
	return true


## Treasury and material cost of one recruit/train action for a target tier.
static func recruit_cost(tier: int) -> Dictionary:
	var material: String = RECRUIT_MATERIAL[tier]
	if material.is_empty():
		return {"treasury": 0, "materials": {}}
	return {
		"treasury": RECRUIT_TREASURY[tier],
		"materials": {material: RECRUIT_QUANTITY[tier]},
	}


func copy() -> WorkerPool:
	var clone := WorkerPool.new()
	clone.counts = counts.duplicate()
	return clone
