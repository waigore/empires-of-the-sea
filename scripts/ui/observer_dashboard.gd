class_name ObserverDashboard
extends Control
## The AI observatory's plate, written once (REQ-P3-01, REQ-P1-07): the title
## line, the calendar's readings, the control row, one ObserverCrownCard per
## Great Power, the order feed and the result line. The panel hands over one
## snapshot and one veto per control; this paints them and owns the geometry, so
## no reader reaches through the plate into the observatory that mounted it.

## The controls the observatory wires to its calendar and pause menu.
signal pause_pressed
signal step_pressed
signal speed_pressed
signal menu_pressed

## Room the order feed keeps; the plate scrolls around it on a short screen.
const FEED_MIN_HEIGHT: float = 128.0
## Crowns whose catalogue name would wrap its third of the standing line read
## their short name instead (name, short name).
const SHORT_NAMES: Array[Array] = [["United Provinces", "U. Provinces"]]

## The plate scrolls as a whole when the screen is shorter than its stack: a
## landscape handset is 360 points tall and this dashboard is taller (REQ-P1-07).
var plate: ScrollContainer = null
var frame: PanelContainer = null
## Room the Great Powers' cards keep on a short screen.
var crowns_scroll: ScrollContainer = null
var crowns: VBoxContainer = null
var turn_label: Label = null
var status: Label = null
var standing: Label = null
var result: Label = null
var feed: Label = null
var feed_caption: Label = null
var pause_button: Button = null
var step_button: Button = null
var speed_button: Button = null
## The pause menu's own door; HIDE wears the head.
var menu_button: Button = null
var tab: Button = null
## One card per Great Power id, in the catalogue's order.
var crowns_by_id: Dictionary = {}
## The collapsed tab's place, set from the head button it replaces (never a
## fixed offset: the plate is inset by the safe margins).
var _tab_home: Vector2


func _init() -> void:
	name = "ObserverUI"
	_tab_home = Vector2(12.0, 12.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build()


func _ready() -> void:
	resized.connect(_tab_view)
	_tab_view()


# --- build -------------------------------------------------------------------


func _build() -> void:
	plate = ScrollContainer.new()
	plate.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(plate)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["margin_left", "margin_top", "margin_bottom"]:
		inset.add_theme_constant_override(side, 12)
	plate.add_child(inset)
	frame = MenuFrame.panel()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	frame.add_child(box)

	box.add_child(_build_head())
	_build_readings(box)
	box.add_child(_build_controls())
	box.add_child(MenuFrame.separator())
	_build_crowns(box)
	box.add_child(MenuFrame.separator())
	_build_feed(box)

	result = MenuFrame.subtitle("")
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(result)

	tab = MenuFrame.small_button("AI OBSERVER", 150.0)
	tab.visible = false
	tab.pressed.connect(_toggle_frame)
	add_child(tab)


func _build_head() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := MenuFrame.title("AI OBSERVATORY", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hide := MenuFrame.small_button("HIDE", 74.0)
	hide.pressed.connect(_toggle_frame)
	head.add_child(hide)
	_tab_home = hide.global_position
	return head


## The calendar's three readings: the turn line, the run's status, and the
## every-crown standing.
func _build_readings(box: VBoxContainer) -> void:
	turn_label = MenuFrame.caption("")
	box.add_child(turn_label)
	status = MenuFrame.caption("")
	box.add_child(status)
	standing = MenuFrame.caption("")
	standing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(standing)


func _build_controls() -> Control:
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	pause_button = MenuFrame.small_button("PAUSE", 86.0)
	pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	controls.add_child(pause_button)
	step_button = MenuFrame.small_button("STEP", 66.0)
	step_button.pressed.connect(func() -> void: step_pressed.emit())
	controls.add_child(step_button)
	speed_button = MenuFrame.small_button("1×", 52.0)
	speed_button.pressed.connect(func() -> void: speed_pressed.emit())
	controls.add_child(speed_button)
	menu_button = MenuFrame.small_button("MENU", 72.0)
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	controls.add_child(menu_button)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(filler)
	return controls


func _build_crowns(box: VBoxContainer) -> void:
	crowns_scroll = ScrollContainer.new()
	crowns_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	crowns_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	crowns_scroll.custom_minimum_size = Vector2(0.0, ObserverCrownCard.MIN_HEIGHT)
	box.add_child(crowns_scroll)
	crowns = VBoxContainer.new()
	crowns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crowns.add_theme_constant_override("separation", 4)
	crowns_scroll.add_child(crowns)
	for faction: int in FactionCatalog.great_power_ids():
		var card := ObserverCrownCard.new()
		crowns.add_child(card)
		crowns_by_id[faction] = card


func _build_feed(box: VBoxContainer) -> void:
	feed_caption = MenuFrame.caption("Recent orders")
	feed_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feed_caption)
	var log_scroll := ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.custom_minimum_size = Vector2(0.0, FEED_MIN_HEIGHT)
	box.add_child(log_scroll)
	feed = Label.new()
	feed.name = "Feed"
	feed.add_theme_font_size_override("font_size", 12)
	feed.add_theme_color_override("font_color", Palette.TEXT)
	feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(feed)


# --- paint -------------------------------------------------------------------


## One snapshot, one turn list: the line, the status, each crown's card and the
## feed all wake from the same reading, so they never disagree about the turn.
func paint(snap: Dictionary, ai_turns: Array) -> void:
	turn_label.text = "TURN %d  ·  %d  ·  SEED %d" % [
		int(snap["turn"]), int(snap["year"]), int(snap["seed"]),
	]
	standing.text = _standing_line(snap["rows"])
	result.text = String(snap["result"])
	result.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if snap["campaign_over"] else Palette.TEXT_DIM
	)
	for row: Dictionary in snap["rows"]:
		fill_crown(row)
	feed.text = ObserverTurnFeed.text(ai_turns)
	feed_caption.text = ObserverTurnFeed.caption(ai_turns)


