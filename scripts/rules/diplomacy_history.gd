class_name DiplomacyHistory
extends RefCounted
## The court chronicle (wiki: diplomacy § Diplomatic History). Pure RefCounted
## data: one crown's view of the log, filtered to the selected court and newest
## first, with parties that crown has not met masked as "Unknown faction". The
## relation score stays sealed, so a line names an outcome and never a number
## (REQ-P2-01, REQ-P3-03).

const UNKNOWN_NAME: String = "Unknown faction"

## Kinds the chronicle narrates. Everything else stays in
## `DiplomacyState.events` for rules and AI bookkeeping but never reaches the
## panel, so a prompt (an offered call to arms, a queued proposal) is not
## mistaken for a resolution.
const NARRATED: Array[String] = [
	"warDeclared",
	"overturesCleared",
	"peaceMade",
	"allianceFormed",
	"allianceBroken",
	"callToArmsAccepted",
	"callToArmsRefused",
	"interventionIntervened",
	"interventionDoNothing",
	"interventionProtest",
	"proposalAccepted",
	"proposalRefused",
	"overtureEstablished",
	"overtureRejected",
	"joinEmpire",
	"colonyFormed",
	"colonyReleased",
	"subsidySet",
	"subsidyCancelled",
	"grantAid",
	"firstContact",
]


## Chronicle lines for the pair (viewer, other), newest first. Ordering is turn
## then resolution order, so a loaded save replays the same page.
static func entries(
	state: DiplomacyState, viewer: int, other: int
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if state == null or viewer == other:
		return found
	for index in state.events.size():
		var event: Dictionary = state.events[index]
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var involved: Array[int] = parties(event)
		if not involved.has(viewer) or not involved.has(other):
			continue
		var text: String = describe(state, event, viewer)
		if text.is_empty():
			continue
		var turn: int = int(event.get("turn", 0))
		found.append(
			{
				"turn": turn,
				"kind": String(event.get("kind", "")),
				"text": text,
				"index": index,
			}
		)
	found.sort_custom(_newest_first)
	return found


## Every faction an event involves: the recorded pair plus any named actor
## (aggressor, protest target, colony suzerain).
static func parties(event: Dictionary) -> Array[int]:
	var ids: Array[int] = [int(event.get("a", -1)), int(event.get("b", -1))]
	var raw: Variant = event.get("data", {})
	if typeof(raw) == TYPE_DICTIONARY:
		var data: Dictionary = raw
		for key: String in ["aggressor", "target", "court"]:
			if data.has(key):
				ids.append(int(data[key]))
	return ids


## One player-facing sentence for an event, or "" when it is not narrated.
## Party names are masked against the viewing crown's contacts.
static func describe(state: DiplomacyState, event: Dictionary, viewer: int) -> String:
	var kind: String = String(event.get("kind", ""))
	if not NARRATED.has(kind):
		return ""
	var raw: Variant = event.get("data", {})
	var data: Dictionary = {}
	if typeof(raw) == TYPE_DICTIONARY:
		data = raw
	var kind_data: String = String(data.get("kind", ""))
	var stage: String = String(data.get("stage", ""))
	var a: String = name_for(state, viewer, int(event.get("a", -1)))
	var b: String = name_for(state, viewer, int(event.get("b", -1)))
	var aggressor: String = name_for(state, viewer, int(data.get("aggressor", -1)))
	var target: String = name_for(state, viewer, int(data.get("target", -1)))
	match kind:
		"warDeclared":
			return "%s declared war on %s." % [a, b]
		"overturesCleared":
			return "The war ended the overtures between %s and %s." % [a, b]
		"peaceMade":
			return "%s and %s concluded a white peace." % [a, b]
		"allianceFormed":
			return "%s and %s signed a formal alliance." % [a, b]
		"allianceBroken":
			return "%s broke its formal alliance with %s." % [a, b]
		"callToArmsAccepted":
			return "%s joined %s's war against %s." % [a, b, aggressor]
		"callToArmsRefused":
			return "%s refused %s's call to arms against %s." % [a, b, aggressor]
		"interventionIntervened":
			return "%s intervened against %s on behalf of %s." % [a, aggressor, b]
		"interventionDoNothing":
			return "%s stood aside while %s made war on %s." % [a, aggressor, b]
		"interventionProtest":
			return "%s protested %s's war on %s." % [a, b, target]
		"proposalAccepted":
			return "%s accepted %s's offer of %s." % [
				b, a, DiplomacyProposals.describe(kind_data, stage)
			]
		"proposalRefused":
			return "%s refused %s's offer of %s." % [
				b, a, DiplomacyProposals.describe(kind_data, stage)
			]
		"overtureEstablished":
			return "%s established the %s with %s." % [
				a, DiplomacyCatalog.stage_label(stage), b
			]
		"overtureRejected":
			return "%s's offer of the %s was refused by %s." % [
				a, DiplomacyCatalog.stage_label(stage), b
			]
		"joinEmpire":
			return "%s was absorbed into the %s empire." % [b, a]
		"colonyFormed":
			return "%s made %s a colony." % [a, b]
		"colonyReleased":
			return "%s was released from the %s colony." % [a, b]
		"subsidySet":
			return "%s set a %d%% subsidy to %s." % [a, int(data.get("percent", 0)), b]
		"subsidyCancelled":
			return "%s's subsidy to %s was cancelled." % [a, b]
		"grantAid":
			return "%s sent %s in aid to %s." % [a, DiplomacyCatalog.money(int(data.get("amount", 0))), b]
		"firstContact":
			return "%s made first contact with %s." % [a, b]
	return ""


## The crown's name in this chronicle: itself always, a faction it holds a
## relation with by name, and every stranger masked (wiki: diplomacy
## § Diplomatic History — visibility and "unknown faction").
static func name_for(state: DiplomacyState, viewer: int, faction: int) -> String:
	if faction < 0:
		return UNKNOWN_NAME
	if faction == viewer:
		return FactionCatalog.name_of(faction)
	if state != null and state.has_relation(viewer, faction):
		return FactionCatalog.name_of(faction)
	return UNKNOWN_NAME


## Calendar stamp used by the court panel, e.g. "Year 1505 (Turn 12)".
static func stamp_for_turn(turn: int) -> String:
	return "Year %d (Turn %d)" % [TurnTime.year_for_turn(turn), turn]


static func _newest_first(left: Dictionary, right: Dictionary) -> bool:
	if int(left["turn"]) != int(right["turn"]):
		return int(left["turn"]) > int(right["turn"])
	return int(left["index"]) > int(right["index"])
