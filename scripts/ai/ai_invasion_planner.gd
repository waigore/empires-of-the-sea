class_name AiInvasionPlanner
extends RefCounted
## Rival overseas invasions (wiki: ai-architecture § Naval policy, ships-and-naval
## § Naval transport; DR-20261110-02).
##
## A court at war with a crown across the water detaches a field army, boards it
## on a squadron, crosses a Passage and marks a beachhead on the enemy coast; the
## landing fights the turn after. The planner chooses one legal step a turn and
## leaves every gate to NavalTransport, NavalMovement, FleetSortie and
## WarpTravel, so the AI never invents an outcome (REQ-P2-03, REQ-P3-03).

const KIND_SPLIT: String = "split_home"
const KIND_DOCK: String = "dock"
const KIND_EMBARK: String = "embark"
const KIND_SAIL: String = "sail"
const KIND_CROSS: String = "cross"
const KIND_BEACHHEAD: String = "beachhead"
const KIND_LAND: String = "land"


## Detach a field army for the crossing when a war lies across the water and no
## field army exists yet. One regiment keeps the seat (the Home Army never
## sails), exactly like the land policy's split, so the adapter applies it once.
## `charts` is the court's own fog: only a hostile coast it has charted is worth
## a crossing, and a null chart is the fixture reading (DR-20261110-21).
## `wants_income` lifts the frontier guard: a court on **earn** sails to the far
## coast the gold is on, unless a hostile host already stands on its own soil
## (DR-20261113-19).
static func split_orders(
	config: AiConfig,
	state: DiplomacyState,
	world: WorldMap,
	model: MapModel,
	fleets: Array,
	armies: Array,
	charts: CourtCharts = null,
	wants_income: bool = false
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if config == null or state == null or world == null or model == null:
		return actions
	var owner: int = config.faction
	if model.region_id != FactionCatalog.region_of(owner):
		return actions
	if not _field_armies(armies, owner).is_empty():
		return actions
	if not _has_overseas_war(state, world, owner, charts, armies, wants_income):
		return actions
	var home: ArmyState = _home_army(armies, owner)
	if home == null or home.count() < 2:
		return actions
	var fleet: FleetState = _idle_fleet(fleets, owner, 1)
	if fleet == null:
		return actions
	# Only as many regiments as the hulls can carry; one always keeps the seat.
	var spare: int = mini(fleet.ship_count(), home.count() - 1)
	if spare < 1:
		return actions
	var ordered: Array[String] = home.regiments.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool:
		var left: int = RegimentCatalog.strength(home.type_of(a))
		var right: int = RegimentCatalog.strength(home.type_of(b))
		if left != right:
			return left < right
		return a < b
	)
	var ids: Array[String] = []
	for index in range(1, spare + 1):
		ids.append(ordered[index])
	actions.append({"kind": KIND_SPLIT, "army_id": home.id, "regiments": ids})
	return actions


## One legal step of this court's expedition in this region, or an empty
## dictionary when it has nothing to do this turn.
static func plan(
	config: AiConfig,
	state: DiplomacyState,
	world: WorldMap,
	region: int,
	model: MapModel,
	fleets: Array,
	armies: Array,
	turn: int = 0,
	charts: CourtCharts = null,
	wants_income: bool = false
) -> Dictionary:
	if config == null or state == null or world == null or model == null:
		return {}
	var owner: int = config.faction
	var hostile: Dictionary = _hostile_owners(state, owner)
	var fleet: FleetState = _expedition(fleets, owner)
	if fleet != null:
		return _voyage(config, world, region, model, armies, fleet, hostile, turn, charts)
	if region != FactionCatalog.region_of(owner):
		return {}
	if not _has_overseas_war(state, world, owner, charts, armies, wants_income):
		return {}
	return _board_step(model, fleets, armies, owner)


## An army boards a squadron that reaches its port; a squadron already there
## takes it aboard. Rivals' squadrons usually start at sea, so docking first is
## the common first step.
static func _board_step(
	model: MapModel, fleets: Array, armies: Array, owner: int
) -> Dictionary:
	var army: ArmyState = _army_to_sail(model, armies, owner)
	if army == null:
		return {}
	var fleet: FleetState = _idle_fleet(fleets, owner, army.count())
	if fleet == null:
		return {}
	if fleet.is_in_port():
		if fleet.province == army.province:
			return {"kind": KIND_EMBARK, "fleet": fleet.id, "army": army.id}
		return {}
	if NavalMovement.province_sea_zones(model, army.province).has(fleet.sea_zone):
		return {"kind": KIND_DOCK, "fleet": fleet.id, "province": army.province}
	var zone: int = AiSeaRoute.sail_toward(
		model, fleet, NavalMovement.province_sea_zones(model, army.province)
	)
	if zone < 0:
		return {}
	return {"kind": KIND_SAIL, "fleet": fleet.id, "zone": zone}


