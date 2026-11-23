class_name PlatformHost
extends RefCounted
## The answers a host gives about the machine the game is running on: which
## features this build carries, how to read the launch command line, the OS
## label a report prints, whether a process is still working, the system
## clipboard and the name a key cap prints (REQ-P3-05).
##
## Gameplay, screens and tooling ask here; outside the display metrics in
## PlatformDisplay, this is the only file that names the engine's OS /
## DisplayServer surfaces, so one review reads every platform call the game
## makes.

const MOBILE_FEATURE: String = "mobile"
const ANDROID_FEATURE: String = "android"
const RELEASE_TEMPLATE_FEATURE: String = "template_release"
const HEADLESS_SERVER: String = "headless"
## No process: nothing started, so nothing to wait on.
const NO_PROCESS: int = -1


## True when this build was exported for a phone or tablet.
static func is_mobile() -> bool:
	return OS.has_feature(MOBILE_FEATURE)


## True when this build is an Android package.
static func is_android() -> bool:
	return OS.has_feature(ANDROID_FEATURE)


## True when this build shipped as a player export, not the editor or a dev run.
static func is_release_export() -> bool:
	return OS.has_feature(RELEASE_TEMPLATE_FEATURE)


## True when the host draws frames: headless CI has none.
static func has_display() -> bool:
	return DisplayServer.get_name() != HEADLESS_SERVER


## Human-readable OS line for a report: `Linux 24.04`.
static func system_label() -> String:
	return "%s %s" % [OS.get_name(), OS.get_version()]


## The arguments after `--` (the launcher's own switches).
static func launch_args() -> PackedStringArray:
	return OS.get_cmdline_user_args()


## Every engine argument, including ones an Android intent carried.
static func command_line() -> PackedStringArray:
	return OS.get_cmdline_args()


## The argument line as one printable string, for a warning line.
static func command_line_text() -> String:
	return str(OS.get_cmdline_args())


## The name a key cap prints, e.g. `W` or `Enter`.
static func key_label(key: InputEventKey) -> String:
	if key == null:
		return ""
	return OS.get_keycode_string(key.physical_keycode)


## The system clipboard now reads `text`. Never fails; the phone and the
## desktop alike just replace it.
static func set_clipboard(text: String) -> void:
	DisplayServer.clipboard_set(text)


## Starts a program with its arguments. Returns its process id, or NO_PROCESS
## when none started.
static func start_process(program: String, args: PackedStringArray) -> int:
	var pid: int = OS.create_process(program, args)
	if pid <= 0:
		return NO_PROCESS
	return pid


## True while the process `pid` is still running. NO_PROCESS never runs.
static func is_running(pid: int) -> bool:
	if pid <= 0:
		return false
	return OS.is_process_running(pid)