## Paint one snapshot row onto its crown's card; a row for a court that holds no
## card is ignored.
func fill_crown(row: Dictionary) -> void:
	var card: ObserverCrownCard = crowns_by_id.get(int(row.get("faction", -1)))
	if card != null:
		card.fill(row)


## The one caption rule: a decided campaign seals the controls, a paused one
## names the pause, a running one names the speed. Every caption names the speed
## the calendar is set to, so a resumed run never reads a stale one.
func sync_controls(running: bool, over: bool, speed: String) -> void:
	pause_button.text = "RESUME" if not running else "PAUSE"
	pause_button.disabled = over
	step_button.disabled = over
	speed_button.text = speed
	if over:
		status.text = "DECIDED  ·  the calendar has stopped"
		return
	var word: String = "RUNNING" if running else "PAUSED"
	status.text = "%s  ·  %s  ·  every crown under AI control" % [word, speed]


# --- geometry ----------------------------------------------------------------


## Phone widths keep the panel readable; desktops give the map more room.
func fit(viewport_width: float) -> void:
	if frame == null:
		return
	var panel_width: float = clampf(viewport_width * 0.5, 280.0, 470.0)
	var width: float = minf(panel_width, maxf(viewport_width - 24.0, 220.0))
	frame.custom_minimum_size.x = width
	# The plate owns its own column, not the screen: the chart beside it must
	# stay clickable, because a tap there is how the observatory reads a
	# province (DR-20261117-11). A full-rect scroll container would swallow
	# every click before the map's own input saw it.
	if plate != null:
		plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		plate.size = Vector2(width + 12.0, get_viewport_rect().size.y)


## Two deliberate rows keep every crown's progress visible without an awkward
## mid-entry wrap at dashboard width. A crown whose name is too long for its
## third of the row reads its short name.
func _standing_line(rows: Array) -> String:
	var parts: PackedStringArray = []
	for row: Dictionary in rows:
		parts.append("%d %s %d" % [
			int(row["rank"]), short_name(String(row["name"])),
			int(row["provinces_old"]),
		])
	var lines: PackedStringArray = []
	for start in range(0, parts.size(), 3):
		lines.append("  ·  ".join(parts.slice(start, start + 3)))
	return "STANDING  " + "\n".join(lines)


## Keeps the standing line on one row at dashboard width.
func short_name(crown: String) -> String:
	for entry: Array in SHORT_NAMES:
		if crown == String(entry[0]):
			return String(entry[1])
	return crown


# --- collapse ----------------------------------------------------------------


func _toggle_frame() -> void:
	frame.visible = not frame.visible
	_tab_view()


## The collapsed tab keeps the observer one tap away, never hover-only.
func _tab_view() -> void:
	if tab == null or frame == null:
		return
	tab.visible = not frame.visible
	tab.position = _tab_home
	tab.size = Vector2(150.0, 44.0)
