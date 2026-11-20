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
## The same yard, while the court cannot yet fill its chest and a regiment is
## due: below the muster's 85 (`W_MUSTER` + `W_MUSTER_WAR`), so the ledger funds
## the line first and the hull it never reaches stops starving the army
## (issue #591).
const W_NAVY_BUILD_WAITING: int = 80
## The expedition's children: the hull and the Explorer it must have, and a
## voyage already afloat, which outranks every new aim of the same court.
const W_HULL: int = 60
const W_EXPLORER: int = 60
const W_VOYAGE: int = 75
## The envoy chain that turns a charted Tribe into a colony: the next step of
## the chain, priced at its published cost and the court's one order
## (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
const W_TRIBE_COLONY: int = 55
## The deed the court is saving toward: the cheapest Minor or Tribe resource
## tile it could sign at the published 15 x base price. Ranked below every other
## treasury claim, so the aim names the intent without taking the purse the
## muster, the yard or a study is saving for (issue #724 task 3).
const W_DEED: int = 40


static func build(readings: Dictionary) -> Array[AiObjective]:
	var objectives: Array[AiObjective] = []
	var at_war: bool = bool(readings.get("at_war", false))
	objectives.append(_defend(readings, at_war))
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
	var deed: AiObjective = _deed(readings)
	if deed != null:
		objectives.append(deed)
	objectives.append(_economy())
	return objectives


## The seat held: at war every court keeps a regiment home, at peace it is a
## standing aim worth little next to growth. While a line is due the guard
## claims nothing — the muster's regiment *is* the Home Army, and a phantom
## slot claim at 90 held the muster's own claim shut every warring turn
## (issue #807, the #474 clause-1 un-latch; evidence/issue-766).
static func _defend(readings: Dictionary, at_war: bool) -> AiObjective:
	var due: bool = bool(readings.get("muster_due", false))
	var cost: Dictionary = (
		{"regiment": 1} if at_war and not due else {}
	)
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
	# The purse it must leave behind plus the material row of the pattern it is
	# saving for: the planner refuses a muster short of that cloth (#474), so a
	# row priced on the purse alone would read `funded` for a regiment the court
	# cannot raise — and clear the very stall the escalation counts (#603).
	var cost: Dictionary = {
		"regiment": 1, "labour": 1, "treasury": int(readings.get("muster_floor", 0)),
	}
	for commodity: Variant in (readings.get("muster_row", {}) as Dictionary).keys():
		var id: String = String(commodity)
		var need: int = int((readings["muster_row"] as Dictionary)[commodity])
		if need > 0:
			cost[id] = int(cost.get(id, 0)) + need
	var muster := AiObjective.create("muster.line", "military", utility, cost)
	# The escalation's explicit terminal reading (#603): a muster that has been
	# deferred past the blocked bar with its shortfall standing still names it,
	# instead of another silent deferred row. The reserve re-route stays the
	# escalation's acting lever; this row only says so in the trace.
	var blocked_turns: int = int(
		(readings.get("blockings", {}) as Dictionary).get("muster.line", 0)
	)
	if blocked_turns > 0:
		muster.block("muster out of reach %d turns" % blocked_turns)
	return muster


## The court's one order a turn: press a war, open one, or spend it ending the
## war that blocks everything else (the peace window T2 funds, #497). An aim
## that has lost the order to its sibling for the escalation bar's turns reads
## `blocked` with the sibling's name — the contention, said out loud once the
## stall is long (issue #603).
static func _diplomacy(readings: Dictionary, at_war: bool) -> Array[AiObjective]:
	var desire: int = clampi(int(readings.get("war_desire", 0)), 0, 100)
	var blockings: Dictionary = readings.get("blockings", {})
	var orders: Array[AiObjective] = []
	if at_war:
		var press := AiObjective.create("war.press", "diplomacy", desire, {"orders": 1})
		var window := AiObjective.create(
			"peace.window", "diplomacy", 100 - desire, {"orders": 1}
		)
		var press_stall: int = int(blockings.get("war.press", 0))
		var window_stall: int = int(blockings.get("peace.window", 0))
		# The sibling that has been losing the order names why it waits.
		if window_stall > 0 and desire >= 50:
			window.block("the court presses its war (%d turns)" % window_stall)
		elif press_stall > 0 and desire < 50:
			press.block("the court sues for peace (%d turns)" % press_stall)
		orders.append(press)
		orders.append(window)
		return orders
	var declare := AiObjective.create("war.declare", "diplomacy", desire, {"orders": 1})
	var declare_stall: int = int(blockings.get("war.declare", 0))
	if declare_stall > 0:
		declare.block("the court does not want this war (%d turns)" % declare_stall)
	orders.append(declare)
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
	# A colonist ashore where the crown owns no land neither founds a province
	# nor boards again (docking needs a crown port), so no voyage can be sailed:
	# the aim says why instead of funding a sailing it cannot order (issue #602).
	# The Explorer is not idle — the civilian planner keeps it on the far shore's
	# chart — but the expedition is over, not under way.
	if bool(readings.get("voyage_stranded", false)):
		return parent.block("the Explorer is ashore with no crown land")
	var under_way: bool = afloat or abroad
	var harbour: bool = bool(readings.get("harbour", false))
	var hull := AiObjective.create("expedition.hull", "naval", W_HULL, {"hull": 1})
	if not harbour:
		hull.block("no harbour")
	else:
		# A long wait for an idle hull is a contention, said out loud once the
		# stall is long (issue #603): the fleet is committed elsewhere.
		var hull_stall: int = int(
			(readings.get("blockings", {}) as Dictionary).get("expedition.hull", 0)
		)
		if hull_stall > 0:
			hull.block("no idle hull %d turns" % hull_stall)
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
		# A footing that holds the slot shut still names the aim it closed, so
		# the trace reads why the court is buying no colony this turn instead of
		# the row simply vanishing (DR-20261116-11, REQ-P5-05).
		var closed: String = String(readings.get("tribe_closed", ""))
		if closed.is_empty():
			return null
		return AiObjective.create(
			"colonise.tribe_chain", "expansion", W_TRIBE_COLONY
		).block(closed)
	var aim := AiObjective.create(
		"colonise.tribe_chain", "expansion", W_TRIBE_COLONY,
		{"treasury": int(readings.get("tribe_stage_cost", 0)), "orders": 1}
	)
	return aim


