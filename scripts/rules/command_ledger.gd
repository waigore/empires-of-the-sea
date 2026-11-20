class_name CommandLedger
extends RefCounted
## The crown's commanders, read as a pool (wiki: military-generals § Generals,
## § Count and tech-gated cap, § Medals; DR-20261115-11).
##
## Generals are abstract: no province, no marker, and the pool always holds the
## faction's tech-gated cap. The army dossier printed the pool as one line of
## prose, so a crown could not read how many commanders it holds, what a medal
## buys in the field, or which study raises the cap next. This projection reads
## that state as a ledger.
##
## Pure: it reads [GeneralRoster], the tech table and the leader's own fallback,
## never a node (REQ-P3-03). No figure is recomputed — the line a medal adds is
## [ArmyModifiers.deployment_limit]'s own, the morale share is its aura's, and
## the initiative is its medal weight — so a row can never name a number the
## battle would not use (REQ-P2-03).

## The cap rungs in the order the wiki publishes them (military-generals
## § Count and tech-gated cap). Two rungs share cap 3 and do not stack, so the
## road names both and the cap reads the highest rung taken.
const ROAD: Array[Dictionary] = [
	{"tech": "organised_regiments", "cap": 2},
	{"tech": "national_bureaucracy", "cap": 3},
	{"tech": "improved_infantry_tactics", "cap": 3},
	{"tech": "nationalism", "cap": 4},
]


## The whole reading: the pool, the cap it answers to, the road to the next
## commander and what a crown with none free fights on.
static func snapshot(
	roster: GeneralRoster, owner: int, tech_unlocked: Dictionary, leader_key: String
) -> Dictionary:
	var rows: Array[Dictionary] = []
	if roster != null:
		# Read the stored pool, never `pool()`: a reading must not spawn or
		# christen a commander the turn has not (REQ-P2-03).
		var stored: Array = roster.pools.get(owner, []) as Array
		for raw: Variant in stored:
			var general: Dictionary = raw
			var medals: int = int(general.get("medals", 0))
			rows.append({
				"id": String(general.get("id", "")),
				"name": String(general.get("name", "")),
				"medals": medals,
				"effects": effects(medals),
				"full": medals >= GeneralRoster.MAX_MEDALS,
			})
	var cap: int = GeneralRoster.cap_for(tech_unlocked)
	return {
		"owner": owner,
		"held": rows.size(),
		"cap": cap,
		"above_cap": rows.size() > cap,
		"rows": rows,
		"road": road(tech_unlocked),
		"next": next_rung(tech_unlocked, cap),
		"ceiling": ceiling(),
		"fallback": fallback(leader_key),
		"leader": leader_key,
	}


## What one commander's medals buy in the field (wiki: military-generals
## § Medal effects): the line he adds, the morale aura and the initiative.
## Every figure is the combat module's own, read at the same clamp.
static func effects(medals: int) -> Dictionary:
	var clamped: int = clampi(medals, 0, GeneralRoster.MAX_MEDALS)
	return {
		"line": ArmyModifiers.deployment_limit(clamped, false) - ArmyModifiers.BASE_DEPLOYMENT,
		"morale_pct": roundi((ArmyModifiers.medal_aura(clamped) - 1.0) * 100.0),
		"initiative": roundi(float(clamped) * ArmyModifiers.W_MEDAL),
	}


## The cap rungs with the study each waits on, in the wiki's order.
static func road(tech_unlocked: Dictionary) -> Array[Dictionary]:
	var rungs: Array[Dictionary] = []
	for rung: Dictionary in ROAD:
		var tech: String = String(rung["tech"])
		rungs.append({
			"tech": tech,
			"name": TechCatalog.display_name(tech),
			"cap": int(rung["cap"]),
			"unlocked": bool(tech_unlocked.get(tech, false)),
		})
	return rungs


## The next study that raises the cap above `cap`, or empty at the ceiling.
## A rung already taken, or one that would not raise the cap, is no road.
static func next_rung(tech_unlocked: Dictionary, cap: int) -> Dictionary:
	for rung: Dictionary in road(tech_unlocked):
		if bool(rung["unlocked"]) or int(rung["cap"]) <= cap:
			continue
		return rung
	return {}


## The highest cap the published rungs reach.
static func ceiling() -> int:
	var top: int = GeneralRoster.BASE_CAP
	for rung: Dictionary in ROAD:
		top = maxi(top, int(rung["cap"]))
	return top


## What a crown with no free commander fights on: its leader's own medals, read
## per side because a leader's land bonus is published per side
## (wiki: military-generals § Assignment; leader-bonuses § Bonus Table).
static func fallback(leader_key: String) -> Dictionary:
	return {
		"attack": ArmyModifiers.fallback_medals(leader_key, false),
		"defend": ArmyModifiers.fallback_medals(leader_key, true),
	}


## The count line: how many commanders the crown holds against its cap, and the
## study that raises it next (REQ-P5-05).
static func summary(data: Dictionary) -> String:
	var held: int = int(data.get("held", 0))
	var cap: int = int(data.get("cap", 0))
	var text: String = "%d of %d commander%s" % [held, cap, "" if cap == 1 else "s"]
	if bool(data.get("above_cap", false)):
		text = "%d commanders (cap %d)" % [held, cap]
	var next: Dictionary = data.get("next", {}) as Dictionary
	if next.is_empty():
		return text + " · the ceiling is %d" % int(data.get("ceiling", cap))
	return text + " · next: %s (%d)" % [String(next["name"]), int(next["cap"])]


## What one medal is worth, in the field's own words (wiki: § Medal effects).
static func medal_line() -> String:
	var one: Dictionary = effects(1)
	return (
		"Each medal: +%d regiment in the line, +%d%% morale, +%d initiative. "
		+ "Four is the most one commander earns."
	) % [int(one["line"]), int(one["morale_pct"]), int(one["initiative"])]


## The fallback line: the medals a crown fights on when no commander is free.
## It names the condition, never the crown's standing — a pool of three reads
## "no free commander" only mid-commitment, and the sheet must not claim it as
## the state it is in (the roll above already counts the pool it holds).
static func fallback_line(data: Dictionary) -> String:
	var fallback: Dictionary = data.get("fallback", {}) as Dictionary
	var attack: int = int(fallback.get("attack", 0))
	var defend: int = int(fallback.get("defend", 0))
	if attack == defend:
		return "With no commander free, the court fights on the leader's own %d medal%s." % [
			attack, "" if attack == 1 else "s"
		]
	return (
		"With no commander free, the court fights on the leader's own %d medals "
		+ "attacking, %d defending."
	) % [attack, defend]
