class_name DiplomacyFtp
extends RefCounted
## Favoured-trading-partner pacts (wiki: world-market § FTP). Pure rules: callers
## supply DiplomacyState; nothing here touches a node (REQ-P3-01, REQ-P3-03).
## Market price terms that read pact counts live in DiplomacyTradeTerms; war
## sever of a pact lives on DiplomacyTrade.

const KIND_ESTABLISH: String = "establish_ftp"
const KIND_REVOKE: String = "revoke_ftp"


static func is_ftp(state: DiplomacyState, a: int, b: int) -> bool:
	if state == null or a == b:
		return false
	return state.ftps.has(state.pair_key(a, b))


static func ftps_of(state: DiplomacyState, faction: int) -> Array[int]:
	var partners: Array[int] = []
	if state == null:
		return partners
	for key: String in state.ftps.keys():
		var courts: Vector2i = DiplomacyKeys.pair_courts(key)
		if courts.x == faction:
			partners.append(courts.y)
		elif courts.y == faction:
			partners.append(courts.x)
	partners.sort()
	return partners


static func can_establish(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if player == target:
		return _deny("A crown cannot trade with itself.")
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return _deny("Only Great Powers exchange favoured trading pacts.")
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	if state.relation(player, target).at_war:
		return _deny("No trade pact can be signed with an enemy.")
	if not DiplomacyRules.has_embassy(state, player, target):
		return _deny("An embassy is required before a trade pact.")
	if is_ftp(state, player, target):
		return _deny("A favoured trading pact already binds us.")
	if state.claimed(player, target, "ftp"):
		return _deny("A trade pact was already offered to this court this turn.")
	return _allow()


## The target answers: an AI court accepts at Friendly standing or better
## (wiki: world-market § FTP — relation ≥ 65).
static func establish(
	state: DiplomacyState, player: int, target: int, decision: String = ""
) -> Dictionary:
	var check: Dictionary = can_establish(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "ftp")
	var record: DiplomacyRelation = state.relation(player, target)
	var accepts: bool = _accepts(record)
	if decision == DiplomacyRules.DECISION_ACCEPT:
		accepts = true
	elif decision == DiplomacyRules.DECISION_REFUSE:
		accepts = false
	if not accepts:
		state.record_event("ftpRefused", player, target)
		return {
			"ok": true,
			"accepted": false,
			"message": "%s declines a favoured trading pact." % (
				FactionCatalog.name_of(target)
			),
		}
	state.ftps[state.pair_key(player, target)] = state.turn
	state.record_event("ftpSigned", player, target)
	return {
		"ok": true,
		"accepted": true,
		"message": "%s signs a favoured trading pact: our merchants clear first." % (
			FactionCatalog.name_of(target)
		),
	}


static func can_revoke(state: DiplomacyState, player: int, target: int) -> Dictionary:
	if not is_ftp(state, player, target):
		return _deny("No favoured trading pact is in force.")
	if state.claimed(player, target, "ftp"):
		return _deny("A trade pact was already offered to this court this turn.")
	return _allow()


static func revoke(state: DiplomacyState, player: int, target: int) -> Dictionary:
	var check: Dictionary = can_revoke(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "ftp")
	state.ftps.erase(state.pair_key(player, target))
	state.record_event("ftpRevoked", player, target)
	return {
		"ok": true,
		"reason": "",
		"message": "The favoured trading pact with %s is ended." % (
			FactionCatalog.name_of(target)
		),
	}


static func _accepts(record: DiplomacyRelation) -> bool:
	if record == null:
		return false
	return record.score >= DiplomacyCatalog.FTP_MIN_SCORE


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
