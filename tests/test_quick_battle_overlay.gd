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