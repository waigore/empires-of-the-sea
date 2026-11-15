class_name GazetteDiplomacy
extends RefCounted
## Diplomacy news for one turn's Gazette (wiki: the-gazette § Item catalog).
## It sorts the resolved turn's recorded acts into the three classes — Our
## court, World, Courts of interest — and hands each item's structured record to
## [Gazette], which prints it. It decides no outcome of its own: every act was
## recorded by the diplomacy rules (REQ-P2-03).

## Kinds that reach the World page when the crown is not a party. A war or a
## peace is world news only between two Great Powers; a Great Power's dealings
## with a Minor Nation or a Tribe are that court's doings, not the epoch's
## (wiki: the-gazette § Item catalog — World).
const WORLD_KINDS: Array[String] = [
	"warDeclared", "peaceMade", "joinEmpire", "colonyFormed", "firstContact",
]
## The acts a proposal answer speaks for. A rival's offer is answered by the
## treaty it asked for, and the treaty records its own event, so the sheet
## prints the act once (wiki: the-gazette § Item catalog — the catalogue lists
## the acts, not the offers that led to them).
const PROPOSAL_ACTS: Dictionary = {
	"overture": ["overtureEstablished", "overtureRejected"],
	"ftp": ["ftpSigned", "ftpRefused"],
	"alliance": ["allianceFormed"],
	"peace": ["peaceMade"],
}
## The proposal answers that may double an act already on the sheet.
const PROPOSAL_KINDS: Array[String] = ["proposalAccepted", "proposalRefused"]
## Kinds a court's page narrates, for the crown and for a watched court alike.
const COURT_KINDS: Array[String] = [
	"warDeclared",
	"peaceMade",
	"allianceFormed",
	"allianceBroken",
	"joinEmpire",
	"colonyFormed",
	"colonyReleased",
	"overtureEstablished",
	"overtureRejected",
	"callToArmsAccepted",
	"callToArmsRefused",
	"interventionIntervened",
	"interventionDoNothing",
	"interventionProtest",
	"proposalAccepted",
	"proposalRefused",
	"subsidySet",
	"subsidyCancelled",
	"ftpSigned",
	"ftpRefused",
	"ftpRevoked",
	"boycottSet",
	"boycottRevoked",
	"grantAid",
	"firstContact",
]


## This turn's acts, sorted: `{world, court, interest}`, each an Array of
## `{kind, rec}` in resolution order. Classification is exclusive and ordered —
## the crown's own acts first, then public epoch facts, then a watched court's
## doings (wiki: the-gazette § Classes).
static func classify(
	viewer: int, turn: int, state: DiplomacyState, watched: Array[int]
) -> Dictionary:
	var out: Dictionary = {"world": [], "court": [], "interest": []}
	if state == null:
		return out
	var acts: Dictionary = _acts(state, turn)
	for event: Dictionary in state.events:
		if int(event.get("turn", -1)) != turn:
			continue
		var kind: String = String(event.get("kind", ""))
		if not COURT_KINDS.has(kind):
			continue
		if _answered(event, acts):
			continue
		var parties: Array[int] = DiplomacyHistory.parties(event)
		var rec: Dictionary = record(kind, event, state, viewer)
		if rec.is_empty():
			continue
		if parties.has(viewer):
			out["court"].append({"kind": kind, "rec": rec})
			continue
		# A court the crown has not met cannot be named, and a masked line is no
		# news: the sheet stays silent about a stranger's affairs.
		if not named(parties, state, viewer):
			continue
		if WORLD_KINDS.has(kind) and world_scale(kind, event):
			rec["self_act"] = false
			out["world"].append({"kind": kind, "rec": rec})
		elif any_watched(parties, watched, viewer):
			rec["self_act"] = false
			out["interest"].append({"kind": kind, "rec": rec})
	return out


## True when this turn's World page may carry the act: a war or a peace is the
## epoch's news only between two Great Powers (wiki: the-gazette § Item catalog —
## World). An absorption, a colony or a first contact is public by its kind.
static func world_scale(kind: String, event: Dictionary) -> bool:
	if kind != "warDeclared" and kind != "peaceMade":
		return true
	for key: String in ["a", "b"]:
		if not FactionCatalog.can_win(int(event.get(key, -1))):
			return false
	return true


## Every act this turn recorded, by pair: the treaties, battles and pledges a
## proposal answer may only restate.
static func _acts(state: DiplomacyState, turn: int) -> Dictionary:
	var seen: Dictionary = {}
	for event: Dictionary in state.events:
		if int(event.get("turn", -1)) != turn:
			continue
		var kind: String = String(event.get("kind", ""))
		if not COURT_KINDS.has(kind) or PROPOSAL_KINDS.has(kind):
			continue
		var key: String = _pair(event)
		if not seen.has(key):
			seen[key] = []
		(seen[key] as Array).append(kind)
	return seen


