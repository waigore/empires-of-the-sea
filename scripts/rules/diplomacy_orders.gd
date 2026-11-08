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


static func options(
	state: DiplomacyState, world: WorldMap, treasury: int, player: int, target: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var record: DiplomacyRelation = state.relation(player, target)
	if record == null:
		return result
	var type: int = FactionCatalog.type_of(target)
	if record.at_war:
		result.append(_valued("Offer Peace", DiplomacyRules.can_make_peace(state, player, target), KIND_PEACE))
	else:
		result.append(_valued("Declare War", DiplomacyRules.can_declare_war(state, player, target), KIND_WAR))
	if type == FactionCatalog.Type.GREAT_POWER and not record.at_war:
		if record.formal_alliance:
			result.append(
				_valued("Break Alliance", _can_break(record), KIND_BREAK)
			)
		else:
			result.append(
				_valued(
					"Offer Alliance", DiplomacyRules.can_form_alliance(state, player, target),
					KIND_ALLIANCE
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
					state, world, player, target, next, treasury
				),
				KIND_OVERTURE,
				DiplomacyCatalog.money(cost) if cost > 0 else "free",
				next
			)
		)
	if not record.at_war:
		result.append(
			_valued(
				"Grant Aid", DiplomacyRules.can_grant_aid(
					state, player, target, DiplomacyCatalog.GRANT_AID_STEP, treasury
				),
				KIND_AID,
				DiplomacyCatalog.money(DiplomacyCatalog.GRANT_AID_STEP),
				str(DiplomacyCatalog.GRANT_AID_STEP)
			)
		)
		if type == FactionCatalog.Type.MINOR_NATION or type == FactionCatalog.Type.TRIBE:
			if state.subsidy(player, target) > 0:
				result.append(
					_valued(
						"End Subsidy · %d%%" % state.subsidy(player, target),
						_allow(), KIND_CANCEL_SUBSIDY
					)
				)
			if DiplomacyRules.has_embassy(state, player, target):
				for percent: int in DiplomacyCatalog.SUBSIDY_OPTIONS:
					result.append(
						_valued(
							"Set Subsidy · %d%%" % percent,
							DiplomacyRules.can_set_subsidy(state, player, target, percent),
							KIND_SUBSIDY,
							"",
							str(percent)
						)
					)
			else:
				result.append(
					_valued(
						"Set Subsidy · 5%",
						DiplomacyRules.can_set_subsidy(state, player, target, 5),
						KIND_SUBSIDY,
						"",
						"5"
					)
				)
	return result


static func validate(
	state: DiplomacyState,
	world: WorldMap,
	treasury: int,
	player: int,
	order: Dictionary
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
				state, world, player, target, String(order.get("stage", "")), treasury
			)
		KIND_AID:
			return DiplomacyRules.can_grant_aid(
				state, player, target, int(order.get("amount", 0)), treasury
			)
		KIND_SUBSIDY:
			return DiplomacyRules.can_set_subsidy(
				state, player, target, int(order.get("amount", 0))
			)
		KIND_CANCEL_SUBSIDY:
			return _allow() if state.subsidy(player, target) > 0 else _deny("No subsidy is active.")
		_:
			return _deny("Unknown court order.")


static func apply(
	state: DiplomacyState,
	world: WorldMap,
	economy: PlayerEconomy,
	order: Dictionary
) -> Dictionary:
	var player: int = int(order.get("from", FactionCatalog.PLAYER_FACTION))
	var target: int = int(order.get("target", -1))
	var treasury: int = economy.treasury if economy != null else 0
	var check: Dictionary = validate(state, world, treasury, player, order)
	if not bool(check.get("ok", false)):
		return check
	var kind: String = String(order.get("kind", ""))
	match kind:
		KIND_WAR:
			return DiplomacyRules.declare_war(state, player, target)
		KIND_PEACE:
			return DiplomacyRules.make_peace(state, player, target)
		KIND_ALLIANCE:
			return DiplomacyRules.form_alliance(state, player, target)
		KIND_BREAK:
			return DiplomacyRules.break_alliance(state, player, target)
		KIND_OVERTURE:
			return DiplomacyRules.establish_overture(
				state, economy, world, player, target, String(order.get("stage", ""))
			)
		KIND_AID:
			return DiplomacyRules.grant_aid(
				state, economy, player, target, int(order.get("amount", 0))
			)
		KIND_SUBSIDY:
			return DiplomacyRules.set_subsidy(
				state, player, target, int(order.get("amount", 0))
			)
		KIND_CANCEL_SUBSIDY:
			state.cancel_subsidy(player, target)
			return {
				"ok": true,
				"reason": "",
				"message": "The subsidy to %s is ended." % FactionCatalog.name_of(target),
			}
	return _deny("Unknown court order.")


static func _valued(
	label: String,
	check: Dictionary,
	kind: String,
	cost_text: String = "",
	arg: String = ""
) -> Dictionary:
	return {
		"label": label,
		"kind": kind,
		"arg": arg,
		"cost_text": cost_text,
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
