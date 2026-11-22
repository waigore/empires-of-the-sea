class_name MapPlayCommandPick
extends RefCounted
## The hosts the court's own land pass would lead into battle this turn, and how
## many of the crown's commanders answer them (wiki: military-generals
## § Assignment — the attack cap; § Medals — fallback; DR-20261122-02).
##
## The reading is not a second opinion: the fights are [MapPlayArmyOrdersPick]'s
## own — the call THE CROWN'S ARMY prints, worded off the published land policy —
## narrowed to the two reasons the rules fight on (a storm into ground the crown
## does not hold, a relief onto its own land holding a hostile host), and the pool
## is [CommandLedger]'s own count. Binding draws one commander per attacking army
## and leaves the rest on the leader's fallback medals, so the sheet can name no
## commander the battle would not spend.
##
## The line names the fights, not only their number: each standard by the sheet's
## own title and the ground its order storms or relieves, three named and the rest
## counted (DR-20261122-22), so a crown reads which of her hosts the staff would
## lead rather than a bare count.
##
## A reading only: nothing here splits a standard, marches a regiment, binds a
## commander or rolls a die, and the crown still presses her own order
## (REQ-P3-03, REQ-P5-06).


## The pass gives no host a march into hostile ground: the gate the sheet names
## instead of a clause it cannot print.
const NO_HOST_LINE: String = "the court would send no host into battle this turn"


## The sheet's sentence: the pick's own line, capitalised and closed — the one
## wording every pick surface prints (MapPlayPickProse; REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, snapshot: Dictionary = {}) -> String:
	return MapPlayPickProse.sentence(String(pick(play, snapshot).get("line", "")))


## The sheet's pick as it prints it: `{hosts, held, led, fallback, line}`. Empty
## when the session runs no planner for the crown, an observer session, a decided
## campaign, a session with no army layer or a walk the land pass cannot read.
static func pick(play: PlaySession, snapshot: Dictionary = {}) -> Dictionary:
	if not MapPlayPickProse.crown_ready(play):
		return {}
	if play.army_layer == null:
		return {}
	var orders: Dictionary = MapPlayArmyOrdersPick.pick(play)
	if orders.is_empty():
		return {}
	var data: Dictionary = snapshot if not snapshot.is_empty() else MapPlayCommand.snapshot(play)
	return from(orders, data)


## The pick the sheet prints, from the orders the land pass would give and the
## pool the sheet already painted: pure, so a suite drives it without a session.
## The fights are named by the clause THE CROWN'S ARMY prints for each standard,
## an exact repeat collapsed into the clause the line already names — so a count of
## hosts stays a count however many standards stand on the same ground
## (DR-20261122-22).
static func from(orders: Dictionary, data: Dictionary) -> Dictionary:
	var fought: Array = orders.get("armies", []) as Array
	var unique: Dictionary = MapPlayPickProse.unique_clauses(clauses_of(fought))
	var clauses: Array[String] = []
	clauses.assign(unique.get("clauses", []))
	var fallback: Dictionary = data.get("fallback", {}) as Dictionary
	return of(
		hosts_of(fought),
		int(data.get("held", 0)),
		int(fallback.get("attack", 0)),
		clauses,
		int(unique.get("extra", 0))
	)


## The pick, worded off the hosts the pass would lead and the pool the crown
## holds: pure, so a sheet and its suite drive it without a session. `clauses` are
## the fights the line names; `extra` counts repeats a clause already stood for.
static func of(
	hosts: int, held: int, fallback: int, clauses: Array[String] = [], extra: int = 0
) -> Dictionary:
	var pool: int = maxi(held, 0)
	return {
		"hosts": hosts,
		"held": pool,
		"led": clampi(pool, 0, hosts),
		"fallback": fallback,
		"line": pick_line(hosts, pool, fallback, clauses, extra),
	}


