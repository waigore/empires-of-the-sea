class_name MapPlayNavalTurn
extends RefCounted
## End-of-turn naval combat: fleets that end movement in the same sea zone
## fight, and losses are pruned from the armies and civilians they carried
## (wiki: ships-and-naval § Naval Combat). Rules resolve each battle; this only
## prunes markers, reports the outcome and emits the plate signal.


## Resolves every sea-zone battle this turn, drops the drowned passengers,
## reports each clash and returns the battles for the turn report. Tokens are
## pruned even in a turn without a battle.
static func resolve(play: PlaySession) -> Array[Dictionary]:
	var hostile := func(a: int, b: int) -> bool:
		return _at_war(play, a, b)
	var tech_gate: Callable = play.has_tech
	var context: Dictionary = {
		"seed": play.map_seed, "turn": play.turn, "has_tech": tech_gate,
	}
	var battles: Array[Dictionary] = play.ship_layer.resolve_battles(
		play.world, hostile, context
	)
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(
		play.army_layer, FleetRosters.carried_armies(play.ship_layer.regions)
	)
	for army: ArmyState in lost:
		play.hud.toast(
			"%d regiments went down with a sunken squadron" % army.count()
		)
	for _unit: CivilianState in CivilianVoyageMap.drop_lost(
		play.civilian_layer, FleetRosters.carried_civilians(play.ship_layer.regions)
	):
		play.hud.toast(
			"A civilian went down with a sunken squadron — lost at sea"
		)
	if battles.is_empty():
		return battles
	for battle: Dictionary in battles:
		var region: int = int(battle.get("region", play.region_index))
		var model: MapModel = (
			play.model if region == play.region_index else play.world.region(region)
		)
		var zone: String = model.sea_zone_name(int(battle["zone"])) if model != null else "—"
		var prefix: String = ""
		if region != play.region_index:
			prefix = "%s — " % FactionCatalog.region_label(region)
		play.hud.toast(prefix + BattleReport.describe(battle, zone, FactionCatalog.names()))
	play.hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	play.emit_battle_resolved(battles)
	return battles


## Fleets at peace share a sea zone; only war makes them hostile (wiki:
## diplomacy § War required for hostile actions). Without a court, keep the
## legacy every-fleet-is-hostile behaviour for isolated fixtures.
static func _at_war(play: PlaySession, a: int, b: int) -> bool:
	return DiplomacyRules.at_war_with(play.diplomacy, a, b)
