extends SceneTree
## Headless free-playtest drive for the trade-deal relation boost (wiki:
## diplomacy § Relation Model — trade-deal boost, R10). A crown that clears a
## world-market deal with a court is lifted the next Diplomacy phase, before
## decay, once per pair: +2.0 base, +0.4 while an Embassy is in effect, +0.2 per
## subsidy percentage point. This drive buys a Minor's harvest, closes the turn
## that settles it, and reads the pair's score across the next close.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_trade_boost.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(
		self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100
	)
	if _screen == null:
		_finish()
		return
	var play: PlaySession = _screen.play
	_say("seed %s — turn %d, treasury %s" % [
		SEED_TEXT, play.turn, DiplomacyCatalog.money(play.treasury()),
	])
	var offer: Dictionary = _buyable_offer(play)
	if offer.is_empty():
		_say("no Minor or Tribe offer is buyable this turn — nothing to read")
		_finish()
		return
	var seller: int = int(offer.get("faction", -1))
	var commodity: String = String(offer.get("commodity", ""))
	var pair: String = play.diplomacy.pair_key(play.player_faction, seller)
	var before: float = play.diplomacy.relation(play.player_faction, seller).score
	_say("--- buying %s from %s (pair %s, score %.1f) ---" % [
		CommodityCatalog.label(commodity), FactionCatalog.name_of(seller), pair, before,
	])
	var staged: Dictionary = play.economy.orders.trade(commodity, 1, true)
	if not bool(staged.get("ok", false)):
		_say("the ledger refused the bid: %s" % String(staged.get("reason", "")))
		_finish()
		return
	_end_turn(play)
	_say("after the settling close (turn %d): recorded=%s, score %.1f" % [
		play.turn,
		str(play.diplomacy.trade_pairs.has(pair)),
		play.diplomacy.relation(play.player_faction, seller).score,
	])
	_say(_boost_events(play.diplomacy))
	_end_turn(play)
	var after: float = play.diplomacy.relation(play.player_faction, seller).score
	var embassy: bool = DiplomacyRules.has_embassy(play.diplomacy, play.player_faction, seller)
	var percent: int = maxi(
		play.diplomacy.subsidy(play.player_faction, seller),
		play.diplomacy.subsidy(seller, play.player_faction)
	)
	var expected: float = 2.0 + (0.4 if embassy else 0.0) + 0.2 * float(percent)
	_say("after the paying close (turn %d): score %.1f (expected %.1f = %.1f + %.1f embassy + %.1f subsidy)" % [
		play.turn, after, before + expected, before, 0.4 if embassy else 0.0, 0.2 * float(percent),
	])
	_say(_boost_events(play.diplomacy))
	_say("the pair's record is consumed: %s" % str(not play.diplomacy.trade_pairs.has(pair)))
	_finish()


## Every trade-deal lift the phase has paid, so the receipt names the turn.
func _boost_events(state: DiplomacyState) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for raw: Variant in state.events:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw
		if String(event.get("kind", "")) != "tradeDealBoost":
			continue
		lines.append("turn %d: %d>%d +%s" % [
			int(event.get("turn", -1)), int(event.get("a", -1)), int(event.get("b", -1)),
			str((event.get("data", {}) as Dictionary).get("delta", 0.0)),
		])
	if lines.is_empty():
		return "  no trade-deal lift has been paid yet"
	return "  lifts: " + " · ".join(lines)


## The first Minor/Tribe offer the crown can pay for and ship this turn.
func _buyable_offer(play: PlaySession) -> Dictionary:
	var market: WorldMarket = play.economy.market
	if market == null:
		return {}
	var cargo: Dictionary = play.economy.trade_cargo()
	if int(cargo.get("clear_free", cargo.get("free", 0))) <= 0:
		return {}
	for raw: Variant in market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = raw
		if int(offer.get("quantity", 0)) <= 0:
			continue
		var commodity: String = String(offer.get("commodity", ""))
		var ask: int = MinorMarket.ask_for_reader(market, offer, play.player_faction)
		if ask > 0 and play.treasury() >= ask:
			return offer
	return {}


func _end_turn(play: PlaySession) -> void:
	var start_turn: int = play.turn
	for _attempt in 12:
		MapPlayTurn.end_turn(play)
		if play.turn != start_turn:
			return
		var human: int = play.player_faction
		if CallToArms.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, CallToArms.KIND_REFUSE, human, "")
		elif Intervention.has_pending(play.diplomacy, human):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, human, "")
		else:
			return
	_say("the turn would not close")


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_trade_boost: %d steps ---" % _steps.size())
	quit()