## "the court would send 2 hosts into battle — each led by a commander", or, when
## the pool runs short, "… its 1 commander would lead 1, and the last host would
## fight on the leader's own 2 medals". The fights are named between the count and
## the commanders' answer — `the field army at Tucapel to storm Cádiz`, three and
## the rest counted — so the crown reads which hosts the staff would lead. A plan
## that fights nothing names the gate.
static func pick_line(
	hosts: int, held: int, fallback: int, clauses: Array[String] = [], extra: int = 0
) -> String:
	if hosts <= 0:
		return NO_HOST_LINE
	var host_word: String = "host" if hosts == 1 else "hosts"
	var count: String = "the court would send %d %s into battle" % [hosts, host_word]
	var named: String = MapPlayPickProse.capped(clauses, MapPlayPickProse.NAMED_LIMIT, extra)
	var fights: String = "" if named.is_empty() else " — %s" % named
	var pool: int = maxi(held, 0)
	if pool >= hosts:
		var each: String = "it is led" if hosts == 1 else "each led"
		return "%s%s — %s by a commander" % [count, fights, each]
	var left: int = hosts - pool
	if pool <= 0:
		var none: String = "it would fight" if hosts == 1 else "they would fight"
		if named.is_empty():
			return "the court would send %d %s into battle with no commander free — %s %s" % [
				hosts, host_word, none, medal_phrase(fallback)
			]
		return "%s — %s — with no commander free, %s %s" % [
			count, named, none, medal_phrase(fallback)
		]
	var tail: String = (
		"the last host would fight" if left == 1 else "the last %d hosts would fight" % left
	)
	return "%s%s — its %d commander%s would lead %d, and %s %s" % [
		count,
		fights,
		pool,
		"" if pool == 1 else "s",
		pool,
		tail,
		medal_phrase(fallback),
	]


## What a host beyond the pool fights on: the leader's own medals, read per side
## by [CommandLedger.fallback] (wiki: military-generals § Assignment).
static func medal_phrase(medals: int) -> String:
	if medals <= 0:
		return "with no medal at all"
	if medals == 1:
		return "on the leader's own 1 medal"
	return "on the leader's own %d medals" % medals


## The fights the land pass would start, in the pass's own order: one per march it
## words as a storm into ground the crown does not hold or a relief onto its own
## land holding a hostile host. A frontier advance, a rotation home, a walk home
## and the seat's split start no battle, so they spend no commander (wiki:
## military-generals § Assignment — one general per attacking army).
static func fights_of(armies: Array) -> Array[Dictionary]:
	var fights: Array[Dictionary] = []
	for raw: Variant in armies:
		var entry: Dictionary = raw
		if _fights(entry):
			fights.append(entry)
	return fights


## How many of those marches fight.
static func hosts_of(armies: Array) -> int:
	return fights_of(armies).size()


## One fight's own clause, in the words THE CROWN'S ARMY prints for that standard:
## `the field army at Tucapel to storm Cádiz`. Empty when the entry carries no
## standard or no order, so the line never promises a march it cannot word.
static func fight_clause(entry: Dictionary) -> String:
	var standard: String = String(entry.get("standard", ""))
	var order: String = String(entry.get("order", ""))
	if standard.is_empty() or order.is_empty():
		return ""
	return "%s %s" % [standard, order]


## The fights as clauses the line names, one per fight and in the pass's own order.
static func clauses_of(armies: Array) -> Array[String]:
	var clauses: Array[String] = []
	for entry: Dictionary in fights_of(armies):
		var clause: String = fight_clause(entry)
		if not clause.is_empty():
			clauses.append(clause)
	return clauses


## Whether one order entry is a march that starts a battle.
static func _fights(entry: Dictionary) -> bool:
	if String(entry.get("kind", "")) != MapPlayArmyPick.KIND_MARCH:
		return false
	var why: String = String(entry.get("why", ""))
	return why == MapPlayArmyPick.WHY_STORM or why == MapPlayArmyPick.WHY_RELIEF