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
	# The full court dossier is the topmost sheet when it is up: back closes it
	# before the map or the court panel hears the press (REQ-P5-07).
	var dossier: CourtDossierScreen = play.hud.dossier_screen if play.hud != null else null
	if dossier != null and dossier.is_open():
		dossier.close()
		return true
	# The Gazette is a soft surface over the map, but back still sets it aside
	# first so a phone never quits from under an open sheet (REQ-P5-07).
	var gazette: GazettePlate = play.hud.gazette_plate if play.hud != null else null
	if gazette != null and gazette.is_shown():
		gazette.dismiss()
		return true
	# The crown's whole-empire sheets stand over the map: back sets the newest
	# ledger a door opened aside first, so a phone never quits from under it
	# (REQ-P5-07; DR-20261113-12, DR-20261115-09…14, DR-20261116-01…02).
	if HudLedgerDoors.dismiss_open(play.hud):
		return true
	# The college's chart is a sheet standing over the college, so back sets it
	# aside before the ledger under it hears the press (DR-20261115-15).
	var chart: TechTreePanel = play.hud.tech_tree if play.hud != null else null
	if chart != null and chart.is_open():
		chart.close()
		return true
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
