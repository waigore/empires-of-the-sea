class_name MapPlayVoyagePick
extends RefCounted
## The voyage the court's own colonisation pass would make with this squadron
## (wiki: civilian-units § Overseas deployment; DR-20261121-08).
##
## The reading is not a second opinion: it asks `AiBindCampaign.colonisation_plan`
## — the one gate a voyage order passes, and the call the rival pass books — for
## the crown's own faction on the chart the squadron sails, with the same court
## kind, config, rosters, footing and workshop readings the pass hands it, so the
## block can never name a step the rules would refuse (REQ-P2-03). A reading only:
## nothing here boards a crew, sails a hull or crosses a Passage, and the crown
## still presses her own order (REQ-P3-03, REQ-P5-06).

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
	if not MapPlayPickProse.crown_ready(play):
		return {}
	if fleet == null or play.ship_layer == null:
		return {}
	if play.world == null or play.civilian_layer == null:
		return {}
	if fleet.owner != play.player_faction:
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
	var step: Dictionary = _step(play, fleet.owner, region)
	if step.is_empty() or int(step.get("fleet", -1)) != fleet.id:
		return {}
	return _words(play, fleet, region, step)


## The step the court's voyage pass would take in `region`, asked the way the
## pass asks it: the court kind, the config, the region's rosters, the footing
## and its funded-parent read, the `earn` goal, the abroad counts, the charts and
## the workshop's appetite, through `AiBindCampaign.colonisation_plan` — the one
## gate a voyage order passes (REQ-P2-03). The goal is read only where the
## planner reads it, beside the posture gate, so a footing that opens the voyage
## pays for no income plan (REQ-P4-01).
static func _step(play: PlaySession, faction: int, region: int) -> Dictionary:
	var model: MapModel = play.world.region(region)
	if model == null:
		return {}
	var court: Dictionary = AiControl.court(play, faction)
	if court.is_empty() or String(court["kind"]) == AiControl.KIND_RANDOM:
		return {}
	var kind: String = String(court["kind"])
	var config: Variant = court["config"]
	if config == null:
		return {}
	var fleets: Array = MapPlayCourtRoster.region_fleets(play, region)
	var civilians: Array = []
	civilians.assign(play.civilian_layer.regions.value(region, []))
	var posture: String = AiBind.phase_for(kind, config, play.diplomacy)
	var earning: bool = false
	if not AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_VOYAGE):
		earning = MapPlaySeaStep.earning(play, faction, kind, config)
	var target: int = WorldMap.NEW_WORLD if region == WorldMap.OLD_WORLD else WorldMap.OLD_WORLD
	return AiBindCampaign.colonisation_plan(
		kind, config, play.world, region, model, fleets, civilians,
		CivilianMuster.abroad_counts(play, target, faction), play.court_charts,
		_voyage_posture(play, faction, posture), earning,
		_appetite(play, faction, kind, config)
	)


## The footing the voyage reads: a funded `colonise.new_world` objective opens
## the voyage even at war — the peace-window child is what bought it (issue #491
## T4) — and a court with no claim keeps the published footing.
static func _voyage_posture(play: PlaySession, faction: int, posture: String) -> String:
	if AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_VOYAGE):
		return posture
	var claim: Dictionary = play.ai.objectives_for(faction) if play.ai != null else {}
	if claim.is_empty():
		return posture
	var funded: Array = claim.get("funded_ids", [])
	return AiPhasePlanner.PHASE_PEACE if funded.has("colonise.new_world") else posture


## The raws this court's workshop can turn and does not hold in number: a landing
## is the one ground a court takes overseas, so the plan names the ground its own
## recipes feed (DR-20261119-05). The court's own chart rides in beside it, so
## the riches weight names only a shore the chart has reached (issue #1382). A
## frozen baseline keeps its published walk and reads none.
static func _appetite(
	play: PlaySession, faction: int, kind: String, config: Variant
) -> Dictionary:
	if kind == AiControl.KIND_BASELINE or play.ai == null:
		return {}
	var economy: PlayerEconomy = play.ledger_for(faction)
	var typed: AiConfig = config as AiConfig
	if economy == null or typed == null:
		return {}
	return AiEconomyPlanner.ground_appetite(
		typed, economy, TownIndustry.best_level(play.world, faction), play.court_charts
	)


## The block's line: the pick's own sentence, or nothing when the court would
## give this squadron no voyage step this turn.
static func line(play: PlaySession, fleet: FleetState) -> String:
	return MapPlayPickProse.sentence_of(pick(play, fleet))


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
	# A landing names the ground, not the coast: the province the tile stands in
	# travels beside it, so the block can mark the coast the step would take
	# (DR-20261122-21).
	if String(data["kind"]) == KIND_LAND and int(data["province"]) == MapModel.NO_ID \
		and tile.x >= 0:
		data["province"] = model.province_at(tile.x, tile.y)
	var line: String = MapPlayVoyagePickWords.line(model, data)
	if line.is_empty():
		return {}
	data["line"] = line
	data["short"] = line
	return data
