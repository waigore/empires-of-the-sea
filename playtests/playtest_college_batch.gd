extends SceneTree
## Headless playtest drive for the college's one press: every study under way
## takes a funding preset in a single act, and the line under the press prices
## the turn before the crown signs (wiki: tech-tree § Research Model;
## DR-20261118-26). Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_college_batch.gd
##
## Pass one plays a turn-0 crown honestly: two studies booked from the college's
## own Research buttons, the press stepped and pressed, and then a real turn
## closed so the phase — not the drive — spends what the line promised. Pass two
## seats a thin purse so the line must name the studies that wait, and reads
## what the phase then pays. Pass three stands the whole college down. Every
## figure read after that is the game's: the press's own face and line, the slot
## rows, the receipt on the bar, the turn toast, the despatch and the slots'
## progress after the turn. Pass four mounts the same sheet on a 720x360 handset
## and reads whether the press and its line are reachable there (REQ-P1-07).

const Launch = preload("res://playtests/playtest_launch.gd")
const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED_TEXT: String = "1500"
const SEED: int = 1500
const MAX_TURN_ATTEMPTS: int = 4

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _press_pass()
	await _purse_pass()
	await _stand_down_pass()
	await _phone_pass()
	_finish()


# --- pass one: the press a crown presses ------------------------------------


## Turn 0: two studies at different presets, the press files both, and one real
## turn is closed so the phase pays what the line promised.
func _press_pass() -> void:
	_say("")
	_say("=== the press a crown presses (turn 0) ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		return
	_play = _screen.play
	_say("seed %s — %s, turn %d, %d ducats, %d study slots" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.treasury(), _play.economy.economy.research.slots.size(),
	])
	await _open_college()
	var booked: int = await _book(2, "low")
	_say("booked %d studies from the college's own Research buttons" % booked)
	if booked < 2:
		return
	_read_college("before the press")
	_read_press("before the press")
	var press: ResearchFundPress = _press()
	# The stepper walks up to Medium: the crown wants the whole college there.
	press.step(1)
	_say("stepped the press to %s" % ResearchFunding.label(press.preset()))
	_read_press("at Medium")
	var promise: Dictionary = await _press_and_read("the press at Medium")
	if promise.is_empty():
		return
	await _close_turn("after the press")
	_read_spend("after the turn", promise)


# --- pass two: the purse cannot reach ---------------------------------------


