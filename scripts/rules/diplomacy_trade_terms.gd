class_name DiplomacyTradeTerms
extends RefCounted
## World-market price terms a crown's trade standing earns, plus the turn's
## trade-deal relation boosts (wiki: world-market § FTP, § Subsidy price
## adjustment; diplomacy § Relation Model — trade-deal boost). Pure rules:
## callers supply DiplomacyState and WorldMap; nothing here touches a node
## (REQ-P3-01, REQ-P3-03).
##
## The product clears every crown against one global order book, so a pact's
## priority and a boycott's exclusion cannot be matched deal by deal. They are
## published as per-crown price terms the market applies, and a subsidy's
## discount/surcharge lands on the commodities that court's provinces produce
## (docs/diplomacy.md § Trade terms).


## Installs every crown's trade terms on the shared market, and the subsidy step
## each pair carries beside them. The market is pure data; the caller supplies
## the world so a subsidy can find its court's goods.
static func apply(
	state: DiplomacyState, world: WorldMap, market: WorldMarket
) -> void:
	if market == null:
		return
	if state == null:
		market.clear_terms()
		return
	var terms: Dictionary = market_terms(state, world)
	for faction: int in terms.keys():
		market.set_terms(faction, terms[faction])
	market.subsidy_terms = subsidy_terms(state)
	market.sealed = sealed_terms(state)


## Faction -> {"buy": {commodity|"*": multiplier}, "sell": {...}} for every
## Great Power. Includes every crown so a rival's trade obeys the same rules.
## The map no longer moves a rate: pacts and boycotts are crown-wide, and a
## subsidy is published as a pair step (`subsidy_terms`).
static func market_terms(state: DiplomacyState, _world: WorldMap = null) -> Dictionary:
	var terms: Dictionary = {}
	if state == null:
		return terms
	for faction: int in FactionCatalog.great_power_ids():
		terms[faction] = faction_terms(state, {}, faction)
	return terms


## One crown's terms. "*" carries pacts and boycotts across every commodity. A
## subsidy is **not** a crown-wide rate: it lands on the pair at settlement
## (wiki: world-market § Subsidy price adjustment — "the step never touches a
## deal with another court"), so `subsidy_terms` publishes it beside the rates
## for the surfaces that state it.
static func faction_terms(
	state: DiplomacyState, _produce: Dictionary, faction: int
) -> Dictionary:
	var buy: Dictionary = {"*": 1.0}
	var sell: Dictionary = {"*": 1.0}
	if state == null:
		return {"buy": buy, "sell": sell}
	var partners: Array[int] = DiplomacyFtp.ftps_of(state, faction)
	buy["*"] = 1.0 - DiplomacyCatalog.FTP_TERMS * float(partners.size())
	sell["*"] = 1.0 + DiplomacyCatalog.FTP_TERMS * float(partners.size())
	var boycotts: int = DiplomacyBoycott.boycotts_against(state, faction).size()
	buy["*"] = float(buy["*"]) + DiplomacyCatalog.BOYCOTT_TERMS * float(boycotts)
	sell["*"] = float(sell["*"]) - DiplomacyCatalog.BOYCOTT_TERMS * float(boycotts)
	buy["*"] = clampf(
		float(buy["*"]), DiplomacyCatalog.TERMS_BUY_MIN, DiplomacyCatalog.TERMS_BUY_MAX
	)
	sell["*"] = clampf(
		float(sell["*"]), DiplomacyCatalog.TERMS_SELL_MIN, DiplomacyCatalog.TERMS_SELL_MAX
	)
	return {"buy": buy, "sell": sell}


## `"buyer>seller" -> percent` for every subsidy in force, so the Minor's ask and
## the Deal Book name the step the clearing charges (wiki: world-market
## § Subsidy price adjustment; DR-20261110-29). Only the subscribed pair appears.
static func subsidy_terms(state: DiplomacyState) -> Dictionary:
	var terms: Dictionary = {}
	if state == null:
		return terms
	for key: String in state.subsidies.keys():
		var courts: Vector2i = DiplomacyKeys.directed_courts(key)
		if courts.x < 0:
			continue
		var percent: int = int(state.subsidies[key])
		if percent <= 0:
			continue
		terms[DiplomacyKeys.directed(courts.x, courts.y)] = percent
	return terms


