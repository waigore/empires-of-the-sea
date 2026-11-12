class_name RegimentNames
extends RefCounted
## Every regiment in play bears a name (wiki: naming § Regiment names;
## DR-20261111-18). Pure data and state: a muster christens the regiment from its
## crown's period pool, walking past the names the army already wears and then
## numbering a repeat, so the same crown, army and instance id always christen
## the same regiment and a reloaded campaign speaks the same names (REQ-P2-03,
## REQ-P3-03). The pick and the digest are NameRoster's; the pool is the army's
## own. The name is stored on the army, so a regiment keeps it for the life of
## the save.

## One period pool of regimental titles per Great Power, ASCII so it prints on
## every target size. Faction ids follow FactionCatalog: Spain, England, France,
## Portugal, Netherlands, Sweden.
const POOLS: Dictionary = {
	0:
	[
		"Tercio de Sicilia",
		"Tercio de Napoles",
		"Tercio de Flandes",
		"Tercio de Milan",
		"Tercio de Aragon",
		"Tercio de Castilla",
		"Tercio de Sevilla",
		"Tercio de Cartagena",
		"Guardia Espanola",
		"Tercio del Mar Oceano",
	],
	1:
	[
		"Coldstream Guards",
		"Royal Welch Foot",
		"The Buffs",
		"Green Howards",
		"Royal Scots",
		"Dorsetshire Foot",
		"The King's Own",
		"Northumberland Foot",
		"Sea Service Marines",
		"London Trained Bands",
	],
	2:
	[
		"Regiment du Roi",
		"Gardes Francaises",
		"Gardes Suisses",
		"Regiment de Picardie",
		"Regiment de Champagne",
		"Regiment de Normandie",
		"Regiment de la Marine",
		"Regiment de Bearn",
		"Royal Roussillon",
		"Regiment de Touraine",
	],
	3:
	[
		"Terco de Lisboa",
		"Terco do Porto",
		"Terco da Beira",
		"Terco de Alentejo",
		"Terco de Goa",
		"Terco de Malaca",
		"Terco do Brasil",
		"Terco de Mazagao",
		"Terco dos Acores",
		"Terco Real",
	],
	4:
	[
		"Hollandse Garde",
		"Blauwe Garde",
		"Oranje Regiment",
		"Nassau Regiment",
		"Zeeland Regiment",
		"Friesland Regiment",
		"Staten Regiment",
		"Amsterdam Schutterij",
		"Oude Garde",
		"Waal Regiment",
	],
	5:
	[
		"Livgardet",
		"Upplands Regemente",
		"Sodermanlands Regemente",
		"Smalands Regemente",
		"Vastgota Regemente",
		"Savolaks Regemente",
		"Halsinge Regemente",
		"Narikes Regemente",
		"Kronobergs Regemente",
		"Varmlands Regemente",
	],
}

## Minors, Tribes and any crown with no pool of its own still name their men.
const GENERIC: Array[String] = [
	"Free Company",
	"Colonial Levy",
	"Marine Company",
	"Frontier Company",
	"Town Watch",
	"Militia Company",
	"Volunteer Company",
	"Garrison Company",
	"Pioneer Company",
	"Provincial Company",
]


## The pool a crown names its regiments from; unknown owners read the generic
## one.
static func pool_for(owner: int) -> Array[String]:
	return NameRoster.pool_of(POOLS, GENERIC, owner)


## The name this regiment wears, read from the army's own record. A regiment
## saved before names existed (or minted by an older scenario file) is
## christened on read by the same arithmetic, so nothing is ever anonymous
## (DR-20261111-18).
static func of(army: ArmyState, regiment_id: String) -> String:
	if army == null or regiment_id.is_empty():
		return ""
	var stored: String = String(army.regiment_names.get(regiment_id, ""))
	if not stored.is_empty():
		return stored
	return christen(army, regiment_id)


## The name a regiment of this army would take now: the mint with the names its
## army already wears set aside.
static func christen(army: ArmyState, regiment_id: String) -> String:
	return mint(army.owner, army.id, regiment_id, taken_names(army, regiment_id))


## Christens every regiment of the army that carries no name yet, in roster
## order, so a recruit, a scenario muster and a loaded save all end up named.
static func fill(army: ArmyState) -> void:
	if army == null:
		return
	for regiment_id: String in army.regiments:
		if not String(army.regiment_names.get(regiment_id, "")).is_empty():
			continue
		army.regiment_names[regiment_id] = christen(army, regiment_id)


## The name a new regiment takes: a stable pick from the crown's pool, advanced
## past the names the army already wears; once the whole pool is in service the
## pick repeats with an ordinal (wiki: naming § Regiment names).
static func mint(owner: int, army_id: int, regiment_id: String, taken: Array[String]) -> String:
	return NameRoster.pick(
		pool_for(owner), "%d:%d:%s" % [owner, army_id, regiment_id], taken, "Unnamed"
	)


## Names this army already wears, leaving out `skip_id` (the regiment being
## christened, which carries no name yet).
static func taken_names(army: ArmyState, skip_id: String = "") -> Array[String]:
	return NameRoster.taken_names(army.regiments, army.regiment_names, skip_id)
