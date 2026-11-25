class_name MapPlayStormWall
extends RefCounted
## The wall a rival court must cross (wiki: ai-architecture § Land reinforcement;
## issues #1314, #1381, #1518).
##
## Owns every wall reading the muster prices: the map-wide thinnest wall a
## peaceful court sizes its host on, and the wall of the courts it fights once a
## war is open. `MapPlayArmyMusterAi` reads it once per pass and notes the host
## on the court's shared config, so the muster, the ledger and the money goal
## never drift from one wall (REQ-P2-03, REQ-P3-01, REQ-P3-03). Pure: the model,
## the diplomacy state and the campaign's tech table in; a threshold out.


## The wall the court must cross today (issue #1518): at war the thinnest wall
## among the provinces of the courts it fights, otherwise the map-wide read.
## The measured seed 1500 sized Portugal's host on a Minor's Wood wall while the
## Spanish wall in front of it stood at 51 against a 27-strength host, so the
## storm gate refused every march into Spain and no Old World province changed
## hands in 200 turns. A peaceful court keeps the map-wide read: it does not yet
## know which neighbour it will fight, and a host it cannot raise would hold the
## bank — and the war — forever.
static func ahead(
	play: PlaySession, model: MapModel, faction: int, techs: Dictionary = {},
	at_war: bool = false
) -> float:
	var wide: float = thinnest_wall(model, faction, techs)
	if not at_war:
		return wide
	var fought: float = war_wall(play, model, faction, techs)
	return fought if fought > 0.0 else wide


## The lowest storm threshold among the walled provinces held by the courts this
## one is at war with, 0 when it fights none or no enemy holds a wall.
static func war_wall(
	play: PlaySession, model: MapModel, faction: int, techs: Dictionary = {}
) -> float:
	if play == null or model == null or play.diplomacy == null:
		return 0.0
	var enemies: Dictionary = {}
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.at_war:
			enemies[record.other(faction)] = true
	if enemies.is_empty():
		return 0.0
	var thinnest: float = 0.0
	for province: int in model.province_count():
		var owner: int = model.province_owner(province)
		if not enemies.has(owner):
			continue
		var threshold: float = _wall(model, province, owner, techs)
		if threshold <= 0.0:
			continue
		if thinnest <= 0.0 or threshold < thinnest:
			thinnest = threshold
	return thinnest


## The lowest storm threshold among the walled provinces this court does not
## own, 0 when none stands. Each province is priced with the battery its holder
## mounts (issue #1381): the campaign's tech table, noted by the map layer, read
## the same way the resolver reads it (`FortRules.storm_threshold`) — a Minor
## Nation's Wood wall is a Royal floor, a Great Power's the emplaced line its
## studies open. A caller with no table prices the top of the ladder
## ([method FortRules.storm_ceiling]), which no longer sizes every minor's wall
## as if it carried siege guns.
static func thinnest_wall(model: MapModel, faction: int, techs: Dictionary = {}) -> float:
	if model == null:
		return 0.0
	var thinnest: float = 0.0
	for province: int in model.province_count():
		var owner: int = model.province_owner(province)
		if owner == faction:
			continue
		var threshold: float = _wall(model, province, owner, techs)
		if threshold <= 0.0:
			continue
		if thinnest <= 0.0 or threshold < thinnest:
			thinnest = threshold
	return thinnest


## One province's wall plus battery, 0 for ground with no siege wall.
static func _wall(
	model: MapModel, province: int, owner: int, techs: Dictionary
) -> float:
	var level: int = FortRules.level_at(model, province)
	if not FortRules.is_siege(level):
		return 0.0
	if techs.is_empty():
		return FortRules.storm_ceiling(level)
	var tech: Variant = techs.get(owner, {})
	if not (tech is Dictionary):
		return FortRules.storm_ceiling(level)
	return FortRules.storm_threshold(tech as Dictionary, level)
