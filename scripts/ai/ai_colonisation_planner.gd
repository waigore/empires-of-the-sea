class_name AiColonisationPlanner
extends RefCounted
## Rival colonisation voyages (wiki: civilian-units § Overseas deployment;
## map-topology § Warp zones; DR-20261109-17).
##
## A Great Power reaches the New World the same way the player does: an idle
## civilian boards a crown squadron, the squadron crosses a Passage, and the
## civilian lands on the far coast. This planner chooses one legal step per turn
## for one court — dock, embark, sail, cross or land — and leaves every gate to
## CivilianVoyage, NavalMovement and WarpTravel (REQ-P2-03, REQ-P3-03).
##
## Rivals with overseas provinces send a Builder to work them; a crown with no
## New World land sends an Explorer to chart it. The existing civilian planner
## takes over once the colonist is ashore.
##
## Ground ranking lives on [AiColonisationGround]; voyage steps on
## [AiColonisationVoyage]. This owner keeps the published API so map adapters
## and traces never chase a rename (REQ-P3-01).
##
## **The ground is read, not picked by the compass** (DR-20261119-05): a landing
## is the one tile a court takes overseas, and the published walk landed on the
## north-easternmost charted coast whatever it grew — so no rival court ever held
## sugar cane, tobacco or furs, and the catalogue's luxury rows waited on a raw no
## crown brought home. `appetite` (commodity → weight) names the raws this court's
## own workshop can turn and does not hold in number: the best such ground wins,
## the compass order breaks ties, and a caller that reads no appetite keeps the
## published order tile for tile.
##
## **The treasury is read beside the workshop** (issue #1382): the appetite may
## also carry a `riches` weight (`economy.riches_route_weight`, set by
## `AiEconomyPlanner.ground_appetite` once the court charts the New World), which
## [method AiColonisationGround.ground_weight] puts on mineral-bearing terrain —
## the ground an Explorer can survey — without ever naming a mineral.
##
## **Riches are ground, not a mineral** (issue #1382 / #1386): a court on **earn**
## sails for cash, and the one New World ground that clears straight to the
## treasury is a deposit no chart shows until an Explorer digs it
## (fog-and-exploration § Prospect-Required Resources; DR-20261111-26). So while
## that court wants income, an Explorer's landing prefers a prospectable tile —
## swamp, hills, peak or desert — over bare ground its workshop has no use for,
## and a raw the workshop is short of still leads it. The deposit is never named:
## every prospectable tile weighs the same until its survey lands (REQ-P2-03).

## Constants the voyage and ground homes publish — kept here so callers that
## already read the planner door keep one name.
const RICHES_KEY: String = AiColonisationGround.RICHES_KEY
const EXPLORER: String = AiColonisationGround.EXPLORER
const RICHES_GROUND: int = AiColonisationGround.RICHES_GROUND
const WANTED_SHIFT: int = AiColonisationGround.WANTED_SHIFT


## One order for this court in this region, or an empty dictionary.
## `abroad` counts this court's civilians already in the target region, by type,
## so a court sends one Explorer to chart it and, once it holds land there, one
## Builder to work it — then one Engineer while that ground has no port to root
## its network (`needs_port`, issue #1422). `charts` is the court's own fog: it
## lands only on coast it has seen and walks only water it charts, with one blind
## step into the unknown to extend the chart (DR-20261110-21). A null chart is the fixture reading —
## every tile charted — and production always hands the court's charts in
## (MapPlayColonisationAi). `posture` is the court's war footing: a court
## fighting a Great Power opens no new voyage, while an expedition already afloat
## keeps sailing (wiki: phase-planner-architecture § Playable slice;
## DR-20261113-15) — unless it is on **earn**, whose gold is across the water
## (DR-20261113-19).
static func plan(
	config: AiConfig,
	world: WorldMap,
	region: int,
	model: MapModel,
	fleets: Array,
	civilians: Array,
	abroad: Dictionary = {},
	charts: CourtCharts = null,
	posture: String = AiPhasePlanner.PHASE_UNKNOWN,
	wants_income: bool = false,
	appetite: Dictionary = {},
	needs_port: bool = false
) -> Dictionary:
	if config == null or world == null or model == null:
		return {}
	var owner: int = config.faction
	var home: int = FactionCatalog.region_of(owner)
	if home < 0:
		return {}
	var target: int = _target_region(world, home, owner)
	if target < 0:
		return {}
	var fleet: FleetState = VoyageRead.carrying(fleets, owner, true)
	if fleet != null:
		var carried: CivilianState = AiColonisationVoyage.by_id(
			civilians, AiColonisationVoyage.carried_id(fleet)
		)
		if carried == null:
			return {}
		return AiColonisationVoyage.voyage(
			world, region, model, fleet, carried, target, charts, appetite, wants_income
		)
	if region != home:
		# No colonist aboard: a squadron left across the water sails home, so the
		# court's hulls are not stranded there for the rest of the campaign (they
		# carry the next voyage and an overseas invasion).
		var stranded: FleetState = AiColonisationVoyage.stranded_fleet(fleets, owner)
		if stranded != null:
			return AiColonisationVoyage.homeward(world, region, model, stranded, charts)
		return {}
	if not AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_VOYAGE) and not wants_income:
		return {}
	var unit: CivilianState = _voyage_unit(civilians, owner, world, target, abroad, needs_port)
	if unit == null:
		return {}
	fleet = VoyageRead.free_squadron(fleets, owner)
	if fleet == null:
		return {}
	return AiColonisationVoyage.board_step(model, fleet, unit, charts)


