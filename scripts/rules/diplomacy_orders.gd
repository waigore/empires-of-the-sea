class_name DiplomacyOrders
extends RefCounted
## Court order catalogue: what can be offered to a faction, validation and
## resolution (wiki: diplomacy § Diplomatic Order Types). The panel renders
## `options`; the controller calls `apply` and reports the result.

const KIND_WAR: String = "declare_war"
const KIND_PEACE: String = "offer_peace"
const KIND_ALLIANCE: String = "alliance"
const KIND_BREAK: String = "break_alliance"
const KIND_OVERTURE: String = "overture"
const KIND_AID: String = "grant_aid"
const KIND_SUBSIDY: String = "set_subsidy"
const KIND_CANCEL_SUBSIDY: String = "cancel_subsidy"
const KIND_FTP: String = DiplomacyTrade.KIND_FTP
const KIND_REVOKE_FTP: String = DiplomacyTrade.KIND_REVOKE_FTP
const KIND_BOYCOTT: String = DiplomacyTrade.KIND_BOYCOTT
const KIND_REVOKE_BOYCOTT: String = DiplomacyTrade.KIND_REVOKE_BOYCOTT

## Panel sections: choice first, trade terms last (REQ-P5-02).
const GROUP_ORDERS: String = "orders"
const GROUP_TREATIES: String = "treaties"
const GROUP_AID: String = "aid"
const GROUP_TRADE: String = "trade"