## The fleet's turn: a squadron with hulls sorts out; a court with no fighting
## hull (peace or war), or one outmatched on its own coast, lays one down. The
## build claims the yard's treasury row; a chest not yet reached ranks below the
## muster (issue #491 T5, #484, #591).
static func _navy(readings: Dictionary, at_war: bool) -> AiObjective:
	var own: int = int(readings.get("warships", 0))
	var hostile: int = int(readings.get("hostile_warships", 0))
	var threat: int = AiUtility.ratio(hostile, maxi(own + hostile, 1))
	if AiNavy.due(at_war, own, hostile):
		var utility: int = W_NAVY_BUILD
		if own > 0:
			utility = AiUtility.clamp_utility(W_NAVY_BUILD - 20 + threat / 2)
		# A chest the court has not reached waits behind the army: the yard is
		# still its aim, but a yard price it cannot pay must not claim the purse
		# the muster needs, or the hull is never laid and the line never rises
		# (issue #591).
		if _chest_beyond_reach(readings):
			utility = mini(utility, W_NAVY_BUILD_WAITING)
		var build := AiObjective.create(
			"navy.build", "naval", utility, _build_cost(readings)
		)
		# The yard founds a slip of its own, so the build asks for the treasury
		# row and the hull's material row — the chest the money goal reserves and
		# the cloth the economy reserves, so the launch is never funded into a
		# store the court already sold (issue #484). A court still studying the
		# unlock keeps that chest but does not claim a launch it cannot lay.
		if not bool(readings.get("warship_open", false)):
			build.block("no warship its techs open")
		elif int(readings.get("warship_hands", ShipEconomy.WORKER_COST)) \
				< ShipEconomy.WORKER_COST:
			# One peasant leaves the pool at launch: a court with no free hand
			# funds no hull the yard would refuse (issue #1126).
			build.block("no free hand for the slip")
		else:
			# A yard the court has stalled on for the blocked bar's turns names
			# it — the chest stays out of reach and the trace says so instead
			# of another silent deferred row (issue #603). The yard's own gate
			# rides in the same words, so a court that cannot lay the hull it
			# funds reads why instead of banking the chest again (issue #1126).
			var yard_stall: int = int(
				(readings.get("blockings", {}) as Dictionary).get("navy.build", 0)
			)
			if yard_stall > 0:
				var gate: String = String(readings.get("warship_refusal", ""))
				build.block(
					"the yard is out of reach %d turns" % yard_stall
					if gate.is_empty()
					else "the yard is out of reach %d turns (%s)" % [yard_stall, gate]
				)
		return build
	if not at_war:
		return null
	return AiObjective.create(
		"navy.sortie", "naval", AiUtility.clamp_utility(W_NAVY + threat / 2), {"hull": 1}
	)


## True while the court is still short of the yard's price and a regiment is
## due: the chest it means to fill is out of reach, so the army's claim outranks
## it (issue #591, `AiIncome.hull_held`). A fleetless court keeps the yard ahead
## of the muster — the same own-warships gate as `hull_held` (issue #484).
static func _chest_beyond_reach(readings: Dictionary) -> bool:
	if int(readings.get("warships", -1)) == 0:
		return false
	if not bool(readings.get("muster_due", false)):
		return false
	var price: int = int(readings.get("warship_price", 0))
	return price > 0 and int(readings.get("treasury", 0)) < price


## Treasury claim only: cloth stays on `AiClaims.NAVY` so the objective does not
## double-book the bolt the market already held (issue #484). The hand the yard
## takes at launch is a gate, not a claim — reading it out of the shared labour
## pool would starve the production run ranked under it (issue #1126).
static func _build_cost(readings: Dictionary) -> Dictionary:
	return {"treasury": int(readings.get("warship_price", 0))}



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
## The standing study prices its own one-slot budget (the bounded exception
## that may dip into the chest the muster claims); a study the purse cannot
## fund this turn is `blocked` with the refusal the planner made — never a
## 0-gold row that reads `funded` while the court learns nothing (issue #590).
static func _research(readings: Dictionary) -> AiObjective:
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


## The standing growth aim: a crew hand on the works.
static func _economy() -> AiObjective:
	return AiObjective.create("economy.production", "economy", W_ECONOMY, {"labour": 1})


## The deed the court is saving toward: the cheapest Minor or Tribe resource
## tile it could sign at the published 15 x base price, priced on the purse it
## must hold. The aim is a reading — the Merchant's own order is what signs the
## deed — but it is the row the deferred-aim escalation tracks, so a court that
## never reaches the price reads `blocked` with the stall named instead of
## saving in silence (issue #724 task 3, #603).
static func _deed(readings: Dictionary) -> AiObjective:
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
