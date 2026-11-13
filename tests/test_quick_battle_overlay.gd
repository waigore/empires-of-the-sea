# gdlint: disable=max-public-methods
extends GdToolsTest
## Quick Battle plate contracts: it replays the report, skips on one tap and
## Also includes battle sim (one Godot boot).
## hands the queue back through its finished signal (REQ-P5-06).

const Fixture = preload("res://tests/map_fixture.gd")
const NAMES: Array[String] = ["España", "England"]


func test_the_plate_shows_a_battle_and_finishes_on_skip() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var done: Array[bool] = [false]
	overlay.finished.connect(func() -> void: done[0] = true)

	overlay.show_battle(_battle(), "Flanders", NAMES)
	await get_tree().process_frame
	overlay.field.queue_redraw()
	await get_tree().process_frame
	assert_true(overlay.is_shown())
	assert_eq(overlay.field.attacker_start, 6)
	assert_eq(overlay.field.defender_start, 4)

	overlay.skip()
	assert_true(overlay._finished)
	assert_true(overlay._continue.visible)
	assert_true(String(overlay._outcome.text).contains("takes Flanders"))

	overlay._on_continue()
	assert_true(done[0])
	assert_false(overlay.is_shown())
	overlay.free()


func test_the_plate_handles_a_battle_without_rounds() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle({"attacker": 0, "defender": 1, "outcome": 0}, "Flanders", NAMES)
	assert_true(overlay.is_shown())
	overlay.skip()
	assert_true(overlay._finished)
	overlay.free()


func test_the_hud_mounts_the_plate_and_queues_a_second_battle() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	screen.hud.show_quick_battle(_battle(), "Flanders")
	assert_true(screen.hud.is_quick_battle_shown())
	screen.hud.show_quick_battle(_battle(), "Burgundy")
	assert_eq(screen.hud._quick_queue.size(), 1, "a second battle waits its turn")
	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_true(screen.hud.is_quick_battle_shown(), "the queued battle takes the plate")
	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_false(screen.hud.is_quick_battle_shown())
	screen.free()


## The court's news waits for the plates: a despatch raised while a battle plays
## sits under the plate and expires unread, so the HUD holds it and raises it
## once the last plate closes (REQ-P5-06).
func test_the_courts_news_waits_for_the_battle_plates() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	var raised: int = screen.hud.despatches.box.get_child_count()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.toast("England occupies Burgundy unopposed")
	screen.hud.toast("England storms Flanders")

	assert_eq(screen.hud.despatches.box.get_child_count(), raised, "no despatch behind the plate")
	assert_eq(screen.hud.despatches.held().size(), 2, "the news waits its turn")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_eq(
		screen.hud.despatches.box.get_child_count(), raised + 2,
		"the court reads it after the battle"
	)
	assert_eq(screen.hud.despatches.held().size(), 0, "nothing is left waiting")
	screen.free()


## A second battle of the same turn keeps the news waiting until the last plate
## closes, so an earlier despatch never slips out between the fights.
func test_the_news_waits_for_every_plate_of_the_turn() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	var raised: int = screen.hud.despatches.box.get_child_count()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.show_quick_battle(_battle(), "Burgundy")
	screen.hud.toast("Spain takes Flanders")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_true(screen.hud.is_quick_battle_shown(), "the second battle takes the plate")
	assert_eq(screen.hud.despatches.box.get_child_count(), raised, "still hidden under a plate")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_eq(
		screen.hud.despatches.box.get_child_count(), raised + 1, "the news arrives at the end"
	)
	screen.free()


## A long turn cannot bury the court in plates: the queue keeps the newest
## despatches, which are the ones the turn's orders produced.
func test_the_news_queue_keeps_the_newest_despatches() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	screen.hud.show_quick_battle(_battle(), "Flanders")
	for index in HudDespatches.QUEUE_CAP + 2:
		screen.hud.toast("news %d" % index)

	assert_eq(screen.hud.despatches.held().size(), HudDespatches.QUEUE_CAP)
	assert_eq(String(screen.hud.despatches.held()[0]), "news 2", "the oldest lines go first")
	screen.free()


