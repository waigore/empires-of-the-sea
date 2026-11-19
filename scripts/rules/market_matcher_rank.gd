class_name MarketMatcherRank
extends RefCounted
## Who takes the goods: the world-market deal matcher's ordering arms (wiki:
## world-market § Trade orders; world-market-first-right-of-refusal § Priority
## override). The matcher sorts the offers once, then asks one arm at a time
## which bid is next: the tier, the favoured pact, a colony's suzerain, the
## Consulate holders' relation, then the court id and the order id.
##
## One job per caller: the matcher keeps the deals, the state and the price,
## and reads no ranking rule of its own (REQ-P3-01). No RNG, no logging, no
## Game/Node access (REQ-P3-03).


## The best bid still standing for this offer, or null when every bid is spent
## or barred.
static func best_bid(
	bids: Array, offer: MarketOrder, blocked: Dictionary, context: Dictionary
) -> MarketOrder:
	var best: MarketOrder = null
	for raw: Variant in bids:
		var bid: MarketOrder = raw
		if bid.remaining() <= 0 or blocked.has(bid.id):
			continue
		# A barred pair is no bid at all for this seller, so the next court in
		# the tier takes the goods (wiki: diplomacy § GP–Tribe — Boycott, R6).
		if boycott_for(context, bid.faction, offer.faction):
			continue
		if best == null or bid_less(bid, best, offer, context):
			best = bid
	return best


## True when a colonial boycott stands between the two courts (wiki: diplomacy
## § GP–Tribe — Boycott, R6). The caller publishes the reading; no diplomacy,
## nothing to bar.
static func boycott_for(context: Dictionary, a: int, b: int) -> bool:
	var callable: Variant = context.get("boycott_for", null)
	return callable is Callable and bool((callable as Callable).call(a, b))


## The four tie-arms, lowest first: priority tier, favoured pact, colony
## suzerain with the Consulate relation, then the smaller court id and order id.
static func bid_less(
	a: MarketOrder, b: MarketOrder, offer: MarketOrder, context: Dictionary
) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	var ftp_for: Variant = context.get("ftp_for", null)
	if ftp_for is Callable:
		var a_ftp: bool = bool((ftp_for as Callable).call(a.faction, offer.faction))
		var b_ftp: bool = bool((ftp_for as Callable).call(b.faction, offer.faction))
		if a_ftp != b_ftp:
			return a_ftp
	if MarketRules.is_minor(offer.faction):
		# A colony's suzerain clears its goods first inside the tier, whatever
		# the rivals' relations (wiki: diplomacy § Favoured trading partner, R7.1;
		# DR-20261111-11). Independent courts keep the R7.3 order below.
		var favoured_for: Variant = context.get("favoured_for", null)
		if favoured_for is Callable:
			var favoured: int = int((favoured_for as Callable).call(offer.faction))
			if favoured >= 0 and a.faction != b.faction:
				if a.faction == favoured:
					return true
				if b.faction == favoured:
					return false
		var consulate_for: Variant = context.get("consulate_for", null)
		# R7.3's relation arm is a tiebreak between Consulate holders only; a
		# court with no Consulate reading has nothing to gate on.
		var relation_applies: bool = not (consulate_for is Callable)
		if consulate_for is Callable:
			var a_consul: bool = bool((consulate_for as Callable).call(a.faction, offer.faction))
			var b_consul: bool = bool((consulate_for as Callable).call(b.faction, offer.faction))
			if a_consul != b_consul:
				return a_consul
			relation_applies = a_consul and b_consul
		var relation_for: Variant = context.get("relation_for", null)
		if relation_applies and relation_for is Callable:
			var a_score: float = float((relation_for as Callable).call(a.faction, offer.faction))
			var b_score: float = float((relation_for as Callable).call(b.faction, offer.faction))
			if not is_equal_approx(a_score, b_score):
				return a_score > b_score
	if a.faction != b.faction:
		return a.faction < b.faction
	return a.id < b.id


## The offer order walked by the tier pass: priority tier, then an auto-offer
## before a court's own, then the smaller court, tile and order id.
## The offer order walked by the tier pass: priority tier, then an auto-offer
## before a court's own, then the smaller court, tile and order id.
static func sort_offers(offers: Array) -> void:
	offers.sort_custom(func(a: MarketOrder, b: MarketOrder) -> bool:
		if a.priority != b.priority:
			return a.priority < b.priority
		if a.auto != b.auto:
			return a.auto
		if a.faction != b.faction:
			return a.faction < b.faction
		if a.origin_region != b.origin_region:
			return a.origin_region < b.origin_region
		if a.origin_index != b.origin_index:
			return a.origin_index < b.origin_index
		return a.id < b.id
	)
