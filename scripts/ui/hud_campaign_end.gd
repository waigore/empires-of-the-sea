class_name HudCampaignEnd
extends RefCounted
## The campaign's last plate and the seal it shuts (REQ-P3-01). GameHud routes
## the three decided outcomes — victory, calendar cap, the court's fall — and
## this owns what they share: raise VictoryOverlay, stop the end-turn seal for
## good, and set every dossier aside so the map is read under the plate
## (wiki: victory § Victory Screen, § Calendar campaign end; REQ-P5-06).

## The seal's caption once no turn can be played; longer than END TURN, so the
## plate drops its pictogram and keeps one line.
const SEALED_TEXT: String = "CAMPAIGN ENDED"
const OPEN_TEXT: String = "END TURN"

var host: Control = null
var overlay: VictoryOverlay = null
var button: Button = null
var glow: Panel = null
var panels: HudPanels = null


## TopBar and HudChrome hand over the seal, its glow and the dossier dock.
func bind(
	hud: Control, p_overlay: VictoryOverlay, seal: Button, p_glow: Panel,
	dock: HudPanels
) -> void:
	host = hud
	overlay = p_overlay
	button = seal
	glow = p_glow
	panels = dock


## The three decided outcomes only raise the plate: GameHud seals the door and
## the dossiers first (`set_campaign_over`), so one call owns the latch.
func show_victory(state: VictoryState, player_faction: int, holdings: int) -> void:
	if overlay != null:
		overlay.show_victory(state, player_faction, holdings)


func show_campaign_complete(leader: int, turn: int, player_faction: int) -> void:
	if overlay != null:
		overlay.show_campaign_complete(leader, turn, player_faction)


func show_defeat(defeat: DefeatState, player_faction: int) -> void:
	if overlay != null:
		overlay.show_defeat(defeat, player_faction)


## AutoBar owns the door's day-to-day caption: AUTO while the seat holds the
## turn, END TURN when it lets go. A campaign that never seals (endless cap)
## reads the seat's word; a sealed one keeps CAMPAIGN ENDED for good.
func mirror_seat(auto_active: bool, over: bool) -> void:
	if button == null:
		return
	button.disabled = over or auto_active
	if not over:
		button.text = "AUTO" if auto_active else OPEN_TEXT
	elif auto_active:
		button.text = SEALED_TEXT


func is_plate_shown() -> bool:
	return overlay != null and overlay.is_shown()


## Turns never reopen; only the plate may step aside to keep viewing the map.
## An endless campaign never seals: its cap only plates, so AutoBar re-vectors
## the door to END TURN / AUTO right after (`AutoBar.mirror_seat`).
func set_over(over: bool) -> void:
	if button != null:
		button.disabled = over
		button.text = SEALED_TEXT if over else OPEN_TEXT
		# Longer caption + seal: drop the pictogram so the plate keeps one line.
		button.icon = null if over else ChromeIcons.texture("hourglass")
	if glow != null:
		glow.visible = not over
	if not over or panels == null:
		return
	panels.hide_province()
	panels.hide_fleet()
	panels.hide_civilian()
	panels.hide_army()
	panels.hide_economy()
	panels.hide_research()
	DiplomacyHud.hide(panels)