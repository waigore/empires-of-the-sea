class_name DefenceSurvey
extends RefCounted
## Defence reading for the military lens: every charted province, the strength
## its owner keeps there and the wall that would meet an attack
## (wiki: combat § Strength, siege-mechanics § Fort Levels, hospital_rules).
## Pure read of the public order of battle: the garrison is the sum of the
## owner's regiments' `FPN + FPM` — the same published terms the court panel's
## power score reads, with no general's medals, chevrons or wounds, so the lens
## can never leak a reading the wiki keeps private (REQ-P3-03, REQ-P2-03).
## A province's band is its wall first, then its garrison, so the player sees
## the two things an attack must beat.

const BAND_OPEN: String = "open"
const BAND_HELD: String = "held"
const BAND_WALLED: String = "walled"
const BAND_CITADEL: String = "citadel"
const BANDS: Array[String] = [BAND_OPEN, BAND_HELD, BAND_WALLED, BAND_CITADEL]

const BAND_LABELS: Dictionary = {
	BAND_OPEN: "Open — no garrison, no wall",
	BAND_HELD: "Garrison only",
	BAND_WALLED: "Walled (fort 1–2)",
	BAND_CITADEL: "Citadel (fort 3+)",
}

## Where a ground stops merely helping and starts sheltering. These read
## [ArmyModifiers.TERRAIN_DEFENCE]'s own numbers rather than copying them, so a
## change to the combat table moves the words with it and the lens can never
## praise ground the battle would not favour (wiki: combat § Modifiers,
## resource-terrain-region-rules § Player-facing terrain display names).
const SHELTER_HARD: float = 1.25
const SHELTER_GOOD: float = 1.10


## Per-province reading plus the counts each band holds and the crown's own
## totals. `armies` is the roster of the region on screen; an embarked army
## defends nothing.
static func snapshot(
	model: MapModel,
	armies: Array[ArmyState],
	visibility: VisibilityModel = null,
	player: int = MapModel.NO_ID
) -> Dictionary:
	var result: Dictionary = {
		"provinces": [] as Array[Dictionary],
		"counts": _empty_counts(),
		"totals": {"provinces": 0, "held": 0, "undefended": 0, "strength": 0},
	}
	if model == null:
		return result
	var garrisons: Dictionary = _garrisons(armies)
	for province: ProvinceState in model.provinces:
		var charted: int = VisibilityModel.Level.FULLY_VISIBLE
		if visibility != null:
			charted = visibility.province_visibility(province.id)
		if charted == VisibilityModel.Level.UNKNOWN:
			continue
		var entry: Dictionary = _entry(model, province, garrisons, charted, player, visibility)
		var counts: Dictionary = result["counts"]
		counts[String(entry["band"])] = int(counts[String(entry["band"])]) + 1
		var totals: Dictionary = result["totals"]
		totals["provinces"] = int(totals["provinces"]) + 1
		if province.owner == player:
			totals["strength"] = int(totals["strength"]) + int(entry["strength"])
			if String(entry["band"]) == BAND_OPEN:
				totals["undefended"] = int(totals["undefended"]) + 1
		(result["provinces"] as Array).append(entry)
	return result


## Band for one province: the wall outranks the garrison, because a walled
## province with an empty town still has to be breached.
static func band_for(fort_level: int, garrison: int) -> String:
	var level: int = FortRules.clamp_level(fort_level)
	if level >= 3:
		return BAND_CITADEL
	if level >= 1:
		return BAND_WALLED
	if garrison > 0:
		return BAND_HELD
	return BAND_OPEN


static func band_label(band: String) -> String:
	return String(BAND_LABELS.get(band, BAND_LABELS[BAND_OPEN]))


## The ground a battle in this province would be fought on, named as the canon
## display name (`MapModel.TERRAIN_LABELS`).
static func terrain_name(terrain: int) -> String:
	return String(MapModel.TERRAIN_LABELS.get(terrain, "Unknown"))


## Whether the ground favours a defence at all. Plains buy nothing, so a slip on
## them stays quiet; every other ground buys something and names itself.
static func shelters(terrain: int) -> bool:
	return ArmyModifiers.terrain_multiplier(terrain) > 1.0


## What one ground buys a defender, in words — read off the battle's own
## multiplier, so the reading and the Combat phase cannot disagree.
static func terrain_flavour(terrain: int) -> String:
	var multiplier: float = ArmyModifiers.terrain_multiplier(terrain)
	if multiplier >= SHELTER_HARD:
		return "shelters a defence"
	if multiplier >= SHELTER_GOOD:
		return "favours a defence"
	if multiplier > 1.0:
		return "gives the defence an edge"
	return "nothing to hold"


## The ground line the hover and the province sheet print: the dominant
## terrain's name and the little it buys.
static func terrain_line(terrain: int) -> String:
	return "%s — %s" % [terrain_name(terrain), terrain_flavour(terrain)]


