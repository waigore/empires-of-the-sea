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
## This file owns the entry and the expansion's weight; each family owns its
## aims and its own weights:
## - [AiObjectiveMusterPlan]: the seat's guard and the line regiment
## - [AiObjectiveWarPlan]: the court's one order (war, peace, declaration)
## - [AiObjectiveExpeditionPlan]: the expedition and the Tribe chain
## - [AiObjectiveNavyPlan]: the fleet's turn and the cargo route
## - [AiObjectiveTreasuryPlan]: the study and the deed
##
## The readings dictionary is the planner-facing contract:
##   posture, at_war, war_desire, regiments, muster_due, muster_floor,
##   escalations, blockings,
##   ships, warships, warship_price, navy_due, hostile_ships, hostile_warships,
##   treasury, reserve, goal, colony_target, harbour, idle_hulls, explorer_ready,
##   voyage_afloat, voyage_abroad, voyage_stranded, cargo_shortfall,
##   research_slots, research_funding,
##   research_cost, research_refusal, tribe_target, tribe_stage_cost,
##   tribe_closed, deed_price.
## A missing reading reads as zero/false, so a thin fixture still emits a
## coherent list.

## Bench weights the parent analysis cites: colonisation carries the largest
## per-province weight (#476, ai-bench W_PROVINCES_NEW = 50).
const W_PROVINCES_NEW: int = 50
## The line's own weight and the war increment its family lifts it by: the one
## reading the yard's waiting weight is tuned under (issue #591).
const W_MUSTER: int = 70
const W_MUSTER_WAR: int = 15
## The standing growth aim: a crew hand on the works.
const W_ECONOMY: int = 55


static func build(readings: Dictionary) -> Array[AiObjective]:
	var at_war: bool = bool(readings.get("at_war", false))
	var objectives: Array[AiObjective] = []
	objectives.append_array(AiObjectiveMusterPlan.build(readings, at_war))
	objectives.append_array(AiObjectiveWarPlan.build(readings, at_war))
	objectives.append_array(_expansion(readings, at_war))
	var navy: AiObjective = AiObjectiveNavyPlan.navy(readings, at_war)
	if navy != null:
		objectives.append(navy)
	var cargo: AiObjective = AiObjectiveNavyPlan.cargo(readings)
	if cargo != null:
		objectives.append(cargo)
	var research: AiObjective = AiObjectiveTreasuryPlan.research(readings)
	if research != null:
		objectives.append(research)
	var deed: AiObjective = AiObjectiveTreasuryPlan.deed(readings)
	if deed != null:
		objectives.append(deed)
	objectives.append(_economy())
	return objectives


## The colony the court is buying, then the Tribe chain that would found
## another: the two expansion aims, each dropped when its reading is quiet.
static func _expansion(readings: Dictionary, at_war: bool) -> Array[AiObjective]:
	var aims: Array[AiObjective] = []
	var colony: AiObjective = AiObjectiveExpeditionPlan.expedition(readings, at_war)
	if colony != null:
		aims.append(colony)
	var chain: AiObjective = AiObjectiveExpeditionPlan.tribe_chain(readings)
	if chain != null:
		aims.append(chain)
	return aims


## The standing growth aim: a crew hand on the works.
static func _economy() -> AiObjective:
	return AiObjective.create("economy.production", "economy", W_ECONOMY, {"labour": 1})
