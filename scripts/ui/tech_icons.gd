class_name TechIcons
extends RefCounted
## One brass medallion per research series (assets/art/tech), generated in the
## shell's family so the college ledger reads as one artefact (REQ-P1-02;
## tools/art/tech-medallions.md). A tech chain shares one plate, so a 113-tech
## catalog needs a few dozen images rather than one each.

const DIR: String = "res://assets/art/tech/"

## Plate -> the tech ids it illustrates. Chains that grow grander keep a later
## plate of their own (`seed_drill`, `circular_saw` and friends).
const SERIES: Dictionary = {
	"fields": ["crop_rotation", "land_enclosure"],
	"seed_drill": ["seed_drill", "moldboard_plow"],
	"sawmill": ["saw_mill", "wind_saw_mill"],
	"circular_saw": ["circular_saw"],
	"mine_timbering": ["mine_engineering", "square_set_timbering"],
	"safety_lamp": ["safety_lamp"],
	"iron_mining": ["iron_mining", "industrial_iron_mining"],
	"steam_mining": ["steam_in_mining"],
	"copper_tin": [
		"copper_and_tin_mining", "large_copper_and_tin_mines",
		"efficient_extraction_of_copper_and_tin",
	],
	"coal": ["coal_mining", "large_coal_mines"],
	"gold": [
		"discovery_of_gold_or_silver", "precious_metals_mining",
		"extraction_of_precious_metals",
	],
	"amalgamation": ["amalgamation_process"],
	"gems": [
		"discovery_of_gems_or_diamonds", "precious_stone_mining",
		"large_precious_stone_mines", "geological_prospecting",
	],
	"sheep": ["sheep_ranching", "scientific_sheep_breeding"],
	"cattle": ["animal_husbandry", "scientific_cattle_breeding"],
	"horse": ["recruit_steppe_horsemen"],
	"road": ["road_construction"],
	"steam_engine": ["early_steam_engine", "later_steam_engine"],
	"dynamite": ["dynamite", "explosives"],
	"press": ["printing_press"],
	"workshop": ["apprentice_workers", "trained_journeymen", "master_artisans"],
	"money": ["money_lending", "banking"],
	"trade_fairs": ["trade_fairs", "merchant_companies"],
	"university": ["university"],
	"diplomacy": ["diplomatic_expertise", "national_bureaucracy"],
	"propaganda": ["propaganda", "nationalism"],
	"empire": ["empire_building"],
	"regiments": ["organised_regiments", "improved_infantry_tactics", "elite_military_training"],
	"iron_weapons": [
		"improved_iron_weapons", "weapon_craftsmanship", "bayonet", "high_grade_steel",
	],
	"rifles": [
		"early_rifles", "long_range_rifles", "needle_guns", "repeating_cavalry_carbine",
	],
	"crucible": ["crucible_process", "industrial_machinery"],
	"military_funding": ["modern_military_funding", "industrial_funding_of_research"],
	"fort": [
		"modern_forts", "siege_engineering", "heavy_emplaced_artillery", "emplaced_siege_guns",
	],
	"field_gun": [
		"horse_artillery", "light_artillery_tactics", "field_artillery_tactics",
		"heavy_artillery",
	],
	"cavalry": ["improved_cavalry_tactics", "hussars", "improved_cavalry_weapons"],
	"scouting": ["scouting"],
	"hull": [
		"superior_hull_design", "improved_sail_design", "large_hulls", "advanced_hull_design",
	],
	"navigation": ["navigation", "convoying"],
	"ship_of_line": ["ship_of_the_line", "privateering_companies"],
	"clipper": ["clipper_ships"],
	"paddlewheel": ["paddlewheels", "merchant_steamships"],
	"iron_ship": ["advanced_iron_working"],
	"sugar": [
		"discovery_of_sugar", "sugar_planting", "sugar_refining",
		"large_sugar_plantations", "sugar_industry",
	],
	"tobacco": [
		"discovery_of_tobacco", "tobacco_planting", "cigar_production",
		"large_tobacco_plantations", "tobacco_industry",
	],
	"cotton": [
		"discovery_of_cotton", "cotton_planting", "cotton_weaving",
		"large_cotton_plantations", "cotton_gin",
	],
	"furs": [
		"discovery_of_furs", "improved_trapping_techniques", "hat_production",
		"excessive_fur_harvesting",
	],
	"riverboats": ["riverboats"],
	"spices": [
		"discovery_of_spices", "improved_sea_routes", "large_spice_plantations",
		"improved_food_preservation",
	],
}

static var _by_tech: Dictionary = {}
static var _cache: Dictionary = {}


## Plate name for a tech, or "" when the catalog gained a tech no plate covers
## (tests guard the coverage; a row then simply draws without a medallion).
static func series_of(tech_id: String) -> String:
	if _by_tech.is_empty():
		for plate: Variant in SERIES.keys():
			for covered: Variant in SERIES[plate]:
				_by_tech[String(covered)] = String(plate)
	return String(_by_tech.get(tech_id, ""))


## The medallion texture for a tech, or null when no plate covers it.
static func texture(tech_id: String) -> Texture2D:
	var plate: String = series_of(tech_id)
	if plate.is_empty():
		return null
	var path: String = DIR + plate + ".png"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## Every tech id the table covers, sorted — the coverage test reads this.
static func covered_ids() -> Array[String]:
	var out: Array[String] = []
	for plate: Variant in SERIES.keys():
		for covered: Variant in SERIES[plate]:
			out.append(String(covered))
	out.sort()
	return out