## A full queue spends the line the plate already told before the court's own
## news: the seat lost and the court's move must never be the price of a battle
## despatch the plate narrated (REQ-P5-06).
func test_the_plate_line_goes_before_the_courts_news() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.toast_plate_line("England takes Flanders")
	for index in HudDespatches.QUEUE_CAP - 1:
		screen.hud.toast("news %d" % index)
	# Full: the next line must not cost the court its own news.
	screen.hud.toast("Spain moves its court to Cuenca")

	var held: PackedStringArray = screen.hud.despatches.held()
	assert_eq(held.size(), HudDespatches.QUEUE_CAP)
	assert_false(held.has("England takes Flanders"), "the plate's own line goes first")
	assert_true(held.has("Spain moves its court to Cuenca"), "the court's news stays")
	screen.free()


## A despatch states what the action did to the other side; an assault's price
## is spelled out separately, and the battery reports the men it hit.
func test_a_despatch_reports_the_losses_it_inflicted() -> void:
	var battle: Dictionary = _battle()
	var assault := {
		"side": 1, "action": "assault", "label": "Assault",
		"attacker_lost": 3, "defender_lost": 1, "guns_destroyed": 0,
	}
	assert_eq(
		QuickBattleCopy.action_line(assault, battle, NAMES),
		"England — Assault · 3 lost · 1 of its own"
	)
	var battery := {
		"side": 1, "action": "battery", "label": "Emplaced battery",
		"attacker_lost": 2, "defender_lost": 0, "guns_destroyed": 0,
	}
	assert_eq(
		QuickBattleCopy.action_line(battery, battle, NAMES),
		"England — Emplaced battery · 2 lost"
	)
	var quiet := {
		"side": 0, "action": "entrench", "label": "Entrench",
		"attacker_lost": 0, "defender_lost": 0, "guns_destroyed": 1,
	}
	assert_eq(
		QuickBattleCopy.action_line(quiet, battle, NAMES),
		"España — Entrench · 1 gun silenced"
	)
	var turned := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 0, "guns_destroyed": 0, "turned": 2,
	}
	assert_eq(
		QuickBattleCopy.action_line(turned, battle, NAMES),
		"España — Volley fire · the wall turns it aside"
	)
	var behind := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 1, "guns_destroyed": 0, "behind_lost": 1,
	}
	assert_eq(
		QuickBattleCopy.action_line(behind, battle, NAMES),
		"España — Volley fire · 1 lost · 1 behind the wall"
	)
	## A blow the standing battery soaked says so, or the player reads a silent
	## action and cannot tell the guns are still answering.
	var soaked := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 0, "guns_destroyed": 0, "battery_hit": 1,
	}
	assert_eq(
		QuickBattleCopy.action_line(soaked, battle, NAMES),
		"España — Volley fire · the battery takes the blow"
	)


## The aftermath names the dead and the wall: both are written into the log the
## player reads after the plate finishes.
func test_the_aftermath_logs_the_losses_and_the_siege() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var battle: Dictionary = _battle()
	battle["fort_level"] = 1
	battle["defender_detail"] = {"pikemen": 2}
	battle["quick"]["lanes"] = {"wall": 2, "behind": 0}
	battle["quick"]["guns_start"] = 1
	battle["quick"]["fort_downgraded"] = true
	battle["quick"]["fort_after"] = 0

	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()

	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(text.contains("Losses — England: 2 Pikemen"), text)
	assert_true(text.contains("battery silenced"), text)
	overlay.free()


