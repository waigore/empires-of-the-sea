class_name MusicRotation
extends RefCounted
## The rotate flag: whether the score is walking `MusicPlaylist.ROTATION` rather
## than holding one explicit bed (issue #1154). Node-free, so the desk and the
## map score read one answer instead of a bare bool each keeps its own copy of.
##
## The flag only says which bed the desk asked for; the desk still plays it.

## True while the rotate is walking: an explicit bed clears it, a rotate bed sets it.
var running: bool = false

var _track: String = ""


## The rotate starts on `track_id`; an empty name keeps the one already walking.
func start(track_id: String = "") -> void:
	running = true
	if not track_id.is_empty():
		_track = track_id


## The bed now under an explicit play: the rotate pauses and forgets where it was.
func hold() -> void:
	running = false
	_track = ""


func track() -> String:
	return _track


## The next tune the rotate hands over to, once it is running.
func next() -> String:
	return MusicPlaylist.next_in_rotation(_track)
