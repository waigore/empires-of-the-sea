class_name DialogueAgendaLines
extends RefCounted
## A rival court's veiled word about its own hidden motive (wiki:
## dialogue-and-mood § Seeding / cadence — the optional `agenda` comment;
## hidden-agendas § Playable slice; DR-20261111-19).
##
## Content only, keyed `<category>/<agenda id>` exactly like every other point,
## so [DialogueCatalog] reads this table as its own. A line names the reader and
## the speaker through `{speaker}` / `{other}` and never names its own agenda:
## the crown overhears a hint, not a confession, and only once its dossier
## already suspects the motive, so no line can hand the player an answer the
## evidence has not earned (REQ-P2-01, REQ-P2-03).

const CAT_AGENDA: String = "agenda"

const POINTS: Dictionary = {
	# --- warmonger: a taste for the weaker neighbour ------------------------
	"agenda/warmonger": {
		"category": CAT_AGENDA,
		"moods": ["irritated", "calculating"],
		"lines": [
			"There is a crown in these waters with a thin wall and a fat treasury. We are patient, not idle.",
			"Our regiments drill while your merchants count. One of those numbers will matter more.",
			"A neighbour's weakness is a standing invitation. We have never been good at refusing one.",
		],
	},
	# --- isolationist: the harbour shut, the court inward -------------------
	"agenda/isolationist": {
		"category": CAT_AGENDA,
		"moods": ["dismissive", "skeptical"],
		"lines": [
			"We shall not be dragged through your quarrels. Our own fields interest us more than your treaties.",
			"An alliance is a rope with two ends, and we prefer our hands free.",
			"Your envoy will find our harbour open and our court busy with its own accounts.",
		],
	},
	# --- backstabber: the friend who keeps the knife ------------------------
	"agenda/backstabber": {
		"category": CAT_AGENDA,
		"moods": ["calculating", "pleased"],
		"lines": [
			"Keep our friendship close. It has served us both, and it shall serve one of us again.",
			"There is no quarrel between us — yet. Consider how rare that is in these waters.",
			"Do not mistake a warm letter for a warm intention. We write to several courts.",
		],
	},
	# --- tech_thief: other men's studies, read cheaply ----------------------
	"agenda/tech_thief": {
		"category": CAT_AGENDA,
		"moods": ["calculating", "skeptical"],
		"lines": [
			"Your colleges publish; ours listen. It is cheaper than teaching our own scholars.",
			"A study kept secret is worth less than one our agents can read. You should consider that.",
			"Our gentlemen of letters are patient men. They read the papers your court leaves out.",
		],
	},
	# --- peacemaker: the war that should have ended sooner ------------------
	"agenda/peacemaker": {
		"category": CAT_AGENDA,
		"moods": ["gracious", "considering"],
		"lines": [
			"Every war ends. We would rather it ended before the terms cost us both a province.",
			"Our squadrons sail to see a fight stopped, not to start one.",
			"When the next crown is carved up, we intend to be the hand on the knife's wrist.",
		],
	},
	# --- envy: whatever the other court has, matched and bettered -----------
	"agenda/envy": {
		"category": CAT_AGENDA,
		"moods": ["calculating", "impatient"],
		"lines": [
			"Your new buildings are fine work. Ours shall be finer, and sooner than you think.",
			"We watch your ledgers the way a rival merchant watches a loaded cart.",
			"Whatever you raise, we shall raise beside it. That is simply how it must be.",
		],
	},
}
