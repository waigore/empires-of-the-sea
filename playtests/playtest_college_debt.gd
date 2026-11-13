extends SceneTree
## Headless playtest drive for the college when the purse runs out: what a crown
## is told when a study cannot be paid, and how far into debt it may go
## (wiki: tech-tree § Research Model; tech-tree-labour-economy § money_lending,
## banking). Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_college_debt.gd
##
## Pass one plays a turn-0 crown honestly: three studies booked at Maximum from
## the college's own buttons, then turns closed until a slot starves. Pass two
## needs a crown that may borrow, and walking 40,000 ducats down to the -500
## floor would cost fourteen turns of nothing, so the drive seats the purse at
## the floor's edge and lets the phase itself do the spending. Every figure read
## after that is the game's: the college's own rows, the ledger's promise, the
## chip and the turn toast.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const MAX_TURN_ATTEMPTS: int = 4
const MAX_WALK_TURNS: int = 10

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _no_borrowing_pass()
	await _floor_edge_pass()
	_finish()


# --- pass one: a crown that may not borrow ---------------------------------


## Turn 0, no Money Lending: the floor is 0, so a Maximum booking is a promise
## the purse cannot keep. The drive reads the college before the first turn and
## after each one, then stops on the first starved slot.
func _no_borrowing_pass() -> void:
	_say("")
	_say("=== a crown that may not borrow (turn 0, floor 0) ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		return
	_play = _screen.play
	_say("seed %s — %s, turn %d, %d ducats · money lending %s, banking %s" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.treasury(),
		str(bool(_play.tech_unlocked().get(ResearchFunding.MONEY_LENDING, false))),
		str(bool(_play.tech_unlocked().get(ResearchFunding.BANKING, false))),
	])
	_play.economy.open_research()
	await process_frame
	var booked: int = await _book_every_slot()
	_say("booked %d studies at Maximum" % booked)
	_read_college("before the first turn")
	_play.hud.panels.hide_research()
	for _turn in MAX_WALK_TURNS:
		if not _advance():
			_say("the calendar never moved — the turn stayed shut")
			return
		_say("")
		_say("--- turn %d closed ---" % _play.turn)
		_read_chip("after the turn")
		for text: String in _toasts():
			_say("turn toast: %s" % text)
		_play.economy.open_research()
		await process_frame
		_read_college("after the turn")
		_play.hud.panels.hide_research()
		_play.economy.open_panel()
		await process_frame
		_say("ledger preview: %s" % _ledger_preview())
		_play.hud.panels.hide_economy()
		if not _unpaid_lines(_play.hud.panels.research_panel).is_empty():
			_say("the college reports a slot the purse cannot pay — stopping the walk")
			return


# --- pass two: a crown that may borrow -------------------------------------


## Turn 100, Money Lending known: the floor is -500. The purse is seated one
## Low payment short of the floor, then a real turn is closed so the phase, not
## the drive, walks the last step down to it.
func _floor_edge_pass() -> void:
	_say("")
	_say("=== a crown that may borrow (turn 100, floor -500) ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		return
	_play = _screen.play
	var floor: int = ResearchFunding.floor_for(_play.tech_unlocked())
	_say("seed %s — %s, turn %d, %d ducats · money lending %s, banking %s · floor %d" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.treasury(),
		str(bool(_play.tech_unlocked().get(ResearchFunding.MONEY_LENDING, false))),
		str(bool(_play.tech_unlocked().get(ResearchFunding.BANKING, false))),
		floor,
	])
	_play.economy.open_research()
	await process_frame
	await _book_every_slot("low")
	_say("booked %d studies at Low (50 ducats each a turn)" % _play.economy.economy.research.researching().size())
	# Seat the purse at the floor's edge: research pays 50 a slot, so -500+50
	# leaves exactly one slot payable before the floor is reached.
	_play.economy.economy.treasury = floor + ResearchFunding.gold("low")
	_play.economy.refresh_panel()
	_play.hud.panels.show_research(
		_play.economy.economy.research, _play.treasury(), _play.economy.research_boost
	)
	await process_frame
	_say("seated the purse at %d (the floor's edge) — the phase spends from here" % _play.treasury())
	_read_college("at the floor's edge")
	_play.hud.panels.hide_research()
	if not _advance():
		_say("the calendar never moved — the turn stayed shut")
		return
	_say("")
	_say("--- turn %d closed at the floor ---" % _play.turn)
	for _frame in 40:
		await process_frame
	_say("treasury after the turn: %d (must never pass %d)" % [_play.treasury(), floor])
	_read_chip("at the floor")
	for text: String in _toasts():
		_say("turn toast: %s" % text)
	_play.economy.open_research()
	await process_frame
	_read_college("at the floor")
	_play.hud.panels.hide_research()
	_play.economy.open_panel()
	await process_frame
	_say("ledger preview: %s" % _ledger_preview())
	_say("ledger summary: %s" % _ledger_summary())
	_play.hud.panels.hide_economy()
	# A study the purse cannot pay must keep its slot and its points; the next
	# turn shows whether the stall costs progress or only time.
	if _advance():
		_say("")
		_say("--- a second turn at the floor (turn %d) ---" % _play.turn)
		_say("treasury now: %d" % _play.treasury())
		_play.economy.open_research()
		await process_frame
		_read_college("after a second turn at the floor")
		_play.hud.panels.hide_research()


# --- booking ---------------------------------------------------------------


