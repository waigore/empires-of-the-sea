class_name RegionBriefing
extends RefCounted
## Opening copy for the map screen: the first-turn briefing and the arrival
## note when a region opens. Presentation only, so MapScreen stays a thin
## controller (REQ-P3-01).


## `turn` is the campaign's own calendar: an advanced start opens at turn 50 or
## 100, so the briefing names that year rather than the first (wiki:
## advanced-starts).
static func opening(
	hud: GameHud, model: MapModel, capital_province: int, player: int,
	turn: int = 1
) -> void:
	hud.toast("The Indies await — Turn %d, %d" % [turn, TurnTime.year_for_turn(turn)])
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
