class_name AudioDirector
extends Node
## Presentation-layer audio: one music bed with a crossfade pair, a small SFX
## voice pool and the sea ambience. Nothing here decides gameplay; screens call
## `play_event` / `play_music` and the mix stays in `AudioMix` (REQ-P1-06, P3).
##
## The desk owns the tree and the printers; the books are node-free helpers: the
## fades live in [AudioBedFader], the bed pair in [AudioBedDeck], the cue voices
## in [AudioVoicePool], the streams in [AudioStreamShelf], and the rotate flag in
## [MusicRotation]. A driven run can still land its fades without the desk holding
## a book of Tweens per switch (docs/testing.md § Speed rules).
##
## Lives as a scene node (no autoload) so `arch-lint` keeps autoloads empty and
## tests can instantiate it in isolation.

signal mix_changed(music_volume: float, sfx_volume: float, muted: bool)

const MUSIC_FADE := 1.6
const SFX_VOICES := 6
const SILENT_DB := -80.0
const AMBIENCE_GAIN := 0.55
## A mix knob settles to disk this long after the last turn, so a drag of the
## slider writes once (REQ-P1-06).
const SAVE_DELAY := 0.5

## Multiplier on every bed fade. Live play reads each knob as its published
## length; a driven run (the headless smoke) sets it to 0 so no frame is spent
## waiting out a fade nothing listens to (docs/testing.md § Speed rules).
var fade_scale: float:
	get:
		return fader.scale
	set(value):
		fader.scale = value

var mix: AudioMix = AudioMix.new()
var settings_path: String = AudioMix.SETTINGS_PATH
## Last bed requested — intent, even when the stream is missing on disk.
var last_track_id: String = ""
## The fades still walking, so a driven run lands them without a Tween per switch.
var fader: AudioBedFader = AudioBedFader.new()
## The cue book: the last cue named and how many were started (the suites and
## the smoke count `cues.played`; a muted cue still names its request).
var cues: AudioVoicePool = AudioVoicePool.new()
## The rotate book: whether the score is walking `MusicPlaylist.ROTATION`.
var rotation: MusicRotation = MusicRotation.new()

var _beds: AudioBedDeck = AudioBedDeck.new()
var _shelf: AudioStreamShelf = AudioStreamShelf.new()
var _ambience: AudioStreamPlayer = null
var _save_timer: Timer = null
var _current_track: String = ""


## True while the rotate is walking; an explicit bed clears it. The map score
## reads this to tell "the tune is running" from "a battle paused it".
var rotating: bool:
	get:
		return rotation.running
	set(value):
		if value:
			rotation.start()
		else:
			rotation.hold()


func _ready() -> void:
	_build_players()
	mix.load_from(settings_path)
	_apply_mix()


# --- cues --------------------------------------------------------------------


func play_event(event_name: String, volume_scale: float = 1.0) -> bool:
	if not AudioEvents.has(event_name):
		return false
	cues.note(event_name)
	var stream: AudioStream = _stream(AudioEvents.path_for(event_name))
	if stream == null:
		return false
	var voice: AudioStreamPlayer = cues.take()
	if not mix.muted and voice != null:
		var cue: Dictionary = AudioEvents.cue(event_name)
		var pitch: float = float(cue.get("pitch", 0.0))
		var trim: float = float(cue.get("volume_db", -12.0))
		var gain: float = linear_to_db(clampf(volume_scale, 0.05, 1.0))
		_sound(voice, stream, trim + gain + mix.sfx_db(), randf_range(-pitch, pitch))
	return true


## One-shot musical hit (victory fanfare, defeat knell) over the running bed.
func play_stinger(track_id: String, volume_db: float = -4.0) -> bool:
	var stream: AudioStream = _stream(MusicPlaylist.path_for(track_id))
	if stream == null:
		return false
	AudioStreamShelf.set_loop(stream, false)
	var voice: AudioStreamPlayer = cues.take()
	if not mix.muted and voice != null:
		_sound(voice, stream, volume_db + mix.sfx_db(), 0.0)
	return true


# --- music -------------------------------------------------------------------


func play_music(track_id: String, fade: float = MUSIC_FADE, rotate: bool = false) -> bool:
	if MusicPlaylist.track(track_id).is_empty():
		return false
	# An explicit bed (the battle tune, a menu door) pauses the rotate; it resumes
	# on the next era change or turn close. A rotate bed never loops: its end is
	# the hand-off to the next one.
	var loop: bool = MusicPlaylist.loops(track_id) and not rotate
	last_track_id = track_id
	var live: AudioStreamPlayer = _beds.live()
	if track_id == _current_track and live != null and live.playing:
		AudioStreamShelf.set_loop(live.stream, loop)
		_note_rotate(rotate, track_id)
		return true
	var stream: AudioStream = _stream(MusicPlaylist.path_for(track_id))
	if stream == null:
		return false
	AudioStreamShelf.set_loop(stream, loop)
	_crossfade(stream, fade)
	_current_track = track_id
	_note_rotate(rotate, track_id)
	_start_ambience()
	return true


