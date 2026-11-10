class_name IntelDossier
extends RefCounted
## The human court's intelligence reading (wiki: ai-dossier, hidden-agendas):
## suspicion per agenda, the confidence band, the strongest guess and the
## behaviour counts the notes read. IntelEvidence turns the chronicle into the
## observations this module scores, so the dossier stays one presentation
## domain (REQ-P3-01).
##
## Nothing here reads an AI's true agenda — the reading is built from public
## acts only, so it can be shown to the player and replayed from a save
## (REQ-P2-01, REQ-P3-03).


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
	var rows: Array[Dictionary] = _agenda_rows(scores, entries)
	return {
		"subject": subject,
		"evidence": entries,
		"agendas": rows,
		"guess": _best_guess(rows),
		"notes": _notes(state, entries, world, viewer, subject),
	}


## Observable acts by the subject, newest first, capped (IntelEvidence owns the
## chronicle read and the masking; the dossier keeps the public name).
static func evidence(
	state: DiplomacyState, world: WorldMap, viewer: int, subject: int
) -> Array[Dictionary]:
	return IntelEvidence.collect(state, world, viewer, subject)


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


## Every agenda, highest suspicion first; ties keep the catalogue order. Each row
## carries the observations that fed it, newest first, so the full dossier can
## show one timeline per agenda (DR-20261110-25).
static func _agenda_rows(
	scores: Dictionary, entries: Array[Dictionary]
) -> Array[Dictionary]:
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
				"timeline": _timeline_for(id, entries),
			}
		)
	rows.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left["score"]) != int(right["score"]):
				return int(left["score"]) > int(right["score"])
			return AiAgenda.IDS.find(String(left["id"])) < AiAgenda.IDS.find(String(right["id"]))
	)
	return rows


## The observations that speak to one agenda, newest first: turn, sentence and
## the points this act added.
static func _timeline_for(id: String, entries: Array[Dictionary]) -> Array[Dictionary]:
	var line: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var weights: Dictionary = entry["weights"] as Dictionary
		if not weights.has(id):
			continue
		line.append(
			{
				"turn": int(entry["turn"]),
				"text": String(entry["text"]),
				"points": int(weights[id]),
			}
		)
	return line


## The strongest reading worth naming, or {} when nothing reaches Possible.
static func _best_guess(rows: Array[Dictionary]) -> Dictionary:
	for row: Dictionary in rows:
		if int(row["score"]) >= 3:
			return row
	return {}


## Counts the notes read — public behaviour, never an inference — plus what a
## spy has watched this court build (DR-20261110-25). Builds are a theme, not
## evidence: they weigh on no agenda.
static func _notes(
	state: DiplomacyState,
	entries: Array[Dictionary],
	world: WorldMap,
	viewer: int,
	subject: int
) -> Dictionary:
	var counts: Dictionary = {}
	for entry: Dictionary in entries:
		var kind: String = String(entry["kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	return {
		"province": IntelEvidence.provinces(world, subject),
		"war": int(counts.get("warDeclared", 0)),
		"alliance": int(counts.get("allianceFormed", 0)),
		"broken": int(counts.get("allianceBroken", 0)),
		"refused": int(counts.get("callToArmsRefused", 0)),
		"peace": int(counts.get("peaceMade", 0)),
		"spy_tech": int(counts.get(IntelEvidence.SPY_TECH, 0)),
		"build": _builds(state, viewer, subject),
	}


## Works a spy watched the subject begin, summed over the kept observations.
static func _builds(state: DiplomacyState, viewer: int, subject: int) -> Dictionary:
	var counted: Dictionary = {}
	if state == null:
		return counted
	for raw: Variant in state.events:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw
		if String(event.get("kind", "")) != IntelEvidence.SPY_BUILD:
			continue
		if int(event.get("a", -1)) != subject or int(event.get("b", -1)) != viewer:
			continue
		var data: Dictionary = event.get("data", {}) as Dictionary
		var works: Dictionary = data.get("works", {}) as Dictionary
		for what: Variant in works.keys():
			var key: String = String(what)
			counted[key] = int(counted.get(key, 0)) + int(works[what])
	return counted


static func display(id: String) -> String:
	return id.capitalize().replace("_", " ")
