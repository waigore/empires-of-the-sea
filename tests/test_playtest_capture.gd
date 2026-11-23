extends GdToolsTest
## Playtest capture mode (issue #1393): the session metadata every artifact
## carries, the report composite (Markdown + JSON + issue drafts), the overlay's
## mode/comment chrome, and the controller's toggle/comment/report state.
##
## Capture IO itself (viewport grab, ffmpeg) is exercised by hand on desktop;
## these cases prove the pure shapes and the state machine, so a headless CI
## boot never needs a display or an encoder.

const DIR: String = "user://test_playtest_capture"


func before_all() -> void:
	InputActions.ensure_actions()


func before_each() -> void:
	_remove_dir(DIR)


func after_all() -> void:
	_remove_dir(DIR)


func _remove_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for sub: String in dir.get_directories():
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _play() -> PlaySession:
	var play: PlaySession = PlaySession.new()
	play.map_seed = 1500
	play.turn = 12
	play.player_faction = 0
	play.region_index = 0
	return play


# --- metadata ---------------------------------------------------------------


func test_meta_carries_session_parameters() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "2026-11-23T05:13:17")
	assert_eq(int(meta["seed"]), 1500, "the map seed rides every artifact")
	assert_eq(int(meta["turn"]), 12, "the turn rides every artifact")
	assert_eq(int(meta["year"]), TurnTime.year_for_turn(12), "the year is derived")
	assert_eq(str(meta["crown"]), "Spain", "the crown is named")
	assert_eq(int(meta["crown_id"]), 0, "the crown id is kept")
	assert_eq(str(meta["region"]), "Old World", "the region is named")
	assert_eq(str(meta["build"]), GameVersion.as_string(), "the build is named")
	assert_eq(str(meta["commit"]), "dev", "an unbaked build says dev")
	assert_true(str(meta["platform"]).contains(OS.get_name()), "the platform is named")
	assert_eq(str(meta["timestamp"]), "2026-11-23T05:13:17", "the stamp is kept")


func test_meta_handles_a_missing_session() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(null, "stamp")
	assert_eq(int(meta["seed"]), 0, "no session, no seed")
	assert_eq(str(meta["crown"]), PlaytestCaptureMeta.UNKNOWN, "no session, no crown")
	assert_eq(str(meta["region"]), PlaytestCaptureMeta.UNKNOWN, "no session, no region")
	assert_eq(str(meta["timestamp"]), "stamp", "the stamp still lands")


func test_meta_names_the_observer_seat() -> void:
	var play: PlaySession = _play()
	play.observer_mode = true
	assert_eq(PlaytestCaptureMeta.crown_name(play), "Observer", "the observer holds no crown")


func test_meta_region_out_of_range_is_unknown() -> void:
	assert_eq(PlaytestCaptureMeta.region_label(-1), PlaytestCaptureMeta.UNKNOWN)
	assert_eq(PlaytestCaptureMeta.region_label(99), PlaytestCaptureMeta.UNKNOWN)


func test_session_dir_name_is_filesystem_safe() -> void:
	var name: String = PlaytestCaptureMeta.session_dir_name(1500, "2026-11-23T05:13:17")
	assert_eq(name, "session-2026-11-23-051317-seed1500", "no colon or T in a folder name")
	assert_false(name.contains(":"), "a colon would break Windows")
	assert_false(name.contains("T"), "the ISO T is replaced")


# --- report -----------------------------------------------------------------


func _report() -> Dictionary:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "2026-11-23T05:13:17")
	var item: Dictionary = PlaytestReport.entry(
		"screenshot", "shot-0001.png", "The fleet is stuck on the reef.", meta
	)
	return PlaytestReport.compose(meta, [item])


func test_markdown_lists_the_capture_and_its_comment() -> void:
	var text: String = PlaytestReport.to_markdown(_report())
	assert_true(text.contains("# Playtest report"), "the page has a title")
	assert_true(text.contains("Seed: 1500"), "the header carries the seed")
	assert_true(text.contains("shot-0001.png"), "the capture is listed")
	assert_true(text.contains("The fleet is stuck on the reef."), "the comment is listed")
	assert_true(text.contains("Turn: 12"), "the capture carries its turn")


func test_markdown_says_when_nothing_is_captured() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "stamp")
	var text: String = PlaytestReport.to_markdown(PlaytestReport.compose(meta, []))
	assert_true(text.contains("_No captures yet._"), "an empty report says so")


