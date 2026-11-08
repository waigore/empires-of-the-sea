class_name DiplomacyAid
extends RefCounted
## Foreign aid and subsidies (wiki: diplomacy § GP–Minor Rules). Split from
## DiplomacyRules so each module keeps one concern and stays under the size bar.


static func can_grant_aid(
	state: DiplomacyState,
	player: int,
	target: int,
	amount: int,
	treasury: int
) -> Dictionary:
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	if state.relation(player, target).at_war:
		return _deny("Aid cannot be sent to an enemy.")
	if not DiplomacyRules.has_embassy(state, player, target):
		return _deny("An embassy is required before aid can be sent.")
	if not DiplomacyCatalog.is_valid_aid(amount):
		return _deny("Aid must be a multiple of £1,000.")
	if treasury < amount:
		return _deny("The treasury cannot cover that aid.")
	return _allow()


static func grant_aid(
	state: DiplomacyState,
	economy: PlayerEconomy,
	player: int,
	target: int,
	amount: int
) -> Dictionary:
	var treasury: int = economy.treasury if economy != null else 0
	var check: Dictionary = can_grant_aid(state, player, target, amount, treasury)
	if not bool(check["ok"]):
		return check
	if not economy.spend_treasury(amount):
		return _deny("The treasury cannot cover that aid.")
	state.apply_delta(
		player, target, DiplomacyCatalog.GRANT_AID_RELATION, "grantAid", {"amount": amount}
	)
	return {
		"ok": true,
		"reason": "",
		"message": "%s sends %s in aid to %s." % [
			FactionCatalog.name_of(player),
			DiplomacyCatalog.money(amount),
			FactionCatalog.name_of(target),
		],
	}


static func can_set_subsidy(
	state: DiplomacyState, player: int, target: int, percent: int
) -> Dictionary:
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	var type: int = FactionCatalog.type_of(target)
	if type != FactionCatalog.Type.MINOR_NATION and type != FactionCatalog.Type.TRIBE:
		return _deny("Subsidies are only offered to Minor Nations and Tribes.")
	if state.relation(player, target).at_war:
		return _deny("No subsidy can be paid to an enemy.")
	if not DiplomacyRules.has_embassy(state, player, target):
		return _deny("An embassy is required before a subsidy can be set.")
	if not DiplomacyCatalog.is_valid_subsidy(percent):
		return _deny("A subsidy must be 5–20% in steps of 5.")
	return _allow()


static func set_subsidy(
	state: DiplomacyState, player: int, target: int, percent: int
) -> Dictionary:
	var check: Dictionary = can_set_subsidy(state, player, target, percent)
	if not bool(check["ok"]):
		return check
	state.set_subsidy(player, target, percent)
	return {
		"ok": true,
		"reason": "",
		"message": "A %d%% subsidy is offered to %s." % [
			percent, FactionCatalog.name_of(target)
		],
	}


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
