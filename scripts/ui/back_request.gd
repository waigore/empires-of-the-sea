class_name BackRequest
extends RefCounted
## Android/iOS back gesture: dismiss the top layer, or tell the caller to quit.
## Android delivers the request twice for one press, so the debounce keeps one
## press from closing a panel and then quitting in the same frame (REQ-P5-07).

const DEBOUNCE_MS: int = 300

static var _last_ms: int = -DEBOUNCE_MS


## Returns true when the press was consumed (a layer closed, or it was a repeat);
## false means the map is bare and the caller should quit.
static func handle(play: PlaySession, improvements: ImprovementPanel) -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _last_ms < DEBOUNCE_MS:
		return true
	_last_ms = now
	if improvements != null and improvements.is_open():
		improvements.close()
		return true
	if play == null:
		return false
	var panels: HudPanels = play.hud.panels
	if panels.is_economy_open():
		panels.hide_economy()
	elif panels.is_research_open():
		panels.hide_research()
	elif panels.is_diplomacy_open():
		DiplomacyHud.hide(panels)
	elif panels.is_army_panel_open():
		panels.hide_army()
	elif (
		panels.is_panel_open()
		or panels.is_fleet_panel_open()
		or panels.is_civilian_panel_open()
	):
		MapPlayInput.deselect(play)
	else:
		return false
	return true
