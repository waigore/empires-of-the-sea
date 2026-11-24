class_name PlaytestCapture
extends CanvasLayer
## Desktop-only playtest capture mode (issue #1393): toggle on/off, take
## screenshots, record video, type a comment on each capture, and composite the
## lot into a playtest report under `user://playtest_captures/`.
##
## The agent debug bridge stays a separate tool (docs/agent-debug.md): this one
## owns files and chrome only, never rules state (REQ-P3-03). Video is a frame
## sequence encoded by `ffmpeg` when it is on PATH; without it the frames stay
## as a usable artifact and the report says so.

const ROOT_DIR: String = "user://playtest_captures"
const FPS: int = 10
const SHOT_PREFIX: String = "shot-"
const FRAME_PREFIX: String = "frame-"
const VIDEO_NAME: String = "video.mp4"

var play: PlaySession = null
var enabled: bool = false
var recording: bool = false
var session_dir: String = ""
var entries: Array[Dictionary] = []
var overlay: PlaytestCaptureOverlay = null
## Overridable for tests so a suite never writes into the player's cache.
var root_dir: String = ROOT_DIR

var _meta: Dictionary = {}
var _shot_index: int = 0
var _video_index: int = 0
var _frame_index: int = 0
var _frame_accum: float = 0.0
var _frame_busy: bool = false
var _video_dir: String = ""
var _encode_pid: int = PlatformHost.NO_PROCESS
var _encode_entry: int = -1
var _pending_comment: int = -1


## Mobile is out of scope for v1: the mode never mounts there.
static func supported() -> bool:
	return PlaytestPlatform.is_desktop()


func _ready() -> void:
	if not supported():
		queue_free()
		return
	layer = 90
	overlay = PlaytestCaptureOverlay.new()
	overlay.name = "Overlay"
	add_child(overlay)
	overlay.toggle_pressed.connect(toggle_mode)
	overlay.screenshot_pressed.connect(capture_screenshot)
	overlay.record_pressed.connect(toggle_recording)
	overlay.comment_submitted.connect(submit_comment)
	overlay.comment_skipped.connect(skip_comment)
	set_process(true)


## The toggle hotkey always works; shot/record only while the mode is on and no
## comment sheet is taking the keyboard.
func _unhandled_input(event: InputEvent) -> void:
	if not supported():
		return
	if event.is_action_pressed(InputActions.PLAYTEST_TOGGLE):
		toggle_mode()
		get_viewport().set_input_as_handled()
		return
	if not enabled or (overlay != null and overlay.is_prompting()):
		return
	if event.is_action_pressed(InputActions.PLAYTEST_SHOT):
		capture_screenshot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.PLAYTEST_RECORD):
		toggle_recording()
		get_viewport().set_input_as_handled()


func toggle_mode() -> void:
	enabled = not enabled
	if enabled:
		_ensure_session()
	overlay.set_mode(enabled)
	overlay.set_status("Ready" if enabled else "")


## The session folder is lazy: a player who never captures writes nothing.
func _ensure_session() -> void:
	if not session_dir.is_empty():
		return
	_meta = PlaytestCaptureMeta.build(play)
	session_dir = root_dir.path_join(
		PlaytestCaptureMeta.session_dir_name(int(_meta["seed"]), str(_meta["timestamp"]))
	)
	DirAccess.make_dir_recursive_absolute(session_dir)
	write_report()


func capture_screenshot() -> void:
	if not enabled:
		return
	_ensure_session()
	var image: Image = await _grab()
	if image == null:
		overlay.set_status("Capture failed")
		return
	_shot_index += 1
	var file: String = "%s%04d.png" % [SHOT_PREFIX, _shot_index]
	if image.save_png(session_dir.path_join(file)) != OK:
		overlay.set_status("Save failed")
		return
	_add_entry("screenshot", file, PlaytestCaptureMeta.build(play))
	overlay.set_status("Shot %d saved" % _shot_index)


## Waits for the frame to finish drawing, so the shot is the frame the player
## saw rather than a half-painted one.
func _grab() -> Image:
	# Headless CI has no drawable frame: answer at once instead of waiting for
	# a `frame_post_draw` that never comes.
	if not PlatformHost.has_display():
		return null
	await RenderingServer.frame_post_draw
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image


