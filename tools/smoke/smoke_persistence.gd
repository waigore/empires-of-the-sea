extends RefCounted
## Last step of the e2e smoke: the pause menu's load rebuilds the whole screen
## from the slot the launch wrote, and the menu's return leaves no campaign
## behind (wiki: persistence; docs/testing.md § E2E smoke).
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeRun = preload("res://tools/smoke/smoke_run.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	var old_screen: MapScreen = screen
	screen.game_menu.open()
	screen.game_menu.open_load()
	screen.game_menu.browser.slot_chosen.emit(SmokeRun.SAVE_SLOT)
	var loaded: MapScreen = run.main.current_screen
	run.check(loaded != null and loaded != old_screen, "load rebuilds the whole screen")
	if loaded == null:
		return
	run.check(old_screen.get_parent() == null, "load clears the previous game")
	run.check(loaded.play.turn == 1, "load restores the saved turn")
	run.check(
		loaded.play.economy.economy.treasury == PlayerEconomy.START_TREASURY,
		"load restores the saved treasury"
	)
	run.check(loaded.save_dir == SmokeRun.SAVE_DIR, "load keeps the slot directory")
	run.check(not run.tree.paused, "load resumes the tree")
	run.screen = loaded
	loaded.game_menu.main_menu_chosen.emit()
	await run.tree.process_frame
	run.check(run.main.current_page is MainMenu, "main menu returns from play")
	run.check(run.main.current_screen == null, "no map survives the return")
	run.clean_save_dir()
