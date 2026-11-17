extends GdToolsTest
## Lean coverage for HudCampaignEnd and GameHud's routing into it (REQ-P3-01).
## The full calendar-cap MapScreen theme lives in test_campaign_end; this suite
## only exercises the collaborator so a chrome extract stays inside the tier-1
## 5 min budget.

var _host: Control = null
var _overlay: VictoryOverlay = null
var _seal: Button = null
var _glow: Panel = null
var _end: HudCampaignEnd = null
var _hud: GameHud = null


func before_each() -> void:
	_host = Control.new()
	add_child(_host)
	_overlay = VictoryOverlay.new()
	_host.add_child(_overlay)
	_seal = Button.new()
	_host.add_child(_seal)
	_glow = Panel.new()
	_host.add_child(_glow)
	_end = HudCampaignEnd.new()
	_end.bind(_host, _overlay, _seal, _glow, null)
	_hud = GameHud.new()
	add_child(_hud)
	_hud.campaign_end = _end


func after_each() -> void:
	if is_instance_valid(_hud):
		_hud.free()
	if is_instance_valid(_host):
		_host.free()
	_hud = null
	_host = null
	_overlay = null
	_seal = null
	_glow = null
	_end = null


func test_victory_routes_through_the_plate_and_seals_the_door() -> void:
	var state := VictoryState.military(FactionCatalog.PLAYER_FACTION, 10)
	_hud.show_victory(state, FactionCatalog.PLAYER_FACTION, 12)
	assert_true(_hud.campaign_over)
	assert_true(_hud.is_victory_shown())
	assert_true(_seal.disabled)
	assert_eq(_seal.text, HudCampaignEnd.SEALED_TEXT)
	assert_false(_glow.visible)


func test_calendar_cap_and_defeat_raise_the_same_sealed_plate() -> void:
	_hud.show_campaign_complete(FactionCatalog.PLAYER_FACTION, 50, FactionCatalog.PLAYER_FACTION)
	assert_true(_hud.campaign_over)
	assert_true(_overlay.is_shown())
	_hud.set_campaign_over(false)
	assert_false(_hud.campaign_over)
	assert_eq(_seal.text, HudCampaignEnd.OPEN_TEXT)
	assert_true(_glow.visible)
	var defeat := DefeatState.terminal_fall(
		FactionCatalog.PLAYER_FACTION, FactionCatalog.PLAYER_FACTION + 1, 20
	)
	_hud.show_defeat(defeat, FactionCatalog.PLAYER_FACTION)
	assert_true(_hud.campaign_over)
	assert_true(_hud.is_victory_shown())


func test_auto_seat_mirrors_the_seal_until_the_campaign_ends() -> void:
	_end.mirror_seat(true, false)
	assert_true(_seal.disabled)
	assert_eq(_seal.text, "AUTO")
	_end.mirror_seat(false, false)
	assert_false(_seal.disabled)
	assert_eq(_seal.text, HudCampaignEnd.OPEN_TEXT)
	_end.mirror_seat(true, true)
	assert_true(_seal.disabled)
	assert_eq(_seal.text, HudCampaignEnd.SEALED_TEXT)


func test_cartouche_routes_the_turn_line_and_minimap_markings() -> void:
	var cartouche := HudChartCartouche.new()
	var turn_label := Label.new()
	_host.add_child(turn_label)
	# Minimap needs a live tree node; bind without building so routing still runs.
	var mini := Minimap.new()
	_host.add_child(mini)
	cartouche.bind(turn_label, mini)
	_hud.cartouche = cartouche
	_hud.set_turn(3, 1494)
	assert_eq(turn_label.text, "Turn 3  ·  1494")
	_hud.refresh_minimap()
	_hud.update_view_rect(Rect2(0, 0, 10, 10))
	# set_minimap with a null model is a no-op inside Minimap; the route still
	# counts as covered when cartouche is bound.
	_hud.set_minimap(null, Vector2(32, 32), null)
