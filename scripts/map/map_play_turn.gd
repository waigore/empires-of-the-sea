class_name MapPlayTurn
extends RefCounted
## End-of-turn resolution, capital framing, and the capital tile lookup.
## Combat and visibility rules stay in their own modules; this reports them.


static func end_turn(play: PlaySession) -> void:
	# The battle plate owns input while a Quick Battle plays; a second turn would
	# stack behind it (REQ-P5-06).
	if play.hud != null and play.hud.is_quick_battle_shown():
		return
	# A decided or calendar-closed campaign accepts no further turns
	# (wiki: victory § Victory Check, turn-time-mapping § Campaign calendar cap).
	if play.campaign_over():
		play.hud.toast(_closed_message(play))
		return
	# A consent decision already waiting keeps the calendar shut.
	var human: int = play.human_faction_id()
	if CallToArms.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacy.show_call(play)
		return
	if Intervention.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacy.show_intervention(play)
		return
	if DiplomacyProposals.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacy.show_offer(play)
		return
	if not MapPlayDiplomacy.resolve_turn(play):
		return
	_finish_turn(play)


## The player answers a call to arms; the suspended turn then runs to its end
## (wiki: diplomacy § Alliances § Mutual defence).
static func answer_call(play: PlaySession, accept: bool) -> void:
	if play.diplomacy == null:
		return
	# A stale button press must never close the phase or advance the calendar.
	if not CallToArms.has_pending(play.diplomacy, play.player_faction):
		return
	var result: Dictionary = CallToArms.resolve_human(play.diplomacy, accept)
	if not bool(result.get("ok", false)):
		if play.hud != null:
			play.hud.toast(String(result.get("reason", "No call awaits an answer.")))
		return
	if play.hud != null:
		var message: String = String(result.get("message", ""))
		if not message.is_empty():
			play.hud.toast(message)
	MapPlayDiplomacy.refresh(play)
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_call(play)
		return
	# A declaration may also have left an intervention offer for this court.
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_intervention(play)
		return
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_offer(play)
		return
	play.turn_suspended = false
	MapPlayDiplomacy.close_turn(play)
	_finish_turn(play)


## The player answers a waiting intervention; the suspended turn then runs to
## its end, or stops again for another waiting decision (wiki: diplomacy).
static func answer_intervention(play: PlaySession, kind: String) -> void:
	if play.diplomacy == null:
		return
	if not Intervention.has_pending(play.diplomacy, play.player_faction):
		return
	var result: Dictionary = Intervention.resolve_human(play.diplomacy, kind)
	if not bool(result.get("ok", false)):
		if play.hud != null:
			play.hud.toast(String(result.get("reason", "No intervention awaits an answer.")))
		return
	if play.hud != null:
		var message: String = String(result.get("message", ""))
		if not message.is_empty():
			play.hud.toast(message)
	MapPlayDiplomacy.refresh(play)
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_call(play)
		return
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_intervention(play)
		return
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_offer(play)
		return
	play.turn_suspended = false
	MapPlayDiplomacy.close_turn(play)
	_finish_turn(play)


## The player answers a rival proposal; the suspended turn then runs to its end,
## or stops again for another waiting decision (wiki: diplomacy § GP AI policy).
static func answer_offer(play: PlaySession, accept: bool) -> void:
	if play.diplomacy == null:
		return
	if not DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		return
	var result: Dictionary = DiplomacyProposals.resolve_human(
		play.diplomacy, play.world, accept
	)
	if not bool(result.get("ok", false)):
		if play.hud != null:
			play.hud.toast(String(result.get("reason", "No proposal awaits an answer.")))
		return
	# The proposing court pays for its overture; the human treasury is untouched.
	# A peace offer starts its own cooldown once the court answers; every other
	# proposal starts the improve-relations cooldown (DR-20261109-06/07).
	var from_id: int = int(result.get("from", -1))
	if play.ai != null:
		if String(result.get("kind", "")) == DiplomacyProposals.KIND_PEACE:
			play.ai.note_peace(from_id, play.player_faction, play.turn)
		else:
			play.ai.note_overture(from_id, play.player_faction, play.turn)
	if play.hud != null:
		var message: String = String(result.get("message", ""))
		if not message.is_empty():
			play.hud.toast(message)
	MapPlayDiplomacy.refresh(play)
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_call(play)
		return
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_intervention(play)
		return
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacy.show_offer(play)
		return
	play.turn_suspended = false
	MapPlayDiplomacy.close_turn(play)
	_finish_turn(play)