func test_json_round_trips() -> void:
	var report: Dictionary = _report()
	var parsed: Variant = JSON.parse_string(PlaytestReport.to_json(report))
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the JSON is an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	assert_eq(int(parsed["meta"]["seed"]), 1500, "the seed survives the round trip")
	assert_eq(str(parsed["entries"][0]["comment"]), "The fleet is stuck on the reef.")


func test_write_creates_both_faces() -> void:
	assert_true(PlaytestReport.write(DIR, _report()), "the report writes")
	assert_true(FileAccess.file_exists(DIR.path_join(PlaytestReport.REPORT_MD)))
	assert_true(FileAccess.file_exists(DIR.path_join(PlaytestReport.REPORT_JSON)))
	var md: FileAccess = FileAccess.open(DIR.path_join(PlaytestReport.REPORT_MD), FileAccess.READ)
	assert_true(md.get_as_text().contains("shot-0001.png"), "the Markdown is on disk")
	md.close()


func test_write_refuses_an_empty_folder() -> void:
	assert_false(PlaytestReport.write("", _report()), "no folder, no report")


func test_issue_draft_uses_the_comment_and_session() -> void:
	var report: Dictionary = _report()
	var draft: Dictionary = PlaytestReport.issue_draft(
		report["entries"][0], report["meta"]
	)
	assert_eq(str(draft["title"]), "[Playtest] The fleet is stuck on the reef.")
	assert_eq(draft["labels"], ["todo", "bug"], "a defect draft is todo + bug")
	assert_true(str(draft["body"]).contains("Seed: 1500"), "the body carries the seed")
	assert_true(str(draft["body"]).contains("shot-0001.png"), "the body names the file")


func test_issue_draft_falls_back_to_the_kind() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "stamp")
	var item: Dictionary = PlaytestReport.entry("video", "video-0001", "", meta)
	var draft: Dictionary = PlaytestReport.issue_draft(item, meta, "enhancement")
	assert_eq(str(draft["title"]), "[Playtest] Video capture", "no comment, kind title")
	assert_eq(draft["labels"], ["todo", "enhancement"], "the caller picks the label")
	assert_true(str(draft["body"]).contains("_No comment typed._"), "the body says so")


# --- overlay ----------------------------------------------------------------


func test_overlay_toggles_mode_and_comment_sheet() -> void:
	var overlay: PlaytestCaptureOverlay = PlaytestCaptureOverlay.new()
	add_child(overlay)
	assert_false(overlay.is_mode_on(), "the mode starts off")
	assert_false(overlay.shot_button.visible, "the shot seal is hidden while off")
	overlay.set_mode(true)
	assert_true(overlay.is_mode_on(), "the mode turns on")
	assert_true(overlay.shot_button.visible, "the shot seal appears")
	assert_true(overlay.record_button.visible, "the record seal appears")
	overlay.prompt_comment("video")
	assert_true(overlay.is_prompting(), "a finished capture opens the sheet")
	assert_true(overlay.comment_edit.has_focus(), "the sheet takes the keyboard")
	overlay.close_prompt()
	assert_false(overlay.is_prompting(), "the sheet closes")
	overlay.set_mode(false)
	assert_false(overlay.shot_button.visible, "turning off hides the seals")
	overlay.free()


func test_overlay_emits_its_buttons() -> void:
	var overlay: PlaytestCaptureOverlay = PlaytestCaptureOverlay.new()
	add_child(overlay)
	var seen: Array[String] = []
	overlay.toggle_pressed.connect(func() -> void: seen.append("toggle"))
	overlay.screenshot_pressed.connect(func() -> void: seen.append("shot"))
	overlay.record_pressed.connect(func() -> void: seen.append("record"))
	overlay.comment_submitted.connect(func(text: String) -> void: seen.append("save:" + text))
	overlay.comment_skipped.connect(func() -> void: seen.append("skip"))
	overlay.toggle_button.pressed.emit()
	overlay.shot_button.pressed.emit()
	overlay.record_button.pressed.emit()
	overlay.set_mode(true)
	overlay.prompt_comment("screenshot")
	overlay.comment_edit.text = "A comment"
	overlay.save_button.pressed.emit()
	assert_eq(seen, ["toggle", "shot", "record", "save:A comment"], "every seal answers")
	overlay.prompt_comment("screenshot")
	overlay.skip_button.pressed.emit()
	assert_eq(seen[-1], "skip", "skip answers too")
	overlay.set_recording(true)
	assert_eq(overlay.record_button.text, "Stop", "recording flips the seal")
	overlay.set_status("Ready")
	assert_eq(overlay.status_text(), "Ready", "the status line reads back")
	overlay.free()


