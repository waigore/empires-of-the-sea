class_name AutoBar
extends Control
## The Auto mode's chrome (wiki: auto-mode; issue #725): the AUTO plaque over the
## chart that arms and disarms the AI seat, the seat's state beside it, the speed
## seal and the crown's own action log. It is also the driver: `_process` spends
## one pacing tick on `MapPlayAuto` while the seat is held.
##
## Presentation only. The seat, the passes and the rules outcomes belong to
## MapPlayAuto and the MapPlayTurn* modules; this class reads them back into
## chrome and asks the player to confirm the two seat changes (REQ-P3-01).
##
## The plaque is map chrome, not a cartouche door: the measured bar has no room
## for another seal without stacking its row (docs/hud-top-bar.md § Geometry), and
## the parent issue asks for a control that is always in reach (issue #725).

const TOUCH_HEIGHT: float = 44.0
const PLAQUE_WIDTH: float = 150.0
## The LOG seal beside the pace: wide enough for its caption and the count of
## lines the plate holds back.
const LOG_SEAL_WIDTH: float = 64.0
const LOG_SEAL_WIDTH_COUNTED: float = 88.0
## Height the plaque and pace take under the cartouche; the despatch lane starts
## below it while the seat's chrome shows, so no toast prints over the seat.
const CHROME_HEIGHT: float = 52.0

var play: PlaySession = null
## The always-present AUTO plaque: the seat's door and its state.
var toggle: AutoSeal = null

var _state_label: Label = null
var _speed_seal: AutoSeal = null
var _speed_label: Label = null
## The whole-log door: the plate prints the newest lines, this opens the rest.
var _log_seal: AutoSeal = null
var _log: AutoLogPlate = null
## Whether the plate held lines back on the last mirror, so the seal re-fits its
## width once per boundary instead of every frame.
var _was_counted: bool = false
## The seat change the player is being asked to confirm.
var _prompt: AutoPrompt = null
var _elapsed: float = 0.0
## What the chrome last printed, so a quiet frame costs no rebuild.
var _signature: String = ""
## Whether the seat's chrome was up on the last mirror, so its two boundaries
## re-lay the despatch lane exactly once each.
var _was_showing: bool = false
## The last run the plaque's face was set to (`null` until the first mirror), so
## a quiet frame repaints no stylebox.
var _was_live: Variant = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(relayout)
	_mirror()


## True while the seat's chrome is up: armed, held, or the log has news.
func is_showing() -> bool:
	return play != null and (play.auto_active or play.auto_armed)


## Binds the session and lays the plaque out under the cartouche.
func bind(p_session: PlaySession, hud: GameHud) -> void:
	play = p_session
	_log.bind(play, hud)
	relayout()
	_signature = ""
	_mirror()


## The HUD laid its chrome out again (a resize, a rotation, a shifted safe
## area): the plaque, the pace and the log follow it, so a phone rotation never
## strands the log off screen (GameHud lays its own chrome out the same way).
## AutoBar's `_ready` connects here, so Auto mode owns its chrome instead of the
## HUD naming a child (REQ-P3-01).
func relayout() -> void:
	_layout(get_parent() as GameHud)


func _process(delta: float) -> void:
	if play == null:
		return
	_drive(delta)
	_mirror()


# --- driver ------------------------------------------------------------------


## One pacing tick per `MapPlayAuto.seconds(play)`. Paused Auto, an open
## confirmation and a decided campaign all hold the clock (wiki: auto-mode
## § Pacing).
func _drive(delta: float) -> void:
	if _prompt != null and _prompt.is_open():
		return
	# The whole-log sheet holds the clock too: a log that grew under the reader
	# would move the lines they opened it to read (wiki: auto-mode § Pacing).
	if _log != null and _log.sheet_open():
		return
	if not MapPlayAuto.running(play):
		_elapsed = 0.0
		return
	var wait: float = MapPlayAuto.seconds(play)
	_elapsed += delta
	if _elapsed < wait:
		return
	_elapsed = 0.0
	MapPlayAuto.tick(play)


# --- build -------------------------------------------------------------------


func _build() -> void:
	toggle = AutoSeal.new(
		"AutoToggle", "auto", "AUTO",
		"Auto mode — hand the AI your seat for a while",
		Vector2(PLAQUE_WIDTH, TOUCH_HEIGHT), true
	)
	_state_label = toggle.set_detail()
	toggle.set_live(false)
	_was_live = false
	toggle.pressed.connect(_on_toggle_pressed)
	add_child(toggle)

	_speed_seal = AutoSeal.new(
		"AutoSpeed", "play", "1x", "Pace — pause, 1x, 2x, 3x",
		Vector2(TOUCH_HEIGHT, TOUCH_HEIGHT)
	)
	_speed_label = _speed_seal.caption()
	_speed_seal.pressed.connect(_on_speed_pressed)
	add_child(_speed_seal)

	_build_log_seal()
	_log = AutoLogPlate.new()
	_log.name = "AutoLogPlate"
	add_child(_log)
	_prompt = AutoPrompt.new()
	_prompt.name = "AutoPrompt"
	_prompt.confirmed.connect(_on_prompt_confirmed)
	_prompt.cancelled.connect(_on_prompt_cancelled)
	add_child(_prompt)


## The LOG seal: the plate's own door to the whole kept log, so a busy turn's
## first orders are read after the plate has moved on (REQ-P5-05).
func _build_log_seal() -> void:
	_log_seal = AutoSeal.new(
		"AutoLogSeal", "scroll", "LOG",
		"The crown's whole action log",
		Vector2(LOG_SEAL_WIDTH, TOUCH_HEIGHT)
	)
	_log_seal.pressed.connect(_on_log_pressed)
	add_child(_log_seal)


