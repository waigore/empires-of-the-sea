class_name LeaderCatalog
extends RefCounted
## Great Power leaders: who rules each crown, and the land-combat bonus that
## key carries (wiki: leader-bonuses, naming § Naming Model).
## Pure data: game setup, the save codec and combat modifiers read the same
## roster, so a leaderKey cannot mean two different things (REQ-P2-01, REQ-P3-03).

## Neutral key fielded when a crown names no leader: no combat bonus, neutral
## AI archetype (wiki: leader-bonuses § Bonus Table, `reserve`/default row).
const DEFAULT_KEY: String = "reserve"

## leaderKey -> melee multiplier (wiki: leader-bonuses § Bonus Table; DR-20261111-24).
## Every Great Power's leader carries one, so no crown fields a leader with no
## land bonus; the values follow the captain's reputation and reuse the fallback
## medal bands (`ArmyModifiers.fallback_medals`). This is the design source of
## truth; a ruleset loader is deferred.
const MULTIPLIERS: Dictionary = {
	"napoleon": 1.25,
	"gustavus": 1.20,
	"isabella": 1.15,
	"victoria": 1.10,
	"de_ruyter": 1.10,
	"henry": 1.05,
	## Prussia's key is kept for variant ids from the seed rules (`prussia_frederick_leader`);
	## no shipped crown fields it.
	"frederick": 1.15,
}

## Leader variants per Great Power, default first. One variant ships today;
## the list shape lets the setup screen offer more when the wiki publishes them
## (naming § Naming Model: `leaderVariants`, first is default).
const VARIANTS: Array[Dictionary] = [
	{"faction": 0, "key": "isabella", "name": "Isabella I"},
	{"faction": 1, "key": "victoria", "name": "Victoria"},
	{"faction": 2, "key": "napoleon", "name": "Napoleon"},
	{"faction": 3, "key": "henry", "name": "Henry the Navigator"},
	{"faction": 4, "key": "de_ruyter", "name": "Michiel de Ruyter"},
	{"faction": 5, "key": "gustavus", "name": "Gustavus Adolphus"},
]


## Leader choices for one crown, default first; empty for Minors and Tribes.
static func variants_for(faction: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in VARIANTS:
		if int(entry["faction"]) == faction:
			result.append(entry)
	return result


static func keys_for(faction: int) -> Array[String]:
	var keys: Array[String] = []
	for entry: Dictionary in variants_for(faction):
		keys.append(String(entry["key"]))
	return keys


## The crown's configured leader: first variant, or the neutral reserve.
static func default_key(faction: int) -> String:
	var keys: Array[String] = keys_for(faction)
	return keys[0] if not keys.is_empty() else DEFAULT_KEY


## A requested key is honoured only when the crown fields that variant;
## otherwise the crown keeps its configured leader.
static func resolve_key(faction: int, wanted: String) -> String:
	if keys_for(faction).has(wanted):
		return wanted
	return default_key(faction)


## Display name for a leaderKey ("Napoleon"); unknown keys read as Reserve.
static func label(leader_key: String) -> String:
	for entry: Dictionary in VARIANTS:
		if String(entry["key"]) == leader_key:
			return String(entry["name"])
	return "Reserve"


## Every leaderKey the roster knows, including the neutral reserve.
static func known_keys() -> Array[String]:
	var keys: Array[String] = []
	for entry: Dictionary in VARIANTS:
		keys.append(String(entry["key"]))
	keys.append(DEFAULT_KEY)
	return keys


## Land-strength multiplier for a leaderKey. Exact key first, then a
## case-insensitive substring match for variant ids such as
## `france_napoleon_leader`; anything else gets no bonus (wiki: leader-bonuses
## § LeaderKey format and matching).
static func multiplier_for(leader_key: String) -> float:
	var key: String = leader_key.strip_edges().to_lower()
	if key.is_empty():
		return 1.0
	if MULTIPLIERS.has(key):
		return float(MULTIPLIERS[key])
	var names: Array = MULTIPLIERS.keys()
	names.sort()
	for known: Variant in names:
		if key.contains(String(known)):
			return float(MULTIPLIERS[known])
	return 1.0


## Signed percentage for UI copy: +25 for Napoleon, 0 for the reserve.
static func bonus_percent(leader_key: String) -> int:
	return int(round((multiplier_for(leader_key) - 1.0) * 100.0))


static func bonus_label(leader_key: String) -> String:
	var percent: int = bonus_percent(leader_key)
	if percent == 0:
		return "no land-combat bonus"
	return "+%d%% land-combat strength" % percent


## Faction -> leaderKey for every Great Power. The human slot takes the chosen
## variant (or its configured default); AI crowns take their config leader
## (wiki: leader-bonuses § Leader Selection).
static func roster(player_faction: int = -1, player_key: String = "") -> Dictionary:
	var result: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		result[faction] = default_key(faction)
	if result.has(player_faction):
		result[player_faction] = resolve_key(player_faction, player_key)
	return result


## Rehydrates a saved Faction -> leaderKey map: missing crowns get their
## configured leader, unknown keys are dropped so a stale save cannot invent a
## bonus. Never changes a key mid-game (wiki: leader-bonuses).
static func from_saved(raw: Variant) -> Dictionary:
	var result: Dictionary = roster()
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	var saved: Dictionary = raw
	var known: Array[String] = known_keys()
	for entry: Variant in saved.keys():
		var faction: int = int(entry)
		if not result.has(faction):
			continue
		var key: String = String(saved[entry])
		if known.has(key):
			result[faction] = key
	return result
