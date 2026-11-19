class_name MapPlayCivilianAi
extends RefCounted
## Rival civilian pass for the economy turn (docs/ai.md): seeds the opening
## roster, then runs `AiCivilianPlanner` in every region the court holds and
## applies the legal moves, works and training through the same rules the
## human's orders use (REQ-P2-03, REQ-P3-03).
##
## This file is the pass: who plans, what is granted and what the report keeps.
## What the pass *reads* before it plans — the court's purses and footing, a
## region's planner context, the trim `earn` makes and the material row the
## planned works will pay — is [MapPlayCivilianPlan]'s one home (REQ-P3-01).
## Where a unit stands and what raising one costs is `CivilianMuster`, shared
## with the random court's own pass.

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
##
## `conquest_bank` is the win-bar reading (issue #995): a court short of the
## bar with an army still under target banks for its next line on `earn`, and
## its optional works wait — the farms and the prospecting keep, and the raw
## the land lands sells, so the purse fills at the sale rate instead of
## feeding the estate engine that never arms it.
static func plan_all(
	play: PlaySession, faction: int, economy: PlayerEconomy, config: Variant,
	overseas: Dictionary = {}, stockpile: Dictionary = {}, floor: int = 0,
	works_floor: int = -1, conquest_bank: bool = false
) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	var kind: String = AiControl.court_kind(play, faction)
	# The cash a crew may spend is what the purse carries after the court's own
	# floor and, at war and short of its target, the muster it is saving for:
	# training and deeds are discretionary, the war chest is not (wiki:
	# growth-stage-planner § Recruitment modulation; treasury-planner
	# § Cash discipline; issue #474).
	var court: Dictionary = MapPlayCivilianPlan.court_context(
		play, faction, economy, config, kind,
		MapPlayCivilianPlan.purses_for(economy.treasury, floor, works_floor),
		conquest_bank
	)
	var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
	# The bank's crop rows are read once, not once per region.
	var crops: Array = (
		MapPlayCivilianPlan.bank_crops(config, economy)
		if bool(court["earn"]) and conquest_bank else []
	)
	for region: int in play.civilian_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		var roster: Array[CivilianState] = CivilianMuster.roster(play, region)
		var works: LandWorks = play.civilian_layer.works_regions.value(region, null)
		if model == null or roster.is_empty() or works == null:
			continue
		var context: Dictionary = MapPlayCivilianPlan.region_context(
			play, faction, economy, region, model, roster, court, overseas
		)
		# The bank the hire ladder honors (issue #1059): the crews the farms
		# and their roads need keep the works purse, the rest of the college
		# stands behind the chest. Scoped to the submission surface: a
		# baseline court's config never reaches the typed reads, and its
		# published hire order keeps its published purses.
		if conquest_bank and kind != AiControl.KIND_BASELINE:
			context["conquest_bank"] = true
		var plan: Dictionary = AiBindCampaign.civilian_plan(
			kind, config, model, roster, works, stockpile, tech_caps,
			economy.tech_unlocked, context
		)
		if bool(court["earn"]):
			MapPlayCivilianPlan.trim_to_purse(
				plan, model, works, faction, context["capital_tile"], crops,
				conquest_bank
			)
		MapPlayCivilianPlan.price(plan["orders"], model, works, stockpile)
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