## The plate must lead with the plan the player set — on the defending side the
## report's `plan` belongs to the attacker, so reading it aloud confuses the
## player about the stance they chose.
func test_the_plate_leads_with_the_players_own_plan() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var battle: Dictionary = _battle()
	overlay.show_battle(battle, "Flanders", NAMES)
	assert_eq(overlay._plan_label.text, "Your plan: Aggressive · enemy: Defensive")
	battle["player_faction"] = 1
	(battle["quick"] as Dictionary)["guns_start"] = 1
	overlay.show_battle(battle, "Flanders", NAMES)
	assert_eq(
		overlay._plan_label.text,
		"Your plan: Defensive · enemy: Aggressive · 1 gun",
		"the defender reads their own stance, and one gun is not \"1 guns\""
	)
	overlay.free()


## The siege despatch tells the lanes, the wall's protection and the level a
## silenced battery leaves behind; a field battle says nothing extra.
func test_the_siege_despatch_names_the_lanes_and_the_breach() -> void:
	var battle: Dictionary = _battle()
	battle["fort_level"] = 2
	battle["quick"]["lanes"] = {"wall": 4, "behind": 2}
	battle["quick"]["sorties"] = 1
	battle["quick"]["fort_downgraded"] = true
	battle["quick"]["fort_after"] = 1

	var line: String = QuickBattleCopy.siege_line(battle)

	assert_true(line.contains("Stone fort"), line)
	assert_true(line.contains("45%"), "the wall's damage reduction is told")
	assert_true(line.contains("4 on the wall, 2 behind"), line)
	assert_true(line.contains("1 sortie"), line)
	assert_true(line.contains("falls to Wood"), line)
	assert_eq(QuickBattleCopy.siege_line(_battle()), "", "a field battle has no siege line")


## Gates and ground: the siege despatch names the three gates and a breach, and
## the aftermath says what the ground did to the action tables.
func test_gates_and_ground_are_told() -> void:
	var battle: Dictionary = _battle()
	battle["fort_level"] = 2
	battle["quick"]["gates"] = {"max": 3, "broken": 0, "damage": 5, "threshold": 7}
	assert_true(QuickBattleCopy.siege_line(battle).contains("3 gates hold"))
	(battle["quick"] as Dictionary)["gates"] = {
		"max": 3, "broken": 1, "damage": 7, "threshold": 7,
	}
	assert_true(QuickBattleCopy.siege_line(battle).contains("1 of 3 gates breached"))
	assert_eq(QuickBattleCopy.gates_text(_battle()["quick"]), "", "no fort, no gates")

	var ground: Dictionary = _battle()
	ground["quick"]["terrain"] = "town"
	assert_eq(
		QuickBattleCopy.terrain_line(ground),
		"Ground — Town streets: assaults −45%, volleys −30%"
	)
	assert_eq(QuickBattleCopy.terrain_line(_battle()), "", "open ground needs no line")

	var action := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 1, "guns_destroyed": 0,
		"gates_broken": 1,
	}
	assert_true(
		QuickBattleCopy.action_line(action, battle, NAMES).contains("1 gate breached")
	)


## Regiment detail in the aftermath: the named types each side lost.
func test_the_loss_line_names_the_regiments() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_detail"] = {"guards": 2}
	battle["defender_detail"] = {"pikemen": 3, "culverin": 1}

	assert_eq(
		QuickBattleCopy.loss_line(battle, NAMES),
		"Losses — España: 2 Guards · England: Culverin · 3 Pikemen"
	)
	assert_eq(QuickBattleCopy.loss_line(_battle(), NAMES), "", "a quiet field has no loss line")


## The line and the reserve: only a side that kept one is named, and the
## despatch counts both sides' reserves (wiki: combat § The line and the
## reserve; DR-20261111-15).
func test_the_line_and_the_reserve_are_told() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_deployed"] = 10
	battle["attacker_reserve"] = 4
	battle["defender_deployed"] = 4
	battle["defender_reserve"] = 0

	assert_eq(
		QuickBattleCopy.line_line(battle, NAMES),
		"Line — España: 10 of 14 in the line"
	)
	assert_eq(
		BattleReport.line_note(battle), " — 4 regiments held in reserve"
	)
	assert_eq(QuickBattleCopy.line_line(_battle(), NAMES), "", "a full line adds no line")
	assert_eq(BattleReport.line_note(_battle()), "", "a full line adds no tail")


