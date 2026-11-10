class_name MapPlaySpyAi
extends RefCounted
## Spy intelligence for rival economies (wiki: research-state § Spy RP boost).
## Keeps the spy-network wiring out of the economy adapter: prepare every rival
## ledger once, then read the tech set each observed court already knows.
## Pure map helper: it reads session state and returns percentages; it never
## resolves a rule itself (REQ-P3-02, REQ-P3-03).


## Every rival ledger exists before any court resolves, so a spy observing a
## court later in the order still reads its known techs this turn.
static func prepare_ledgers(play: PlaySession) -> void:
	if play == null or play.ai == null:
		return
	for faction: int in FactionCatalog.great_power_ids():
		if faction != play.player_faction or play.observer_mode:
			play.ai.economy_for(faction)


## Tech id -> spy-network RP percentage for this court's occupied slots.
static func research_bonus(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> Dictionary:
	if play == null or play.ai == null or economy == null:
		return {}
	var qualifying: Array[int] = qualifying_rivals(play, faction)
	if qualifying.is_empty():
		return {}
	var rival_techs: Dictionary = {}
	for rival: int in qualifying:
		rival_techs[rival] = _techs_of(play, rival)
	return SpyNetworks.research_boost(qualifying, rival_techs)


## Rival Great Powers observed by this court's spies in any region.
static func qualifying_rivals(play: PlaySession, faction: int) -> Array[int]:
	var result: Array[int] = []
	if play == null or play.world == null or play.civilian_layer == null:
		return result
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		for rival: int in SpyNetworks.qualifying_rivals(
			model, _roster(play, region), faction
		):
			if not result.has(rival):
				result.append(rival)
	result.sort()
	return result


## Live roster for the shown region, stored table for the other.
static func _roster(play: PlaySession, region: int) -> Array[CivilianState]:
	if play.model != null and region == play.model.region_id:
		return play.civilian_layer.units
	var units: Array[CivilianState] = []
	units.assign(play.civilian_layer.regions.value(region, []))
	return units


## The human court's research lives on the economy controller, not in the rival
## ledger table, so a rival spy observing the player reads the real tech set.
static func _techs_of(play: PlaySession, faction: int) -> Dictionary:
	if faction == play.player_faction:
		if play.economy != null and play.economy.economy != null:
			return play.economy.economy.research.unlocked
		return {}
	if play.ai != null:
		return play.ai.economy_for(faction).research.unlocked
	return {}