# --- controller -------------------------------------------------------------


func _capture() -> PlaytestCapture:
	var capture: PlaytestCapture = PlaytestCapture.new()
	capture.name = "PlaytestCaptureProbe"
	capture.play = _play()
	capture.root_dir = DIR
	add_child(capture)
	return capture


func test_capture_is_supported_on_desktop() -> void:
	assert_true(PlaytestCapture.supported(), "the CI host is a desktop")


func test_toggle_creates_the_session_and_report() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	assert_true(capture.enabled, "the mode turns on")
	assert_true(capture.session_dir.begins_with(DIR), "the session lands under the root")
	assert_true(FileAccess.file_exists(capture.report_path()), "the report exists at once")
	assert_eq(capture.overlay.status_text(), "Ready", "the overlay says ready")
	capture.toggle_mode()
	assert_false(capture.enabled, "the mode turns off")
	capture.free()


func test_shot_and_record_hotkeys_wait_for_the_mode() -> void:
	var capture: PlaytestCapture = _capture()
	capture._unhandled_input(_action(InputActions.PLAYTEST_SHOT))
	assert_eq(capture.session_dir, "", "a shot while off writes nothing")
	capture._unhandled_input(_action(InputActions.PLAYTEST_TOGGLE))
	assert_true(capture.enabled, "the toggle always answers")
	capture._unhandled_input(_action(InputActions.PLAYTEST_RECORD))
	assert_true(capture.recording, "record starts while on")
	capture._unhandled_input(_action(InputActions.PLAYTEST_RECORD))
	assert_false(capture.recording, "record stops while on")
	capture.free()


func test_comment_attaches_to_the_last_capture() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("screenshot", "shot-0001.png", "", capture._meta)
	)
	capture._pending_comment = 0
	capture.submit_comment("  The reef hides the fleet.  ")
	assert_eq(
		str(capture.entries[0]["comment"]), "The reef hides the fleet.",
		"the comment is trimmed and attached"
	)
	assert_false(capture.overlay.is_prompting(), "saving closes the sheet")
	capture.free()


func test_skip_leaves_the_comment_empty() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("screenshot", "shot-0001.png", "", capture._meta)
	)
	capture._pending_comment = 0
	capture.skip_comment()
	assert_eq(str(capture.entries[0]["comment"]), "", "skip keeps it empty")
	capture.free()


func test_issue_drafts_cover_every_capture() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("screenshot", "shot-0001.png", "One", capture._meta)
	)
	capture.entries.append(
		PlaytestReport.entry("video", "video-0001", "Two", capture._meta)
	)
	var drafts: Array[Dictionary] = capture.issue_drafts("enhancement")
	assert_eq(drafts.size(), 2, "one draft per capture")
	assert_eq(str(drafts[1]["title"]), "[Playtest] Two", "the second draft is the video")
	assert_eq(drafts[0]["labels"], ["todo", "enhancement"], "the label is passed through")
	capture.free()


func test_encode_args_name_the_frame_pattern_and_output() -> void:
	var args: PackedStringArray = PlaytestCapture.encode_args("/tmp/frame-%04d.jpg", "/tmp/v.mp4")
	assert_eq(args[0], "-y", "overwrite the old file")
	assert_eq(args[2], str(PlaytestCapture.FPS), "the capture rate is named")
	assert_eq(args[4], "/tmp/frame-%04d.jpg", "the frame pattern is named")
	assert_eq(args[-1], "/tmp/v.mp4", "the output is named")


func test_finish_encode_keeps_the_frames_when_no_video_landed() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("video", "video-0001", "", capture._meta)
	)
	capture._video_dir = DIR.path_join("video-0001")
	capture._encode_entry = 0
	capture._finish_encode()
	assert_eq(capture.overlay.status_text(), "Video frames saved", "the frames stay usable")
	assert_eq(str(capture.entries[0]["file"]), "video-0001", "the entry keeps the folder")
	capture.free()


func test_a_headless_grab_never_crashes_the_mode() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	await capture.capture_screenshot()
	assert_true(
		capture.overlay.status_text() in ["Shot 1 saved", "Capture failed"],
		"a headless grab either saves or says it failed"
	)
	capture.free()


func _action(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
