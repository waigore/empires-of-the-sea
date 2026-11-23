class_name MapPlayTraining
extends RefCounted
## Hiring a civilian at the capital: the order the muster list places and the
## Build/work delivery it promised (wiki: civilian-units § Training;
## workers-and-population § Phase placement). Costs and gates stay in
## [CivilianCatalog] and [CivilianWorkPlan]; this only routes the order and
## reports it (REQ-P3-02).
##
## Training left [MapPlayCivilians] because it is a Build/work order like the
## drill yard's and the slip's, and the civilian module keeps the work orders
## and the voyage (REQ-P3-01). The seat every hire lands at is the crown's own
## seat, read off the world and never off the chart on screen: a crown looking
## at a colony when the turn closes still hires at its capital, and a province
## on that chart wearing the seat's own number hires nobody (wiki:
## capital-and-connectivity § Capital; world-model-identity).

## A hire ordered from the wrong chart waits at the capital: the sheet says where
## rather than claiming the ground under the tap.
const AT_SEAT_ONLY: String = "Civilians are trained at the capital — %s."


## Queues a civilian hire at the capital. The treasury and paper are paid and
## the unit musters when the turn closes, so it takes orders with the next turn.
static func train(play: PlaySession, type_id: String) -> void:
	var seat: Dictionary = MapPlayCourtHoldings.crown_seat(play)
	var at_seat: bool = (
		int(seat["region"]) == play.region_index
		and play.selected_province == int(seat["province"])
	)
	if not at_seat:
		play.hud.toast(_elsewhere(seat))
		return
	var reason: String = _blocked_reason(play, type_id)
	if not reason.is_empty():
		play.hud.toast(reason)
		return
	play.economy.economy.queue_build(RecruitQueue.KIND_CIVILIAN, type_id)
	play.hud.toast(
		"%s is engaged at %s — ready next turn"
		% [CivilianCatalog.display_name(type_id), _seat_name(seat)]
	)


## Pays for and musters one queued civilian. The gate is read again at
## resolution, so a purse spent elsewhere in the turn still refuses the hire
## (wiki: civilian-units § Training; REQ-P2-03). The muster lands on the seat's
## own chart, whether or not that chart is the one the crown is looking at.
static func settle(play: PlaySession, type_id: String) -> Dictionary:
	var seat: Dictionary = MapPlayCourtHoldings.crown_seat(play)
	if int(seat["province"]) == MapModel.NO_ID:
		return {"ok": false, "reason": "Your capital is not in hand."}
	var reason: String = _blocked_reason(play, type_id)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var region: int = int(seat["region"])
	var model: MapModel = seat["model"]
	var roster: Array = play.civilian_layer.regions.value(region, [])
	var tile: Vector2i = CivilianMuster.mustering_tile(model, int(seat["province"]), roster)
	if tile.x < 0:
		return {"ok": false, "reason": "There is no room to muster another civilian."}
	var state: PlayerEconomy = play.economy.economy
	state.spend_treasury(CivilianCatalog.treasury_cost(type_id))
	state.take("paper", CivilianCatalog.paper_cost(type_id))
	var unit: CivilianState = CivilianMuster.append_unit(
		play, region, roster, play.player_faction, type_id, tile
	)
	if play.hud != null:
		play.hud.stats.set_treasury(play.treasury())
		play.hud.stats.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
	return {"ok": true, "reason": "", "unit": unit, "place": _seat_name(seat)}


## Empty string when a civilian may be engaged at the capital; otherwise the
## wiki reason. The order path and the Build/work pass share this one gate.
static func _blocked_reason(play: PlaySession, type_id: String) -> String:
	if not CivilianCatalog.known(type_id):
		return "Unknown civilian."
	if not CivilianCatalog.is_implemented(type_id):
		return CivilianCatalog.deferred_reason(type_id)
	var tech: String = CivilianHire.locked_tech(type_id, play.tech_unlocked())
	if not tech.is_empty():
		return "Requires %s." % TechCatalog.display_name(tech)
	if play.economy == null or play.economy.economy == null:
		return "The crown keeps no ledger."
	var state: PlayerEconomy = play.economy.economy
	if not CivilianCatalog.can_afford(
		type_id, state.treasury, state.quantity("paper")
	):
		return "The crown cannot afford a %s." % CivilianCatalog.display_name(type_id)
	if _muster_tile(play).x < 0:
		return "There is no room to muster another civilian."
	return ""


## The free tile a hire would muster on: the seat's own chart, whatever chart is
## on screen (wiki: civilian-units § Training).
static func _muster_tile(play: PlaySession) -> Vector2i:
	var seat: Dictionary = MapPlayCourtHoldings.crown_seat(play)
	var model: MapModel = seat["model"]
	if model == null or int(seat["province"]) == MapModel.NO_ID:
		return CivilianState.NO_TILE
	var roster: Array = play.civilian_layer.regions.value(int(seat["region"]), [])
	return CivilianMuster.mustering_tile(model, int(seat["province"]), roster)


## What a hire hears away from the seat: the capital by name when the crown has
## one, the plain rule when it has none.
static func _elsewhere(seat: Dictionary) -> String:
	var name: String = _seat_name(seat)
	if name.is_empty():
		return "Civilians are trained at the capital."
	return AT_SEAT_ONLY % name


static func _seat_name(seat: Dictionary) -> String:
	var model: MapModel = seat["model"]
	var province: int = int(seat["province"])
	if model == null or province == MapModel.NO_ID:
		return ""
	return model.province_name(province)