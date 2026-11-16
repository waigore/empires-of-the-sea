class_name BattleTrace
extends RefCounted
## Combat's rows in the merged observer turn record (wiki:
## turn-trace-interpretation § Observer export). The full-AI observer hides the
## HUD, so it has no plate, no Gazette and no toast: the observatory panel's
## orders feed and the per-turn record are the only narration a run has. Without
## these rows a siege resolves in silence — the standing loses regiments and a
## fort level with nothing naming the fight.
##
## Files after `AiTurnLog.record` has written the turn's record, from the book
## `MapPlayTurnFinish` keeps: the adapter owns the Combat pass, the merged record
## and its event cap belong to [AiTurnLog]. Pure translation, worded by the same
## [BattleReport] the live despatch uses, so the observer reads exactly the
## sentence a crown would.

const NO_ID: int = MapModel.NO_ID


## Writes one turn's Combat pass into an already-written merged record: land
## battles first, then sea battles, each in the order the rules resolved them.
## The event is filed under the attacker, whose sentence names both courts.
static func record(
	merged: Dictionary, play: PlaySession,
	land: Array[Dictionary], naval: Array[Dictionary]
) -> void:
	var factions: Dictionary = merged.get("factions", {})
	for battle: Dictionary in land:
		_file(
			merged, factions, battle,
			BattleReport.describe_land(
				battle, _province_name(play, battle), FactionCatalog.names()
			)
		)
	for battle: Dictionary in naval:
		_file(
			merged, factions, battle,
			BattleReport.describe(
				battle, _zone_name(play, battle), FactionCatalog.names()
			)
		)


static func _file(
	merged: Dictionary, factions: Dictionary, battle: Dictionary, text: String
) -> void:
	var attacker: int = int(battle.get("attacker", NO_ID))
	if not factions.has(attacker):
		return
	AiTurnLog.event(merged, factions[attacker], attacker, text)


## The province the fight was in, read from the region the record names (a
## battle in another theatre still names its own place).
static func _province_name(play: PlaySession, battle: Dictionary) -> String:
	var model: MapModel = _model(play, battle)
	if model == null:
		return "—"
	return model.province_name(int(battle.get("province", -1)))


static func _zone_name(play: PlaySession, battle: Dictionary) -> String:
	var model: MapModel = _model(play, battle)
	if model == null:
		return "—"
	return model.sea_zone_name(int(battle.get("zone", -1)))


static func _model(play: PlaySession, battle: Dictionary) -> MapModel:
	if play == null or play.world == null:
		return null
	var region: int = int(battle.get("region", play.region_index))
	if region == play.region_index:
		return play.model
	return play.world.region(region)
