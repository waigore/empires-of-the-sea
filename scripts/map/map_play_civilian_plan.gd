class_name MapPlayCivilianPlan
extends RefCounted
## What one civilian pass reads before it plans, and what a short purse does to
## the plan: the court's two purses and footing, a region's planner context, the
## trim `earn` makes and the material row the planned works will pay (docs/ai.md;
## REQ-P2-03, REQ-P3-03).
##
## Split out of `MapPlayCivilianAi` so that file stays the seed/plan/apply loop
## and this one owns the court's reading and the plan's shaping (REQ-P3-01).
## Nothing here orders or spends: pricing is the same arithmetic `CivilianWork`
## charges, and a trim only drops orders the purse cannot pay.

## The two purses a crew reads. A hire may spend what the standing reserve
## leaves; the works may spend down to the cash floor when the court is on
## `earn`, because extraction is what refills the store the muster is saved for
## (wiki: ai-architecture § Money first; issue #489). `works_floor` below zero
## keeps both purses on the standing reserve.
static func purses_for(treasury: int, floor: int, works_floor: int) -> Dictionary:
	var spendable: int = int(AiClaims.purse(treasury, floor).get("treasury", 0))
	if works_floor < 0:
		return {"spendable": spendable, "works": spendable, "earn": false}
	return {
		"spendable": spendable,
		"works": int(AiClaims.purse(treasury, works_floor).get("treasury", 0)),
		"earn": true,
	}


## The footing, the purses and the win-bar latch every region of one court
## reads: the war footing is read once, not once per region (DR-20261116-15).
static func court_context(
	play: PlaySession, faction: int, economy: PlayerEconomy, config: Variant,
	kind: String, purses: Dictionary, conquest_bank: bool
) -> Dictionary:
	return {
		"config": config,
		"kind": kind,
		"posture": AiBind.phase_for(kind, config, play.diplomacy),
		"spendable": int(purses["spendable"]),
		"works_cash": int(purses["works"]),
		"earn": bool(purses["earn"]),
		"at_war": MapPlayCourt.at_war(play, faction),
		"conquest_bank": conquest_bank,
	}


## One region's planner context: where its capital and muster stand, whether a
## voyage waits for its crew, the raw an overseas hold landed, and the larder
## slack the ward gate reads (wiki: economy-planner § Reservations; issue #807,
## #894, #995).
static func region_context(
	play: PlaySession, faction: int, economy: PlayerEconomy, region: int,
	model: MapModel, roster: Array[CivilianState], court: Dictionary,
	overseas: Dictionary = {}
) -> Dictionary:
	var capital: Dictionary = WorldBootstrap.capital_seat(model, faction)
	var context: Dictionary = {
		"treasury": int(court["works_cash"]),
		"hire_treasury": int(court["spendable"]),
		"earn": bool(court["earn"]),
		"paper": economy.quantity("paper"),
		"capital_province": int(capital["province"]),
		"capital_tile": capital["tile"],
		"tech_unlocked": economy.tech_unlocked,
		"at_war": bool(court["at_war"]), "diplomacy": play.diplomacy,
		"phase": String(court["posture"]),
		"visibility": MapPlayCourtFog.view_for(play, faction, region),
	}
	var muster: Vector2i = CivilianMuster.muster_port(play, faction, region, model)
	if play.world != null and region == FactionCatalog.region_of(faction):
		# The crew the next voyage across the water will carry — an Explorer
		# while the crown holds no ground there, a Merchant once that Explorer
		# has landed (#1127). Stamped before the muster so the hire order can
		# raise a claim crew even on a turn the harbour has no hull to spare.
		context["voyage_crew_kind"] = CivilianMuster.voyage_kind(play, faction, region)
		# The stranded-voyage read the claim crew's carve-out rides (issue
		# #1139): the expedition the court paid for is ashore with no crown
		# land, so its claim still has a step the hire ladder must keep open.
		context["voyage_stranded"] = MapPlayObjectiveVoyage.claim_stranded(
			play, faction
		)
		# The deed the court is saving toward: the cheapest priced, openable
		# resource tile, so the deed Merchant's carve-out (#1135) reads the
		# same purchase the ledger's `market.deed` aim funds.
		var deed: Dictionary = AiMerchantWork.openable_deed(
			model, faction,
			{
				"diplomacy": play.diplomacy,
				"visibility": MapPlayCourtFog.view_for(play, faction, region),
				"treasury": int(court["spendable"]),
			}
		)
		context["deed_price"] = int(deed.get("price", 0))
	if muster.x >= 0:
		context["muster_port"] = muster
		# Only the crew the voyage will board waits at the harbour; the crown's
		# other crews keep working the home ground (issue #894).
		context["muster_unit"] = CivilianMuster.muster_colonist(
			roster, faction, String(context.get("voyage_crew_kind", "explorer"))
		)
	# A court whose last Explorer would sail with the voyage takes the second
	# crew first, so the colony leaves a prospector behind (#894).
	if CivilianMuster.needs_voyage_crew(play, faction, region, model):
		context["voyage_crew"] = true
	if region != int(overseas.get("home_region", region)):
		context["delivered_raw"] = (
			overseas.get("by_province", {}) as Dictionary
		).get(region, {})
	_note_larder(play, faction, economy, context, court)
	return context


