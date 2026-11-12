class_name GeneralNames
extends RefCounted
## Every commander in play bears a name (wiki: naming § General names;
## DR-20261112-03). Pure data and state: a crown christens each general from its
## own period pool, walking past the names its other generals already carry and
## then numbering a repeat, so the same crown and general id always christen the
## same commander and a reloaded campaign speaks the same names (REQ-P2-03,
## REQ-P3-03). The pick and the digest are NameRoster's; the pool is the army's
## own. The name is stored on the roster, so a general keeps it for the life of
## the save.

## One period pool of commanders per Great Power, ASCII so it prints on every
## target size. Faction ids follow FactionCatalog: Spain, England, France,
## Portugal, Netherlands, Sweden.
const POOLS: Dictionary = {
	0:
	[
		"Duke of Alba",
		"Duke of Parma",
		"Marquis of Spinola",
		"Duke of Medina Sidonia",
		"Hernan Cortes",
		"Francisco Pizarro",
		"Pedro de Alvarado",
		"Duke of Osuna",
		"Marquis of Villafranca",
		"Count of Fuentes",
	],
	1:
	[
		"Duke of Marlborough",
		"Duke of Wellington",
		"Earl of Essex",
		"Sir Francis Drake",
		"Lord Fairfax",
		"Prince Rupert",
		"Duke of Cumberland",
		"Earl of Peterborough",
		"Sir John Moore",
		"Lord Clive",
	],
	2:
	[
		"Duc de Guise",
		"Vicomte de Turenne",
		"Prince de Conde",
		"Duc de Luxembourg",
		"Marquis de Vauban",
		"Comte de Rochambeau",
		"Duc de Villars",
		"Marquis de Montcalm",
		"Comte de Grasse",
		"Duc de Richelieu",
	],
	3:
	[
		"Duque de Aveiro",
		"Conde de Castelo Melhor",
		"Dom Joao de Castro",
		"Conde de Vila Flor",
		"Dom Francisco de Noronha",
		"Marques de Marialva",
		"Conde de Redondo",
		"Dom Luis de Almeida",
		"Conde de Tarouca",
		"Marques de Alegrete",
	],
	4:
	[
		"Prince of Orange",
		"Maurice of Nassau",
		"Frederick Henry",
		"Michiel de Ruyter",
		"Maarten Tromp",
		"Duke of Schomberg",
		"Walrad of Nassau",
		"Count of Solms",
		"Prince of Hesse",
		"Willem van Oranje",
	],
	5:
	[
		"Gustavus Adolphus",
		"Gustaf Horn",
		"Jacob De la Gardie",
		"Lennart Torstensson",
		"Carl Gustaf Wrangel",
		"Count of Konigsmarck",
		"Magnus Stenbock",
		"Carl Gustaf Rehnskiold",
		"Charles XII",
		"Axel Oxenstierna",
	],
}

## A crown with no pool of its own still names its commanders.
const GENERIC: Array[String] = [
	"Colonel Hawksworth",
	"Captain Bellamy",
	"Major Craddock",
	"Colonel Thorne",
	"Captain Marsh",
	"Major Ellery",
	"Colonel Vance",
	"Captain Rooke",
	"Major Standish",
	"Colonel Hale",
]


## The pool a crown names its commanders from; unknown owners read the generic
## one.
static func pool_for(owner: int) -> Array[String]:
	return NameRoster.pool_of(POOLS, GENERIC, owner)


## The name a general of this crown would take now: a stable pick from the
## crown's pool, advanced past the names its other generals already carry; once
## the whole pool is in service the pick repeats with an ordinal (wiki: naming
## § General names).
static func mint(owner: int, general_id: String, taken: Array[String]) -> String:
	return NameRoster.pick(
		pool_for(owner), "%d:%s" % [owner, general_id], taken, "Commander"
	)