func _battle() -> Dictionary:
	return {
		"attacker": 0,
		"defender": 1,
		"player_faction": 0,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"quick": {
			"plan": "aggressive",
			"defender_plan": "defensive",
			"attacker_start": 6,
			"defender_start": 4,
			"attacker_left": 4,
			"defender_left": 0,
			"guns_start": 0,
			"guns_left": 0,
			"attacker_cohesion": 2,
			"defender_cohesion": 0,
			"rounds": [
				{
					"round": 1,
					"attacker_count": 6,
					"defender_count": 2,
					"guns": 0,
					"actions": [{
						"side": 0,
						"action": "assault",
						"label": "Assault",
						"attacker_lost": 1,
						"defender_lost": 2,
						"guns_destroyed": 0,
					}],
				},
				{
					"round": 2,
					"attacker_count": 5,
					"defender_count": 0,
					"guns": 0,
					"actions": [],
				},
			],
		},
	}

## The nomadic read: every blow names the men it mauled as well as the
## regiment it broke (wiki: combat § Strength).
func test_a_despatch_reports_the_mauled() -> void:
	var action := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 1, "mauled": 4,
	}
	assert_eq(
		QuickBattleCopy.action_line(action, _battle(), NAMES),
		"España — Volley fire · 1 lost · 4 mauled"
	)


## The plate shows the condition it was told about: a mauled survivor and the
## chevrons won, both in the log and on the field's rail (REQ-P5-05).
func test_the_plate_reads_mauled_regiments_and_chevrons() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_health"] = [
		{"id": "unit_1", "type": "guards", "hp": 60, "max": 120, "medals": 1, "fraction": 0.5},
		{"id": "unit_2", "type": "guards", "hp": 120, "max": 120, "medals": 0, "fraction": 1.0},
	]
	battle["defender_health"] = []
	battle["attacker_chevrons"] = 2

	assert_eq(QuickBattleCopy.health_line(battle, NAMES), "Mauled — España: Guards 50%")
	assert_eq(
		QuickBattleCopy.chevron_line(battle, NAMES),
		"Chevrons — España: 2 regiments rise a chevron"
	)
	assert_eq(QuickBattleCopy.health_line(_battle(), NAMES), "")
	assert_eq(QuickBattleCopy.chevron_line(_battle(), NAMES), "")

	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()
	assert_eq(overlay.field.attacker_health.size(), 2, "the rail reads the aftermath")
	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(text.contains("Mauled — España: Guards 50%"), text)
	assert_true(text.contains("2 regiments rise a chevron"), text)
	overlay.free()


## The field's name added to the winner's colours: the aftermath line the plate
## prints, and none for a field every colour already bears (DR-20261112-02).
func test_the_plate_names_the_honours_won() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_honours"] = 3

	assert_eq(
		QuickBattleCopy.honour_line(battle, "Flanders", NAMES),
		"Honours — España: Flanders added to 3 colours"
	)
	assert_eq(QuickBattleCopy.honour_line(_battle(), "Flanders", NAMES), "")
	assert_eq(QuickBattleCopy.honour_line(battle, "", NAMES), "")

	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()
	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(text.contains("Honours — España: Flanders added to 3 colours"), text)
	overlay.free()


