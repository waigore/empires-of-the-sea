class_name MapPlayRaids
extends RefCounted
## End-of-turn raid pass, both ways (wiki: ships-and-naval § Trade and Transport
## Interception; DR-20261110-13). Hostile patrols and blockades off the crown's
## coast pinch its imports; the crown's own stations pinch rival cargo as prize.
## Cargo only — no hull is sunk, captured or damaged on either side. Rules stay
## in NavalRaid; this applies the results to the ledgers, marks the map and
## reports them (REQ-P3-02, REQ-P3-03).

## Despatch lines per turn; the rest collapse into one summary.
const MAX_REPORTS: int = 4


static func resolve(play: PlaySession) -> Dictionary:
	if play.ship_layer == null or play.economy == null:
		return {}
	if play.economy.economy == null or play.economy.market == null:
		return {}
	var reports: Array[Dictionary] = []
	var incoming: Dictionary = _incoming(play)
	var prizes: Array[Dictionary] = _prizes(play)
	if not incoming.is_empty():
		reports.append(incoming)
	reports.append_array(prizes)
	if reports.is_empty():
		return {"ok": false, "taken": 0, "prize": 0, "prizes": [], "reports": []}
	_report(play, reports)
	return {
		"ok": true,
		"taken": int(incoming.get("taken", 0)),
		"prize": _prize_total(prizes),
		"prizes": prizes,
		"reports": reports,
	}


## Raiders working the crown's own waters skim this turn's imports. The cargo at
## risk is the crown's, not the whole order book's (DR-20261110-13). A raid never
## touches a hull, so the home fleet needs no repair pass.
static func _incoming(play: PlaySession) -> Dictionary:
	var imports: Dictionary = play.economy.market.imports_for(play.player_faction)
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
		play.turn,
		-1.0,
		play.has_tech
	)
	if not bool(result.get("ok", false)):
		return {}
	var taken: int = 0
	var losses: Dictionary = result.get("losses", {})
	for raw_id: Variant in losses.keys():
		var id: String = String(raw_id)
		var quantity: int = mini(int(losses[id]), play.economy.economy.quantity(id))
		if quantity <= 0:
			continue
		play.economy.economy.take(id, quantity)
		taken += quantity
	if taken <= 0:
		return {}
	result["kind"] = "incoming"
	result["taken"] = taken
	result["region"] = model.region_id
	result["zone_name"] = model.sea_zone_name(int(result.get("zone", -1)))
	return result


## The crown's own Patrol/Blockade squadrons take rival cargo as prize, region by
## region: a blockade off a rival coast pays (DR-20261110-13).
static func _prizes(play: PlaySession) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if play.world == null:
		return reports
	var importing: Array[int] = play.economy.market.importing_factions()
	if importing.is_empty():
		return reports
	var crown: PlayerEconomy = play.ledger_for(play.player_faction)
	if crown == null:
		return reports
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array = _roster(play, region)
		if roster.is_empty():
			continue
		var victims: Dictionary = _victims(play, importing, region)
		if victims.is_empty():
			continue
		var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
			model,
			roster,
			play.player_faction,
			victims,
			hostile(play),
			play.map_seed,
			play.turn,
			play.has_tech
		)
		for raid: Dictionary in raids:
			var seized: Dictionary = _seize(play, raid)
			if seized.is_empty():
				continue
			reports.append(_prize_report(model, raid, seized))
	return reports


## Victims this region can offer: a rival with cargo afloat and a home fleet in
## port at its own seat, so its laden hulls are in these waters.
static func _victims(play: PlaySession, importing: Array[int], region: int) -> Dictionary:
	var victims: Dictionary = {}
	for faction: int in importing:
		if faction == play.player_faction:
			continue
		var imports: Dictionary = play.economy.market.imports_for(faction)
		if imports.is_empty():
			continue
		var seat: int = play.world.seat_province(region, faction)
		if seat < 0:
			continue
		var home: FleetState = _in_port_at(_roster(play, region), faction, seat)
		if home == null:
			continue
		victims[faction] = {"imports": imports, "home": home}
	return victims


