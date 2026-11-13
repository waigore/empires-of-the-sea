class_name AiObserverPanel
extends CanvasLayer
## Live full-AI observatory (debug tool): every Great Power's standing, ledger
## and last-turn orders, plus pause / step / speed controls. Reads
## MapPlayObserver snapshots and drives MapPlayTurn for the next turn; it never
## decides a rule outcome itself (REQ-P2-03, REQ-P5-02).

const SPEEDS: Array[float] = [1.4, 0.7, 0.3]
const SPEED_LABELS: Array[String] = ["1×", "2×", "4×"]
const MAX_LOG_LINES: int = 12

var play: PlaySession = null
var running: bool = true

var _ui: Control = null
var _frame: PanelContainer = null
var _tab: Button = null
var _turn_label: Label = null
var _status: Label = null
var _standing: Label = null
var _result: Label = null
var _crowns: VBoxContainer = null
var _log: Label = null
var _pause: Button = null
var _step: Button = null
var _speed: Button = null
var _cards: Dictionary = {}
var _speed_index: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	layer = 4
	_build()
	_fit()
	get_viewport().size_changed.connect(_fit)
	refresh()


func _process(delta: float) -> void:
	if play == null:
		return
	if not running or play.campaign_over():
		_sync_controls()
		return
	_elapsed += delta
	if _elapsed < SPEEDS[_speed_index]:
		return
	_elapsed = 0.0
	MapPlayTurn.end_turn(play)


# --- build -------------------------------------------------------------------


func _build() -> void:
	_ui = Control.new()
	_ui.name = "ObserverUI"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiTheme.build()
	add_child(_ui)

	_frame = MenuFrame.panel()
	_frame.anchor_bottom = 1.0
	_frame.offset_left = 12.0
	_frame.offset_top = 12.0
	_frame.offset_right = 420.0
	_frame.offset_bottom = -12.0
	_ui.add_child(_frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_frame.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title := MenuFrame.title("AI OBSERVATORY", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	_turn_label = MenuFrame.caption("")
	box.add_child(_turn_label)
	_status = MenuFrame.caption("")
	box.add_child(_status)
	_standing = MenuFrame.caption("")
	_standing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_standing)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	box.add_child(controls)
	_pause = MenuFrame.small_button("PAUSE", 86.0)
	_pause.pressed.connect(_toggle_running)
	controls.add_child(_pause)
	_step = MenuFrame.small_button("STEP", 66.0)
	_step.pressed.connect(_step_once)
	controls.add_child(_step)
	_speed = MenuFrame.small_button("1×", 52.0)
	_speed.pressed.connect(_cycle_speed)
	controls.add_child(_speed)
	var menu_button := MenuFrame.small_button("MENU", 72.0)
	menu_button.pressed.connect(_open_menu)
	controls.add_child(menu_button)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(filler)

	box.add_child(MenuFrame.separator())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_crowns = VBoxContainer.new()
	_crowns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crowns.add_theme_constant_override("separation", 4)
	scroll.add_child(_crowns)
	for faction: int in FactionCatalog.great_power_ids():
		_add_card(faction)

	box.add_child(MenuFrame.separator())
	box.add_child(MenuFrame.caption("Recent orders"))
	var log_scroll := ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.custom_minimum_size = Vector2(0.0, 96.0)
	box.add_child(log_scroll)
	_log = Label.new()
	_log.add_theme_font_size_override("font_size", 12)
	_log.add_theme_color_override("font_color", Palette.TEXT)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(_log)

	_result = MenuFrame.subtitle("")
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_result)

	var hide := MenuFrame.small_button("HIDE", 74.0)
	hide.pressed.connect(_toggle_panel)
	head.add_child(hide)
	_tab = MenuFrame.small_button("AI OBSERVER", 150.0)
	_tab.visible = false
	_tab.pressed.connect(_toggle_panel)
	_ui.add_child(_tab)
	_tab_view()


