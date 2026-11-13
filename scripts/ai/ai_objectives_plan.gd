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
##   research_slots, research_funding, research_cost,
##   tribe_target, tribe_stage, tribe_stage_cost.
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
## A court at war with no fighting hull puts the yard ahead of a sortie: it has
## nothing to sortie with (issue #484, #500).
const W_NAVY_BUILD: int = 90
## The expedition's children: the hull and the Explorer it must have, and a
## voyage already afloat, which outranks every new aim of the same court.
const W_HULL: int = 60
const W_EXPLORER: int = 60
const W_VOYAGE: int = 75
## The envoy chain that turns a charted Tribe into a colony: the next step of
## the chain, priced at its published cost and the court's one order
## (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
const W_TRIBE_COLONY: int = 55


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
	var tribe_chain: AiObjective = _tribe_chain(readings)
	if tribe_chain != null:
		objectives.append(tribe_chain)
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


## The expedition: one parent with the children that actually make it sail — the
## hull kept off the cargo routes, the Explorer mustering for the next train
## slot, the order that opens the peace window at war, and the voyage already
## afloat as a protected claim (issue #491 T2, #476).
##
## The parent carries no cost of its own: the allocator funds the children, and
## the gate that musters the Explorer reads `expedition.hull` rather than
## looking for a squadron a second time. A child that cannot be had is blocked
## with its reason, and a funded parent whose children are deferred prints the
## shortfall (e.g. `expedition.hull 0/1`).
static func _colonise(readings: Dictionary, at_war: bool) -> AiObjective:
	if not bool(readings.get("colony_target", false)):
		return null
	var parent := AiObjective.create(
		"colonise.new_world", "expansion", W_PROVINCES_NEW, {}
	)
	var afloat: bool = bool(readings.get("voyage_afloat", false))
	var abroad: bool = bool(readings.get("voyage_abroad", false))
	var under_way: bool = afloat or abroad
	var harbour: bool = bool(readings.get("harbour", false))
	var hull := AiObjective.create("expedition.hull", "naval", W_HULL, {"hull": 1})
	if not harbour:
		hull.block("no harbour")
	var explorer := AiObjective.create(
		"expedition.explorer", "civilian", W_EXPLORER, {"civilian": 1}
	)
	if not under_way and not bool(readings.get("explorer_ready", false)):
		explorer.block("no Explorer free")
	parent.with_child(hull).with_child(explorer)
	if at_war:
		# The court's one order is already claimed by `peace.window`; the voyage
		# needs that window funded, not a second order of its own.
		parent.needs("peace.window")
	if under_way:
		# Already under way — at sea or landed on the far shore: no new hull or
		# colonist, but the voyage outranks opening a second one.
		parent.with_child(AiObjective.create("expedition.voyage", "expansion", W_VOYAGE, {}))
	return parent


## The colony the court is buying: the next envoy step toward the Tribe it has
## charted, priced at the published stage cost and the court's one order. The
## aim is only a reading — `AiTribeColony` is what the diplomacy planner weighs —
## so the trace explains a rival's colonial diplomacy even on the turn it spends
## the order elsewhere (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
static func _tribe_chain(readings: Dictionary) -> AiObjective:
	var target: int = int(readings.get("tribe_target", -1))
	if target < 0:
		return null
	var aim := AiObjective.create(
		"colonise.tribe_chain", "expansion", W_TRIBE_COLONY,
		{"treasury": int(readings.get("tribe_stage_cost", 0)), "orders": 1}
	)
	return aim


## The fleet's turn: a squadron with hulls sorts out; a court with no fighting
## hull, or one outmatched on its own coast, lays one down instead. The build's
## cost is the cheapest warship its techs open (issue #491 T5, #484).
static func _navy(readings: Dictionary, at_war: bool) -> AiObjective:
	if not at_war:
		return null
	var own: int = int(readings.get("warships", 0))
	var hostile: int = int(readings.get("hostile_warships", 0))
	var threat: int = AiUtility.ratio(hostile, maxi(own + hostile, 1))
	if own <= 0:
		return AiObjective.create(
			"navy.build", "naval", W_NAVY_BUILD,
			{"treasury": int(readings.get("warship_price", 0)), "hull": 1}
		)
	if hostile > own:
		return AiObjective.create(
			"navy.build", "naval", AiUtility.clamp_utility(W_NAVY_BUILD - 20 + threat / 2),
			{"treasury": int(readings.get("warship_price", 0)), "hull": 1}
		)
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
