class_name AiStaffTaste
extends RefCounted
## The one crew a leader's taste asks for beyond the region's work (wiki:
## civilian-build-planner § Architecture — relative civilian-type weights;
## ai-personalities § Domain weight vectors).
##
## The published hire order fills a region's staff targets and stops there, so
## every court would keep the same mix: the map's own work is the only appetite
## in the table. A leader leans somewhere — the explorer court charts more
## ground, the fortifier raises another road or fort, the trader works another
## deed, the tactician reads a rival's order of battle — and this module is that
## lean, and nothing else. It reads the archetype's weight vector, says which
## type is the court's own crew and what one more of it asks of the target
## table; the hire itself is the published one, paid at the catalogue's price,
## through the same purse, footing and gate it always passed (REQ-P2-03,
## REQ-P3-03). Pure config read: state in, weights out.

## Weight at which a type is the court's own crew: one kept beyond the region's
## own work. A type the archetype does not name reads 1, the published order.
const TASTE: int = 3

## The types a taste may ask for, in the catalogue's own order. A Rail Builder
## is a technology's crew, not a taste's: it is taken when the rail work is
## there (CivilianCatalog).
const TYPES: Array[String] = ["explorer", "engineer", "builder", "spy", "merchant"]


## The type's weight in the court's archetype; 1 is the published order, and a
## court with no archetype (a fixture, a crown that names no leader) reads 1
## everywhere.
static func weight(config: AiConfig, type_id: String) -> int:
	if config == null:
		return 1
	return int(config.staff_preference().get(type_id, 1))


## True when this crew is the court's own rather than the region's.
static func is_taste(config: AiConfig, type_id: String) -> bool:
	return weight(config, type_id) >= TASTE


## The region's targets with one more crew of the court's own taste, where that
## crew has work in this region: a Merchant is only wanted while a deed is open
## (its published target is 0 otherwise, and a merchant with no deed would
## idle), and the Spy's screen is one spy's work, so a second stands only for
## the archetype that wants a rival read as well as its own court screened.
## Every other type keeps the target the map's work gave it.
static func raises(config: AiConfig, targets: Dictionary) -> Dictionary:
	var raised: Dictionary = targets.duplicate()
	for type_id: String in TYPES:
		if not is_taste(config, type_id):
			continue
		if int(raised.get(type_id, 0)) <= 0:
			continue
		raised[type_id] = int(raised.get(type_id, 0)) + 1
	return raised


## How many of one type a roster already fields: what a target is measured
## against, and what tells a taste hire from the region's own ask.
static func held(roster: Array, type_id: String) -> int:
	var found: int = 0
	for unit: CivilianState in roster:
		if unit != null and unit.type_id == type_id:
			found += 1
	return found


## The court's own crew, when it is on offer: with its first Builder and
## Engineer standing, the court takes the crew its archetype leans on ahead of
## the rest of the published queue, so the mix a leader keeps is the mix its
## archetype reads of (wiki: civilian-build-planner § Architecture;
## civilian-units § Merchant — the deed partner's own early door reads the same
## way). Empty when no crew of the court's own is on offer, or the region has
## yet to stand the two crews every court musters first: the published order
## then stands exactly as it did.
static func lead(config: AiConfig, queue: Array[String], roster: Array) -> String:
	if config == null:
		return ""
	if held(roster, "builder") < 1 or held(roster, "engineer") < 1:
		return ""
	for type_id: String in TYPES:
		if is_taste(config, type_id) and queue.has(type_id):
			return type_id
	return ""


## True when a hire is the court's own crew rather than the region's ask: the
## roster already meets the region's target for the type (`own`) and only the
## taste table still wants one more (`targets`). A caller that hands in no
## region reading keeps the published answer — the hire is the map's.
static func drives(
	config: AiConfig, type_id: String, targets: Dictionary, own: Dictionary, roster: Array
) -> bool:
	if not is_taste(config, type_id) or own.is_empty():
		return false
	var have: int = held(roster, type_id)
	return have >= int(own.get(type_id, 0)) and int(targets.get(type_id, 0)) > have


## "the fortifier's taste" — the archetype a court hires in character of, as the
## turn trace names it. Empty for a court with no archetype.
static func note(config: AiConfig) -> String:
	if config == null:
		return ""
	var title: String = String(config.personality.get("title", ""))
	if title.is_empty():
		return ""
	return "the %s's taste" % title