class_name IntelEvidence
extends RefCounted
## Reads the crown's chronicle into dossier evidence (wiki: ai-dossier,
## hidden-agendas): what a court's observable acts weigh, and the one
## player-facing sentence each act earns. IntelDossier scores and presents the
## observations this module collects (REQ-P3-01, REQ-P3-03).
##
## Pure RefCounted over `DiplomacyState.events` (which the campaign persists);
## nothing here reads an AI's true agenda, so the reading can be shown to the
## player and replayed from a save (REQ-P2-01). The newest [constant
## EVIDENCE_CAP] observations survive and older ones drop, so a long campaign
## cannot grow the dossier without bound.

const EVIDENCE_CAP: int = 50

## Evidence weights (DR-20261110-05). One act may speak to more than one agenda.
const W_WAR: int = 2
const W_WEAKER: int = 1
const W_STRONGER: int = 2
const W_HUMAN_AHEAD: int = 1
const W_WAR_ON_ALLY: int = 4
const W_BREAK_ALLY: int = 3
const W_BREAK_ISOLATION: int = 1
const W_CTA_REFUSED: int = 2
const W_STOOD_ASIDE: int = 1
const W_INTERVENED: int = 2
const W_PROTESTED: int = 1
const W_PEACE: int = 2
const W_ACCEPTED_OFFER: int = 1
const W_REFUSED_OFFER: int = 1
const W_ALLIANCE: int = 1
const W_AID: int = 1
const W_ABSORB: int = 1
## A study a shadowed court finished (DR-20261110-25). Research is hidden, so
## only the court report can carry it; a court that keeps finishing studies
## under the spy's eye reads as racing the field.
const W_SPY_TECH: int = 2

## Chronicle kinds the spy writes about a court it shadows. Neither is narrated
## in the pair's chronicle: they are intelligence, not diplomacy.
const SPY_TECH: String = "spyTechObserved"
const SPY_BUILD: String = "spyBuildObserved"
## The turn a despatch observed (the spy reports after the calendar advanced).
const OBSERVED_TURN: String = "observed_turn"

const UNKNOWN_COURT: String = "an unknown court"


