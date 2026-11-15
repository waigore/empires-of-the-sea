class_name InputActions
extends RefCounted
## Registers the demo's InputMap actions at runtime so gameplay code never
## hard-codes key codes (AGENTS.md: use InputMap actions).

const PAN_LEFT := "pan_left"
const PAN_RIGHT := "pan_right"
const PAN_UP := "pan_up"
const PAN_DOWN := "pan_down"
const ZOOM_IN := "zoom_in"
const ZOOM_OUT := "zoom_out"
const END_TURN := "end_turn"
const FOCUS_CAPITAL := "focus_capital"
const CANCEL := "cancel"
const MUTE := "mute"
## The cartouche's one lens seal: walks the four map readings on each press.
const LENS := "resource_lens"
const DIPLOMACY_LENS := "diplomacy_lens"
## Third map reading: which of the crown's own tiles reach the capital by road.
const CROWN_LENS := "crown_road_lens"
## Fourth map reading: the garrison, wall and hospital of every charted province.
const DEFENCE_LENS := "defence_lens"
## Fifth map reading: the squadrons in every zone the crown charts, the station
## they hold and the battle the turn will resolve there.
const SEA_LENS := "sea_lens"
## Opens the whole-empire civilian roster from anywhere on the map.
const CIVILIAN_ROSTER := "civilian_roster"
## Opens the muster roll: every army and squadron the crown holds (DR-20261113-12).
const MUSTER_ROLL := "muster_roll"
## Opens the province ledger: every province the crown holds (DR-20261115-09).
const PROVINCE_LEDGER := "province_ledger"
## Opens the command ledger: every commander the crown's pool holds
## (DR-20261115-11).
const COMMAND_LEDGER := "command_ledger"
## Opens the crown's eyes: the spy network and the courts it shadows
## (DR-20261115-10).
const SPY_LEDGER := "spy_ledger"
## Opens the towns ledger: every town the crown holds and the step that raises
## it (DR-20261115-12).
const TOWNS_LEDGER := "towns_ledger"
## Opens the navy ledger: every hull the crown floats, squadron by squadron
## (DR-20261115-14).
const NAVY_LEDGER := "navy_ledger"


static func ensure_actions() -> void:
	_bind(PAN_LEFT, [KEY_A, KEY_LEFT])
	_bind(PAN_RIGHT, [KEY_D, KEY_RIGHT])
	_bind(PAN_UP, [KEY_W, KEY_UP])
	_bind(PAN_DOWN, [KEY_S, KEY_DOWN])
	_bind(ZOOM_IN, [KEY_E, KEY_EQUAL, KEY_KP_ADD])
	_bind(ZOOM_OUT, [KEY_Q, KEY_MINUS, KEY_KP_SUBTRACT])
	_bind(END_TURN, [KEY_SPACE, KEY_ENTER])
	_bind(FOCUS_CAPITAL, [KEY_F, KEY_HOME])
	_bind(CANCEL, [KEY_ESCAPE])
	_bind(MUTE, [KEY_M])
	_bind(LENS, [KEY_L])
	_bind(DIPLOMACY_LENS, [KEY_P])
	_bind(CROWN_LENS, [KEY_R])
	_bind(DEFENCE_LENS, [KEY_K])
	_bind(SEA_LENS, [KEY_H])
	_bind(CIVILIAN_ROSTER, [KEY_C])
	_bind(MUSTER_ROLL, [KEY_O])
	_bind(PROVINCE_LEDGER, [KEY_T])
	_bind(COMMAND_LEDGER, [KEY_G])
	_bind(SPY_LEDGER, [KEY_I])
	_bind(TOWNS_LEDGER, [KEY_B])
	_bind(NAVY_LEDGER, [KEY_N])


static func _bind(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_get_events(action).is_empty():
		return
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