## The larder slack the ward gate reads and the provision premium follows: the
## harvest this turn landed less every mouth the consumption phase feeds. No
## reading keeps the old reading. A muster due with the slack at or under zero
## leads the Builders to the ration estates, so the food income for the army the
## court desires is provisioned before that army is raised (#807).
##
## The conquest bank latches the same premium (issue #995): a court short of the
## bar banking for its host desires that army already. The bank provisions the
## army it means to buy.
static func _note_larder(
	play: PlaySession, faction: int, economy: PlayerEconomy, context: Dictionary,
	court: Dictionary
) -> void:
	if play.ai == null or not play.ai.food_slack.has(faction):
		return
	var slack: int = int(play.ai.food_slack[faction])
	context["larder_slack"] = slack
	# The provision premium is the submission surface's own reading: a baseline
	# court's MainlineAiConfig must never reach the typed signature, and its
	# planners keep their published market (the same guard
	# `AiBindEconomy.fed_slack` uses for the muster's own reading).
	if String(court["kind"]) == AiControl.KIND_BASELINE:
		return
	if slack > 0 or not _wants_army(play, faction, economy, court):
		return
	context["provision_food"] = true


## The court is saving for a line the pool cannot carry: a muster due, or the
## win-bar bank's own latch.
static func _wants_army(
	play: PlaySession, faction: int, economy: PlayerEconomy, court: Dictionary
) -> bool:
	if bool(court["conquest_bank"]):
		return true
	return AiArmyReinforce.muster_floor(
		court["config"], economy, MapPlayCourt.regiments(play, faction),
		bool(court["at_war"])
	) > 0


## The crop rows a conquest bank keeps working (issue #995): the food the
## court's own mouths eat, plus the raw sources — transitively, through every
## refinement hop — of the row of the line the court is saving for: the levy's
## cloth is wool woven, the regular's cast iron is ore smelted, the musket's
## steel is that ore smelted twice. A court with no line to save for, or a
## caller with no registry to read, keeps the food alone.
static func bank_crops(config: Variant, economy: PlayerEconomy) -> Array:
	var crops: Array = []
	crops.assign(CommodityCatalog.FOOD)
	if config == null or economy == null:
		return crops
	var type_id: String = AiArmyReinforce.saving_type(config, economy)
	if type_id.is_empty():
		return crops
	var wanted: Array = []
	for commodity: Variant in RegimentEconomy.training_inputs(type_id).keys():
		var id: String = String(commodity)
		wanted.append(id)
		if not crops.has(id):
			crops.append(id)
	# Walk every refinement hop: each row commodity is kept, and so is every
	# raw one of its recipes, until no new source opens.
	for _hop in 3:
		var opened: Array = []
		for commodity: String in wanted:
			for raw: String in ProductionRecipes.raw_sources(commodity):
				if not crops.has(raw) and not opened.has(raw):
					opened.append(raw)
		if opened.is_empty():
			break
		for raw: String in opened:
			crops.append(raw)
			wanted.append(raw)
	return crops


## A plan on `earn` keeps only what refills the store: extraction and surveys,
## or the conquest bank's farms and the farm line's own feedstock, with the one
## road that puts an off-network town on the crown's network (issue #489, #995).
static func trim_to_purse(
	plan: Dictionary, model: MapModel, works: LandWorks, faction: int,
	capital_tile: Vector2i, crops: Array, conquest_bank: bool
) -> void:
	if not conquest_bank:
		keep_extraction(plan, model)
		return
	keep_bank_works(
		plan, model, crops,
		AiTownRoads.steps(
			model, works, faction,
			ImprovementSystem.connected_tiles(model, works, faction, capital_tile)
		)
	)


