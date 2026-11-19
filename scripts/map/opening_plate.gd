class_name OpeningPlate
extends ColorRect
## The opening parchment: opaque while the chart mounts, then lifted by
## MapPlaySetup.intro. It sits above the HUD, so a plate that outlives the
## opening hides the whole campaign — chart and chrome alike — leaving only the
## pause menu's MENU seal (one layer higher) on a blank parchment (issue #886).
##
## The lift therefore cannot be the only way out: the tween is pause-immune, and
## a deadline lifts the plate even if nothing ever calls `lift`. A fault earlier
## in the screen's `_ready` then costs the opening frame, not the campaign.

## How long the plate may cover the chart before the deadline lifts it. World
## generation on a handset can take a few seconds; past this the chart is shown
## whatever state the mount reached.
const HOLD_MAX_SECONDS: float = 8.0
const FADE_SECONDS: float = 0.9

## The deadline this plate arms for itself; tests set it before `_ready`.
var hold_max: float = HOLD_MAX_SECONDS
## Fade length when `lift()` is called without an override (deadline uses this
## too). Suites pin a short value so they never wait out a real opening fade.
var fade_seconds: float = FADE_SECONDS

var _lifted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var deadline := Timer.new()
	deadline.name = "Deadline"
	deadline.one_shot = true
	deadline.process_mode = Node.PROCESS_MODE_ALWAYS
	deadline.wait_time = maxf(hold_max, 0.01)
	deadline.timeout.connect(_on_deadline)
	add_child(deadline)
	deadline.start()


## Starts the parchment's fade. Idempotent: `intro` calls it, and the deadline
## may call it later; a second call changes nothing. Pass `seconds` to override
## `fade_seconds` for one lift (suites that call `lift` directly).
func lift(seconds: float = -1.0) -> void:
	if _lifted:
		return
	_lifted = true
	var fade: float = fade_seconds if seconds < 0.0 else seconds
	var tween: Tween = create_tween()
	# A paused tree is one of the ways the old plate was stranded: the pause
	# menu pauses everything, and the opening frame has to lift regardless.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, maxf(fade, 0.01)).set_trans(
		Tween.TRANS_SINE
	)
	tween.tween_callback(hide)


## A screen that never lifted the plate (a fault before `intro`, or a lift that
## never ticked) still owes the player the chart: the deadline names the fault in
## the log, so a device that strands the opening says why, and reveals the chart.
func _on_deadline() -> void:
	if _lifted:
		return
	push_warning(
		"OpeningPlate: the map screen never lifted the opening frame — lifting it on its deadline (issue #886)"
	)
	lift()