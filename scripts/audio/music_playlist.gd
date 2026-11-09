class_name MusicPlaylist
extends RefCounted
## Score catalogue and the era rule that picks the bed for a turn's calendar year
## (REQ-P1-06). Pure data: no players, no nodes, so the mapping is unit-tested.

const ROOT := "res://assets/audio/music/"
const AMBIENCE := "res://assets/audio/ambience/ambience_sea.ogg"

const AGE_OF_DISCOVERY := "age_of_discovery"
const SPANISH_MAIN := "spanish_main"
const GILDED_MINUET := "gilded_minuet"
const BROADSIDES := "broadsides"
const VICTORY := "victory"
const DEFEAT := "defeat"

## Exploration beds in era order. The 1500 start opens on a branle; the Baroque
## gigue carries the bulk of a campaign; the galant minuet closes it.
const ERA_BEDS: Array[Dictionary] = [
	{
		"id": AGE_OF_DISCOVERY,
		"from_year": 1500,
		"file": "music_age_of_discovery.ogg",
		"title": "Age of Discovery",
		"era": "Renaissance branle",
	},
	{
		"id": SPANISH_MAIN,
		"from_year": 1550,
		"file": "music_spanish_main.ogg",
		"title": "The Spanish Main",
		"era": "Baroque gigue",
	},
	{
		"id": GILDED_MINUET,
		"from_year": 1700,
		"file": "music_gilded_minuet.ogg",
		"title": "Gilded Minuet",
		"era": "Galant minuet",
	},
]

const TRACKS: Dictionary = {
	AGE_OF_DISCOVERY: {
		"id": AGE_OF_DISCOVERY, "file": "music_age_of_discovery.ogg", "loop": true
	},
	SPANISH_MAIN: {"id": SPANISH_MAIN, "file": "music_spanish_main.ogg", "loop": true},
	GILDED_MINUET: {"id": GILDED_MINUET, "file": "music_gilded_minuet.ogg", "loop": true},
	BROADSIDES: {"id": BROADSIDES, "file": "music_broadsides.ogg", "loop": true},
	VICTORY: {"id": VICTORY, "file": "stinger_victory.ogg", "loop": false},
	DEFEAT: {"id": DEFEAT, "file": "stinger_defeat.ogg", "loop": false},
}


## Bed that suits a calendar year; falls back to the earliest bed before 1500.
static func bed_for_year(year: int) -> Dictionary:
	var chosen: Dictionary = ERA_BEDS[0]
	for bed: Dictionary in ERA_BEDS:
		if year >= int(bed["from_year"]):
			chosen = bed
	return chosen


static func bed_id_for_year(year: int) -> String:
	return String(bed_for_year(year)["id"])


static func bed_for_turn(turn: int) -> Dictionary:
	return bed_for_year(TurnTime.year_for_turn(turn))


static func track(track_id: String) -> Dictionary:
	var found: Variant = TRACKS.get(track_id, {})
	if found is Dictionary:
		return found
	return {}


static func path_for(track_id: String) -> String:
	var data: Dictionary = track(track_id)
	if data.is_empty():
		return ""
	return ROOT + String(data.get("file", ""))


static func loops(track_id: String) -> bool:
	return bool(track(track_id).get("loop", true))


static func ids() -> Array[String]:
	var out: Array[String] = []
	for key: String in TRACKS.keys():
		out.append(key)
	out.sort()
	return out