## One voyage step: cross at the Passage, otherwise sail toward the next hostile
## coast, then mark the beachhead the landing waits for.
static func _voyage(
	config: AiConfig,
	world: WorldMap,
	region: int,
	model: MapModel,
	armies: Array,
	fleet: FleetState,
	hostile: Dictionary,
	turn: int,
	charts: CourtCharts = null
) -> Dictionary:
	var army: ArmyState = _carried_army(armies, fleet)
	if army == null:
		return {}
	var home: int = FactionCatalog.region_of(fleet.owner)
	var target_region: int = _other_region(world, home)
	if target_region < 0:
		return {}
	if region != target_region:
		if fleet.is_at_sea() and world.is_warp_zone(region, fleet.sea_zone):
			return {"kind": KIND_CROSS, "fleet": fleet.id}
		var warp: int = _sail(
			model, fleet, world.warp_zones(region), charts, fleet.owner
		)
		if warp < 0:
			return {}
		return {"kind": KIND_SAIL, "fleet": fleet.id, "zone": warp}
	if fleet.has_beachhead():
		if not NavalTransport.beachhead_ready(fleet, turn):
			return {}
		return {
			"kind": KIND_LAND, "fleet": fleet.id, "province": fleet.beachhead_province,
		}
	var target: int = _target(config, model, armies, army, hostile, charts)
	if target < 0:
		return _retire(model, fleet, turn, hostile)
	if NavalMovement.provinces_by_zone(model, fleet.sea_zone).has(target):
		return {"kind": KIND_BEACHHEAD, "fleet": fleet.id, "province": target}
	var zone: int = _sail(
		model, fleet, NavalMovement.province_sea_zones(model, target), charts, fleet.owner
	)
	if zone < 0:
		return {}
	return {"kind": KIND_SAIL, "fleet": fleet.id, "zone": zone}


## The next zone toward `goals`, walking only water this court charts; with no
## charted route it takes the lowest-id adjacent zone it has not seen, which is
## how a far coast is found (DR-20261110-21).
static func _sail(
	model: MapModel, fleet: FleetState, goals: Array[int], charts: CourtCharts, owner: int
) -> int:
	if charts == null:
		return AiSeaRoute.sail_toward(model, fleet, goals)
	var known: Array[int] = charts.known_zones(owner, model.region_id)
	var charted: Array[int] = []
	for zone: int in goals:
		if known.has(zone):
			charted.append(zone)
	if not charted.is_empty():
		var step: int = AiSeaRoute.sail_toward(model, fleet, charted)
		if step >= 0:
			return step
	for zone: int in NavalMovement.destination_zones(model, fleet):
		if not known.has(zone):
			return zone
	return -1


## The worthiest hostile coast this army can storm: best province score, then
## lowest id, with the land policy's wall and margin gating the fight. A coast
## the court has never charted cannot be chosen (DR-20261110-21).
static func _target(
	config: AiConfig, model: MapModel, armies: Array, army: ArmyState, hostile: Dictionary,
	charts: CourtCharts = null
) -> int:
	var best: int = -1
	var best_score: int = 0
	for province: ProvinceState in model.provinces:
		if not province.coastal:
			continue
		var owner: int = province.owner
		if owner == MapModel.NO_ID or owner == army.owner:
			continue
		if not _invadable(owner, hostile):
			continue
		if charts != null and not charts.knows_province(army.owner, model.region_id, province.id):
			continue
		if not _can_storm(config, model, armies, army, province.id):
			continue
		var score: int = AiMilitaryPlanner.province_score(config, model, province.id)
		if best < 0 or score > best_score or (score == best_score and province.id < best):
			best = province.id
			best_score = score
	return best


## Walls soak attacking strength, so a landing needs a margin over the defenders
## (wiki: siege-mechanics § Auto-resolve composite).
static func _can_storm(
	config: AiConfig, model: MapModel, armies: Array, army: ArmyState, province: int
) -> bool:
	var roster: Array[ArmyState] = []
	roster.assign(armies)
	var defenders: Array[ArmyState] = ArmyForce.armies_of(
		roster, province, model.province_owner(province)
	)
	if defenders.is_empty():
		return true
	var wall: float = FortRules.wall_hp(FortRules.level_at(model, province))
	var attack: float = army.strength() - wall
	var margin: float = float(config.parameter("military.attack_margin_pct")) / 100.0
	return attack > ArmyForce.side_strength(defenders) * margin


