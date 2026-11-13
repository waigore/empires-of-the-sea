class_name MapPlayTurn
extends RefCounted
## Turn closure: the consent ladder, then movement/combat/upkeep and the new
## turn. Campaign close and standing live in MapPlayCampaign, land battles in
## MapPlayLandTurn, sea battles in MapPlayNavalTurn, fog decay in MapPlayFogTurn
## (REQ-P3-02). This only orders them and reports what the rules decided.


static func end_turn(play: PlaySession) -> void:
	# The battle plate owns input while a Quick Battle plays; a second turn would
	# stack behind it (REQ-P5-06).
	if play.hud != null and play.hud.is_quick_battle_shown():
		return
	# A decided or calendar-closed campaign accepts no further turns
	# (wiki: victory § Victory Check, turn-time-mapping § Campaign calendar cap).
	if play.campaign_over():
		play.hud.toast(MapPlayCampaign.closed_message(play))
		return
	# A consent decision already waiting keeps the calendar shut.
	var human: int = play.human_faction_id()
	if CallToArms.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyConsent.show_call(play)
		return
	if Intervention.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyConsent.show_intervention(play)
		return
	if DiplomacyProposals.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyConsent.show_offer(play)
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
	if _show_pending(play):
		return
	play.turn_suspended = false
	MapPlayDiplomacy.close_turn(play)
	_finish_turn(play)


## The player answers a waiting intervention; the suspended turn then runs to
## its end, or stops again for another waiting decision (wiki: diplomacy).
static func answer_intervention(play: PlaySession, kind: String) -> void:
	if play.diplomacy == null:
		return
	var offer: Dictionary = Intervention.pending_for(play.diplomacy, play.player_faction)
	if offer.is_empty():
		return
	# Protesting an aggressor holding Propaganda costs 5, not 10; the rules read
	# that crown's ledger, never ours (wiki: tech-tree-diplomacy-civilian).
	var ledger: PlayerEconomy = play.ledger_for(int(offer.get("aggressor", -1)))
	var tech: Dictionary = ledger.tech_unlocked if ledger != null else {}
	var result: Dictionary = Intervention.resolve_human(play.diplomacy, kind, tech)
	if not bool(result.get("ok", false)):
		if play.hud != null:
			play.hud.toast(String(result.get("reason", "No intervention awaits an answer.")))
		return
	if play.hud != null:
		var message: String = String(result.get("message", ""))
		if not message.is_empty():
			play.hud.toast(message)
	MapPlayDiplomacy.refresh(play)
	if _show_pending(play):
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
	var result: Dictionary = DiplomacyProposals.resolve_human(play.diplomacy, play.world, accept)
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
	if _show_pending(play):
		return
	play.turn_suspended = false
	MapPlayDiplomacy.close_turn(play)
	_finish_turn(play)


## Opens the court on whichever consent decision still waits — a call to arms,
## an intervention or a rival proposal — so each answer path resumes the same
## ladder. True when one did.
static func _show_pending(play: PlaySession) -> bool:
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacyConsent.show_call(play)
		return true
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacyConsent.show_intervention(play)
		return true
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacyConsent.show_offer(play)
		return true
	return false


