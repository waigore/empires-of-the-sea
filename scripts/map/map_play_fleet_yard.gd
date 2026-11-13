class_name MapPlayFleetYard
extends RefCounted
## The crown's capital shipyard as a map intent: slip rows, opening the yard from
## the province dossier, and launching or breaking up hulls (wiki: ships-and-naval
## § Ship muster and the breaker's yard). Rules stay in FleetYard/NavalTransport;
## this only routes the order and reports to the court (REQ-P3-02).
##
## Each layer owns the yard once: FleetYard prices a hull, this routes the order,
## FleetYardBlock draws the rows. Sailing and fog intel stay on MapPlayFleets.


## Slip rows for an own squadron: launching needs the capital port, breaking up a
## hull works anywhere (wiki: ships-and-naval § Ship muster and the breaker's
## yard).
static func rows(play: PlaySession, fleet: FleetState) -> Array[Dictionary]:
	if fleet == null or fleet.owner != play.player_faction or play.economy == null:
		return []
	return FleetYard.rows(play.economy.economy, _is_home(play, fleet))


## Opens the capital yard from the province dossier; with no home fleet afloat the
## slip is shown and the first launch founds the squadron.
static func open(play: PlaySession) -> void:
	var province: int = play.capital_province
	if province < 0 or play.model.province_owner(province) != play.player_faction:
		play.hud.toast("Your capital must be in hand to open the yard.")
		return
	if not NavalMovement.has_harbour(play.model, province):
		play.hud.toast("Your capital has no harbour for a yard.")
		return
	var home: FleetState = play.ship_layer.home_fleet(province)
	if home != null:
		refresh(play, home)
		return
	if play.economy == null:
		return
	play.hud.panels.show_fleet(
		play.model, null, true, "", FleetYard.rows(play.economy.economy, true), province
	)


static func refresh(play: PlaySession, fleet: FleetState) -> void:
	if fleet == null:
		return
	play.ship_layer.select(play.ship_layer.ship_for(fleet))
	MapPlayFleets.show_dossier(play, fleet)
	play.hud.panels.fleet_panel.set_yard_open(true)


## Queues one hull at the capital slip. A launch is a `BuildUnitOrder`: the
## ledger pays and the hull joins the home fleet in Build/work at the turn's
## close, so she sails with the next Orders phase (wiki: ships-and-naval
## § Ship build economy; workers-and-population § Phase placement).
static func launch(play: PlaySession, type_id: String) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var province: int = play.capital_province
	if province < 0 or play.model.province_owner(province) != play.player_faction:
		play.hud.toast("Your capital must be in hand to launch hulls.")
		return
	if not NavalMovement.has_harbour(play.model, province):
		play.hud.toast("Your capital has no harbour for a yard.")
		return
	var economy: PlayerEconomy = play.economy.economy
	var reason: String = ShipEconomy.blocked_reason(
		type_id,
		economy.treasury,
		economy.stockpile,
		economy.available_peasants(),
		economy.tech_unlocked
	)
	if not reason.is_empty():
		play.hud.toast(reason)
		return
	economy.queue_build(RecruitQueue.KIND_SHIP, type_id)
	play.hud.toast(
		"%s is laid down at %s — she launches next turn"
		% [ShipStats.display_name(type_id), play.model.province_name(province)]
	)
	refresh(play, play.ship_layer.home_fleet(province))


## Breaks up one hull and returns its peasant to the pool.
static func scrap(play: PlaySession, hull_id: String) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return
	var carried_army: ArmyState = ArmyTransport.army_by_id(
		play.army_layer, fleet.embarked_army
	)
	var can_break: Dictionary = NavalTransport.can_scrap(fleet, carried_army)
	if not bool(can_break.get("ok", false)):
		play.hud.toast(String(can_break.get("reason", "The hull stays afloat.")))
		return
	var result: Dictionary = play.ship_layer.scrap_hull(fleet, hull_id, play.economy.economy)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The hull stays afloat.")))
		return
	play.hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	var broken: String = String(result.get("name", ""))
	if broken.is_empty():
		broken = ShipStats.display_name(String(result.get("type", "")))
	play.hud.toast("%s broken up — one peasant returns to the pool" % broken)
	if bool(result.get("retired", false)):
		play.hud.panels.hide_fleet()
		return
	refresh(play, fleet)


## Routes a shipyard intent from the fleet dossier or the province yard:
## `yard:build:<type>` launches a hull, `yard:scrap:<hull>` breaks one up.
## False when the order belongs to another panel (REQ-P3-02).
static func on_action(play: PlaySession, action: String) -> bool:
	if action.begins_with("yard:build:"):
		launch(play, action.trim_prefix("yard:build:"))
		return true
	if action.begins_with("yard:scrap:"):
		scrap(play, action.trim_prefix("yard:scrap:"))
		return true
	return false


## True when this squadron is the crown's home fleet at its capital port.
static func _is_home(play: PlaySession, fleet: FleetState) -> bool:
	if fleet == null or fleet.owner != play.player_faction or not fleet.is_in_port():
		return false
	return fleet.province >= 0 and fleet.province == play.capital_province
