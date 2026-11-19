extends RefCounted
## Seventh step of the e2e smoke: the crown's forces — a fleet's station and
## sail, the regiment press that queues for Build/work, and the home squadron
## carrying an idle civilian ashore (DR-20261109-17, wiki: ships-and-naval).
## The navy and the press run inside the turn; the colonists wait until it has
## closed, so the driver calls that step on its own.
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeFind = preload("res://tools/smoke/smoke_find.gd")


## Player navy path: sortie the home fleet, select it and spend its one move.
static func step_navy(run) -> void:
	var screen: MapScreen = run.screen
	var capital: int = screen.play.capital_province
	# The opening muster moors every hull in the home fleet (issue #1043), so
	# the navy path starts with the sortie a player makes from the dossier.
	var fleet: FleetState = screen.ship_layer.home_fleet(capital)
	run.check(fleet != null, "home fleet mustered at the seat")
	if fleet == null:
		return
	var zones: Array[int] = NavalMovement.province_sea_zones(screen.model, capital)
	run.check(not zones.is_empty(), "the seat has a sea zone")
	if zones.is_empty():
		return
	MapPlayCivilianVoyage.sortie(screen.play, fleet, zones[0])
	run.check(fleet.is_at_sea(), "the home squadron sorties")
	var ship: Ship = screen.ship_layer.ship_for(fleet)
	run.check(ship != null, "the home squadron flies a marker")
	if ship == null:
		return
	# Give the sortie's move back so the station and sail rows are still open.
	fleet.moved = false
	screen.ship_layer.select(ship)
	await run.tree.process_frame
	run.check(screen.ship_layer.selected() == ship, "fleet selection sticks")
	run.check(screen.hud.panels.is_fleet_panel_open(), "fleet dossier opens")
	run.check(
		MapPlayFleetMissions.rows(screen.play, fleet).size() > 0,
		"fleet dossier offers a station"
	)
	# The dossier prints the combat maths the resolver fights with, and the map
	# marker flies the squadron's hulls (wiki: ships-and-naval § Naval Strength).
	run.check(screen.hud._fleet_panel._strength.visible, "fleet strength block shows")
	run.check(
		screen.hud._fleet_panel._strength._strength.text.contains("FRP"),
		"fleet strength names its weights"
	)
	run.check(
		screen.ship_layer.ship_for(fleet).hull_count == fleet.ship_count(),
		"fleet marker flies the squadron's hulls"
	)
	run.check(
		screen.ship_layer.ship_for(fleet).strength_known,
		"the crown reads her own squadron's weight"
	)
	MapPlayFleets.on_action(screen.play, "mission:patrol")
	run.check(
		fleet.mission == FleetState.Mission.PATROL and fleet.moved,
		"patrol station applies and spends the move"
	)
	# Give the move back so the smoke also proves the sail path.
	fleet.moved = false
	var zones: Array = NavalMovement.destination_zones(screen.model, fleet)
	run.check(not zones.is_empty(), "fleet has a sail destination")
	if zones.is_empty():
		return
	var zone: int = int(zones[0])
	var tile: Vector2i = screen.model.sea_zones[zone].tiles[0]
	run.check(MapPlayFleets.try_order(screen.play, tile), "fleet sails")
	run.check(fleet.sea_zone == zone and fleet.moved, "fleet spends its move")
	run.check(fleet.mission == FleetState.Mission.NONE, "sailing clears the station")
	# A hull leaves the squadron as a command of her own (wiki: ships-and-naval
	# § Ship instances; DR-20261116-12): the roster keeps both and both fly.
	fleet.add_hull("smoke_split", "sloop")
	var hulls_before: int = fleet.ship_count()
	var roster_before: int = screen.ship_layer.fleets.size()
	MapPlayFleets.on_action(screen.play, "split:smoke_split")
	run.check(
		screen.ship_layer.fleets.size() == roster_before + 1,
		"a hull detaches into a squadron of her own"
	)
	run.check(fleet.ship_count() == hulls_before - 1, "the squadron keeps her other hulls")
	var split_fleet: FleetState = null
	for other: FleetState in screen.ship_layer.fleets:
		if other != fleet and other.hulls.has("smoke_split"):
			split_fleet = other
	run.check(split_fleet != null, "the detached hull flies alone")
	run.check(
		split_fleet != null and split_fleet.sea_zone == fleet.sea_zone,
		"the new squadron keeps her station"
	)
	run.check(
		split_fleet != null and screen.ship_layer.ship_for(split_fleet) != null,
		"the new squadron flies a marker"
	)
	# Moor the home fleet back at the seat, so the later crew and turn steps read
	# the holds they expect (issue #1043).
	fleet.moved = false
	var moored: Dictionary = screen.ship_layer.order(
		fleet, FleetState.Location.IN_PORT, capital
	)
	run.check(bool(moored.get("ok", false)), "the home squadron moors again")
	run.check(fleet.is_in_port() and fleet.province == capital, "the home fleet keeps the seat")


