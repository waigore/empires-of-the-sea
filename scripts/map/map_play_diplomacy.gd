class_name MapPlayDiplomacy
extends RefCounted
## Court intents and the diplomacy phase for the map screen. Rules live in
## scripts/rules; this wires orders to the ledger and reports the outcome.
## Rival AI lives in MapPlayDiplomacyAi; pending consent prompts in
## MapPlayDiplomacyConsent.


static func open(play: PlaySession) -> void:
	if play.observer_mode:
		return
	if play.diplomacy == null:
		play.diplomacy = DiplomacyState.new()
		play.diplomacy.initialize(play.turn)
	play.diplomacy.human_faction = play.player_faction
	sync_first_contact(play)
	_install_terms(play)
	DiplomacyHud.show(
		play.hud.panels,
		play.diplomacy,
		play.world,
		play.player_faction,
		play.treasury(),
		_tech(play),
		play.court_reports,
		public_power(play),
		counsel(play)
	)


## The court's own envoy reading, one pick per crown the crown is in contact
## with: the order her staff's planner would spend this turn, with the row the
## panel marks from the same pick (`MapPlayDiplomacyPick`; DR-20261121-05,
## DR-20261122-11). Advice only — the sheet prints it and the crown still
## presses her own order (REQ-P5-06).
static func counsel(play: PlaySession) -> Dictionary:
	return MapPlayDiplomacyPick.picks(play)


## THE COURT on one court: the sheet a counsel line's own door opens, so a line
## that names a court — THE COLONIES' chain does — has its presses one tap away
## (wiki: diplomacy § The crown's own envoy; DR-20261123-05; REQ-P5-01,
## REQ-P5-03). Reads only: it declares, offers, boycotts and signs nothing.
##
## Returns false when the crown is not in contact with that court (or a session
## has no court sheet), so the caller can say so rather than leave the press
## silent (REQ-P5-05).
static func open_court(play: PlaySession, court: int) -> bool:
	if play == null or play.hud == null or play.observer_mode:
		return false
	if not can_open_court(play.diplomacy, play.player_faction, court):
		return false
	open(play)
	var panel: DiplomacyPanel = play.hud.panels.diplomacy_panel
	if panel == null:
		return false
	panel.select_faction(court)
	return true


## Whether THE COURT can stand on one court: the crown holds a relation with it —
## the one gate `DiplomacyPanel.select_faction` answers, read here so a door never
## promises a sheet it cannot stand on (REQ-P5-05).
static func can_open_court(state: DiplomacyState, player: int, court: int) -> bool:
	if state == null or court < 0 or court == player:
		return false
	return state.has_relation(player, court)


## The published power score for every crown, from the public order of battle
## `MapPlayCourtHoldings` reads once. The panel compares each court against the
## reader with it; no screen reads an army or a hull itself.
static func public_power(play: PlaySession) -> Dictionary:
	var orders: Dictionary = MapPlayCourtHoldings.public_orders(play)
	return DiplomacyPower.public_power(
		play.world,
		orders.get("strength", {}) as Dictionary,
		orders.get("ships", {}) as Dictionary
	)


static func refresh(play: PlaySession) -> void:
	if play.diplomacy == null or play.observer_mode:
		return
	# Trade terms always reach the market (FTP / boycott), even when the sheet
	# is shut. Envoy counsel and the power table are sheet-only: computing them
	# while the court is closed paid a full planner pass under coverage on every
	# order and consent resume (docs/testing.md § Speed rules).
	_install_terms(play)
	if play.hud == null or play.hud.panels == null or not play.hud.panels.is_diplomacy_open():
		return
	DiplomacyHud.refresh(
		play.hud.panels,
		play.diplomacy,
		play.world,
		play.player_faction,
		play.treasury(),
		_tech(play),
		play.court_reports,
		public_power(play),
		counsel(play)
	)


static func on_order(play: PlaySession, kind: String, target: int, arg: String) -> void:
	if play.campaign_over():
		return
	if play.diplomacy == null:
		return
	# While a consent decision waits, the court entertains no other business: the
	# order is refused and the panel opens on the answer the court owes first
	# (`ConsentLadder` owns that order).
	var waiting: String = ConsentLadder.pending_kind(play.diplomacy, play.player_faction)
	if not waiting.is_empty():
		play.hud.toast(ConsentCopy.held(waiting))
		MapPlayDiplomacyConsent.show_waiting(play, waiting)
		return
	var order: Dictionary = {"kind": kind, "from": play.player_faction, "target": target}
	if kind == DiplomacyOrders.KIND_OVERTURE:
		order["stage"] = arg
	elif kind == DiplomacyOrders.KIND_AID or kind == DiplomacyOrders.KIND_SUBSIDY:
		order["amount"] = arg.to_int()
	var economy: PlayerEconomy = play.economy.economy if play.economy != null else null
	var result: Dictionary = DiplomacyOrders.apply(
		play.diplomacy, play.world, economy, order, _tech(play), public_power(play)
	)
	var message: String = String(result.get("message", ""))
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The court refuses.")))
	elif not message.is_empty():
		play.hud.toast(message)
	for call_line: String in result.get("calls", []):
		if not call_line.is_empty():
			play.hud.toast(call_line)
	for news: String in result.get("interventions", []):
		if not news.is_empty():
			play.hud.toast(news)
	# An absorbed crown's units change colours with its provinces: fleets first,
	# then land regiments (wiki: diplomacy § GP–Minor Rules).
	if result.has("absorbed"):
		var loser: int = int(result["absorbed"])
		if play.ship_layer != null:
			play.ship_layer.transfer_owner(loser, play.player_faction)
		if play.army_layer != null:
			play.army_layer.transfer_owner(loser, play.player_faction)
	if bool(result.get("map_changed", false)):
		play.refresh_map_views()
	play.hud.stats.set_treasury(play.treasury())
	refresh(play)
	# War, peace and alliances repaint the political wash at once.
	MapPlayLens.mount_diplomacy(play)


