class_name MapPlayAdvanced
extends RefCounted
## Applies an advanced-start preset to a fresh session (wiki: advanced-starts;
## DR-20261111-01). One pass at new-game time: ledgers and techs, court
## overtures, the inherited New World chart and estates, then the crown's
## soldiers, hulls and civilians. Idempotent guards stay on the session so a
## reload never re-applies it — the save already carries the state.
##
## People and arms muster on MapPlayAdvancedCivilians / MapPlayAdvancedForces so
## this shell stays under the soft size bar (REQ-P3-01).

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
	MapPlayAdvancedCivilians.apply(play, tier)
	MapPlayAdvancedForces.regiments(play, tier)
	report["ships"] = MapPlayAdvancedForces.ships(play, tier)
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
