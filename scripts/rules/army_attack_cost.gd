class_name ArmyAttackCost
extends RefCounted
## The treasury a Great Power spends to fight one land battle (wiki:
## tech-tree-military § Economy modifiers, `kLandBattleAttackTreasuryCostBase`).
## Base 100 ducats per attacker per battle context; Industrial Machinery ×0.75
## and Modern Military Funding ×0.85, multiplied together when both are known.
## Pure maths, so auto-resolve and Quick Battle charge the same price
## (REQ-P2-03, REQ-P3-03).

const BASE: int = 100
const TECH_FACTORS: Dictionary = {
	"industrial_machinery": 0.75,
	"modern_military_funding": 0.85,
}


## Product of the unlocked attack-cost techs; 1.0 with none researched.
static func multiplier(unlocked: Dictionary) -> float:
	var factor: float = 1.0
	for tech_id: Variant in TECH_FACTORS.keys():
		if bool(unlocked.get(String(tech_id), false)):
			factor *= float(TECH_FACTORS[tech_id])
	return factor


## Whole ducats, floored: 100 alone, 75, 85, and 63 with both techs.
static func cost(unlocked: Dictionary) -> int:
	return floori(float(BASE) * multiplier(unlocked))


## Charges one battle context through the caller's ledger callback
## (`context["pay_attack"]`). Without a callback — rules tests, projections —
## nothing is taken, and the price is still reported.
static func charge(context: Dictionary, attacker: int) -> Dictionary:
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var unlocked: Dictionary = tech.get(attacker, {}) as Dictionary
	var due: int = cost(unlocked)
	var pay: Callable = context.get("pay_attack", Callable())
	if not pay.is_valid():
		return {"due": due, "paid": 0}
	var paid: int = maxi(int(pay.call(attacker, due)), 0)
	return {"due": due, "paid": mini(paid, due)}


## Stamps one exchange's price onto its battle record, so the despatch and the
## Quick Battle plate can name what the attack cost.
static func stamp(fee: Dictionary, report: Dictionary) -> Dictionary:
	report["attack_cost"] = int(fee.get("due", 0))
	report["attack_paid"] = int(fee.get("paid", 0))
	return report


## Takes the price off one court's ledger and reports what was actually paid.
## A crown never fights on credit: the charge floors at zero, so an attack whose
## purse is short still resolves (nothing in the rules makes treasury a
## condition of attacking).
static func pay(ledger: PlayerEconomy, due: int) -> int:
	if ledger == null or due <= 0:
		return 0
	var paid: int = mini(due, maxi(ledger.treasury, 0))
	if paid > 0:
		ledger.spend_treasury(paid)
	return paid
