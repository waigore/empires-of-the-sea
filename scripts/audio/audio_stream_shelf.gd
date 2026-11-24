class_name AudioStreamShelf
extends RefCounted
## The streams the desk has already loaded, keyed by path, and the one loop rule
## every bed and cue obeys (REQ-P1-06). Node-free: the desk owns the players,
## this owns the cache so a repeated cue costs no load and a driven run that
## plays a tune twice reads it once (docs/testing.md § Speed rules).
##
## A path that is empty or missing on disk reads as null, so the desk can price a
## cue without a stream and still count the request.

var _cache: Dictionary = {}


## The stream at `path`, loaded once; null when the path is empty or missing.
func stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = load(path)
	if loaded is AudioStream:
		_cache[path] = loaded
		return loaded
	return null


## Sets the loop each stream family carries, so one rule serves Ogg and Wav beds.
static func set_loop(stream: AudioStream, loop: bool) -> void:
	if stream == null:
		return
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = loop
		return
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
