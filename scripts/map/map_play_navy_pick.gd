class_name MapPlayNavyPick
extends RefCounted
## The sails the court's own naval pass would order this turn, named on THE
## CROWN'S NAVY before the crown opens a single squadron's dossier (wiki:
## ships-and-naval § The crown's navy, § Missions and Movement;
## DR-20261121-13).
##
## The reading is not a second opinion: it is `AiBindCampaign.naval_orders` — the
## call `MapPlayFleetPick` reads for one squadron's own dossier, and the rival
## pass and the Auto seat make for a court — asked once per chart for this crown,
## so the sheet cannot name a sail the policy would not order (REQ-P2-03).
##
## A reading only: nothing here moves a hull, takes a station or rolls a die, and
## the crown still presses her own order (REQ-P3-03, REQ-P5-06).

## The policy's own kinds, so a wording never guesses at an order it cannot say.
const KIND_SORTIE: String = AiNavalPlanner.KIND_SORTIE
const KIND_PURSUE: String = AiNavalPlanner.KIND_PURSUE
const KIND_RAID: String = AiNavalPlanner.KIND_RAID
const KIND_HOME: String = AiNavalPlanner.KIND_HOME
const KIND_CONVOY: String = AiNavalPlanner.KIND_CONVOY

## Squadrons wait for a sail and the pass orders none: the gate the sheet names
## instead of a clause it cannot print.
const NO_ORDER_LINE: String = (
	"the court would send no waiting squadron to sea this turn"
)


## The sheet's sentence: the pick's own line, capitalised and closed — the one
## wording every pick surface prints (MapPlayPickProse; REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, snapshot: Dictionary = {}) -> String:
	return MapPlayPickProse.sentence_of(pick(play, snapshot))


## The navy's pick as the sheet prints it: `{squadrons, line}`, where each
## squadron is `{region, fleet_id, kind, line}`. Empty when the session runs no
## planner for the crown, an observer session, a decided campaign, a session with
## no naval layer or diplomacy, or a navy the pass leaves entirely alone.
static func pick(play: PlaySession, snapshot: Dictionary = {}) -> Dictionary:
	if not MapPlayPickProse.crown_ready(play):
		return {}
	if play.world == null or play.ship_layer == null or play.diplomacy == null:
		return {}
	var faction: int = play.player_faction
	var squadrons: Array[Dictionary] = _squadrons(play, faction)
	if not squadrons.is_empty():
		return of(squadrons, snapshot)
	# The pass names no sail: the sheet says whether any squadron waited for one,
	# so a navy already under way reads nothing rather than a gate.
	return gate(_waiting(play, faction))


## The gate a silent pass earns: `waiting` squadrons stood for a sail and the
## policy gave none, so the sheet names that rather than a clause it cannot
## print. A navy with nothing waiting has nothing to say (REQ-P5-06).
static func gate(waiting: int) -> Dictionary:
	return MapPlayPickProse.gate(waiting, "squadrons", NO_ORDER_LINE)


## The pick, worded off the squadrons the pass orders and the sheet's own
## snapshot: the squadrons in the order the sheet prints its headings, or the
## gate that leaves a waiting navy with nothing to name. Pure — a sheet and its
## suite drive it without a session.
static func of(squadrons: Array[Dictionary], snapshot: Dictionary = {}) -> Dictionary:
	if squadrons.is_empty():
		return {}
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(
		squadrons, snapshot.get("groups", []), "fleet_id", "fleet"
	)
	return {"squadrons": ordered, "keys": keys_of(ordered), "line": pick_line(ordered)}


## The squadrons the reading names, by `MapPlayPickProse.row_key` — what the
## sheet's own headings look themselves up by (a heading says `fleet`, the pick
## entry `fleet_id`), so a marked squadron is one the line answers
## (DR-20261122-05).
static func keys_of(squadrons: Array[Dictionary]) -> Dictionary:
	var keys: Dictionary = {}
	for squadron: Dictionary in squadrons:
		keys[MapPlayPickProse.row_key(squadron, "fleet_id")] = true
	return keys


## "the court would send the Leopard into the Mar Caribe and the Swallow home to
## Cádiz this turn". Beyond three the line counts the squadrons it cannot name
## (`… and 2 more`) so a busy navy stays one line of chrome.
static func pick_line(squadrons: Array[Dictionary]) -> String:
	var clauses: Array[String] = []
	for squadron: Dictionary in squadrons:
		clauses.append(String(squadron.get("line", "")))
	return MapPlayPickProse.court_line("the court would send", clauses)


