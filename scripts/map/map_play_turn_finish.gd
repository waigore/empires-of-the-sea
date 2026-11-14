class_name MapPlayTurnFinish
extends RefCounted
## The turn's finish: movement, rearmament, combat, upkeep and the new turn,
## once the diplomacy phase closed. MapPlayTurn owns the consent ladder and hands
## the resolved turn over here; every step below is a named phase of that one
## order, so a rules change lands in the phase that owns it and the kernel reads
## as the sequence it is (REQ-P3-02).
##
## Rules outcomes live in the modules each phase calls; this module only orders
## them, carries one turn's book between the phases and reports the result.


## One turn's book: what the marching passes reported and what the battles
## resolved. The later phases read it for the observer trace, the Gazette sheet
## and the spy despatch; nothing outside this module sees it.
class TurnBook:
	var invasion: Array[Dictionary] = []
	var army: Array[Dictionary] = []
	var colonisation: Array[Dictionary] = []
	var fleet: Array[Dictionary] = []
	var land_battles: Array[Dictionary] = []
	var naval_battles: Array[Dictionary] = []
	var economy_report: Dictionary = {}
	var crown_report: Dictionary = {}
	var raid_report: Dictionary = {}
	## The calendar year the new turn opens on, read once for the bar and the view.
	var year: int = 0


static func run(play: PlaySession) -> void:
	var book := TurnBook.new()
	_march(play, book)
	_rearm(play)
	_resolve_battles(play, book)
	if _close_if_decided(play, book):
		return
	_open_new_turn(play, book)


## Civilians work first, then the rival expeditions board and sail before the
## field armies march, so an army chosen for the crossing is not also ordered
## inland (docs/ai.md).
static func _march(play: PlaySession, book: TurnBook) -> void:
	MapPlayCivilians.resolve_work(play)
	book.invasion = MapPlayInvasionAi.run(play)
	book.army = MapPlayArmies.run_ai(play)
	# Colonisation counts every applied voyage step, so the observer's trace can
	# show an expedition crossing even when no army is aboard (issue #476).
	book.colonisation = MapPlayColonisationAi.run(play)
	book.fleet = MapPlayFleets.run_ai(play)


## Regiment upgrade runs after movement and before combat: a crown's men take up
## the newest pattern its own techs allow, and Minors follow the leading power
## (wiki: tech-tree-military § Infantry/Cavalry/Artillery; factions § Minor
## military parity).
static func _rearm(play: PlaySession) -> void:
	var tech_by_faction: Dictionary = MapPlayCampaign.tech_by_faction(play)
	var upgrades: Dictionary = RegimentUpgrades.apply(play.army_layer.regions, tech_by_faction)
	MilitaryParity.apply(play.army_layer.regions, tech_by_faction)
	if play.hud == null:
		return
	var rearmed: int = int((upgrades["by_faction"] as Dictionary).get(play.player_faction, 0))
	if rearmed > 0:
		play.hud.toast("%d regiment%s re-equipped with the new pattern" % [
			rearmed, "" if rearmed == 1 else "s"])


## Combat, then the passes that read the finished charts: spies, the crews left
## ashore by a conquest, fog decay and a rival court's first contact with the
## Tribes it has charted (wiki: diplomacy § GP–Tribe first contact).
static func _resolve_battles(play: PlaySession, book: TurnBook) -> void:
	book.land_battles = MapPlayLandTurn.resolve(play)
	book.naval_battles = MapPlayNavalTurn.resolve(play)
	MapPlaySpies.resolve(play)
	MapPlayCivilians.settle_stranding(play)  # crews caught by conquest
	MapPlayFogTurn.resolve(play)
	MapPlayCourtFog.resolve(play)
	MapPlayTribeContact.resolve(play)


## True when the campaign ended on this turn, so no new turn opens. The human
## crown's fall is answered before any victory check: defeat never hands the
## conqueror a military win (wiki: victory; DR-20261109-05).
static func _close_if_decided(play: PlaySession, book: TurnBook) -> bool:
	if play.defeat != null:
		play.emit_turn_ended(play.turn)
		return true
	# Victory is checked after every phase, once per turn, and never re-checked.
	# The crown's own bar carries the campaign's level; every rival keeps the
	# published one (wiki: victory § Military victory; DR-20261111-28).
	var victory: VictoryState = VictoryRules.resolve(
		play.victory, play.world, play.turn, play.human_faction_id(), play.difficulty
	)
	if victory != null:
		# The sheet still narrates the turn that decided the age: filed on its own
		# turn and left unraised, so the archive has no gap and the final turn's
		# news is read after the plate steps aside (wiki: the-gazette
		# § When it appears; victory § Victory Screen).
		_file_decided_sheet(play, book)
		MapPlayCampaign.close_victory(play, victory)
		return true
	# Military victory wins the turn; otherwise the calendar cap closes an
	# undecided campaign on its last full turn (wiki: turn-time-mapping).
	if VictoryRules.calendar_halt(play.turn, play.infinite_mode):
		_file_decided_sheet(play, book)
		MapPlayCampaign.close_calendar(play)
		return true
	return false