## Moves the raid's cargo from the rival's stockpile into the crown's. The prize
## is landed by the raiding squadron itself, so it needs no free cargo hold.
static func _seize(play: PlaySession, raid: Dictionary) -> Dictionary:
	var victim: PlayerEconomy = play.ledger_for(int(raid.get("victim", -1)))
	var crown: PlayerEconomy = play.ledger_for(play.player_faction)
	if victim == null or crown == null:
		return {}
	var losses: Dictionary = raid.get("losses", {})
	var seized: Dictionary = {}
	for raw_id: Variant in losses.keys():
		var id: String = String(raw_id)
		var quantity: int = mini(int(losses[id]), victim.quantity(id))
		if quantity <= 0:
			continue
		victim.take(id, quantity)
		crown.add(id, quantity)
		seized[id] = quantity
	return seized


static func _prize_report(model: MapModel, raid: Dictionary, seized: Dictionary) -> Dictionary:
	var zone: int = int(raid.get("zone", -1))
	return {
		"kind": "prize",
		"raider": int(raid.get("raider", -1)),
		"victim": int(raid.get("victim", -1)),
		"zone": zone,
		"region": model.region_id,
		"zone_name": model.sea_zone_name(zone),
		"taken": NavalRaid.total_of(seized),
		"losses": seized,
		"chance": float(raid.get("chance", 0.0)),
		"roll": float(raid.get("roll", 1.0)),
		"hulls_lost": [],
	}


static func _prize_total(prizes: Array[Dictionary]) -> int:
	var total: int = 0
	for prize: Dictionary in prizes:
		total += int(prize.get("taken", 0))
	return total


## Toasts and map rings for the turn's raids: the moment the ledger moves
## (REQ-P5-06). Sound is bound to the screen's `raid_resolved` signal.
static func _report(play: PlaySession, reports: Array[Dictionary]) -> void:
	var shown: int = 0
	for report: Dictionary in reports:
		if shown >= MAX_REPORTS:
			break
		shown += 1
		_mark(play, report)
		if play.hud != null:
			play.hud.toast(
				BattleReport.describe_raid(
					report, String(report.get("zone_name", "")),
					FactionCatalog.names(), play.player_faction
				)
			)
	if reports.size() > shown and play.hud != null:
		play.hud.toast(
			"%d more raids went unreported" % (reports.size() - shown)
		)
	play.emit_raid_resolved(reports)


static func _mark(play: PlaySession, report: Dictionary) -> void:
	if play.overlay == null or play.model == null:
		return
	if int(report.get("region", -1)) != play.model.region_id:
		return
	var zone: int = int(report.get("zone", -1))
	if zone < 0:
		return
	play.overlay.ripple(play.model.sea_zone_center(zone) * PlaySession.TILE_SIZE)


static func _roster(play: PlaySession, region: int) -> Array:
	var roster: Array = []
	if play.model != null and region == play.model.region_id:
		roster.assign(play.ship_layer.fleets)
	else:
		roster.assign(play.ship_layer.regions.value(region, []))
	return roster


static func _in_port_at(roster: Array, owner: int, province: int) -> FleetState:
	for fleet: FleetState in roster:
		if fleet == null or fleet.owner != owner:
			continue
		if fleet.is_in_port() and fleet.province == province:
			return fleet
	return null


## The crown's home squadron and the map it sits on, in any region: the ledger
## may be open on the New World while raiders work the Old World approaches.
static func _home(play: PlaySession) -> Dictionary:
	return home_entry(play, play.player_faction)


## Any crown's home squadron in port at its own seat, in whichever region that
## seat sits: the hulls whose cargo rides at risk (DR-20261110-13).
static func home_fleet(play: PlaySession, faction: int) -> FleetState:
	return home_entry(play, faction).get("fleet", null) as FleetState


static func home_entry(play: PlaySession, faction: int) -> Dictionary:
	if play.ship_layer == null or play.world == null:
		return {}
	for region: int in play.world.region_count():
		var seat: int = play.world.seat_province(region, faction)
		if seat < 0:
			continue
		var roster: Array = _roster(play, region)
		var fleet: FleetState = _in_port_at(roster, faction, seat)
		if fleet == null:
			continue
		return {"fleet": fleet, "model": play.world.region(region), "roster": roster}
	return {}


static func hostile(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(play.diplomacy, a, b)
