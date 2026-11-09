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