class_name RegimentUpgrades
extends RefCounted
## Great Power in-place regiment upgrades (wiki: tech-tree-military § Infantry,
## Cavalry, Artillery — every "Improves: <type> upgrade path" row; military-units
## § Minor military parity for the same in-place rule).
##
## A court's trained men re-equip the turn after the unlocking tech lands: the
## regiment keeps its instance id, army and province, and its type becomes the
## newest buildable type of its own category. The researched tech is the whole
## price — no extra treasury, materials or worker (DR-20261110-17). Pure rules,
## no nodes, so the turn pass and the tests share one implementation (REQ-P3-03).


## The regiment `tech_id` unlocks, paired with the type it replaces in its
## category, as {from, to, name}. Empty when the tech unlocks no regiment or its
## category has no earlier type (the first heavy cavalry or light artillery).
static func path_for(tech_id: String) -> Dictionary:
	if tech_id.is_empty():
		return {}
	for type_id: String in RegimentCatalog.ids():
		if RegimentEconomy.tech_for(type_id) != tech_id:
			continue
		var previous: String = previous_type(type_id)
		if previous.is_empty():
			return {}
		return {
			"from": previous,
			"to": type_id,
			"name": "%s upgrade path" % RegimentCatalog.display_name(previous),
		}
	return {}


## The strongest same-category type of a lower era — the rung below `type_id`.
## Bowmen, Knights and Lancers sit at the top of their own ladders (wiki:
## military-units § Regiment Table note), so their successors simply do not
## exist and this returns "".
static func previous_type(type_id: String) -> String:
	if not RegimentCatalog.has_type(type_id):
		return ""
	var category: int = RegimentCatalog.category(type_id)
	var era: int = RegimentCatalog.era(type_id)
	var best: String = ""
	var best_era: int = 0
	var best_strength: int = -1
	for other: String in RegimentCatalog.ids():
		if other == type_id or RegimentCatalog.category(other) != category:
			continue
		var other_era: int = RegimentCatalog.era(other)
		if other_era >= era:
			continue
		var strength: int = RegimentCatalog.strength(other)
		if other_era > best_era or (other_era == best_era and strength > best_strength):
			best = other
			best_era = other_era
			best_strength = strength
	return best


## The newest same-category type this court can build, never below the type it
## already fields. The era ladder itself is MilitaryParity's one helper, so both
## upgrade passes agree on which type is "next".
static func target_type(type_id: String, tech_unlocked: Dictionary) -> String:
	if not RegimentCatalog.has_type(type_id):
		return type_id
	var category: int = RegimentCatalog.category(type_id)
	var target_era: int = RegimentCatalog.era(type_id)
	for other: String in RegimentCatalog.ids():
		if RegimentCatalog.category(other) != category:
			continue
		if not RegimentEconomy.buildable(other, tech_unlocked):
			continue
		target_era = maxi(target_era, RegimentCatalog.era(other))
	if target_era <= RegimentCatalog.era(type_id):
		return type_id
	return MilitaryParity.upgrade_type(type_id, target_era)


## Re-equips every Great Power regiment in place across every region. Returns
## {count, by_faction, upgraded} for the turn trace. Minor Nations follow the
## parity pass and Tribes never upgrade here, so this only reads Great Powers.
static func apply(regions: MapRegionTable, tech_by_faction: Dictionary) -> Dictionary:
	var report: Dictionary = {"count": 0, "by_faction": {}, "upgraded": []}
	if regions == null:
		return report
	for region: int in regions.region_ids():
		var roster: Array = []
		roster.assign(regions.value(region, []))
		for raw: Variant in roster:
			var army: ArmyState = raw
			if army == null:
				continue
			if FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
				continue
			var tech: Dictionary = tech_by_faction.get(army.owner, {}) as Dictionary
			for regiment_id: String in army.regiments:
				var current: String = army.type_of(regiment_id)
				var upgraded: String = target_type(current, tech)
				if upgraded == current:
					continue
				army.set_type(regiment_id, upgraded)
				report["count"] = int(report["count"]) + 1
				var by_faction: Dictionary = report["by_faction"]
				by_faction[army.owner] = int(by_faction.get(army.owner, 0)) + 1
				(report["upgraded"] as Array).append({
					"region": region,
					"army": army.id,
					"faction": army.owner,
					"regiment": regiment_id,
					"from": current,
					"to": upgraded,
				})
	return report