## The colours cited for a field won while mauled: the plate line names the
## weight a citation buys, and a clean win adds none (DR-20261112-10,
## DR-20261113-04).
func test_the_plate_names_the_cited_colours() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_citations"] = 2

	assert_eq(
		QuickBattleCopy.citation_line(battle, "Flanders", NAMES),
		"Citations — España: 2 colours cited at Flanders (+5% each)"
	)
	battle["attacker_citations"] = 1
	assert_eq(
		QuickBattleCopy.citation_line(battle, "Flanders", NAMES),
		"Citations — España: 1 colour cited at Flanders (+5% each)"
	)
	assert_eq(QuickBattleCopy.citation_line(_battle(), "Flanders", NAMES), "")

	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()
	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(
		text.contains("Citations — España: 1 colour cited at Flanders (+5% each)"), text
	)
	overlay.free()


## The field floats the damage an action recorded, over the side it struck.
func test_the_field_floats_the_damage_it_was_told() -> void:
	var battle: Dictionary = _battle()
	battle["quick"]["rounds"][0]["attacker_health"] = [
		{"id": "unit_1", "type": "guards", "hp": 40, "max": 120, "medals": 0, "fraction": 0.333},
	]
	battle["quick"]["rounds"][0]["actions"][0]["hits"] = [{
		"id": "unit_2", "type": "pikemen", "damage": 12, "hp": 80, "max": 110, "medals": 0,
	}]
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay._enter_round(0)

	assert_eq(overlay.field._floaters.size(), 1, "one number per hit")
	assert_eq(String(overlay.field._floaters[0]["text"]), "-12")
	assert_eq(overlay.field.attacker_health.size(), 1, "the rail reads the round")
	overlay.free()

# --- battle_sim ---
## The Battle Simulator's rules glue (`BattleScenario`) and its scene. The
## sandbox must run the live Quick Battle resolver, not a parallel model
## (REQ-P2-03); the screen must paint the record it gets back.

const SIM_SCENE: PackedScene = preload("res://scenes/battle_sim.tscn")


