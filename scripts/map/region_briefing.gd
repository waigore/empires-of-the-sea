class_name RegionBriefing
extends RefCounted
## Opening copy for the map screen: the first-turn briefing and the arrival
## note when a region opens. Presentation only, so MapScreen stays a thin
## controller (REQ-P3-01).


static func opening(
	hud: GameHud, model: MapModel, capital_province: int, player: int
) -> void:
	hud.toast("The Indies await — Turn 1, 1500")
	hud.toast(
		"%d Great Powers, %d minor nations, %d tribes"
		% [
			FactionCatalog.great_power_ids().size(),
			FactionCatalog.minor_ids().size(),
			FactionCatalog.tribe_ids().size(),
		]
	)
	if capital_province < 0:
		return
	hud.toast(
		"%s holds court at %s"
		% [FactionCatalog.name_of(player), model.province_name(capital_province)]
	)


static func arrival(hud: GameHud, model: MapModel, region_index: int) -> void:
	hud.toast(
		"%s — %d provinces"
		% [FactionCatalog.region_label(region_index), model.province_count()]
	)
	if region_index != FactionCatalog.NEW_WORLD:
		return
	hud.toast(
		"Lands of the %d tribes — unexplored and uncharted"
		% FactionCatalog.tribe_ids().size()
	)
