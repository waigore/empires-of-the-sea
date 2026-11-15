extends RefCounted
## Ninth step of the e2e smoke: the campaign's two endings on the live scene —
## a decided military victory, and the calendar cap that closes an undecided age
## on its last full turn (wiki: victory, turn-time-mapping § Campaign calendar
## cap). The smoke map is too small to win by province count, so the record is
## seeded.
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.


static func step(run) -> void:
	var screen: MapScreen = run.screen
	screen.play.victory = VictoryState.military(MapScreen.PLAYER_FACTION, screen.turn)
	screen.hud.show_victory(
		screen.play.victory,
		MapScreen.PLAYER_FACTION,
		VictoryRules.old_world_holdings(screen.world, MapScreen.PLAYER_FACTION)
	)
	await run.tree.process_frame
	run.check(screen.hud.is_victory_shown(), "campaign plate shows")
	run.check(screen.hud._end_turn_button.disabled, "end turn seal closes")
	var turn_before: int = screen.turn
	MapPlayTurn.end_turn(screen.play)
	run.check(screen.turn == turn_before, "decided campaign refuses another turn")
	screen.hud.victory_overlay.dismiss()
	run.check(not screen.hud.is_victory_shown(), "final view dismisses the plate")
	# Calendar cap: an undecided age closes on its last full turn, with the same
	# sealed plate (wiki: turn-time-mapping § Campaign calendar cap).
	screen.play.victory = null
	screen.play.infinite_mode = false
	screen.play.turn = TurnTime.cap_turn()
	MapPlayTurn.end_turn(screen.play)
	await run.tree.process_frame
	if DiplomacyProposals.has_pending(screen.play.diplomacy, MapScreen.PLAYER_FACTION):
		MapCourtOrders.apply(
			screen.play, DiplomacyProposals.KIND_ACCEPT, MapScreen.PLAYER_FACTION, ""
		)
		await run.tree.process_frame
	run.check(screen.play.campaign_halted, "calendar cap closes an undecided age")
	run.check(screen.turn == TurnTime.cap_turn(), "cap keeps the last full turn")
	run.check(screen.hud.is_victory_shown(), "campaign-complete plate shows")
	run.check(
		screen.hud.victory_overlay._title.text == "CAMPAIGN COMPLETE",
		"plate names the calendar end"
	)
	run.check(screen.hud._end_turn_button.disabled, "cap keeps the turn seal shut")
