class_name MapSoundtrack
extends Node
## Binds map-screen moments to cues and era beds. Owns nothing but the score
## state: it listens to the screen's signals and forwards intent to the
## AudioDirector, so the controller stays free of audio wiring (REQ-P1-06, P3).

## Seconds of battle music before the era bed returns.
const BATTLE_SECONDS := 14.0

var screen: MapScreen = null
var audio: AudioDirector = null

var _battle_timer: Timer = null


func _ready() -> void:
	screen = get_parent() as MapScreen
	if screen == null:
		return
	audio = screen.get_node_or_null("Audio") as AudioDirector
	if audio == null:
		return
	_battle_timer = Timer.new()
	_battle_timer.one_shot = true
	_battle_timer.wait_time = BATTLE_SECONDS
	_battle_timer.timeout.connect(_sync_bed)
	add_child(_battle_timer)
	audio.mix_changed.connect(_on_mix_changed)
	_bind_screen()
	_sync_bed()
	# Children are ready before the screen is: hud/ship_layer exist only after.
	if screen.is_node_ready():
		_bind_widgets()
	else:
		screen.ready.connect(_bind_widgets, CONNECT_ONE_SHOT)


func _unhandled_input(event: InputEvent) -> void:
	if audio == null:
		return
	if InputMap.has_action(InputActions.MUTE) and event.is_action_pressed(InputActions.MUTE):
		audio.toggle_mute()
		_sync_controls()
		get_viewport().set_input_as_handled()


# --- wiring ------------------------------------------------------------------


func _bind_screen() -> void:
	screen.province_selected.connect(_on_province_selected)
	screen.selection_cleared.connect(_on_selection_cleared)
	screen.coast_charted.connect(_on_coast_charted)
	screen.battle_resolved.connect(_on_battle_resolved)
	screen.turn_ended.connect(_on_turn_ended)
	screen.victory_declared.connect(_on_victory_declared)


func _bind_widgets() -> void:
	if screen == null or not is_instance_valid(screen):
		return
	if screen.ship_layer != null:
		screen.ship_layer.ship_selected.connect(_on_fleet_selected)
		screen.ship_layer.fleet_moved.connect(_on_fleet_moved)
	if screen.civilian_layer != null:
		screen.civilian_layer.unit_selected.connect(_on_civilian_selected)
		screen.civilian_layer.unit_moved.connect(_on_civilian_moved)
	if screen.hud != null:
		screen.hud.panel_action.connect(_on_panel_action)
		screen.hud.panel_closed.connect(_on_panel_closed)
		screen.hud.fleet_closed.connect(_on_panel_closed)
		screen.hud.civilian_action.connect(_on_panel_action)
		screen.hud.civilian_cancel.connect(_on_panel_closed)
		screen.hud.civilian_closed.connect(_on_panel_closed)
		screen.hud.zoom_in_pressed.connect(_play.bind(AudioEvents.UI_CLICK))
		screen.hud.zoom_out_pressed.connect(_play.bind(AudioEvents.UI_CLICK))
		screen.hud.victory_dismissed.connect(_play.bind(AudioEvents.UI_CLICK))
	var controls := _controls()
	if controls != null:
		controls.ui_sound.connect(_play)
		controls.music_volume_changed.connect(_on_music_volume_changed)
		controls.sfx_volume_changed.connect(_on_sfx_volume_changed)
		controls.mute_toggled.connect(_on_mute_toggled)
	_sync_controls()


func _controls() -> AudioControls:
	if screen == null or screen.hud == null:
		return null
	return screen.hud.get_node_or_null("AudioControls") as AudioControls


# --- cues --------------------------------------------------------------------


func _play(event_name: String) -> void:
	if audio != null:
		audio.play_event(event_name)


func _on_province_selected(_province_id: int) -> void:
	_play(AudioEvents.PROVINCE_SELECT)
	_play(AudioEvents.PANEL_OPEN)


func _on_selection_cleared() -> void:
	_play(AudioEvents.PANEL_CLOSE)


