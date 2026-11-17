class_name AiObserverPanel
extends CanvasLayer
## Live full-AI observatory (debug tool): every Great Power's standing, ledger
## and last-turn orders, plus pause / step / speed controls. Reads
## MapPlayObserver snapshots and drives MapPlayTurn for the next turn; it never
## decides a rule outcome itself (REQ-P2-03, REQ-P5-02).
##
## One module per concern (REQ-P3-01): the dashboard's plate, the crown cards and
## the order feed all live in `scripts/ui/observer_dashboard.gd`, the feed's text
## and caption in ObserverTurnFeed, one crown's card in ObserverCrownCard, and
## this class owns the calendar, the snapshot and the controls.

const SPEEDS: Array[float] = [1.4, 0.7, 0.3]
const SPEED_LABELS: Array[String] = ["1×", "2×", "4×"]
## Turns the feed keeps; ObserverTurnFeed prints them (REQ-P5-05).
const FEED_TURNS: int = ObserverTurnFeed.FEED_TURNS
const FEED_MIN_HEIGHT: float = ObserverDashboard.FEED_MIN_HEIGHT
## Room the cards keep on a short screen; the plate scrolls around them (REQ-P1-07).
const CARD_MIN_HEIGHT: float = ObserverCrownCard.MIN_HEIGHT

var play: PlaySession = null
var running: bool = true
## The plate, the crown cards and the feed the snapshot paints.
var board: ObserverDashboard = null
## The province reading a tap on the chart opens (ObserverProvinceSheet). It is
## a reading, never an order: the observatory has no seat to give them.
var sheet: ObserverProvinceSheet = null

var _speed_index: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	layer = 4
	board = ObserverDashboard.new()
	add_child(board)
	board.menu_pressed.connect(_open_menu)
	board.pause_pressed.connect(_toggle_running)
	board.step_pressed.connect(_step_once)
	board.speed_pressed.connect(_cycle_speed)
	sheet = ObserverProvinceSheet.new()
	add_child(sheet)
	_connect_chart()
	_fit()
	get_viewport().size_changed.connect(_fit)
	refresh()


func _process(delta: float) -> void:
	# Nothing to drive, or the calendar is held: the controls still mirror the
	# seat so Pause reads Resume the frame it is pressed.
	if play == null or not running or play.campaign_over():
		_sync_controls()
		return
	_elapsed += delta
	if _elapsed < SPEEDS[_speed_index]:
		return
	_elapsed = 0.0
	MapPlayTurn.end_turn(play)


## Phone widths keep the panel readable; desktops give the map more room.
func _fit() -> void:
	if board != null:
		board.fit(get_viewport().get_visible_rect().size.x)


func refresh() -> void:
	if play == null or board == null:
		return
	var snap: Dictionary = MapPlayObserver.snapshot(play)
	board.paint(snap, play.ai_turns)
	# A turn moves owners, works and hosts, so the open province is re-read with
	# the plate; a closed sheet costs nothing (REQ-P4-01).
	if sheet != null:
		sheet.refresh()
	_sync_controls()


## The chart's own selection signals: a tap on a province opens its reading, and
## a tap on open water or a cleared selection closes it. The observatory reads
## the chart the map already draws — it never asks for a second projection.
func _connect_chart() -> void:
	var host := get_parent() as MapScreen
	if host == null or sheet == null:
		return
	host.province_selected.connect(_on_province_selected)
	host.selection_cleared.connect(sheet.clear)


func _on_province_selected(province_id: int) -> void:
	if sheet == null or play == null:
		return
	sheet.show_province(play, province_id)


func _sync_controls() -> void:
	if play == null or board == null:
		return
	var over: bool = play.campaign_over()
	var speed: String = SPEED_LABELS[_speed_index]
	board.sync_controls(running, over, speed)


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