## One squadron's clause: the sail the policy would order her, named by the
## flagship she flies so two squadrons never read alike. Empty when the order
## names nothing this module can say (an unknown kind, or a chart with no such
## water), so the line can never promise a sail to nowhere.
static func clause(model: MapModel, order: Dictionary, ship: String) -> String:
	if model == null or order.is_empty() or ship.is_empty():
		return ""
	var kind: String = String(order.get("kind", ""))
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	match kind:
		KIND_SORTIE:
			if zone == MapModel.NO_ID:
				return ""
			return "the %s into the %s" % [ship, model.sea_zone_name(zone)]
		KIND_PURSUE:
			if zone == MapModel.NO_ID:
				return ""
			return "the %s in pursuit into the %s" % [ship, model.sea_zone_name(zone)]
		KIND_RAID:
			if zone == MapModel.NO_ID:
				return ""
			return "the %s for the %s, the first leg toward a hostile coast" % [
				ship, model.sea_zone_name(zone)
			]
		KIND_HOME:
			return _home_clause(model, order, ship)
		KIND_CONVOY:
			return _convoy_clause(model, order, ship)
	return ""


## Convoy: the merchant hull's leg home is a convoy, never a war move
## (wiki: economy-planner § Cargo; issue #1258).
static func _convoy_clause(model: MapModel, order: Dictionary, ship: String) -> String:
	if bool(order.get("dock", false)):
		var port: int = int(order.get("province", MapModel.NO_ID))
		if port == MapModel.NO_ID:
			return ""
		return "the %s home with the holds, to %s" % [ship, model.province_name(port)]
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	return "the %s home with the holds, toward the %s" % [ship, model.sea_zone_name(zone)]


## Home: she docks when the harbour is hers to enter, else she takes the first
## leg of the road back (DR-20261110-30).
static func _home_clause(model: MapModel, order: Dictionary, ship: String) -> String:
	if bool(order.get("dock", false)):
		var port: int = int(order.get("province", MapModel.NO_ID))
		if port == MapModel.NO_ID:
			return ""
		return "the %s home to %s" % [ship, model.province_name(port)]
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	return "the %s for the %s, the first leg home" % [ship, model.sea_zone_name(zone)]


## The sails the pass books, in the pass's own order: one clause per squadron of
## the crown the policy orders, read on the chart she sails.
static func _squadrons(play: PlaySession, faction: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var court: Dictionary = AiControl.court(play, faction)
	if court.is_empty():
		return found
	var kind: String = String(court["kind"])
	var config: Variant = court["config"]
	if config == null:
		return found
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[FleetState] = MapPlayCourtRoster.region_fleets(play, region)
		if roster.is_empty():
			continue
		var plan: Dictionary = AiBindCampaign.naval_orders(
			kind, config, play.diplomacy, model, roster, play.court_charts
		)
		for raw: Variant in plan.get("orders", []):
			var order: Dictionary = raw
			var fleet: FleetState = _fleet(roster, int(order.get("fleet_id", -1)))
			if fleet == null or fleet.owner != faction:
				continue
			var said: String = clause(model, order, _ship(fleet))
			if said.is_empty():
				continue
			found.append({
				"region": region,
				"fleet_id": fleet.id,
				"kind": String(order.get("kind", "")),
				"line": said,
			})
	return found


## The squadrons the pass weighs at all — afloat, unmoved, carrying no army —
## so the sheet knows whether a silent pass left anyone waiting for a sail.
static func _waiting(play: PlaySession, faction: int) -> int:
	var waiting: int = 0
	for region: int in play.ship_layer.regions.region_ids():
		var roster: Array[FleetState] = MapPlayCourtRoster.region_fleets(play, region)
		for fleet: FleetState in roster:
			if fleet == null or fleet.owner != faction:
				continue
			if fleet.moved or not fleet.is_afloat() or fleet.embarked_army >= 0:
				continue
			waiting += 1
	return waiting


## The squadron a plan names, read off the roster the plan was asked about.
static func _fleet(roster: Array[FleetState], fleet_id: int) -> FleetState:
	for fleet: FleetState in roster:
		if fleet != null and fleet.id == fleet_id:
			return fleet
	return null


## The flagship a squadron flies: the sheet's own heading reads her the same way
## (wiki: naming § Ship names).
static func _ship(fleet: FleetState) -> String:
	if fleet.hulls.is_empty():
		return ""
	return ShipNames.of(fleet, fleet.hulls[0])
