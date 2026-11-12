class_name MilitaryParity
extends RefCounted
## Minor Nation regiment parity (wiki: factions § Minor military parity).
##
## The Minor Regiment Upgrade phase runs after movement and before combat: every
## Old World Minor Nation's land regiments become the appropriate higher-tier
## version at the strongest Great Power's current buildable era, in place. Tribes
## keep effective level 1 and are never upgraded. Pure rules: no nodes, so the
## turn pass and tests share one implementation (REQ-P2-01, REQ-P3-03).

const TRIBE_LEVEL: int = 1


## Highest land-regiment era any Great Power can build right now. A court with
## no tech data can still build era-1 regiments, so the floor is 1.
static func max_great_power_era(tech_by_faction: Dictionary) -> int:
	var highest: int = TRIBE_LEVEL
	for raw: Variant in tech_by_faction.keys():
		var tech: Dictionary = tech_by_faction[raw]
		for type_id: String in RegimentCatalog.ids():
			if not RegimentEconomy.buildable(type_id, tech):
				continue
			highest = maxi(highest, RegimentCatalog.era(type_id))
	return highest


## Effective military level a crown fights at: the Great Power maximum for a
## Minor Nation, level 1 for a Tribe.
static func effective_level(faction: int, great_power_era: int) -> int:
	if FactionCatalog.has_military_parity(faction):
		return maxi(great_power_era, 1)
	return TRIBE_LEVEL


## Upgrades every Minor Nation regiment to the target era in place. Returns a
## report for the turn trace; nothing mutates for Great Powers or Tribes.
static func apply(regions: MapRegionTable, tech_by_faction: Dictionary) -> Dictionary:
	var target: int = max_great_power_era(tech_by_faction)
	var report: Dictionary = {
		"era": target,
		"upgraded": [],
		"count": 0,
	}
	if regions == null:
		return report
	for region: int in regions.region_ids():
		var roster: Array = []
		roster.assign(regions.value(region, []))
		for raw: Variant in roster:
			var army: ArmyState = raw
			if army == null or not FactionCatalog.has_military_parity(army.owner):
				continue
			for regiment_id: String in army.regiments:
				var current: String = army.type_of(regiment_id)
				var upgraded: String = upgrade_type(current, target)
				if upgraded == current:
					continue
				army.set_type(regiment_id, upgraded)
				report["count"] = int(report["count"]) + 1
				(report["upgraded"] as Array).append({
					"region": region,
					"army": army.id,
					"faction": army.owner,
					"regiment": regiment_id,
					"from": current,
					"to": upgraded,
				})
	return report


## The same-category regiment closest to `target_era` without going above it.
## Cavalry never becomes infantry (or the reverse) and a court already ahead of
## the Great Powers is never downgraded. Ties break by strength, then type id so
## a replay always resolves the same way.
static func upgrade_type(current: String, target_era: int) -> String:
	if not RegimentCatalog.has_type(current):
		return current
	var current_era: int = RegimentCatalog.era(current)
	if current_era >= target_era:
		return current
	var category: int = RegimentCatalog.category(current)
	var best: String = current
	var best_era: int = current_era
	var best_strength: int = RegimentCatalog.strength(current)
	for type_id: String in RegimentCatalog.ids():
		if RegimentCatalog.category(type_id) != category:
			continue
		var era: int = RegimentCatalog.era(type_id)
		if era > target_era or era < best_era:
			continue
		var strength: int = RegimentCatalog.strength(type_id)
		if era > best_era or strength > best_strength:
			best = type_id
			best_era = era
			best_strength = strength
		elif era == best_era and strength == best_strength and type_id < best:
			best = type_id
	return best
