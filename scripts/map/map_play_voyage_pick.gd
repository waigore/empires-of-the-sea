class_name MapPlayVoyagePick
extends RefCounted
## The voyage the court's own colonisation pass would make with this squadron
## (wiki: civilian-units § Overseas deployment; DR-20261121-08).
##
## The reading is not a second opinion: it is `MapPlayColonisationAi.step` — the
## call the rival pass applies — asked for the crown's own faction on the chart
## the squadron sails, so the block can never name a step the rules would refuse
## (REQ-P2-03). A reading only: nothing here boards a crew, sails a hull or
## crosses a Passage, and the crown still presses her own order (REQ-P3-03,
## REQ-P5-06).

const KIND_EMBARK: String = MapPlayVoyagePickWords.KIND_EMBARK
const KIND_SAIL: String = MapPlayVoyagePickWords.KIND_SAIL
const KIND_DOCK: String = MapPlayVoyagePickWords.KIND_DOCK
const KIND_CROSS: String = MapPlayVoyagePickWords.KIND_CROSS
const KIND_LAND: String = MapPlayVoyagePickWords.KIND_LAND


## The pick for one squadron, as the passenger block reads it: `{kind, fleet,
## unit, crew, zone, province, tile, ground, carrying, harbour, line, short}`.
## Empty when the court would give this squadron no voyage step — a rival's hull,
## a squadron that has already sailed, a session with no planner or no ledger, a
## decided campaign, or a plan that names another squadron.
static func pick(play: PlaySession, fleet: FleetState) -> Dictionary:
	if play == null or fleet == null or play.ship_layer == null:
		return {}
	if play.world == null or play.civilian_layer == null:
		return {}
	if fleet.owner != play.player_faction or play.observer_mode or play.campaign_over():
		return {}
	# A squadron that has sailed keeps the step she was given; the pass skips
	# her, and so does the block (wiki: ships-and-naval § Missions and Movement).
	if fleet.moved:
		return {}
	# A crown with no ledger has no voyage plan to read: the pass prices the
	# expedition on the court's own purse (wiki: economy-planner § Reservations).
	if play.ledger_for(fleet.owner) == null:
		return {}
	var region: int = MapPlayFleetPick.region_of(play, fleet)
	if region < 0:
		return {}
	var step: Dictionary = MapPlayColonisationAi.step(play, fleet.owner, region)
	if step.is_empty() or int(step.get("fleet", -1)) != fleet.id:
		return {}
	return _words(play, fleet, region, step)


## The block's line: the pick's own sentence, or nothing when the court would
## give this squadron no voyage step this turn.
static func line(play: PlaySession, fleet: FleetState) -> String:
	return MapPlayVoyagePickWords.sentence(String(pick(play, fleet).get("line", "")))


## One step, carried with the words the block prints. The kind, the crew, the
## water and the ground travel beside them so a caller can read the pick without
## parsing a sentence.
static func _words(
	play: PlaySession, fleet: FleetState, region: int, step: Dictionary
) -> Dictionary:
	var model: MapModel = MapPlayFleetPick.model_of(play, region)
	if model == null:
		return {}
	var unit: CivilianState = null
	if step.has("unit"):
		unit = CivilianVoyageMap.by_id(play.civilian_layer, int(step["unit"]))
	var tile: Vector2i = step.get("tile", CivilianState.NO_TILE)
	var data: Dictionary = {
		"kind": String(step.get("kind", "")),
		"fleet": fleet.id,
		"unit": unit.id if unit != null else -1,
		"crew": unit.type_id if unit != null else "",
		"zone": int(step.get("zone", MapModel.NO_ID)),
		"province": int(step.get("province", MapModel.NO_ID)),
		"tile": tile,
		"ground": MapPlayCivilianVoyage.ground_label(play, tile) if tile.x >= 0 else "",
		"carrying": not fleet.embarked_civilians.is_empty(),
		"harbour": NavalMovement.home_harbour(model, fleet.owner),
	}
	# A boarding names no province of its own: the harbour is where it stands, so
	# the pick carries it for a caller that never reads a sentence.
	if String(data["kind"]) == KIND_EMBARK and int(data["province"]) == MapModel.NO_ID:
		data["province"] = data["harbour"]
	var line: String = MapPlayVoyagePickWords.line(model, data)
	if line.is_empty():
		return {}
	data["line"] = line
	data["short"] = line
	return data