## The hover line: what stands here, in the terms a battle reads — the garrison,
## the wall, the ward, then the ground the fight would be had on.
static func summary_text(entry: Dictionary) -> String:
	var strength: int = int(entry.get("strength", 0))
	var regiments: int = int(entry.get("regiments", 0))
	var fort: int = int(entry.get("fort", 0))
	var parts: PackedStringArray = []
	if regiments <= 0:
		parts.append("No garrison")
	else:
		parts.append("%d strength · %d regiment%s" % [strength, regiments, _s(regiments)])
	if fort > 0:
		parts.append(
			"Fort %d (%d gun%s)" % [fort, int(entry.get("guns", 0)), _s(int(entry.get("guns", 0)))]
		)
	else:
		parts.append("No wall")
	var hospital: int = int(entry.get("hospital", 0))
	if hospital > 0:
		parts.append(HospitalRules.level_name(hospital))
	if bool(entry.get("foreign", false)):
		parts.append("Foreign host ashore")
	var ground: String = String(entry.get("terrain_line", ""))
	if not ground.is_empty():
		parts.append(ground)
	return " · ".join(parts)


# --- collection --------------------------------------------------------------


## Strength and headcount per (province, owner): one pass over the roster, so
## the province walk below never scans every army again.
static func _garrisons(armies: Array[ArmyState]) -> Dictionary:
	var table: Dictionary = {}
	for army: ArmyState in armies:
		if army == null or army.province == MapModel.NO_ID or army.embarked_fleet >= 0:
			continue
		var here: Dictionary = table.get(army.province, {})
		var row: Dictionary = here.get(army.owner, {"strength": 0, "regiments": 0})
		row["strength"] = int(row["strength"]) + public_strength(army)
		row["regiments"] = int(row["regiments"]) + army.regiments.size()
		here[army.owner] = row
		table[army.province] = here
	return table


## The published order of battle of one army: `FPN + FPM` per regiment, with no
## medal multiplier and no health scaling (wiki: diplomacy § Great Power power
## score).
static func public_strength(army: ArmyState) -> int:
	var total: int = 0
	for regiment_id: String in army.regiments:
		total += RegimentCatalog.strength(army.type_of(regiment_id))
	return total


static func _entry(
	model: MapModel,
	province: ProvinceState,
	garrisons: Dictionary,
	charted: int,
	player: int,
	visibility: VisibilityModel
) -> Dictionary:
	var here: Dictionary = garrisons.get(province.id, {})
	var own: Dictionary = here.get(province.owner, {"strength": 0, "regiments": 0})
	var garrison: int = int(own["strength"])
	var fort: int = FortRules.clamp_level(province.fort_level)
	## The ground the Combat phase would fight on — the same pick, not a second
	## ranking, so the reading can never name a different province's ground.
	var terrain: int = ArmyModifiers.terrain_for(model, province.id)
	var entry: Dictionary = {
		"id": province.id,
		"name": province.name,
		"owner": province.owner,
		"charted": charted,
		"strength": garrison,
		"regiments": int(own["regiments"]),
		"fort": fort,
		"guns": FortRules.guns(fort),
		"hospital": HospitalRules.clamp_level(province.hospital_level),
		"band": band_for(fort, garrison),
		"terrain": terrain,
		"terrain_name": terrain_name(terrain),
		"terrain_line": terrain_line(terrain),
		"shelters": shelters(terrain),
		"foreign": _has_foreign(here, province.owner),
		"anchor": _anchor(model, province, visibility),
	}
	entry["summary"] = summary_text(entry)
	return entry


## A province holds a foreign host when any crown but the owner keeps regiments
## there — a contested ground, not a garrison.
static func _has_foreign(here: Dictionary, owner: int) -> bool:
	for faction: int in here.keys():
		if faction != owner and int((here[faction] as Dictionary)["regiments"]) > 0:
			return true
	return false


## Plaque anchor: the province centre when it is known land, else the nearest
## charted land tile — an archipelago centre can fall in a bay or in fog.
static func _anchor(
	model: MapModel, province: ProvinceState, visibility: VisibilityModel
) -> Vector2:
	var center: Vector2 = province.center
	var guess := Vector2i(roundi(center.x), roundi(center.y))
	if _known_land(model, visibility, guess):
		return Vector2(guess)
	var best: Vector2i = guess
	var best_distance: float = INF
	for tile: Vector2i in province.tiles:
		if not _known_land(model, visibility, tile):
			continue
		var distance: float = Vector2(tile).distance_squared_to(center)
		if distance < best_distance:
			best_distance = distance
			best = tile
	return Vector2(best)


static func _known_land(
	model: MapModel, visibility: VisibilityModel, tile: Vector2i
) -> bool:
	if not model.is_land(tile.x, tile.y):
		return false
	if visibility == null:
		return true
	return visibility.level_at(tile.x, tile.y) != VisibilityModel.Level.UNKNOWN


static func _empty_counts() -> Dictionary:
	var counts: Dictionary = {}
	for band: String in BANDS:
		counts[band] = 0
	return counts


static func _s(count: int) -> String:
	return "" if count == 1 else "s"