## Movement, combat, upkeep and the new turn, once the diplomacy phase closed.
static func _finish_turn(play: PlaySession) -> void:
	MapPlayCivilians.resolve_work(play)
	# Rival expeditions board and sail before the field armies march, so an army
	# chosen for the crossing is not also ordered inland (docs/ai.md).
	var invasion_trace: Array[Dictionary] = MapPlayInvasionAi.run(play)
	var army_trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	MapPlayColonisationAi.run(play)
	var fleet_trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	# Minor Regiment Upgrade runs after movement and before combat.
	MilitaryParity.apply(play.army_layer.regions, _great_power_tech(play))
	var land_battles: Array[Dictionary] = MapPlayArmies.resolve_battles(play)
	var naval_battles: Array[Dictionary] = _resolve_naval_combat(play)
	MapPlaySpies.resolve(play)
	_resolve_visibility(play)
	# The human crown's terminal fall seals the session before any victory
	# check: defeat never hands the conqueror a military win, nor opens that
	# plate on the same seal (wiki: victory § Victory Check § Defeat interaction;
	# DR-20261109-05).
	if play.defeat != null:
		play.emit_turn_ended(play.turn)
		return
	# Victory is checked after every phase, once per turn, and never re-checked.
	var victory: VictoryState = VictoryRules.resolve(play.victory, play.world, play.turn)
	if victory != null:
		_finish_campaign(play, victory)
		return
	# Military victory wins the turn; otherwise the calendar cap closes an
	# undecided campaign on its last full turn (wiki: turn-time-mapping).
	if VictoryRules.calendar_halt(play.turn, play.infinite_mode):
		_finish_calendar(play)
		return
	# Enemy patrols and blockades in the crown's home waters skim this turn's
	# imports before the ledger closes (wiki: ships-and-naval § Trade and
	# Transport Interception; DR-20261109-16).
	MapPlayRaids.resolve(play)
	play.ship_layer.expire_beachheads(play.turn)
	play.ship_layer.begin_turn()
	play.army_layer.begin_turn()
	MapPlayFleets.refresh_visibility(play)
	MapPlayArmies.refresh_visibility(play)
	# Rival ledgers resolve on post-combat ownership and plan civilian work for
	# the new turn; the observer runs every crown on that same pass.
	var economy_report: Dictionary = MapPlayEconomyAi.run(play)
	AiTurnLog.record(play, army_trace, fleet_trace, economy_report, invasion_trace)
	play.turn += 1
	var year: int = TurnTime.year_for_turn(play.turn)
	if play.observer_mode:
		AiTurnLog.apply_feeding(play, economy_report)
	else:
		play.refresh_research()
		MapPlaySpies.prepare_player_research(play)
		play.economy.resolve_turn()
		play.feeding[PlaySession.PLAYER_FACTION] = play.economy.feeding_coverage()
		play.income = play.economy.projected_income()
	play.hud.set_turn(play.turn, year)
	if not play.observer_mode:
		play.hud.set_income(play.income)
		MapPlayDiplomacy.refresh(play)
	play.hud.toast("Turn %d — %d" % [play.turn, year])
	var selected: Ship = play.ship_layer.selected()
	if selected != null:
		var fleet: FleetState = play.ship_layer.fleet_of(selected)
		if fleet != null:
			MapPlayFleets.show_dossier(play, fleet)
			MapPlayFleets.refresh_options(play, fleet)
	if play.civilian_layer.selected_unit != null:
		MapPlayCivilians.refresh_panel(play)
	if play.army_layer.selected_army != null:
		MapPlayArmies.refresh_panel(play)
	play.improvements.set_tech_caps(play.tech_caps())
	play.improvements.refresh_if_open()
	MapPlaySetup.build_lens(play)
	MapPlaySpies.report(play, land_battles, naval_battles, economy_report)
	play.emit_turn_ended(play.turn)


## Campaign decided: record the winner, mount the plate, and stop the calendar
## at the turn that decided it (wiki: victory § Victory Check).
static func _finish_campaign(play: PlaySession, victory: VictoryState) -> void:
	play.victory = victory
	if not play.observer_mode:
		play.hud.show_victory(
			victory,
			play.player_faction,
			VictoryRules.old_world_holdings(play.world, victory.winner_player_id)
		)
	play.hud.toast(victory.summary())
	play.emit_turn_ended(play.turn)
	play.emit_campaign_end(victory)


## The calendar closed the age without a military victory: record it, mount the
## campaign-complete plate, and leave the turn number on the last full turn
## (wiki: turn-time-mapping § Campaign calendar cap, victory § Calendar end).
static func _finish_calendar(play: PlaySession) -> void:
	play.campaign_halted = true
	var leader: int = declared_leader(play)
	if not play.observer_mode:
		play.hud.show_campaign_complete(leader, play.turn, play.player_faction)
	play.hud.toast(
		"Campaign complete — %d" % TurnTime.year_for_turn(play.turn)
	)
	play.emit_turn_ended(play.turn)


