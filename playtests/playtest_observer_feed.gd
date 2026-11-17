extends SceneTree
## Headless free-playtest drive for the full-AI observer's "Recent orders" feed
## (wiki: turn-trace-interpretation § Observer export; docs/ai-observer.md
## § Metrics). The observatory panel is the observer's only narration: every
## crown's resolved turn writes one merged record (`play.ai_turns`), and the
## panel's feed is the one place a watcher reads it without the JSONL export.
##
## This drive plays a real all-AI campaign forward and, after every turn, reads
## the feed exactly as the panel paints it, then compares it with the merged
## record the same turn wrote: how many rows exist, how many the feed prints,
## and which rows a busy turn loses. It also reads the plate's geometry, so a
## feed that grew past its frame (hiding the crowns under it) would show.
## Not a CI gate, run it by hand:
##   godot --headless --path . --script res://playtests/playtest_observer_feed.gd

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED: int = 1500
const TURNS: int = 24

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = SCENE.instantiate()
	_screen.map_seed = SEED
	_screen.map_width = int(GameConfig.SIZES[1]["width"])
	_screen.map_height = int(GameConfig.SIZES[1]["height"])
	_screen.observer_mode = true
	_screen.infinite_mode = true
	# A headless run skips the pure-view follow-up (docs/ai-observer.md
	# § Performance budget); the observer's own panel is mounted regardless.
	MapPlayTurn.view_live = false
	root.add_child(_screen)
	for _frame in 3:
		await process_frame
	_play = _screen.play
	if _play == null:
		print("playtest: the observer built no session — update playtests/playtest_observer_feed.gd")
		quit(1)
		return
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	if panel == null:
		print("playtest: the observatory panel is not mounted — update playtests/playtest_observer_feed.gd")
		quit(1)
		return
	_say("observer: seed %d, turn %d, human seat %d (empty)" % [
		_play.map_seed, _play.turn, _play.human_faction_id(),
	])
	_say("the feed before any turn: %s" % _feed_text(panel))
	var busiest: Dictionary = {}
	var lost_total: int = 0
	var turns_with_loss: int = 0
	for step in TURNS:
		MapPlayTurn.end_turn(_play)
		panel.refresh()
		var merged: Dictionary = _play.ai_turns[_play.ai_turns.size() - 1]
		var events: Array = merged.get("events", [])
		var feed: PackedStringArray = panel.board.feed.text.split("\n")
		var printed: Array[String] = _printed_rows(feed, int(merged["turn"]))
		var lost: int = events.size() - printed.size()
		lost_total += maxi(lost, 0)
		if lost > 0:
			turns_with_loss += 1
		_say("T%d  %2d rows resolved  ·  %2d printed  ·  %2d unread  ·  feed holds %d lines  ·  caption %s" % [
			int(merged["turn"]), events.size(), printed.size(), maxi(lost, 0),
			feed.size(), panel.board.feed_caption.text,
		])
		if busiest.is_empty() or events.size() > int(busiest["rows"]):
			busiest = {
				"turn": int(merged["turn"]), "rows": events.size(),
				"printed": printed.size(), "events": events.duplicate(true),
				"feed": Array(feed).duplicate(),
			}
	if _play.campaign_over():
		_say("the campaign decided on turn %d" % _play.turn)
	_say("")
	_say("%d rows resolved over %d turns; %d never reached the feed in %d turns" % [
		_rows_over_run(), TURNS, lost_total, turns_with_loss,
	])
	_read_busiest(busiest)
	await _read_layout(panel)
	await _read_phone()
	_finish()


# --- reads -------------------------------------------------------------------


## The feed's own text, exactly as the panel paints it.
func _feed_text(panel: AiObserverPanel) -> String:
	var text: String = panel.board.feed.text
	return "(empty)" if text.is_empty() else text.replace("\n", " ⏎ ")


## The rows a feed's lines print for one turn: `T<n>  <text>`, newest first.
func _printed_rows(feed: PackedStringArray, turn: int) -> Array[String]:
	var rows: Array[String] = []
	var prefix: String = "T%d  " % turn
	for line: String in feed:
		if line.begins_with(prefix):
			rows.append(line.substr(prefix.length()))
	return rows


func _rows_over_run() -> int:
	var total: int = 0
	for merged: Dictionary in _play.ai_turns:
		total += (merged.get("events", []) as Array).size()
	return total


