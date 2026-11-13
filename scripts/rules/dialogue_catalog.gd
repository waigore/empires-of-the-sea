class_name DialogueCatalog
extends RefCounted
## Authored court lines (wiki: dialogue-content-and-yarn § Design intent).
## Stable content keys `<category>/<situation>`; a line names the speaker and
## the court it answers through `{speaker}` / `{other}` only, so no asset path,
## province id or number ever reaches the text (REQ-P1-02, REQ-P2-03).
## Two or three variants per point keep a long campaign from repeating itself;
## the pick is a salted hash, never randomness (see [DialogueEvents]).
##
## This table authors what a court says to another court — diplomacy, the wait
## for an answer, its standing remark. What the world does to the reader (a
## verdict, a study, a hostile host at the seat, a Tribe taken under the flag)
## is authored in [DialogueEpisodes], and the veiled word a rival lets slip
## about its own hidden motive in [DialogueAgendaLines]; the tables read as one
## catalogue here, so every caller asks this class and no screen invents a point
## of its own.

const CAT_DIPLOMATIC: String = "diplomatic"
const CAT_EVENT: String = "event"
const CAT_NEGOTIATION: String = "negotiation"
const CAT_REACTIVE: String = "reactive"
const CAT_AGENDA: String = "agenda"

const POINTS: Dictionary = {
	# --- diplomatic: what a court says once an act is done -------------------
	"diplomatic/war_declared_by_them": {
		"category": CAT_DIPLOMATIC,
		"moods": ["irritated", "dismissive"],
		"lines": [
			"You have had our patience. Now you shall have our broadsides.",
			"Our guns are laid, our letters are finished, and our patience is spent.",
			"Let the sea judge between our crowns, since the court could not.",
		],
	},
	"diplomatic/war_declared_by_you": {
		"category": CAT_DIPLOMATIC,
		"moods": ["irritated", "calculating"],
		"lines": [
			"So be it. Every sail you take shall be answered for at the peace.",
			"You strike first. We shall be the last to strike.",
			"Our harbours are shut to your flag, and our cruisers are not idle.",
		],
	},
	"diplomatic/peace_made": {
		"category": CAT_DIPLOMATIC,
		"moods": ["considering", "pleased"],
		"lines": [
			"Enough blood has gone to the fishes. The war is done.",
			"The treaty is signed. Let no captain test the ink.",
			"We shall have peace, and watch you the closer for it.",
		],
	},
	"diplomatic/alliance_formed": {
		"category": CAT_DIPLOMATIC,
		"moods": ["pleased", "gracious"],
		"lines": [
			"Your enemies are ours now, and ours are yours.",
			"Let the treaty be read aloud in both our harbours.",
			"We stand with you, so long as the terms stand.",
		],
	},
	"diplomatic/alliance_broken_by_them": {
		"category": CAT_DIPLOMATIC,
		"moods": ["dismissive", "calculating"],
		"lines": [
			"The treaty served its season. It serves no longer.",
			"We renounce the alliance; our ships sail where we bid them.",
			"Do not look for our squadrons. You will not find them beside you.",
		],
	},
	"diplomatic/alliance_broken_by_you": {
		"category": CAT_DIPLOMATIC,
		"moods": ["irritated", "dismissive"],
		"lines": [
			"You break your word before witnesses. We shall remember it.",
			"Our clerks have written your name beside this day.",
			"So a crown keeps faith. Good to know before the next treaty.",
		],
	},
	"diplomatic/overture_granted": {
		"category": CAT_DIPLOMATIC,
		"moods": ["gracious", "pleased"],
		"lines": [
			"Our envoy shall keep your court, and your merchants our ports.",
			"It is agreed. Let the papers be sealed and the wine poured.",
			"We receive your envoy kindly, and expect the courtesy returned.",
		],
	},
	"diplomatic/overture_accepted": {
		"category": CAT_DIPLOMATIC,
		"moods": ["pleased", "considering"],
		"lines": [
			"Your envoy is welcome. Our clerks will find him a chair.",
			"We accept. Let it be entered in the book of treaties.",
			"A small step, and a useful one. Come, let us sign.",
		],
	},
	"diplomatic/overture_refused": {
		"category": CAT_DIPLOMATIC,
		"moods": ["skeptical", "dismissive"],
		"lines": [
			"The terms do not suit us. Keep your envoy at home.",
			"A consul from your court would find little to do here.",
			"No. We need nothing from you badly enough to grant this.",
		],
	},
	"diplomatic/overture_withdrawn": {
		"category": CAT_DIPLOMATIC,
		"moods": ["impatient", "skeptical"],
		"lines": [
			"Very well. We shall not ask twice.",
			"Your refusal is entered in the ledger, and not in your favour.",
			"Then we keep our envoy, and our money, at home.",
		],
	},
	"diplomatic/call_to_arms_joined": {
		"category": CAT_DIPLOMATIC,
		"moods": ["pleased", "gracious"],
		"lines": [
			"Our regiments are yours in this quarrel.",
			"The treaty speaks plainly, and so do we. We march.",
			"Consider the aggressor answered.",
		],
	},
	"diplomatic/call_to_arms_refused": {
		"category": CAT_DIPLOMATIC,
		"moods": ["skeptical", "calculating"],
		"lines": [
			"The treaty did not bind us to this ruin. Our regiments stay home.",
			"We have weighed this war. You will fight it without us.",
			"Do not mistake our refusal for friendship to the other side.",
		],
	},
	"diplomatic/intervention_joined": {
		"category": CAT_DIPLOMATIC,
		"moods": ["pleased", "gracious"],
		"lines": [
			"We will not stand by while a crown is carved up.",
			"Our squadrons sail. The aggressor had better mind its charts.",
			"The embassy stood for this. We answer it now.",
		],
	},
	"diplomatic/intervention_stood_aside": {
		"category": CAT_DIPLOMATIC,
		"moods": ["dismissive", "calculating"],
		"lines": [
			"Our embassy is closed. What follows is not our affair.",
			"We have taken the papers home. The war is yours.",
			"We choose our quarrels. This is not one of them.",
		],
	},
	"diplomatic/intervention_protested": {
		"category": CAT_DIPLOMATIC,
		"moods": ["irritated", "dismissive"],
		"lines": [
			"This war is an outrage, and our court says so plainly.",
			"We protest this aggression in every court that will hear us.",
			"There will be a reckoning for this, though not today with guns.",
		],
	},
	"diplomatic/proposal_accepted": {
		"category": CAT_DIPLOMATIC,
		"moods": ["pleased", "gracious"],
		"lines": [
			"It is agreed. Our clerks will draw it up before the day is out.",
			"You have dealt with us fairly. We shall remember it.",
			"Then let it be finished, and let both fleets know it.",
		],
	},
	"diplomatic/proposal_refused": {
		"category": CAT_DIPLOMATIC,
		"moods": ["dismissive", "irritated"],
		"lines": [
			"Very well. The offer is withdrawn.",
			"We had expected better of your court. So be it.",
			"The offer dies here. Do not come asking after it.",
		],
	},
	"diplomatic/first_contact": {
		"category": CAT_DIPLOMATIC,
		"moods": ["skeptical", "calculating"],
		"lines": [
			"We had heard of your crown. Now we shall learn what it is worth.",
			"Send word who you are, that our clerks may enter it properly.",
			"A new flag in these waters. {other}, is it? We shall watch where it sails.",
		],
	},
	# --- negotiation: what a court says while it waits for an answer ---------
	"negotiation/proposal_alliance": {
		"category": CAT_NEGOTIATION,
		"moods": ["considering", "calculating"],
		"lines": [
			"An alliance, then. Two crowns hold a sea better than one.",
			"Our courts are close enough in mind. Shall we put it in ink?",
			"Sign with us, and neither of us faces the next war alone.",
		],
	},
	"negotiation/proposal_overture": {
		"category": CAT_NEGOTIATION,
		"moods": ["considering", "calculating"],
		"lines": [
			"A consul at your court and your merchants at our quay. Shall we?",
			"We propose an arrangement of mutual use. The papers are ready.",
			"Small treaties keep the peace. Come, agree to one.",
		],
	},
	"negotiation/proposal_peace": {
		"category": CAT_NEGOTIATION,
		"moods": ["considering", "calculating"],
		"lines": [
			"Let the guns fall silent. We offer a white peace.",
			"We have both lost enough ships to this war. Shall we stop?",
			"Our terms are a white peace, no more and no less. Answer it.",
		],
	},
	# A pact and a non-aggression offer are treaties of their own: the envoy
	# names the one on the table, never a consul it is not offering.
	"negotiation/proposal_ftp": {
		"category": CAT_NEGOTIATION,
		"moods": ["considering", "calculating"],
		"lines": [
			"Let our merchants be favoured partners, and our ports will know it.",
			"A trading pact between our crowns: your lots clear first at our quay.",
			"Put your name to a favoured pact, and we shall both sell at better rates.",
		],
	},
	"negotiation/proposal_nap": {
		"category": CAT_NEGOTIATION,
		"moods": ["considering", "calculating"],
		"lines": [
			"The pact of non-aggression, then. Our clerks have the draft ready.",
			"One more step between our crowns. Put your seal to the pact.",
			"We are near enough to sign it. Let the non-aggression pact stand.",
		],
	},
	# --- reactive: the court's standing word when nothing has happened --------
	# The five bands are authored in [DialogueYarn], a Yarn script keyed by the
	# same `DialoguePoint/<category>/<situation>` point; the merged catalogue
	# below reads them beside these rows.
}


