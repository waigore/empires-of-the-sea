extends RefCounted
## Shared plumbing for the hand-run persistence drives (docs/testing.md
## § Free playtest drives): the pause menu's save/load browser, the slot rows,
## a scratch directory, and one turn closed through the game's own consent
## ladder. No `class_name`: the drives preload this file, so a fresh clone, a
## manual run and the gd-tools cache all resolve it the same way.
##
## Every helper goes through the game's own paths — the browser's buttons, the
## router's screen swap, `MapPlayTurn` — so a drive never reaches past what a
## player can press.

const MAX_TURN_ATTEMPTS: int = 6


## Writes `slot` from the pause menu, confirming the overwrite guard when the
## slot already holds a campaign. Returns the browser's own status line.
static func save_slot(screen: MapScreen, slot: int) -> String:
	if screen == null:
		return "no screen"
	screen.game_menu.open()
	screen.game_menu.open_save()
	var button: Button = row(screen, slot)
	if button == null:
		screen.game_menu.close()
		return "the save browser has no row for slot %d" % slot
	button.emit_signal("pressed")
	# An occupied slot asks a second time before it is overwritten.
	if screen.game_menu.browser._pending_overwrite == slot:
		button = row(screen, slot)
		if button != null:
			button.emit_signal("pressed")
	var status: String = screen.game_menu._status.text
	screen.game_menu.close()
	return status


## Presses `slot` in the load browser and returns the screen the router built
## (null when the load was refused or the row is missing).
static func load_slot(screen: MapScreen, main: Node, slot: int) -> MapScreen:
	if screen == null or main == null:
		return null
	screen.game_menu.open()
	screen.game_menu.open_load()
	var button: Button = row(screen, slot)
	if button == null or button.disabled:
		screen.game_menu.close()
		return null
	button.emit_signal("pressed")
	var loaded: MapScreen = main.current_screen as MapScreen
	if loaded != null and not is_instance_valid(loaded):
		return null
	return loaded


static func row(screen: MapScreen, slot: int) -> Button:
	if screen == null or screen.game_menu == null:
		return null
	var browser: SaveBrowser = screen.game_menu.browser
	if browser == null or browser.slot_buttons.size() < slot:
		return null
	return browser.slot_buttons[slot - 1]


## Closes one turn, answering whatever consent decision a rival court raised
## (the player would answer the court plate). False when the turn stays shut.
static func advance(play: PlaySession) -> bool:
	for _attempt in MAX_TURN_ATTEMPTS:
		var before: int = play.turn
		MapPlayTurn.end_turn(play)
		if play.turn > before:
			return true
		if not answer_pending(play):
			return false
		if play.turn > before:
			return true
	return false


static func answer_pending(play: PlaySession) -> bool:
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapPlayTurn.answer_call(play, false)
		return true
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		return true
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapPlayTurn.answer_offer(play, false)
		return true
	return false


## Empties a scratch save directory so a hand run never touches the player's
## slots and a rerun starts from the same place.
static func clean_dir(dir: String) -> void:
	var path: String = ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(path):
		return
	var handle := DirAccess.open(dir)
	if handle != null:
		for file_name: String in handle.get_files():
			handle.remove(file_name)
	DirAccess.remove_absolute(path)


## Visible label/button text under `node`, optionally only lines that begin
## with `prefix` — the reads a player makes, not the rules state behind them.
static func collect_text(node: Node, prefix: String, into: PackedStringArray) -> void:
	if node == null:
		return
	if node is Label:
		var label: Label = node
		if label.visible and (prefix.is_empty() or label.text.begins_with(prefix)):
			into.append(label.text)
	elif node is Button:
		var button: Button = node
		if button.visible and (prefix.is_empty() or button.text.begins_with(prefix)):
			into.append(button.text)
	for child: Node in node.get_children():
		collect_text(child, prefix, into)
