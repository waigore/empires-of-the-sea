class_name CivilianMuster
extends RefCounted
## Where a court's civilians stand, where a new one may be mustered, and what it
## costs to raise one (wiki: civilian-units § Overseas deployment; DR-20261111-05).
##
## Every rival civilian pass needs the same three readings: the roster of a
## region (on screen or stored), a free land tile at a province's seat, and the
## harbour a colonist boards at. They lived as private helpers of
## `MapPlayCivilianAi` while a second pass (`AiRandomCourt`) reached in for the
## training step; this module is that seam, public and shared (REQ-P3-01,
## REQ-P3-03). Nothing here decides *what* to train — the planners do — only
## where it stands and how the ledger pays for it.

## Where this court musters a colonist: its own harbour, while the crew its next
## voyage carries is not already abroad and a squadron is free to carry one. The
## crew's own policy holds it there instead of marching it off to work
## (AiExplorerWork, AiMerchantWork), so the expedition the colonisation pass
## plans can board it (wiki: civilian-units § Overseas deployment;
## DR-20261111-05). (-1, -1) when nothing is mustering.
static func muster_port(
	play: PlaySession, faction: int, region: int, model: MapModel
) -> Vector2i:
	if not wants_voyage(play, faction, region, model):
		return CivilianState.NO_TILE
	var port: int = AiBindCampaign.harbour(AiControl.court_kind(play, faction), model, faction)
	if port < 0:
		return CivilianState.NO_TILE
	var data: ProvinceState = model.province_data(port)
	if data == null or data.port_tile.x < 0:
		return CivilianState.NO_TILE
	return data.port_tile


## True when the court has everything a voyage needs: its own region, a crew
## still to send, a funded hull claim and a harbour. One colonist of each kind
## sails at a time, so a court whose Explorer has already landed still musters
## the Merchant that follows it — the claim whose deeds found the colony
## (#1127).
static func wants_voyage(
	play: PlaySession, faction: int, region: int, model: MapModel
) -> bool:
	if play.world == null or model == null:
		return false
	if region != FactionCatalog.region_of(faction):
		return false
	if int(abroad_counts(play, _other_region(region), faction).get(
		voyage_kind(play, faction, region), 0
	)) > 0:
		return false
	if not hull_claimed(play, faction, region):
		return false
	return AiBindCampaign.harbour(AiControl.court_kind(play, faction), model, faction) >= 0


## The colonist kind this court's next voyage carries (`VoyageRead.voyage_kind`):
## a Builder once it holds ground across the water, else a Merchant while its
## Explorer is ashore there, else an Explorer (wiki: civilian-units § Overseas
## deployment; #1127). The muster and the colonisation planner read this one
## home, so neither names a crew the other will not board.
static func voyage_kind(play: PlaySession, faction: int, region: int) -> String:
	if play.world == null:
		return "explorer"
	var other: int = _other_region(region)
	return VoyageRead.voyage_kind(
		VoyageRead.holds_ground_in(play.world, other, faction),
		abroad_counts(play, other, faction)
	)


## This court's civilians in one region, counted by kind — the reading the
## voyage's crew choice asks for.
static func abroad_counts(play: PlaySession, region: int, faction: int) -> Dictionary:
	var counts: Dictionary = {}
	if region < 0 or play.civilian_layer == null:
		return counts
	for unit: CivilianState in roster(play, region):
		if unit != null and unit.owner == faction:
			counts[unit.type_id] = int(counts.get(unit.type_id, 0)) + 1
	return counts


## The region across the water from a crown's own.
static func _other_region(region: int) -> int:
	return WorldMap.NEW_WORLD if region == WorldMap.OLD_WORLD else WorldMap.OLD_WORLD


