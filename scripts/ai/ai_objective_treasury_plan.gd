class_name AiObjectiveTreasuryPlan
extends RefCounted
## The treasury's aims: the study the college is filling and the deed the
## merchant is saving toward (docs/ai.md; issue #491, #590, #724). Pure:
## readings in, objectives out (REQ-P2-03).

const W_RESEARCH: int = 45
const W_RESEARCH_STEP: int = 5
## The deed the court is saving toward: the cheapest Minor or Tribe resource
## tile it could sign at the published 15 x base price. Ranked below every other
## treasury claim, so the aim names the intent without taking the purse the
## muster, the yard or a study is saving for (issue #724 task 3).
const W_DEED: int = 40


## A study while the court has a slot to fill; the funding step is the utility.
## The standing study prices its own one-slot budget (the bounded exception
## that may dip into the chest the muster claims); a study the purse cannot
## fund this turn is `blocked` with the refusal the planner made — never a
## 0-gold row that reads `funded` while the court learns nothing (issue #590).
static func research(readings: Dictionary) -> AiObjective:
	if int(readings.get("research_slots", 0)) <= 0:
		return null
	var step: int = clampi(int(readings.get("research_funding", 0)), 0, 4)
	var cost: Dictionary = (
		{"standing": 1}
		if int(readings.get("standing_study", 0)) > 0
		else {"treasury": int(readings.get("research_cost", 0))}
	)
	var aim := AiObjective.create(
		"research.study", "research", W_RESEARCH + step * W_RESEARCH_STEP, cost
	)
	var refusal: String = String(readings.get("research_refusal", ""))
	if not refusal.is_empty():
		aim.block(refusal)
	return aim


## The deed the court is saving toward: the cheapest Minor or Tribe resource
## tile it could sign at the published 15 x base price, priced on the purse it
## must hold. The aim is a reading — the Merchant's own order is what signs the
## deed — but it is the row the deferred-aim escalation tracks, so a court that
## never reaches the price reads `blocked` with the stall named instead of
## saving in silence (issue #724 task 3, #603).
static func deed(readings: Dictionary) -> AiObjective:
	var price: int = int(readings.get("deed_price", 0))
	if price <= 0:
		return null
	var aim := AiObjective.create("market.deed", "economy", W_DEED, {"treasury": price})
	var stall: int = int(
		(readings.get("blockings", {}) as Dictionary).get("market.deed", 0)
	)
	if stall > 0:
		aim.block("the deed is out of reach %d turns" % stall)
	return aim
