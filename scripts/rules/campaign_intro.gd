class_name CampaignIntro
extends RefCounted
## The crown's charge at the opening of a campaign (wiki:
## dialogue-content-and-yarn § Kinds, `game_start_intro`; dialogue-management
## § Kinds: a dismiss-only client gate before the first turn).
##
## Pure composition: the page prints what this module returns and decides
## nothing, so the gate can never change an outcome (REQ-P2-03) and the copy
## carries no province id, score or asset path (REQ-P1-02, REQ-P3-03). The pick
## of address is a stable salt of the campaign's seed and crown, so the same
## campaign always opens with the same words (REQ-P2-04).

## Content key in the wiki's `<category>/<situation>` form. The intro is the one
## point the reader's own court speaks, so it lives here rather than in the
## court-to-court catalogue, whose speaker is always the other party.
const POINT: String = "intro/opening"

const KICKER: String = "By the grace of God and the counsel of the crown"
const TITLE: String = "THE CROWN'S CHARGE"
const BEGIN: String = "BEGIN"

## Authored addresses. `{leader}`, `{crown}` and `{seat}` are the only variables
## and all three arrive already masked, so the catalogue never looks a faction up.
const LINES: Array[String] = [
	"To {leader}, who holds the crown of {crown}:\n\n"
	+ "Our charts end where the ocean begins. Beyond them lie the Indies, and every "
	+ "court in Europe has already sent its captains to take them. We shall not be "
	+ "the last to sail.\n\n"
	+ "Work the estates we hold, raise the towns that feed them, and carry our flag "
	+ "to coasts no European has yet named. Where our ships go, our claim goes with "
	+ "them.",
	"{leader}, the age is open and it will not wait for us.\n\n"
	+ "Our rivals divide the New World among themselves while our harbours stand "
	+ "half empty and our fields half worked. A crown that sleeps through this "
	+ "century will beg for the next.\n\n"
	+ "Set our people to the land, our yards to the hulls, and our captains to the "
	+ "sea. What we take now, our children keep.",
	"Hear the charge laid on {leader} and on the crown of {crown}.\n\n"
	+ "From {seat} we ask three things of you: that our fields be worked, that our "
	+ "squadrons be manned, and that our name be spoken on every coast the sun "
	+ "touches. The sea grants no second voyage.\n\n"
	+ "Go, and let the map of this age be drawn in our hand.",
]


## The whole page in one record: kicker, title, stamp, body, charges, begin.
## `turn` is the campaign's own calendar, so an advanced start opens in its year
## rather than in 1500 (wiki: advanced-starts).
static func address(
	crown: String,
	leader: String,
	seat: String,
	turn: int,
	infinite: bool,
	salt: int
) -> Dictionary:
	var body: String = render(
		String(LINES[absi(salt) % LINES.size()]), leader, crown, seat
	)
	return {
		"kicker": KICKER,
		"title": TITLE,
		"stamp": _stamp(seat, turn),
		"body": body,
		"charges": charges(infinite),
		"begin": BEGIN,
	}


## The campaign's own calendar and the seat it opened on; a page mounted with no
## seat (a tool, a test) still prints a whole stamp.
static func _stamp(seat: String, turn: int) -> String:
	var year: String = "Anno Domini %d" % TurnTime.year_for_turn(maxi(turn, 1))
	if seat.is_empty():
		return year
	return "%s  ·  %s" % [year, seat]


## The charge a page prints when it is mounted with no campaign behind it (a
## tool, a test, a preview): the default crown's own opening.
static func default_address() -> Dictionary:
	var faction: int = FactionCatalog.PLAYER_FACTION
	return address(
		FactionCatalog.name_of(faction),
		LeaderCatalog.label(LeaderCatalog.default_key(faction)),
		"",
		1,
		false,
		0
	)


## What the age asks of the crown: the published win condition, the calendar the
## player chose, and how many rivals sail for the same shores
## (wiki: victory § Military victory; turn-time-mapping § Campaign calendar cap).
static func charges(infinite: bool) -> Array[String]:
	var lines: Array[String] = []
	lines.append("Win the age: hold %d Old World provinces." % VictoryRules.MILITARY_THRESHOLD)
	if infinite:
		lines.append("No calendar closes this age; the field alone decides it.")
	else:
		lines.append(
			"The calendar closes in %d — turn %d."
			% [TurnTime.STOP_YEAR, TurnTime.cap_turn()]
		)
	lines.append(
		"%d rival crowns sail for the same shores."
		% maxi(FactionCatalog.great_power_ids().size() - 1, 0)
	)
	return lines


## Fill the three permitted placeholders. Every name is handed in already masked.
static func render(template: String, leader: String, crown: String, seat: String) -> String:
	return (
		template
		.replace("{leader}", leader)
		.replace("{crown}", crown)
		.replace("{seat}", seat)
	)


## Stable integer salt: the same seed and crown always open with the same words,
## in this run and after a save (never randomness).
static func salt(map_seed: int, faction: int) -> int:
	var value: int = 17
	for part: int in [map_seed, faction]:
		value = absi(value * 131 + part + 17) % 1000003
	return value
