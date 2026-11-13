class_name DiplomacyRules
extends RefCounted
## Diplomacy transitions and order resolution (wiki: diplomacy). Pure rules:
## callers supply DiplomacyState, WorldMap and PlayerEconomy; nothing here
## touches nodes (REQ-P3-03).


## Acceptance decision passed to a transition when the target court answers a
## proposal. `auto` keeps the rule-driven accept/refuse test.
const DECISION_AUTO: String = "auto"
const DECISION_ACCEPT: String = "accept"
const DECISION_REFUSE: String = "refuse"


static func can_declare_war(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if player == target:
		return _deny("A crown cannot declare war on itself.")
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	var record: DiplomacyRelation = state.relation(player, target)
	if record.at_war:
		return _deny("%s is already at war with us." % FactionCatalog.name_of(target))
	return _allow()


## `world` reaches deed holders; `aggressor_tech` is the declarer's own tech.
static func declare_war(
	state: DiplomacyState, player: int, target: int,
	call_to_arms: bool = true, world: WorldMap = null, aggressor_tech: Dictionary = {}
) -> Dictionary:
	var check: Dictionary = can_declare_war(state, player, target)
	if not bool(check["ok"]):
		return check
	var record: DiplomacyRelation = state.relation(player, target)
	record.at_war = true
	record.since_turn = state.turn
	record.formal_alliance = false
	if _downgrade_overtures(state, player, target):
		state.record_event("overturesCleared", player, target)
	DiplomacyTrade.sever(state, player, target)
	state.touch(player, target, "warDeclared")
	# Mutual defence: a declaration drags allies of the defender in (or queues
	# the human court's consent decision). A call-to-arms join never cascades.
	var calls: Array[String] = []
	if call_to_arms:
		calls = CallToArms.on_war_declared(state, player, target)
	# A war on a Minor Nation or Tribe lets courts with an embassy there answer
	# (wiki: diplomacy § Intervention).
	var interventions: Array[String] = []
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		interventions = Intervention.on_war_declared(state, player, target, world, aggressor_tech)
	return {
		"ok": true,
		"reason": "",
		"calls": calls,
		"interventions": interventions,
		"message": "%s declares war on %s." % [
			FactionCatalog.name_of(player), FactionCatalog.name_of(target)
		],
	}


static func can_make_peace(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	var record: DiplomacyRelation = state.relation(player, target)
	if not record.at_war:
		return _deny("%s is not at war with us." % FactionCatalog.name_of(target))
	return _allow()


## A court answers the white-peace offer. `auto` keeps the rule-driven test;
## `accept`/`refuse` carry the human court's decision (wiki: diplomacy
## § GP–GP Rules — peace needs both sides).
static func make_peace(
	state: DiplomacyState, player: int, target: int, decision: String = DECISION_AUTO
) -> Dictionary:
	var check: Dictionary = can_make_peace(state, player, target)
	if not bool(check["ok"]):
		return check
	var record: DiplomacyRelation = state.relation(player, target)
	var accepts: bool = _accepts_peace(record, target)
	if decision == DECISION_ACCEPT:
		accepts = true
	elif decision == DECISION_REFUSE:
		accepts = false
	if not accepts:
		return {
			"ok": true,
			"accepted": false,
			"message": "%s refuses a white peace." % FactionCatalog.name_of(target),
		}
	record.at_war = false
	record.since_turn = state.turn
	state.touch(player, target, "peaceMade")
	return {
		"ok": true,
		"accepted": true,
		"message": "Peace is concluded with %s." % FactionCatalog.name_of(target),
	}


static func can_form_alliance(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return _deny("Only Great Powers sign formal alliances.")
	var record: DiplomacyRelation = state.relation(player, target)
	if record == null:
		return _deny("No envoy has reached that court.")
	if record.at_war:
		return _deny("No alliance can be signed while at war.")
	if record.formal_alliance:
		return _deny("A formal alliance already binds us.")
	if record.score < DiplomacyCatalog.ALLIANCE_MIN_SCORE:
		return _deny("The court is not friendly enough for an alliance.")
	return _allow()


static func form_alliance(
	state: DiplomacyState, player: int, target: int, decision: String = DECISION_AUTO
) -> Dictionary:
	var check: Dictionary = can_form_alliance(state, player, target)
	if not bool(check["ok"]):
		return check
	var record: DiplomacyRelation = state.relation(player, target)
	var accepts: bool = _accepts_alliance(record)
	if decision == DECISION_ACCEPT:
		accepts = true
	elif decision == DECISION_REFUSE:
		accepts = false
	if not accepts:
		return {
			"ok": true,
			"accepted": false,
			"message": "%s declines the alliance." % FactionCatalog.name_of(target),
		}
	record.formal_alliance = true
	record.since_turn = state.turn
	record.set_score(maxf(record.score, DiplomacyCatalog.ALLIANCE_CLAMP))
	state.touch(player, target, "allianceFormed")
	return {
		"ok": true,
		"accepted": true,
		"message": "A formal alliance is sealed with %s." % FactionCatalog.name_of(target),
	}


static func break_alliance(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	var record: DiplomacyRelation = state.relation(player, target)
	if record == null or not record.formal_alliance:
		return _deny("There is no formal alliance to break.")
	record.formal_alliance = false
	state.apply_delta(player, target, -DiplomacyCatalog.BREAK_ALLY_PENALTY, "allianceBroken")
	for other: DiplomacyRelation in state.relations_of(player):
		var peer: int = other.other(player)
		if peer == target or FactionCatalog.type_of(peer) != FactionCatalog.Type.GREAT_POWER:
			continue
		state.apply_delta(
			player, peer, -DiplomacyCatalog.BREAK_CASCADE_PENALTY, "allianceBreakCascade"
		)
	return {
		"ok": true,
		"reason": "",
		"message": "The alliance with %s is broken; the other courts take note." % (
			FactionCatalog.name_of(target)
		),
	}


static func has_embassy(state: DiplomacyState, a: int, b: int) -> bool:
	return _tier(state.overture(a, b)) >= 2 or _tier(state.overture(b, a)) >= 2


## A Trade Consulate or any higher overture stage, in either direction
## (wiki: civilian-units § Work Order Summary — explore/prospect in a
## Minor or Tribe province).
static func has_consulate(state: DiplomacyState, a: int, b: int) -> bool:
	if state == null:
		return false
	return _tier(state.overture(a, b)) >= 1 or _tier(state.overture(b, a)) >= 1


## War state between two factions. Without a court (isolated fixtures) factions
## stay hostile to each other, preserving the legacy every-fleet-is-hostile rule.
static func at_war_with(state: DiplomacyState, a: int, b: int) -> bool:
	if state == null:
		return true
	var record: DiplomacyRelation = state.relation(a, b)
	return record != null and record.at_war


## Land a Great Power may enter: a declared enemy's, or a Tribe's without a
## declaration (wiki: factions § Tribe).
## Purchased-tile protection is deferred with land purchase (DR-20261108-06).
static func invadable(state: DiplomacyState, attacker: int, target: int) -> bool:
	if attacker == target:
		return false
	if FactionCatalog.type_of(target) == FactionCatalog.Type.TRIBE:
		return true
	return at_war_with(state, attacker, target)


static func provinces_owned(world: WorldMap, faction: int) -> int:
	if world == null:
		return 0
	var total: int = 0
	for index in world.region_count():
		total += world.owned_provinces(index, faction)
	return total


## Three or fewer provinces and the original capital is no longer held.
static func nearly_defeated(world: WorldMap, faction: int) -> bool:
	if world == null or provinces_owned(world, faction) > 3:
		return false
	for index in world.region_count():
		if world.capital_province_of(index, faction) != MapModel.NO_ID:
			return false
	return true


static func can_establish_overture(
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	target: int,
	stage: String,
	treasury: int,
	tech: Dictionary = {}
) -> Dictionary:
	if player == target:
		return _deny("A crown cannot treat with itself.")
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	if state.relation(player, target).at_war:
		return _deny("No overture can be made while at war.")
	if not DiplomacyCatalog.knows_stage(stage) or stage == DiplomacyCatalog.STAGE_NONE:
		return _deny("Unknown overture.")
	var target_type: int = FactionCatalog.type_of(target)
	var gate: String = DiplomacyCatalog.tech_gate(stage, target_type, tech)
	if not gate.is_empty():
		return _deny(gate)
	var current: String = state.overture(player, target)
	if stage != DiplomacyCatalog.next_stage(current):
		return _deny(
			"The next overture is %s." % DiplomacyCatalog.stage_label(
				DiplomacyCatalog.next_stage(current)
			)
		)
	if state.claimed(player, target, "overture"):
		return _deny("An overture was already made to this court this turn.")
	var provinces: int = provinces_owned(world, target)
	if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		if state.relation(player, target).score < DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE:
			return _deny("Join Empire requires Friendly or Allied standing.")
		if provinces < 1:
			return _deny("That faction holds no provinces to join.")
		# A colony is bought once: the Tribe keeps its land, so a second Join
		# Empire would charge the full price for a record that already stands.
		if target_type == FactionCatalog.Type.TRIBE and state.colony_of(target) == player:
			return _deny("That tribe is already your colony.")
		if target_type == FactionCatalog.Type.GREAT_POWER and not nearly_defeated(world, target):
			return _deny("Only a nearly defeated Great Power may be absorbed.")
	var cost: int = DiplomacyCatalog.stage_cost(stage, provinces)
	if treasury < cost:
		return _deny("The treasury cannot cover the %s." % DiplomacyCatalog.stage_label(stage))
	return {"ok": true, "reason": "", "cost": cost, "provinces": provinces}


static func establish_overture(
	state: DiplomacyState,
	economy: PlayerEconomy,
	world: WorldMap,
	player: int,
	target: int,
	stage: String,
	tech: Dictionary = {},
	decision: String = DECISION_AUTO
) -> Dictionary:
	var treasury: int = economy.treasury if economy != null else 0
	var check: Dictionary = can_establish_overture(
		state, world, player, target, stage, treasury, tech
	)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "overture")
	var record: DiplomacyRelation = state.relation(player, target)
	var accepts: bool = _accepts_overture(record, target, stage)
	if decision == DECISION_ACCEPT:
		accepts = true
	elif decision == DECISION_REFUSE:
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


static func _absorb(world: WorldMap, state: DiplomacyState, winner: int, loser: int) -> void:
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.owner == loser:
				province.owner = winner
	state.clear_relations_of(loser)
	state.record_event("joinEmpire", winner, loser)


static func _accepts_peace(record: DiplomacyRelation, target: int) -> bool:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return true
	return record.score >= DiplomacyCatalog.PEACE_MIN_SCORE


static func _accepts_alliance(record: DiplomacyRelation) -> bool:
	return record.score >= DiplomacyCatalog.ALLIANCE_CLAMP


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


static func _downgrade_overtures(state: DiplomacyState, a: int, b: int) -> bool:
	var gp_pair: bool = (
		FactionCatalog.type_of(a) == FactionCatalog.Type.GREAT_POWER
		and FactionCatalog.type_of(b) == FactionCatalog.Type.GREAT_POWER
	)
	var changed: bool = false
	for direction: Vector2i in [Vector2i(a, b), Vector2i(b, a)]:
		var stage: String = DiplomacyCatalog.STAGE_NONE
		if gp_pair:
			stage = DiplomacyCatalog.STAGE_EMBASSY
		if state.overture(direction.x, direction.y) == stage:
			continue
		state.set_overture(direction.x, direction.y, stage)
		changed = true
	return changed


static func _tier(stage: String) -> int:
	return DiplomacyCatalog.STAGES.find(stage)


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