static func options(
	state: DiplomacyState,
	world: WorldMap,
	treasury: int,
	player: int,
	target: int,
	tech: Dictionary = {}
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var record: DiplomacyRelation = state.relation(player, target)
	if record == null:
		return result
	var type: int = FactionCatalog.type_of(target)
	if record.at_war:
		result.append(
			_valued("Offer Peace", DiplomacyRules.can_make_peace(state, player, target), KIND_PEACE)
		)
	else:
		result.append(
			_valued(
				"Declare War",
				DiplomacyRules.can_declare_war(state, player, target),
				KIND_WAR,
				"",
				"",
				GROUP_ORDERS,
				InterventionCopy.warden_hint(state, world, player, target)
			)
		)
	if type == FactionCatalog.Type.GREAT_POWER and not record.at_war:
		if record.formal_alliance:
			result.append(
				_valued("Break Alliance", _can_break(record), KIND_BREAK, "", "", GROUP_TREATIES)
			)
		else:
			result.append(
				_valued(
					"Offer Alliance", DiplomacyRules.can_form_alliance(state, player, target),
					KIND_ALLIANCE, "", "", GROUP_TREATIES
				)
			)
	var next: String = DiplomacyCatalog.next_stage(state.overture(player, target))
	if next != "" and not record.at_war:
		var cost: int = DiplomacyCatalog.stage_cost(
			next, DiplomacyRules.provinces_owned(world, target)
		)
		result.append(
			_valued(
				"Offer %s" % DiplomacyCatalog.stage_label(next),
				DiplomacyRules.can_establish_overture(
					state, world, player, target, next, treasury, tech
				),
				KIND_OVERTURE,
				DiplomacyCatalog.money(cost) if cost > 0 else "free",
				next,
				GROUP_TREATIES,
				DiplomacyOvertures.stage_hint(next, type)
			)
		)
	if not record.at_war:
		result.append(
			_valued(
				"Grant Aid", DiplomacyAid.can_grant_aid(
					state, player, target, DiplomacyCatalog.GRANT_AID_STEP, treasury
				),
				KIND_AID,
				DiplomacyCatalog.money(DiplomacyCatalog.GRANT_AID_STEP),
				str(DiplomacyCatalog.GRANT_AID_STEP),
				GROUP_AID,
				"One gift of gold; the court remembers it."
			)
		)
		if type == FactionCatalog.Type.GREAT_POWER:
			_add_ftp_options(result, state, player, target)
			_add_boycott_options(result, state, player, target)
		if type == FactionCatalog.Type.MINOR_NATION or type == FactionCatalog.Type.TRIBE:
			_add_subsidy_options(result, state, player, target)
	return result


## Favoured trading pact and colonial boycott, both GP-only and both toggles:
## the court always offers the way back out of a standing agreement.
static func _add_ftp_options(
	result: Array[Dictionary], state: DiplomacyState, player: int, target: int
) -> void:
	if DiplomacyTrade.is_ftp(state, player, target):
		result.append(
			_valued(
				"End Favoured Trading Pact",
				DiplomacyTrade.can_revoke_ftp(state, player, target),
				KIND_REVOKE_FTP, "", "", GROUP_TRADE,
				"Trade terms return to the world price."
			)
		)
		return
	result.append(
		_valued(
			"Offer Favoured Trading Pact",
			DiplomacyTrade.can_establish_ftp(state, player, target),
			KIND_FTP, "", "", GROUP_TRADE,
			"Our imports cost 5% less and our exports earn 5% more."
		)
	)


static func _add_boycott_options(
	result: Array[Dictionary], state: DiplomacyState, player: int, target: int
) -> void:
	if DiplomacyTrade.is_boycotting(state, player, target):
		result.append(
			_valued(
				"Lift the Boycott",
				DiplomacyTrade.can_revoke_boycott(state, player, target),
				KIND_REVOKE_BOYCOTT, "", "", GROUP_TRADE,
				"Their trade with our colonies resumes."
			)
		)
		return
	result.append(
		_valued(
			"Boycott Their Trade",
			DiplomacyTrade.can_boycott(state, player, target),
			KIND_BOYCOTT, "", "", GROUP_TRADE,
			"Our colonies shut to them: their market terms worsen 10%."
		)
	)


static func _add_subsidy_options(
	result: Array[Dictionary], state: DiplomacyState, player: int, target: int
) -> void:
	if state.subsidy(player, target) > 0:
		result.append(
			_valued(
				"End Subsidy · %d%%" % state.subsidy(player, target),
				_allow(), KIND_CANCEL_SUBSIDY, "", "", GROUP_TRADE,
				"Prices return to the world market."
			)
		)
	if not DiplomacyRules.has_embassy(state, player, target):
		result.append(
			_valued(
				"Set Subsidy · 5%",
				DiplomacyAid.can_set_subsidy(state, player, target, 5),
				KIND_SUBSIDY, "", "5", GROUP_TRADE,
				"An embassy is needed to direct trade to this court."
			)
		)
		return
	for percent: int in DiplomacyCatalog.SUBSIDY_OPTIONS:
		result.append(
			_valued(
				"Set Subsidy · %d%%" % percent,
				DiplomacyAid.can_set_subsidy(state, player, target, percent),
				KIND_SUBSIDY, "", str(percent), GROUP_TRADE,
				"Their goods cost us %d%% more; ours earn %d%% less." % [percent, percent],
				state.subsidy(player, target) == percent
			)
		)


static func validate(
	state: DiplomacyState,
	world: WorldMap,
	treasury: int,
	player: int,
	order: Dictionary,
	tech: Dictionary = {}
) -> Dictionary:
	var target: int = int(order.get("target", -1))
	match String(order.get("kind", "")):
		KIND_WAR:
			return DiplomacyRules.can_declare_war(state, player, target)
		KIND_PEACE:
			return DiplomacyRules.can_make_peace(state, player, target)
		KIND_ALLIANCE:
			return DiplomacyRules.can_form_alliance(state, player, target)
		KIND_BREAK:
			var record: DiplomacyRelation = state.relation(player, target)
			return _can_break(record) if record != null else _deny("No envoy has reached that court.")
		KIND_OVERTURE:
			return DiplomacyRules.can_establish_overture(
				state, world, player, target, String(order.get("stage", "")), treasury, tech
			)
		KIND_AID:
			return DiplomacyAid.can_grant_aid(
				state, player, target, int(order.get("amount", 0)), treasury
			)
		KIND_SUBSIDY:
			return DiplomacyAid.can_set_subsidy(
				state, player, target, int(order.get("amount", 0))
			)
		KIND_CANCEL_SUBSIDY:
			return _allow() if state.subsidy(player, target) > 0 else _deny("No subsidy is active.")
		KIND_FTP:
			return DiplomacyTrade.can_establish_ftp(state, player, target)
		KIND_REVOKE_FTP:
			return DiplomacyTrade.can_revoke_ftp(state, player, target)
		KIND_BOYCOTT:
			return DiplomacyTrade.can_boycott(state, player, target)
		KIND_REVOKE_BOYCOTT:
			return DiplomacyTrade.can_revoke_boycott(state, player, target)
		_:
			return _deny("Unknown court order.")


static func apply(
	state: DiplomacyState,
	world: WorldMap,
	economy: PlayerEconomy,
	order: Dictionary,
	tech: Dictionary = {}
) -> Dictionary:
	var player: int = int(order.get("from", FactionCatalog.PLAYER_FACTION))
	var target: int = int(order.get("target", -1))
	var treasury: int = economy.treasury if economy != null else 0
	var check: Dictionary = validate(state, world, treasury, player, order, tech)
	if not bool(check.get("ok", false)):
		return check
	var kind: String = String(order.get("kind", ""))
	match kind:
		KIND_WAR:
			# The declarer's own Propaganda softens a protest against it
			# (wiki: diplomacy § Intervention).
			return DiplomacyRules.declare_war(state, player, target, true, world, tech)
		KIND_PEACE:
			return DiplomacyRules.make_peace(state, player, target)
		KIND_ALLIANCE:
			return DiplomacyRules.form_alliance(state, player, target)
		KIND_BREAK:
			return DiplomacyRules.break_alliance(state, player, target)
		KIND_OVERTURE:
			return DiplomacyOvertures.establish_overture(
				state, economy, world, player, target, String(order.get("stage", "")), tech
			)
		KIND_AID:
			return DiplomacyAid.grant_aid(
				state, economy, player, target, int(order.get("amount", 0))
			)
		KIND_SUBSIDY:
			return DiplomacyAid.set_subsidy(
				state, player, target, int(order.get("amount", 0))
			)
		KIND_CANCEL_SUBSIDY:
			state.cancel_subsidy(player, target)
			return {
				"ok": true,
				"reason": "",
				"message": "The subsidy to %s is ended." % FactionCatalog.name_of(target),
			}
		KIND_FTP:
			return DiplomacyTrade.establish_ftp(state, player, target)
		KIND_REVOKE_FTP:
			return DiplomacyTrade.revoke_ftp(state, player, target)
		KIND_BOYCOTT:
			return DiplomacyTrade.boycott(state, player, target)
		KIND_REVOKE_BOYCOTT:
			return DiplomacyTrade.revoke_boycott(state, player, target)
	return _deny("Unknown court order.")


static func _valued(
	label: String,
	check: Dictionary,
	kind: String,
	cost_text: String = "",
	arg: String = "",
	group: String = GROUP_ORDERS,
	hint: String = "",
	active: bool = false
) -> Dictionary:
	return {
		"label": label,
		"kind": kind,
		"arg": arg,
		"cost_text": cost_text,
		"group": group,
		"hint": hint,
		"active": active,
		"ok": bool(check.get("ok", false)),
		"reason": String(check.get("reason", "")),
	}


static func _can_break(record: DiplomacyRelation) -> Dictionary:
	if not record.formal_alliance:
		return _deny("There is no formal alliance to break.")
	return _allow()


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