## Movement, combat, upkeep and the new turn, once the diplomacy phase closed.
static func _finish_turn(play: PlaySession) -> void:
	MapPlayCivilians.resolve_work(play)
	# Rival expeditions board and sail before the field armies march, so an army
	# chosen for the crossing is not also ordered inland (docs/ai.md).
	var invasion_trace: Array[Dictionary] = MapPlayInvasionAi.run(play)
	var army_trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	MapPlayColonisationAi.run(play)
	var fleet_trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	# Regiment upgrade runs after movement and before combat: a crown's men take
	# up the newest pattern its own techs allow, and Minors follow the leading
	# power (wiki: tech-tree-military § Infantry/Cavalry/Artillery; factions
	# § Minor military parity).
	var tech_by_faction: Dictionary = MapPlayCampaign.tech_by_faction(play)
	var upgrades: Dictionary = RegimentUpgrades.apply(play.army_layer.regions, tech_by_faction)
	MilitaryParity.apply(play.army_layer.regions, tech_by_faction)
	if play.hud != null:
		var rearmed: int = int((upgrades["by_faction"] as Dictionary).get(play.player_faction, 0))
		if rearmed > 0:
			play.hud.toast("%d regiment%s re-equipped with the new pattern" % [
				rearmed, "" if rearmed == 1 else "s"])
	var land_battles: Array[Dictionary] = MapPlayLandTurn.resolve(play)
	var naval_battles: Array[Dictionary] = MapPlayNavalTurn.resolve(play)
	MapPlaySpies.resolve(play)
	MapPlayCivilians.settle_stranding(play)  # crews caught by conquest
	MapPlayFogTurn.resolve(play)
	MapPlayCourtFog.resolve(play)
	# Every chart is final now, so a rival court opens first contact with the
	# Tribes it has charted before the turn closes (wiki: diplomacy § GP–Tribe
	# first contact).
	MapPlayTribeContact.resolve(play)
	# The human crown's terminal fall seals the session before any victory check:
	# defeat never hands the conqueror a military win (wiki: victory; DR-20261109-05).
	if play.defeat != null:
		play.emit_turn_ended(play.turn)
		return
	# Victory is checked after every phase, once per turn, and never re-checked.
	# The crown's own bar carries the campaign's level; every rival keeps the
	# published one (wiki: victory § Military victory; DR-20261111-28).
	var victory: VictoryState = VictoryRules.resolve(
		play.victory, play.world, play.turn, play.human_faction_id(), play.difficulty
	)
	if victory != null:
		MapPlayCampaign.close_victory(play, victory)
		return
	# Military victory wins the turn; otherwise the calendar cap closes an
	# undecided campaign on its last full turn (wiki: turn-time-mapping).
	if VictoryRules.calendar_halt(play.turn, play.infinite_mode):
		MapPlayCampaign.close_calendar(play)
		return
	# The raid pass runs after the rival ledgers book the new turn's buys and
	# before the crown's ledger closes: both sides' cargo is afloat, and losses
	# leave the stockpile before anything resolves (wiki: ships-and-naval
	# § Trade and Transport Interception; DR-20261109-16, DR-20261110-13).
	play.ship_layer.expire_beachheads(play.turn)
	play.ship_layer.begin_turn()
	play.army_layer.begin_turn(play.world)
	# A turn's falls feed the Gazette's World page (DR-20261110-14).
	play.last_falls.clear()
	MapPlayFleets.refresh_visibility(play)
	MapPlayArmies.refresh_visibility(play)
	# Rival ledgers resolve on post-combat ownership and plan civilian work for
	# the new turn; the observer runs every crown on that same pass.
	var economy_report: Dictionary = MapPlayEconomyAi.run(play)
	var raid_report: Dictionary = MapPlayRaids.resolve(play)
	AiTurnLog.record(play, army_trace, fleet_trace, economy_report, invasion_trace)
	play.turn += 1
	# The new turn opens the crown's watch: a rival squadron still under the same
	# eye that saw her last turn is read now, and her weight reaches the markers
	# (wiki: ships-and-naval § Sighted strength).
	MapPlayFleets.refresh_visibility(play)
	var year: int = TurnTime.year_for_turn(play.turn)
	var crown_report: Dictionary = {}
	if play.observer_mode:
		AiTurnLog.apply_feeding(play, economy_report)
	else:
		play.refresh_research()
		play.economy.research_boost = MapPlayEspionage.research_boost(play)
		crown_report = play.economy.resolve_turn()
		play.feeding[PlaySession.PLAYER_FACTION] = play.economy.feeding_coverage()
		# The crown's own turn speaks: a finished study and a host at the seat
		# are answered by the courts before the panel is refreshed below
		# (wiki: dialogue-and-mood § Design intent; DR-20261111-08).
		MapPlayCourtVoice.record_turn(play, crown_report)
	# Every court has staged its orders by now: clear the shared book once.
	MapPlayMarket.run(play, economy_report)
	if not play.observer_mode:
		play.income = play.economy.projected_income()
	play.hud.set_turn(play.turn, year)
	if not play.observer_mode:
		play.hud.set_income(play.income)
		MapPlayDiplomacy.refresh(play)
	var market_line: String = LedgerText.market_summary(
		play.market_report, play.player_faction
	)
	if play.observer_mode or market_line.is_empty():
		play.hud.toast("Turn %d — %d" % [play.turn, year])
	else:
		play.hud.toast("Turn %d — %d. %s" % [play.turn, year, market_line])
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
	# An open dossier follows the works, the town and the tech the turn changed.
	MapPlaySetup.refresh_dossier(play)
	MapPlaySetup.build_lens(play)
	MapPlaySpies.report(play, land_battles, naval_battles, economy_report)
	# The sheet narrates the turn that just resolved; the overlay opens only when
	# it found news (wiki: the-gazette § When it appears).
	MapPlayGazette.close_turn(
		play, land_battles, naval_battles, economy_report, crown_report, raid_report
	)
	play.emit_turn_ended(play.turn)
