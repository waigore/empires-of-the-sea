class_name DiplomacyTreaties
extends RefCounted
## Breaking what was signed: the alliance's unified price, and the binding
## pact's break — its cascade, the treaty it clears and the one-turn war lock
## it stamps (wiki: diplomacy § Breaking an alliance, § Breaking a pact;
## issue #750). Split from [DiplomacyRules] so no rules module outgrows the
## size bar (REQ-P3-01). Pure rules: state in, result out (REQ-P3-03).


## Breaking an alliance keeps its unified price; the pact it rode on stands,
## so the war ban outlives the alliance (wiki: diplomacy § Breaking an
## alliance; issue #750).
static func break_alliance(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	var record: DiplomacyRelation = state.relation(player, target)
	if record == null or not record.formal_alliance:
		return OrderVerdict.deny("There is no formal alliance to break.")
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


## Break NAP: instant, no treasury. The former partner drops 20 and every other
## court the breaker holds a relation with drops 3. A formal alliance rides on
## the pact, so the break clears it too — at the larger alliance price, −50 with
## the partner and −10 with every other Great Power (wiki: diplomacy
## § Breaking a pact; issue #750). The break stamps the pair's one-turn war
## lock: no declaration on that pair until the turn after this one.
static func break_nap(state: DiplomacyState, player: int, target: int) -> Dictionary:
	if not state.has_relation(player, target):
		return OrderVerdict.deny("No envoy has reached that court.")
	var record: DiplomacyRelation = state.relation(player, target)
	if record.at_war:
		return OrderVerdict.deny("War has already ended the pact.")
	if not DiplomacyRules.has_pact(state, player, target):
		return OrderVerdict.deny("There is no non-aggression pact to break.")
	var allied: bool = record.formal_alliance
	record.formal_alliance = false
	record.treaty_break_turn = state.turn
	state.set_overture(player, target, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_overture(target, player, DiplomacyCatalog.STAGE_EMBASSY)
	var partner: float = (
		DiplomacyCatalog.BREAK_ALLY_PENALTY if allied else DiplomacyCatalog.BREAK_NAP_PENALTY
	)
	var cascade: float = (
		DiplomacyCatalog.BREAK_CASCADE_PENALTY
		if allied
		else DiplomacyCatalog.BREAK_NAP_CASCADE_PENALTY
	)
	state.apply_delta(player, target, -partner, "napBroken", {"cleared_alliance": allied})
	for other: DiplomacyRelation in state.relations_of(player):
		var peer: int = other.other(player)
		if peer == target:
			continue
		# The alliance cascade keeps the alliance rule's Great Power filter; the
		# bare pact break reaches every court the breaker holds a relation with.
		if allied and FactionCatalog.type_of(peer) != FactionCatalog.Type.GREAT_POWER:
			continue
		state.apply_delta(player, peer, -cascade, "napBreakCascade")
	var broken: String = "pact and alliance" if allied else "non-aggression pact"
	return {
		"ok": true,
		"reason": "",
		"message": "The %s with %s is broken; war must wait a turn." % [
			broken, FactionCatalog.name_of(target)
		],
	}
