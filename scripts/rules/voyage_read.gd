class_name VoyageRead
extends RefCounted
## Which squadron and which colonist a court could still send this turn
## (wiki: civilian-units § Overseas deployment; ships-and-naval § Naval
## transport; DR-20261109-17).
##
## The eligibility was copied into the colonisation planner, the crossing force,
## the objective ledger, the civilian pass and the cargo planner, and the copies
## drifted: one forgot a laden hull, one forgot a moved one. These predicates are
## pure roster maths — no nodes, no orders — so every caller keeps its own
## ranking (lowest id, most room, a count) while reading one eligibility rule
## (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## True when the hull can take a passenger: afloat, no army and no colonists.
static func is_free(fleet: FleetState) -> bool:
	if fleet == null or not fleet.is_afloat():
		return false
	return fleet.embarked_army < 0 and not fleet.carries_civilians()


## The lowest-id free, un-moved squadron, or null. The colonisation planner's
## hull: an expedition keeps the same squadron for the whole crossing.
static func free_squadron(fleets: Array, owner: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.moved or not is_free(fleet):
			continue
		if best == null or fleet.id < best.id:
			best = fleet
	return best


## The free, un-moved squadron with the most room; the id breaks a tie so the
## same state always sails the same hulls. The crossing force's choice.
static func roomiest(fleets: Array, owner: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.moved or not is_free(fleet):
			continue
		if best == null or fleet.ship_count() > best.ship_count():
			best = fleet
	return best


## How many free, un-moved squadrons the roster holds — the objective ledger's
## one-hull grant.
static func free_count(fleets: Array, owner: int) -> int:
	var total: int = 0
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.moved:
			continue
		if is_free(fleet):
			total += 1
	return total


## The lowest-id squadron already carrying a colonist. `unmoved_only` keeps the
## planner from steering a squadron that has spent its move; the ledger reads
## every laden hull, moved or not, because the expedition is afloat either way.
static func carrying(
	fleets: Array, owner: int, unmoved_only: bool = false
) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner:
			continue
		if unmoved_only and fleet.moved:
			continue
		if not fleet.carries_civilians():
			continue
		if best == null or fleet.id < best.id:
			best = fleet
	return best


## The lowest-id idle colonist of `type_id`: not working, not moved and not
## already embarked, so a court sends one expedition at a time.
static func idle_colonist(
	civilians: Array, owner: int, type_id: String
) -> CivilianState:
	for raw: Variant in civilians:
		var unit: CivilianState = raw
		if unit == null or unit.owner != owner or unit.type_id != type_id:
			continue
		if unit.is_working() or unit.moved or unit.is_embarked():
			continue
		return unit
	return null


## True when the court owns at least one province in the model.
static func owns_land(model: MapModel, owner: int) -> bool:
	if model == null:
		return false
	for province: ProvinceState in model.provinces:
		if province.owner == owner:
			return true
	return false


## True when the court owns land in one region of the world.
static func owns_land_in(world: WorldMap, region: int, owner: int) -> bool:
	if world == null:
		return false
	return owns_land(world.region(region), owner)


## True when the court holds ground in one region: a province it owns, or a
## purchased deed. A deed is crown land for every landing rule that asks (wiki:
## civilian-units § Overseas deployment — "Builder, Engineer, Rail Builder and
## Spy need crown land (a purchased deed counts)"), so a Merchant's deed is what
## lets a Builder land on the far shore (DR-20261109-17).
static func holds_ground(model: MapModel, owner: int) -> bool:
	if model == null or owner < 0:
		return false
	if owns_land(model, owner):
		return true
	return model.ownership.has_deed_of(owner)


## The same reading through the world: true when the court holds ground in one
## region of it.
static func holds_ground_in(world: WorldMap, region: int, owner: int) -> bool:
	if world == null:
		return false
	return holds_ground(world.region(region), owner)


## True when the court holds ground in this region that could carry a port and
## no port stands on any of it: overseas extraction has no capital tile to seed
## its network, so an estate there pays only once a port roots it (wiki:
## extraction-and-improvements § Overseas delivery; issue #1422). A province
## with no coastal tile can never carry a port, so it never asks for one.
static func needs_port(model: MapModel, works: LandWorks, owner: int) -> bool:
	if model == null or works == null or owner < 0:
		return false
	for province: ProvinceState in model.provinces:
		if model.province_owner(province.id) != owner:
			continue
		if works.province_has_port(model, province.id):
			continue
		for tile: Vector2i in province.tiles:
			if MapGeo.is_coastal_tile(model, tile.x, tile.y):
				return true
	return false


## The colonist kind the court's next voyage carries, from the readings that
## decide it: a Builder once the crown holds ground in the region, else an
## Explorer while none of this court's Explorers is abroad, else a Merchant —
## the claim whose deeds found the colony (wiki: civilian-units § Overseas
## deployment; map-play colonisation #497, #602, #1127). An **Engineer** follows
## the Builder once the ground abroad has no port: no capital tile seeds
## connectivity overseas, so the Builder's estate and every road from it gather
## nothing until a port roots the network (wiki: extraction-and-improvements
## § Overseas delivery; issue #1422). One home, so the crew the muster holds at
## the harbour is the crew the planner boards.
static func voyage_kind(
	holds_ground: bool, abroad: Dictionary, needs_port: bool = false
) -> String:
	if holds_ground:
		# The port the ground abroad still lacks is the root its estates pay
		# through, so the Engineer sails once the Builder stands there
		# (issue #1422).
		if needs_port and int(abroad.get("builder", 0)) > 0:
			return "engineer"
		return "builder"
	if int(abroad.get("explorer", 0)) > 0:
		return "merchant"
	return "explorer"
