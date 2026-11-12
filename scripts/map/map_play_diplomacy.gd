class_name MapPlayDiplomacy
extends RefCounted
## Court intents and the diplomacy phase for the map screen. Rules live in
## scripts/rules; AI, pending consent and first contact live in sibling map-play
## modules. This wires orders to the ledger and reports the outcome.


static func open(play: PlaySession) -> void:
	if play.observer_mode:
		return
	if play.diplomacy == null:
		play.diplomacy = DiplomacyState.new()
		play.diplomacy.initialize(play.turn)
	play.diplomacy.human_faction = play.player_faction
	MapPlayFirstContact.sync(play)
	_install_terms(play)
	DiplomacyHud.show(
		play.hud.panels,
		play.diplomacy,
		play.world,
		play.player_faction,
		play.treasury(),
		_tech(play),
		play.court_reports,
		public_power(play)
	)


## The public order of battle every crown's power score is read from: FPN + FPM
## over every land army, without the general medal multiplier, and every hull —
## each summed across both regions (wiki: diplomacy § Great Power power score).
## The campaign close reads the same terms in MapPlayCampaign.declared_leader;
## this pass is the one the court panel opens with.
static func public_orders(play: PlaySession) -> Dictionary:
	var strength: Dictionary = {}
	var ships: Dictionary = {}
	if play.army_layer != null:
		for raw: Variant in play.army_layer.regions.values():
			var stored: Array[ArmyState] = []
			stored.assign(raw)
			for army: ArmyState in stored:
				if army == null:
					continue
				strength[army.owner] = float(strength.get(army.owner, 0.0)) + army.strength()
	if play.ship_layer != null:
		for faction: int in FactionCatalog.great_power_ids():
			ships[faction] = play.ship_layer.hull_count_all(faction)
	return {"strength": strength, "ships": ships}


## The published power score for every crown, from those orders. The panel
## compares each court against the reader with it; no screen reads an army or a
## hull itself.
static func public_power(play: PlaySession) -> Dictionary:
	var orders: Dictionary = public_orders(play)
	return DiplomacyPower.public_power(
		play.world,
		orders.get("strength", {}) as Dictionary,
		orders.get("ships", {}) as Dictionary
	)


static func refresh(play: PlaySession) -> void:
	if play.diplomacy == null or play.observer_mode:
		return
	_install_terms(play)
	DiplomacyHud.refresh(
		play.hud.panels,
		play.diplomacy,
		play.world,
		play.player_faction,
		play.treasury(),
		_tech(play),
		play.court_reports,
		public_power(play)
	)


static func on_order(play: PlaySession, kind: String, target: int, arg: String) -> void:
	if play.campaign_over():
		return
	if play.diplomacy == null:
		return
	# While a call to arms waits, the court entertains no other business.
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		play.hud.toast("Answer the call to arms first.")
		MapPlayDiplomacyPending.show_call(play)
		return
	# An intervention offer holds the court just as firmly.
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		play.hud.toast("Answer the intervention first.")
		MapPlayDiplomacyPending.show_intervention(play)
		return
	# A rival proposal waits for the court's answer before any new business.
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		play.hud.toast("Answer the proposal first.")
		MapPlayDiplomacyPending.show_offer(play)
		return
	var order: Dictionary = {"kind": kind, "from": play.player_faction, "target": target}
	if kind == DiplomacyOrders.KIND_OVERTURE:
		order["stage"] = arg
	elif kind == DiplomacyOrders.KIND_AID or kind == DiplomacyOrders.KIND_SUBSIDY:
		order["amount"] = arg.to_int()
	var economy: PlayerEconomy = play.economy.economy if play.economy != null else null
	var result: Dictionary = DiplomacyOrders.apply(
		play.diplomacy, play.world, economy, order, _tech(play)
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
	play.hud.set_treasury(play.treasury())
	refresh(play)
	# War, peace and alliances repaint the political wash at once.
	MapPlaySetup.build_diplomacy_lens(play)


## End-of-turn diplomacy phase: first contact, rival-court AI orders, subsidy
## upkeep, relation drift. Returns false when a call to arms suspends the turn
## before the phase can close (wiki: diplomacy § Alliances).
static func resolve_turn(play: PlaySession) -> bool:
	if play.diplomacy == null:
		return true
	MapPlayFirstContact.sync(play)
	MapPlayDiplomacyAi.run(play)
	var human: int = play.human_faction_id()
	if CallToArms.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyPending.show_call(play)
		return false
	if Intervention.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyPending.show_intervention(play)
		return false
	if DiplomacyProposals.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyPending.show_offer(play)
		return false
	close_turn(play)
	return true


## Closes the diplomacy phase once no consent decision is outstanding.
static func close_turn(play: PlaySession) -> void:
	if play.diplomacy == null:
		return
	play.diplomacy.end_turn()
	# The phase is over: next turn's decisions are news again, even when they
	# repeat a pair that was told about this turn.
	play.announced_decisions.clear()
	refresh(play)


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
