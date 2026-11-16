class_name MapPlayCivilianAi
extends RefCounted
## Rival civilian pass for the economy turn (docs/ai.md): seeds the opening
## roster, then runs `AiCivilianPlanner` in every region the court holds and
## applies the legal moves, works and training through the same rules the
## human's orders use (REQ-P2-03, REQ-P3-03).
##
## Split out of `MapPlayEconomyAi` so the civilian domain (units, mustering,
## training) does not share a file with extraction, market and food. Where a
## unit stands and what raising one costs is `CivilianMuster`, shared with the
## random court's own pass (REQ-P3-01).

## Rivals open with a spy, so espionage is live from turn one.
const RIVAL_STARTING_CIVILIANS: Array[String] = [
	"explorer", "builder", "engineer", "spy",
]


## Every region the player has bootstrapped gets the rival's opening civilians
## once. A rival with no capital there (a colony or the New World) gets none.
static func seed(play: PlaySession, faction: int) -> void:
	for region: int in play.civilian_layer.works_regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array = CivilianMuster.roster(play, region)
		if CivilianMuster.has_owner(roster, faction):
			continue
		var capital: Dictionary = WorldBootstrap.capital_seat(model, faction)
		if int(capital["province"]) < 0:
			continue
		for type_id: String in RIVAL_STARTING_CIVILIANS:
			var tile: Vector2i = CivilianMuster.mustering_tile(
				model, int(capital["province"]), roster
			)
			if tile.x < 0:
				break
			CivilianMuster.append_unit(play, region, roster, faction, type_id, tile)
		play.civilian_layer.regions.set_region(region, roster)


## One planning pass over every region this court holds, priced on `stockpile`
## and applying nothing. The economy turn plans the works before the market
## stages its sale, so the feedstock a crew will spend is known in advance and
## can be kept back (wiki: economy-planner § Reservations — one stockpile serves
## build, work and trade); the same plans are applied once the ledger closes. An
## overseas region is priced on the raw its holds actually landed.
static func plan_all(
	play: PlaySession, faction: int, economy: PlayerEconomy, config: Variant,
	overseas: Dictionary = {}, stockpile: Dictionary = {}, floor: int = 0,
	works_floor: int = -1
) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	var kind: String = AiControl.court_kind(play, faction)
	# The cash a crew may spend is what the purse carries after the court's own
	# floor and, at war and short of its target, the muster it is saving for:
	# training and deeds are discretionary, the war chest is not (wiki:
	# growth-stage-planner § Recruitment modulation; treasury-planner
	# § Cash discipline; issue #474).
	var purses: Dictionary = purses_for(economy.treasury, floor, works_floor)
	var spendable: int = int(purses["spendable"])
	var works_cash: int = int(purses["works"])
	var earn: bool = bool(purses["earn"])
	# The court's war footing, read once for every region: a court at war hires
	# no expansion crew (DR-20261116-15). The baseline planners ignore the key.
	var posture: String = AiBind.phase_for(kind, config, play.diplomacy)
	for region: int in play.civilian_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		var roster: Array[CivilianState] = CivilianMuster.roster(play, region)
		var works: LandWorks = play.civilian_layer.works_regions.value(region, null)
		if model == null or roster.is_empty() or works == null:
			continue
		var capital: Dictionary = WorldBootstrap.capital_seat(model, faction)
		var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
		var context: Dictionary = {
			"treasury": works_cash,
			"hire_treasury": spendable,
			"earn": earn,
			"paper": economy.quantity("paper"),
			"capital_province": int(capital["province"]),
			"capital_tile": capital["tile"],
			"tech_unlocked": economy.tech_unlocked,
			"at_war": MapPlayCourt.at_war(play, faction), "diplomacy": play.diplomacy,
			"phase": posture,
			"visibility": MapPlayCourtFog.view_for(play, faction, region),
		}
		var muster: Vector2i = CivilianMuster.muster_port(play, faction, region, model)
		if muster.x >= 0:
			context["muster_port"] = muster
		if region != int(overseas.get("home_region", region)):
			context["delivered_raw"] = (overseas.get("by_province", {}) as Dictionary).get(region, {})
		# The larder slack the ward gate reads and the provision premium
		# follows: the harvest this turn landed less every mouth the
		# consumption phase feeds; the economy pass noted it. No reading keeps
		# the old reading. A muster due with the slack at or under zero leads
		# the Builders to the ration estates, so the food income for the army
		# the court desires is provisioned before that army is raised (#807).
		if play.ai != null and play.ai.food_slack.has(faction):
			context["larder_slack"] = int(play.ai.food_slack[faction])
			if (
				int(context["larder_slack"]) <= 0
				and AiArmyReinforce.muster_floor(
					config, economy, MapPlayCourt.regiments(play, faction),
					MapPlayCourt.at_war(play, faction)
				) > 0
			):
				context["provision_food"] = true
		var plan: Dictionary = AiBind.civilian_plan(
			kind, config, model, roster, works, stockpile, tech_caps,
			economy.tech_unlocked, context
		)
		if earn:
			keep_extraction(plan, model)
		price(plan["orders"], model, works)
		plans.append({
			"region": region,
			"model": model,
			"roster": roster,
			"works": works,
			"tech_caps": tech_caps,
			"context": context,
			"plan": plan,
		})
	return plans


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


