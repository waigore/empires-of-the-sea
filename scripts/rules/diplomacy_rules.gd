class_name DiplomacyRules
extends RefCounted
## Treaties, court standing and the overture gate (wiki: diplomacy): war, peace,
## alliances, the shared reads every court answers, and whether the next rung
## may be taken. Taking it — charge, record, absorption — is DiplomacyOvertures;
## aid, trade and proposals keep their own modules. Pure rules: callers supply
## DiplomacyState, WorldMap and PlayerEconomy; nothing here touches nodes
## (REQ-P3-03).


## Acceptance decision passed to a transition when the target court answers a
## proposal. `auto` keeps the rule-driven accept/refuse test.
const DECISION_AUTO: String = "auto"
const DECISION_ACCEPT: String = "accept"
const DECISION_REFUSE: String = "refuse"


static func can_declare_war(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if player == target:
		return OrderVerdict.deny("A crown cannot declare war on itself.")
	if not state.has_relation(player, target):
		return OrderVerdict.deny("No envoy has reached that court.")
	var record: DiplomacyRelation = state.relation(player, target)
	if record.at_war:
		return OrderVerdict.deny("%s is already at war with us." % FactionCatalog.name_of(target))
	if record.formal_alliance:
		return OrderVerdict.deny("A formal alliance binds us; break it before war.")
	if has_pact(state, player, target):
		return OrderVerdict.deny("A non-aggression pact binds us; break it before war.")
	if record.treaty_break_turn >= 0 and state.turn <= record.treaty_break_turn:
		return OrderVerdict.deny("A pact was broken this turn; war on that court must wait.")
	return OrderVerdict.allow()


## An active non-aggression pact: the overture chain stands at the pact or any
## later rung, in either direction (wiki: diplomacy § Breaking a pact; #750).
static func has_pact(state: DiplomacyState, a: int, b: int) -> bool:
	var nap_tier: int = _tier(DiplomacyCatalog.STAGE_NAP)
	return _tier(state.overture(a, b)) >= nap_tier \
		or _tier(state.overture(b, a)) >= nap_tier


## `world` reaches deed holders; `aggressor_tech` is the declarer's own tech.
static func declare_war(
	state: DiplomacyState, player: int, target: int,
	call_to_arms: bool = true, world: WorldMap = null, aggressor_tech: Dictionary = {}
) -> Dictionary:
	var check: Dictionary = can_declare_war(state, player, target)
	if not bool(check["ok"]):
		return check
	return _apply_war(state, player, target, call_to_arms, world, aggressor_tech)


## Third-party war entry (a call-to-arms join, an intervention): the joining
## court is honouring a duty, so the war gate is not asked. The war itself ends
## the treaties the pair holds — the pact stage downgrades, the alliance flag
## drops — the same turn the pair stands on opposite sides (wiki: diplomacy
## § GP–GP Rules — war invariant; issue #750).
static func enter_war(state: DiplomacyState, player: int, target: int) -> Dictionary:
	return _apply_war(state, player, target, false, null, {})


static func _apply_war(
	state: DiplomacyState, player: int, target: int,
	call_to_arms: bool, world: WorldMap, aggressor_tech: Dictionary
) -> Dictionary:
	# A duty path (a call-to-arms join, an intervention) never asks the gate, so
	# the pair may have met for the first time on the battlefield: the war is a
	# relation state, so the record is created here rather than assumed
	# (wiki: diplomacy § GP–GP Rules — war invariant; § Intervention).
	var record: DiplomacyRelation = state.ensure_relation(player, target)
	if record == null:
		return {
			"ok": false, "reason": "That court cannot be fought.",
			"calls": [], "interventions": [], "message": "",
		}
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
		return OrderVerdict.deny("No envoy has reached that court.")
	var record: DiplomacyRelation = state.relation(player, target)
	if not record.at_war:
		return OrderVerdict.deny("%s is not at war with us." % FactionCatalog.name_of(target))
	return OrderVerdict.allow()


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
		return OrderVerdict.deny("Only Great Powers sign formal alliances.")
	var record: DiplomacyRelation = state.relation(player, target)
	if record == null:
		return OrderVerdict.deny("No envoy has reached that court.")
	if record.at_war:
		return OrderVerdict.deny("No alliance can be signed while at war.")
	if record.formal_alliance:
		return OrderVerdict.deny("A formal alliance already binds us.")
	if not has_pact(state, player, target):
		return OrderVerdict.deny("An alliance needs a non-aggression pact first.")
	if record.score < DiplomacyCatalog.ALLIANCE_MIN_SCORE:
		# The gate is the hidden score and the sheet shows a tenth-step meter,
		# so the refusal names the gate's distance up that meter rather than a
		# band word the court has not reached (wiki: diplomacy
		# § Player-facing relation display).
		return OrderVerdict.deny(
			"The court is not warm enough for an alliance — the gate stands %s."
			% DiplomacyCatalog.gate_line(record.score, DiplomacyCatalog.ALLIANCE_MIN_SCORE)
		)
	return OrderVerdict.allow()


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


## A formal embassy: the second rung or higher, in either direction
## (wiki: diplomacy § Overtures).
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
## declaration (wiki: factions § Tribe). A Tribe province another crown has
## bought land in is the exception: the investment is a stake, so the march
## needs a declaration like any other foreign land (wiki: factions § Tribe —
## "unless another GP has invested in the province"; DR-20261110-20).
## `model`/`province` are optional so the coarse war query (combat, beachhead
## targeting) keeps its two-argument reading.
static func invadable(
	state: DiplomacyState, attacker: int, target: int,
	model: MapModel = null, province: int = -1
) -> bool:
	return bool(InvasionBar.read(state, attacker, target, model, province).get("ok", false))


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
		return OrderVerdict.deny("A crown cannot treat with itself.")
	if not state.has_relation(player, target):
		return OrderVerdict.deny("No envoy has reached that court.")
	if state.relation(player, target).at_war:
		return OrderVerdict.deny("No overture can be made while at war.")
	if not DiplomacyCatalog.knows_stage(stage) or stage == DiplomacyCatalog.STAGE_NONE:
		return OrderVerdict.deny("Unknown overture.")
	var target_type: int = FactionCatalog.type_of(target)
	var gate: String = DiplomacyCatalog.tech_gate(stage, target_type, tech)
	if not gate.is_empty():
		return OrderVerdict.deny(gate)
	var current: String = state.overture(player, target)
	if stage != DiplomacyCatalog.next_stage(current):
		return OrderVerdict.deny(
			"The next overture is %s." % DiplomacyCatalog.stage_label(
				DiplomacyCatalog.next_stage(current)
			)
		)
	if state.claimed(player, target, "overture"):
		return OrderVerdict.deny("An overture was already made to this court this turn.")
	var provinces: int = provinces_owned(world, target)
	if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		# The gate is the hidden score, not one of the sheet's words: the herald
		# reads Neutral from 50 to 60, so the refusal names the gate's distance
		# up the herald's meter instead of a band word the court has not
		# reached (wiki: diplomacy § Player-facing relation display; playtest
		# diary 2026-11-13, item 3).
		if state.relation(player, target).score < DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE:
			return OrderVerdict.deny(
				"Join Empire needs a warmer court than this one — the gate stands %s."
				% DiplomacyCatalog.gate_line(
					state.relation(player, target).score,
					DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE
				)
			)
		if provinces < 1:
			return OrderVerdict.deny("That faction holds no provinces to join.")
		# A colony is bought once: the Tribe keeps its land, so a second Join
		# Empire would charge the full price for a record that already stands.
		if target_type == FactionCatalog.Type.TRIBE and state.colony_of(target) == player:
			return OrderVerdict.deny("That tribe is already your colony.")
		# A Great Power target is offered to a court that still stands on its own
		# provinces: acceptance, not the offer, reads the near-defeat and power
		# gates (wiki: diplomacy § Join Empire; issue #750).
	var cost: int = DiplomacyCatalog.stage_cost(stage, provinces)
	if treasury < cost:
		return OrderVerdict.deny("The treasury cannot cover the %s." % DiplomacyCatalog.stage_label(stage))
	return {"ok": true, "reason": "", "cost": cost, "provinces": provinces}


static func _accepts_peace(record: DiplomacyRelation, target: int) -> bool:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return true
	return record.score >= DiplomacyCatalog.PEACE_MIN_SCORE


## Join Empire acceptance for a Great Power target: the target is nearly
## defeated, or the offerer's published power is at least
## `JOIN_EMPIRE_POWER_RATIO` times the target's, so standing alone is hopeless
## (wiki: diplomacy § Join Empire; issue #750). A human target answers the
## consent prompt itself; this predicate is the rule- and AI-driven accept.
## Without a power map only the near-defeat criterion answers.
##
## Shared answer (REQ-P3-01): `DiplomacyOvertures.establish_overture` —
## the walk every court, human or rival, takes an absorption through — and
## `AiDiplomacyTreaties.best` — the rival's own pricing of the rung — both
## read this one call, so the AI never prices a yes the rule would refuse.
static func answer_join_empire(
	world: WorldMap, offerer: int, target: int, power: Dictionary = {}
) -> bool:
	if nearly_defeated(world, target):
		return true
	if power.is_empty():
		return false
	var theirs: int = maxi(int(power.get(target, 0)), 1)
	return float(int(power.get(offerer, 0))) \
		>= DiplomacyCatalog.JOIN_EMPIRE_POWER_RATIO * float(theirs)


static func _accepts_alliance(record: DiplomacyRelation) -> bool:
	return record.score >= DiplomacyCatalog.ALLIANCE_CLAMP


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
