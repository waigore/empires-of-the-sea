class_name GeneralRoster
extends RefCounted
## Per-faction general pool (wiki: military-generals § Generals).
## Generals are abstract: no province, no map marker. The pool always holds the
## faction's cap (Great Powers only), grows when the cap-raising techs land and
## never loses a general. Binding to armies is per Combat phase and lives in
## GeneralBinding, not here.

const BASE_CAP: int = 1
const MAX_MEDALS: int = 4
## Cap floors from researched techs; the highest applicable floor wins
## (national_bureaucracy and improved_infantry_tactics do not stack).
const CAP_TECHS: Dictionary = {
	"organised_regiments": 2,
	"national_bureaucracy": 3,
	"improved_infantry_tactics": 3,
	"nationalism": 4,
}

## owner -> Array[Dictionary] of {"id": String, "medals": int}
var pools: Dictionary = {}


static func cap_for(tech_unlocked: Dictionary) -> int:
	var cap: int = BASE_CAP
	for tech: Variant in CAP_TECHS.keys():
		if bool(tech_unlocked.get(String(tech), false)):
			cap = maxi(cap, int(CAP_TECHS[tech]))
	return cap


## The faction's roster, created at the opening cap on first use.
func pool(owner: int) -> Array[Dictionary]:
	if not pools.has(owner):
		var fresh: Array[Dictionary] = []
		pools[owner] = fresh
		sync(owner, {})
	var stored: Array[Dictionary] = []
	stored.assign(pools[owner])
	return stored


## Spawns generals until the roster meets the tech-gated cap; never trims an
## above-cap roster (wiki: persistence and load reconciliation).
func sync(owner: int, tech_unlocked: Dictionary) -> int:
	var stored: Array[Dictionary] = []
	stored.assign(pools.get(owner, []))
	var wanted: int = cap_for(tech_unlocked)
	while stored.size() < wanted:
		stored.append({"id": "general_%d" % (stored.size() + 1), "medals": 0})
	pools[owner] = stored
	return stored.size()


func count(owner: int) -> int:
	return pool(owner).size()


## Reconciles every Great Power roster to its own researched cap. The ledger
## keeps the human's pool in step, but a rival's has no such driver: without
## this, a crown that studied organised_regiments still fields one commander and
## its second attacking army falls back to leader medals (wiki:
## military-generals § Count and tech-gated cap, § Assignment).
## `tech_by_faction` is the same per-crown map combat modifiers read, so no
## court can borrow another's generals. Returns how many commanders were
## spawned; minor nations and tribes never hold a pool.
func reconcile(tech_by_faction: Dictionary) -> int:
	var spawned: int = 0
	for raw: Variant in tech_by_faction.keys():
		var owner: int = int(raw)
		if FactionCatalog.type_of(owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		var unlocked: Variant = tech_by_faction[raw]
		if typeof(unlocked) != TYPE_DICTIONARY:
			continue
		var before: int = (pools.get(owner, []) as Array).size()
		sync(owner, unlocked as Dictionary)
		var after: int = (pools.get(owner, []) as Array).size()
		spawned += after - before
	return spawned


func ids(owner: int) -> Array[String]:
	var result: Array[String] = []
	for general: Dictionary in pool(owner):
		result.append(String(general["id"]))
	return result


func medals(owner: int, general_id: String) -> int:
	for general: Dictionary in pool(owner):
		if String(general["id"]) == general_id:
			return int(general["medals"])
	return 0


## A winning general gains one medal, capped at four (wiki: § Medals).
func award(owner: int, general_id: String) -> int:
	var stored: Array[Dictionary] = []
	stored.assign(pools.get(owner, []))
	for general: Dictionary in stored:
		if String(general["id"]) != general_id:
			continue
		general["medals"] = mini(int(general["medals"]) + 1, MAX_MEDALS)
		pools[owner] = stored
		return int(general["medals"])
	return 0


func label(owner: int, general_id: String) -> String:
	var index: int = ids(owner).find(general_id)
	if index < 0:
		return ""
	return "General %d" % (index + 1)


## Plain data for local saves: every pool with its earned medals. The pool size
## is the persisted effective cap, so a load rebuilds the roster exactly and
## medals never decrease (wiki: military-generals § Persistence and load
## reconciliation, § Medals).
func to_dict() -> Dictionary:
	var saved: Dictionary = {}
	for raw: Variant in pools.keys():
		var owner: int = int(raw)
		var entries: Array[Dictionary] = []
		for general: Dictionary in pool(owner):
			entries.append({
				"id": String(general["id"]),
				"medals": clampi(int(general["medals"]), 0, MAX_MEDALS),
			})
		saved[owner] = entries
	return {"pools": saved}


static func from_dict(data: Dictionary) -> GeneralRoster:
	var roster := GeneralRoster.new()
	var saved: Variant = data.get("pools", {})
	if typeof(saved) != TYPE_DICTIONARY:
		return roster
	for raw: Variant in saved.keys():
		var entries: Variant = saved[raw]
		if typeof(entries) != TYPE_ARRAY:
			continue
		var stored: Array[Dictionary] = []
		for entry: Variant in entries:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var general: Dictionary = entry
			var general_id: String = String(general.get("id", ""))
			if general_id.is_empty():
				continue
			stored.append({
				"id": general_id,
				"medals": clampi(int(general.get("medals", 0)), 0, MAX_MEDALS),
			})
		roster.pools[int(raw)] = stored
	return roster


## "2 generals · 3 medals" for the army dossier.
func summary(owner: int) -> String:
	var roster: Array[Dictionary] = pool(owner)
	if roster.is_empty():
		return "No generals"
	var medals: int = 0
	for general: Dictionary in roster:
		medals += int(general["medals"])
	var plural: String = "" if roster.size() == 1 else "s"
	return "%d general%s · %d medal%s" % [roster.size(), plural, medals, "" if medals == 1 else "s"]
