class_name ShipNames
extends RefCounted
## Every hull in play bears a name (wiki: naming § Ship names; DR-20261111-07).
## Pure data and state: the yard christens a hull from its crown's period pool,
## walking past the names the squadron already flies and then numbering a repeat,
## so the same crown, squadron and instance id always christen the same hull and
## a reloaded campaign speaks the same names (REQ-P2-03, REQ-P3-03). The pick and
## the digest are NameRoster's; the pool is the navy's own. The name is stored on
## the fleet, so a hull keeps it for the life of the save.

## One period pool per Great Power, ASCII so it prints on every target size.
## Faction ids follow FactionCatalog: Spain, England, France, Portugal,
## Netherlands, Sweden.
const POOLS: Dictionary = {
	0:
	[
		"San Martin",
		"Trinidad",
		"San Felipe",
		"San Mateo",
		"Santa Ana",
		"Concepcion",
		"Santiago",
		"San Juan",
		"San Salvador",
		"Victoria",
	],
	1:
	[
		"Revenge",
		"Dreadnought",
		"Swiftsure",
		"Triumph",
		"Warspite",
		"Defiance",
		"Sovereign",
		"Lion",
		"Rainbow",
		"Vanguard",
	],
	2:
	[
		"Soleil Royal",
		"Dauphin Royal",
		"Tonnant",
		"Foudroyant",
		"Superbe",
		"Intrepide",
		"Hercule",
		"Neptune",
		"Formidable",
		"Sceptre",
	],
	3:
	[
		"Sao Martinho",
		"Sao Filipe",
		"Sao Mateus",
		"Santiago",
		"Sao Joao",
		"Santa Cruz",
		"Santo Antonio",
		"Sao Salvador",
		"Nossa Senhora",
		"Boa Viagem",
	],
	4:
	[
		"Batavia",
		"Amsterdam",
		"Rotterdam",
		"Delft",
		"Vrijheid",
		"Gouden Leeuw",
		"Eendracht",
		"Hollandia",
		"Prins Willem",
		"Zeven Provincien",
	],
	5:
	[
		"Vasa",
		"Kronan",
		"Svardet",
		"Nyckeln",
		"Mars",
		"Elefanten",
		"Draken",
		"Tre Kronor",
		"Riksapplet",
		"Gota Lejon",
	],
}

## Minors, Tribes and any crown with no pool of its own still name their hulls.
const GENERIC: Array[String] = [
	"Providence",
	"Fortune",
	"Diligence",
	"Bonaventure",
	"Hope",
	"Adventure",
	"Patience",
	"Temperance",
	"Vigilant",
	"Union",
]


## The pool a crown names its hulls from; unknown owners read the generic one.
static func pool_for(owner: int) -> Array[String]:
	return NameRoster.pool_of(POOLS, GENERIC, owner)


## The name this hull flies, read from the fleet's own record. A hull saved
## before names existed (or minted by an older scenario file) is christened on
## read by the same arithmetic, so nothing is ever anonymous (DR-20261111-07).
static func of(fleet: FleetState, hull_id: String) -> String:
	if fleet == null or hull_id.is_empty():
		return ""
	var stored: String = String(fleet.hull_names.get(hull_id, ""))
	if not stored.is_empty():
		return stored
	return christen(fleet, hull_id)


## The name a hull of this fleet would take now: the mint with the names its
## squadron already flies set aside.
static func christen(fleet: FleetState, hull_id: String) -> String:
	return mint(fleet.owner, fleet.id, hull_id, taken_names(fleet, hull_id))


## Christens every hull of the fleet that carries no name yet, in roster order,
## so a launched hull, a scenario muster and a loaded save all end up named. The
## squadron's names are then made pairwise distinct, because a roster that took
## hulls from two cohorts (a merge, or a save written by a build that named them
## apart) can fly one name twice (wiki: naming § Ship names).
static func fill(fleet: FleetState) -> void:
	if fleet == null:
		return
	for hull_id: String in fleet.hulls:
		if not String(fleet.hull_names.get(hull_id, "")).is_empty():
			continue
		fleet.hull_names[hull_id] = christen(fleet, hull_id)
	settle(fleet)


## One name, one hull: a squadron's names are pairwise distinct (wiki: naming
## § Ship names; DR-20261111-07). The hull earlier in the roster keeps the name
## it flies and a later one is christened again past the names the squadron now
## bears, so a hull that joined the squadron in a merge gives way to the hull
## that already flew the name. Deterministic — the same owners, squadrons and
## instance ids always settle alike — and written to the fleet's own store, so a
## reload speaks the settled names. An ordinary squadron is left untouched.
static func settle(fleet: FleetState) -> void:
	if fleet == null:
		return
	var seen: Dictionary = {}
	for hull_id: String in fleet.hulls:
		var name: String = of(fleet, hull_id)
		if name.is_empty() or seen.has(name):
			fleet.hull_names[hull_id] = christen(fleet, hull_id)
			name = String(fleet.hull_names[hull_id])
		seen[name] = true


## The name a new hull takes: a stable pick from the crown's pool, advanced past
## the names the squadron already flies; once the whole pool is in service the
## pick repeats with an ordinal (wiki: naming § Ship names).
static func mint(owner: int, fleet_id: int, hull_id: String, taken: Array[String]) -> String:
	return NameRoster.pick(
		pool_for(owner), "%d:%d:%s" % [owner, fleet_id, hull_id], taken, "Unnamed"
	)


## Names this squadron already flies, leaving out `skip_id` (the hull being
## christened, which carries no name yet).
static func taken_names(fleet: FleetState, skip_id: String = "") -> Array[String]:
	return NameRoster.taken_names(fleet.hulls, fleet.hull_names, skip_id)
