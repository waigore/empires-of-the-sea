class_name DialogueAgenda
extends RefCounted
## A rival court's veiled word about its own hidden motive (wiki:
## dialogue-and-mood § Seeding / cadence — the `agenda` comment about once every
## seven turns; hidden-agendas § Playable slice — "discoverable only via
## evidence → dossier suspicion—never by reading the true value";
## DR-20261111-19).
##
## Rules-only and presentation-only at once: the beat is recorded in the pair's
## log like any other answer, so the court panel speaks the same words after a
## reload, and no rule reads one back (REQ-P2-03, REQ-P2-04, REQ-P3-03). The
## court never names its agenda, and it keeps its counsel until the reader's own
## dossier already reads that motive as "Likely" — evidence leads, flavour
## follows.

## Chronicle kind of one spoken agenda beat. Not narrated by the pair's
## chronicle: it is the court's word, not an act between the crowns.
const SPOKE: String = "agendaSpoke"
## One word in seven turns for each court (wiki: dialogue-and-mood § Seeding /
## cadence).
const CADENCE: int = 7
## Suspicion at which the dossier already reads the court's motive as "Likely"
## (IntelDossier.band_for). Below it the court says nothing of its own design.
const SUSPICION_FLOOR: int = 6


static func knows(kind: String) -> bool:
	return kind == SPOKE


## Content key of one agenda's veiled line, e.g. `agenda/warmonger`.
static func point_for(agenda_id: String) -> String:
	return "agenda/%s" % agenda_id


## This court's own dialogue seed, from the AI seed hierarchy: the game seed and
## the court, nothing else, so the same campaign speaks on the same turns.
static func seed_for(game_seed: int, faction: int) -> int:
	return absi(("%d:dialogue:%d" % [game_seed, faction]).hash())


## True on the turn this court is due to speak. The turn is added to the seed so
## every court speaks once in [constant CADENCE] turns; the seed alone is fixed
## for the whole campaign, so the page's bare `dialogueSeed % 7 == 0` would
## either speak every turn or never (DR-20261111-19).
static func due(game_seed: int, faction: int, turn: int) -> bool:
	if turn < 1:
		return false
	return posmod(turn + seed_for(game_seed, faction), CADENCE) == 0


## The turn a recorded beat belongs to: its own act turn, carried in the beat's
## data because the diplomacy clock is not stepped by every phase. Falls back to
## the log's stamp for a malformed record.
static func turn_of(event: Dictionary) -> int:
	var raw: Variant = event.get("data", {})
	if typeof(raw) == TYPE_DICTIONARY and (raw as Dictionary).has("turn"):
		return int((raw as Dictionary)["turn"])
	return int(event.get("turn", 0))


## Which point a recorded agenda beat speaks, and who speaks it. Only the court
## that recorded the beat reads it, and the speaker is always the other court:
## a rival does not confide in itself. An unknown agenda id speaks nothing.
static func plan(event: Dictionary, viewer: int, other: int) -> Dictionary:
	if String(event.get("kind", "")) != SPOKE:
		return {}
	if int(event.get("a", -1)) != viewer:
		return {}
	var agenda_id: String = _agenda_of(event)
	if not AiAgenda.has(agenda_id):
		return {}
	return {"point": point_for(agenda_id), "speaker": other}


## Records this turn's beat for one rival when the court is due, the crown knows
## it, and the crown's dossier already suspects its motive. Returns true when a
## beat was recorded.
static func record(
	state: DiplomacyState,
	world: WorldMap,
	viewer: int,
	other: int,
	game_seed: int,
	turn: int
) -> bool:
	if state == null or viewer == other or other < 0:
		return false
	if not state.has_relation(viewer, other):
		return false
	if not due(game_seed, other, turn):
		return false
	var agenda_id: String = AiAgenda.assign(game_seed, other)
	if not _suspected(state, world, viewer, other, agenda_id):
		return false
	state.record_event(SPOKE, viewer, other, {"agenda": agenda_id, "turn": turn})
	return true


## The reader's own reading of the court — its dossier, never the true value —
## must already carry [constant SUSPICION_FLOOR] against the motive, so a line
## cannot hand out intelligence the evidence has not earned.
static func _suspected(
	state: DiplomacyState, world: WorldMap, viewer: int, other: int, agenda_id: String
) -> bool:
	var entries: Array[Dictionary] = IntelEvidence.collect(state, world, viewer, other)
	return int(IntelDossier.suspicion(entries).get(agenda_id, 0)) >= SUSPICION_FLOOR


static func _agenda_of(event: Dictionary) -> String:
	var raw: Variant = event.get("data", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	return String((raw as Dictionary).get("agenda", ""))
