class_name ConsentCopy
extends RefCounted
## The blocking consent prompts' words: a call to arms, an intervention or a
## rival's proposal, and the buttons that answer them
## (wiki: dialogue-content-and-yarn § Playable slice).
##
## Every sentence is authored here once, in the source tongue, and read through
## [DialogueLocale] under a stable key, exactly as a court's own line is: a
## tongue file answers a prompt without touching code, and a key no file answers
## keeps the authored English (REQ-P2-05). Nothing on the rules path reads what
## comes back — the words are display only (REQ-P2-03) — and the court banner
## and the map despatch ask this module, so both always print the same thing
## (REQ-P5-05).
##
## The sentences live together rather than beside each rule that queues a
## decision because a prompt is one surface: its caption, its stakes, its terms
## and its answers must read as one voice in every tongue that ships.

const KEY_PREFIX: String = "Prompt"

## Every prompt sentence, in the source tongue. The key is what a tongue file
## answers; the value is what a court that reads no translation prints. A `%s`
## or `%d` is filled by the caller and must survive translation.
const SOURCES: Dictionary = {
	# Who moved, and what it costs us — the line both banners open with.
	"declaration": "%s has declared war on %s. %s",
	# A call to arms (wiki: diplomacy § Alliances § Mutual defence).
	"call/caption": "CALL TO ARMS",
	"call/stake": (
		"Our formal alliance binds us: join the war against %s, or refuse and"
		+ " break the treaty — −50 with %s and −10 with every other Great Power"
		+ " but the aggressor."
	),
	"call/toast": "%s calls on our alliance against %s.",
	# An intervention (wiki: diplomacy § Intervention).
	"intervention/caption": "INTERVENTION",
	"intervention/stake_embassy": (
		"Our embassy stands: intervene, protest, or stand aside and lose the"
		+ " embassy."
	),
	"intervention/stake_deed": (
		"Our deed there is at stake: join the war, protest, or stand aside."
	),
	"intervention/stake_deeds": (
		"Our %d deeds there are at stake: join the war, protest, or stand aside."
	),
	"intervention/stake_both_deed": (
		"Our embassy stands and our deed there is at stake: intervene, protest,"
		+ " or stand aside and lose the embassy."
	),
	"intervention/stake_both_deeds": (
		"Our embassy stands and our %d deeds there are at stake: intervene,"
		+ " protest, or stand aside and lose the embassy."
	),
	# A rival's proposal (wiki: diplomacy § Court proposals).
	"proposal/caption": "PROPOSAL",
	"proposal/alliance": "%s proposes a formal alliance.",
	"proposal/peace": "%s proposes a white peace.",
	"proposal/ftp": "%s proposes a favoured trading pact.",
	"proposal/overture/consulate": "%s proposes the Trade Consulate.",
	"proposal/overture/embassy": "%s proposes the Embassy.",
	"proposal/overture/nap": "%s proposes the Non-Aggression Pact.",
	"proposal/overture/join_empire": "%s proposes the Join Empire.",
	"proposal/overture/none": "%s proposes the No overture.",
	"proposal/terms": "Favoured terms: imports at %d%%, exports at %d%%.",
	"proposal/quote": "“%s”",
	"proposal/answer": "Answer the proposal.",
	# The words on the answers themselves, named for the intent they emit.
	"button/join": "Join the war",
	"button/refuse": "Refuse",
	"button/intervene": "Intervene",
	"button/stand_aside": "Stand aside",
	"button/protest": "Protest",
	"button/accept": "Accept",
	# The envoy's face, worn on the proposal caption
	# (wiki: dialogue-and-mood § Mood machine).
	"mood/considering": "Considering",
	"mood/pleased": "Pleased",
	"mood/gracious": "Gracious",
	"mood/calculating": "Calculating",
	"mood/skeptical": "Skeptical",
	"mood/impatient": "Impatient",
	"mood/irritated": "Irritated",
	"mood/dismissive": "Dismissive",
}


## The key one prompt line answers to, e.g. `Prompt/call/caption`.
static func key(name: String) -> String:
	return "%s/%s" % [KEY_PREFIX, name]


## One prompt line in the reader's tongue, its source standing in when no file
## answers the key. The line is filled **after** the tongue is read, so a
## translation names the courts and the rates with its own word order.
static func say(name: String, args: Array = []) -> String:
	var source: String = String(SOURCES.get(name, ""))
	if source.is_empty():
		return ""
	var line: String = DialogueLocale.translate(key(name), source)
	return line % args if not args.is_empty() else line


## Every prompt line this build authors, keyed as a tongue file answers it, so a
## test can hold each file to the catalogue.
static func catalogue() -> Dictionary:
	var found: Dictionary = {}
	for name: Variant in SOURCES.keys():
		found[key(String(name))] = String(SOURCES[name])
	return found


