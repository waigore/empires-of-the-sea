class_name MapPlayRaids
extends RefCounted
## End-of-turn raid pass: hostile patrols and blockades in the crown's waters
## skim the home fleet's imports (wiki: ships-and-naval § Trade and Transport
## Interception; DR-20261109-16). Rules stay in NavalRaid; this applies the
## result to the live ledger and reports it (REQ-P3-02, REQ-P3-03).


static func resolve(play: PlaySession) -> Dictionary:
	if play.ship_layer == null or play.economy == null:
		return {}
	if play.economy.economy == null or play.economy.market == null:
		return {}
	var imports: Dictionary = play.economy.market.imports_this_turn()
	if imports.is_empty():
		return {}
	var home: Dictionary = _home(play)
	if home.is_empty():
		return {}
	var fleet: FleetState = home["fleet"] as FleetState
	var model: MapModel = home["model"] as MapModel
	var roster: Array = home["roster"]
	var result: Dictionary = NavalRaid.resolve(
		model,
		roster,
		play.player_faction,
		fleet,
		imports,
		hostile(play),
		play.map_seed,
		play.turn
	)
	if not bool(result.get("ok", false)):
		return result
	var taken: int = 0
	var losses: Dictionary = result.get("losses", {})
	for raw_id: Variant in losses.keys():
		var id: String = String(raw_id)
		var quantity: int = mini(int(losses[id]), play.economy.economy.quantity(id))
		if quantity <= 0:
			continue
		play.economy.economy.take(id, quantity)
		taken += quantity
	if taken > 0 and play.hud != null:
		play.hud.toast("Raiders seize %d cargo from the home fleet" % taken)
	result["taken"] = taken
	return result


## The crown's home squadron and the map it sits on, in any region: the ledger
## may be open on the New World while raiders work the Old World approaches.
static func _home(play: PlaySession) -> Dictionary:
	if play.ship_layer == null or play.world == null:
		return {}
	for region: int in play.world.region_count():
		var seat: int = play.world.seat_province(region, play.player_faction)
		if seat < 0:
			continue
		var roster: Array = []
		if play.model != null and region == play.model.region_id:
			roster.assign(play.ship_layer.fleets)
		else:
			roster.assign(play.ship_layer.regions.value(region, []))
		for fleet: FleetState in roster:
			if fleet == null or fleet.owner != play.player_faction:
				continue
			if not fleet.is_in_port() or fleet.province != seat:
				continue
			return {"fleet": fleet, "model": play.world.region(region), "roster": roster}
	return {}


static func hostile(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(play.diplomacy, a, b)
