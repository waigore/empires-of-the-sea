class_name CivilianHire
extends RefCounted
## What a craft's hire buys and what it waits on, in the roster's own words
## (wiki: civilian-units § Civilian Types and Roles, § Training). The muster rail
## is where a crown spends 1,000–2,000 ducats and four paper on a name, and the
## one study a craft waits on lived only in the refusal a crown met after the
## press (DR-20261118-09). Pure reads over the roster: it prices nothing, gates
## nothing and moves nothing (REQ-P2-03, REQ-P3-03).

## Each craft's own work, one line, from the wiki's roster row: the Explorer
## charts and prospects, the Engineer builds, the Builder raises, the Spy shadows
## and screens, the Merchant buys deeds, the Rail Builder lays railroads.
const WORK: Dictionary = {
	"explorer": "Charts a province and prospects its ground",
	"engineer": "Builds roads, harbours, forts and wards",
	"builder": "Raises estates and develops the town",
	"spy": "Shadows a rival court and keeps the counter-espionage screen",
	"merchant": "Buys land in a Minor's or Tribe's province",
	"rail_builder": "Upgrades roads to railroads",
}


## What the craft does, "" for a type the roster does not carry.
static func does(type_id: String) -> String:
	return String(WORK.get(type_id, ""))


## The study a still-locked craft waits on, "" when the hire is open. One reading
## for the rail that prints the gate and the order that refuses the hire, so the
## row can never name a study the order would not ask for (wiki: civilian-units
## § Training; REQ-P2-03).
static func locked_tech(type_id: String, tech_unlocked: Dictionary = {}) -> String:
	if CivilianCatalog.is_unlocked(type_id, tech_unlocked):
		return ""
	return CivilianCatalog.unlock_tech(type_id)


## The line under a hire's button: what the craft does, then the study it waits
## on — `Upgrades roads to railroads · needs Early Steam Engine`. A gated craft
## says so on the row instead of leaving it to a refusal toast.
static func line(type_id: String, tech_unlocked: Dictionary = {}) -> String:
	var work: String = does(type_id)
	var tech: String = locked_tech(type_id, tech_unlocked)
	if tech.is_empty():
		return work
	return "%s · needs %s" % [work, TechCatalog.display_name(tech)]