## True when this crew is the one the pending voyage will board, so it takes no
## work and waits at the harbour instead. Only that one waits: the crown's other
## crews keep working while a colony sails (issue #894; #1127). A caller that
## hands in no pick keeps the published reading — the harbour holds the crew.
static func held_for_voyage(unit: CivilianState, context: Dictionary) -> bool:
	var port: Vector2i = context.get("muster_port", CivilianState.NO_TILE)
	if port.x < 0:
		return false
	if not context.has("muster_unit"):
		return true
	return int(context["muster_unit"]) == unit.id


## One legal march to the harbour a pending voyage boards at, or {} when the
## crew already stands there. Every crew that can muster walks this step, so a
## Merchant called for a claim reaches the port the Explorer waits at.
static func muster_move(
	model: MapModel, unit: CivilianState, context: Dictionary,
	view: VisibilityModel = null
) -> Dictionary:
	var port: Vector2i = context.get("muster_port", CivilianState.NO_TILE)
	if port.x < 0 or model == null or unit == null or _at_port(model, unit, port):
		return {}
	return AiLandRoute.step_toward(model, unit, port, view)


static func _at_port(model: MapModel, unit: CivilianState, port: Vector2i) -> bool:
	var here: int = model.province_at(unit.tile.x, unit.tile.y)
	return here != MapModel.NO_ID and here == model.province_at(port.x, port.y)


## True when the voyage would take an Explorer (the court holds no ground across
## the water) and that Explorer is the last one standing on the home region while
## its own land still holds unsurveyed ground. The hire order reads this to take
## the second crew first, so the colony sails with a prospector left behind
## (issue #894). A court that holds ground overseas sends a Builder instead, so
## the reading never holds its crews back.
static func needs_voyage_crew(
	play: PlaySession, faction: int, region: int, model: MapModel
) -> bool:
	if play.world == null:
		return false
	var other: int = _other_region(region)
	if VoyageRead.holds_ground_in(play.world, other, faction):
		return false
	if explorers(roster(play, region), faction) > 1:
		return false
	return home_unsurveyed(play, faction, region, model)


## True when the crown's own land still holds ground no Explorer has surveyed:
## the mineral deposits the estates ledger prices cannot be planned until it is
## dug (wiki: fog-and-exploration § Prospecting; issue #894).
static func home_unsurveyed(
	play: PlaySession, faction: int, region: int, model: MapModel
) -> bool:
	var works: LandWorks = play.civilian_layer.works_regions.value(region, null)
	if works == null or model == null:
		return false
	var view: VisibilityModel = MapPlayCourtFog.view_for(play, faction, region)
	for province: ProvinceState in model.provinces:
		if model.province_owner(province.id) != faction:
			continue
		if not MineralSurvey.unsurveyed_in_province(
			model, works, faction, province.id, view
		).is_empty():
			return true
	return false


## Explorers this crown fields in a roster.
static func explorers(roster: Array, faction: int) -> int:
	var found: int = 0
	for unit: CivilianState in roster:
		if unit != null and unit.owner == faction and unit.type_id == "explorer":
			found += 1
	return found


## The crew the pending voyage will board: the court's first idle colonist of the
## kind the muster calls (`VoyageRead.idle_colonist`), or -1 when none is free.
## Only that crew waits at the muster port; the crown's others keep working the
## ground while a colony sails (issue #894; #1127).
static func muster_colonist(roster: Array, faction: int, kind: String = "explorer") -> int:
	var unit: CivilianState = VoyageRead.idle_colonist(roster, faction, kind)
	return unit.id if unit != null else -1


## True when the court's last ledger funded the expedition's hull claim — the
## gate the voyage now musters behind, instead of looking for a squadron a
## second time (issue #491 T2). A court with no ledger yet (the opening turn, an
## old save, a fixture) falls back to the free-squadron check, so the muster
## behaves as published until the first ledger exists. A deferred claim leaves
## the Explorer ashore, and the ledger's line already names the shortfall.
static func hull_claimed(play: PlaySession, faction: int, region: int) -> bool:
	var claim: Dictionary = play.ai.objectives_for(faction) if play.ai != null else {}
	if claim.is_empty():
		return has_free_squadron(play, region, faction)
	return (claim.get("funded_ids", []) as Array).has("expedition.hull")


