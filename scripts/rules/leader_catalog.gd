class_name LeaderCatalog
extends RefCounted
## Great Power leaders: who rules each crown, and the one primary bonus that
## key carries (wiki: leader-bonuses, DR-20261113-18).
## Pure data: game setup, the save codec, combat, naval, fog, tribe contact and
## research resolvers read the same table, so a leaderKey cannot mean two
## different things (REQ-P2-01, REQ-P3-03).
##
## One primary bonus per key: a leader never stacks a second domain. Land melee
## is published per side (Napoleon both, Gustavus attacking, Frederick
## defending); the remaining crowns each own one non-land domain.

## Neutral key fielded when a crown names no leader: no bonus, neutral AI
## archetype (wiki: leader-bonuses § Bonus Table, `reserve`/default row).
const DEFAULT_KEY: String = "reserve"

## leaderKey -> land multiplier per side (wiki: leader-bonuses § Bonus Table).
## `attack` and `defend` are the published factors; a side this key does not
## favour reads 1.0.
const LAND_BONUSES: Dictionary = {
	"napoleon": {"attack": 1.25, "defend": 1.25},
	"gustavus": {"attack": 1.15, "defend": 1.0},
	"frederick": {"attack": 1.0, "defend": 1.15},
}

## Naval keys: only a key that publishes a naval row alters sea strength
## (wiki: leader-bonuses § Bonus Table — de Ruyter's +15%).
const NAVAL_MULTIPLIER: float = 1.15
const NAVAL_KEYS: Array[String] = ["de_ruyter"]

## GP–Tribe first contact opens at this score instead of the 50.0 equilibrium
## (wiki: leader-bonuses § Bonus Table — Isabella).
const FIRST_CONTACT_SCORE: float = 60.0
const FIRST_CONTACT_KEYS: Array[String] = ["isabella"]

## Extra orthogonal land rings a ship reveal charts, beyond the strict coastal
## ring (wiki: leader-bonuses § Bonus Table — Henry).
const EXTRA_COASTAL_RINGS: int = 1
const COASTAL_RING_KEYS: Array[String] = ["henry"]

## Research funding RP multiplier, applied to the base funding RP before the
## spy boost (wiki: leader-bonuses § Bonus Table — Victoria).
const FUNDING_MULTIPLIER: float = 1.15
const FUNDING_KEYS: Array[String] = ["victoria"]

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


## Land-strength multiplier for a leaderKey on one side of a battle. Exact key
## first, then a case-insensitive substring match for variant ids such as
## `france_napoleon_leader`; anything else gets no bonus (wiki: leader-bonuses
## § LeaderKey format and matching).
static func land_multiplier(leader_key: String, defending: bool) -> float:
	var known: String = matched_key(leader_key, LAND_BONUSES.keys())
	if known.is_empty():
		return 1.0
	var row: Dictionary = LAND_BONUSES[known]
	return float(row["defend" if defending else "attack"])


## Naval-strength multiplier: the one published naval key, every other 1.0
## (wiki: leader-bonuses § When Bonuses Apply — leaders without a row in a
## domain do not modify that domain).
static func naval_multiplier(leader_key: String) -> float:
	if matched_key(leader_key, NAVAL_KEYS).is_empty():
		return 1.0
	return NAVAL_MULTIPLIER


## Score a GP–Tribe relation opens on for this crown: 60.0 for the one key that
## publishes the diplomacy lean, else the Neutral equilibrium (wiki:
## leader-bonuses § Bonus Table).
static func first_contact_score(leader_key: String) -> float:
	if matched_key(leader_key, FIRST_CONTACT_KEYS).is_empty():
		return DiplomacyCatalog.INITIAL_SCORE
	return FIRST_CONTACT_SCORE


## Extra orthogonal land rings this crown's ship reveal charts, on top of the
## published strict coastal ring (wiki: leader-bonuses § Bonus Table).
static func coastal_rings(leader_key: String) -> int:
	if matched_key(leader_key, COASTAL_RING_KEYS).is_empty():
		return 0
	return EXTRA_COASTAL_RINGS


## RP multiplier on a slot's base funding, applied before the spy boost
## (wiki: leader-bonuses § Bonus Table).
static func funding_multiplier(leader_key: String) -> float:
	if matched_key(leader_key, FUNDING_KEYS).is_empty():
		return 1.0
	return FUNDING_MULTIPLIER


## Every leaderKey the bonus table publishes, fielded today or not: Frederick is
## a table / future variant, so UI matching must still name his effect
## (wiki: leader-bonuses § Bonus Table).
static func published_keys() -> Array[String]:
	var keys: Array[String] = []
	var groups: Array = [
		LAND_BONUSES.keys(), NAVAL_KEYS, FIRST_CONTACT_KEYS, COASTAL_RING_KEYS,
		FUNDING_KEYS,
	]
	for group: Variant in groups:
		for key: Variant in group as Array:
			if not keys.has(String(key)):
				keys.append(String(key))
	return keys


## The published key this leaderKey names, or "". Exact match wins; otherwise
## the first known key (in id order) that the string contains (wiki:
## leader-bonuses § LeaderKey format and matching).
static func matched_key(leader_key: String, known_keys: Array) -> String:
	var key: String = leader_key.strip_edges().to_lower()
	if key.is_empty():
		return ""
	if known_keys.has(key):
		return key
	var names: Array = known_keys.duplicate()
	names.sort()
	for known: Variant in names:
		if key.contains(String(known)):
			return String(known)
	return ""


## Signed percentage for UI copy: +25 for Napoleon's land, 0 for the reserve.
static func land_percent(leader_key: String, defending: bool = false) -> int:
	return int(round((land_multiplier(leader_key, defending) - 1.0) * 100.0))


## The effect the key publishes, in the words setup and the HUD show. A key
## with no row reads "no bonus" — never "no land-combat bonus" (wiki:
## leader-bonuses § Acceptance criteria — UI).
static func bonus_label(leader_key: String) -> String:
	var known: String = matched_key(leader_key, published_keys())
	match known:
		"napoleon":
			return "+25% land-combat strength"
		"gustavus":
			return "+15% land-combat strength when attacking"
		"frederick":
			return "+15% land-combat strength when defending"
		"isabella":
			return "Tribe first contact opens at relation 60"
		"henry":
			return "ship reveal charts one further coastal land ring"
		"de_ruyter":
			return "+15% naval-combat strength"
		"victoria":
			return "+15% research funding points"
	return "no bonus"


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
