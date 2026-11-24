class_name AudioVoicePool
extends RefCounted
## The short cues the desk plays: a small round of voices that take turns so a
## burst of clicks never needs a new node (REQ-P1-06, docs/testing.md § Speed
## rules). Node-free: the desk owns the players, this hands one out and keeps
## count of what was asked — the last cue named and how many were started.
##
## A cue that cannot sound (missing stream, muted mix) is still a request, so the
## desk names it here before its players are asked.

var last_event: String = ""
## Cues started, muted ones included: the driven runs count these.
var played: int = 0

var _voices: Array[AudioStreamPlayer] = []
var _cursor: int = 0


## Takes the voices under the pool's hand and mutes them until a cue warms one.
func adopt(voices: Array[AudioStreamPlayer], silent_db: float) -> void:
	_voices = voices
	_cursor = 0
	for player: AudioStreamPlayer in _voices:
		player.volume_db = silent_db


## Names the cue asked for, so a desk reads intent even when nothing sounds.
func note(event_name: String) -> void:
	last_event = event_name


## The voices under the pool's hand, in the order a cue meets them.
func voices() -> Array[AudioStreamPlayer]:
	return _voices


## Counts one cue started and hands back the voice that carries it.
func take() -> AudioStreamPlayer:
	played += 1
	return next_voice()


## A free voice, else the next in the round (stopped so its new cue starts clean).
func next_voice() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _voices:
		if not player.playing:
			return player
	if _voices.is_empty():
		return null
	var chosen: AudioStreamPlayer = _voices[_cursor % _voices.size()]
	_cursor += 1
	chosen.stop()
	return chosen


## Falls every resting voice silent: a fresh mix mutes what no cue is using.
func hush(silent_db: float) -> void:
	for player: AudioStreamPlayer in _voices:
		if not player.playing:
			player.volume_db = silent_db