## No war target left (peace signed mid-voyage): land on an own coast instead of
## keeping a field army afloat, and sail toward the nearest one when none is in
## reach.
static func _retire(
	model: MapModel, fleet: FleetState, turn: int, hostile: Dictionary
) -> Dictionary:
	var query: Callable = func(a: int, b: int) -> bool: return a != b and hostile.has(b)
	for province: int in NavalTransport.landing_provinces(model, fleet, turn, query):
		return {"kind": KIND_LAND, "fleet": fleet.id, "province": province}
	var goals: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner != fleet.owner or not province.coastal:
			continue
		for zone: int in NavalMovement.province_sea_zones(model, province.id):
			if not goals.has(zone):
				goals.append(zone)
	goals.sort()
	var zone: int = AiSeaRoute.sail_toward(model, fleet, goals)
	if zone < 0:
		return {}
	return {"kind": KIND_SAIL, "fleet": fleet.id, "zone": zone}


## The region this court campaigns in: the other one, reached through a Passage.
static func _other_region(world: WorldMap, home: int) -> int:
	for index in world.region_count():
		if index != home and not world.warp_zones(home).is_empty():
			return index
	return -1


## Something worth a fleet: a declared enemy's or a Tribe's coast lies across the
## water and the court has charted it, and no hostile province touches its own
## border, so the land army is not needed at home (wiki: factions § Tribe;
## DR-20261110-21 keeps an uncharted shore out of reach). A court on **earn**
## still sails into a border war — the gold that ends its impasse is overseas —
## unless a hostile host already stands on its own soil, in which case the
## defence comes first (DR-20261113-19).
static func _has_overseas_war(
	state: DiplomacyState, world: WorldMap, owner: int,
	charts: CourtCharts = null, armies: Array = [], wants_income: bool = false
) -> bool:
	var home: int = FactionCatalog.region_of(owner)
	if home < 0 or world.warp_zones(home).is_empty():
		return false
	var hostile: Dictionary = _hostile_owners(state, owner)
	var here: MapModel = world.region(home)
	if here != null and not AiMilitaryPlanner.frontier_hostile(here, owner, state).is_empty():
		if not wants_income or AiMilitaryPlanner.invader_on_home_soil(
			here, owner, armies, state
		):
			return false
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if index == home or model == null:
			continue
		for province: ProvinceState in model.provinces:
			if not province.coastal or not _invadable(province.owner, hostile):
				continue
			if charts != null and not charts.knows_province(owner, index, province.id):
				continue
			return true
	return false


## The squadron carrying this court's expedition, lowest id first.
static func _expedition(fleets: Array, owner: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.embarked_army < 0:
			continue
		if best == null or fleet.id < best.id:
			best = fleet
	return best


## Lowest-id squadron that can still take troops: afloat, un-moved, no army and
## no colonists aboard, with room for `needed` regiments.
static func _idle_fleet(fleets: Array, owner: int, needed: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null or fleet.owner != owner or fleet.moved:
			continue
		if not fleet.is_afloat() or fleet.embarked_army >= 0 or fleet.carries_civilians():
			continue
		if fleet.ship_count() < needed:
			continue
		if best == null or fleet.id < best.id:
			best = fleet
	return best


## A field army that can march to a harbour and sail: un-moved, non-empty and
## standing in an own coastal province with a harbour.
static func _army_to_sail(model: MapModel, armies: Array, owner: int) -> ArmyState:
	for army: ArmyState in _field_armies(armies, owner):
		if army.moved or army.is_embarked() or army.is_empty():
			continue
		if model.province_owner(army.province) != owner:
			continue
		if not NavalMovement.has_harbour(model, army.province):
			continue
		return army
	return null


static func _carried_army(armies: Array, fleet: FleetState) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army == null or army.owner != fleet.owner:
			continue
		if army.embarked_fleet == fleet.id or army.id == fleet.embarked_army:
			return army
	return null


## A coast this court may take: a declared enemy's, or a Tribe's without a
## declaration (wiki: factions § Tribe).
static func _invadable(owner: int, hostile: Dictionary) -> bool:
	if hostile.has(owner):
		return true
	return FactionCatalog.type_of(owner) == FactionCatalog.Type.TRIBE


## Factions this court is at war with, as a membership set.
static func _hostile_owners(state: DiplomacyState, owner: int) -> Dictionary:
	var hostile: Dictionary = {}
	for record: DiplomacyRelation in state.relations_of(owner):
		if record.at_war:
			hostile[record.other(owner)] = true
	return hostile


static func _home_army(armies: Array, owner: int) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army != null and army.owner == owner and army.home:
			return army
	return null


static func _field_armies(armies: Array, owner: int) -> Array[ArmyState]:
	var field: Array[ArmyState] = []
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army != null and army.owner == owner and not army.home and not army.is_empty():
			field.append(army)
	field.sort_custom(func(a: ArmyState, b: ArmyState) -> bool: return a.id < b.id)
	return field
