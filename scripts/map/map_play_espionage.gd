class_name MapPlayEspionage
extends RefCounted
## Session glue for the spy network: folds every region's roster into the
## Research-phase share (wiki: civilian-units § Spy; DR-20261110-03). The rules
## live in SpyNetworks; qualifying courts and rosters live on MapPlaySpyAi; this
## only reads the rival ledgers for the human crown's boost.


const SPY_TYPE: String = "spy"


## Tech id -> percent the human crown's spies add this turn. Empty when no spy
## stands on a rival Great Power's land, or before the rival ledgers exist.
## Every region counts: a spy posted overseas reads the same.
static func research_boost(play: PlaySession) -> Dictionary:
	if play == null or play.civilian_layer == null or play.ai == null:
		return {}
	var rivals: Array[int] = MapPlaySpyAi.qualifying_rivals(play, play.player_faction)
	if rivals.is_empty():
		return {}
	var tech: Dictionary = {}
	for faction: int in rivals:
		tech[faction] = play.ai.economy_for(faction).tech_unlocked
	return SpyNetworks.research_boost(rivals, tech)