## `viewer -> {seller: issuer}`: every Minor/Tribe seller whose suzerain's boycott
## shuts it to that crown. The rate tables already say the boycotted crown trades
## at 10% worse; this is the other half of the same order, published so the
## market's offer row can name the bar it cannot show as a price (wiki: diplomacy
## § GP–Tribe — Boycott, R6; DR-20261115-03). Both directions are read from the
## same records the matcher bars on, so a row and a deal never disagree.
static func sealed_terms(state: DiplomacyState) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	for raw_tribe: Variant in state.colonies.keys():
		var tribe: int = int(raw_tribe)
		var suzerain: int = state.colony_of(tribe)
		if suzerain < 0:
			continue
		for faction: int in FactionCatalog.great_power_ids():
			if faction == suzerain:
				continue
			if not DiplomacyBoycott.is_boycotting(state, suzerain, faction):
				continue
			var row: Dictionary = out.get(faction, {}) as Dictionary
			row[tribe] = suzerain
			out[faction] = row
	return out


## One crown's terms, as the court sheet states them. The map is no longer read:
## a subsidy is a pair step (`subsidy_terms`), not a commodity rate.
static func for_court(
	state: DiplomacyState, _world: WorldMap, faction: int
) -> Dictionary:
	return faction_terms(state, {}, faction)


## Records that a pair cleared a world-market deal this turn: the next Diplomacy
## phase lifts it before decay (wiki: diplomacy § Relation Model — trade-deal
## boost, R10). Volume-independent and once per pair, so a second deal between
## the same courts adds nothing. Only a court-to-court deal involving at least
## one Great Power counts: the standing world counterparty is no court, and two
## Minor/Tribe courts never trade with each other.
static func record_deal(state: DiplomacyState, a: int, b: int) -> void:
	if state == null or a < 0 or b < 0 or a == b:
		return
	var type_a: int = FactionCatalog.type_of(a)
	var type_b: int = FactionCatalog.type_of(b)
	if type_a < 0 or type_b < 0:
		return
	var gp: int = FactionCatalog.Type.GREAT_POWER
	if type_a != gp and type_b != gp:
		return
	state.trade_pairs[state.pair_key(a, b)] = true


## Pays this turn's trade-deal lifts, once per pair, before the drift reads the
## pairs: +2.0 base, +0.4 while an Embassy is in effect, +0.2 per subsidy
## percentage point between the parties. A boosted pair is event-modified and
## skips its decay; a pair at war keeps its frozen score (wiki: diplomacy
## § Relation Model — trade-deal boost, R10).
static func pay_trade_boosts(state: DiplomacyState) -> int:
	if state == null:
		return 0
	var paid: int = 0
	for key: String in state.trade_pairs.keys():
		var courts: Vector2i = DiplomacyKeys.pair_courts(key)
		if courts.x < 0:
			continue
		var a: int = courts.x
		var b: int = courts.y
		var record: DiplomacyRelation = state.relation(a, b)
		if record == null or record.at_war:
			continue
		var boost: float = DiplomacyCatalog.TRADE_BOOST_BASE
		if (
			DiplomacyCatalog.is_embassy_stage(state.overture(a, b))
			or DiplomacyCatalog.is_embassy_stage(state.overture(b, a))
		):
			boost += DiplomacyCatalog.TRADE_BOOST_EMBASSY
		var percent: int = maxi(state.subsidy(a, b), state.subsidy(b, a))
		boost += DiplomacyCatalog.TRADE_BOOST_PER_SUBSIDY * float(percent)
		state.apply_delta(a, b, boost, "tradeDealBoost", {"boost": boost})
		paid += 1
	state.trade_pairs.clear()
	return paid