func _add_card(faction: int) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Palette.INK_SOFT, Palette.GOLD_DIM, 1, 3, Vector4(8, 4, 8, 4))
	)
	_crowns.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var rank := _label("#–", 11, Palette.GOLD_DIM)
	rank.custom_minimum_size = Vector2(30.0, 0.0)
	head.add_child(rank)
	var name_label := _label("", 16, Palette.GOLD_PALE, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var progress := _label("", 11, Palette.TEXT)
	head.add_child(progress)
	var meta := _label("", 10, Palette.TEXT_DIM, true)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(meta)
	var stats := _label("", 11, Palette.TEXT, true)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(stats)
	var last := _label("", 11, Palette.GOLD, true)
	last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(last)
	_cards[int(faction)] = {
		"rank": rank, "name": name_label, "progress": progress,
		"meta": meta, "stats": stats, "last": last,
	}


func _label(text: String, size: int, color: Color, serif: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if serif:
		label.add_theme_font_override("font", UiTheme.serif())
	return label


## Phone widths keep the panel readable; desktops give the map more room.
func _fit() -> void:
	if _frame == null:
		return
	var width: float = get_viewport().get_visible_rect().size.x
	var panel_width: float = clampf(width * 0.5, 280.0, 470.0)
	_frame.offset_right = minf(panel_width, maxf(width - 24.0, 220.0))


# --- refresh -----------------------------------------------------------------


func refresh() -> void:
	if play == null or _turn_label == null:
		return
	var snap: Dictionary = MapPlayObserver.snapshot(play)
	_turn_label.text = "TURN %d  ·  %d  ·  SEED %d" % [
		int(snap["turn"]), int(snap["year"]), int(snap["seed"]),
	]
	_standing.text = _standing_line(snap["rows"])
	_result.text = String(snap["result"])
	_result.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if snap["campaign_over"] else Palette.TEXT_DIM
	)
	for row: Dictionary in snap["rows"]:
		_refresh_card(row)
	_log.text = _recent_log()
	_sync_controls()


func _refresh_card(row: Dictionary) -> void:
	var card: Dictionary = _cards.get(int(row["faction"]), {})
	if card.is_empty():
		return
	var rank: Label = card["rank"]
	rank.text = "#%d" % int(row["rank"])
	var name_label: Label = card["name"]
	name_label.text = "%s%s" % [
		String(row["name"]), "" if bool(row["alive"]) else " (fallen)",
	]
	var progress: Label = card["progress"]
	progress.text = "%d/%d" % [
		int(row["provinces_old"]), VictoryRules.MILITARY_THRESHOLD,
	]
	var meta: Label = card["meta"]
	meta.text = "%s  ·  %s  ·  %s  ·  %s  ·  %s" % [
		String(row["leader"]), String(row["agenda"]), String(row["profile"]),
		String(row["posture"]), String(row["intent"]),
	]
	var wars: Array = row["wars"]
	var stats: Label = card["stats"]
	stats.text = (
		"%d OW · %d NW  ·  power %d  ·  army %d  ·  fleet %d  ·  civilians %d\n"
		+ "treasury %d  ·  stock %d  ·  workers %d  ·  wars: %s"
	) % [
		int(row["provinces_old"]), int(row["provinces_new"]), int(row["power"]),
		int(row["regiments"]), int(row["ships"]), int(row["civilians"]),
		int(row["treasury"]), int(row["stock"]), int(row["workers"]),
		", ".join(PackedStringArray(wars)) if not wars.is_empty() else "none",
	]
	var last: Label = card["last"]
	last.text = "Last turn: %s" % String(row["headline"])


## Two deliberate rows keep every crown's progress visible without an awkward
## mid-entry wrap at dashboard width.
func _standing_line(rows: Array) -> String:
	var parts: PackedStringArray = []
	for row: Dictionary in rows:
		parts.append("%d %s %d" % [
			int(row["rank"]), _short_name(String(row["name"])),
			int(row["provinces_old"]),
		])
	var lines: PackedStringArray = []
	for start in range(0, parts.size(), 3):
		lines.append("  ·  ".join(parts.slice(start, start + 3)))
	return "STANDING  " + "\n".join(lines)


## Keeps the standing line on one row at dashboard width.
func _short_name(name: String) -> String:
	return "U. Provinces" if name == "United Provinces" else name


## Two most recent resolved turns, newest order first.
func _recent_log() -> String:
	if play.ai_turns.is_empty():
		return "No orders recorded yet."
	var lines: PackedStringArray = []
	var first: int = maxi(play.ai_turns.size() - 2, 0)
	for index in range(play.ai_turns.size() - 1, first - 1, -1):
		var merged: Dictionary = play.ai_turns[index]
		var events: Array = merged.get("events", [])
		for cursor in range(events.size() - 1, -1, -1):
			var event: Dictionary = events[cursor]
			lines.append("T%d  %s" % [int(merged["turn"]), String(event["text"])])
			if lines.size() >= MAX_LOG_LINES:
				break
		if lines.size() >= MAX_LOG_LINES:
			break
	return "\n".join(lines) if not lines.is_empty() else "No orders recorded yet."


func _sync_controls() -> void:
	if play == null or _pause == null:
		return
	var over: bool = play.campaign_over()
	_pause.text = "RESUME" if not running else "PAUSE"
	_pause.disabled = over
	_step.disabled = over
	_speed.text = SPEED_LABELS[_speed_index]
	if over:
		_status.text = "DECIDED  ·  the calendar has stopped"
	elif running:
		_status.text = "RUNNING  ·  %s  ·  every crown under AI control" % (
			SPEED_LABELS[_speed_index]
		)
	else:
		_status.text = "PAUSED  ·  %s  ·  every crown under AI control" % (
			SPEED_LABELS[_speed_index]
		)


# --- controls ----------------------------------------------------------------


func _toggle_running() -> void:
	running = not running
	_elapsed = 0.0
	_sync_controls()


func _step_once() -> void:
	if play == null or play.campaign_over():
		return
	running = false
	MapPlayTurn.end_turn(play)
	refresh()


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	_elapsed = 0.0
	_sync_controls()


## Pauses the calendar while the shared pause menu is open; Resume restarts it.
func _open_menu() -> void:
	var host := get_parent() as MapScreen
	if host == null or host.game_menu == null:
		return
	running = false
	_sync_controls()
	host.game_menu.open()


func _toggle_panel() -> void:
	_frame.visible = not _frame.visible
	_tab_view()


## The collapsed tab keeps the observer one tap away, never hover-only.
func _tab_view() -> void:
	if _tab == null or _frame == null:
		return
	_tab.visible = not _frame.visible
	_tab.position = Vector2(12.0, 12.0)
	_tab.size = Vector2(150.0, 44.0)
