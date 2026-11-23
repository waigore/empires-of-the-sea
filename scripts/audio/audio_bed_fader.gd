class_name AudioBedFader
extends RefCounted
## The fades the desk runs over its beds: each one is a Tween written onto a
## player, kept so a driven run can land them and a fresh mix can clear them
## (REQ-P1-06, docs/testing.md § Speed rules). Node-free: the desk owns the
## tree, this owns the book of fades still walking.

## Multiplier on every fade. Live play reads each knob as its published length;
## a driven run (the headless smoke) sets it to 0 so no frame is spent waiting
## out a fade nothing listens to.
var scale: float = 1.0

## The newest fades, oldest first. A short book keeps a burst of quick switches
## from pinning every tween it ever wrote.
var _fades: Array[Tween] = []


## Writes the fade with a tween born from `tree`. When `stop_when_done` is set the
## player falls silent at the end of the walk.
func fade(
	tree: Node,
	player: AudioStreamPlayer,
	target_db: float,
	seconds: float,
	stop_when_done: bool
) -> void:
	# A driven run asks for no fade: land on the knob at once, as a zero-length
	# crossfade already does, so the bed is the same without the wait.
	var length: float = seconds * scale
	if length <= 0.0:
		player.volume_db = target_db
		if stop_when_done:
			player.stop()
		return
	var tween: Tween = tree.create_tween()
	tween.tween_property(player, "volume_db", target_db, length)
	if stop_when_done:
		tween.tween_callback(player.stop)
	_fades.append(tween)
	if _fades.size() > 8:
		_fades = _fades.slice(_fades.size() - 8)


## Steps every waiting fade to its end, the way the tree would have on its own
## frames. A driven run calls this so no Tween keeps the tree busy after the
## last assert.
func land() -> void:
	for tween: Tween in _fades:
		if tween.is_valid():
			tween.custom_step(60.0)
	_fades.clear()


## Kills every waiting fade: the mix has spoken and the desk lands the knobs.
func clear() -> void:
	for tween: Tween in _fades:
		if tween.is_valid():
			tween.kill()
	_fades.clear()


## The fades still walking, oldest first.
func pending() -> Array[Tween]:
	return _fades