## Start the rotate, or keep the one already running. A rotate bed plays once —
## no loop — and hands over to the next when it ends, so a session hears the
## whole set instead of one loop for hours (issue #1154).
func play_rotation(track_id: String = "", fade: float = MUSIC_FADE) -> bool:
	var wanted: String = track_id if not track_id.is_empty() else MusicPlaylist.ROTATION[0]
	if not MusicPlaylist.rotates(wanted):
		return false
	return play_music(wanted, fade, true)


func stop_music(fade: float = MUSIC_FADE) -> void:
	_note_rotate(false, "")
	_current_track = ""
	fader.fade(self, _beds.live(), SILENT_DB, fade, true)


## Lands every bed now at the knob it is fading toward, the way `_apply_mix`
## does when the mix changes. A driven run ends its fades this way so no Tween
## keeps the tree busy after the last assert (docs/testing.md § Speed rules).
func land_fades() -> void:
	fader.land()
	# The stopped bed stays stopped; the desk only restores the live one, and
	# only when the mix is not muted (the mute assert left it at silence).
	if _current_track.is_empty() or mix.muted:
		return
	_beds.live().volume_db = mix.music_db()


func current_track_id() -> String:
	return _current_track


## The bed the desk is holding: the one playing, or the one it last asked for.
## A suite or a driven run reads this instead of walking the players.
func live_bed() -> AudioStreamPlayer:
	return _beds.live()


## The bed waiting its turn under a crossfade: the tail of a switch, not the tune.
func sleeping_bed() -> AudioStreamPlayer:
	return _beds.waiting()


# --- mix ---------------------------------------------------------------------


func set_music_volume(value: float) -> void:
	mix.set_music(value)
	_mix_spoken()


func set_sfx_volume(value: float) -> void:
	mix.set_sfx(value)
	_mix_spoken()


func set_muted(value: bool) -> void:
	mix.set_muted(value)
	_mix_spoken()


func toggle_mute() -> void:
	set_muted(not mix.muted)


func is_muted() -> bool:
	return mix.muted


# --- internals ---------------------------------------------------------------


## One door for the rotate flag: a rotate bed names where it walks, any other
## bed (or a stop) pauses the rotate.
func _note_rotate(rotate: bool, track_id: String) -> void:
	if rotate:
		rotation.start(track_id)
	else:
		rotation.hold()


## Applies a fresh mix, saves it soon and tells the desk's listeners: one door
## for every knob, so the three setters cannot drift apart (REQ-P1-06).
func _mix_spoken() -> void:
	_apply_mix()
	if _save_timer != null:
		_save_timer.start()
	mix_changed.emit(mix.music, mix.sfx, mix.muted)


## One cue on a pooled voice: the pool picks the player, the caller prices it.
func _sound(voice: AudioStreamPlayer, stream: AudioStream, volume_db: float, pitch: float) -> void:
	voice.stream = stream
	voice.pitch_scale = 1.0 + pitch
	voice.volume_db = volume_db
	voice.play()


func _build_players() -> void:
	var beds: Array[AudioStreamPlayer] = []
	for index in 2:
		var bed := AudioStreamPlayer.new()
		bed.name = "Music%d" % index
		bed.finished.connect(_on_bed_finished.bind(bed))
		add_child(bed)
		beds.append(bed)
	_beds.adopt(beds, SILENT_DB)
	var voices: Array[AudioStreamPlayer] = []
	for index in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Sfx%d" % index
		add_child(voice)
		voices.append(voice)
	cues.adopt(voices, SILENT_DB)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.volume_db = SILENT_DB
	add_child(_ambience)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(func() -> void: mix.save(settings_path))
	add_child(_save_timer)


func _apply_mix() -> void:
	fader.clear()
	_beds.rest_knobs(mix.music_db(), SILENT_DB)
	_ambience.volume_db = _ambience_db()
	cues.hush(SILENT_DB)


func _ambience_db() -> float:
	if mix.muted:
		return SILENT_DB
	return mix.music_db() + linear_to_db(AMBIENCE_GAIN)


func _start_ambience() -> void:
	if _ambience == null or _ambience.playing:
		return
	var stream: AudioStream = _stream(MusicPlaylist.AMBIENCE)
	if stream == null:
		return
	AudioStreamShelf.set_loop(stream, true)
	_ambience.stream = stream
	_ambience.volume_db = _ambience_db()
	_ambience.play()


## A rotate bed ran to its end and hands over to the next tune. The other bed
## (the tail of a crossfade) ending moves nothing: only the live bed's end is a
## hand-off. The callback binds its own bed; a driven run may call with none.
func _on_bed_finished(bed: AudioStreamPlayer = null) -> void:
	if not rotation.running:
		return
	if bed != null and bed != _beds.live():
		return
	play_rotation(rotation.next())


func _crossfade(stream: AudioStream, fade: float) -> void:
	var outgoing: AudioStreamPlayer = _beds.live()
	var incoming: AudioStreamPlayer = _beds.turn()
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	fader.fade(self, outgoing, SILENT_DB, fade, true)
	fader.fade(self, incoming, mix.music_db(), fade, false)


func _stream(path: String) -> AudioStream:
	return _shelf.stream(path)
