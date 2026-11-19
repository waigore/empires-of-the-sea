class_name DiplomacyOvertures
extends RefCounted
## What taking an overture rung does: charge the treasury, walk the record in
## both directions, and land the last link — a Tribe colony, a Minor's
## absorption, or a nearly defeated Great Power's fall (wiki: diplomacy
## § Overtures; factions § Tribe). DiplomacyRules still reads the rungs and
## gates the next one; this module owns the transition (REQ-P3-01).


static func establish_overture(
	state: DiplomacyState,
	economy: PlayerEconomy,
	world: WorldMap,
	player: int,
	target: int,
	stage: String,
	tech: Dictionary = {},
	decision: String = DiplomacyRules.DECISION_AUTO,
	power: Dictionary = {}
) -> Dictionary:
	var treasury: int = economy.treasury if economy != null else 0
	var check: Dictionary = DiplomacyRules.can_establish_overture(
		state, world, player, target, stage, treasury, tech
	)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "overture")
	var record: DiplomacyRelation = state.relation(player, target)
	var accepts: bool = _accepts_overture(record, target, stage, world, player, power)
	if decision == DiplomacyRules.DECISION_ACCEPT:
		accepts = true
	elif decision == DiplomacyRules.DECISION_REFUSE:
		accepts = false
	if not accepts:
		state.record_event("overtureRejected", player, target, {"stage": stage})
		return {
			"ok": true,
			"accepted": false,
			"message": "%s declines the %s." % [
				FactionCatalog.name_of(target), DiplomacyCatalog.stage_label(stage)
			],
		}
	var cost: int = int(check["cost"])
	if cost > 0 and (economy == null or not economy.spend_treasury(cost)):
		return _deny("The treasury cannot cover the %s." % DiplomacyCatalog.stage_label(stage))
	if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		if FactionCatalog.type_of(target) == FactionCatalog.Type.TRIBE:
			return DiplomacyColony.found(state, player, target, stage, cost)
		_absorb(world, state, player, target)
		return {
			"ok": true,
			"accepted": true,
			"cost": cost,
			"map_changed": true,
			"absorbed": target,
			"message": "%s is absorbed into the empire." % FactionCatalog.name_of(target),
		}
	state.set_overture(player, target, stage)
	state.set_overture(target, player, stage)
	state.touch(player, target, "overtureEstablished", {"stage": stage})
	return {
		"ok": true,
		"accepted": true,
		"cost": cost,
		"message": "%s accepts the %s." % [
			FactionCatalog.name_of(target), DiplomacyCatalog.stage_label(stage)
		],
	}


## What the last link of the chain buys, in the words the court that pays it
## reads: a Tribe keeps its land, so its provinces never count toward victory
## (wiki: factions § Tribe; diplomacy § GP–Tribe Rules). Earlier links are
## steps, not purchases, and stay quiet.
##
## Every absorbed crown's land, regiments and hulls change flags
## (wiki: diplomacy § GP–Minor Rules — Join Empire; `MapPlayDiplomacy.on_order`
## hands the fleets over with the provinces), so the line names all three. A
## Great Power target answers the offer on either of the rule's roads — nearly
## defeated, or the offerer's published power twice its own
## (wiki: diplomacy § Join Empire; DR-20261115-19) — so the line names both.
##
## A court short of the warmth gate reads where that gate stands on its own
## herald's meter, so the row names the wait before the press (wiki: diplomacy
## § Join Empire, § Player-facing relation display).
static func stage_hint(stage: String, target_type: int, score: float = -1.0) -> String:
	if stage != DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		return ""
	var line: String
	match target_type:
		FactionCatalog.Type.TRIBE:
			line = (
				"A colony: the tribe keeps its land, so its provinces never count "
				+ "toward victory — its trade favours your court."
			)
		FactionCatalog.Type.MINOR_NATION:
			line = "Its provinces, regiments and hulls join your empire."
		_:
			line = (
				"A crown answers yes when it is nearly defeated, or when your "
				+ "power is twice its own — then its provinces, regiments and "
				+ "hulls join yours."
			)
	if score >= 0.0 and score < DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE:
		line += " The gate stands %s." % DiplomacyCatalog.gate_line(
			score, DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE
		)
	return line


static func _absorb(world: WorldMap, state: DiplomacyState, winner: int, loser: int) -> void:
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.owner == loser:
				province.owner = winner
				# The absorbed court's seat does not travel with its land
				# (wiki: capital-and-connectivity § Capital loss and
				# reassignment).
				CapitalLoss.clear_seat(province)
	state.clear_relations_of(loser)
	state.record_event("joinEmpire", winner, loser)


static func _accepts_overture(
	record: DiplomacyRelation, target: int, stage: String,
	world: WorldMap, player: int, power: Dictionary
) -> bool:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return true
	if stage == DiplomacyCatalog.STAGE_NAP:
		return record.score >= DiplomacyCatalog.NAP_MIN_SCORE
	if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		# The warmth the court must hold joins the absorption gate: a nearly
		# defeated crown, or one the offerer so far outpowers that standing
		# alone is hopeless (wiki: diplomacy § Join Empire; issue #750).
		return record.score >= DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE \
			and DiplomacyRules.accepts_join_empire(world, player, target, power)
	return true


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
