class_name AudioEvents
extends RefCounted
## One-shot cue table: gameplay intent -> sound file + mix trim (REQ-P1-06).
## Pure data so tests can assert every cue resolves to a shipped file without
## instantiating an AudioStreamPlayer.

const UI_CLICK := "ui_click"
const PANEL_OPEN := "panel_open"
const PANEL_CLOSE := "panel_close"
const PROVINCE_SELECT := "province_select"
const FLEET_SELECT := "fleet_select"
const FLEET_MOVE := "fleet_move"
const ORDER_DENIED := "order_denied"
const TURN_BELL := "turn_bell"
const COIN := "coin"
const COAST_CHARTED := "coast_charted"
const BROADSIDE := "broadside"
const HULL_HIT := "hull_hit"
const FLEET_SUNK := "fleet_sunk"
const CIVILIAN_SELECT := "civilian_select"
const CIVILIAN_MOVE := "civilian_move"

const ROOT := "res://assets/audio/sfx/"

## volume_db trims the normalised file; pitch is the +/- random detune (fraction)
## so repeated clicks never sound identical.
const CUES: Dictionary = {
	UI_CLICK: {"file": "ui_click.wav", "volume_db": -10.0, "pitch": 0.05},
	PANEL_OPEN: {"file": "panel_open.wav", "volume_db": -9.0, "pitch": 0.03},
	PANEL_CLOSE: {"file": "panel_close.wav", "volume_db": -10.0, "pitch": 0.03},
	PROVINCE_SELECT: {"file": "province_select.wav", "volume_db": -8.0, "pitch": 0.02},
	FLEET_SELECT: {"file": "fleet_select.wav", "volume_db": -7.0, "pitch": 0.02},
	FLEET_MOVE: {"file": "fleet_move.wav", "volume_db": -5.0, "pitch": 0.04},
	ORDER_DENIED: {"file": "order_denied.wav", "volume_db": -7.0, "pitch": 0.02},
	TURN_BELL: {"file": "turn_bell.wav", "volume_db": -4.0, "pitch": 0.01},
	COIN: {"file": "coin.wav", "volume_db": -9.0, "pitch": 0.04},
	COAST_CHARTED: {"file": "coast_charted.wav", "volume_db": -7.0, "pitch": 0.02},
	BROADSIDE: {"file": "broadside.wav", "volume_db": -2.0, "pitch": 0.05},
	HULL_HIT: {"file": "hull_hit.wav", "volume_db": -4.0, "pitch": 0.06},
	FLEET_SUNK: {"file": "fleet_sunk.wav", "volume_db": -3.0, "pitch": 0.03},
	CIVILIAN_SELECT: {"file": "civilian_select.wav", "volume_db": -8.0, "pitch": 0.04},
	CIVILIAN_MOVE: {"file": "civilian_move.wav", "volume_db": -8.0, "pitch": 0.05},
}


static func has(event_name: String) -> bool:
	return CUES.has(event_name)


static func cue(event_name: String) -> Dictionary:
	var found: Variant = CUES.get(event_name, {})
	if found is Dictionary:
		return found
	return {}


static func path_for(event_name: String) -> String:
	var data: Dictionary = cue(event_name)
	if data.is_empty():
		return ""
	return ROOT + String(data.get("file", ""))


static func names() -> Array[String]:
	var out: Array[String] = []
	for key: String in CUES.keys():
		out.append(key)
	out.sort()
	return out
