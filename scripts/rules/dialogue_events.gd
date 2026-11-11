class_name DialogueEvents
extends RefCounted
## A rival court's spoken word, derived from what actually happened (wiki:
## dialogue-and-mood § Design intent, dialogue-management § Design intent).
## Presentation only: the rules layer writes events, this module only reads one
## back into a line, a face and a category, so a court can never talk its way
## into a different outcome (REQ-P2-03). Selection is a stable hash of
## (turn, speaker, viewer, point), so a reloaded campaign speaks identically
## (REQ-P2-04, REQ-P3-03).


## The hottest word for one recorded diplomacy event, or {} when the act is not
## voiced. `viewer` is the court reading the panel; the speaker is always the
## other party, never the reader.
static func for_event(state: DiplomacyState, event: Dictionary, viewer: int) -> Dictionary:
	if state == null or typeof(event) != TYPE_DICTIONARY:
		return {}
	var plan: Dictionary = _plan(event, viewer)
	if plan.is_empty():
		return {}
	var speaker: int = int(plan["speaker"])
	if speaker < 0 or speaker == viewer:
		return {}
	var point: String = String(plan["point"])
	var salt: int = _salt(int(event.get("turn", state.turn)), speaker, viewer, point)
	var template: String = DialogueCatalog.line_for(point, salt)
	if template.is_empty():
		return {}
	return _spoken(state, viewer, speaker, point, template, DialogueCatalog.mood_for(point, salt))


## The pair's newest voiced word, else the court's standing remark, so the panel
## always has something to show for a court it knows (REQ-P5-05). The log is
## scanned newest first, not the narrated chronicle, so a beat the chronicle
## stays silent about (a battle) can still be the court's last word.
static func for_pair(state: DiplomacyState, viewer: int, other: int) -> Dictionary:
	if state == null or viewer == other:
		return {}
	for index in range(state.events.size() - 1, -1, -1):
		var event: Dictionary = state.events[index]
		if typeof(event) != TYPE_DICTIONARY:
			continue
		if not DiplomacyHistory.parties(event).has(other):
			continue
		var spoken: Dictionary = for_event(state, event, viewer)
		if not spoken.is_empty():
			return spoken
	return standing(state, viewer, other)


## A silence has a voice too: the court's word for its current stand with the
## reader, drawn from the relation band and never from the sealed score.
static func standing(state: DiplomacyState, viewer: int, other: int) -> Dictionary:
	if state == null or viewer == other:
		return {}
	var record: DiplomacyRelation = state.relation(viewer, other)
	if record == null:
		return {}
	var point: String = "reactive/standing_neutral"
	if record.at_war:
		point = "reactive/standing_war"
	elif record.formal_alliance:
		point = "reactive/standing_alliance"
	elif record.score >= DiplomacyCatalog.ALLIANCE_MIN_SCORE:
		point = "reactive/standing_friendly"
	elif record.score < DiplomacyCatalog.NAP_MIN_SCORE:
		point = "reactive/standing_cold"
	var template: String = DialogueCatalog.line_for(
		point, _salt(state.turn, other, viewer, point)
	)
	if template.is_empty():
		return {}
	return _spoken(
		state, viewer, other, point, template,
		DialogueCatalog.mood_for(point, _salt(state.turn, other, viewer, point))
	)


## Records a land battle the reader fought, so the court can answer the field
## (wiki: dialogue-and-mood § Design intent — event: battle results). Only a
## battle the reader was in is kept: the panel only ever speaks to the human
## crown, so a rival's own fights would be words nobody reads. A standoff, a
## mutual ruin and an unopposed capture have no verdict and write nothing.
## Returns true when a beat was recorded.
static func record_land_battle(
	state: DiplomacyState, battle: Dictionary, viewer: int
) -> bool:
	if typeof(battle) != TYPE_DICTIONARY:
		return false
	var winner: int = -1
	match int(battle.get("outcome", ArmyCombat.Outcome.STALEMATE)):
		ArmyCombat.Outcome.ATTACKER_VICTORY, ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			winner = int(battle.get("attacker", -1))
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			winner = int(battle.get("defender", -1))
	var kind: String = "siege" if String(battle.get("battle_mode", "")) == "siege" else "field"
	return _record_battle(state, battle, viewer, kind, winner)