## On `earn` only extraction is funded from the cash floor: a court that cannot
## pay its next commitment still works the resources that refill the store, and
## leaves the town levels, roads and ports for the turn it can pay for them
## (issue #489).
static func keep_extraction(plan: Dictionary, model: MapModel) -> void:
	var kept: Array[Dictionary] = []
	for raw: Variant in plan.get("orders", []):
		var order: Dictionary = raw
		# A survey comes first: the deposit is hidden until the Explorer digs, so
		# a prospect order never names the resource it is looking for and must
		# not be read as a town level or a road. Dropping it left every rival
		# with an idle Explorer for the whole campaign — and a mine is the only
		# income a court has apart from sales (wiki: fog-and-exploration
		# § Prospecting; issue #489).
		if String(order.get("action", "")) == "prospect":
			kept.append(order)
			continue
		var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
		if tile.x < 0 or model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
			continue
		kept.append(order)
	plan["orders"] = kept


## The conquest bank's trim (issue #995): while a court short of the bar banks
## for its next line, the farms and the line's own feedstock keep — the ration
## estates that feed the mouths the army has, the wool and the iron the
## pattern it saves for are woven and cast into, and the prospecting that
## opens a paying tile. The other estates wait with the towns and ports: their
## lumber and cast iron are the stock the sale needs, and the estate engine
## they feed is the engine that never armed the court (issue #995; the France
## reading on the same bench — the court that sold its raw won; the estate
## court parked). The food claims and the lock-recovery purchases still keep
## the larder fed, so a fed court stays fed (#807).
##
## `town_roads` is the town-link step set (`AiTownRoads.steps`): those roads
## keep too. A province's estates pay only once its town reaches the capital
## under the Town rule, and a Builder prices an off-network raise on the
## promise that the engineer's road follows — a promise this trim used to break
## by waiting the roads with the towns, so a farm the bank raised on a province
## whose town stood off the network gathered nothing. One road pays a whole
## province, which is the bank's own provisioning, exactly like the farmhand
## hire. An order on the tile of a crop the bank already keeps keeps as it is:
## that estate's own link is its provisioning too.
static func keep_bank_works(
	plan: Dictionary, model: MapModel, crops: Array, town_roads: Dictionary = {}
) -> void:
	var kept: Array[Dictionary] = []
	for raw: Variant in plan.get("orders", []):
		var order: Dictionary = raw
		if String(order.get("action", "")) == "prospect":
			kept.append(order)
			continue
		var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
		if tile.x < 0:
			continue
		if town_roads.has(tile):
			kept.append(order)
			continue
		var resource: int = model.resource_at(tile.x, tile.y)
		if resource != MapModel.NO_ID and crops.has(
			ImprovementCatalog.commodity(resource)
		):
			kept.append(order)
	plan["orders"] = kept


## The material row a planned work will be charged when it is assigned, read from
## the same two rules the assignment itself reads, so the row the market keeps
## back is the row the crew pays (wiki: civilian-units § Work Order Summary).
## Prices the orders the pass planned: the same cost maths the assignment
## charges, with the H8 feedstock bootstrap read against the ledger the works
## were planned against, so a waived raise reserves no material it will not
## spend (wiki: extraction-and-improvements § H8 feedstock bootstrap; #878).
static func price(
	orders: Array, model: MapModel, works: LandWorks, stockpile: Dictionary = {}
) -> void:
	for raw: Variant in orders:
		var order: Dictionary = raw
		var action: String = String(order.get("action", ""))
		var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
		var level: int = CivilianWork.cost_level(action, model, tile, works)
		var cost: Dictionary = CivilianWork.cost_for(action, level)
		if action == "build_improvement":
			cost = CivilianWorkPlan.bootstrap_cost(model, tile, stockpile, level)
		order["cost"] = cost


## The material rows the planned works will be charged, read ahead of the sale
## they must survive (wiki: economy-planner § Reservations). Training's paper is
## a separate claim and stays with the ledger.
static func work_rows(plans: Array[Dictionary]) -> Dictionary:
	var rows: Dictionary = {}
	for entry: Dictionary in plans:
		var plan: Dictionary = entry.get("plan", {})
		for raw: Variant in plan.get("orders", []):
			var order: Dictionary = raw
			var cost: Dictionary = order.get("cost", {})
			for commodity: Variant in cost.keys():
				var id: String = String(commodity)
				var amount: int = int(cost[commodity])
				if amount > 0:
					rows[id] = int(rows.get(id, 0)) + amount
	return rows
