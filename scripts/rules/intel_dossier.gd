class_name IntelDossier
extends RefCounted
## The human court's intelligence reading (wiki: ai-dossier, hidden-agendas).
## Pure RefCounted: every observable act the crown's chronicle already records
## is turned into evidence for one of the six agendas, and the bands confidence
## follow the dossier tables. Nothing here reads an AI's true agenda — the
## reading is built from public acts only, so it can be shown to the player and
## replayed from a save (REQ-P2-01, REQ-P3-03).
##
## Evidence is computed on demand from `DiplomacyState.events` (which the
## campaign persists); the newest [constant EVIDENCE_CAP] observations survive and
## older ones drop, so a long campaign cannot grow the dossier without bound.

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

const UNKNOWN_COURT: String = "an unknown court"


## Suspicion band and confidence from the dossier table: 0–2 / 3–5 / 6–8 /
## 9–10 / 11+ (wiki: ai-dossier § Architecture — confidence bands).
static func band_for(score: int) -> Dictionary:
	var value: int = maxi(score, 0)
	if value >= 11:
		return {"label": "Confirmed", "confidence": 100}
	if value >= 9:
		return {"label": "Almost certain", "confidence": 85}
	if value >= 6:
		return {"label": "Likely", "confidence": 60}
	if value >= 3:
		return {"label": "Possible", "confidence": 25}
	return {"label": "Unknown", "confidence": 0}


## One dossier for a viewing crown: evidence, per-agenda suspicion, best guess
## and the behaviour counts the notes read.
static func report(
	state: DiplomacyState, world: WorldMap, viewer: int, subject: int
) -> Dictionary:
	var entries: Array[Dictionary] = evidence(state, world, viewer, subject)
	var scores: Dictionary = suspicion(entries)
	var rows: Array[Dictionary] = _agenda_rows(scores)
	return {
		"subject": subject,
		"evidence": entries,
		"agendas": rows,
		"guess": _best_guess(rows),
		"notes": _notes(entries, world, subject),
	}


## Observable acts by the subject, newest first, capped. A court the viewer has
## not met stays masked; acts against courts it has not met name them not at all.
static func evidence(
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
		var weights: Dictionary = _weights_for(state, world, viewer, subject, event, allies)
		if kind == "allianceFormed" and a != b:
			allies[key] = true
		elif kind == "allianceBroken" or kind == "warDeclared":
			allies.erase(key)
		if weights.is_empty():
			continue
		found.append(
			{
				"turn": int(event.get("turn", 0)),
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


## Points per agenda: every retained observation's weights, summed.
static func suspicion(entries: Array[Dictionary]) -> Dictionary:
	var scores: Dictionary = {}
	for entry: Dictionary in entries:
		var weights: Dictionary = entry["weights"] as Dictionary
		for raw: Variant in weights.keys():
			var id: String = String(raw)
			if not AiAgenda.has(id):
				continue
			scores[id] = int(scores.get(id, 0)) + int(weights[raw])
	return scores


## The one act can feed several agendas; only the subject's own acts count.
static func _weights_for(
	state: DiplomacyState,
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
			var mine: int = _provinces(world, subject)
			var theirs: int = _provinces(world, b)
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
	return "Acted at %s." % FactionCatalog.name_of(subject)


## Every agenda, highest suspicion first; ties keep the catalogue order.
static func _agenda_rows(scores: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw: Variant in AiAgenda.IDS:
		var id: String = String(raw)
		var score: int = int(scores.get(id, 0))
		var band: Dictionary = band_for(score)
		rows.append(
			{
				"id": id,
				"label": display(id),
				"score": score,
				"band": String(band["label"]),
				"confidence": int(band["confidence"]),
			}
		)
	rows.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left["score"]) != int(right["score"]):
				return int(left["score"]) > int(right["score"])
			return AiAgenda.IDS.find(String(left["id"])) < AiAgenda.IDS.find(String(right["id"]))
	)
	return rows


## The strongest reading worth naming, or {} when nothing reaches Possible.
static func _best_guess(rows: Array[Dictionary]) -> Dictionary:
	for row: Dictionary in rows:
		if int(row["score"]) >= 3:
			return row
	return {}


## Counts the notes read — public behaviour, never an inference.
static func _notes(entries: Array[Dictionary], world: WorldMap, subject: int) -> Dictionary:
	var counts: Dictionary = {}
	for entry: Dictionary in entries:
		var kind: String = String(entry["kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	return {
		"province": _provinces(world, subject),
		"war": int(counts.get("warDeclared", 0)),
		"alliance": int(counts.get("allianceFormed", 0)),
		"broken": int(counts.get("allianceBroken", 0)),
		"refused": int(counts.get("callToArmsRefused", 0)),
		"peace": int(counts.get("peaceMade", 0)),
	}


static func display(id: String) -> String:
	return id.capitalize().replace("_", " ")


static func _pair(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func _provinces(world: WorldMap, faction: int) -> int:
	if world == null:
		return 0
	return DiplomacyRules.provinces_owned(world, faction)


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