## Great Power research state for the Minor Regiment Upgrade pass. Rivals keep
## their tech in their own ledger; the human court's lives in EconomyController.
static func _great_power_tech(play: PlaySession) -> Dictionary:
	var tech: Dictionary = {}
	if play == null:
		return tech
	if play.economy != null and play.economy.economy != null:
		tech[play.player_faction] = play.economy.economy.tech_unlocked
	if play.ai == null:
		return tech
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		tech[faction] = play.ai.economy_for(faction).tech_unlocked
	return tech


## Strongest crown by power score, or NO_ID when the top score is shared. The
## strength term is the public order of battle — FPN + FPM over every regiment
## the crown holds, in both regions, without the general medal multiplier — and
## the hull term counts every ship it floats, again in both regions
## (wiki: victory § Calendar campaign end, diplomacy § Great Power power score).
static func declared_leader(play: PlaySession) -> int:
	var strength: Dictionary = {}
	var ships: Dictionary = {}
	if play.army_layer != null:
		for raw: Variant in play.army_layer.regions.values():
			var stored: Array = []
			stored.assign(raw)
			for army: ArmyState in stored:
				if army != null:
					strength[army.owner] = (
						float(strength.get(army.owner, 0.0)) + army.strength()
					)
	if play.ship_layer != null:
		for faction: int in FactionCatalog.great_power_ids():
			ships[faction] = play.ship_layer.hull_count_all(faction)
	return VictoryRules.declared_leader(play.world, strength, ships)


static func _closed_message(play: PlaySession) -> String:
	if play.defeat != null:
		return play.defeat.summary()
	if play.victory != null:
		return "Campaign ended — %s" % play.victory.winner_name()
	return "Campaign complete — the age has run its course"


static func focus_capital(play: PlaySession) -> void:
	play.camera.focus_on(capital_world(play), 0.7)


## World position of the ruler's seat: the capital tile from the capital-choice
## phase, falling back to the province centre when the map has no capital.
static func capital_world(play: PlaySession) -> Vector2:
	if play.capital_tile.x >= 0:
		return MapGeo.tile_center(play.capital_tile.x, play.capital_tile.y, PlaySession.TILE_SIZE)
	if play.capital_province >= 0:
		return play.model.province_center(play.capital_province) * PlaySession.TILE_SIZE
	return MapGeo.world_size(play.model, PlaySession.TILE_SIZE) * 0.5


static func capital_tile(play: PlaySession, province_id: int) -> Vector2i:
	return play.model.capital_tile_of(province_id)

## Fleets sharing a sea zone fight (wiki: ships-and-naval § Naval Combat).
static func _resolve_naval_combat(play: PlaySession) -> Array[Dictionary]:
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


## End-of-turn visibility for every region (wiki: fog-and-exploration). Knowledge
## decays off-screen too; only the shown region's fog texture is repainted.
static func _resolve_visibility(play: PlaySession) -> void:
	if play.visibility_by_region.is_empty():
		return
	for index in play.world.region_count():
		var visibility: VisibilityModel = play.visibility_by_region.get(index, null)
		if visibility == null:
			continue
		var at_sea: Array = []
		for fleet: FleetState in _fleets_of(play, index):
			if fleet.owner == play.player_faction and fleet.is_at_sea():
				at_sea.append(fleet.sea_zone)
		var held: Array = CivilianMovement.held_provinces(
			play.world.region(index), _civilians_of(play, index), play.player_faction
		)
		var changed: Array = visibility.end_of_turn(at_sea, held)
		if index == play.region_index and not changed.is_empty():
			play.overlay.sync_visibility(visibility, changed)


## Live roster for the shown region; stored table for the other.
static func _fleets_of(play: PlaySession, index: int) -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	if play.ship_layer == null:
		return fleets
	if index == play.region_index:
		return play.ship_layer.fleets
	fleets.assign(play.ship_layer.regions.value(index, []))
	return fleets


static func _civilians_of(play: PlaySession, index: int) -> Array[CivilianState]:
	var units: Array[CivilianState] = []
	if play.civilian_layer == null:
		return units
	if index == play.region_index:
		return play.civilian_layer.units
	units.assign(play.civilian_layer.regions.value(index, []))
	return units


## Fleets at peace share a sea zone; only war makes them hostile (wiki:
## diplomacy § War required for hostile actions). Without a court, keep the
## legacy every-fleet-is-hostile behaviour for isolated fixtures.
static func _at_war(play: PlaySession, a: int, b: int) -> bool:
	return DiplomacyRules.at_war_with(play.diplomacy, a, b)
