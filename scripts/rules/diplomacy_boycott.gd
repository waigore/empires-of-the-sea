class_name DiplomacyBoycott
extends RefCounted
## Colonial boycotts between Great Powers (wiki: diplomacy § GP–Tribe — Boycott).
## Pure rules: callers supply DiplomacyState; nothing here touches a node
## (REQ-P3-01, REQ-P3-03). Market price terms that read boycott counts live in
## DiplomacyTradeTerms; war sever of a boycott lives on DiplomacyTrade.

const KIND_SET: String = "boycott"
const KIND_REVOKE: String = "revoke_boycott"


static func is_boycotting(state: DiplomacyState, issuer: int, target: int) -> bool:
	if state == null:
		return false
	return state.boycotts.has(DiplomacyKeys.directed(issuer, target))


static func boycotts_against(state: DiplomacyState, target: int) -> Array[int]:
	var issuers: Array[int] = []
	if state == null:
		return issuers
	for key: String in state.boycotts.keys():
		var courts: Vector2i = DiplomacyKeys.directed_courts(key)
		if courts.y == target and courts.x != target:
			issuers.append(courts.x)
	issuers.sort()
	return issuers


static func can_boycott(state: DiplomacyState, player: int, target: int) -> Dictionary:
	if player == target:
		return _deny("A crown cannot boycott itself.")
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return _deny("Only a Great Power can be boycotted.")
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	if state.relation(player, target).at_war:
		return _deny("We are already at war with that crown; no boycott is needed.")
	if _colony_tribes(state, player).is_empty():
		return _deny("A colony is required before a boycott can be declared.")
	if is_boycotting(state, player, target):
		return _deny("A boycott of that crown is already in force.")
	if state.claimed(player, target, "boycott"):
		return _deny("A boycott order was already given this turn.")
	return _allow()


## Applying a boycott also voids the target's subsidies to every colony of the
## issuer, because those courts no longer trade with it (wiki: diplomacy
## § GP–Tribe — Boycott, R6.2).
static func boycott(state: DiplomacyState, player: int, target: int) -> Dictionary:
	var check: Dictionary = can_boycott(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "boycott")
	state.boycotts[DiplomacyKeys.directed(player, target)] = state.turn
	state.record_event("boycottSet", player, target)
	for tribe: int in _colony_tribes(state, player):
		state.cancel_subsidy(target, tribe)
	return {
		"ok": true,
		"reason": "",
		"message": "Our colonies are closed to %s; its trade with them ends." % (
			FactionCatalog.name_of(target)
		),
	}


static func can_revoke(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if not is_boycotting(state, player, target):
		return _deny("No boycott of that crown is in force.")
	if state.claimed(player, target, "boycott"):
		return _deny("A boycott order was already given this turn.")
	return _allow()


static func revoke(state: DiplomacyState, player: int, target: int) -> Dictionary:
	var check: Dictionary = can_revoke(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "boycott")
	state.boycotts.erase(DiplomacyKeys.directed(player, target))
	state.record_event("boycottRevoked", player, target)
	return {
		"ok": true,
		"reason": "",
		"message": "The boycott of %s is lifted." % FactionCatalog.name_of(target),
	}


## True when a colonial boycott stands between the courts: the boycotted crown
## may not trade with, aid or subsidise that colony (wiki: diplomacy
## § GP–Tribe — Boycott, R6).
static func blocked(state: DiplomacyState, a: int, b: int) -> bool:
	if state == null or a == b:
		return false
	var suzerain: int = state.colony_of(b)
	if suzerain >= 0 and suzerain != a and is_boycotting(state, suzerain, a):
		return true
	suzerain = state.colony_of(a)
	if suzerain >= 0 and suzerain != b and is_boycotting(state, suzerain, b):
		return true
	return false


static func _colony_tribes(state: DiplomacyState, gp: int) -> Array[int]:
	var tribes: Array[int] = []
	if state == null:
		return tribes
	for tribe: int in state.colonies.keys():
		if int(state.colonies[tribe]) == gp:
			tribes.append(tribe)
	tribes.sort()
	return tribes


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
