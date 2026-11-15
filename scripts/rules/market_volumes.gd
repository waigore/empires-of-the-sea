class_name MarketVolumes
extends RefCounted
## One turn's world-market trade volumes: what each commodity saw bid and
## offered (price discovery, wiki: world-market § Price discovery), what each
## crown bought (its own cargo holds, DR-20261109-03) and the cargo afloat a
## blockade can raid (wiki: ships-and-naval § Trade and Transport Interception;
## DR-20261110-13). [MarketBook] owns one; prices and terms stay on
## [WorldMarket]. No RNG, no logging, no Game/Node access (REQ-P3-03).

## Commodity -> units bid this turn.
var bids: Dictionary
## Commodity -> units offered this turn.
var offers: Dictionary
## Faction -> units bought this turn.
var bought_by_faction: Dictionary
## Faction -> {commodity: units}: cargo afloat this turn.
var imports_by_faction: Dictionary


## Godot shares a typed default literal across instances, so every volume dict
## is built per instance here; one book must never see another's cargo.
func _init() -> void:
	bids = _fresh_dict()
	offers = _fresh_dict()
	bought_by_faction = _fresh_dict()
	imports_by_faction = _fresh_dict()


## Units bid this turn on one commodity ([method record_import] writes them).
func bid_volume(commodity: String) -> int:
	return int(bids.get(commodity, 0))


## Units offered this turn on one commodity ([method record_offer] writes them).
func offer_volume(commodity: String) -> int:
	return int(offers.get(commodity, 0))


## Units bought this turn across every commodity: the tonnage merchant cargo
## must carry (wiki: world-market § Cargo).
func bought_units() -> int:
	var total: int = 0
	for commodity: Variant in bids.keys():
		total += int(bids[commodity])
	return total


## Units one crown bought this turn. Legacy books that predate per-buyer
## accounting attribute every laden hold to the player.
func bought_units_for(faction: int) -> int:
	if bought_by_faction.is_empty() and not bids.is_empty():
		return bought_units() if faction == FactionCatalog.PLAYER_FACTION else 0
	if bought_by_faction.has(faction):
		return int(bought_by_faction[faction])
	# A saved book round-tripped through JSON keeps string keys.
	return int(bought_by_faction.get(str(faction), 0))


## This turn's demand per commodity across every buyer, for price discovery.
## A raid must read one crown's own cargo instead: [method imports_for].
func imports_this_turn() -> Dictionary:
	return bids.duplicate()


## One crown's own cargo this turn, commodity -> units: what a raid can take off
## its merchant hulls. Legacy books that predate per-buyer cargo attribute the
## whole book to the player, as [method bought_units_for] does.
func imports_for(faction: int) -> Dictionary:
	if imports_by_faction.is_empty():
		return bids.duplicate() if faction == FactionCatalog.PLAYER_FACTION else {}
	var own: Variant = _cargo_row(faction)
	if own is Dictionary:
		return (own as Dictionary).duplicate()
	return {}


## Every crown with cargo afloat this turn, ascending: the courts a blockade can
## raid (DR-20261110-13).
func importing_factions() -> Array[int]:
	var out: Array[int] = []
	if imports_by_faction.is_empty():
		if not bids.is_empty():
			out.append(FactionCatalog.PLAYER_FACTION)
		return out
	for raw: Variant in imports_by_faction.keys():
		var cargo: Dictionary = imports_by_faction[raw] as Dictionary
		if not cargo.is_empty():
			out.append(int(raw))
	out.sort()
	return out


## Books a purchase whose goods never sat another crown's stockpile: the buyer's
## cargo and its price-discovery demand move together (wiki: world-market
## § Minor and tribe auto-sell).
func record_import(commodity: String, quantity: int, faction: int) -> void:
	if quantity <= 0:
		return
	# A legacy book that only knows global bids attributes them to the player
	# before the first per-buyer entry is written.
	if bought_by_faction.is_empty() and not bids.is_empty():
		bought_by_faction[FactionCatalog.PLAYER_FACTION] = bought_units()
	bids[commodity] = bid_volume(commodity) + quantity
	var prior: int = (
		int(bought_by_faction[faction]) if bought_by_faction.has(faction) else 0
	)
	bought_by_faction[faction] = prior + quantity
	var cargo: Dictionary = _cargo_book(faction)
	cargo[commodity] = int(cargo.get(commodity, 0)) + quantity


