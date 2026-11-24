class_name DeckRead
extends RefCounted
## What a squadron's deck can still take, in one reading (wiki: ships-and-naval
## § Naval transport, § Civilian passengers; DR-20261124-14).
##
## The rule page publishes the deck plainly — "each hull carries one regiment,
## regardless of type", and "one hull carries one civilian" — so a deck is its
## hulls, and the room it has is what those hulls are not already carrying. The
## boarding gates ([method NavalTransport.can_embark],
## [method CivilianVoyage.can_embark]) read the same [NavalDeck] counts, so a
## sheet that prices the room can promise no berth a boarding would refuse
## (REQ-P2-03, REQ-P5-05).
##
## A reading only: no army, colonist or hull is boarded, landed or broken here,
## and no gate is loosened. The words are this module's, so the squadron's sheet
## and the standard's boarding press cannot count one deck two ways.


## The deck, as `{known, hulls, men, colonists, aboard, free}`: `hulls` is
## [method NavalDeck.capacity] (one berth a hull), `men` the regiments the
## caller means to put aboard, `colonists` the passengers the squadron already
## carries, `aboard` both of them, and `free` the berths those two leave.
## `known` false for a squadron with no hull, so a sheet prints nothing rather
## than a zero.
static func read(fleet: FleetState, men: int = 0) -> Dictionary:
	if fleet == null:
		return _nothing()
	var hulls: int = NavalDeck.capacity(fleet)
	if hulls <= 0:
		return _nothing()
	var colonists: int = maxi(fleet.civilian_count(), 0)
	var aboard: int = maxi(men, 0) + colonists
	return {
		"known": true,
		"hulls": hulls,
		"men": maxi(men, 0),
		"colonists": colonists,
		"aboard": aboard,
		"free": maxi(hulls - aboard, 0),
	}


## The room the deck has, for a line a sheet already prints: `room for 2 more`
## on a deck with berths left, `no room aboard` when the hulls are full, and
## nothing for a squadron the read does not know.
static func room_text(reading: Dictionary) -> String:
	if not bool(reading.get("known", false)):
		return ""
	var free: int = int(reading.get("free", 0))
	if free <= 0:
		return "no room aboard"
	return "room for %d more" % free


## The deck in the words a boarding press prints: `5 hulls, 3 free`, `5 hulls,
## 1 free` on a deck with one berth left, `5 hulls, all free` on a deck carrying
## nobody and `5 hulls, no room aboard` on a full one. Singular where the
## squadron is one hull (REQ-P1-07: the sheet is read at a phone's size).
static func deck_text(reading: Dictionary) -> String:
	if not bool(reading.get("known", false)):
		return ""
	var hulls: int = int(reading.get("hulls", 0))
	var free: int = int(reading.get("free", 0))
	var phrase: String = "%d %s" % [hulls, "hull" if hulls == 1 else "hulls"]
	if free <= 0:
		return "%s, no room aboard" % phrase
	if free >= hulls:
		return "%s, all free" % phrase
	return "%s, %d free" % [phrase, free]


static func _nothing() -> Dictionary:
	return {
		"known": false,
		"hulls": 0,
		"men": 0,
		"colonists": 0,
		"aboard": 0,
		"free": 0,
	}