## Geometry follows the viewport: the plaque rides top-centre under the
## cartouche, the pace beside it and the log beneath, so the chart keeps its
## middle and the gesture stays one thumb away on a phone.
func _layout(hud: GameHud) -> void:
	var height: float = 60.0
	if hud != null and hud.top_bar != null:
		height = hud.top_bar.offset_bottom
	var width: float = maxf((hud.size if hud != null else size).x, 1.0)
	var plaque: float = minf(PLAQUE_WIDTH, width * 0.4)
	toggle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toggle.offset_left = -plaque * 0.5
	toggle.offset_right = plaque * 0.5
	toggle.offset_top = height + 8.0
	toggle.offset_bottom = height + 8.0 + TOUCH_HEIGHT
	_speed_seal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_speed_seal.offset_left = plaque * 0.5 + 6.0
	_speed_seal.offset_right = plaque * 0.5 + 6.0 + TOUCH_HEIGHT
	_speed_seal.offset_top = height + 8.0
	_speed_seal.offset_bottom = height + 8.0 + TOUCH_HEIGHT
	# The LOG seal follows the pace, so the seat's three controls read as one row
	# and the chart keeps its middle (REQ-P1-07).
	var seal_left: float = plaque * 0.5 + 6.0 + TOUCH_HEIGHT + 6.0
	var counted: bool = _log != null and _log.held_back() > 0
	var seal_width: float = LOG_SEAL_WIDTH_COUNTED if counted else LOG_SEAL_WIDTH
	_log_seal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_log_seal.offset_left = seal_left
	_log_seal.offset_right = seal_left + seal_width
	_log_seal.offset_top = height + 8.0
	_log_seal.offset_bottom = height + 8.0 + TOUCH_HEIGHT
	# The plate keeps the left rail under the cartouche on the atlas layout, and
	# the room above the minimap on a phone (AutoLogPlate owns that geometry).
	if _log != null:
		_log.layout(height)


# --- presses -----------------------------------------------------------------


func _on_toggle_pressed() -> void:
	if play == null or _prompt == null:
		return
	_prompt.ask(AutoPrompt.DISARM if play.auto_active else AutoPrompt.ARM)


func _on_prompt_confirmed(kind: String) -> void:
	if play != null:
		if kind == AutoPrompt.ARM:
			MapPlayAuto.arm(play)
		else:
			MapPlayAuto.disarm(play)
	_signature = ""
	_mirror()


func _on_prompt_cancelled() -> void:
	_mirror()


func _on_log_pressed() -> void:
	if _log != null:
		_log.open_sheet()


func _on_speed_pressed() -> void:
	if play == null:
		return
	MapPlayAuto.cycle_speed(play)
	_signature = ""
	_mirror()


# --- mirror ------------------------------------------------------------------


func _mirror() -> void:
	if play == null or toggle == null:
		return
	var signature: String = "%d|%d|%d|%d|%s" % [
		play.auto_speed,
		int(play.auto_active),
		int(play.auto_armed),
		play.auto_log.size(),
		String(play.auto_log.back()) if not play.auto_log.is_empty() else "",
	]
	if signature == _signature:
		return
	_signature = signature
	_speed_seal.visible = play.auto_active
	_log.mirror()
	_log_seal.visible = _log.is_showing()
	var held: int = _log.held_back()
	_log_seal.set_caption("LOG" if held <= 0 else "LOG +%d" % held)
	_log_seal.tooltip_text = _log_tooltip()
	if (held > 0) != _was_counted:
		_was_counted = held > 0
		relayout()
	toggle.set_state_text(_state_text())
	toggle.set_state_ink(Palette.GOLD_PALE if play.auto_active else Palette.TEXT_DIM)
	# Paused, the bars say it on their own; a live pace prints its rate beside
	# them, so the seal fits a phone's 44-point target either way.
	_speed_label.visible = play.auto_speed > 0
	_speed_label.text = MapPlayAuto.speed_label(play)
	_speed_seal.set_icon("play" if play.auto_speed > 0 else "pause")
	# The seat's face follows its run: the plaque warms while Auto holds the
	# turn, and one face serves every hover and press (AutoSeal owns the tones).
	if _was_live != play.auto_active:
		_was_live = play.auto_active
		toggle.set_live(play.auto_active)
	var hud := get_parent() as GameHud
	if _was_showing != is_showing():
		_was_showing = is_showing()
		# The despatch lane starts below the seat's chrome while it shows, so the
		# bar and the lane are laid out again on the seat's two boundaries.
		if hud != null:
			hud._relayout()
	# The seat also owns the end-turn seal's caption: AUTO while it holds the
	# turn, END TURN when it lets go. The campaign's own seal belongs to
	# HudCampaignEnd and an endless cap only plates, so `sealed` is the latch.
	if hud == null or hud.campaign_end == null:
		return
	hud.campaign_end.mirror_seat(play.auto_active, hud.campaign_over)


## The plaque's second line names the seat in one phrase.
func _state_text() -> String:
	if play.auto_active and not play.auto_armed:
		return "ends with this turn"
	if play.auto_active:
		return "the AI holds your seat"
	if play.auto_armed:
		return "arms after this turn"
	return "hand the seat to the AI"


## The seal's caption names what the plate holds back, so the door is offered
## exactly when there is something behind it (REQ-P5-05).
func _log_tooltip() -> String:
	var held: int = _log.held_back()
	if held <= 0:
		return "The crown's whole action log"
	return "The crown's whole action log — %d earlier lines the plate does not print" % held
