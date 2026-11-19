class_name CargoRead
extends RefCounted
## What the next turn's crossing will carry from the crown's overseas estates,
## read before the turn closes (wiki: ships-and-naval § Cargo holds and capacity;
## extraction-and-improvements § Flow to Stockpile; DR-20261109-17,
## DR-20261116-05).
##
## The Extraction phase ships the richest tonnage first into the home fleet's
## holds and leaves the rest on the far shore — there is no per-province storage
## — and the turn's despatch only speaks **after** the fact. This reading runs
## over the plan the phase itself will use, so a crown that is about to strand a
## harvest reads the wait while it can still launch a hull or moor the squadron
## (REQ-P2-03, REQ-P5-05).


## The plan's own figures as a before-shot: `holds` the home squadron carries,
## `waiting` tons the overseas estates will yield, `crossing` tons the holds will
## land, `stranded` tons left on the far shore, and `goods` that stranded
## tonnage by commodity, richest first (the plan's own shipping order).
## An empty plan is a reading the caller could not make (no world): `known` is
## false and every figure is 0, so a sheet prints nothing rather than a zero.
static func reading(plan: Dictionary) -> Dictionary:
	if plan.is_empty() or not plan.has("holds"):
		return {
			"known": false, "holds": 0, "waiting": 0, "crossing": 0, "stranded": 0,
			"goods": [],
		}
	var crossing: int = maxi(int(plan.get("used", 0)), 0)
	var stranded: int = maxi(int(plan.get("left_total", 0)), 0)
	var goods: Array[Dictionary] = []
	var left: Dictionary = plan.get("left", {}) as Dictionary
	for raw: Variant in EconomyOverseas.priority(left.keys()):
		var id: String = String(raw)
		var amount: int = int(left[id])
		if amount > 0:
			goods.append({"id": id, "amount": amount})
	return {
		"known": true,
		"holds": maxi(int(plan.get("holds", 0)), 0),
		"waiting": crossing + stranded,
		"crossing": crossing,
		"stranded": stranded,
		"goods": goods,
	}


## The crossing in one line, or empty when nothing waits abroad: the reading
## appears only when the rule bites, so a court with no overseas estate reads no
## extra chrome (REQ-P1-07).
static func line(read: Dictionary) -> String:
	if not bool(read.get("known", false)) or int(read.get("waiting", 0)) <= 0:
		return ""
	var text: String = "CROSSING  %s abroad  ·  %s cross this turn" % [
		_tons(int(read.get("waiting", 0))), _tons(int(read.get("crossing", 0)))
	]
	var stranded: int = int(read.get("stranded", 0))
	if stranded > 0:
		text += "  ·  %s left on the far shore" % _tons(stranded)
	return text


## The rule the line rests on and the step that would land the rest: a hold
## carries one unit a turn, and the home squadron's merchant hulls are the only
## holds (wiki: ships-and-naval § Cargo holds and capacity). Empty when every ton
## crosses, because then there is no wait to name.
static func note(read: Dictionary) -> String:
	if not bool(read.get("known", false)):
		return ""
	var stranded: int = int(read.get("stranded", 0))
	if stranded <= 0:
		return ""
	var goods: String = goods_text(read)
	if int(read.get("holds", 0)) <= 0:
		return (
			"No holds cross: the home squadron's merchant hulls are the only holds, "
			+ "and she is away from the seat or carries none. Launch a merchant hull "
			+ "at the seat, or moor her there.%s"
		) % goods
	return (
		"A hold carries one unit a turn: %d more would land the rest. Whatever is "
		+ "left stays on the far shore — no per-province storage.%s"
	) % [stranded, goods]


## The stranded tonnage by commodity, richest first, as a sentence tail: the
## plan's own order, so the goods a crown loses are named and not only counted.
static func goods_text(read: Dictionary, limit: int = 3) -> String:
	var goods: Array = read.get("goods", []) as Array
	if goods.is_empty():
		return ""
	var parts: PackedStringArray = []
	for index in mini(goods.size(), limit):
		var entry: Dictionary = goods[index] as Dictionary
		parts.append(
			"%s %d" % [CommodityCatalog.label(String(entry["id"])), int(entry["amount"])]
		)
	var text: String = " Left: " + ", ".join(parts)
	if goods.size() > limit:
		text += " and %d more" % (goods.size() - limit)
	return text + "."


## "1 ton" / "4 tons": the unit the holds carry, so a figure never reads as a
## count of hulls.
static func _tons(amount: int) -> String:
	return "%d ton%s" % [amount, "" if amount == 1 else "s"]
