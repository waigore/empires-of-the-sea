class_name MarketFavoured
extends RefCounted
## The favoured trading partner of a Minor Nation or Tribe (wiki: diplomacy
## § Favoured trading partner, R7.1).
##
## - A **colony Tribe** trades with its suzerain whatever any rival's relation
##   score (R5; the lookup never reads relations for a colony).
## - An **independent** Minor or Tribe trades with the Great Power holding the
##   highest decimal relation with it; ties break to the smaller faction id.
## - No Great Power holds a relation with it: the partner is undefined.
##
## Read-only over the diplomacy record, so rules and tests can ask without a
## map screen: no goods move, no treasury is touched, no RNG or logging
## (REQ-P3-03). `MarketMatcher` honours the colony arm as a tiebreak inside one
## integer priority tier (DR-20261111-11); the independent arm is the same
## crown R7.3 already ranks behind every Consulate holder, so the auction
## leaves that order alone.

const UNDEFINED: int = -1


static func of(state: DiplomacyState, seller: int) -> int:
	if state == null or seller < 0:
		return UNDEFINED
	var suzerain: int = state.colony_of(seller)
	if suzerain >= 0:
		return suzerain
	var best: int = UNDEFINED
	var best_score: float = 0.0
	# `relations_of` walks the partners in ascending faction id, so an equal
	# score keeps the earlier (smaller) id without a second comparison.
	for record: DiplomacyRelation in state.relations_of(seller):
		var gp: int = record.other(seller)
		if FactionCatalog.type_of(gp) != FactionCatalog.Type.GREAT_POWER:
			continue
		if best != UNDEFINED and record.score <= best_score:
			continue
		best = gp
		best_score = record.score
	return best


## True when the seller is a colony and `court` is the suzerain it trades with
## first (the arm the auction reads).
static func is_suzerain(state: DiplomacyState, seller: int, court: int) -> bool:
	if state == null or seller < 0 or court < 0:
		return false
	return state.colony_of(seller) == court
