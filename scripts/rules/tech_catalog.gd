class_name TechCatalog
extends RefCounted
## The shared technology catalog: every Great Power researches the same static
## list (wiki: tech-tree § Catalog, tech-and-extraction-cap). Pure data plus
## queries — research state, extraction caps and the research ledger all read
## this table, so no screen invents its own tech ids (REQ-P2-03, REQ-P3-03).

const CATEGORIES: Array[String] = [
	"gathering", "transport", "labour", "diplomatic", "military", "naval", "new-world",
]
const CATEGORY_LABELS: Dictionary = {
	"gathering": "Gathering and production",
	"transport": "Transport",
	"labour": "Labour and economy",
	"diplomatic": "Diplomacy and civilians",
	"military": "Military",
	"naval": "Naval",
	"new-world": "New World",
}
const ERA_NAMES: Dictionary = {
	1: "Renaissance",
	2: "Enlightenment",
	3: "Revolution",
	4: "Industrial",
}

## Wiki cost formula: cost(tier) = 1800 + (tier - 1) * 600.
const BASE_COST: int = 1800
const COST_STEP: int = 600

## Extraction caps are 1..4; a resource with no cap-raising tech stays at 1.
const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 4
## Resources whose chain intentionally stops below level 4, declared in the
## wiki (tech-and-extraction-cap § Extraction Cap).
const CAP_EXCEPTIONS: Dictionary = {"horses": 1, "wool": 3}