## Army training is live: the recruit order musters a regiment into the Home
## Army and spends the ledger.
static func step_army_recruit(run) -> void:
	var screen: MapScreen = run.screen
	var home: ArmyState = SmokeFind.home_army(screen)
	if home == null:
		return
	var before: int = home.count()
	# The civilian drills earlier in the smoke spent the opening purse; top it
	# up so the muster row is payable, then prove the press only queues it.
	screen.economy.economy.add_treasury(RegimentCatalog.treasury_cost("peasant_levies"))
	var treasury: int = screen.economy.economy.treasury
	var fabric: int = screen.economy.economy.quantity("fabric")
	MapPlayArmyMuster.recruit(screen.play, "peasant_levies")
	run.check(
		screen.play.economy.economy.recruits.pending(
			RecruitQueue.KIND_REGIMENT, "peasant_levies"
		) == 1,
		"recruit queues a regiment for Build/work"
	)
	run.check(home.count() == before, "the regiment waits for the turn to close")
	run.check(screen.economy.economy.treasury == treasury, "the press spends no treasury")
	run.check(screen.economy.economy.quantity("fabric") == fabric, "the press spends no fabric")
	run.works["regiments"] = before


## Colonist path: the home squadron takes an idle civilian aboard and puts it
## ashore again (DR-20261109-17). The sortie itself stays in unit tests: sailing
## the home fleet would zero the trade holds the turn check needs.
static func step_colonists(run) -> void:
	var screen: MapScreen = run.screen
	var capital: int = screen.play.capital_province
	var home: FleetState = screen.ship_layer.home_fleet(capital)
	run.check(home != null, "home squadron waits at the capital")
	var colonist: CivilianState = SmokeFind.idle_civilian(screen, capital)
	run.check(colonist != null, "an idle colonist is available")
	if home == null or colonist == null:
		return
	screen.ship_layer.select(screen.ship_layer.ship_for(home))
	await run.tree.process_frame
	run.check(screen.hud.panels.is_fleet_panel_open(), "fleet dossier opens for the crew")
	var crew: Dictionary = MapPlayCivilianVoyage.crew(screen.play, home)
	run.check(not (crew["embark"] as Array).is_empty(), "the dossier offers the colonist")
	MapPlayCivilianVoyage.on_action(screen.play, "crew:embark:%d" % colonist.id)
	run.check(colonist.is_embarked(), "the colonist boards")
	run.check(colonist.tile.x < 0, "an embarked civilian leaves the map")
	MapPlayCivilianVoyage.on_action(screen.play, "crew:land:%d" % capital)
	run.check(not colonist.is_embarked(), "the colonist goes ashore")
	run.check(colonist.tile.x >= 0, "the colonist holds a shore tile")
	await run.tree.process_frame