func _add_entry(kind: String, file: String, meta: Dictionary) -> void:
	entries.append(PlaytestReport.entry(kind, file, "", meta))
	_pending_comment = entries.size() - 1
	write_report()
	overlay.prompt_comment(kind)


func submit_comment(text: String) -> void:
	if _pending_comment >= 0 and _pending_comment < entries.size():
		entries[_pending_comment]["comment"] = text.strip_edges()
	_pending_comment = -1
	overlay.close_prompt()
	write_report()


func skip_comment() -> void:
	_pending_comment = -1
	overlay.close_prompt()
	write_report()


func toggle_recording() -> void:
	if recording:
		stop_recording()
	else:
		start_recording()


func start_recording() -> void:
	if not enabled or recording:
		return
	_ensure_session()
	_video_index += 1
	_video_dir = session_dir.path_join("video-%04d" % _video_index)
	DirAccess.make_dir_recursive_absolute(_video_dir)
	_frame_index = 0
	_frame_accum = 0.0
	recording = true
	overlay.set_recording(true)
	overlay.set_status("Recording…")


func stop_recording() -> void:
	if not recording:
		return
	recording = false
	overlay.set_recording(false)
	if _frame_index == 0:
		overlay.set_status("Nothing recorded")
		return
	_add_entry("video", _video_dir.get_file(), PlaytestCaptureMeta.build(play))
	_start_encode()


## The ffmpeg command line, kept pure so a test can read it without spawning.
static func encode_args(pattern: String, out_path: String) -> PackedStringArray:
	return PackedStringArray([
		"-y", "-framerate", str(FPS), "-i", pattern,
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path,
	])


## Encoding runs off the main loop: the UI keeps drawing while ffmpeg works.
func _start_encode() -> void:
	var pattern: String = ProjectSettings.globalize_path(
		_video_dir.path_join(FRAME_PREFIX + "%04d.jpg")
	)
	var out_path: String = ProjectSettings.globalize_path(_video_dir.path_join(VIDEO_NAME))
	_encode_entry = entries.size() - 1
	_encode_pid = PlatformHost.start_process("ffmpeg", encode_args(pattern, out_path))
	if _encode_pid == PlatformHost.NO_PROCESS:
		_encode_entry = -1
		overlay.set_status("Video frames saved (no ffmpeg)")


func _process(delta: float) -> void:
	if recording and not _frame_busy:
		_frame_accum += delta
		if _frame_accum >= 1.0 / float(FPS):
			_frame_accum = 0.0
			_capture_frame()
	if _encode_pid > 0 and not PlatformHost.is_running(_encode_pid):
		_finish_encode()


func _capture_frame() -> void:
	_frame_busy = true
	var image: Image = await _grab()
	if image != null and recording:
		_frame_index += 1
		image.save_jpg(
			_video_dir.path_join("%s%04d.jpg" % [FRAME_PREFIX, _frame_index]), 0.8
		)
	_frame_busy = false


func _finish_encode() -> void:
	_encode_pid = PlatformHost.NO_PROCESS
	var out_path: String = _video_dir.path_join(VIDEO_NAME)
	if (
		FileAccess.file_exists(out_path)
		and _encode_entry >= 0
		and _encode_entry < entries.size()
	):
		entries[_encode_entry]["file"] = "%s/%s" % [_video_dir.get_file(), VIDEO_NAME]
		overlay.set_status("Video saved")
	else:
		overlay.set_status("Video frames saved")
	_encode_entry = -1
	write_report()


func write_report() -> bool:
	if session_dir.is_empty():
		return false
	return PlaytestReport.write(session_dir, PlaytestReport.compose(_meta, entries))


func report_path() -> String:
	return session_dir.path_join(PlaytestReport.REPORT_MD)


## Ready-to-file drafts for every capture; the agent reviews before filing.
func issue_drafts(label: String = "bug") -> Array[Dictionary]:
	var drafts: Array[Dictionary] = []
	for item: Dictionary in entries:
		drafts.append(PlaytestReport.issue_draft(item, _meta, label))
	return drafts
