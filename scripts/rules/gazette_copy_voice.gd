class_name GazetteCopyVoice
extends RefCounted
## The shared vocabulary of the Gazette's copy desk: how the crown names itself
## in print, and the figures every desk may quote. A desk reads only what the
## record carries, so no desk can invent an outcome the rules did not decide
## (wiki: the-gazette § Prose; REQ-P2-03, REQ-P3-03).


## The crown's own voice in a printed line.
const CROWN: String = "our crown"


## The beaten side's losses, hulls or regiments, exactly as the phase recorded
## them. Never negative.
static func count(rec: Dictionary) -> int:
	return maxi(int(rec.get("count", 0)), 0)


## The crown's own dead in a battle it fought. Another court's fight carries no
## `own_lost`, so its losses are never counted (wiki: the-gazette § What the
## crown can know).
static func own(rec: Dictionary) -> int:
	return maxi(int(rec.get("own_lost", 0)), 0)


## Money as the ledger prints it.
static func money(rec: Dictionary) -> String:
	return DiplomacyCatalog.money(int(rec.get("amount", 0)))
