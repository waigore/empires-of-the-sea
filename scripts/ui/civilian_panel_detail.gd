class_name CivilianPanelDetail
extends RefCounted
## A civilian dossier's ground: the province, tile and deed, the mineral read
## through the viewer's own survey record, the works standing on it, an
## Explorer's survey left to do and a spy's tradecraft (wiki: civilian-units §
## Work Order Summary; fog-and-exploration § Prospecting). Keeps the sheet's
## reading out of its widgets, so [CivilianPanel] composes and this module words
## (REQ-P3-01, REQ-P3-03).


## One caption/value row per fact, in the order the sheet prints them. The
## caller owns the grid; this module only answers with words.
## `viewer` is the court reading the sheet, which is not always the crew's owner:
## a rival's crew is observe-only, and the ground is read through the *viewer's*
## survey record (wiki: fog-and-exploration § Prospecting — per court;
## DR-20261111-26).
static func rows(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	context: Dictionary,
	viewer: int = FactionCatalog.PLAYER_FACTION
) -> Array[Array]:
	var result: Array[Array] = []
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	result.append(["Province", model.province_name(province) if province >= 0 else "—"])
	result.append(["Tile", "%d, %d" % [unit.tile.x, unit.tile.y]])
	result.append(["Held by", FactionCatalog.name_of(model.owner_at(unit.tile.x, unit.tile.y))])
	if model.is_purchased_tile(unit.tile):
		result.append(["Deed", "Purchased land"])
	result.append(["Resource", _resource_text(model, works, unit.tile, viewer)])
	result.append(["Works", _works_text(model, works, unit.tile, viewer)])
	if unit.type_id == "explorer" and viewer == unit.owner:
		result.append(["Survey", _survey_text(model, works, unit, province, context)])
	var province_data: ProvinceState = model.province_data(province)
	if province_data != null and province_data.is_town_tile(unit.tile):
		result.append(["Town", "Level %d / 4" % province_data.town_level()])
	if unit.type_id == SpyNetworks.SPY_TYPE:
		result.append(["Tradecraft", _tradecraft_text(model, unit)])
	return result


## What the ground holds, as far as the viewer has read it: a hidden mineral is
## never named here; the ground itself is the news (wiki: fog-and-exploration §
## Prospecting; DR-20261111-26).
static func _resource_text(
	model: MapModel, works: LandWorks, tile: Vector2i, viewer: int
) -> String:
	var resource: int = MineralSurvey.known_resource(model, works, viewer, tile)
	if resource >= 0:
		return String(MapGenerator.resource_info(resource).get("name", "—"))
	if MineralSurvey.prospectable(model, tile):
		return "Unsurveyed ground"
	return "None surveyed"


## Every work standing on the tile, the finest transport named first.
static func _works_text(
	model: MapModel, works: LandWorks, tile: Vector2i, viewer: int
) -> String:
	var development: PackedStringArray = PackedStringArray()
	var level: int = works.improvement_at(model, tile)
	if level > 0:
		development.append(
			ImprovementCatalog.display_name(model.resource_at(tile.x, tile.y), level)
		)
	if works.transport_at(model, tile) >= LandWorks.TRANSPORT_RAIL:
		development.append("Railroad")
	elif works.transport_at(model, tile) >= LandWorks.TRANSPORT_IMPROVED_ROAD:
		development.append("Improved road")
	elif works.transport_at(model, tile) >= LandWorks.TRANSPORT_ROAD:
		development.append("Road")
	if works.has_port(model, tile):
		development.append("Port")
	if works.is_prospected(viewer, model, tile):
		development.append("Prospected")
	return " · ".join(development) if not development.is_empty() else "—"


## What an Explorer has left to read here: the survey is the one order whose
## target is not the ground underfoot, so the dossier says how much is left and
## whether this province can be read at all (DR-20261111-26). A Minor or Tribe
## province without a Consulate offers no ground to survey, so the row names the
## gate rather than promising taps the rules would refuse (REQ-P2-03).
static func _survey_text(
	model: MapModel,
	works: LandWorks,
	unit: CivilianState,
	province: int,
	context: Dictionary
) -> String:
	var gate: String = CivilianExplorerGates.consulate_refusal(
		model, unit.owner, province, context
	)
	if not gate.is_empty():
		return gate
	var left: int = MineralSurvey.unsurveyed_in_province(
		model, works, unit.owner, province
	).size()
	if left <= 0:
		return "Every prospectable tile here is charted"
	return "%d tile%s still to survey — tap one on the map" % [
		left, "" if left == 1 else "s"
	]


## What the spy's standing actually buys where it stands: a shadowed court only
## shares its research when it is a Great Power (wiki: civilian-units § Spy (2);
## DR-20261110-03), and the counter-espionage screen exists only while the order
## is up (wiki: civilian-units § Spy (3)). A dossier that promised a share from
## a minor court, or a screen from an idle spy, would claim an outcome the rules
## never grant (REQ-P2-03).
static func _tradecraft_text(model: MapModel, unit: CivilianState) -> String:
	var host: int = model.owner_at(unit.tile.x, unit.tile.y)
	if host == MapModel.NO_ID:
		return "Unclaimed land — no court to shadow"
	if host == unit.owner:
		if unit.work_action() == SpyRules.WORK_COUNTER:
			# The order costs a spy that could be shadowing a rival for +15% RP,
			# so the dossier names what the screen buys before the court commits
			# (wiki: civilian-units § Spy (3)).
			return (
				"Counter-espionage screen — empire-wide; %d%% a turn to take a"
				+ " rival agent, %d%% to turn one."
			) % [SpyRules.KILL_PCT, SpyRules.DEFECT_PCT]
		return "No screen up — only the counter-espionage order covers your land"
	var host_name: String = FactionCatalog.name_of(host)
	if FactionCatalog.type_of(host) == FactionCatalog.Type.GREAT_POWER:
		return "Shadows %s — presence reveal, +%d%% RP" % [
			host_name, SpyNetworks.BOOST_PERCENT
		]
	return "Shadows %s — presence reveal only; only Great Powers share research" % host_name