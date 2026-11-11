class_name MapPlayDiplomacy
extends RefCounted
## Court intents and the diplomacy phase for the map screen. Rules live in
## scripts/rules; this wires orders to the ledger and reports the outcome.


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
		show_call(play)
		return
	# An intervention offer holds the court just as firmly.
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		play.hud.toast("Answer the intervention first.")
		show_intervention(play)
		return
	# A rival proposal waits for the court's answer before any new business.
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		play.hud.toast("Answer the proposal first.")
		show_offer(play)
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
		_rebuild_map(play)
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
	sync_first_contact(play)
	run_ai(play)
	var human: int = play.human_faction_id()
	if CallToArms.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacy.show_call(play)
		return false
	if Intervention.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacy.show_intervention(play)
		return false
	if DiplomacyProposals.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacy.show_offer(play)
		return false
	close_turn(play)
	return true


## Closes the diplomacy phase once no consent decision is outstanding.
static func close_turn(play: PlaySession) -> void:
	if play.diplomacy == null:
		return
	play.diplomacy.end_turn()
	refresh(play)


## Opens the court on the waiting call and tells the player what is at stake.
static func show_call(play: PlaySession) -> void:
	if play.diplomacy == null or play.hud == null:
		return
	var call: Dictionary = CallToArms.pending_call_for(play.diplomacy, play.player_faction)
	if call.is_empty():
		return
	open(play)
	play.hud.toast(
		"%s calls on our alliance against %s."
		% [
			FactionCatalog.name_of(int(call["defender"])),
			FactionCatalog.name_of(int(call["aggressor"])),
		]
	)


## Opens the court on a waiting intervention and names what is at stake.
static func show_intervention(play: PlaySession) -> void:
	if play.diplomacy == null or play.hud == null:
		return
	var offer: Dictionary = Intervention.pending_for(play.diplomacy, play.player_faction)
	if offer.is_empty():
		return
	open(play)
	play.hud.toast(
		"%s declares war on %s. %s"
		% [
			FactionCatalog.name_of(int(offer["aggressor"])),
			FactionCatalog.name_of(int(offer["target"])),
			Intervention.offer_text(offer),
		]
	)


## Opens the court on a waiting rival proposal and names what is offered.
static func show_offer(play: PlaySession) -> void:
	if play.diplomacy == null or play.hud == null:
		return
	var offer: Dictionary = DiplomacyProposals.pending_for(
		play.diplomacy, play.player_faction
	)
	if offer.is_empty():
		return
	open(play)
	play.hud.toast(
		"%s proposes %s. Answer the proposal."
		% [
			FactionCatalog.name_of(int(offer["from"])),
			DiplomacyProposals.describe(
				String(offer["kind"]), String(offer.get("stage", ""))
			),
		]
	)


## Rival Great Powers take their one diplomatic action for the turn before the
## phase closes, so declarations apply to this turn's movement and combat
## (wiki: diplomacy § Turn Sequence).
static func run_ai(play: PlaySession) -> void:
	if play.ai == null:
		play.ai = AiState.new()
	var result: Dictionary = AiTurn.run(
		play.diplomacy,
		play.world,
		play.ai,
		play.turn,
		play.human_faction_id(),
		play.map_seed,
		_ai_context(play)
	)
	play.ai_trace.assign(result.get("trace", []))
	_apply_ai_map_changes(play, result.get("trace", []))
	if play.hud == null:
		return
	for message: String in result.get("messages", []):
		play.hud.toast(message)


## A rival that absorbs a Minor moves provinces: its units change colour and the
## chart is rebuilt, exactly as the court's own Join Empire order does.
static func _apply_ai_map_changes(play: PlaySession, trace: Array) -> void:
	for record: Dictionary in trace:
		var result: Dictionary = record.get("result", {})
		if not bool(result.get("map_changed", false)) and not result.has("absorbed"):
			continue
		var loser: int = int(result.get("absorbed", -1))
		if loser >= 0:
			var winner: int = int(record.get("faction", -1))
			if play.ship_layer != null:
				play.ship_layer.transfer_owner(loser, winner)
			if play.army_layer != null:
				play.army_layer.transfer_owner(loser, winner)
		_rebuild_map(play)


