class_name MapPlayCargoAi
extends RefCounted
## Applies a rival's cargo plan (wiki: economy-planner § Cargo;
## DR-20261110-26). `AiCargoPlanner` chooses the routes and the hull; this pass
## walks the squadrons through NavalMovement and pays the yard through FleetYard,
## so holds, treasury and movement obey the same rules as the human's orders
## (REQ-P2-03). Pure planning stays in `scripts/ai/`.

const KIND_ROUTE: String = AiCargoPlanner.KIND_ROUTE


## Walks merchant squadrons toward the seat and lays down one hull when the
## colonies' left tonnage and the court's trade holds still outrun the berths.
static func run(
	play: PlaySession, faction: int, economy: PlayerEconomy, overseas: Dictionary = {}
) -> Dictionary:
	var report: Dictionary = {
		"want": 0, "holds": 0, "routes": [], "launch": {}, "candidates": [],
	}
	if play == null or economy == null or play.ship_layer == null or play.world == null:
		return report
	var region: int = FactionCatalog.region_of(faction)
	var model: MapModel = play.world.region(region) if region >= 0 else null
	if model == null:
		return report
	var seat: int = WorldBootstrap.capital_province(model, faction)
	if seat < 0:
		return report
	var config: AiConfig = AiConfig.build(faction, play.map_seed)
	var roster: Array[FleetState] = []
	roster.assign(play.ship_layer.regions.value(region, []))
	var want: int = (
		int(overseas.get("used", 0)) + int(overseas.get("left_total", 0))
		+ maxi(config.parameter("cargo.trade_holds"), 0)
	)
	var blocked: Dictionary = _hostile_zones(play, faction, roster)
	var plan: Dictionary = AiCargoPlanner.plan(
		config, economy, model, roster, seat, want, blocked
	)
	report["want"] = int(plan["want"])
	report["holds"] = int(plan["holds"])
	report["candidates"] = plan["candidates"]
	for raw: Variant in plan["routes"]:
		var route: Dictionary = raw
		var fleet: FleetState = _fleet_by_id(roster, int(route.get("fleet_id", -1)), faction)
		if fleet == null:
			continue
		var moved: Dictionary = AiCargoPlanner.apply_route(model, fleet, route)
		if not bool(moved.get("ok", false)):
			continue
		# A rival merchant charts the water it enters for its own court
		# (wiki: fog-and-exploration; DR-20261110-23).
		if not bool(route.get("dock", false)):
			MapPlayCourtFog.note_fleet_entry(
				play, region, fleet, int(route.get("zone", -1))
			)
		report["routes"].append(route.duplicate())
	var launch: Dictionary = plan["launch"]
	if not launch.is_empty():
		var laid: Dictionary = _launch(
			play, roster, faction, economy, seat, launch
		)
		if not laid.is_empty():
			report["launch"] = laid
	# A court whose ledger funded the navy's build aim lays a fighting hull down
	# through the same yard: a rival can rebuild the fleet it lost instead of
	# only watching it shrink (issue #491 T5, #484).
	var warship: Dictionary = _build_warship(play, faction, roster, economy, seat)
	if not warship.is_empty():
		report["warship"] = warship
	play.ship_layer.regions.set_region(region, roster)
	_refresh_visible(play)
	return report


## The fighting hull the court's ledger asked for, laid down through the yard, or
## an empty row when the claim was not funded or no warship is payable.
static func _build_warship(
	play: PlaySession, faction: int, roster: Array, economy: PlayerEconomy, seat: int
) -> Dictionary:
	if play.ai == null:
		return {}
	var claim: Dictionary = play.ai.objectives_for(faction)
	if not (claim.get("funded_ids", []) as Array).has("navy.build"):
		return {}
	var type_id: String = _warship_type(economy)
	if type_id.is_empty():
		return {}
	return _launch(play, roster, faction, economy, seat, {"type_id": type_id})


## The strongest warship this court can pay for today: what its yard opens, its
## purse and stores cover, and its fields can spare a hand for. Empty when the
## court can lay nothing down.
static func _warship_type(economy: PlayerEconomy) -> String:
	var best: String = ""
	var best_strength: float = 0.0
	var peasants: int = economy.available_peasants()
	for raw: Variant in ShipEconomy.ENTRIES.keys():
		var type_id: String = String(raw)
		if not ShipStats.is_warship(type_id):
			continue
		var reason: String = ShipEconomy.blocked_reason(
			type_id, economy.treasury, economy.stockpile, peasants, economy.tech_unlocked
		)
		if not reason.is_empty():
			continue
		var strength: float = ShipStats.strength(type_id)
		if best.is_empty() or strength > best_strength:
			best = type_id
			best_strength = strength
	return best


## Paying for one hull: the slip is the crown's squadron already in port at its
## seat, or a new empty squadron founded there (the player's yard does the same).
static func _launch(
	play: PlaySession,
	roster: Array,
	faction: int,
	economy: PlayerEconomy,
	seat: int,
	order: Dictionary
) -> Dictionary:
	var type_id: String = String(order.get("type_id", ""))
	if type_id.is_empty():
		return {}
	var fleet: FleetState = _slip_fleet(roster, faction, seat)
	var founded: bool = fleet == null
	if founded:
		fleet = FleetState.empty_in_port(
			FleetRosters.next_id_all(play.ship_layer.regions), faction, seat
		)
	# A hull id already afloat at this berth is skipped, so a roster restored
	# from a save or a fixture never denies the launch (issue #491 T5).
	var hull_id: String = "ship_%d" % play.ship_layer.next_hull
	while fleet.hulls.has(hull_id):
		play.ship_layer.next_hull += 1
		hull_id = "ship_%d" % play.ship_layer.next_hull
	var result: Dictionary = FleetYard.launch(economy, fleet, type_id, hull_id)
	if not bool(result.get("ok", false)):
		return {}
	play.ship_layer.next_hull += 1
	if founded:
		roster.append(fleet)
	return {"type_id": type_id, "hull": hull_id, "founded": founded}


## Water a merchant will not enter: a zone holding a squadron its court is at
## war with. A route step into one waits for a safer turn.
static func _hostile_zones(
	play: PlaySession, faction: int, roster: Array
) -> Dictionary:
	var blocked: Dictionary = {}
	if play.diplomacy == null:
		return blocked
	for fleet: FleetState in roster:
		if fleet == null or fleet.owner == faction:
			continue
		if not fleet.is_at_sea() or not fleet.is_afloat():
			continue
		if DiplomacyRules.at_war_with(play.diplomacy, faction, fleet.owner):
			blocked[fleet.sea_zone] = true
	return blocked


static func _slip_fleet(roster: Array, owner: int, seat: int) -> FleetState:
	for fleet: FleetState in roster:
		if fleet == null or fleet.owner != owner or not fleet.is_in_port():
			continue
		if fleet.province == seat:
			return fleet
	return null


static func _fleet_by_id(roster: Array, fleet_id: int, owner: int) -> FleetState:
	for fleet: FleetState in roster:
		if fleet != null and fleet.id == fleet_id and fleet.owner == owner:
			return fleet
	return null


## Re-reads the on-screen markers after a rival moved hulls; the human's
## selection survives the rebuild when it is still in the region.
static func _refresh_visible(play: PlaySession) -> void:
	if play.ship_layer.model == null:
		return
	var selected: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	play.ship_layer.spawn(
		play.ship_layer.model, 0, 0, -1, false, play.player_faction
	)
	if selected != null:
		play.ship_layer.select(play.ship_layer.ship_for(selected))