## The harbour a rival's expedition musters at: its seat when the seat has a
## port, else its lowest-id port province. -1 when the crown owns no harbour,
## which is the one case a voyage cannot start (wiki: ships-and-naval § Home
## Fleet; civilian-units § Overseas deployment). One reading serves every
## planner (`NavalMovement.home_harbour`).
static func harbour(model: MapModel, owner: int) -> int:
	if owner < 0:
		return MapModel.NO_ID
	return NavalMovement.home_harbour(model, owner)


## The other region when the crown has land there, else the New World from the
## Old World. A court already abroad with land at home never sails back here.
static func _target_region(world: WorldMap, home: int, owner: int) -> int:
	if home == WorldMap.OLD_WORLD:
		return WorldMap.NEW_WORLD
	if VoyageRead.owns_land_in(world, WorldMap.OLD_WORLD, owner):
		return WorldMap.OLD_WORLD
	return -1


## First idle civilian the court should send, or null. A crown that holds ground
## overseas sends its Builder to work it; a crown whose ground abroad has no port
## sends the Engineer that roots its network once the Builder stands there; a
## crown whose Explorer is already ashore sends the Merchant, whose deeds found
## the colony; otherwise it charts with an Explorer (wiki: civilian-units
## § Overseas deployment; extraction-and-improvements § Overseas delivery; #497,
## #602, #1127, #1422). One colonist of each kind at a time, so the expedition is
## not duplicated, and the kind is `VoyageRead.voyage_kind` — the same reading the
## muster holds the crew behind at the harbour.
static func _voyage_unit(
	civilians: Array, owner: int, world: WorldMap, target: int, abroad: Dictionary,
	needs_port: bool = false
) -> CivilianState:
	var holds: bool = VoyageRead.holds_ground_in(world, target, owner)
	var kind: String = VoyageRead.voyage_kind(holds, abroad, needs_port)
	var unit: CivilianState = _idle_of(civilians, owner, kind, abroad)
	if unit != null or not holds:
		return unit
	# No crew of the kind the ground asks for is free: the published read stands
	# (the Explorer charts), and the port waits for the next Engineer.
	return _idle_of(civilians, owner, VoyageRead.voyage_kind(false, abroad), abroad)


## One idle colonist of `kind`, or null when one of that kind is already abroad:
## one crew of each kind sails at a time, so the claim is never doubled.
static func _idle_of(
	civilians: Array, owner: int, kind: String, abroad: Dictionary
) -> CivilianState:
	if int(abroad.get(kind, 0)) > 0:
		return null
	return VoyageRead.idle_colonist(civilians, owner, kind)


## Published private doors the suites already call — thin forwards so the
## ground and voyage homes own the bodies without renaming every assert.
static func _landing_zones(
	model: MapModel, type_id: String, owner: int, charts: CourtCharts = null,
	appetite: Dictionary = {}, riches: int = 0
) -> Array[int]:
	return AiColonisationGround.landing_zones(
		model, type_id, owner, charts, appetite, riches
	)


static func _carried_id(fleet: FleetState) -> int:
	return AiColonisationVoyage.carried_id(fleet)