## id -> {name, era (cost tier), category, prereqs, caps, discovery, note}.
## `caps` is the max improvement level the tech grants per commodity;
## `discovery` lists commodities an explorer must reveal before it is
## researchable; `note` names effects this slice does not simulate yet.
const TECHS: Dictionary = {
	"crop_rotation": {"name": "Crop Rotation", "era": 1, "category": "gathering", "prereqs": []},
	"saw_mill": {"name": "Saw Mill", "era": 1, "category": "gathering", "prereqs": [], "caps": {"timber": 2}},
	"land_enclosure": {"name": "Land Enclosure", "era": 1, "category": "gathering", "prereqs": [], "caps": {"grain": 2}},
	"mine_engineering": {"name": "Mine Engineering", "era": 1, "category": "gathering", "prereqs": []},
	"iron_mining": {"name": "Iron Mining", "era": 1, "category": "gathering", "prereqs": ["mine_engineering"], "caps": {"iron": 2}},
	"copper_and_tin_mining": {"name": "Copper and Tin Mining", "era": 1, "category": "gathering", "prereqs": ["mine_engineering"], "caps": {"copper": 2, "tin": 2}},
	"coal_mining": {"name": "Coal Mining", "era": 1, "category": "gathering", "prereqs": ["mine_engineering"], "caps": {"coal": 1}},
	"wind_saw_mill": {"name": "Wind Saw Mill", "era": 2, "category": "gathering", "prereqs": ["saw_mill"], "caps": {"timber": 3}},
	"seed_drill": {"name": "Seed Drill", "era": 2, "category": "gathering", "prereqs": ["land_enclosure"], "caps": {"grain": 3}},
	"sheep_ranching": {"name": "Sheep Ranching", "era": 2, "category": "gathering", "prereqs": ["crop_rotation"], "caps": {"wool": 2}},
	"animal_husbandry": {"name": "Animal Husbandry", "era": 2, "category": "gathering", "prereqs": ["crop_rotation"], "caps": {"meat": 3}},
	"square_set_timbering": {"name": "Square-set Timbering", "era": 2, "category": "gathering", "prereqs": ["coal_mining"], "caps": {"coal": 2}},
	"steam_in_mining": {"name": "Steam in Mining", "era": 2, "category": "gathering", "prereqs": ["iron_mining"], "caps": {"iron": 3}},
	"large_coal_mines": {"name": "Large Coal Mines", "era": 2, "category": "gathering", "prereqs": ["square_set_timbering", "steam_in_mining"], "caps": {"coal": 3}},
	"large_copper_and_tin_mines": {"name": "Large Copper and Tin Mines", "era": 2, "category": "gathering", "prereqs": ["copper_and_tin_mining"], "caps": {"copper": 3, "tin": 3}},
	"circular_saw": {"name": "Circular Saw", "era": 3, "category": "gathering", "prereqs": ["wind_saw_mill", "university"], "caps": {"timber": 4}},
	"scientific_sheep_breeding": {"name": "Scientific Sheep Breeding", "era": 3, "category": "gathering", "prereqs": ["sheep_ranching", "university"], "caps": {"wool": 3}},
	"scientific_cattle_breeding": {"name": "Scientific Cattle Breeding", "era": 3, "category": "gathering", "prereqs": ["animal_husbandry", "university"], "caps": {"meat": 4}},
	"moldboard_plow": {"name": "Moldboard Plow", "era": 3, "category": "gathering", "prereqs": ["seed_drill"], "caps": {"grain": 4}},
	"safety_lamp": {"name": "Safety Lamp", "era": 4, "category": "gathering", "prereqs": ["large_coal_mines", "dynamite"], "caps": {"coal": 4}},
	"large_precious_stone_mines": {"name": "Large Precious Stone Mines", "era": 3, "category": "gathering", "prereqs": ["precious_stone_mining", "university"], "caps": {"diamonds": 3, "gems": 3}},
	"extraction_of_precious_metals": {"name": "Extraction of Precious Metals", "era": 3, "category": "gathering", "prereqs": ["precious_metals_mining", "university"], "caps": {"gold": 3, "silver": 3}},
	"geological_prospecting": {"name": "Geological Prospecting", "era": 4, "category": "gathering", "prereqs": ["large_precious_stone_mines", "dynamite"], "caps": {"diamonds": 4, "gems": 4}},
	"amalgamation_process": {"name": "Amalgamation Process", "era": 4, "category": "gathering", "prereqs": ["dynamite", "extraction_of_precious_metals"], "caps": {"gold": 4, "silver": 4}},
	"industrial_iron_mining": {"name": "Industrial Iron Mining", "era": 4, "category": "gathering", "prereqs": ["industrial_funding_of_research", "steam_in_mining"], "caps": {"iron": 4}},
	"efficient_extraction_of_copper_and_tin": {"name": "Efficient Extraction of Copper & Tin", "era": 4, "category": "gathering", "prereqs": ["large_coal_mines", "large_copper_and_tin_mines"], "caps": {"copper": 4, "tin": 4}},
	"road_construction": {"name": "Road Construction", "era": 1, "category": "transport", "prereqs": ["saw_mill", "land_enclosure", "iron_mining"]},
	"early_steam_engine": {"name": "Early Steam Engine", "era": 2, "category": "transport", "prereqs": ["road_construction", "square_set_timbering", "steam_in_mining"]},
	"later_steam_engine": {"name": "Later Steam Engine", "era": 3, "category": "transport", "prereqs": ["early_steam_engine", "crucible_process"]},
	"dynamite": {"name": "Dynamite", "era": 4, "category": "transport", "prereqs": ["later_steam_engine", "banking", "explosives"]},
	"printing_press": {"name": "Printing Press", "era": 1, "category": "labour", "prereqs": []},
	"apprentice_workers": {"name": "Apprentice Workers", "era": 2, "category": "labour", "prereqs": ["land_enclosure", "sugar_refining"]},
	"trained_journeymen": {"name": "Trained Journeymen", "era": 2, "category": "labour", "prereqs": ["cigar_production", "printing_press"]},
	"master_artisans": {"name": "Master Artisans", "era": 3, "category": "labour", "prereqs": ["apprentice_workers", "university", "hat_production"]},
	"money_lending": {"name": "Money Lending", "era": 1, "category": "labour", "prereqs": ["land_enclosure"], "note": "Improves: research funding may reach -500 ducats."},
	"banking": {"name": "Banking", "era": 3, "category": "labour", "prereqs": ["master_artisans", "trade_fairs"], "note": "Improves: with Money Lending, research funding reaches -1000 ducats."},
	"trade_fairs": {"name": "Trade Fairs", "era": 2, "category": "labour", "prereqs": ["merchant_companies", "sugar_refining"]},
	"university": {"name": "University", "era": 3, "category": "labour", "prereqs": ["money_lending", "apprentice_workers", "printing_press"], "note": "Enables: a fourth research slot."},
	"diplomatic_expertise": {"name": "Diplomatic Expertise", "era": 1, "category": "diplomatic", "prereqs": []},
	"merchant_companies": {"name": "Merchant Companies", "era": 1, "category": "diplomatic", "prereqs": []},
	"national_bureaucracy": {"name": "National Bureaucracy", "era": 2, "category": "diplomatic", "prereqs": ["printing_press", "money_lending", "diplomatic_expertise"]},
	"propaganda": {"name": "Propaganda", "era": 3, "category": "diplomatic", "prereqs": ["national_bureaucracy", "university"], "note": "Improves: protesting an aggressor costs 5 relation, not 10."},
	"nationalism": {"name": "Nationalism", "era": 3, "category": "diplomatic", "prereqs": ["propaganda", "master_artisans", "modern_forts"], "note": "Improves: battle deployment limit to 12 regiments."},
	"empire_building": {"name": "Empire Building", "era": 4, "category": "diplomatic", "prereqs": ["nationalism", "banking"], "note": "Enables: Join Empire overture on a nearly defeated Great Power."},
	"organised_regiments": {"name": "Organised Regiments", "era": 1, "category": "military", "prereqs": ["land_enclosure"]},
	"improved_iron_weapons": {"name": "Improved Iron Weapons", "era": 1, "category": "military", "prereqs": ["organised_regiments", "iron_mining"]},
	"improved_infantry_tactics": {"name": "Improved Infantry Tactics", "era": 2, "category": "military", "prereqs": ["organised_regiments", "printing_press"]},
	"crucible_process": {"name": "Crucible Process", "era": 2, "category": "military", "prereqs": ["square_set_timbering", "steam_in_mining"]},
	"bayonet": {"name": "Bayonet", "era": 2, "category": "military", "prereqs": ["improved_iron_weapons", "crucible_process"]},
	"weapon_craftsmanship": {"name": "Weapon Craftsmanship", "era": 2, "category": "military", "prereqs": ["organised_regiments", "copper_and_tin_mining"]},
	"industrial_machinery": {"name": "Industrial Machinery", "era": 3, "category": "military", "prereqs": ["trained_journeymen", "steam_in_mining", "university"]},
	"explosives": {"name": "Explosives", "era": 3, "category": "military", "prereqs": ["weapon_craftsmanship", "industrial_machinery"]},
	"early_rifles": {"name": "Early Rifles", "era": 3, "category": "military", "prereqs": ["improved_infantry_tactics", "crucible_process"]},
	"long_range_rifles": {"name": "Long Range Rifles", "era": 3, "category": "military", "prereqs": ["early_rifles", "crucible_process"]},
	"needle_guns": {"name": "Needle Guns", "era": 4, "category": "military", "prereqs": ["industrial_funding_of_research", "bayonet", "early_rifles"]},
	"elite_military_training": {"name": "Elite Military Training", "era": 4, "category": "military", "prereqs": ["modern_military_funding", "needle_guns", "explosives"]},
	"recruit_steppe_horsemen": {"name": "Recruit Steppe Horsemen", "era": 1, "category": "military", "prereqs": ["crop_rotation"]},
	"improved_cavalry_tactics": {"name": "Improved Cavalry Tactics", "era": 2, "category": "military", "prereqs": ["printing_press", "animal_husbandry"]},
	"hussars": {"name": "Hussars", "era": 2, "category": "military", "prereqs": ["improved_cavalry_tactics", "recruit_steppe_horsemen"]},
	"improved_cavalry_weapons": {"name": "Improved Cavalry Weapons", "era": 3, "category": "military", "prereqs": ["industrial_machinery", "crucible_process", "improved_cavalry_tactics"]},
	"scouting": {"name": "Scouting", "era": 3, "category": "military", "prereqs": ["hussars", "early_rifles"]},
	"repeating_cavalry_carbine": {"name": "Repeating Cavalry Carbine", "era": 4, "category": "military", "prereqs": ["industrial_funding_of_research", "improved_cavalry_weapons"]},
	"horse_artillery": {"name": "Horse Artillery", "era": 1, "category": "military", "prereqs": ["animal_husbandry", "copper_and_tin_mining"]},
	"siege_engineering": {"name": "Siege Engineering", "era": 2, "category": "military", "prereqs": ["printing_press", "copper_and_tin_mining"]},
	"light_artillery_tactics": {"name": "Light Artillery Tactics", "era": 3, "category": "military", "prereqs": ["crucible_process", "university"]},
	"modern_forts": {"name": "Modern Forts", "era": 3, "category": "military", "prereqs": ["siege_engineering", "university"]},
	"heavy_artillery": {"name": "Heavy Artillery", "era": 3, "category": "military", "prereqs": ["modern_forts", "crucible_process"]},
	"heavy_emplaced_artillery": {"name": "Heavy Emplaced Artillery", "era": 3, "category": "military", "prereqs": ["road_construction", "national_bureaucracy", "siege_engineering"]},
	"field_artillery_tactics": {"name": "Field Artillery Tactics", "era": 4, "category": "military", "prereqs": ["light_artillery_tactics", "modern_military_funding"]},
	"high_grade_steel": {"name": "High Grade Steel", "era": 4, "category": "military", "prereqs": ["heavy_artillery", "industrial_funding_of_research", "modern_military_funding"]},
	"emplaced_siege_guns": {"name": "Emplaced Siege Guns", "era": 4, "category": "military", "prereqs": ["heavy_artillery", "heavy_emplaced_artillery"]},
	"modern_military_funding": {"name": "Modern Military Funding", "era": 3, "category": "military", "prereqs": ["banking", "large_precious_stone_mines", "modern_forts"]},
	"industrial_funding_of_research": {"name": "Industrial Funding of Research", "era": 3, "category": "military", "prereqs": ["industrial_machinery", "crucible_process"], "note": "Improves: +20% research points for military and naval techs."},
	"superior_hull_design": {"name": "Superior Hull Design", "era": 1, "category": "naval", "prereqs": []},
	"improved_sail_design": {"name": "Improved Sail Design", "era": 2, "category": "naval", "prereqs": ["wind_saw_mill", "superior_hull_design"]},
	"convoying": {"name": "Convoying", "era": 2, "category": "naval", "prereqs": ["merchant_companies"]},
	"navigation": {"name": "Navigation", "era": 1, "category": "naval", "prereqs": ["superior_hull_design"]},
	"large_hulls": {"name": "Large Hulls", "era": 2, "category": "naval", "prereqs": ["wind_saw_mill", "navigation", "convoying"]},
	"clipper_ships": {"name": "Clipper Ships", "era": 4, "category": "naval", "prereqs": ["circular_saw", "advanced_hull_design"]},
	"paddlewheels": {"name": "Paddlewheels", "era": 3, "category": "naval", "prereqs": ["advanced_hull_design", "early_steam_engine"]},
	"merchant_steamships": {"name": "Merchant Steamships", "era": 4, "category": "naval", "prereqs": ["paddlewheels", "riverboats"]},
	"advanced_hull_design": {"name": "Advanced Hull Design", "era": 3, "category": "naval", "prereqs": ["university", "improved_sail_design", "privateering_companies"]},
	"ship_of_the_line": {"name": "Ship of the Line", "era": 3, "category": "naval", "prereqs": ["large_hulls", "large_copper_and_tin_mines"]},
	"privateering_companies": {"name": "Privateering Companies", "era": 2, "category": "naval", "prereqs": ["navigation", "diplomatic_expertise"], "note": "Improves: Patrol/Blockade interception and trade raids by 25%."},
	"advanced_iron_working": {"name": "Advanced Iron Working", "era": 4, "category": "naval", "prereqs": ["ship_of_the_line", "industrial_funding_of_research", "paddlewheels"]},
	"discovery_of_sugar": {"name": "Discovery of Sugar", "era": 1, "category": "new-world", "prereqs": [], "discovery": ["sugarCane"]},
	"sugar_planting": {"name": "Sugar Planting", "era": 1, "category": "new-world", "prereqs": ["discovery_of_sugar"], "caps": {"sugarCane": 2}},
	"sugar_refining": {"name": "Sugar Refining", "era": 1, "category": "new-world", "prereqs": ["discovery_of_sugar"]},
	"large_sugar_plantations": {"name": "Large Sugar Plantations", "era": 2, "category": "new-world", "prereqs": ["sugar_planting"], "caps": {"sugarCane": 3}},
	"sugar_industry": {"name": "Sugar Industry", "era": 3, "category": "new-world", "prereqs": ["large_sugar_plantations"], "caps": {"sugarCane": 4}},
	"discovery_of_tobacco": {"name": "Discovery of Tobacco", "era": 1, "category": "new-world", "prereqs": [], "discovery": ["tobacco"]},
	"tobacco_planting": {"name": "Tobacco Planting", "era": 1, "category": "new-world", "prereqs": ["discovery_of_tobacco"], "caps": {"tobacco": 2}},
	"cigar_production": {"name": "Cigar Production", "era": 1, "category": "new-world", "prereqs": ["discovery_of_tobacco"]},
	"large_tobacco_plantations": {"name": "Large Tobacco Plantations", "era": 2, "category": "new-world", "prereqs": ["tobacco_planting", "seed_drill"], "caps": {"tobacco": 3}},
	"tobacco_industry": {"name": "Tobacco Industry", "era": 3, "category": "new-world", "prereqs": ["early_steam_engine", "large_tobacco_plantations"], "caps": {"tobacco": 4}},
	"discovery_of_cotton": {"name": "Discovery of Cotton", "era": 1, "category": "new-world", "prereqs": [], "discovery": ["cotton"]},
	"cotton_planting": {"name": "Cotton Planting", "era": 1, "category": "new-world", "prereqs": ["discovery_of_cotton"], "caps": {"cotton": 2}},
	"cotton_weaving": {"name": "Cotton Weaving", "era": 1, "category": "new-world", "prereqs": ["discovery_of_cotton"], "note": "Enables: cloth production from cotton via labour recipes."},
	"large_cotton_plantations": {"name": "Large Cotton Plantations", "era": 2, "category": "new-world", "prereqs": ["cotton_planting"], "caps": {"cotton": 3}},
	"cotton_gin": {"name": "Cotton Gin", "era": 3, "category": "new-world", "prereqs": ["large_cotton_plantations", "trained_journeymen"], "caps": {"cotton": 4}},
	"discovery_of_furs": {"name": "Discovery of Furs", "era": 1, "category": "new-world", "prereqs": [], "discovery": ["furs"]},
	"improved_trapping_techniques": {"name": "Improved Trapping Techniques", "era": 1, "category": "new-world", "prereqs": ["discovery_of_furs"], "caps": {"furs": 2}},
	"hat_production": {"name": "Hat Production", "era": 1, "category": "new-world", "prereqs": ["discovery_of_furs"]},
	"riverboats": {"name": "Riverboats", "era": 3, "category": "new-world", "prereqs": ["improved_trapping_techniques", "early_steam_engine"], "caps": {"furs": 3}},
	"excessive_fur_harvesting": {"name": "Excessive Fur Harvesting", "era": 4, "category": "new-world", "prereqs": ["later_steam_engine", "riverboats"], "caps": {"furs": 4}},
	"discovery_of_spices": {"name": "Discovery of Spices", "era": 1, "category": "new-world", "prereqs": [], "discovery": ["spices"]},
	"improved_sea_routes": {"name": "Improved Sea Routes", "era": 1, "category": "new-world", "prereqs": ["discovery_of_spices"], "caps": {"spices": 2}},
	"large_spice_plantations": {"name": "Large Spice Plantations", "era": 2, "category": "new-world", "prereqs": ["seed_drill", "improved_sea_routes"], "caps": {"spices": 3}},
	"improved_food_preservation": {"name": "Improved Food Preservation", "era": 3, "category": "new-world", "prereqs": ["large_spice_plantations"], "caps": {"spices": 4}},
	"discovery_of_gold_or_silver": {"name": "Discovery of Gold or Silver", "era": 1, "category": "new-world", "prereqs": [], "discovery": ["gold", "silver"]},
	"precious_metals_mining": {"name": "Precious Metals Mining", "era": 1, "category": "new-world", "prereqs": ["discovery_of_gold_or_silver", "mine_engineering"], "caps": {"gold": 2, "silver": 2}},
	"discovery_of_gems_or_diamonds": {"name": "Discovery of Gems or Diamonds", "era": 1, "category": "new-world", "prereqs": [], "discovery": ["gems", "diamonds"]},
	"precious_stone_mining": {"name": "Precious Stone Mining", "era": 1, "category": "new-world", "prereqs": ["discovery_of_gems_or_diamonds"], "caps": {"diamonds": 2, "gems": 2}},
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for tech_id: Variant in TECHS.keys():
		out.append(String(tech_id))
	out.sort()
	return out


static func known(tech_id: String) -> bool:
	return TECHS.has(tech_id)


static func entry(tech_id: String) -> Dictionary:
	return TECHS.get(tech_id, {})


static func display_name(tech_id: String) -> String:
	return String(entry(tech_id).get("name", tech_id))


static func category(tech_id: String) -> String:
	return String(entry(tech_id).get("category", "gathering"))


static func category_label(tech_id: String) -> String:
	return String(CATEGORY_LABELS.get(category(tech_id), category(tech_id)))


static func era(tech_id: String) -> int:
	return int(entry(tech_id).get("era", 1))


static func era_name(tech_id: String) -> String:
	return String(ERA_NAMES.get(era(tech_id), ""))


## Research point cost of the tech (wiki: tech-tree § Research Model).
static func cost(tech_id: String) -> int:
	return cost_for_era(era(tech_id))


static func cost_for_era(cost_tier: int) -> int:
	return BASE_COST + (clampi(cost_tier, 1, 4) - 1) * COST_STEP


static func prerequisites(tech_id: String) -> Array[String]:
	var out: Array[String] = []
	for prereq: Variant in entry(tech_id).get("prereqs", []):
		out.append(String(prereq))
	return out


## Techs that list `tech_id` as a prerequisite — the "leads to" edges.
static func dependents(tech_id: String) -> Array[String]:
	var out: Array[String] = []
	for other: Variant in TECHS.keys():
		if prerequisites(String(other)).has(tech_id):
			out.append(String(other))
	out.sort()
	return out


static func discovery_resources(tech_id: String) -> Array[String]:
	var out: Array[String] = []
	for commodity: Variant in entry(tech_id).get("discovery", []):
		out.append(String(commodity))
	return out


static func caps_of(tech_id: String) -> Dictionary:
	return (entry(tech_id).get("caps", {}) as Dictionary).duplicate()


## Resource -> highest unlocked improvement level. Absent resources stay at 1.
static func extraction_caps(unlocked: Dictionary) -> Dictionary:
	var caps: Dictionary = {}
	for tech_id: Variant in unlocked.keys():
		if not bool(unlocked[tech_id]):
			continue
		var granted: Dictionary = caps_of(String(tech_id))
		for commodity: Variant in granted.keys():
			var id: String = String(commodity)
			caps[id] = maxi(int(caps.get(id, MIN_LEVEL)), int(granted[commodity]))
	return caps


static func cap_for(commodity: String, unlocked: Dictionary) -> int:
	var cap: int = MIN_LEVEL
	for tech_id: Variant in unlocked.keys():
		if not bool(unlocked[tech_id]):
			continue
		var granted: Dictionary = caps_of(String(tech_id))
		if granted.has(commodity):
			cap = maxi(cap, int(granted[commodity]))
	return cap


## Starting techs: no prerequisites at all.
static func roots() -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in ids():
		if prerequisites(tech_id).is_empty():
			out.append(tech_id)
	return out


## Player-facing effect line, built from the data the slice actually applies
## (wiki: tech-tree-gathering § Acceptance criteria — fixed effect phrases).
static func effect_text(tech_id: String) -> String:
	var parts: PackedStringArray = []
	var note: String = String(entry(tech_id).get("note", ""))
	if not note.is_empty():
		parts.append(note)
	var caps: Dictionary = caps_of(tech_id)
	if not caps.is_empty():
		var bits: PackedStringArray = []
		var commodities: Array = caps.keys()
		commodities.sort()
		for commodity: Variant in commodities:
			bits.append("%s %d" % [
				CommodityCatalog.label(String(commodity)), int(caps[commodity]),
			])
		parts.append("Improves: extraction cap %s." % ", ".join(bits))
	var discovery: Array[String] = discovery_resources(tech_id)
	if not discovery.is_empty():
		var found: PackedStringArray = []
		for commodity: String in discovery:
			found.append(CommodityCatalog.label(commodity))
		parts.append("Enables: research once an explorer finds %s." % " or ".join(found))
	for line: String in TechUnlocks.lines(tech_id):
		parts.append(line)
	var children: Array[String] = dependents(tech_id)
	if not children.is_empty():
		var names: PackedStringArray = []
		for child: String in children.slice(0, 3):
			names.append(display_name(child))
		if children.size() > 3:
			names.append("and %d more" % (children.size() - 3))
		_merge_lead(parts, "research paths to %s" % ", ".join(names))
	if parts.is_empty():
		parts.append("Prerequisite-only in this slice.")
	return " ".join(parts)


## Joins a "leads to" clause onto the row's Unlocks line so a tech with both a
## unit unlock and dependents reads as one sentence, not two "Unlocks:".
static func _merge_lead(parts: PackedStringArray, lead: String) -> void:
	for index in parts.size():
		if not parts[index].begins_with("Unlocks: "):
			continue
		parts[index] = "%s; %s." % [parts[index].trim_suffix("."), lead]
		return
	parts.append("Unlocks: %s." % lead)
