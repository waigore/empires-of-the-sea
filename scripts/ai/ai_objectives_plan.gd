class_name AiObjectivesPlan
extends RefCounted
## The objective set one rival court emits before its planners run (docs/ai.md;
## issue #491 T1).
##
## Pure: readings in, objectives out. Nothing here issues an order or writes
## state, so stamping the ledger into the turn trace cannot move the rules
## (REQ-P2-03). Utilities are AiUtility's shared 0–100 currency and the cost
## rows name the resources the objective would claim once T2–T5 fund them, so
## the trace already explains what each aim wants and whether it got it.
##
## The readings dictionary is the planner-facing contract:
##   posture, at_war, war_desire, regiments, muster_due, muster_floor,
##   ships, hostile_ships, treasury, reserve, goal, colony_target, harbour,
##   idle_hulls, explorer_ready, voyage_afloat, cargo_shortfall,
##   research_slots, research_funding, research_cost.
## A missing reading reads as zero/false, so a thin fixture still emits a
## coherent list.

## Bench weights the parent analysis cites: colonisation carries the largest
## per-province weight (#476, ai-bench W_PROVINCES_NEW = 50).
const W_PROVINCES_NEW: int = 50
const W_DEFEND: int = 90
const W_DEFEND_PEACE: int = 25
const W_MUSTER: int = 70
const W_MUSTER_WAR: int = 15
const W_RESEARCH: int = 45
const W_RESEARCH_STEP: int = 5
const W_ECONOMY: int = 55
const W_CARGO: int = 40
const W_NAVY: int = 60


static func build(readings: Dictionary) -> Array[AiObjective]:
	var objectives: Array[AiObjective] = []
	var at_war: bool = bool(readings.get("at_war", false))
	objectives.append(_defend(at_war))
	var muster: AiObjective = _muster(readings, at_war)
	if muster != null:
		objectives.append(muster)
	objectives.append_array(_diplomacy(readings, at_war))
	var colony: AiObjective = _colonise(readings, at_war)
	if colony != null:
		objectives.append(colony)
	var navy: AiObjective = _navy(readings, at_war)
	if navy != null:
		objectives.append(navy)
	var cargo: AiObjective = _cargo(readings)
	if cargo != null:
		objectives.append(cargo)
	var research: AiObjective = _research(readings)
	if research != null:
		objectives.append(research)
	objectives.append(_economy())
	return objectives


## The seat held: at war every court keeps a regiment home, at peace it is a
## standing aim worth little next to growth.
static func _defend(at_war: bool) -> AiObjective:
	var cost: Dictionary = {"regiment": 1} if at_war else {}
	return AiObjective.create(
		"defend.seat", "military", W_DEFEND if at_war else W_DEFEND_PEACE, cost
	)


## A line regiment while the court stands under its target. The treasury entry
## is the war chest it must leave behind (AiArmyReinforce.muster_floor), which
## T3 turns into a shared claim (#498).
static func _muster(readings: Dictionary, at_war: bool) -> AiObjective:
	# `muster_due` is the court's own saving flag: muster_floor is non-zero
	# exactly while it stands under its target with a peasant and a line it can
	# pay for (AiArmyReinforce), so the ledger prices the muster it is saving
	# for and stays quiet once it stands at target.
	if not bool(readings.get("muster_due", false)):
		return null
	var utility: int = W_MUSTER + (W_MUSTER_WAR if at_war else 0)
	return AiObjective.create(
		"muster.line", "military", utility,
		{"regiment": 1, "labour": 1, "treasury": int(readings.get("muster_floor", 0))}
	)


## The court's one order a turn: press a war, open one, or spend it ending the
## war that blocks everything else (the peace window T2 funds, #497).
static func _diplomacy(readings: Dictionary, at_war: bool) -> Array[AiObjective]:
	var desire: int = clampi(int(readings.get("war_desire", 0)), 0, 100)
	var orders: Array[AiObjective] = []
	if at_war:
		orders.append(AiObjective.create("war.press", "diplomacy", desire, {"orders": 1}))
		orders.append(
			AiObjective.create("peace.window", "diplomacy", 100 - desire, {"orders": 1})
		)
		return orders
	orders.append(AiObjective.create("war.declare", "diplomacy", desire, {"orders": 1}))
	return orders


## The expedition parent: a hull off the cargo routes, the next train slot for
## the Explorer, and — at war — the order that opens the peace window. Its
## children arrive with T2 (#497); T1 already prices the parent so starvation is
## visible (issue #476).
static func _colonise(readings: Dictionary, at_war: bool) -> AiObjective:
	if not bool(readings.get("colony_target", false)):
		return null
	var objective := AiObjective.create(
		"colonise.new_world", "expansion", W_PROVINCES_NEW, {"hull": 1, "civilian": 1}
	)
	if at_war:
		objective.cost["orders"] = 1
	if not bool(readings.get("harbour", false)):
		objective.block("no harbour")
	elif int(readings.get("idle_hulls", 0)) <= 0 and not bool(
		readings.get("voyage_afloat", false)
	):
		objective.block("no hull free")
	return objective


## The fleet's turn: a squadron at war sorts out; a court with no hull at sea
## builds one (T5 makes the build a funded objective, #500).
static func _navy(readings: Dictionary, at_war: bool) -> AiObjective:
	if not at_war:
		return null
	var own: int = int(readings.get("ships", 0))
	var hostile: int = int(readings.get("hostile_ships", 0))
	if own <= 0:
		return AiObjective.create("navy.build", "naval", W_NAVY, {"treasury": 1, "hull": 1})
	var threat: int = AiUtility.ratio(hostile, maxi(own, 1))
	return AiObjective.create(
		"navy.sortie", "naval", AiUtility.clamp_utility(W_NAVY + threat / 2), {"hull": 1}
	)


## Merchant tonnage short of the seat's need: sail the hulls home.
static func _cargo(readings: Dictionary) -> AiObjective:
	var shortfall: int = int(readings.get("cargo_shortfall", 0))
	if shortfall <= 0:
		return null
	return AiObjective.create(
		"cargo.route", "economy", AiUtility.clamp_utility(W_CARGO + shortfall),
		{"hull": shortfall}
	)


## A study while the court has a slot to fill; the funding step is the utility.
static func _research(readings: Dictionary) -> AiObjective:
	if int(readings.get("research_slots", 0)) <= 0:
		return null
	var step: int = clampi(int(readings.get("research_funding", 0)), 0, 4)
	return AiObjective.create(
		"research.study", "research", W_RESEARCH + step * W_RESEARCH_STEP,
		{"treasury": int(readings.get("research_cost", 0))}
	)


## The standing growth aim: a crew hand on the works.
static func _economy() -> AiObjective:
	return AiObjective.create("economy.production", "economy", W_ECONOMY, {"labour": 1})