## True when the proposal answer only restates an act the sheet already prints
## this turn for the same pair — a refused overture is one act, not two lines.
static func _answered(event: Dictionary, acts: Dictionary) -> bool:
	var kind: String = String(event.get("kind", ""))
	if not PROPOSAL_KINDS.has(kind):
		return false
	var raw: Variant = event.get("data", {})
	var data: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var asked: String = String(data.get("kind", ""))
	if not PROPOSAL_ACTS.has(asked):
		return false
	var recorded: Array = acts.get(_pair(event), [])
	for act: String in PROPOSAL_ACTS[asked] as Array:
		if recorded.has(act):
			return true
	return false


static func _pair(event: Dictionary) -> String:
	var a: int = int(event.get("a", -1))
	var b: int = int(event.get("b", -1))
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## A turn's fallen crowns, as World items: only a Great Power is struck from the
## roll of powers, and only a court the crown can name. A fall clears the fallen
## court's relations with the world, so the record carries the knowledge the
## crown held when the court fell (wiki: the-gazette § Item catalog — World,
## "Great Power terminal fall").
static func falls(viewer: int, state: DiplomacyState, raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var fallen: Dictionary = entry
		var faction: int = int(fallen.get("faction", -1))
		# A Minor or a Tribe going down is map cleanup, not a struck name.
		if faction < 0 or faction == viewer or not FactionCatalog.can_win(faction):
			continue
		if not met(state, viewer, faction) and not bool(fallen.get("known", false)):
			continue
		out.append(
			{
				"kind": "greatPowerFell",
				"rec": {
					"who": _fallen_name(state, viewer, faction),
					"whom": name_for(state, viewer, int(fallen.get("conqueror", -1))),
				},
			}
		)
	return out


## True when the viewing crown has met the court (it always knows itself).
static func met(state: DiplomacyState, viewer: int, faction: int) -> bool:
	if faction == viewer:
		return true
	if faction < 0 or state == null:
		return false
	return state.has_relation(viewer, faction)


## The fallen court's name: the chronicle's masking while the relation stands,
## the roster's own name once the fall has cleared it — a court the crown had met
## is no stranger to the sheet.
static func _fallen_name(state: DiplomacyState, viewer: int, faction: int) -> String:
	var named: String = name_for(state, viewer, faction)
	if named != DiplomacyHistory.UNKNOWN_NAME:
		return named
	return FactionCatalog.name_of(faction)


## One structured record for [GazetteCopy]. `self_act` keeps the crown speaking
## for itself; every other court is named through the chronicle's masking.
static func record(
	kind: String, event: Dictionary, state: DiplomacyState, viewer: int
) -> Dictionary:
	var raw: Variant = event.get("data", {})
	var data: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var a: int = int(event.get("a", -1))
	var b: int = int(event.get("b", -1))
	var rec: Dictionary = {
		"kind": kind,
		"who": name_for(state, viewer, a),
		"whom": name_for(state, viewer, b),
		"self_act": a == viewer,
	}
	match kind:
		"grantAid":
			rec["amount"] = int(data.get("amount", 0))
		"subsidySet":
			rec["percent"] = int(data.get("percent", 0))
		"ftpRevoked", "boycottRevoked":
			rec["cause"] = String(data.get("cause", ""))
		"callToArmsAccepted", "callToArmsRefused":
			rec["aggressor"] = name_for(state, viewer, int(data.get("aggressor", -1)))
		"interventionProtest":
			# `b` is the aggressor the protest names; the target rides in the data.
			rec["aggressor"] = String(rec["whom"])
			rec["target"] = name_for(state, viewer, int(data.get("target", b)))
		"interventionIntervened", "interventionDoNothing":
			rec["aggressor"] = name_for(state, viewer, int(data.get("aggressor", -1)))
			rec["target"] = String(rec["whom"])
		"proposalAccepted", "proposalRefused":
			rec["label"] = DiplomacyProposals.describe(
				String(data.get("kind", "")), String(data.get("stage", ""))
			)
		"overtureEstablished", "overtureRejected":
			rec["label"] = DiplomacyCatalog.stage_label(String(data.get("stage", "")))
	if String(rec["who"]).is_empty() or String(rec["whom"]).is_empty():
		return {}
	return rec


## A court named only if the viewing crown has met it; the crown speaks of
## itself in the first person (wiki: the-gazette § PlayerView and masking).
static func name_for(state: DiplomacyState, viewer: int, faction: int) -> String:
	if faction == viewer:
		return GazetteCopy.CROWN
	return DiplomacyHistory.name_for(state, viewer, faction)


static func named(parties: Array, state: DiplomacyState, viewer: int) -> bool:
	for raw: Variant in parties:
		var faction: int = int(raw)
		if faction == viewer:
			continue
		if faction < 0 or state == null or not state.has_relation(viewer, faction):
			return false
	return true


static func any_watched(parties: Array, watched: Array[int], viewer: int) -> bool:
	for raw: Variant in parties:
		var faction: int = int(raw)
		if faction != viewer and watched.has(faction):
			return true
	return false