## Books a study in every free slot from the college's own Research buttons and
## sets each occupied slot to `funding` with its own funding button. Returns how
## many slots end up at study.
func _book_every_slot(funding: String = "maximum") -> int:
	var panel: ResearchPanel = _play.hud.panels.research_panel
	for _slot in panel._state.slots.size():
		var assign: Button = _find_open_study(panel)
		if assign == null:
			break
		assign.emit_signal("pressed")
		await process_frame
	for row: Node in panel.find_children("*", "HBoxContainer", true, false):
		if not (row is ResearchSlotRow):
			continue
		var button: Button = _funding_button(row)
		var guard: int = 0
		while button != null and button.text != ResearchFunding.label(funding) and guard < 6:
			button.emit_signal("pressed")
			await process_frame
			button = _funding_button(row)
			guard += 1
	return panel._state.researching().size()


## The first Research button the college offers with a free slot.
func _find_open_study(node: Node) -> Button:
	if node is Button:
		var button: Button = node
		if button.text == "Research" and not button.disabled:
			return button
	for child: Node in node.get_children():
		var found: Button = _find_open_study(child)
		if found != null:
			return found
	return null


## A slot row's funding preset button: the one button that is not Cancel.
func _funding_button(row: Node) -> Button:
	var stack: Array[Node] = [row]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and (node as Button).text != "Cancel":
			return node as Button
		stack.append_array(node.get_children())
	return null


# --- reads -----------------------------------------------------------------


func _read_college(label: String) -> void:
	var panel: ResearchPanel = _play.hud.panels.research_panel
	_say("college %s: %s" % [label, _college_summary(panel)])
	var notice: String = _college_notice(panel)
	if not notice.is_empty():
		_say("  notice: %s" % notice)
	for line: String in _slot_lines(panel):
		_say("  slot: %s" % line)
	for line: String in _unpaid_lines(panel):
		_say("  unpaid: %s" % line)


## The college's own line for a study the treasury cannot pay: the rule, named
## under the summary wherever a slot starves.
func _college_notice(panel: ResearchPanel) -> String:
	var labels: PackedStringArray = PackedStringArray()
	_collect(panel, labels)
	for text: String in labels:
		if " unpaid — " in text:
			return text
	return ""


func _college_summary(panel: ResearchPanel) -> String:
	var labels: PackedStringArray = PackedStringArray()
	_collect(panel, labels)
	for text: String in labels:
		if " slot" in text:
			return text
	return labels[0] if not labels.is_empty() else "no line"


## One line per occupied slot: name, spend, progress, funding and the row's own
## next-turn line with the tooltip behind it.
func _slot_lines(panel: ResearchPanel) -> Array[String]:
	var out: Array[String] = []
	for row: Node in panel.find_children("*", "HBoxContainer", true, false):
		if not (row is ResearchSlotRow):
			continue
		var labels: PackedStringArray = PackedStringArray()
		_collect(row, labels)
		if labels.is_empty():
			continue
		var funding: Button = _funding_button(row)
		var next: Label = _next_label(row)
		out.append("%s — %s — %s — funding %s — next \"%s\" (%s)" % [
			labels[0],
			labels[1] if labels.size() > 1 else "?",
			labels[2] if labels.size() > 2 else "?",
			funding.text if funding != null else "?",
			next.text if next != null else "?",
			next.tooltip_text if next != null else "",
		])
	return out


func _unpaid_lines(panel: ResearchPanel) -> Array[String]:
	var out: Array[String] = []
	for row: Node in panel.find_children("*", "HBoxContainer", true, false):
		if not (row is ResearchSlotRow):
			continue
		var next: Label = _next_label(row)
		if next != null and "unpaid" in next.text:
			var labels: PackedStringArray = PackedStringArray()
			_collect(row, labels)
			out.append("%s (%s)" % [
				labels[0] if not labels.is_empty() else "?",
				next.tooltip_text,
			])
	return out


func _next_label(row: Node) -> Label:
	var labels: PackedStringArray = PackedStringArray()
	for child: Node in row.get_children():
		var stack: Array[Node] = [child]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is Label:
				var label: Label = node
				var text: String = label.text
				if label.visible and (
					text.begins_with("+") or text.begins_with("unpaid")
					or text.begins_with("earns")
				):
					return label
			stack.append_array(node.get_children())
	return null


func _chip_line() -> String:
	return "%s / %s — tooltip \"%s\"" % [
		_play.hud._treasury_label.text, _play.hud._income_label.text,
		_play.hud._treasury_chip.tooltip_text,
	]


func _read_chip(label: String) -> void:
	_say("chip %s: %s" % [label, _chip_line()])


func _ledger_preview() -> String:
	var labels: PackedStringArray = PackedStringArray()
	_collect(_play.hud.panels.economy_panel, labels)
	for text: String in labels:
		if text.begins_with("Next turn:"):
			return text
	return "no preview line"


func _ledger_summary() -> String:
	var labels: PackedStringArray = PackedStringArray()
	_collect(_play.hud.panels.economy_panel, labels)
	for text: String in labels:
		if " ducats" in text and " labour " in text:
			return text
	return "no summary line"


## Every despatch plate standing in the lane at this moment, oldest first, so a
## turn's news is read as the court reads it (the lane stacks plates).
func _toasts() -> Array[String]:
	var out: Array[String] = []
	if _play.hud._toast_box == null:
		return out
	var labels: PackedStringArray = PackedStringArray()
	_collect(_play.hud._toast_box, labels)
	for text: String in labels:
		out.append(text)
	return out


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


## Closes one turn, answering whatever consent decision a rival court raised.
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


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_college_debt: %d steps ---" % _steps.size())
	quit()