## The last turn's sheet, filed after a decided campaign. The other books are
## empty on purpose: the crown's ledger and the raids never ran for a turn that
## closed on combat.
static func _file_decided_sheet(play: PlaySession, book: TurnBook) -> void:
	MapPlayGazette.close_turn(
		play, book.land_battles, book.naval_battles, {}, {}, {}, play.turn, false
	)


static func _open_new_turn(play: PlaySession, book: TurnBook) -> void:
	_begin_layers(play)
	_rival_ledgers(play, book)
	play.turn += 1
	_crown_ledger(play, book)
	_report_turn(play, book)


## Every layer turns over onto the new turn before any ledger resolves: launched
## squadrons lose last turn's beachheads, and a turn's falls feed the Gazette's
## World page (DR-20261110-14). The sea settles its seats before the new turn's
## ledgers read the harbour: a rival that docked at its own capital through any
## planner folds into the home fleet (wiki: ships-and-naval § Home Fleet).
static func _begin_layers(play: PlaySession) -> void:
	play.ship_layer.expire_beachheads(play.turn)
	play.ship_layer.begin_turn()
	play.army_layer.begin_turn(play.world)
	MapPlayHomeMerge.settle_seats(play)
	play.last_falls.clear()
	MapPlayFleets.refresh_visibility(play)
	MapPlayArmies.refresh_visibility(play)


## Rival ledgers resolve on post-combat ownership and plan civilian work for the
## new turn; the observer runs every crown on that same pass. The raid pass runs
## after those buys and before the crown's ledger closes: both sides' cargo is
## afloat, and losses leave the stockpile before anything resolves (wiki:
## ships-and-naval § Trade and Transport Interception; DR-20261109-16,
## DR-20261110-13). The record is filed before the calendar advances, so it
## narrates the turn that just resolved.
static func _rival_ledgers(play: PlaySession, book: TurnBook) -> void:
	book.economy_report = MapPlayEconomyAi.run(play)
	book.raid_report = MapPlayRaids.resolve(play)
	AiTurnLog.record(
		play, book.army, book.fleet, book.economy_report, book.invasion,
		book.colonisation
	)


## The crown's own turn: the new turn's watch, its ledger, the shared market book
## and the bar. The observer answers from the rival pass instead, so its courts
## are never charged twice.
static func _crown_ledger(play: PlaySession, book: TurnBook) -> void:
	# The new turn opens the crown's watch: a rival squadron still under the same
	# eye that saw her last turn is read now, and her weight reaches the markers
	# (wiki: ships-and-naval § Sighted strength).
	MapPlayFleets.refresh_visibility(play)
	book.year = TurnTime.year_for_turn(play.turn)
	if play.observer_mode:
		AiTurnLog.apply_feeding(play, book.economy_report)
	else:
		play.refresh_research()
		play.economy.research_boost = MapPlayEspionage.research_boost(play)
		book.crown_report = play.economy.resolve_turn()
		# The crown's own rations are filed under the crown the player chose: a
		# rival's id must never carry them, and her own armies must read them at
		# the published feeding band (wiki: combat § Feeding modifiers;
		# game-setup § Human/AI slot assignment).
		play.feeding[play.player_faction] = play.economy.feeding_coverage()
		# The crown's own turn speaks: a finished study and a host at the seat
		# are answered by the courts before the panel is refreshed below
		# (wiki: dialogue-and-mood § Design intent; DR-20261111-08).
		MapPlayCourtVoice.record_turn(play, book.crown_report)
	# Every court has staged its orders by now: clear the shared book once.
	MapPlayMarket.run(play, book.economy_report)
	if not play.observer_mode:
		play.income = play.economy.projected_income()
	play.hud.set_turn(play.turn, book.year)
	if not play.observer_mode:
		play.hud.set_income(play.income)
		MapPlayDiplomacy.refresh(play)
	play.improvements.set_tech_caps(play.tech_caps())


## The turn's news, in reading order: the bar and the open dossiers follow the
## turn, the spy despatch names what the courts did, then the sheet narrates the
## turn that just resolved and opens only when it found news (wiki: the-gazette
## § When it appears).
static func _report_turn(play: PlaySession, book: TurnBook) -> void:
	_follow_view(play, book.year)
	MapPlaySpies.report(play, book.land_battles, book.naval_battles, book.economy_report)
	MapPlayGazette.close_turn(
		play, book.land_battles, book.naval_battles, book.economy_report,
		book.crown_report, book.raid_report
	)
	play.emit_turn_ended(play.turn)


## The turn's view follow-up: the toast, the open dossiers, the survey lens and
## the province sheet. Pure presentation — a headless run (`view_live` false)
## has nothing on screen to follow, so it skips the whole pass and the rules
## outcome is unchanged (docs/ai-observer.md § Performance budget).
static func _follow_view(play: PlaySession, year: int) -> void:
	if not MapPlayTurn.view_live:
		return
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
	play.improvements.refresh_if_open()
	# An open dossier follows the works, the town and the tech the turn changed.
	MapPlaySetup.refresh_dossier(play)
	MapPlaySetup.build_lens(play)
