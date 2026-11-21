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
	var fallback: Dictionary = data.get("fallback", {}) as Dictionary
	return of(
		hosts_of(orders.get("armies", [])),
		int(data.get("held", 0)),
		int(fallback.get("attack", 0))
	)


## The pick, worded off the hosts the pass would lead and the pool the crown
## holds: pure, so a sheet and its suite drive it without a session.
static func of(hosts: int, held: int, fallback: int) -> Dictionary:
	var pool: int = maxi(held, 0)
	return {
		"hosts": hosts,
		"held": pool,
		"led": clampi(pool, 0, hosts),
		"fallback": fallback,
		"line": pick_line(hosts, pool, fallback),
	}


## "the court would send 2 hosts into battle — each led by a commander", or, when
## the pool runs short, "… its 1 commander would lead 1, and the last host would
## fight on the leader's own 2 medals". A plan that fights nothing names the gate.
static func pick_line(hosts: int, held: int, fallback: int) -> String:
	if hosts <= 0:
		return NO_HOST_LINE
	var host_word: String = "host" if hosts == 1 else "hosts"
	var pool: int = maxi(held, 0)
	if pool >= hosts:
		var each: String = "it is led" if hosts == 1 else "each led"
		return "the court would send %d %s into battle — %s by a commander" % [
			hosts, host_word, each
		]
	var left: int = hosts - pool
	if pool <= 0:
		var none: String = "it would fight" if hosts == 1 else "they would fight"
		return "the court would send %d %s into battle with no commander free — %s %s" % [
			hosts, host_word, none, medal_phrase(fallback)
		]
	var tail: String = (
		"the last host would fight" if left == 1 else "the last %d hosts would fight" % left
	)
	return "the court would send %d %s into battle — its %d commander%s would lead %d, and %s %s" % [
		hosts,
		host_word,
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


## The fights the land pass would start: one per march it words as a storm into
## ground the crown does not hold or a relief onto its own land holding a hostile
## host. A frontier advance, a rotation home, a walk home and the seat's split
## start no battle, so they spend no commander (wiki: military-generals
## § Assignment — one general per attacking army).
static func hosts_of(armies: Array) -> int:
	var count: int = 0
	for raw: Variant in armies:
		var entry: Dictionary = raw
		if String(entry.get("kind", "")) != MapPlayArmyPick.KIND_MARCH:
			continue
		var why: String = String(entry.get("why", ""))
		if why == MapPlayArmyPick.WHY_STORM or why == MapPlayArmyPick.WHY_RELIEF:
			count += 1
	return count