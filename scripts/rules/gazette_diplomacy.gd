class_name GazetteDiplomacy
extends RefCounted
## Diplomacy news for one turn's Gazette (wiki: the-gazette § Item catalog).
## It sorts the resolved turn's recorded acts into the three classes — Our
## court, World, Courts of interest — and hands each item's structured record to
## [Gazette], which prints it. It decides no outcome of its own: every act was
## recorded by the diplomacy rules (REQ-P2-03).

## Kinds that reach the World page when the crown is not a party.
const WORLD_KINDS: Array[String] = [
	"warDeclared", "peaceMade", "joinEmpire", "colonyFormed", "firstContact",
]
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
	for event: Dictionary in state.events:
		if int(event.get("turn", -1)) != turn:
			continue
		var kind: String = String(event.get("kind", ""))
		if not COURT_KINDS.has(kind):
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
		if WORLD_KINDS.has(kind):
			rec["self_act"] = false
			out["world"].append({"kind": kind, "rec": rec})
		elif any_watched(parties, watched, viewer):
			rec["self_act"] = false
			out["interest"].append({"kind": kind, "rec": rec})
	return out


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
