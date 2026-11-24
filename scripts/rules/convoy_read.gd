class_name ConvoyRead
extends RefCounted
## What the crown's warships do for its convoy, in one reading (wiki:
## ships-and-naval § Trade and Transport Interception; DR-20261124-04). The rule
## page publishes the escort cover — "warships accompanying the home fleet
## reduce both cargo and ship loss probabilities",
## `escortFactor = min(0.5, escortHull / cargoHull × 0.3)` — and the raid pass
## reads it, but no sheet a crown plans on said what its warships buy.
##
## Every number here is [NavalHullLoss]'s own, never a second copy: the cover is
## its `escort_factor`, the hull risk its `chance` and the hull it protects its
## `at_risk`, so the sheet cannot promise a convoy the turn's raids deny
## (REQ-P2-03). A reading only: no hull is lost, moved or ordered here.

## The published cap on escort cover (`min(0.5, …)`); a convoy at this share
## guards as well as one can, so the words stop promising more.
const COVER_CAP: float = 0.5


## The convoy's cover and what a raid still costs it: `home` is the crown's
## squadron in port at its seat — the hulls a commerce raid works (the raid pass
## reads the same squadron through `MapPlayRaids.home_fleet`). An empty reading —
## no squadron, or no merchant hull to protect — has `known` false and no words,
## so a sheet prints nothing rather than a zero.
static func read(home: FleetState) -> Dictionary:
	if home == null:
		return _nothing()
	var target: Dictionary = NavalHullLoss.at_risk(home)
	if target.is_empty():
		return _nothing()
	var cover: float = NavalHullLoss.escort_factor(home)
	var chance: float = NavalHullLoss.chance(home)
	var at_risk: String = String(target.get("type_id", ""))
	return {
		"known": true,
		"cover": cover,
		"capped": cover >= COVER_CAP,
		"warships": _warships(home),
		"cargo": home.hulls.size() - _warships(home),
		"at_risk": at_risk,
		"hull_chance": chance,
		"line": line(cover, _warships(home), chance, at_risk),
		"tip": tip(),
	}


## The reading in one line: the cover the convoy's warships give and what a hit
## still costs.
##   `CONVOY  1 warship cuts a raid on the holds by 20%  ·  a hit sinks a
##   Fluyte on 32%`
##   `CONVOY  no warship covers the holds  ·  a hit sinks a Fluyte on 40%`
## A convoy at the published cap names the cap instead of a larger share, and a
## squadron with no merchant hull has no prize to price, so the line is empty.
static func line(
	cover: float, warships: int, hull_chance: float, at_risk: String
) -> String:
	if at_risk.is_empty():
		return ""
	var risk: String = "a hit sinks %s on %d%%" % [
		with_article(ShipStats.display_name(at_risk)), _percent(hull_chance),
	]
	if warships <= 0:
		return "CONVOY  no warship covers the holds  ·  %s" % risk
	if cover >= COVER_CAP:
		return "CONVOY  %d warship%s give all the cover a convoy takes (%d%%)  ·  %s" % [
			warships, "" if warships == 1 else "s", _percent(COVER_CAP), risk,
		]
	var share: int = maxi(1, _percent(cover))
	return "CONVOY  %d warship%s cut%s a raid on the holds by %d%%  ·  %s" % [
		warships, "" if warships == 1 else "s", "s" if warships == 1 else "", share, risk,
	]


## The rule behind the line, for the row's own tip: the formula, the cap and
## where the figure comes from. A phone keeps no hover, so the line above stands
## on its own and the tip only says what the numbers are.
static func tip() -> String:
	return (
		"Escort cover is min(%d%%, escort hull / cargo hull x 0.3) over the"
		+ " warships in port at your seat. It cuts both a raid's chance and the"
		+ " chance a hit sends a merchant hull down: the richest hold is the prize."
	) % _percent(COVER_CAP)


## `a Fluyte`, `an Indiaman`: the catalogue's own name for the hull, read with
## the article its word takes. The prize line in the fleet dossier words one hull
## the same way, so two sheets never print her two ways.
static func with_article(name: String) -> String:
	var first: String = name.substr(0, 1).to_lower()
	var vowel: bool = (
		first == "a" or first == "e" or first == "i" or first == "o" or first == "u"
	)
	return "%s %s" % ["an" if vowel else "a", name]


## Warships in the squadron: the escorts the formula weighs.
static func _warships(home: FleetState) -> int:
	var total: int = 0
	for hull_id: String in home.hulls:
		if ShipStats.is_warship(home.type_of(hull_id)):
			total += 1
	return total


static func _percent(share: float) -> int:
	return roundi(clampf(share, 0.0, 1.0) * 100.0)


static func _nothing() -> Dictionary:
	return {
		"known": false, "cover": 0.0, "capped": false, "warships": 0, "cargo": 0,
		"at_risk": "", "hull_chance": 0.0, "line": "", "tip": "",
	}