## Who moved, and the stake the court is weighing for each answer.
static func declaration(aggressor: int, defender: int, stake: String) -> String:
	return say("declaration", [
		FactionCatalog.name_of(aggressor),
		FactionCatalog.name_of(defender),
		stake,
	])


static func call_caption() -> String:
	return say("call/caption")


## What a call to arms asks and what each answer costs: the war it joins and the
## treaty a refusal breaks (wiki: diplomacy § Alliances § Mutual defence,
## § Breaking an alliance).
static func call_stake(call: Dictionary) -> String:
	return say("call/stake", [
		FactionCatalog.name_of(int(call.get("aggressor", -1))),
		FactionCatalog.name_of(int(call.get("defender", -1))),
	])


## The whole call banner body: the declaration, then what it costs us.
static func call_body(call: Dictionary) -> String:
	return declaration(
		int(call.get("aggressor", -1)),
		int(call.get("defender", -1)),
		call_stake(call)
	)


## The despatch the map raises when a call waits on the court: the ally that
## calls, and the crown it asks us to stand beside.
static func call_toast(call: Dictionary) -> String:
	return say("call/toast", [
		FactionCatalog.name_of(int(call.get("defender", -1))),
		FactionCatalog.name_of(int(call.get("aggressor", -1))),
	])


static func intervention_caption() -> String:
	return say("intervention/caption")


## The whole intervention banner body: the declaration, then what is at stake.
static func intervention_body(offer: Dictionary) -> String:
	return declaration(
		int(offer.get("aggressor", -1)),
		int(offer.get("target", -1)),
		intervention_stake(offer)
	)


## What the court risks by answering: the embassy, the deeds it bought there, or
## both — never a stake the offer does not hold (DR-20261110-20).
static func intervention_stake(offer: Dictionary) -> String:
	var basis: String = String(offer.get("basis", "embassy"))
	var deeds: int = int(offer.get("deeds", 0))
	if basis == "deed":
		return (
			say("intervention/stake_deeds", [deeds])
			if deeds > 1
			else say("intervention/stake_deed")
		)
	if basis == "both":
		return (
			say("intervention/stake_both_deeds", [deeds])
			if deeds > 1
			else say("intervention/stake_both_deed")
		)
	if deeds > 1:
		return say("intervention/stake_deeds", [deeds])
	return say("intervention/stake_embassy")


## The proposal caption, with the envoy's face when the offer has spoken.
static func proposal_caption(mood: String) -> String:
	var caption: String = say("proposal/caption")
	if mood.is_empty():
		return caption
	return "%s  ·  %s" % [caption, mood_word(mood).to_upper()]


## What the rival proposes, in one sentence. The stage is named by its own line,
## so no tongue has to bend an article around an English stage label.
static func proposal_body(from_id: int, kind: String, stage: String) -> String:
	return say(_proposal_line(kind, stage), [FactionCatalog.name_of(from_id)])


## The map despatch: the offer, then the ask.
static func proposal_toast(from_id: int, kind: String, stage: String) -> String:
	return "%s %s" % [proposal_body(from_id, kind, stage), say("proposal/answer")]


## The rate a favoured pact publishes, in the words the answering court reads
## (wiki: world-market § FTP; DR-20261110-10).
static func proposal_terms() -> String:
	var margin: float = DiplomacyCatalog.FTP_TERMS
	return say("proposal/terms", [
		roundi((1.0 - margin) * 100.0),
		roundi((1.0 + margin) * 100.0),
	])


## The envoy's own words, set off in the punctuation the tongue uses.
static func proposal_quote(words: String) -> String:
	return say("proposal/quote", [words])


## One answer's word, named for the intent it emits (`join`, `refuse`, …).
static func button(answer: String) -> String:
	var named: String = "button/%s" % answer
	if not SOURCES.has(named):
		return answer.capitalize()
	return say(named)


## The envoy's face, in the reader's tongue; a mood no file names still reads.
static func mood_word(mood: String) -> String:
	var named: String = "mood/%s" % mood
	if not SOURCES.has(named):
		return mood.capitalize()
	return say(named)


## The line one proposal answers to, by kind; an unknown stage still names the
## offer rather than falling silent.
static func _proposal_line(kind: String, stage: String) -> String:
	if kind == DiplomacyProposals.KIND_ALLIANCE:
		return "proposal/alliance"
	if kind == DiplomacyProposals.KIND_PEACE:
		return "proposal/peace"
	if kind == DiplomacyProposals.KIND_FTP:
		return "proposal/ftp"
	var by_stage: String = "proposal/overture/%s" % stage
	if SOURCES.has(by_stage):
		return by_stage
	return "proposal/overture/none"