## The same for a sea fight. A beaten squadron that withdraws still lost the
## water, so its withdrawal is the verdict (wiki: ships-and-naval § Naval
## Combat; dialogue-and-mood § Design intent — event).
static func record_naval_battle(
	state: DiplomacyState, battle: Dictionary, viewer: int
) -> bool:
	if typeof(battle) != TYPE_DICTIONARY:
		return false
	var winner: int = -1
	match int(battle.get("outcome", NavalCombat.Outcome.NONE)):
		NavalCombat.Outcome.SIDE1_VICTORY:
			winner = int(battle.get("attacker", -1))
		NavalCombat.Outcome.SIDE2_VICTORY:
			winner = int(battle.get("defender", -1))
	var retreat: Variant = battle.get("retreat", {})
	if winner < 0 and typeof(retreat) == TYPE_DICTIONARY:
		var beaten: int = int((retreat as Dictionary).get("beaten", -1))
		if bool((retreat as Dictionary).get("success", false)) and beaten >= 0:
			winner = (
				int(battle.get("defender", -1))
				if beaten == int(battle.get("attacker", -1))
				else int(battle.get("attacker", -1))
			)
	return _record_battle(state, battle, viewer, "sea", winner)


static func _record_battle(
	state: DiplomacyState,
	battle: Dictionary,
	viewer: int,
	kind: String,
	winner: int
) -> bool:
	if state == null or winner < 0:
		return false
	var attacker: int = int(battle.get("attacker", -1))
	var defender: int = int(battle.get("defender", -1))
	if attacker < 0 or defender < 0 or attacker == defender:
		return false
	if winner != attacker and winner != defender:
		return false
	if viewer != attacker and viewer != defender:
		return false
	state.record_event(
		"battleFought", attacker, defender, {"kind": kind, "winner": winner}
	)
	return true


## The negotiation beat for a proposal awaiting the reader's answer: the point
## says what is on the table, and [DialogueMood] reads the wait and the offer's
## generosity off the offer itself (wiki: dialogue-and-mood § Mood machine).
static func for_offer(state: DiplomacyState, viewer: int, offer: Dictionary) -> Dictionary:
	if state == null or offer.is_empty():
		return {}
	var from_id: int = int(offer.get("from", -1))
	if from_id < 0 or from_id == viewer:
		return {}
	var kind: String = String(offer.get("kind", ""))
	var stage: String = String(offer.get("stage", ""))
	var point: String = "negotiation/proposal_%s" % kind
	if not DialogueCatalog.has_point(point):
		return {}
	var record: DiplomacyRelation = state.relation(viewer, from_id)
	var score: float = record.score if record != null else DiplomacyCatalog.INITIAL_SCORE
	var stall: int = DialogueMood.stall(int(offer.get("turn", state.turn)), state.turn)
	var salt: int = _salt(state.turn, from_id, viewer, "%s:%s" % [point, stage])
	var template: String = DialogueCatalog.line_for(point, salt)
	if template.is_empty():
		return {}
	var spoken: Dictionary = _spoken(
		state, viewer, from_id, point, template, DialogueMood.OPEN_MOOD
	)
	spoken["mood"] = DialogueMood.for_offer(
		stall, DialogueMood.quality(score, _required(kind, stage)), salt
	)
	return spoken


static func _spoken(
	state: DiplomacyState,
	viewer: int,
	speaker: int,
	point: String,
	template: String,
	mood: String
) -> Dictionary:
	return {
		"speaker": speaker,
		"point": point,
		"category": DialogueCatalog.category_for(point),
		"mood": mood,
		"text": DialogueCatalog.render(
			template, _name(state, viewer, speaker), _name(state, viewer, viewer)
		),
	}


