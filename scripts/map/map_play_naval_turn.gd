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
		# Last turn's rations decide how hard each squadron can fight
		# (wiki: workers-and-population § Consumption).
		"navy_feeding": _navy_feeding(play),
		# A rival of the chosen difficulty fights its own strength
		# (wiki: ruleset-config § Difficulty).
		"difficulty": strength_multipliers(play),
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
		var place: String = zone
		if region != play.region_index:
			prefix = "%s — " % FactionCatalog.region_label(region)
			# The plate names one place in one sentence, so the chart rides in
			# brackets rather than a second dash.
			place = "%s (%s)" % [zone, FactionCatalog.region_label(region)]
		var line: String = prefix + BattleReport.describe(
			battle, zone, FactionCatalog.names()
		)
		# The human's own engagement reads on the sea's despatch plate, so the
		# despatch that repeats its outcome is the first line the held-news cap
		# may drop (REQ-P5-06). A rival's fight stays the court's news alone.
		var player: int = play.human_faction_id()
		var on_plate: bool = play.hud != null and (
			int(battle.get("attacker", -1)) == player or int(battle.get("defender", -1)) == player
		)
		if on_plate:
			play.hud.show_naval_dispatch(battle, place)
			play.hud.toast_plate_line(line, BattleReport.icon_of(battle))
		else:
			play.hud.toast(line, BattleReport.icon_of(battle))
	play.hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	play.emit_battle_resolved(battles)
	return battles


## The difficulty layer's strength factor per rival court, read by the resolver
## and the fleet dossier alike so the odds printed are the odds struck (wiki:
## ruleset-config § Difficulty; DR-20261111-24). The human crown is absent from
## the table and fights as published.
static func strength_multipliers(play: PlaySession) -> Dictionary:
	return Difficulty.combat_multipliers(
		play.human_faction_id(), play.difficulty, FactionCatalog.great_power_ids()
	)


## Each crown's last resolved navy coverage, read from its own ledger so the
## human and every rival answer the same rule (wiki: workers-and-population
## § Consumption). A crown with no ledger fights at full rations.
static func _navy_feeding(play: PlaySession) -> Dictionary:
	var feeding: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		var ledger: PlayerEconomy = play.ledger_for(faction)
		if ledger != null:
			feeding[faction] = ledger.navy_feeding
	return feeding


## Fleets at peace share a sea zone; only war makes them hostile (wiki:
## diplomacy § War required for hostile actions). Without a court, keep the
## legacy every-fleet-is-hostile behaviour for isolated fixtures.
static func _at_war(play: PlaySession, a: int, b: int) -> bool:
	return DiplomacyRules.at_war_with(play.diplomacy, a, b)