## Turn 0 with a thin purse: three studies at High cost 1,200 a turn, the purse
## holds 1,000, so the line must name the study that waits and the phase must
## pay exactly the two it named.
func _purse_pass() -> void:
	_say("")
	_say("=== a purse that cannot reach (turn 0, 1,000 ducats) ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		return
	_play = _screen.play
	await _open_college()
	var booked: int = await _book(3, "low")
	_say("booked %d studies at Low" % booked)
	if booked < 3:
		return
	_play.economy.economy.treasury = 1000
	_play.economy.refresh_research_panel()
	await process_frame
	_say("seated the purse at %d ducats" % _play.treasury())
	var press: ResearchFundPress = _press()
	for _step in 3:
		press.step(1)
	_say("stepped the press to %s" % ResearchFunding.label(press.preset()))
	_read_college("with a thin purse")
	_read_press("with a thin purse")
	var promise: Dictionary = await _press_and_read("the press at High")
	if promise.is_empty():
		return
	await _close_turn("after the press")
	_read_spend("after the turn", promise)


# --- pass three: the whole college stands down ------------------------------


## The press at None is the crown's one way to stop paying for research it no
## longer wants. The receipt must say what it did, and the turn must spend
## nothing on study.
func _stand_down_pass() -> void:
	if _play == null:
		return
	_say("")
	_say("=== the whole college stands down ===")
	await _open_college()
	var press: ResearchFundPress = _press()
	if press == null or not press.visible:
		_say("no press stands on the sheet — nothing to stand down")
		return
	for _step in 4:
		press.step(-1)
	_say("stepped the press to %s" % ResearchFunding.label(press.preset()))
	_read_press("at None")
	var promise: Dictionary = await _press_and_read("the press at None", "n")
	if promise.is_empty():
		return
	await _close_turn("after standing down")
	_read_spend("after the turn", promise)


# --- pass four: the sheet on a handset --------------------------------------


## A handset sheet cannot carry the slots, the press and two lists at desktop
## sizes. The press must stay on the sheet, its line must stay readable, and the
## lists must keep room to be read: at 914x411 (the emulated phone) and at the
## 720x360 floor (REQ-P1-07, REQ-P5-07).
func _phone_pass() -> void:
	for size: Vector2i in [Vector2i(914, 411), Vector2i(720, 360)]:
		await _phone(size)


func _phone(size: Vector2i) -> void:
	_say("")
	_say("=== the college's press on a %dx%d handset ===" % [size.x, size.y])
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = SEED
	screen.map_width = int(GameConfig.SIZES[0]["width"])
	screen.map_height = int(GameConfig.SIZES[0]["height"])
	viewport.add_child(screen)
	for _frame in 8:
		await process_frame
	if screen.play == null:
		_say("the handset screen built no session")
		viewport.queue_free()
		return
	_play = screen.play
	_play.economy.open_research()
	for _frame in 8:
		await process_frame
	var panel: ResearchPanel = _play.hud.panels.research_panel
	var tabs: Control = _tabs_of(panel)
	var press: ResearchFundPress = _press()
	_say("with no study under way: press visible %s · lists %s" % [
		str(press.visible if press != null else false),
		(str(tabs.size) if tabs != null else "?"),
	])
	var booked: int = await _book(2, "low")
	_say("booked %d studies on the handset" % booked)
	for _frame in 4:
		await process_frame
	press = _press()
	if press == null:
		_say("the handset sheet mounted no press")
		viewport.queue_free()
		return
	var sheet: Control = panel
	var sheet_bottom: float = sheet.global_position.y + sheet.size.y
	var press_bottom: float = press.global_position.y + press.size.y
	var line_bottom: float = press.line().global_position.y + press.line().size.y
	_say("sheet %s at y %.0f (bottom %.0f) in a %s screen" % [
		str(sheet.size), sheet.global_position.y, sheet_bottom,
		str(viewport.size),
	])
	_say("press face \"%s\" — %s × %.0f, bottom %.0f" % [
		press.press_button().text, str(press.size.x), press.size.y, press_bottom,
	])
	_say("press line \"%s\" — × %.0f, bottom %.0f" % [
		press.line().text, press.line().size.y, line_bottom,
	])
	_say("the lists take %s under the press" % (str(tabs.size) if tabs != null else "?"))
	_say("the queue's window is %s of the %s its rows need (DR-20261119-02)" % [
		str(panel._slots_scroll.size),
		str(panel._slots_body.get_combined_minimum_size()),
	])
	_say("the press %s the sheet's edge; its line %s" % [
		"fits inside" if press_bottom <= sheet_bottom else "runs past",
		"fits inside" if line_bottom <= sheet_bottom else "runs past",
	])
	screen.queue_free()
	viewport.queue_free()


# --- the press --------------------------------------------------------------


func _press() -> ResearchFundPress:
	if _play == null or _play.hud == null:
		return null
	return _play.hud.panels.research_panel.fund_press()


## Presses the real button, reads the receipt the bar carries, then re-reads the
## sheet so the drive can see whether the press stood down. Returns the promise
## the press made: per-tech gold and RP per turn, keyed by tech id.
func _press_and_read(label: String, _unused: String = "") -> Dictionary:
	var press: ResearchFundPress = _press()
	if press == null:
		_say("no press stands on the sheet")
		return {}
	var plan: Dictionary = press.plan()
	if press.press_button().disabled:
		_say("the press is dead — it would file nothing (%s)" % label)
		press.press_button().pressed.emit()
		await process_frame
		_say("  a press of a dead face: %s" % _last_toast())
		return {}
	var face: String = press.press_button().text
	var line: String = press.line().text
	press.press_button().pressed.emit()
	for _frame in 3:
		await process_frame
	_say("pressed \"%s\"" % face)
	_say("  the line it signed: %s" % line)
	_say("  the receipt: %s" % _last_toast())
	var promise: Dictionary = {}
	for row: ResearchSlotRow in _slot_rows():
		var tech_id: String = _play.economy.economy.research.tech_at(row.slot)
		if tech_id.is_empty():
			continue
		promise[tech_id] = {
			"gold": row.gold_next(),
			"rp": row.rp_next(),
			"unpaid": row.unpaid_next(),
		}
	_read_press("after the press (%s)" % label)
	_read_college("after the press (%s)" % label)
	return promise


func _read_press(label: String) -> void:
	var press: ResearchFundPress = _press()
	if press == null:
		_say("press %s: no press" % label)
		return
	var plan: Dictionary = press.plan()
	_say("press %s: visible %s · face \"%s\" (%s) · line \"%s\"" % [
		label, str(press.visible), press.press_button().text,
		"dead" if press.press_button().disabled else "live", press.line().text,
	])
	_say("  plan: %d studies · %d filed · %d kept · %s ducats · %s RP · %d wait" % [
		int(plan["count"]), int(plan["filed"]), int(plan["kept"]),
		TextFormat.thousands(int(plan["gold"])), TextFormat.thousands(int(plan["rp"])),
		int(plan["unpaid"]),
	])


## What the phase really did: the slots' own progress against the promise, the
## despatch and the college's heading.
func _read_spend(label: String, promise: Dictionary) -> void:
	await _open_college()
	var state: ResearchState = _play.economy.economy.research
	var earned: int = 0
	var promised: int = 0
	for tech_id: String in promise:
		var want: Dictionary = promise[tech_id]
		var got: int = state.progress_of(tech_id)
		if state.is_unlocked(tech_id):
			_say("  %s landed this turn (promised %d RP)" % [
				TechCatalog.display_name(tech_id), int(want["rp"]),
			])
			continue
		_say("  %s: promised %d RP, holds %d (%s)" % [
			TechCatalog.display_name(tech_id), int(want["rp"]), got,
			"paid" if not bool(want["unpaid"]) else "unpaid",
		])
		if not bool(want["unpaid"]):
			earned += got
			promised += int(want["rp"])
	_say("slots holding progress %s: %d RP of the %d promised" % [label, earned, promised])
	_read_college(label)


func _read_college(label: String) -> void:
	var panel: ResearchPanel = _play.hud.panels.research_panel
	if panel == null:
		return
	var heading: String = ""
	var notice: String = ""
	for text: String in _labels(panel):
		if text.begins_with("RESEARCH SLOTS"):
			heading = text
		elif " unpaid — " in text:
			notice = text
	_say("college %s: %s" % [label, heading])
	if not notice.is_empty():
		_say("  notice: %s" % notice)
	for row: ResearchSlotRow in _slot_rows():
		var tech_id: String = _play.economy.economy.research.tech_at(row.slot)
		_say("  slot %d: %s · funding %s · %s ducats & %s RP · %s" % [
			row.slot, TechCatalog.display_name(tech_id),
			ResearchFunding.label(_play.economy.economy.research.funding_at(row.slot)),
			TextFormat.thousands(row.gold_next()), TextFormat.thousands(row.rp_next()),
			"unpaid" if row.unpaid_next() else "paid",
		])


# --- booking ----------------------------------------------------------------


func _open_college() -> void:
	_play.hud.research_pressed.emit()
	for _frame in 3:
		await process_frame


## Books `count` studies from the college's own Research buttons and sets each
## occupied slot to `funding` with its own funding button.
func _book(count: int, funding: String) -> int:
	var panel: ResearchPanel = _play.hud.panels.research_panel
	for _slot in count:
		var assign: Button = _find_open_study(panel)
		if assign == null:
			break
		assign.pressed.emit()
		await process_frame
	for row: ResearchSlotRow in _slot_rows():
		var button: Button = _funding_button(row)
		var guard: int = 0
		while button != null and button.text != ResearchFunding.label(funding) and guard < 6:
			button.pressed.emit()
			await process_frame
			button = _funding_button(row)
			guard += 1
	return _play.economy.economy.research.researching().size()


func _find_open_study(node: Node) -> Button:
	if node is Button:
		var button: Button = node
		if button.text == "Research" and not button.disabled and button.visible:
			return button
	for child: Node in node.get_children():
		var found: Button = _find_open_study(child)
		if found != null:
			return found
	return null


func _funding_button(row: ResearchSlotRow) -> Button:
	var stack: Array[Node] = [row]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button:
			var button: Button = node
			if button.text != "Cancel" and ResearchFunding.ORDER.has(_preset_of(button.text)):
				return button
		stack.append_array(node.get_children())
	return null


## The preset whose label a funding button wears, or "" for any other button.
func _preset_of(text: String) -> String:
	for preset: String in ResearchFunding.ORDER:
		if ResearchFunding.label(preset) == text:
			return preset
	return ""


func _slot_rows() -> Array[ResearchSlotRow]:
	var out: Array[ResearchSlotRow] = []
	if _play == null or _play.hud == null:
		return out
	for node: Node in _play.hud.panels.research_panel.find_children("*", "ResearchSlotRow", true, false):
		out.append(node as ResearchSlotRow)
	return out


func _tabs_of(panel: ResearchPanel) -> Control:
	for node: Node in panel.find_children("*", "TabContainer", true, false):
		return node as Control
	return null


func _labels(node: Node) -> PackedStringArray:
	var into: PackedStringArray = PackedStringArray()
	_collect(node, into)
	return into


func _collect(node: Node, into: PackedStringArray) -> void:
	if node is Label:
		var label: Label = node
		if label.visible and not label.text.strip_edges().is_empty():
			into.append(label.text)
	elif node is Button:
		var button: Button = node
		if button.visible and not button.text.strip_edges().is_empty():
			into.append(button.text)
	for child: Node in node.get_children():
		_collect(child, into)


# --- turns -----------------------------------------------------------------


func _close_turn(label: String) -> void:
	_play.hud.panels.hide_research()
	for _frame in 2:
		await process_frame
	if not _advance():
		_say("%s: the calendar never moved — the turn stayed shut" % label)
		return
	for _frame in 30:
		await process_frame
	_say("%s: turn %d, %d ducats" % [label, _play.turn, _play.treasury()])
	for text: String in _toasts():
		_say("  turn toast: %s" % text)


func _advance() -> bool:
	for _attempt in MAX_TURN_ATTEMPTS:
		var before: int = _play.turn
		MapPlayTurn.end_turn(_play)
		if _play.turn > before:
			return true
		if not _answer_pending():
			return false
		if _play.turn > before:
			return true
	return false


func _answer_pending() -> bool:
	if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
		_say("  court asks: call to arms — stood aside")
		MapPlayTurn.answer_call(_play, false)
		return true
	if Intervention.has_pending(_play.diplomacy, _play.player_faction):
		_say("  court asks: intervention — did nothing")
		MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		return true
	if DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
		_say("  court asks: a proposal — refused")
		MapPlayTurn.answer_offer(_play, false)
		return true
	return false


func _toasts() -> Array[String]:
	var out: Array[String] = []
	if _play == null or _play.hud == null or _play.hud._toast_box == null:
		return out
	var labels: PackedStringArray = _labels(_play.hud._toast_box)
	for text: String in labels:
		out.append(text)
	return out


func _last_toast() -> String:
	var labels: PackedStringArray = _labels(_play.hud._toast_box)
	if labels.is_empty():
		return "nothing on the bar"
	return labels[labels.size() - 1]


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_college_batch: %d steps ---" % _steps.size())
	quit()