## Unit counts the war-desire score reads plus each rival's stockpile, so the
## resource-need bonus is live once the AI economy exists (wiki: diplomacy-planner).
static func _ai_context(play: PlaySession) -> Dictionary:
	var regiments: Dictionary = {}
	var ships: Dictionary = {}
	for raw: Dictionary in FactionCatalog.all():
		var faction: int = int(raw["id"])
		if play.army_layer != null:
			regiments[faction] = play.army_layer.regiment_count_all(faction)
		if play.ship_layer != null:
			ships[faction] = play.ship_layer.hull_count_all(faction)
	var context: Dictionary = {"regiments": regiments, "ships": ships}
	if play.ai != null:
		context["stockpiles"] = play.ai.stockpiles(play.human_faction_id())
	# The courts' own charts let a rival value the envoy chain that opens a coast
	# it has found but may not survey (DR-20261111-05).
	if play.court_charts != null:
		context["charts"] = play.court_charts
	return context


## A Tribe is contacted only by non-unknown tile visibility in its provinces;
## sea-reachable colonial intel alone does not count (wiki: diplomacy § first
## contact). This is the human crown's pass, made after turn resolution, and it
## returns the Tribes newly met so the herald can name them.
static func sync_first_contact(play: PlaySession) -> Array[int]:
	var contacted: Array[int] = []
	if play.diplomacy == null or play.world == null:
		return contacted
	var human: int = play.human_faction_id()
	if human < 0:
		return contacted
	for tribe: int in FactionCatalog.tribe_ids():
		if not _meets_tribe(play, human, tribe):
			continue
		contacted.append(tribe)
	if not contacted.is_empty() and play.hud != null:
		var names: PackedStringArray = []
		for tribe: int in contacted:
			names.append(FactionCatalog.name_of(tribe))
		play.hud.toast("First contact: %s" % ", ".join(names))
	return contacted


## The same rule for every AI court, silently and once per pair, after the
## end-of-turn fog pass has settled what each court can see (wiki: diplomacy
## § GP–Tribe first contact — "first-contact relations are persisted during turn
## resolution at end-of-turn"). A rival that charts a New World shore therefore
## meets the Tribe that holds it, which is what lets it treat — or war — there
## (DR-20261111-05).
static func sync_rival_contact(play: PlaySession) -> Array[int]:
	var met: Array[int] = []
	if play.diplomacy == null or play.world == null:
		return met
	var human: int = play.human_faction_id()
	for court: int in FactionCatalog.great_power_ids():
		if court == human:
			continue
		for tribe: int in FactionCatalog.tribe_ids():
			if _meets_tribe(play, court, tribe):
				met.append(tribe)
	return met


## Opens the relation when this court holds a charted tile of the Tribe's land
## and has not met it yet. True when a relation was made.
static func _meets_tribe(play: PlaySession, court: int, tribe: int) -> bool:
	if play.diplomacy.has_relation(court, tribe):
		return false
	if not _sees_tribe(play, court, tribe):
		return false
	play.diplomacy.ensure_relation(court, tribe, play.turn)
	play.diplomacy.touch(court, tribe, "firstContact")
	return true


## Whether one court's own chart holds any tile of a Tribe's land. The human
## reads the session's table directly; a rival reads the grid CourtCharts keeps.
static func _sees_tribe(play: PlaySession, court: int, tribe: int) -> bool:
	var views: Dictionary = play.visibility_by_region
	if play.court_charts != null and court != play.player_faction:
		views = play.court_charts.regions_of(court)
	for region_index: int in views.keys():
		var visibility: VisibilityModel = views[region_index]
		if visibility == null or visibility.model == null:
			continue
		for province: ProvinceState in visibility.model.provinces:
			if province.owner != tribe:
				continue
			if visibility.province_visibility(province.id) != VisibilityModel.Level.UNKNOWN:
				return true
	return false


static func _rebuild_map(play: PlaySession) -> void:
	play.refresh_map_views()


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
