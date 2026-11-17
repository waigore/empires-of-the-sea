class_name ObserverProvince
extends RefCounted
## The observatory's read-only province reading (docs/ai-observer.md): what one
## province holds, read for the court that owns it — the ground, the town, the
## estates, the wall, the ward and the host standing there.
##
## Every word is another module's own: the estate rows are `ResourceSurvey`'s,
## the crown link `LandConnectivity`'s, the wall and the ward `FortRules` and
## `HospitalRules`, the band `DefenceSurvey`'s. This module only gathers them for
## the province the observer tapped, so the sheet can never name a number the
## rules would not (REQ-P2-03, REQ-P3-03). It orders nothing and reads no
## private ledger: the observer sees what the chart shows, not a court's books.

const NO_ID: int = MapModel.NO_ID


## One province's reading, or {} when the id names no province on the chart on
## screen. `play.land_works` is the region's works, so the estates are the ones
## the chart draws; the owner's own capital is the seat the crown link reads.
static func reading(play: PlaySession, province_id: int) -> Dictionary:
	if play == null or play.world == null or play.model == null:
		return {}
	var model: MapModel = play.model
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return {}
	var owner: int = province.owner
	var works: LandWorks = play.land_works
	var seat: Dictionary = WorldBootstrap.capital_seat(model, owner)
	var capital: Vector2i = seat["tile"]
	var blockade: Blockades = MapPlayBlockades.of(play, owner)
	var rows: Array[Dictionary] = [] as Array[Dictionary]
	var unsurveyed: int = 0
	var crown: Dictionary = {}
	if works != null:
		rows = ResourceSurvey.province_rows(
			model, works, _units(play), owner, province_id, null, capital,
			_tech_caps(play, owner), blockade
		)
		unsurveyed = MineralSurvey.unsurveyed_in_province(
			model, works, owner, province_id
		).size()
		crown = LandConnectivity.province_link(
			model, works, owner, capital, province_id, blockade
		)
	var host: Dictionary = _host(play, model, province, owner)
	return {
		"id": province_id,
		"name": province.name,
		"capital": province.capital,
		"owner": owner,
		"owner_caption": ProvinceSheetHead.owner_caption(owner),
		"terrain": _terrain(model, province_id),
		"port": _port(model, province),
		"town": DossierCopy.town(province),
		"town_tip": DossierCopy.town_tip(province),
		"roads": (
			DossierCopy.crown_roads(province, crown)
			if crown.has("linked") else DossierCopy.roads(rows)
		),
		"fort": FortRules.describe(province.fort_level),
		"hospital": HospitalRules.describe(
			province.hospital_level, province.hospital_staffed
		),
		"estates": rows,
		"unsurveyed": unsurveyed,
		"band": DefenceSurvey.band_for(province.fort_level, int(host["strength"])),
		"band_label": DefenceSurvey.band_label(
			DefenceSurvey.band_for(province.fort_level, int(host["strength"]))
		),
		"strength": int(host["strength"]),
		"regiments": int(host["regiments"]),
		"defence": _defence_text(host),
	}


## The ground a battle in this province would be fought on, in the published
## display name — `ArmyModifiers.terrain_for`'s own call, so the sheet cannot
## name ground the Combat phase would not use (wiki:
## resource-terrain-region-rules § Player-facing terrain display names).
static func _terrain(model: MapModel, province_id: int) -> String:
	var ground: int = ArmyModifiers.terrain_for(model, province_id)
	return String(MapModel.TERRAIN_LABELS.get(ground, "Unknown"))


## A harbour names the sea zone it opens on; landlocked ground says so.
static func _port(model: MapModel, province: ProvinceState) -> String:
	var tile: Vector2i = province.port_tile
	if tile.x < 0:
		return "Landlocked"
	return "Harbour · %s" % model.sea_zone_name(model.sea_zone_at(tile.x, tile.y))


## The host standing in the province: the owner's own regiments and their
## published strength (`FPN + FPM`, no medals, no health — the same reading the
## defence lens projects), and whether another crown keeps regiments there.
static func _host(
	play: PlaySession, model: MapModel, province: ProvinceState, owner: int
) -> Dictionary:
	var host: Dictionary = {"strength": 0, "regiments": 0, "foreign": false}
	if play.army_layer == null:
		return host
	var armies: Array = play.army_layer.regions.value(model.region_id, [])
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army == null or army.province != province.id or army.embarked_fleet >= 0:
			continue
		if army.owner == owner:
			host["strength"] = int(host["strength"]) + DefenceSurvey.public_strength(army)
			host["regiments"] = int(host["regiments"]) + army.regiments.size()
		elif not army.regiments.is_empty():
			host["foreign"] = true
	return host


## The defence line in the lens's own words, so the sheet and the military
## reading never disagree about what would meet an attack.
static func _defence_text(host: Dictionary) -> String:
	var regiments: int = int(host["regiments"])
	var parts: PackedStringArray = PackedStringArray()
	if regiments <= 0:
		parts.append("No garrison")
	else:
		parts.append("%d strength · %d regiment%s" % [
			int(host["strength"]), regiments, "" if regiments == 1 else "s",
		])
	if bool(host["foreign"]):
		parts.append("Foreign host ashore")
	return " · ".join(parts)


## The civilians the estate rows read: the region's roster, whichever crown
## holds them, because a rival's Builder at work is a fact the chart draws.
static func _units(play: PlaySession) -> Array[CivilianState]:
	if play.civilian_layer == null:
		return [] as Array[CivilianState]
	return play.civilian_layer.units


## The owner's researched extraction caps, read from its own ledger; a court
## with no ledger yet (a Minor or Tribe) reads the bare terrain caps.
static func _tech_caps(play: PlaySession, owner: int) -> Dictionary:
	var ledger: PlayerEconomy = play.ledger_for(owner)
	if ledger == null:
		return {}
	return TechCatalog.extraction_caps(ledger.tech_unlocked)