## The material row a planned work will be charged when it is assigned, read from
## the same two rules the assignment itself reads, so the row the market keeps
## back is the row the crew pays (wiki: civilian-units § Work Order Summary).
static func price(orders: Array, model: MapModel, works: LandWorks) -> void:
	for raw: Variant in orders:
		var order: Dictionary = raw
		var action: String = String(order.get("action", ""))
		var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
		order["cost"] = CivilianWork.cost_for(
			action, CivilianWork.cost_level(action, model, tile, works)
		)


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


## Applies what `plan_all` decided: the moves, the work orders (paid through the
## same rules a crown's own orders use) and the next civilian to train.
static func apply(
	play: PlaySession, faction: int, economy: PlayerEconomy, plans: Array[Dictionary]
) -> Dictionary:
	var report: Dictionary = {
		"orders": [], "moves": [], "training": [], "training_blocked": "",
	}
	for entry: Dictionary in plans:
		var region: int = int(entry["region"])
		var model: MapModel = entry["model"]
		var roster: Array = entry["roster"]
		var works: LandWorks = entry["works"]
		var tech_caps: Dictionary = entry["tech_caps"]
		var context: Dictionary = entry["context"]
		var plan: Dictionary = entry["plan"]
		for move: Dictionary in plan["moves"]:
			var unit: CivilianState = CivilianMuster.unit_by_id(roster, int(move["unit_id"]))
			if unit != null:
				var view: VisibilityModel = context["visibility"]
				CivilianMovement.apply_move(model, unit, move["tile"], view)
				report["moves"].append(move)
		for order: Dictionary in plan["orders"]:
			var unit: CivilianState = CivilianMuster.unit_by_id(roster, int(order["unit_id"]))
			if unit == null:
				continue
			var result: Dictionary = CivilianWork.assign(
				model, unit, String(order["action"]), works, roster,
				economy.stockpile, context["visibility"], order["tile"], tech_caps,
				economy.tech_unlocked, context
			)
			if bool(result.get("ok", false)):
				report["orders"].append(order)
		var training: Dictionary = plan["training"]
		if bool(training.get("ok", false)):
			var hired: Dictionary = CivilianMuster.train(
				play, region, roster, faction, economy, training, context
			)
			if not hired.is_empty():
				# Whether the court's own archetype asked for this crew, or the
				# region's work did: the trace names which (AiStaffTaste).
				hired["taste"] = bool(training.get("taste", false))
				report["training"].append(hired)
		# A hire the footing held shut names why (REQ-P5-05).
		report["training_blocked"] = String(
			training.get("reason", report["training_blocked"])
		)
		play.civilian_layer.regions.set_region(region, roster)
		if (
			MapPlayTurn.view_live
			and play.model != null and region == play.model.region_id
			and play.civilian_layer.is_inside_tree()
		):
			play.civilian_layer.sync()
			play.civilian_layer.refresh_works()
	return report