## Books a sale for price discovery (wiki: world-market § Price discovery).
func record_offer(commodity: String, quantity: int) -> void:
	if quantity <= 0:
		return
	offers[commodity] = offer_volume(commodity) + quantity


## Takes a cancelled offer back out of the turn's supply, never below zero.
func withdraw_offer(commodity: String, quantity: int) -> void:
	offers[commodity] = maxi(offer_volume(commodity) - maxi(quantity, 0), 0)


## Starts a clean turn: nothing bought, sold or afloat yet.
func reset() -> void:
	bids.clear()
	offers.clear()
	bought_by_faction.clear()
	imports_by_faction.clear()


func copy() -> MarketVolumes:
	var clone := MarketVolumes.new()
	clone.bids = bids.duplicate()
	clone.offers = offers.duplicate()
	clone.bought_by_faction = bought_by_faction.duplicate()
	clone.imports_by_faction = imports_by_faction.duplicate(true)
	return clone


func to_dict() -> Dictionary:
	return {
		"bids": bids.duplicate(),
		"offers": offers.duplicate(),
		"bought_by_faction": bought_by_faction.duplicate(),
		"imports_by_faction": imports_by_faction.duplicate(true),
	}


static func from_dict(data: Dictionary) -> MarketVolumes:
	var volumes := MarketVolumes.new()
	volumes.bids = _dict_copy(data.get("bids"))
	volumes.offers = _dict_copy(data.get("offers"))
	volumes.bought_by_faction = _dict_copy(data.get("bought_by_faction"))
	volumes.imports_by_faction = _dict_copy(data.get("imports_by_faction"), true)
	return volumes


## Folds a save written while the volumes sat beside the book (on the market or
## on the book itself) back in. Absent keys change nothing.
func adopt_legacy(host: Dictionary) -> void:
	if host.has("bids"):
		bids = _dict_copy(host.get("bids"))
	if host.has("offers"):
		offers = _dict_copy(host.get("offers"))
	if host.has("bought_by_faction"):
		bought_by_faction = _dict_copy(host.get("bought_by_faction"))
	if host.has("imports_by_faction"):
		imports_by_faction = _dict_copy(host.get("imports_by_faction"), true)


## A map no other instance shares. Godot's debugger can hand back one constant
## for a bare `{}`, so each volume map is filled from a JSON round trip — one
## book must never read another's cargo.
static func _fresh_dict() -> Dictionary:
	var raw: Variant = JSON.parse_string("{}")
	if raw is Dictionary:
		return raw as Dictionary
	return {}


static func _empty_book() -> Dictionary:
	return _fresh_dict()


## The turn's cargo row for one crown, or null when it ships nothing. A loaded
## book may key factions by string, so both spellings are read.
func _cargo_row(faction: int) -> Variant:
	if imports_by_faction.has(faction):
		return imports_by_faction[faction]
	# String keys come from a JSON round trip. Never fall back to `get(key, {})`:
	# Godot hands back the mutable default literal, shared by every caller.
	if imports_by_faction.has(str(faction)):
		return imports_by_faction[str(faction)]
	return null


## The live per-crown cargo row, created on the first buy this turn. A loaded
## book may key factions by string, so a new purchase keeps filling that row.
func _cargo_book(faction: int) -> Dictionary:
	# Read the row straight from the book: a lookup funnelled through a Variant
	# return hands back a copy, and a purchase would then fill a detached row.
	var existing: Variant = _cargo_row(faction)
	if existing is Dictionary:
		return imports_by_faction[faction]
	imports_by_faction[faction] = {}
	return imports_by_faction[faction]


static func _dict_copy(raw: Variant, deep: bool = false) -> Dictionary:
	if raw is not Dictionary:
		return {}
	return (raw as Dictionary).duplicate(deep)