## Observable acts by the subject, newest first, capped. A court the viewer has
## not met stays masked; acts against courts it has not met name them not at all.
static func collect(
	state: DiplomacyState, world: WorldMap, viewer: int, subject: int
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if state == null or viewer == subject:
		return found
	var allies: Dictionary = {}
	for index in state.events.size():
		var event: Dictionary = state.events[index]
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var kind: String = String(event.get("kind", ""))
		var a: int = int(event.get("a", -1))
		var b: int = int(event.get("b", -1))
		var key: String = _pair(a, b)
		var weights: Dictionary = _weights_for(world, viewer, subject, event, allies)
		if kind == "allianceFormed" and a != b:
			allies[key] = true
		elif kind == "allianceBroken" or kind == "warDeclared":
			allies.erase(key)
		if weights.is_empty():
			continue
		found.append(
			{
				"turn": turn_of(event),
				"index": index,
				"kind": kind,
				"text": _text_for(state, viewer, subject, event),
				"weights": weights,
			}
		)
	if found.size() > EVIDENCE_CAP:
		found = found.slice(found.size() - EVIDENCE_CAP)
	found.reverse()
	return found


## The turn an observation belongs to: the chronicle's stamp, or the despatch's.
static func turn_of(event: Dictionary) -> int:
	var data: Dictionary = _kind_data(event)
	if data.has(OBSERVED_TURN):
		return int(data[OBSERVED_TURN])
	return int(event.get("turn", 0))


static func provinces(world: WorldMap, faction: int) -> int:
	if world == null:
		return 0
	return DiplomacyRules.provinces_owned(world, faction)


## The one act can feed several agendas; only the subject's own acts count.
static func _weights_for(
	world: WorldMap,
	viewer: int,
	subject: int,
	event: Dictionary,
	allies: Dictionary
) -> Dictionary:
	var kind: String = String(event.get("kind", ""))
	var a: int = int(event.get("a", -1))
	var b: int = int(event.get("b", -1))
	var weights: Dictionary = {}
	match kind:
		"warDeclared":
			if a != subject:
				return weights
			var mine: int = provinces(world, subject)
			var theirs: int = provinces(world, b)
			if bool(allies.get(_pair(a, b), false)):
				weights[AiAgenda.BACKSTABBER] = W_WAR_ON_ALLY
			else:
				weights[AiAgenda.WARMONGER] = W_WAR
			if theirs < mine:
				weights[AiAgenda.WARMONGER] = int(weights.get(AiAgenda.WARMONGER, 0)) + W_WEAKER
			elif theirs > mine:
				weights[AiAgenda.ENVY] = W_STRONGER
				if b == viewer:
					weights[AiAgenda.ENVY] = W_STRONGER + W_HUMAN_AHEAD
		"allianceBroken":
			if a != subject:
				return weights
			weights[AiAgenda.BACKSTABBER] = W_BREAK_ALLY
			weights[AiAgenda.ISOLATIONIST] = W_BREAK_ISOLATION
		"callToArmsRefused":
			if a == subject:
				weights[AiAgenda.ISOLATIONIST] = W_CTA_REFUSED
		"interventionDoNothing":
			if a == subject:
				weights[AiAgenda.ISOLATIONIST] = W_STOOD_ASIDE
		"interventionIntervened":
			if a == subject:
				weights[AiAgenda.PEACEMAKER] = W_INTERVENED
		"interventionProtest":
			# A court that keeps its embassy and puts a price on the aggression
			# reads as a peace-seeker, just less loudly than one that joins
			# (DR-20261110-16).
			if a == subject:
				weights[AiAgenda.PEACEMAKER] = W_PROTESTED
		"peaceMade":
			if a == subject:
				weights[AiAgenda.PEACEMAKER] = W_PEACE
		"proposalAccepted":
			if b == subject:
				weights[AiAgenda.PEACEMAKER] = W_ACCEPTED_OFFER
		"proposalRefused":
			if b == subject:
				weights[AiAgenda.ISOLATIONIST] = W_REFUSED_OFFER
		"allianceFormed":
			if a == subject:
				weights[AiAgenda.PEACEMAKER] = W_ALLIANCE
		"grantAid":
			if a == subject:
				weights[AiAgenda.PEACEMAKER] = W_AID
		"joinEmpire":
			if a == subject:
				weights[AiAgenda.WARMONGER] = W_ABSORB
		"spyTechObserved":
			# The spy is the only witness to a rival's research, so the act is
			# evidence only for the crown that posted it (DR-20261110-25).
			if a != subject or b != viewer:
				return weights
			weights[AiAgenda.TECH_THIEF] = W_SPY_TECH
		_:
			pass
	return weights


## One player-facing sentence per observation. Names are masked against the
## viewing crown's contacts, so the dossier never names a stranger.
static func _text_for(
	state: DiplomacyState, viewer: int, subject: int, event: Dictionary
) -> String:
	var kind: String = String(event.get("kind", ""))
	var a: int = int(event.get("a", -1))
	var b: int = int(event.get("b", -1))
	var data: Dictionary = _kind_data(event)
	# The other party is whichever side of the act is not the subject: the
	# declarer's target, the proposer whose offer was answered, the ally lost.
	var other: String = _court(state, viewer, b if a == subject else a)
	var aggressor: String = _court(state, viewer, int(data.get("aggressor", -1)))
	match kind:
		"warDeclared":
			return "Declared war on %s." % other
		"allianceBroken":
			return "Broke its formal alliance with %s." % other
		"callToArmsRefused":
			return "Refused %s's call to arms." % other
		"interventionDoNothing":
			return "Stood aside while %s made war on %s." % [aggressor, other]
		"interventionIntervened":
			return "Intervened against %s on behalf of %s." % [aggressor, other]
		"interventionProtest":
			return "Protested %s's war on %s." % [
				other, _court(state, viewer, int(data.get("target", -1)))
			]
		"peaceMade":
			return "Concluded a white peace with %s." % other
		"proposalAccepted":
			return "Accepted %s's offer of %s." % [
				other, DiplomacyProposals.describe(String(data.get("kind", "")), String(data.get("stage", "")))
			]
		"proposalRefused":
			return "Refused %s's offer of %s." % [
				other, DiplomacyProposals.describe(String(data.get("kind", "")), String(data.get("stage", "")))
			]
		"allianceFormed":
			return "Signed a formal alliance with %s." % other
		"grantAid":
			return "Sent aid to %s." % other
		"joinEmpire":
			return "Absorbed %s into its empire." % other
		"spyTechObserved":
			var tech: String = String(data.get("tech", ""))
			var study: String = (
				TechCatalog.display_name(tech) if not tech.is_empty() else "a technology"
			)
			return "Finished %s while our spy watched." % study
	return "Acted at %s." % FactionCatalog.name_of(subject)


static func _pair(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func _court(state: DiplomacyState, viewer: int, faction: int) -> String:
	var name: String = DiplomacyHistory.name_for(state, viewer, faction)
	if name == DiplomacyHistory.UNKNOWN_NAME:
		return UNKNOWN_COURT
	return name


static func _kind_data(event: Dictionary) -> Dictionary:
	var raw: Variant = event.get("data", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw as Dictionary
