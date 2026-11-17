class_name DiplomacyTrade
extends RefCounted
## Trade diplomacy spine: KIND aliases the court order catalogue still names,
## thin forwards for AI/baselines that still call the pre-split names, and war's
## commercial sever that cuts FTP, boycott and subsidy together (wiki:
## diplomacy § GP–Tribe — Boycott, R6.4; world-market § FTP — breaks on war).
## Pact ops live in DiplomacyFtp; boycotts in DiplomacyBoycott; market terms and
## trade-deal boosts in DiplomacyTradeTerms (REQ-P3-01).

const KIND_FTP: String = DiplomacyFtp.KIND_ESTABLISH
const KIND_REVOKE_FTP: String = DiplomacyFtp.KIND_REVOKE
const KIND_BOYCOTT: String = DiplomacyBoycott.KIND_SET
const KIND_REVOKE_BOYCOTT: String = DiplomacyBoycott.KIND_REVOKE


static func is_ftp(state: DiplomacyState, a: int, b: int) -> bool:
	return DiplomacyFtp.is_ftp(state, a, b)


static func can_establish_ftp(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	return DiplomacyFtp.can_establish(state, player, target)


static func can_revoke_ftp(state: DiplomacyState, player: int, target: int) -> Dictionary:
	return DiplomacyFtp.can_revoke(state, player, target)


static func is_boycotting(state: DiplomacyState, issuer: int, target: int) -> bool:
	return DiplomacyBoycott.is_boycotting(state, issuer, target)


static func can_boycott(state: DiplomacyState, player: int, target: int) -> Dictionary:
	return DiplomacyBoycott.can_boycott(state, player, target)


static func can_revoke_boycott(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	return DiplomacyBoycott.can_revoke(state, player, target)


static func blocked_by_boycott(state: DiplomacyState, a: int, b: int) -> bool:
	return DiplomacyBoycott.blocked(state, a, b)


## War severs every commercial tie between the two crowns: subsidies both ways,
## the favoured-trading pact and any boycott in either direction (wiki:
## diplomacy § GP–Tribe — Boycott, R6.4; world-market § FTP — breaks on war).
static func sever(state: DiplomacyState, a: int, b: int) -> void:
	if state == null:
		return
	state.cancel_subsidy(a, b)
	state.cancel_subsidy(b, a)
	if state.ftps.erase(state.pair_key(a, b)):
		state.record_event("ftpRevoked", a, b, {"cause": "war"})
	for pair: Vector2i in [Vector2i(a, b), Vector2i(b, a)]:
		if state.boycotts.erase(DiplomacyKeys.directed(pair.x, pair.y)):
			state.record_event("boycottRevoked", pair.x, pair.y, {"cause": "war"})