func test_the_scenario_builds_the_requested_battle() -> void:
	var spec: Dictionary = {
		"attacker": ["musketeers", "musketeers", "musketeers", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers", "culverin"],
		"fort": 2, "terrain": "woods", "seed": 3,
	}
	var result: Dictionary = BattleScenario.fight(spec)
	var report: Dictionary = result["report"]
	var quick: Dictionary = report["quick"]

	assert_eq(int(report["fort_level"]), 2)
	assert_eq(String(report["battle_mode"]), "siege")
	assert_eq(String(quick["terrain"]), "woods")
	assert_eq(String(quick["terrain_label"]), "Woods")
	assert_eq(int(quick["guns_start"]), 2, "a stone fort fields two emplaced guns")
	assert_eq(int(quick["lanes"]["wall"]), 3)
	assert_eq(int(quick["lanes"]["behind"]), 1)
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_eq(int(quick["attacker_start"]), 4)
	assert_eq(int(quick["defender_start"]), 4)


func test_the_scenario_runs_the_live_resolver() -> void:
	var spec: Dictionary = {
		"attacker": ["guards", "guards", "guards", "guards", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers"], "fort": 1, "terrain": "town",
		"attacker_plan": "aggressive", "defender_plan": "balanced", "seed": 11,
	}
	var first: Dictionary = BattleScenario.fight(spec)
	var scene: Dictionary = BattleScenario.build(spec)
	var direct: Dictionary = QuickBattle.resolve_exchange(
		scene["model"], scene["armies"], scene["province"], scene["defender"],
		scene["attacker"], false, scene["context"]
	)
	var sandbox: Dictionary = first["report"]

	assert_eq(int(sandbox["outcome"]), int(direct["outcome"]))
	assert_eq(
		(sandbox["defender_lost"] as Array).size(),
		(direct["defender_lost"] as Array).size()
	)
	assert_eq(
		(sandbox["attacker_lost"] as Array).size(),
		(direct["attacker_lost"] as Array).size()
	)
	assert_eq(String(sandbox["quick"]["defender_plan"]), "balanced")


func test_the_scenario_normalises_unknown_types() -> void:
	var scene: Dictionary = BattleScenario.build({
		"attacker": ["not_a_regiment"], "defender": ["pikemen"], "terrain": "open",
	})
	var armies: Array[ArmyState] = scene["armies"]
	assert_eq(armies[1].count(), 1)
	assert_eq(armies[1].type_of(armies[1].regiments[0]), RegimentCatalog.DEFAULT_TYPE)


func test_a_field_scenario_has_no_wall() -> void:
	var result: Dictionary = BattleScenario.fight({
		"attacker": ["musketeers", "musketeers"], "defender": ["pikemen", "pikemen"],
		"fort": 0, "terrain": "hill",
	})
	var quick: Dictionary = result["report"]["quick"]
	assert_eq(String(result["report"]["battle_mode"]), "field")
	assert_true((quick["gates"] as Dictionary).is_empty(), "no fort, no gates")
	assert_eq(String(quick["terrain"]), "hill")


## The published marsh id is the ground the sandbox paints (wiki: quick-battle
## § Terrain): a swamp province fights on marsh, and BattleScenario must map
## that id onto MapModel.Terrain.SWAMP — not leave the match arm dead.
func test_the_marsh_scenario_paints_swamp_ground() -> void:
	var scene: Dictionary = BattleScenario.build({
		"attacker": ["musketeers"], "defender": ["pikemen"], "terrain": "marsh",
	})
	var model: MapModel = scene["model"]
	assert_eq(model.terrain[model.index_of(2, 1)], MapModel.Terrain.SWAMP)
	assert_eq(String(scene["context"]["terrain_override"]), "marsh")


func test_every_ground_paints() -> void:
	var field := QuickBattleField.new()
	field.custom_minimum_size = Vector2(480, 320)
	field.size = Vector2(480, 320)
	add_child(field)
	for terrain: String in ["open", "hill", "woods", "town", "marsh"]:
		field.terrain = terrain
		field.fort_level = 3 if terrain == "town" else 0
		field.gates_broken = 2
		field.attacker_count = 4
		field.defender_count = 4
		field.attacker_health = []
		field.defender_health = []
		field.queue_redraw()
		await get_tree().process_frame
	assert_eq(field.terrain, "marsh")
	field.free()


## A painted plate is only as good as the asset behind it: a moved or renamed
## texture must fail here, not on a playtester's screen.
func test_the_painted_plate_assets_exist() -> void:
	for terrain: String in BattlePlate.PLATES.keys():
		var entry: Dictionary = BattlePlate.PLATES[terrain]
		assert_true(
			ResourceLoader.exists(String(entry["path"])),
			"missing plate for %s" % terrain
		)
	for fort in [1, 2, 3]:
		assert_true(
			ResourceLoader.exists(BattlePlate.WALLS[fort]), "missing wall %d" % fort
		)
	for path: String in [
		BattlePlate.SOLDIER, BattlePlate.CANNON, BattlePlate.HORSE, BattlePlate.RUBBLE,
	]:
		assert_true(ResourceLoader.exists(path), "missing %s" % path)


## --- per-type miniatures (issue #427) ---------------------------------------
## Every playable type stands as its own miniature: one sprite per catalog id,
## all painted by tools/art/regiment_miniatures.py on one scale. A type that
## falls back to the shared musketeer is a missing asset, so this fails here.


func test_every_regiment_type_has_its_own_miniature() -> void:
	var seen: Dictionary = {}
	for type_id: String in RegimentCatalog.ids():
		assert_true(RegimentMiniatures.has_art(type_id), "no miniature for %s" % type_id)
		var path: String = RegimentMiniatures.art_path(type_id)
		assert_false(seen.has(path), "%s shares another type's art" % type_id)
		seen[path] = type_id
		var tex: Texture2D = RegimentMiniatures.texture(type_id)
		assert_true(tex != null, "miniature did not load for %s" % type_id)
		var image: Image = tex.get_image()
		assert_true(image != null and image.get_height() > 0, "empty art for %s" % type_id)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(image.get_data())
		var digest: String = ctx.finish().hex_encode()
		assert_false(
			seen.has(digest), "%s is a copy of %s" % [type_id, String(seen.get(digest, ""))]
		)
		seen[digest] = type_id
	var unknown: Texture2D = RegimentMiniatures.texture("not_a_regiment")
	assert_true(unknown != null, "an unknown type still fields a miniature")
	assert_eq(RegimentMiniatures.art_path("not_a_regiment"),
		RegimentMiniatures.art_path(RegimentCatalog.DEFAULT_TYPE),
		"an unknown type normalises to the levy's art")


## Each miniature is painted on the foot figure's scale, so a gun is drawn low
## and a rider tall instead of every type filling the same box.
func test_the_miniatures_keep_their_natural_size() -> void:
	var foot: float = RegimentMiniatures.width("musketeers", 20.0)
	var horse: float = RegimentMiniatures.width("knights", 20.0)
	var gun: Texture2D = RegimentMiniatures.texture("culverin")
	assert_true(horse > foot, "a horseman stands wider than a file of musketeers")
	assert_true(
		float(gun.get_height()) < RegimentMiniatures.FIGURE_HEIGHT * 0.8,
		"a gun sprite is painted lower than a standing man"
	)
	assert_true(
		RegimentMiniatures.spacing(_slots(["culverin"]), 20.0)
			> RegimentMiniatures.spacing(_slots(["musketeers"]), 20.0),
		"a gun needs more room in the line"
	)


## The line stands in type blocks and the caption names them in the order they
## stand, so a player can point at a block and read its type.
func test_the_line_stands_in_type_blocks_and_names_them() -> void:
	var slots: Array[Dictionary] = _slots(["musketeers", "pikemen", "musketeers", ""])
	assert_eq(slots.size(), 4)
	var named: Array[String] = []
	for slot: Dictionary in slots:
		named.append(String(slot["type"]))
	assert_eq(
		"|".join(named), "|musketeers|musketeers|pikemen",
		"same types stand together, the unnamed slot first"
	)
	assert_eq(RegimentMiniatures.caption(slots), "2 Musketeers · Pikemen")
	assert_eq(RegimentMiniatures.caption(_slots([])), "", "no men, no caption")
	assert_eq(
		RegimentMiniatures.caption(_slots(["", ""])), "",
		"a record that names no type adds no caption"
	)


## A long composition is elided to the room it has, never drawn over the other
## side's caption (a phone plate is half a desktop one).
func test_the_caption_fits_the_room_it_has() -> void:
	var slots: Array[Dictionary] = _slots([
		"guards", "guards", "pikemen", "hussars", "culverin", "bowmen",
		"arquebusiers", "siege_guns",
	])
	var text: String = RegimentMiniatures.caption(slots)
	assert_true(text.ends_with("…"), text)
	var font: Font = UiTheme.serif()
	var narrow: String = RegimentMiniatures.fit(text, 60.0, font, 11)
	assert_true(narrow.ends_with("…"), narrow)
	assert_true(
		font.get_string_size(narrow, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= 60.0,
		"the cut caption still fits its room: %s" % narrow
	)
	assert_eq(
		RegimentMiniatures.fit("2 Pikemen", 400.0, font, 11), "2 Pikemen",
		"a caption with room to spare is untouched"
	)


## A cold cache loads the art once and keeps it; a caption with no room draws
## nothing rather than squeezing a word into a gap.
func test_the_miniature_table_loads_once_and_a_caption_needs_room() -> void:
	RegimentMiniatures._cache.clear()
	var first: Texture2D = RegimentMiniatures.texture("guards")
	var second: Texture2D = RegimentMiniatures.texture("guards")
	assert_true(first != null, "a cold cache still finds the miniature")
	assert_true(first == second, "the second read is the cached texture")
	var field := QuickBattleField.new()
	field.size = Vector2(200, 200)
	add_child(field)
	## No room, or nothing to say: the caption draws nothing (the field's own
	## frame covers the drawing path).
	RegimentMiniatures.draw_caption(field, "", Vector2.ZERO, 160.0, Palette.TEXT, 11)
	RegimentMiniatures.draw_caption(field, "2 Pikemen", Vector2.ZERO, 4.0, Palette.TEXT, 11)
	field.free()


## The plate itself: a battle record's types are painted and named on the field,
## both in the simulator and in the live plate (one shared view).
func test_the_field_paints_each_type_and_names_the_line() -> void:
	var field := QuickBattleField.new()
	field.custom_minimum_size = Vector2(520, 360)
	field.size = Vector2(520, 360)
	add_child(field)
	field.attacker_color = Palette.CRIMSON
	field.defender_color = Palette.NAVY
	field.attacker_count = 3
	field.defender_count = 2
	field.attacker_health = [
		{"id": "a", "type": "guards", "hp": 120, "max": 120, "medals": 0, "fraction": 1.0},
		{"id": "b", "type": "cuirassiers", "hp": 110, "max": 110, "medals": 1, "fraction": 1.0},
		{"id": "c", "type": "culverin", "hp": 80, "max": 80, "medals": 0, "fraction": 1.0},
	]
	field.defender_health = [
		{"id": "d", "type": "pikemen", "hp": 110, "max": 110, "medals": 0, "fraction": 0.6},
		{"id": "e", "type": "bowmen", "hp": 80, "max": 80, "medals": 0, "fraction": 1.0},
	]
	field.queue_redraw()
	await get_tree().process_frame

	var slots: Array[Dictionary] = RegimentMiniatures.slots(field.attacker_health, 3, 12)
	assert_eq(
		RegimentMiniatures.caption(slots), "Cuirassiers · Culverin · Guards",
		"the plate names what the attacker fielded"
	)
	assert_true(
		RegimentMiniatures.width("cuirassiers", 20.0) > RegimentMiniatures.width("guards", 20.0),
		"the rider is drawn on its own miniature, not the musketeer's"
	)
	var defender: Array[Dictionary] = RegimentMiniatures.slots(field.defender_health, 2, 12)
	assert_eq(RegimentMiniatures.caption(defender), "Bowmen · Pikemen")
	field.free()


func _slots(types: Array) -> Array[Dictionary]:
	var entries: Array = []
	for index in types.size():
		entries.append({"type": String(types[index]), "fraction": 1.0, "medals": 0})
	return RegimentMiniatures.slots(entries, entries.size(), 12)


## The wall must read as a fortification: taller than a man, with the garrison
## standing on the parapet above the field line.
func test_the_wall_towers_over_the_garrison() -> void:
	for fort in [1, 2, 3]:
		var wall: float = BattlePlate.wall_height(600.0, fort)
		assert_true(wall > BattlePlate.soldier_height(600.0) * 1.5, "wall too low")
		assert_true(BattlePlate.parapet_y(600.0, fort) < 600.0 * BattlePlate.GROUND)
	assert_true(
		BattlePlate.wall_height(600.0, 3) > BattlePlate.wall_height(600.0, 1),
		"a later fort stands taller"
	)


func test_the_simulator_scene_fights_and_steps() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame

	screen._fight()
	assert_false(screen._result.is_empty(), "Fight resolves the current setup")
	assert_true(screen._log.text.contains("ROUND"), "the despatch is printed")
	assert_true(screen._log.text.contains("OUTCOME"))
	assert_true(screen._field.fort_level >= 0)

	screen._step()
	assert_true(screen._status.text.contains("Round") or screen._status.text.contains("No rounds"))
	screen._reset()
	assert_true(screen._result.is_empty())
	assert_eq(screen._field.attacker_count, 0)

	screen.free()
