class_name AdvancedStart
extends RefCounted
## Advanced start presets: begin a campaign at turn 50 (~1598) or turn 100
## (~1698) with Great Powers already progressed in tech, economy, soldiery and
## New World presence (wiki: advanced-starts). Pure data + planning helpers so
## setup, the bootstrap pass and tests share one table (REQ-P3-03).
##
## DR-20261111-01 adapts the wiki's CT-profile gate to this product: a preset
## applies to any generated world, every fraction is computed on the actual
## map, and only state the product models is seeded (per-player fog exists for
## the human court; rival fog exploration stays deferred).

const NONE: String = "none"
const TURNS50: String = "turns50"
const TURNS100: String = "turns100"
const IDS: Array[String] = [NONE, TURNS50, TURNS100]

const LABELS: Dictionary = {
	NONE: "Turn 0 — 1500",
	TURNS50: "Turn 50 — 1598",
	TURNS100: "Turn 100 — 1698",
}

## Fixed technology lists, identical for every Great Power (wiki § Fixed
## technology lists). Prerequisites hold inside each list.
const TECHS_50: Array[String] = [
	"crop_rotation", "saw_mill", "land_enclosure", "mine_engineering",
	"iron_mining", "sheep_ranching", "wind_saw_mill", "road_construction",
	"printing_press", "money_lending", "diplomatic_expertise",
	"merchant_companies", "superior_hull_design", "navigation", "convoying",
	"improved_sail_design", "organised_regiments", "improved_iron_weapons",
	"recruit_steppe_horsemen", "animal_husbandry",
	"improved_cavalry_tactics", "discovery_of_sugar", "discovery_of_tobacco",
]

const TECHS_100_ADDED: Array[String] = [
	"copper_and_tin_mining", "coal_mining", "seed_drill",
	"square_set_timbering", "steam_in_mining", "early_steam_engine",
	"sugar_refining", "cigar_production", "apprentice_workers",
	"national_bureaucracy", "privateering_companies", "large_hulls",
	"improved_infantry_tactics", "crucible_process", "hussars",
	"horse_artillery", "siege_engineering", "weapon_craftsmanship",
	"discovery_of_cotton", "discovery_of_furs", "discovery_of_spices",
	"discovery_of_gold_or_silver",
]

## Tier tables (wiki § Tier tables). `civilians` is the crown's total roster;
## `nw_owned` provinces per Great Power; shares are fractions of the real map.
const TIERS: Dictionary = {
	TURNS50:
	{
		"turn": 50,
		"treasury": 20000,
		"peasants": 16,
		"apprentices": 0,
		"regiments": 6,
		"cargo_ships": 1,
		"embassies": false,
		"nw_owned": 0,
		"nw_reveal": 0.625,
		"prospect": 0.5,
		"develop": 0.25,
		"civilians":
		{"explorer": 3, "builder": 3, "engineer": 2, "spy": 1, "merchant": 1},
	},
	TURNS100:
	{
		"turn": 100,
		"treasury": 40000,
		"peasants": 16,
		"apprentices": 4,
		"regiments": 12,
		"cargo_ships": 6,
		"embassies": true,
		"nw_owned": 6,
		"nw_reveal": 1.0,
		"prospect": 0.75,
		"develop": 0.5,
		"civilians":
		{
			"explorer": 4,
			"builder": 4,
			"engineer": 3,
			"spy": 2,
			"merchant": 2,
			"rail_builder": 1,
		},
	},
}


## Canonical id: an unknown or empty value is a turn-0 campaign.
static func normalize(id: String) -> String:
	var key: String = id.strip_edges().to_lower()
	return key if TIERS.has(key) else NONE


static func active(id: String) -> bool:
	return TIERS.has(normalize(id))


## Tier row for an active preset; empty for turn 0.
static func entry(id: String) -> Dictionary:
	return TIERS.get(normalize(id), {})


static func label(id: String) -> String:
	return String(LABELS.get(normalize(id), LABELS[NONE]))


static func turn(id: String) -> int:
	return int(entry(id).get("turn", 1))


## The tier's fixed tech list (23 at 50 turns, 45 at 100).
static func tech_ids(id: String) -> Array[String]:
	var techs: Array[String] = []
	var key: String = normalize(id)
	if key == NONE:
		return techs
	techs.append_array(TECHS_50)
	if key == TURNS100:
		techs.append_array(TECHS_100_ADDED)
	return techs


## Unlocked-tech table for order maths and catalogs.
static func tech_table(id: String) -> Dictionary:
	var table: Dictionary = {}
	for tech: String in tech_ids(id):
		table[tech] = true
	return table


## Crown roster totals per civilian type (wiki § Civilians column).
static func civilians(id: String) -> Dictionary:
	var raw: Variant = entry(id).get("civilians", {})
	return (raw as Dictionary).duplicate() if raw is Dictionary else {}


static func regiments(id: String) -> int:
	return int(entry(id).get("regiments", 0))


static func cargo_ships(id: String) -> int:
	return int(entry(id).get("cargo_ships", 0))


static func nw_owned(id: String) -> int:
	return int(entry(id).get("nw_owned", 0))


static func nw_reveal(id: String) -> float:
	return float(entry(id).get("nw_reveal", 0.0))


static func prospect_share(id: String) -> float:
	return float(entry(id).get("prospect", 0.0))


static func develop_share(id: String) -> float:
	return float(entry(id).get("develop", 0.0))


static func embassies(id: String) -> bool:
	return bool(entry(id).get("embassies", false))


## Balanced regiment roster of the tier's best buildable type per branch
## (infantry, cavalry, artillery), highest era then FPN+FPM, id as tie-break
## (wiki § Bootstrap step 5).
static func regiment_types(id: String) -> Array[String]:
	var types: Array[String] = []
	var count: int = regiments(id)
	if count <= 0:
		return types
	var tech: Dictionary = tech_table(id)
	var branches: Array[String] = ["infantry", "cavalry", "artillery"]
	var best: Array[String] = []
	for branch: String in branches:
		best.append(_best_regiment(branch, tech))
	var index: int = 0
	while types.size() < count:
		var type_id: String = best[index % best.size()]
		if type_id.is_empty():
			index += 1
			continue
		types.append(type_id)
		index += 1
	return types


static func _best_regiment(branch: String, tech: Dictionary) -> String:
	var best_id: String = ""
	var best_era: int = -1
	var best_sum: int = -1
	for type_id: String in RegimentCatalog.ids():
		if _branch_of(type_id) != branch:
			continue
		if not RegimentEconomy.buildable(type_id, tech):
			continue
		var row: Dictionary = RegimentCatalog.row(type_id)
		var era: int = int(row.get("era", 0))
		var strength: int = int(row.get("fpn", 0)) + int(row.get("fpm", 0))
		if (
			era > best_era
			or (era == best_era and strength > best_sum)
			or (era == best_era and strength == best_sum and (best_id.is_empty() or type_id < best_id))
		):
			best_id = type_id
			best_era = era
			best_sum = strength
	return best_id


static func _branch_of(type_id: String) -> String:
	var category: int = RegimentCatalog.category(type_id)
	match category:
		RegimentCatalog.Category.LIGHT_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.SPEAR_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.HEAVY_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.LIGHT_ARTILLERY:
			return "artillery"
		RegimentCatalog.Category.HEAVY_ARTILLERY:
			return "artillery"
		_:
			return "infantry"
