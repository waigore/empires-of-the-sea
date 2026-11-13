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
	decision: String = DiplomacyRules.DECISION_AUTO
) -> Dictionary:
	var treasury: int = economy.treasury if economy != null else 0
	var check: Dictionary = DiplomacyRules.can_establish_overture(
		state, world, player, target, stage, treasury, tech
	)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "overture")
	var record: DiplomacyRelation = state.relation(player, target)
	var accepts: bool = _accepts_overture(record, target, stage)
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
static func stage_hint(stage: String, target_type: int) -> String:
	if stage != DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		return ""
	match target_type:
		FactionCatalog.Type.TRIBE:
			return (
				"A colony: the tribe keeps its land, so its provinces never count "
				+ "toward victory — its trade favours your court."
			)
		FactionCatalog.Type.MINOR_NATION:
			return "Its provinces and regiments join your empire."
		_:
			return "A nearly defeated crown's provinces and armies join yours."


static func _absorb(world: WorldMap, state: DiplomacyState, winner: int, loser: int) -> void:
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.owner == loser:
				province.owner = winner
	state.clear_relations_of(loser)
	state.record_event("joinEmpire", winner, loser)


static func _accepts_overture(
	record: DiplomacyRelation, target: int, stage: String
) -> bool:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return true
	if stage == DiplomacyCatalog.STAGE_NAP:
		return record.score >= DiplomacyCatalog.NAP_MIN_SCORE
	if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		return record.score >= DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE
	return true


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
