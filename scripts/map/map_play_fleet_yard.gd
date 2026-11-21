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
	return FleetYard.rows(play.economy.economy, _is_home(play, fleet), flown(play))


## The craft this court flies or has flown: the opening muster's hulls and every
## launch kept in its ledger, the same list a rival court's yard reads, so a hull
## already in the crown's own water may be replaced without her study
## (issue #484; REQ-P2-03).
static func flown(play: PlaySession) -> Array[String]:
	return MapPlayCourt.hull_types(play, play.player_faction)


## Opens the capital yard from the province dossier; with no home fleet afloat the
## slip is shown and the first launch founds the squadron.
static func open(play: PlaySession) -> void:
	if not _at_slip(play):
		return
	var province: int = int(MapPlayCourt.crown_seat(play)["province"])
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
	var opening := FleetDossierOpening.new()
	opening.is_player = true
	opening.slip = province
	opening.yard_rows = FleetYard.rows(play.economy.economy, true, flown(play))
	opening.yard_pick = MapPlayYardPick.line(play)
	play.hud.panels.show_fleet(play.model, opening)


static func refresh(play: PlaySession, fleet: FleetState) -> void:
	if fleet == null:
		# The capital slip with no squadron afloat has no dossier to redraw: the
		# yard re-reads its own rows from the ledger, so a launch taken there
		# cannot leave the slip promising hulls the orders already claim
		# (wiki: ships-and-naval § Ship muster and the breaker's yard;
		# DR-20261118-08).
		open(play)
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
	if not _at_slip(play):
		return
	var province: int = int(MapPlayCourt.crown_seat(play)["province"])
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
		economy.tech_unlocked,
		flown(play)
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


## The yard's one press: every ready hull on the slip, one each, in the yard's
## order — the same `BuildUnitOrder` a row's Launch press files, so the price,
## the study gate, the peasant and the phase stay in ShipEconomy/FleetYard
## (REQ-P2-03, REQ-P5-04; DR-20261118-08). The walk stops at the first refusal,
## because that refusal is the rules' answer for the realm, and the court reads
## one receipt instead of a lane of toasts (REQ-P5-05).
static func launch_all(play: PlaySession) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	if not _at_slip(play):
		return
	var province: int = int(MapPlayCourt.crown_seat(play)["province"])
	if province < 0 or play.model.province_owner(province) != play.player_faction:
		play.hud.toast("Your capital must be in hand to launch hulls.")
		return
	if not NavalMovement.has_harbour(play.model, province):
		play.hud.toast("Your capital has no harbour for a yard.")
		return
	var economy: PlayerEconomy = play.economy.economy
	var craft: Array[String] = flown(play)
	var types: Array[String] = FleetYard.batch_types(economy, true, craft)
	if types.is_empty():
		return
	var result: Dictionary = FleetYard.queue_all(economy, true, types, craft)
	play.hud.toast(_batch_receipt(result))
	refresh(play, play.ship_layer.home_fleet(province))


## The one line the yard's batch leaves on the court's lane: what it laid down,
## what it paid and what the next hull waits on (REQ-P5-05; DR-20261118-11).
static func _batch_receipt(result: Dictionary) -> String:
	var filed: int = int(result.get("filed", 0))
	var total: int = int(result.get("total", 0))
	var refusal: String = String(result.get("refusal", ""))
	if filed == 0 and not refusal.is_empty():
		return refusal
	var spent: String = RaiseBatchSum.paid(result)
	var laid: String = (
		"%d hulls are laid down for %s — they launch next turn" % [filed, spent]
		if filed != 1
		else "One hull is laid down for %s — she launches next turn" % spent
	)
	if refusal.is_empty():
		return laid
	return "%d of %d hulls are laid down for %s — the next waits: %s" % [
		filed, total, spent, refusal
	]


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
	var can_break: Dictionary = NavalDeck.can_scrap(fleet, carried_army)
	if not bool(can_break.get("ok", false)):
		play.hud.toast(String(can_break.get("reason", "The hull stays afloat.")))
		return
	var result: Dictionary = ShipYardOps.scrap_hull(
		play.ship_layer, fleet, hull_id, play.economy.economy
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The hull stays afloat.")))
		return
	play.hud.stats.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
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
	if action == "yard:launch_all":
		launch_all(play)
		return true
	if action.begins_with("yard:build:"):
		launch(play, action.trim_prefix("yard:build:"))
		return true
	if action.begins_with("yard:scrap:"):
		scrap(play, action.trim_prefix("yard:scrap:"))
		return true
	return false


## True when this squadron is the crown's home fleet at its capital port. The
## seat is the crown's own, read off the world: on a chart with no seat the
## framing field holds a colony, and a squadron moored there is no home fleet
## (wiki: capital-and-connectivity § Capital).
static func _is_home(play: PlaySession, fleet: FleetState) -> bool:
	if fleet == null or fleet.owner != play.player_faction or not fleet.is_in_port():
		return false
	var seat: int = int(MapPlayCourt.crown_seat(play)["province"])
	return fleet.province >= 0 and fleet.province == seat


## True when the chart on screen holds the crown's seat: the yard stands at the
## capital, so a province on another chart — even one wearing the seat's own
## number — lays no keel. False answers the press with where the yard really
## stands (wiki: world-model-identity; capital-and-connectivity § Capital).
static func _at_slip(play: PlaySession) -> bool:
	var seat: Dictionary = MapPlayCourt.crown_seat(play)
	var region: int = int(seat["region"])
	var province: int = int(seat["province"])
	if region == MapModel.NO_ID or province == MapModel.NO_ID:
		return true
	if region == play.region_index:
		return true
	var model: MapModel = seat["model"]
	play.hud.toast("The yard stands at %s, on the %s chart — open it to lay a keel." % [
		model.province_name(province), FactionCatalog.region_label(region),
	])
	return false
