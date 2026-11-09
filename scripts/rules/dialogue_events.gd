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
## always has something to show for a court it knows (REQ-P5-05).
static func for_pair(state: DiplomacyState, viewer: int, other: int) -> Dictionary:
	if state == null or viewer == other:
		return {}
	for entry: Dictionary in DiplomacyHistory.entries(state, viewer, other):
		var index: int = int(entry.get("index", -1))
		if index < 0 or index >= state.events.size():
			continue
		var spoken: Dictionary = for_event(state, state.events[index], viewer)
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
	return {}


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
