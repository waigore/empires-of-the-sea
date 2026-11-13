class_name AiUtility
extends RefCounted
## The one currency a rival court's objectives are priced in (docs/ai.md;
## issue #491 T1). Planners score in their own scales — desire 0–100, holds,
## ducats, funding steps — and each normalizes into this 0–100 scale here, so
## the ledger can rank a voyage against a regiment without inventing an
## exchange rate per planner (REQ-P2-02, REQ-P2-03).
##
## Pure arithmetic: no state, no nodes, safe to drive from tests.

## Resources an objective may claim, in the trace's reading order. Treasury is
## ducats, hull a slip at the yard, civilian the next train slot, regiment the
## next muster slot, labour a crew hand, orders the court's one order a turn.
const RESOURCES: Array[String] = [
	"treasury", "hull", "civilian", "regiment", "labour", "orders",
]
## A pool no caller states is not scarce: a claim against it always succeeds.
const UNBOUNDED: int = 1 << 30


static func clamp_utility(value: int) -> int:
	return clampi(value, 0, 100)


## A planner's own score mapped onto 0–100 between `low` and `high`.
static func scale(value: int, low: int, high: int) -> int:
	if high <= low:
		return 100 if value >= high else 0
	return clamp_utility(roundi(100.0 * float(value - low) / float(high - low)))


## A part of a whole as 0–100: the shape a "strength against the enemy" reading
## takes.
static func ratio(part: int, whole: int) -> int:
	if whole <= 0:
		return 100 if part > 0 else 0
	return clamp_utility(roundi(100.0 * float(maxi(part, 0)) / float(whole)))


## Rank = clamp(utility × modifier / 1000, 0, 100). T1 passes no modifier; the
## posture vector becomes a modifier in T4 (#499).
static func modified(utility: int, per_mille: int = 1000) -> int:
	return clamp_utility((utility * maxi(per_mille, 0)) / 1000)


## A cost row with zero and unknown keys dropped, so the trace reads only what
## the objective actually asks for.
static func clean_cost(cost: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	for key: String in RESOURCES:
		var amount: int = int(cost.get(key, 0))
		if amount > 0:
			clean[key] = amount
	return clean


## What a grant left unfunded: cost − claim, positive entries only.
static func shortfall(cost: Dictionary, claim: Dictionary) -> Dictionary:
	var short: Dictionary = {}
	for key: String in RESOURCES:
		var missing: int = int(cost.get(key, 0)) - int(claim.get(key, 0))
		if missing > 0:
			short[key] = missing
	return short


## "hull 0/1, civilian 0/1" — the trace's starvation line (issue #491 T2).
static func claim_text(cost: Dictionary, claim: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in RESOURCES:
		var asked: int = int(cost.get(key, 0))
		if asked <= 0:
			continue
		parts.append("%s %d/%d" % [key, int(claim.get(key, 0)), asked])
	return ", ".join(parts)


## A readable cost row for the trace: "treasury 120, orders 1".
static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in RESOURCES:
		if int(cost.get(key, 0)) > 0:
			parts.append("%s %d" % [key, int(cost[key])])
	return ", ".join(parts)