## Full content key, e.g. `DialoguePoint/diplomatic/peace_made`.
static func key(point: String) -> String:
	return "DialoguePoint/%s" % point


## This table joined with the episode beats, built once: callers never have to
## know which module authored a point.
static var _merged: Dictionary = {}


static func table() -> Dictionary:
	if _merged.is_empty():
		_merged = POINTS.duplicate(true)
		_merged.merge(DialogueEpisodes.POINTS, true)
		_merged.merge(DialogueAgendaLines.POINTS, true)
		_merged.merge(DialogueYarn.table(), true)
	return _merged


static func points() -> Array[String]:
	var found: Array[String] = []
	for point: String in table().keys():
		found.append(point)
	found.sort()
	return found


static func has_point(point: String) -> bool:
	return table().has(point)


static func category_for(point: String) -> String:
	return String(_entry(point).get("category", ""))


static func lines_for(point: String) -> Array:
	var raw: Variant = _entry(point).get("lines", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


static func moods_for(point: String) -> Array:
	var raw: Variant = _entry(point).get("moods", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


## One authored line, chosen by the caller's stable salt so a reload speaks the
## same words, in the locale the game runs (DialogueLocale keys every variant).
## Unknown points speak nothing.
static func line_for(point: String, salt: int) -> String:
	var lines: Array = lines_for(point)
	if lines.is_empty():
		return ""
	var index: int = absi(salt) % lines.size()
	return DialogueLocale.line(point, index, String(lines[index]))


## The mood a point carries when the caller has no negotiation state to read.
static func mood_for(point: String, salt: int) -> String:
	var moods: Array = moods_for(point)
	if moods.is_empty():
		return DialogueMood.OPEN_MOOD
	return String(moods[absi(salt) % moods.size()])


## Fill the two permitted placeholders. Names are handed in already masked, so
## the catalogue never looks a faction up (REQ-P2-03).
static func render(template: String, speaker_name: String, other_name: String) -> String:
	return template.replace("{speaker}", speaker_name).replace("{other}", other_name)


static func _entry(point: String) -> Dictionary:
	var raw: Variant = table().get(point, {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}
