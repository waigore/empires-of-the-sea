class_name MapPlayEspionage
extends RefCounted
## Session glue for the spy network: folds every region's roster into the
## Research-phase share (wiki: civilian-units § Spy; DR-20261110-03). The rules
## live in SpyNetworks; this only reads the live rosters and the rival ledgers.

const SPY_TYPE: String = "spy"


## Tech id -> percent the human crown's spies add this turn. Empty when no spy
## stands on a rival Great Power's land, or before the rival ledgers exist.
## Every region counts: a spy posted overseas reads the same.
static func research_boost(play: PlaySession) -> Dictionary:
	if play == null or play.civilian_layer == null or play.ai == null:
		return {}
	var rivals: Array[int] = []
	for index in play.world.region_count():
		var model: MapModel = play.world.region(index)
		for rival: int in SpyNetworks.qualifying_rivals(
			model, _roster(play, index), play.player_faction
		):
			if not rivals.has(rival):
				rivals.append(rival)
	if rivals.is_empty():
		return {}
	var tech: Dictionary = {}
	for faction: int in rivals:
		tech[faction] = play.ai.economy_for(faction).tech_unlocked
	return SpyNetworks.research_boost(rivals, tech)


## Live roster for the shown region, stored table for the other.
static func _roster(play: PlaySession, index: int) -> Array[CivilianState]:
	var units: Array[CivilianState] = []
	if index == play.region_index:
		return play.civilian_layer.units
	units.assign(play.civilian_layer.regions.value(index, []))
	return units
