class_name MapPlayAdvanced
extends RefCounted
## Applies an advanced-start preset to a fresh session (wiki: advanced-starts;
## DR-20261111-01). One pass at new-game time: ledgers and techs, court
## overtures, the inherited New World chart and estates, then the crown's
## soldiers, hulls and civilians. Idempotent guards stay on the session so a
## reload never re-applies it — the save already carries the state.

const NEW_WORLD: int = 1


## New-game entry: applies the preset and repaints the region on screen. A load
## never calls this — the save already carries the state.
static func begin(play: PlaySession) -> void:
	if play == null or not AdvancedStart.active(play.advanced_start):
		return
	apply(play)
	play.switch_region(play.region_index)
	# The preset rewrites every purse after the HUD was built from the turn-0
	# ledger, so the top bar must be repainted here: a court that opens on 40,000
	# ducats read 2,500 until some later order happened to refresh it.
	if play.hud == null or play.economy == null:
		return
	play.hud.set_treasury(play.treasury(), false)
	play.income = play.economy.projected_income()
	play.hud.set_income(play.income)


static func apply(play: PlaySession) -> Dictionary:
	var report: Dictionary = {"tier": play.advanced_start}
	if play == null or play.world == null or not AdvancedStart.active(play.advanced_start):
		return report
	var tier: String = AdvancedStart.normalize(play.advanced_start)
	_economies(play, tier)
	_diplomacy(play, tier)
	report["estates"] = _world(play, tier)
	_civilians(play, tier)
	_regiments(play, tier)
	report["ships"] = _ships(play, tier)
	return report


# --- ledgers, techs, commanders ----------------------------------------------


## Every Great Power starts on the tier's purse, workforce and fixed tech list;
## rival ledgers are the same `PlayerEconomy` the AI planners read.
static func _economies(play: PlaySession, tier: String) -> void:
	var tech: Dictionary = AdvancedStart.tech_table(tier)
	var row: Dictionary = AdvancedStart.entry(tier)
	for faction: int in FactionCatalog.great_power_ids():
		var economy: PlayerEconomy = _economy(play, faction)
		if economy == null:
			continue
		economy.treasury = int(row["treasury"])
		economy.workers = WorkerPool.make(
			int(row["peasants"]), int(row["apprentices"]), 0, 0
		)
		_larder(economy)
		for tech_id: String in tech.keys():
			economy.research.unlock(tech_id)
		economy.research.ensure_slots()
		play.army_layer.generals.sync(faction, tech)


## A progressed court keeps its people fed: the turn-0 rule seeds grain from
## the workforce for START_GRAIN_TURNS, so the tier's own mouths get the same
## larder (plus the trained tiers' luxuries) rather than striking on turn 51.
static func _larder(economy: PlayerEconomy) -> void:
	var turns: int = PlayerEconomy.START_GRAIN_TURNS
	var grain: int = economy.workers.count(WorkerPool.Tier.PEASANT)
	for tier: int in range(1, WorkerPool.TIER_COUNT):
		var count: int = economy.workers.count(tier)
		grain += count
		var luxury: String = WorkerPool.luxury_for(tier)
		if count > 0 and not luxury.is_empty():
			economy.stockpile[luxury] = maxi(
				economy.quantity(luxury), count * turns
			)
	economy.stockpile["grain"] = maxi(economy.quantity("grain"), grain * turns)
	var trained: int = economy.workers.total() - economy.workers.count(WorkerPool.Tier.PEASANT)
	economy.stockpile["meat"] = maxi(economy.quantity("meat"), trained * turns)


## The crown's ledger: the human's controller or the rival AI book.
static func _economy(play: PlaySession, faction: int) -> PlayerEconomy:
	if faction == play.player_faction and play.economy != null and not play.observer_mode:
		return play.economy.economy
	if play.ai == null:
		play.ai = AiState.new()
	return play.ai.economy_for(faction)


# --- diplomacy ---------------------------------------------------------------


## Consulates at 50 turns, embassies at 100, with every Old World Minor and with
## the Tribes whose shores the inherited chart covers (wiki § Tier tables
## "Diplomacy").
static func _diplomacy(play: PlaySession, tier: String) -> void:
	if play.diplomacy == null:
		return
	var stage: String = (
		DiplomacyCatalog.STAGE_EMBASSY if AdvancedStart.embassies(tier)
		else DiplomacyCatalog.STAGE_CONSULATE
	)
	var partners: Array[int] = FactionCatalog.minor_ids()
	partners.append_array(_contact_tribes(play.world, tier))
	for faction: int in FactionCatalog.great_power_ids():
		for partner: int in partners:
			if partner == faction:
				continue
			play.diplomacy.ensure_relation(faction, partner, play.turn)
			play.diplomacy.set_overture(faction, partner, stage)


