class_name AiRandomCourt
extends RefCounted
## BENCH filler crowns: seeded random legal treasury / recruit / production /
## civilian build-develop / train actions. No diplomacy, land, or sea planners.
## MapPlayEconomyAi supplies overseas yield; this module never calls back into
## map_play (avoids class_name load cycles).

## Economy + civilian pass for one random court. Returns a faction report row.
static func economy(
	play: PlaySession,
	faction: int,
	market: WorldMarket,
	overseas: Dictionary
) -> Dictionary:
	var empty: Dictionary = {
		"extraction": {},
		"resolved": {},
		"production": {"assignments": [], "candidates": []},
		"trade": {},
		"cargo": {},
		"recruits": [],
		"civilians": {"orders": [], "moves": [], "training": []},
		"works_reserved": {},
		"research": {},
		"income": {"goal": "earn", "reserve": 0},
		"random": true,
	}
	if play == null or play.world == null or play.civilian_layer == null:
		return empty
	play.ensure_ai()
	var rng: RandomNumberGenerator = _rng(play, faction)
	var economy: PlayerEconomy = play.ai.economy_for(faction)
	MapPlayCivilianAi.seed(play, faction)
	var production: Dictionary = _random_production(economy, rng)
	var hospitals: Array[int] = HospitalRules.demand_list(play.world, faction)
	var ships: int = (
		play.ship_layer.hull_count_all(faction) if play.ship_layer != null else 0
	)
	var army_food: int = (
		play.army_layer.food_upkeep_all(faction) if play.army_layer != null else 0
	)
	var resolved: Dictionary = EconomyTurn.resolve(
		economy, market, overseas.get("extraction", {}) as Dictionary,
		ships, army_food, false, {}, hospitals, String(play.leaders.get(faction, ""))
	)
	HospitalRules.feed(
		play.world, faction,
		int((resolved.get("consumption", {}) as Dictionary).get("hospital_fed", 0))
	)
	economy.production.clear_assignments()
	for assignment: Dictionary in production["assignments"]:
		economy.production.set_assignment(String(assignment["recipe"]), int(assignment["units"]))
	var recruits: Array[Dictionary] = _random_recruits(economy, rng)
	for order: Dictionary in recruits:
		economy.recruit(int(order["tier"]))
	var civilians: Dictionary = _random_civilians(play, faction, economy, rng)
	return {
		"extraction": overseas.get("extraction", {}),
		"resolved": resolved,
		"production": production,
		"trade": {},
		"cargo": {},
		"recruits": recruits,
		"civilians": civilians,
		"works_reserved": {},
		"research": {},
		"income": {"goal": "earn", "reserve": 0},
		"random": true,
	}


static func _random_production(economy: PlayerEconomy, rng: RandomNumberGenerator) -> Dictionary:
	var assignments: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	var ids: Array[String] = []
	ids.assign(ProductionRecipes.available_ids(economy.tech_unlocked))
	if ids.is_empty():
		return {"assignments": assignments, "candidates": candidates}
	if rng.randf() < 0.35:
		return {"assignments": assignments, "candidates": candidates}
	var recipe_id: String = ids[rng.randi_range(0, ids.size() - 1)]
	var labour: int = economy.workers.labour()
	var stock: Dictionary = economy.stockpile.duplicate()
	var runs: int = ProductionRecipes.max_runs(recipe_id, stock, labour)
	if runs <= 0:
		return {"assignments": assignments, "candidates": candidates}
	var units: int = rng.randi_range(1, mini(runs, 3))
	assignments.append({"recipe": recipe_id, "units": units})
	candidates.append({"recipe": recipe_id, "assigned": units, "score": 0})
	return {"assignments": assignments, "candidates": candidates}


static func _random_recruits(economy: PlayerEconomy, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if rng.randf() < 0.4:
		return orders
	for _i in rng.randi_range(1, 2):
		var options: Array[int] = []
		for tier in WorkerPool.TIER_COUNT:
			if economy.recruit_blocked_reason(tier).is_empty():
				options.append(tier)
		if options.is_empty():
			break
		var tier: int = options[rng.randi_range(0, options.size() - 1)]
		var result: Dictionary = economy.copy().recruit(tier)
		if not bool(result.get("ok", false)):
			break
		orders.append({"tier": tier})
		economy.recruit(tier)
	return orders


static func _random_civilians(
	play: PlaySession,
	faction: int,
	economy: PlayerEconomy,
	rng: RandomNumberGenerator
) -> Dictionary:
	var report: Dictionary = {"orders": [], "moves": [], "training": []}
	for region: int in play.civilian_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		var roster: Array[CivilianState] = []
		if play.model != null and region == play.model.region_id:
			roster = play.civilian_layer.units
		else:
			roster.assign(play.civilian_layer.regions.value(region, []))
		var works: LandWorks = play.civilian_layer.works_regions.value(region, null)
		if model == null or roster.is_empty() or works == null:
			continue
		var capital: Dictionary = WorldBootstrap.capital_seat(model, faction)
		var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
		var visibility: VisibilityModel = MapPlayCourtFog.view_for(play, faction, region)
		var context: Dictionary = {
			"treasury": economy.treasury,
			"paper": economy.quantity("paper"),
			"capital_province": int(capital["province"]),
			"capital_tile": capital["tile"],
			"tech_unlocked": economy.tech_unlocked,
			"at_war": false,
			"diplomacy": play.diplomacy,
			"visibility": visibility,
		}
		for unit: CivilianState in roster:
			if unit == null or unit.owner != faction or unit.is_working():
				continue
			if rng.randf() < 0.45:
				continue
			var options: Array = CivilianWork.options(
				model, unit, works, roster, economy.stockpile, visibility, tech_caps,
				economy.tech_unlocked, context
			)
			var legal: Array[Dictionary] = []
			for raw: Variant in options:
				var row: Dictionary = raw
				if bool(row.get("ok", false)):
					legal.append(row)
			if legal.is_empty():
				continue
			var pick: Dictionary = legal[rng.randi_range(0, legal.size() - 1)]
			var action: String = String(pick.get("action", ""))
			var tile: Vector2i = unit.tile
			var result: Dictionary = CivilianWork.assign(
				model, unit, action, works, roster, economy.stockpile, visibility, tile,
				tech_caps, economy.tech_unlocked, context
			)
			if bool(result.get("ok", false)):
				report["orders"].append({
					"unit_id": unit.id, "action": action, "tile": tile, "random": true,
				})
		if rng.randf() >= 0.5 and int(capital["province"]) >= 0:
			var types: Array[String] = ["builder", "engineer", "explorer"]
			var type_id: String = types[rng.randi_range(0, types.size() - 1)]
			var hired: Dictionary = MapPlayCivilianAi._train(
				play, region, roster, faction, economy,
				{"ok": true, "type_id": type_id}, context
			)
			if not hired.is_empty():
				report["training"].append(hired)
		play.civilian_layer.regions.set_region(region, roster)
		if (
			play.model != null and region == play.model.region_id
			and play.civilian_layer.is_inside_tree()
		):
			play.civilian_layer.sync()
			play.civilian_layer.refresh_works()
	return report


static func _rng(play: PlaySession, faction: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d:random" % [play.map_seed, play.turn, faction])
	return rng
