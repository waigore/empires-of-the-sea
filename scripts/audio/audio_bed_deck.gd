class_name AudioBedDeck
extends RefCounted
## The two beds a crossfade turns between: the one heard and the one warming.
## Node-free — the desk owns the players and the fades, this only keeps the
## book of which bed is which and at what knob (REQ-P1-06).
##
## "Live" is the bed the desk last asked for: the incoming bed mid-crossfade, or
## the resting bed when nothing is fading. The other one is always the next to
## take a new stream.

var _beds: Array[AudioStreamPlayer] = []
var _live: int = 0


## Takes the pair under the deck's hand with the first bed live and the rest
## under `silent_db` until a stream warms one.
func adopt(beds: Array[AudioStreamPlayer], silent_db: float) -> void:
	_beds = beds
	_live = 0
	rest_knobs(silent_db, silent_db)


func live() -> AudioStreamPlayer:
	if _beds.is_empty():
		return null
	return _beds[_live]


## The bed waiting its turn; the live one when there is no second bed.
func waiting() -> AudioStreamPlayer:
	if _beds.size() < 2:
		return live()
	return _beds[1 - _live]


## Hands the next stream to the waiting bed and makes it live. Returns that bed.
func turn() -> AudioStreamPlayer:
	if _beds.size() > 1:
		_live = 1 - _live
	return live()


func live_index() -> int:
	return _live


## Puts the live bed on `live_db` and every other one under `silent_db`.
func rest_knobs(live_db: float, silent_db: float) -> void:
	for index in _beds.size():
		var bed: AudioStreamPlayer = _beds[index]
		bed.volume_db = live_db if index == _live else silent_db