func _on_fleet_selected(ship: Ship) -> void:
	if ship == null:
		return
	_play(AudioEvents.FLEET_SELECT)


func _on_fleet_moved(_fleet: FleetState, _result: Dictionary) -> void:
	_play(AudioEvents.FLEET_MOVE)


func _on_civilian_selected(unit: CivilianState) -> void:
	if unit == null:
		return
	_play(AudioEvents.CIVILIAN_SELECT)


func _on_civilian_moved(_unit: CivilianState, result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_play(AudioEvents.CIVILIAN_MOVE)
	else:
		_play(AudioEvents.ORDER_DENIED)


func _on_coast_charted(_province_id: int) -> void:
	_play(AudioEvents.COAST_CHARTED)


func _on_panel_closed() -> void:
	_play(AudioEvents.PANEL_CLOSE)


func _on_panel_action(action: String) -> void:
	match action:
		"recruit":
			_play(AudioEvents.COIN)
		"build":
			_play(AudioEvents.UI_CLICK)
		_:
			_play(AudioEvents.UI_CLICK)


func _on_turn_ended(_turn: int) -> void:
	_play(AudioEvents.TURN_BELL)
	_play(AudioEvents.COIN)
	# A battle resolved this turn keeps the battle bed until its timer expires.
	if _battle_timer != null and _battle_timer.time_left > 0.0:
		return
	_sync_bed()


## Campaign decided: the fanfare marks the moment over the running bed.
func _on_victory_declared(_victory: VictoryState) -> void:
	if audio != null:
		audio.play_stinger(MusicPlaylist.VICTORY)


# --- battles -----------------------------------------------------------------


func _on_battle_resolved(battles: Array[Dictionary]) -> void:
	if battles.is_empty() or audio == null:
		return
	for _battle: Dictionary in battles:
		audio.play_event(AudioEvents.BROADSIDE)
	var outcome: int = _player_outcome(battles)
	if outcome > 0:
		audio.play_stinger(MusicPlaylist.VICTORY)
	elif outcome < 0:
		audio.play_event(AudioEvents.HULL_HIT)
		audio.play_stinger(MusicPlaylist.DEFEAT)
	audio.play_music(MusicPlaylist.BROADSIDES, 0.8)
	if _battle_timer != null:
		_battle_timer.start()


## +1 player won every engagement, -1 lost, 0 drawn or mixed.
func _player_outcome(battles: Array[Dictionary]) -> int:
	var won: bool = false
	var lost: bool = false
	for battle: Dictionary in battles:
		var attacker: int = int(battle.get("attacker", -1))
		var defender: int = int(battle.get("defender", -1))
		if attacker != screen.player_faction and defender != screen.player_faction:
			continue
		var outcome: int = int(battle.get("outcome", NavalCombat.Outcome.STALEMATE))
		if outcome == NavalCombat.Outcome.STALEMATE:
			continue
		var player_is_side_one: bool = attacker == screen.player_faction
		var side_one_won: bool = outcome == NavalCombat.Outcome.SIDE1_VICTORY
		if side_one_won == player_is_side_one:
			won = true
		else:
			lost = true
	if won and not lost:
		return 1
	if lost and not won:
		return -1
	return 0


# --- music -------------------------------------------------------------------


func _sync_bed() -> void:
	if audio == null or screen == null:
		return
	var bed: Dictionary = MusicPlaylist.bed_for_turn(screen.turn)
	audio.play_music(String(bed["id"]))


# --- mix ---------------------------------------------------------------------


func _sync_controls() -> void:
	var controls := _controls()
	if controls == null or audio == null:
		return
	controls.set_mix(audio.mix.music, audio.mix.sfx, audio.mix.muted)


func _on_mix_changed(music: float, sfx: float, muted: bool) -> void:
	var controls := _controls()
	if controls != null:
		controls.set_mix(music, sfx, muted)


func _on_music_volume_changed(value: float) -> void:
	if audio != null:
		audio.set_music_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	if audio != null:
		audio.set_sfx_volume(value)


func _on_mute_toggled(muted: bool) -> void:
	if audio != null:
		audio.set_muted(muted)