## Which point a recorded act speaks, and who speaks it. Bookkeeping acts
## (subsidy, aid, colony status) are not voiced: the standing word covers them.
static func _plan(event: Dictionary, viewer: int) -> Dictionary:
	var kind: String = String(event.get("kind", ""))
	var a: int = int(event.get("a", -1))
	var b: int = int(event.get("b", -1))
	if viewer != a and viewer != b:
		return {}
	var other: int = b if a == viewer else a
	match kind:
		"warDeclared":
			if a == viewer:
				return _told("diplomatic/war_declared_by_you", other)
			return _told("diplomatic/war_declared_by_them", a)
		"peaceMade":
			return _told("diplomatic/peace_made", other)
		"allianceFormed":
			return _told("diplomatic/alliance_formed", other)
		"allianceBroken":
			if a == viewer:
				return _told("diplomatic/alliance_broken_by_you", other)
			return _told("diplomatic/alliance_broken_by_them", a)
		"callToArmsAccepted":
			return _told("diplomatic/call_to_arms_joined", other)
		"callToArmsRefused":
			return _told("diplomatic/call_to_arms_refused", other)
		"interventionIntervened":
			return _told("diplomatic/intervention_joined", other)
		"interventionDoNothing":
			return _told("diplomatic/intervention_stood_aside", other)
		"interventionProtest":
			return _told("diplomatic/intervention_protested", other)
		"proposalAccepted":
			return _told("diplomatic/proposal_accepted", other)
		"proposalRefused":
			return _told("diplomatic/proposal_refused", other)
		"overtureEstablished":
			if a == viewer:
				return _told("diplomatic/overture_accepted", other)
			return _told("diplomatic/overture_granted", a)
		"overtureRejected":
			if a == viewer:
				return _told("diplomatic/overture_refused", other)
			return _told("diplomatic/overture_withdrawn", a)
		"firstContact":
			return _told("diplomatic/first_contact", other)
		"battleFought":
			return _battle_plan(event, viewer, other)
	return {}


## The court that reads the verdict speaks it: the winner is pleased and the
## beaten court is not, and a siege names the part each played (DR-20261111-01).
## A beat with no verdict, or one naming a court outside the pair, says nothing.
static func _battle_plan(event: Dictionary, viewer: int, other: int) -> Dictionary:
	var data: Variant = event.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var winner: int = int((data as Dictionary).get("winner", -1))
	if winner != viewer and winner != other:
		return {}
	var speaker_won: bool = winner == other
	var kind: String = String((data as Dictionary).get("kind", "field"))
	if kind == "sea":
		return _told("event/sea_won" if speaker_won else "event/sea_lost", other)
	if kind == "siege":
		var speaker_attacked: bool = other == int(event.get("a", -1))
		if speaker_won:
			return _told(
				"event/siege_won" if speaker_attacked else "event/siege_held", other
			)
		return _told(
			"event/siege_lost" if speaker_attacked else "event/siege_taken", other
		)
	return _told("event/field_won" if speaker_won else "event/field_lost", other)


## Relation floor the offer's own rules put under it, so quality is measured
## against what the court actually asked for (wiki: diplomacy § thresholds).
static func _required(kind: String, stage: String) -> float:
	match kind:
		DiplomacyProposals.KIND_ALLIANCE:
			return DiplomacyCatalog.ALLIANCE_MIN_SCORE
		DiplomacyProposals.KIND_PEACE:
			return DiplomacyCatalog.PEACE_MIN_SCORE
		DiplomacyProposals.KIND_OVERTURE:
			if stage == DiplomacyCatalog.STAGE_NAP:
				return DiplomacyCatalog.NAP_MIN_SCORE
			if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
				return DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE
	return 0.0


static func _name(state: DiplomacyState, viewer: int, faction: int) -> String:
	return DiplomacyHistory.name_for(state, viewer, faction)


static func _told(point: String, speaker: int) -> Dictionary:
	return {"point": point, "speaker": speaker}


## Deterministic integer salt: the same act, court and reader always pick the
## same line and the same face, in this run and after a save.
static func _salt(turn: int, speaker: int, viewer: int, extra: String) -> int:
	var value: int = 7
	for part: int in [turn, speaker, viewer]:
		value = absi(value * 131 + part + 17) % 1000003
	for byte: int in extra.to_utf8_buffer():
		value = absi(value * 131 + byte + 17) % 1000003
	return value