## Tribes whose province lies inside the chard share of the New World.
static func _contact_tribes(world: WorldMap, tier: String) -> Array[int]:
	var tribes: Array[int] = []
	if world == null or world.region_count() < 2:
		return tribes
	var model: MapModel = world.region(NEW_WORLD)
	for province_id: int in AdvancedWorld.charted_provinces(world, AdvancedStart.nw_reveal(tier)):
		var owner: int = model.province_owner(province_id)
		if FactionCatalog.type_of(owner) == FactionCatalog.Type.TRIBE and not tribes.has(owner):
			tribes.append(owner)
	tribes.sort()
	return tribes


# --- the inherited map -------------------------------------------------------


## Colonies (100-turn), fog, prospecting and the standing estates.
static func _world(play: PlaySession, tier: String) -> Dictionary:
	var works: Dictionary = _works_table(play)
	var report: Dictionary = {}
	report["claimed"] = AdvancedWorld.claim(
		play.world, AdvancedStart.nw_owned(tier), FactionCatalog.great_power_ids()
	)
	_reveal(play, tier)
	var powers: Array[int] = FactionCatalog.great_power_ids()
	report["prospected"] = AdvancedEstates.prospect(
		play.world, works, powers, AdvancedStart.prospect_share(tier)
	)
	report["developed"] = AdvancedEstates.develop(
		play.world, works, powers, AdvancedStart.develop_share(tier)
	)
	report["deeds"] = AdvancedEstates.purchase_minor_land(
		play.world, works, powers, AdvancedStart.develop_share(tier)
	)
	_store_works(play, works)
	return report


## The inherited New World chart (wiki § NW sea-zone visibility — the rule is
## per Great Power): the human's grid lives in the session's table and every
## rival's in `CourtCharts`, so both are charted here. A rival that starts the
## age with colonies on the Passage shore knows the lanes that reach them, and a
## rival that does not still knows no more than the player.
static func _reveal(play: PlaySession, tier: String) -> void:
	if play.world.region_count() < 2:
		return
	var id: int = NEW_WORLD
	var model: MapModel = play.world.region(id)
	if not play.visibility_by_region.has(id):
		var visibility := VisibilityModel.new()
		visibility.setup(model, play.player_faction)
		visibility.apply_initial()
		play.visibility_by_region[id] = visibility
	var share: float = AdvancedStart.nw_reveal(tier)
	AdvancedWorld.reveal(
		play.world, play.visibility_by_region[id] as VisibilityModel,
		play.player_faction, share
	)
	_reveal_courts(play, id, share)


## Every rival reads the same inherited lanes, through its own chart. The grids
## are the ones the turn reads, so a rival's voyage and its explorer act on the
## water its court was given rather than a copy (REQ-P2-03).
static func _reveal_courts(play: PlaySession, region: int, share: float) -> void:
	# Hands the session its charts (idempotent) so a fixture that never loaded a
	# region can still inherit them.
	MapPlayCourtFog.build(play)
	if play.court_charts == null:
		return
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		var view: VisibilityModel = play.court_charts.model_for(faction, region)
		if view == null:
			continue
		AdvancedWorld.reveal(play.world, view, faction, share)


## One works record per region, shared with the civilian layer.
static func _works_table(play: PlaySession) -> Dictionary:
	var table: Dictionary = {}
	for model: MapModel in play.world.regions:
		var id: int = model.region_id
		var works: LandWorks = play.civilian_layer.works_regions.value(id, null)
		table[id] = works if works != null else LandWorks.new()
	return table


static func _store_works(play: PlaySession, table: Dictionary) -> void:
	for raw: Variant in table.keys():
		play.civilian_layer.works_regions.set_region(int(raw), table[raw])


# --- crown's people ----------------------------------------------------------


## Tops every crown's civilian roster up to the tier totals at its own capital.
static func _civilians(play: PlaySession, tier: String) -> void:
	var model: MapModel = play.world.region(0)
	if model == null:
		return
	var roster: Array = _roster(play)
	var works: LandWorks = play.civilian_layer.works_regions.value(0, null)
	var taken: Dictionary = _taken_tiles(model, roster)
	var totals: Dictionary = AdvancedStart.civilians(tier)
	for faction: int in model.faction_ids:
		if FactionCatalog.type_of(faction) != FactionCatalog.Type.GREAT_POWER:
			continue
		var provinces: Array[ProvinceState] = _muster_provinces(model, faction)
		if provinces.is_empty():
			continue
		for province: ProvinceState in provinces:
			taken[province.capital_tile] = true
			if works != null:
				for tile: Vector2i in province.tiles:
					if works.improvement_at(model, tile) > 0:
						taken[tile] = true
		for type_id: Variant in totals.keys():
			var want: int = int(totals[type_id])
			var have: int = _count_type(roster, faction, String(type_id))
			for _index in maxi(want - have, 0):
				var tile: Vector2i = _free_tile(model, provinces, taken)
				if tile.x < 0:
					break
				taken[tile] = true
				roster.append(_new_civilian(play, faction, String(type_id), tile))