## A squadron of this court that could take a colonist: hulls aloft, no troops
## aboard, and not already carrying one.
static func has_free_squadron(play: PlaySession, region: int, owner: int) -> bool:
	if play.ship_layer == null:
		return false
	var roster: Array = play.ship_layer.regions.value(region, [])
	for raw: Variant in roster:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner:
			continue
		if VoyageRead.is_free(fleet):
			return true
	return false


## Pays for and musters a civilian at the faction's capital, through the same
## catalog costs the training panel uses.
static func train(
	play: PlaySession,
	region: int,
	roster: Array,
	faction: int,
	economy: PlayerEconomy,
	training: Dictionary,
	context: Dictionary
) -> Dictionary:
	var type_id: String = String(training.get("type_id", ""))
	var province: int = int(context.get("capital_province", -1))
	if type_id.is_empty() or province < 0:
		return {}
	var treasury_cost: int = CivilianCatalog.treasury_cost(type_id)
	var paper_cost: int = CivilianCatalog.paper_cost(type_id)
	if economy.treasury < treasury_cost or economy.quantity("paper") < paper_cost:
		return {}
	var model: MapModel = play.world.region(region)
	var tile: Vector2i = mustering_tile(model, province, roster)
	if tile.x < 0 or not economy.spend_treasury(treasury_cost):
		return {}
	if not economy.take("paper", paper_cost):
		economy.add_treasury(treasury_cost)
		return {}
	var unit: CivilianState = append_unit(
		play, region, roster, faction, type_id, tile
	)
	return {"type_id": type_id, "unit": unit.id, "tile": tile}


## The roster a region's pass works on: the live layer's own list when the
## region is on screen, else the stored table.
static func roster(play: PlaySession, region: int) -> Array[CivilianState]:
	if play.model != null and region == play.model.region_id:
		return play.civilian_layer.units
	var stored: Array[CivilianState] = []
	stored.assign(play.civilian_layer.regions.value(region, []))
	return stored


static func has_owner(roster: Array, owner: int) -> bool:
	for unit: CivilianState in roster:
		if unit != null and unit.owner == owner:
			return true
	return false


## Appends to the visible roster through the layer's own id counter; an
## off-screen region only stores the unit in its table (no marker yet).
static func append_unit(
	play: PlaySession,
	region: int,
	roster: Array,
	owner: int,
	type_id: String,
	tile: Vector2i
) -> CivilianState:
	if play.model != null and region == play.model.region_id:
		return play.civilian_layer.add_unit(owner, type_id, tile)
	var unit: CivilianState = CivilianState.create(
		play.civilian_layer.next_id, owner, type_id, tile
	)
	play.civilian_layer.next_id += 1
	roster.append(unit)
	return unit


## Free land tile in the province nearest its seat, mirroring the player's
## mustering rule without needing the region on screen.
static func mustering_tile(
	model: MapModel, province: int, roster: Array
) -> Vector2i:
	if model == null or province < 0:
		return CivilianState.NO_TILE
	var seat: Vector2i = model.capital_tile_of(province)
	var tiles: Array = model.province_tiles(province)
	if seat.x < 0:
		if tiles.is_empty():
			return CivilianState.NO_TILE
		seat = tiles[0]
	var taken: Dictionary = {seat: true}
	for unit: CivilianState in roster:
		if unit != null:
			taken[unit.tile] = true
	var free: Array[Vector2i] = []
	for tile: Vector2i in tiles:
		if not taken.has(tile) and model.is_land(tile.x, tile.y):
			free.append(tile)
	free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var left: int = (a - seat).length_squared()
		var right: int = (b - seat).length_squared()
		if left != right:
			return left < right
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	if free.is_empty():
		return seat
	return free[0]


static func unit_by_id(roster: Array, unit_id: int) -> CivilianState:
	for unit: CivilianState in roster:
		if unit != null and unit.id == unit_id:
			return unit
	return null
