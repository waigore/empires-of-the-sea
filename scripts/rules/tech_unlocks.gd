class_name TechUnlocks
extends RefCounted
## Every build order one researched tech opens, derived from the canonical gate
## tables (wiki: tech-tree § Effect Types). The college tooltip, the catalog
## audit and tests read this one answer, so a gate can never drift from the text
## the player is shown (REQ-P2-03, REQ-P3-03).

enum Kind { UNLOCK, ENABLE, IMPROVE }

const PHRASES: Dictionary = {
	Kind.UNLOCK: "Unlocks",
	Kind.ENABLE: "Enables",
	Kind.IMPROVE: "Improves",
}


## Rows for one tech as {kind: Kind, id: String, name: String}: units and hulls
## first, then the orders they open, then the modifiers they improve.
static func entries(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if tech_id.is_empty():
		return rows
	rows.append_array(_regiments(tech_id))
	rows.append_array(_hulls(tech_id))
	rows.append_array(_civilians(tech_id))
	rows.append_array(_workers(tech_id))
	rows.append_array(_forts(tech_id))
	rows.append_array(_rails(tech_id))
	rows.append_array(_generals(tech_id))
	rows.append_array(_upgrades(tech_id))
	rows.append_array(_attack_costs(tech_id))
	rows.sort_custom(_before)
	return rows


## Fixed-field phrase lines for the research ledger, one per kind present:
## "Unlocks: Lancers regiment.", "Enables: fort level 2.".
static func lines(tech_id: String) -> Array[String]:
	var groups: Dictionary = {
		Kind.UNLOCK: PackedStringArray(),
		Kind.ENABLE: PackedStringArray(),
		Kind.IMPROVE: PackedStringArray(),
	}
	for row: Dictionary in entries(tech_id):
		var words: PackedStringArray = groups[int(row["kind"])]
		words.append(String(row["name"]))
	var out: Array[String] = []
	for kind: int in [Kind.UNLOCK, Kind.ENABLE, Kind.IMPROVE]:
		var words: PackedStringArray = groups[kind]
		if words.is_empty():
			continue
		out.append("%s: %s." % [PHRASES[kind], ", ".join(words)])
	return out


# --- build-order domains -----------------------------------------------------


static func _regiments(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for type_id: String in _sorted_keys(RegimentEconomy.TECH):
		if String(RegimentEconomy.TECH[type_id]) != tech_id:
			continue
		rows.append(_row(Kind.UNLOCK, type_id, "%s regiment" % RegimentCatalog.display_name(type_id)))
	return rows


static func _hulls(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for type_id: String in _sorted_keys(ShipEconomy.TECH):
		if String(ShipEconomy.TECH[type_id]) != tech_id:
			continue
		rows.append(_row(Kind.UNLOCK, type_id, "%s hull" % ShipStats.display_name(type_id)))
	return rows


static func _civilians(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for type_id: String in CivilianCatalog.ORDER:
		if CivilianCatalog.unlock_tech(type_id) != tech_id:
			continue
		rows.append(_row(Kind.UNLOCK, type_id, "%s civilian" % CivilianCatalog.display_name(type_id)))
	return rows


static func _workers(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tier in range(1, WorkerPool.TIER_COUNT):
		if not WorkerPool.required_techs(tier).has(tech_id):
			continue
		rows.append(_row(
			Kind.ENABLE, "worker_%d" % tier,
			"recruiting %s" % WorkerPool.tier_name(tier).to_lower()
		))
	return rows


static func _forts(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for level in range(1, FortRules.MAX_LEVEL + 1):
		if FortRules.tech_gate(level) != tech_id:
			continue
		rows.append(_row(Kind.ENABLE, "fort_%d" % level, "fort level %d" % level))
	for battery: Dictionary in FortRules.EMPLACED_TECHS:
		if String(battery["tech"]) != tech_id:
			continue
		rows.append(_row(
			Kind.ENABLE, "emplaced_%s" % String(battery["type"]),
			"%s emplaced batteries" % RegimentCatalog.display_name(String(battery["type"]))
		))
	return rows


## Roads and railroads: the tile's terrain chooses the transport tech the wiki
## requires (wiki: tech-tree-transport § Acceptance Criteria).
static func _rails(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var flat: bool = false
	var hills: bool = false
	var mountains: bool = false
	for terrain: Variant in CivilianTransport.RAIL_TERRAIN_TECHS.keys():
		if String(CivilianTransport.RAIL_TERRAIN_TECHS[terrain]) != tech_id:
			continue
		match int(terrain):
			MapModel.Terrain.HILLS, MapModel.Terrain.SWAMP:
				hills = true
			MapModel.Terrain.MOUNTAINS:
				mountains = true
			_:
				flat = true
	if flat:
		rows.append(_row(Kind.ENABLE, "rail_flat", "railroads on flat terrain"))
	if hills:
		rows.append(_row(Kind.ENABLE, "rail_hills", "railroads on hills and swamps"))
	if mountains:
		rows.append(_row(Kind.ENABLE, "rail_mountains", "railroads on mountains"))
	if tech_id == CivilianTransport.ROAD_CONSTRUCTION:
		rows.append(_row(Kind.ENABLE, "road_level_2", "improved roads (transport level 2)"))
	return rows


static func _generals(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not GeneralRoster.CAP_TECHS.has(tech_id):
		return rows
	rows.append(_row(
		Kind.IMPROVE, "general_cap", "general cap to %d" % int(GeneralRoster.CAP_TECHS[tech_id])
	))
	return rows


## The in-place upgrade each military tech opens: the type its newest regiment
## replaces inside the same category (wiki: tech-tree-military § Infantry,
## Cavalry, Artillery — "Improves: <type> upgrade path"; DR-20261110-17).
static func _upgrades(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var path: Dictionary = RegimentUpgrades.path_for(tech_id)
	if path.is_empty():
		return rows
	rows.append(_row(
		Kind.IMPROVE, "upgrade_%s" % String(path["from"]), String(path["name"])
	))
	return rows


## A tech's factor on the treasury one land battle costs its attacker (wiki:
## tech-tree-military § Economy modifiers).
static func _attack_costs(tech_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not ArmyAttackCost.TECH_FACTORS.has(tech_id):
		return rows
	rows.append(_row(
		Kind.IMPROVE, "attack_cost",
		"land-battle attack cost ×%.2f" % float(ArmyAttackCost.TECH_FACTORS[tech_id])
	))
	return rows


# --- helpers -----------------------------------------------------------------


static func _row(kind: int, id: String, name: String) -> Dictionary:
	return {"kind": kind, "id": id, "name": name}


static func _sorted_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in source.keys():
		if String(source[key]).is_empty():
			continue
		keys.append(String(key))
	keys.sort()
	return keys


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["kind"]) != int(b["kind"]):
		return int(a["kind"]) < int(b["kind"])
	return String(a["name"]) < String(b["name"])