## End-of-turn diplomacy phase: first contact, rival-court AI orders, subsidy
## upkeep, relation drift. Returns false when a call to arms suspends the turn
## before the phase can close (wiki: diplomacy § Alliances).
static func resolve_turn(play: PlaySession) -> bool:
	if play.diplomacy == null:
		return true
	sync_first_contact(play)
	# Despatch filtering stays off the AI surface (ai-bench binds that tree):
	# mute the lane while rivals act, then raise only crown-facing lines
	# (wiki: hud-toasts, the-gazette § Not the Gazette).
	var hud: GameHud = play.hud
	play.hud = null
	MapPlayDiplomacyAi.run(play)
	play.hud = hud
	_toast_rival_pass(play)
	if MapPlayDiplomacyConsent.hold_turn(play, play.human_faction_id()):
		return false
	close_turn(play)
	return true


## What the crown hears the moment the rival pass resolves, in the court's own
## voice. Only an act that names the crown is despatch news: a declaration on
## the crown governs this turn's movement and combat, and a treaty or offer
## aimed at it asks for an answer. Every act between other courts is World news
## the Gazette narrates and a spy's court report carries (wiki: hud-toasts).
static func _toast_rival_pass(play: PlaySession) -> void:
	if play.hud == null:
		return
	for record: Dictionary in play.ai_trace:
		for line: String in _crown_despatch(play, record):
			play.hud.toast(line)
	# The pass has just raised every new decision in its own words; the turn
	# resolver must not raise them a second time on the same press.
	MapPlayDiplomacyConsent.mark_announced(play)


static func _crown_despatch(play: PlaySession, record: Dictionary) -> Array[String]:
	var action: Dictionary = record.get("action", {}) as Dictionary
	# A record that names no action is a trace from before the pass kept them:
	# its lines were already filtered when it was written, so it still speaks.
	if not action.is_empty():
		var target: int = int(action.get("target", MapModel.NO_ID))
		if target != play.human_faction_id():
			return []
	var lines: Array[String] = []
	lines.assign(record.get("messages", []))
	if lines.is_empty():
		var message: String = String(record.get("message", ""))
		if not message.is_empty():
			lines.append(message)
	return lines


## Closes the diplomacy phase once no consent decision is outstanding.
static func close_turn(play: PlaySession) -> void:
	if play.diplomacy == null:
		return
	play.diplomacy.end_turn()
	# The phase is over: next turn's decisions are news again, even when they
	# repeat a pair that was told about this turn.
	play.announced_decisions.clear()
	refresh(play)


## A Tribe is contacted only by non-unknown tile visibility in its provinces;
## sea-reachable colonial intel alone does not count (wiki: diplomacy § first contact).
static func sync_first_contact(play: PlaySession) -> Array[int]:
	var contacted: Array[int] = []
	# The observer has no human court to open first contact for; rival courts
	# keep the relations seeded at setup (wiki: game-setup § Human/AI slots).
	if play.observer_mode:
		return contacted
	if play.diplomacy == null or play.world == null:
		return contacted
	for tribe: int in FactionCatalog.tribe_ids():
		if play.diplomacy.has_relation(play.player_faction, tribe):
			continue
		if not _sees_tribe(play, tribe):
			continue
		var relation: DiplomacyRelation = play.diplomacy.ensure_relation(
			play.player_faction, tribe, play.turn
		)
		## A crown whose leader publishes the Tribe lean opens friendlier than the
		## Neutral equilibrium (wiki: leader-bonuses § Bonus Table — Isabella).
		if relation != null:
			relation.set_score(LeaderCatalog.first_contact_score(
				String(play.leaders.get(play.player_faction, ""))
			))
		play.diplomacy.touch(play.player_faction, tribe, "firstContact")
		contacted.append(tribe)
	# The meeting reads on the Gazette's World page (its catalog carries public
	# first contact); the despatch lane does not announce it (wiki: hud-toasts).
	return contacted


static func _sees_tribe(play: PlaySession, tribe: int) -> bool:
	for region_index: int in play.visibility_by_region.keys():
		var visibility: VisibilityModel = play.visibility_by_region[region_index]
		if visibility == null or visibility.model == null:
			continue
		for province: ProvinceState in visibility.model.provinces:
			if province.owner != tribe:
				continue
			if visibility.province_visibility(province.id) != VisibilityModel.Level.UNKNOWN:
				return true
	return false


## Researched techs gate embassy and GP Join Empire orders
## (wiki: tech-tree-diplomacy-civilian).
static func _tech(play: PlaySession) -> Dictionary:
	if play.economy == null or play.economy.economy == null:
		return {}
	return play.economy.economy.tech_unlocked


## Publishes every crown's trade terms on the shared market, so a pact, boycott
## or subsidy reaches the ledger's prices (wiki: world-market § FTP).
static func _install_terms(play: PlaySession) -> void:
	var market: WorldMarket = play.economy.market if play.economy != null else null
	DiplomacyTrade.apply_terms(play.diplomacy, play.world, market)
