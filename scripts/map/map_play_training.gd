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
## and the voyage (REQ-P3-01).


## Queues a civilian hire at the capital. The treasury and paper are paid and
## the unit musters when the turn closes, so it takes orders with the next turn.
static func train(play: PlaySession, type_id: String) -> void:
	if play.selected_province != play.capital_province:
		play.hud.toast("Civilians are trained at the capital.")
		return
	var reason: String = _blocked_reason(play, type_id)
	if not reason.is_empty():
		play.hud.toast(reason)
		return
	play.economy.economy.queue_build(RecruitQueue.KIND_CIVILIAN, type_id)
	play.hud.toast(
		"%s is engaged at %s — ready next turn"
		% [
			CivilianCatalog.display_name(type_id),
			play.model.province_name(play.capital_province),
		]
	)


## Pays for and musters one queued civilian. The gate is read again at
## resolution, so a purse spent elsewhere in the turn still refuses the hire
## (wiki: civilian-units § Training; REQ-P2-03).
static func settle(play: PlaySession, type_id: String) -> Dictionary:
	var reason: String = _blocked_reason(play, type_id)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var state: PlayerEconomy = play.economy.economy
	state.spend_treasury(CivilianCatalog.treasury_cost(type_id))
	state.take("paper", CivilianCatalog.paper_cost(type_id))
	var unit: CivilianState = play.civilian_layer.add_unit(
		play.player_faction, type_id, play.civilian_layer.mustering_tile(play.capital_province)
	)
	if play.hud != null:
		play.hud.set_treasury(play.treasury())
		play.hud.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
	return {"ok": true, "reason": "", "unit": unit}


## Empty string when a civilian may be engaged at the capital; otherwise the
## wiki reason. The order path and the Build/work pass share this one gate.
static func _blocked_reason(play: PlaySession, type_id: String) -> String:
	if not CivilianCatalog.known(type_id):
		return "Unknown civilian."
	if not CivilianCatalog.is_implemented(type_id):
		return CivilianCatalog.deferred_reason(type_id)
	if not CivilianCatalog.is_unlocked(type_id, play.tech_unlocked()):
		return (
			"Requires %s."
			% TechCatalog.display_name(CivilianCatalog.unlock_tech(type_id))
		)
	if play.economy == null or play.economy.economy == null:
		return "The crown keeps no ledger."
	var state: PlayerEconomy = play.economy.economy
	if not CivilianCatalog.can_afford(
		type_id, state.treasury, state.quantity("paper")
	):
		return "The crown cannot afford a %s." % CivilianCatalog.display_name(type_id)
	if play.civilian_layer.mustering_tile(play.capital_province).x < 0:
		return "There is no room to muster another civilian."
	return ""
