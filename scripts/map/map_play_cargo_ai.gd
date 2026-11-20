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
	var kind: String = AiControl.court_kind(play, faction)
	if kind == AiControl.KIND_RANDOM:
		return report
	var config: Variant = AiBind.config(kind, faction, play.map_seed, play.ensure_ai().profiles)
	var roster: Array[FleetState] = MapPlayCourt.region_fleets(play, region)
	var want: int = (
		int(overseas.get("used", 0)) + int(overseas.get("left_total", 0))
		+ maxi(int(config.parameter("cargo.trade_holds")), 0)
	)
	var blocked: Dictionary = _hostile_zones(play, faction, roster)
	var plan: Dictionary = AiBindCampaign.cargo_plan(
		kind, config, economy, model, roster, seat, want, blocked
	)
	report["want"] = int(plan["want"])
	report["holds"] = int(plan["holds"])
	report["candidates"] = plan["candidates"]
	for raw: Variant in plan["routes"]:
		var route: Dictionary = raw
		var fleet: FleetState = MapPlayCourt.fleet_by_id(
			roster, int(route.get("fleet_id", -1)), faction
		)
		if fleet == null:
			continue
		var moved: Dictionary = AiBindCampaign.cargo_apply_route(kind, model, fleet, route)
		if not bool(moved.get("ok", false)):
			continue
		# A route that ends at the crown's own seat folds into the home fleet as
		# it docks, never a turn later (wiki: ships-and-naval § Home Fleet).
		if bool(route.get("dock", false)):
			MapPlayHomeMerge.fold(play, model, roster, fleet)
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
		if bool(laid.get("ok", false)):
			report["launch"] = laid
	# A court whose ledger funded the navy's build aim lays a fighting hull down
	# through the same yard: a rival can rebuild the fleet it lost instead of
	# only watching it shrink (issue #491 T5, #484). A funded claim the yard
	# refuses names the gate instead of banking the chest in silence (#1126).
	var warship: Dictionary = _build_warship(play, faction, roster, economy, seat)
	if not warship.is_empty():
		if warship.has("refused"):
			report["warship_refused"] = warship
		else:
			report["warship"] = warship
	play.ship_layer.regions.set_region(region, roster)
	MapPlayCourt.refresh_hulls(play)
	return report


## The fighting hull the court's ledger asked for, laid down through the yard.
## The row carries the yard's price and the chest the court held for it, so the
## turn trace explains what allowed the launch (issue #484). A claim the yard
## refuses comes back as `{"refused": <the gate's words>}` instead: the trace
## names what held the hull back, so the court is not left banking the chest and
## the cloth again in silence (issue #1126).
static func _build_warship(
	play: PlaySession, faction: int, roster: Array, economy: PlayerEconomy, seat: int
) -> Dictionary:
	if play.ai == null:
		return {}
	var claim: Dictionary = play.ai.objectives_for(faction)
	if not (claim.get("funded_ids", []) as Array).has("navy.build"):
		return {}
	var flown: Array[String] = MapPlayCourt.hull_types(play, faction)
	# One gate for the yard, the ledger and this pass: the hull the yard would
	# lay down today, or the reason it will not (issue #1126).
	var yard: Dictionary = AiNavy.laying(economy, flown)
	var type_id: String = String(yard.get("type_id", ""))
	if type_id.is_empty():
		return {"refused": String(yard.get("reason", "")), "type_id": ""}
	var chest: int = MapPlayCourt.navy_chest(play, faction)
	var laid: Dictionary = _launch(
		play, roster, faction, economy, seat, {"type_id": type_id}, flown
	)
	if not bool(laid.get("ok", false)):
		return {"refused": String(laid.get("reason", "")), "type_id": type_id}
	laid.erase("ok")
	laid["price"] = ShipEconomy.treasury_cost(type_id)
	laid["chest"] = chest
	return laid


## Paying for one hull: the slip is the crown's squadron already in port at its
## seat, or a new empty squadron founded there (the player's yard does the same).
## Returns `{ok: true, type_id, hull, founded}` or `{ok: false, reason}` in the
## yard's own words, so a refusal reads in the trace (issue #1126).
static func _launch(
	play: PlaySession,
	roster: Array,
	faction: int,
	economy: PlayerEconomy,
	seat: int,
	order: Dictionary,
	flown: Array = []
) -> Dictionary:
	var type_id: String = String(order.get("type_id", ""))
	if type_id.is_empty():
		return {"ok": false, "reason": "the slip has no hull to lay"}
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
	var known: Array = flown if not flown.is_empty() else ShipEconomy.types_flown(roster)
	var result: Dictionary = FleetYard.launch(economy, fleet, type_id, hull_id, known)
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": String(result.get("reason", ""))}
	play.ship_layer.next_hull += 1
	if founded:
		roster.append(fleet)
	return {"ok": true, "type_id": type_id, "hull": hull_id, "founded": founded}


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

