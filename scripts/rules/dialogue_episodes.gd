class_name DialogueEpisodes
extends RefCounted
## The court's word once the world has answered (wiki: dialogue-and-mood
## § Design intent — `event` beats; DR-20261111-01, DR-20261111-08).
##
## Content only, keyed the same `<category>/<situation>` way as
## [DialogueCatalog], which reads this table as its own: a verdict on the field,
## and the three home-front beats a crown's own turn raises — a study finished,
## a hostile host at the seat, a Tribe taken under the flag. Lines name the
## speaker and the court it answers through `{speaker}` / `{other}` only, so no
## asset path, province id or number ever reaches the text (REQ-P1-02,
## REQ-P2-03).

const CAT_EVENT: String = "event"

const POINTS: Dictionary = {
	# --- the field, the siege and the water --------------------------------
	# The speaker is the court that reads the verdict; a siege splits by the
	# part the speaker played, because a wall kept and a wall carried are not
	# the same boast (DR-20261111-01).
	"event/field_won": {
		"category": CAT_EVENT,
		"moods": ["pleased", "gracious"],
		"lines": [
			"Our line broke theirs in the open. The prisoners are already counting themselves.",
			"You brought your regiments into the open, and the open kept ours.",
			"The field is ours. We shall bury theirs and thank the ground for it.",
		],
	},
	"event/field_lost": {
		"category": CAT_EVENT,
		"moods": ["irritated", "dismissive"],
		"lines": [
			"Our line broke on yours. The court has read every name aloud.",
			"We shall not dress it: the field was yours, and the colours with it.",
			"Our colours are in your hands. Do not think the war is in them.",
		],
	},
	"event/siege_won": {
		"category": CAT_EVENT,
		"moods": ["pleased", "calculating"],
		"lines": [
			"The breach is ours and the town with it. Our batteries did the talking.",
			"Your walls came down in the end. We shall hold them better than you did.",
			"The garrison answered our last summons with a flag. The town is ours.",
		],
	},
	"event/siege_held": {
		"category": CAT_EVENT,
		"moods": ["dismissive", "pleased"],
		"lines": [
			"The walls held. Your batteries bought nothing but smoke and patience.",
			"You broke on our ramparts. The guns are still ours, and so is the town.",
			"Our stones outlasted your train. Come again when you have more of it.",
		],
	},
	"event/siege_lost": {
		"category": CAT_EVENT,
		"moods": ["irritated", "skeptical"],
		"lines": [
			"Our guns fell silent before the wall did. The siege is raised.",
			"We shall not spend another train on those stones this year.",
			"The wall stood and our batteries did not. The court will hear of it.",
		],
	},
	"event/siege_taken": {
		"category": CAT_EVENT,
		"moods": ["irritated", "dismissive"],
		"lines": [
			"The breach is yours and the town with it. We shall want it back.",
			"Our walls failed us. The court is being told so this very hour.",
			"You have the town. The stones remember who raised them.",
		],
	},
	"event/sea_won": {
		"category": CAT_EVENT,
		"moods": ["pleased", "gracious"],
		"lines": [
			"Our broadsides settled it. The water is ours, and the wreckage with it.",
			"Your squadron went down with the sun. We counted the masts from the shore.",
			"The sea answered for us. Send no more sail where ours keeps station.",
		],
	},
	"event/sea_lost": {
		"category": CAT_EVENT,
		"moods": ["irritated", "dismissive"],
		"lines": [
			"Our squadron went down with the sun. The sea keeps what it takes.",
			"The water is yours. Our captains will be asked hard questions.",
			"We lost the station and the hulls with it. That is the whole of the news.",
		],
	},
	# --- the crown's own turn (DR-20261111-08) ------------------------------
	# A study finished: the rival that watches the crown most closely says so.
	"event/tech_studied": {
		"category": CAT_EVENT,
		"moods": ["calculating", "skeptical"],
		"lines": [
			"Your scholars publish while ours still argue. We have taken note of it.",
			"So the crown has learned something new. Our admirals will want to hear it.",
			"Every study your court finishes makes our own colleges quieter. Go carefully.",
		],
	},
	# A hostile host stands in the reader's capital province.
	"event/capital_threatened": {
		"category": CAT_EVENT,
		"moods": ["dismissive", "irritated"],
		"lines": [
			"Your seat lies under our guns. Open the gates and spare the houses.",
			"We stand before your palace, and the question left is only how long.",
			"The town is ours to take when we choose it. Sleep on that.",
		],
	},
	# A Tribe the reader took under the flag speaks for itself.
	"event/colony_founded": {
		"category": CAT_EVENT,
		"moods": ["skeptical", "impatient"],
		"lines": [
			"Your flag is over our land. We were not asked, only told.",
			"You have bought our elders and our ground in the same handshake.",
			"The musket and the chapel came off the same ship. We carry both now.",
		],
	},
}
