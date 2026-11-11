extends GdToolsTest
## Quick Battle plate contracts: it replays the report, skips on one tap and
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
	var raised: int = screen.hud._toast_box.get_child_count()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.toast("England occupies Burgundy unopposed")
	screen.hud.toast("England storms Flanders")

	assert_eq(screen.hud._toast_box.get_child_count(), raised, "no despatch behind the plate")
	assert_eq(screen.hud._toast_queue.size(), 2, "the news waits its turn")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_eq(
		screen.hud._toast_box.get_child_count(), raised + 2,
		"the court reads it after the battle"
	)
	assert_eq(screen.hud._toast_queue.size(), 0, "nothing is left waiting")
	screen.free()


## A second battle of the same turn keeps the news waiting until the last plate
## closes, so an earlier despatch never slips out between the fights.
func test_the_news_waits_for_every_plate_of_the_turn() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	var raised: int = screen.hud._toast_box.get_child_count()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.show_quick_battle(_battle(), "Burgundy")
	screen.hud.toast("Spain takes Flanders")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_true(screen.hud.is_quick_battle_shown(), "the second battle takes the plate")
	assert_eq(screen.hud._toast_box.get_child_count(), raised, "still hidden under a plate")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_eq(
		screen.hud._toast_box.get_child_count(), raised + 1, "the news arrives at the end"
	)
	screen.free()


## A long turn cannot bury the court in plates: the queue keeps the newest
## despatches, which are the ones the turn's orders produced.
func test_the_news_queue_keeps_the_newest_despatches() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	screen.hud.show_quick_battle(_battle(), "Flanders")
	for index in GameHud.TOAST_QUEUE_CAP + 2:
		screen.hud.toast("news %d" % index)

	assert_eq(screen.hud._toast_queue.size(), GameHud.TOAST_QUEUE_CAP)
	assert_eq(String(screen.hud._toast_queue[0]), "news 2", "the oldest lines go first")
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
