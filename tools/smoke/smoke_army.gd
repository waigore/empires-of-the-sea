extends RefCounted
## Third step of the e2e smoke: the crown's own host at the capital — the army
## dossier, a detachment, the colours' new name, the field hospital train and
## the troop chip that counts both regions (DR-20261112-07, DR-20261113-05).
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeFind = preload("res://tools/smoke/smoke_find.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	var home_army: ArmyState = SmokeFind.home_army(screen)
	run.check(home_army != null, "Home Army musters at the capital")
	if home_army == null:
		return
	run.check(home_army.province == screen.capital_province, "Home Army stands at the capital")
	screen.army_layer.select(home_army)
	await run.tree.process_frame
	run.check(screen.hud.panels.is_army_panel_open(), "army dossier opens")
	var field_before: int = home_army.count()
	MapPlayArmies.on_action(screen.play, "detach:%s" % home_army.regiments[0])
	await run.tree.process_frame
	var field: ArmyState = screen.army_layer.selected_army
	run.check(field != null and not field.is_home_army(), "detached army becomes a field army")
	run.check(home_army.count() == field_before - 1, "Home Army keeps its remaining regiments")
	run.check(
		field != null and not RegimentNames.of(field, field.regiments[0]).is_empty(),
		"the detached regiment keeps its title"
	)
	if field != null:
		await _name_colours(run, screen, field)
		await _train(run, screen, field)
		await _dismiss(run, screen, field)
	# The dismissal retired the field army; the smoke leaves the court reading the
	# Home Army it opened on.
	screen.army_layer.select(home_army)
	await run.tree.process_frame
	run.check(
		screen.hud.stats.army_label.text
		== str(screen.army_layer.regiment_count_all(MapScreen.PLAYER_FACTION)),
		"troop chip counts every region"
	)


## The crown's own name (DR-20261113-05): the order writes the title the roster
## prints, and the colours keep the name they were given.
static func _name_colours(run, screen: MapScreen, field: ArmyState) -> void:
	var colours: String = field.regiments[0]
	MapPlayArmies.on_action(screen.play, "rename:%s:Guards of the Crown" % colours)
	await run.tree.process_frame
	run.check(
		RegimentNames.of(field, colours) == "Guards of the Crown",
		"the crown names its colours"
	)
	var named_row: HBoxContainer = (
		screen.hud.panels.army_panel._roster.get_child(0) as VBoxContainer
	).get_child(0) as HBoxContainer
	run.check(
		(named_row.get_child(1) as Label).text.begins_with("Guards of the Crown —"),
		"the roster prints the crown's own name"
	)


## The train (DR-20261112-07): the dossier names the offer or its refusal, and a
## pitched train reads on the strength line.
static func _train(run, screen: MapScreen, field: ArmyState) -> void:
	MapPlayArmies.show_panel(screen.play, field)
	await run.tree.process_frame
	run.check(
		screen.hud.panels.army_panel._hospital.visible,
		"the dossier offers the field hospital train"
	)
	run.check(
		not String(screen.hud.panels.army_panel._hospital.text).is_empty(),
		"the train order names itself"
	)
	HospitalTrain.apply(field)
	MapPlayArmies.show_panel(screen.play, field)
	await run.tree.process_frame
	run.check(
		String(screen.hud.panels.army_panel._strength.text).contains("field hospital"),
		"the strength line names the train"
	)
	run.check(
		not screen.hud.panels.army_panel._hospital.visible,
		"a served train order is gone"
	)


## The published dismissal (wiki: military-armies § Dismissing regiments;
## DR-20261116-07): the last colours of a field army leave, one peasant returns
## to the pool and the standard retires with them.
static func _dismiss(run, screen: MapScreen, field: ArmyState) -> void:
	var ledger: PlayerEconomy = screen.play.economy.economy
	var peasants: int = ledger.workers.count(WorkerPool.Tier.PEASANT)
	var colours: String = field.regiments[0]
	MapPlayArmies.on_action(screen.play, "dismiss:%s" % colours)
	await run.tree.process_frame
	run.check(field.count() == 0, "the last regiment is dismissed")
	run.check(
		ledger.workers.count(WorkerPool.Tier.PEASANT) == peasants + 1,
		"one peasant returns to the pool"
	)
	run.check(not screen.army_layer.armies.has(field), "an emptied field army retires")
	run.check(
		not screen.hud.panels.is_army_panel_open(),
		"the dossier closes with the standard"
	)