static func _new_civilian(
	play: PlaySession, faction: int, type_id: String, tile: Vector2i
) -> CivilianState:
	var unit: CivilianState = CivilianState.create(
		play.civilian_layer.next_id, faction, type_id, tile
	)
	play.civilian_layer.next_id += 1
	return unit


static func _roster(play: PlaySession) -> Array:
	var list: Array = play.civilian_layer.regions.value(0, [])
	play.civilian_layer.regions.set_region(0, list)
	return list


static func _taken_tiles(model: MapModel, roster: Array) -> Dictionary:
	var taken: Dictionary = {}
	for raw: Variant in roster:
		var unit: CivilianState = raw as CivilianState
		if unit != null and not unit.is_embarked():
			taken[unit.tile] = true
	return taken


static func _count_type(roster: Array, owner: int, type_id: String) -> int:
	var count: int = 0
	for raw: Variant in roster:
		var unit: CivilianState = raw as CivilianState
		if unit != null and unit.owner == owner and unit.type_id == type_id:
			count += 1
	return count


## The crown's own land, seat first then the rest of its provinces in id order:
## a tier roster larger than the capital can hold musters across the realm.
static func _muster_provinces(model: MapModel, faction: int) -> Array[ProvinceState]:
	var provinces: Array[ProvinceState] = []
	var seat: ProvinceState = _capital(model, faction)
	if seat != null:
		provinces.append(seat)
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province != seat:
			provinces.append(province)
	return provinces


static func _free_tile(
	model: MapModel, provinces: Array[ProvinceState], taken: Dictionary
) -> Vector2i:
	for province: ProvinceState in provinces:
		for tile: Vector2i in province.tiles:
			if tile == province.capital_tile or taken.has(tile):
				continue
			if model.is_land(tile.x, tile.y):
				return tile
	return Vector2i(-1, -1)


static func _capital(model: MapModel, faction: int) -> ProvinceState:
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			return province
	return null


# --- crown's soldiers and hulls ----------------------------------------------


## The tier's balanced regiment roster joins each Great Power's Home Army.
static func _regiments(play: PlaySession, tier: String) -> void:
	var types: Array[String] = AdvancedStart.regiment_types(tier)
	if types.is_empty():
		return
	var armies: Array = play.army_layer.regions.value(0, [])
	play.army_layer.regions.set_region(0, armies)
	for faction: int in FactionCatalog.great_power_ids():
		var army: ArmyState = _home_army(armies, faction)
		if army == null:
			continue
		for type_id: String in types:
			var unit_id: String = "unit_%d" % play.army_layer.next_regiment
			play.army_layer.next_regiment += 1
			army.add_regiment(unit_id, type_id)


static func _home_army(armies: Array, faction: int) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw as ArmyState
		if army != null and army.owner == faction and army.is_home_army():
			return army
	return null


## Cargo hulls at each crown's own seat: the tier's galleon minimum, added to
## the squadron already in port or to a new one (wiki § Tier tables, Cargo ships).
static func _ships(play: PlaySession, tier: String) -> int:
	var ships: int = AdvancedStart.cargo_ships(tier)
	var model: MapModel = play.world.region(0)
	if ships <= 0 or model == null:
		return 0
	var fleets: Array = play.ship_layer.regions.value(0, [])
	play.ship_layer.regions.set_region(0, fleets)
	var added: int = 0
	for faction: int in FactionCatalog.great_power_ids():
		var province: ProvinceState = _capital(model, faction)
		if province == null:
			continue
		var fleet: FleetState = _home_squadron(fleets, faction, province.id)
		if fleet == null:
			fleet = FleetState.in_port(fleets.size(), faction, province.id)
			fleets.append(fleet)
		var have: int = _galleons(fleet)
		for _index in maxi(ships - have, 0):
			var hull: String = "ship_%d" % play.ship_layer.next_hull
			play.ship_layer.next_hull += 1
			fleet.add_hull(hull, "galleon")
			added += 1
	return added


static func _home_squadron(
	fleets: Array, faction: int, province_id: int
) -> FleetState:
	for raw: Variant in fleets:
		var fleet: FleetState = raw as FleetState
		if fleet == null or fleet.owner != faction:
			continue
		if fleet.is_in_port() and fleet.province == province_id:
			return fleet
	return null


static func _galleons(fleet: FleetState) -> int:
	var count: int = 0
	for hull_id: String in fleet.hulls:
		if fleet.type_of(hull_id) == "galleon":
			count += 1
	return count