## The busiest turn as the feed painted it the moment it was newest: what the
## feed kept and what it never showed, in the order the record wrote them
## (diplomacy, armies, fleets, economy, battles last).
func _read_busiest(busiest: Dictionary) -> void:
	if busiest.is_empty():
		_say("no turn resolved a row")
		return
	var turn: int = int(busiest["turn"])
	_say("")
	_say("--- the busiest turn: T%d, %d rows, %d printed ---" % [
		turn, int(busiest["rows"]), int(busiest["printed"]),
	])
	var printed: Array[String] = _printed_rows(
		PackedStringArray(busiest["feed"]), turn
	)
	var shown: Dictionary = {}
	for row: String in printed:
		shown[row] = int(shown.get(row, 0)) + 1
	var unread: int = 0
	for event: Dictionary in busiest["events"]:
		var text: String = String(event.get("text", ""))
		var name: String = FactionCatalog.name_of(int(event.get("faction", 0)))
		# Three crowns can accept the same pact in one turn, so a row is spent
		# by its first match and counted again for the next.
		if int(shown.get(text, 0)) > 0:
			shown[text] = int(shown[text]) - 1
			_say("  read    %s: %s" % [name, text])
		else:
			unread += 1
			_say("  UNREAD  %s: %s" % [name, text])
	_say("%d of %d rows of T%d never reached the feed" % [
		unread, int(busiest["rows"]), turn,
	])
	_say("the feed held %d lines the moment T%d was newest" % [
		(busiest["feed"] as Array).size(), turn,
	])


## Where the feed and the crowns sit once the feed carries a busy turn: a plate
## that grew past its frame would hide the rows it means to show.
func _read_layout(panel: AiObserverPanel) -> void:
	for _frame in 4:
		await process_frame
	var feed_scroll := panel.board.feed.get_parent() as ScrollContainer
	var frame: Control = panel.board.frame
	_say("")
	_say("--- the plate's own geometry ---")
	_say("panel frame: %s" % str(frame.size))
	_say("feed label: %s, minimum %s (%d lines)" % [
		str(panel.board.feed.size), str(panel.board.feed.get_minimum_size()),
		panel.board.feed.text.split("\n").size(),
	])
	if feed_scroll != null:
		var bar: VScrollBar = feed_scroll.get_v_scroll_bar()
		_say("feed scroll: %s  ·  content %s  ·  page %s  ·  scrollable %s" % [
			str(feed_scroll.size), str(bar.max_value), str(bar.page),
			str(bar.max_value > bar.page),
		])
	var crowns: Control = panel.board.crowns.get_parent() as Control
	_say("crowns scroll: %s" % (str(crowns.size) if crowns != null else "no"))
	var box := _crowns_box(panel)
	if box != null:
		_say("crown cards reach y %.0f of the frame's %.0f" % [
			box.global_position.y + box.size.y, frame.global_position.y + frame.size.y,
		])


## The same plate at a phone's landscape size. A headless window cannot be
## resized, so this mounts a second observer in a SubViewport of 720x360 (the
## handset profile) and reads the feed's window and the crowns' room there: a
## 128-pixel feed must not eat the cards on a short screen (REQ-P1-07).
func _read_phone() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = SEED
	screen.map_width = int(GameConfig.SIZES[1]["width"])
	screen.map_height = int(GameConfig.SIZES[1]["height"])
	screen.observer_mode = true
	screen.infinite_mode = true
	viewport.add_child(screen)
	for _frame in 6:
		await process_frame
	var play: PlaySession = screen.play
	if play == null:
		_say("the handset observer built no session")
		return
	for _turn in 3:
		MapPlayTurn.end_turn(play)
	var panel := screen.get_node_or_null("AiObserver") as AiObserverPanel
	if panel == null:
		_say("the handset observer mounted no panel")
		return
	panel.refresh()
	for _frame in 4:
		await process_frame
	var feed_scroll := panel.board.feed.get_parent() as ScrollContainer
	var frame: Control = panel.board.frame
	_say("")
	_say("--- the same plate on a 720x360 handset ---")
	_say("panel frame: %s  ·  caption %s" % [
		str(frame.size), panel.board.feed_caption.text,
	])
	_say("feed scroll: %s  ·  label %s  ·  lines %d" % [
		str(feed_scroll.size) if feed_scroll != null else "no",
		str(panel.board.feed.size), panel.board.feed.text.split("\n").size(),
	])
	var crowns: Control = panel.board.crowns.get_parent() as Control
	_say("crowns scroll: %s" % (str(crowns.size) if crowns != null else "no"))
	if crowns != null:
		_say("crown cards reach y %.0f of the frame's %.0f" % [
			crowns.global_position.y + crowns.size.y,
			frame.global_position.y + frame.size.y,
		])
	var bar: VScrollBar = panel.board.plate.get_v_scroll_bar()
	_say("plate: %s tall in the %s screen  ·  content %s  ·  scrollable %s" % [
		str(frame.size.y), str(panel.get_viewport().get_visible_rect().size),
		str(bar.max_value), str(bar.max_value > bar.page),
	])
	screen.queue_free()
	viewport.queue_free()


func _crowns_box(panel: AiObserverPanel) -> Control:
	var node: Node = panel.board.feed
	while node != null:
		if node is VBoxContainer and node != panel.board.crowns:
			return node as Control
		node = node.get_parent()
	return null


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_observer_feed: %d steps ---" % _steps.size())
	quit()