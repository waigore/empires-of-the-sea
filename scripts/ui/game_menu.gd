class_name GameMenu
extends CanvasLayer
## In-game pause menu (REQ-P5-01): resume, save to a local slot, load a local
## slot (the router rebuilds the whole screen), the sound desk, the chart's keys
## (`KeysSheet`) and the way back to the title. The cartouche's own MENU seal
## opens it.

signal save_chosen(slot: int)
signal load_chosen(slot: int)
signal main_menu_chosen

const SAVE_BROWSER: PackedScene = preload("res://scenes/save_browser.tscn")

var save_button: Button = null
var load_button: Button = null
var keys_button: Button = null
var main_menu_button: Button = null
var resume_button: Button = null
var browser: SaveBrowser = null
## The pause door: the cartouche's MENU crest (built here, mounted on the bar),
## and the parking state the roster and ledgers touch while they are up
## (GameMenuDoor, REQ-P3-02).
var door := GameMenuDoor.new()
## Music, effects and mute, folded into the pause page: the map itself carries
## no sound seal (REQ-P1-06).
var sound_desk: SoundDesk = null
## Live campaign seed (wiki: game-setup); copy puts the digits on the clipboard.
var seed_label: Label = null
## The crown's own leader and the effect its key publishes, read on every open
## (wiki: leader-bonuses § Acceptance criteria — UI; DR-20261120-09).
var crown_label: Label = null
var copy_seed_button: Button = null

var _ui: Control = null
var _overlay: Control = null
var _pause_page: VBoxContainer = null
## The pause page's KEYS reading, filled by `KeysSheet` on first open so the
## chart's bindings are read once the map has registered its actions.
var _keys_page: VBoxContainer = null
var _status: Label = null
var _owns_pause: bool = false
var _shown_seed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = Control.new()
	_ui.name = "MenuUI"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiTheme.build()
	add_child(_ui)
	_build_trigger()
	_build_overlay()
	_build_browser()


## The pause door lives in the cartouche now: the crest at the bar's upper-left
## opens this page, so the map carries no loose seal of its own (REQ-P5-01).
## GameMenu mounts it while the bar is already built, so a standalone pause
## (no HUD) keeps its own corner button instead.
func _build_trigger() -> void:
	var seal := Button.new()
	seal.name = "MenuSeal"
	seal.pressed.connect(open)
	TopBar.dress(seal, "", "MENU", "Menu — save, load, sound or return to the title")
	var hud := get_node_or_null("../HUD/HudRoot") as GameHud
	if hud == null or hud.top_row == null:
		seal.position = Vector2(18.0, 132.0)
		_ui.add_child(seal)
		door.mount(seal)
		return
	hud.top_row.add_child(seal)
	hud.top_row.move_child(seal, 0)
	door.mount(seal)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_ui.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.02, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	# Same centred-column contract as the menu pages: centred while it fits,
	# scrolled from the top once it does not (REQ-P5-01).
	var short: bool = MenuFrame.is_short(_ui)
	var row: float = MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	var box: VBoxContainer = MenuFrame.column(_overlay, 380.0)
	var frame := MenuFrame.panel()
	box.add_child(frame)

	_pause_page = VBoxContainer.new()
	_pause_page.add_theme_constant_override("separation", 8 if short else 10)
	frame.add_child(_pause_page)

	var heading := MenuFrame.title("PAUSED", 26 if short else 30)
	_pause_page.add_child(heading)
	if not short:
		_pause_page.add_child(MenuFrame.subtitle("The sea waits while the ledger is open."))

	# Who am I: the crown's own leader and the effect the bonus table publishes
	# for it, in the words the new-game chooser used (REQ-P5-01, REQ-P5-05).
	# A phone drops the caption, not the reading, so the row costs the compact
	# page what the dropped subtitle gave back.
	if not short:
		_pause_page.add_child(MenuFrame.caption("Crown"))
	crown_label = MenuFrame.subtitle("—")
	crown_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_page.add_child(crown_label)

	_pause_page.add_child(MenuFrame.caption("Map seed"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	_pause_page.add_child(seed_row)
	seed_label = MenuFrame.subtitle("—")
	seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_label)
	copy_seed_button = MenuFrame.small_button("COPY", 96.0)
	copy_seed_button.pressed.connect(_on_copy_seed)
	seed_row.add_child(copy_seed_button)

	resume_button = MenuFrame.action_button("RESUME", row)
	resume_button.pressed.connect(close)
	_pause_page.add_child(resume_button)

	save_button = MenuFrame.action_button("SAVE GAME", row)
	save_button.pressed.connect(open_save)
	_pause_page.add_child(save_button)

	load_button = MenuFrame.action_button("LOAD GAME", row)
	load_button.pressed.connect(open_load)
	_pause_page.add_child(load_button)

	# The chart's controls, one press from the pause: a keyboard player never
	# guesses a key, and a touch player reads the door that does the same work
	# (`KeyReference`; REQ-P5-03).
	keys_button = MenuFrame.action_button("KEYS", row)
	keys_button.pressed.connect(open_keys)
	_pause_page.add_child(keys_button)

	main_menu_button = MenuFrame.action_button("MAIN MENU", row)
	main_menu_button.pressed.connect(_on_main_menu)
	_pause_page.add_child(main_menu_button)

	# The mix desk lives here now: the map's cartouche carries no sound seal.
	_pause_page.add_child(MenuFrame.separator())
	sound_desk = SoundDesk.new()
	sound_desk.name = "SoundDesk"
	_pause_page.add_child(sound_desk)

	_status = MenuFrame.subtitle("")
	_status.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_pause_page.add_child(_status)


## The screen's director drives the pause page's desk; the title page binds its
## own bell instead (REQ-P1-06).
func bind_audio(director: AudioDirector) -> void:
	if sound_desk != null:
		sound_desk.bind(director)


func _build_browser() -> void:
	browser = SAVE_BROWSER.instantiate()
	browser.visible = false
	browser.slot_chosen.connect(_on_browser_slot)
	browser.back_pressed.connect(_show_pause_page)
	_overlay.add_child(browser)


func open() -> void:
	if _overlay == null or _overlay.visible:
		return
	_overlay.visible = true
	_show_pause_page()
	_refresh_seed()
	_status.text = ""
	_owns_pause = true
	get_tree().paused = true


func close() -> void:
	if _overlay == null:
		return
	_overlay.visible = false
	if browser != null:
		browser.visible = false
	if _owns_pause:
		get_tree().paused = false
		_owns_pause = false


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func open_save() -> void:
	if browser == null:
		return
	_pause_page.visible = false
	browser.visible = true
	browser.setup(SaveBrowser.Mode.SAVE, _save_dir())


func open_load() -> void:
	if browser == null:
		return
	_pause_page.visible = false
	browser.visible = true
	browser.setup(SaveBrowser.Mode.LOAD, _save_dir())


## The chart's controls on one page (docs/ui-demo.md § Controls): the key each
## action answers to and the door a touch player presses instead
## (`KeyReference`; REQ-P5-03, REQ-P5-07). The page is filled on first open,
## because the map registers its InputMap actions in its own `_ready` and a
## sheet built earlier could print blank caps.
func open_keys() -> void:
	if _overlay == null:
		return
	if not _overlay.visible:
		open()
	_show_keys_page()


func show_save_result(ok: bool, slot: int) -> void:
	_show_pause_page()
	_status.text = (
		"Saved to slot %d." % slot if ok else "The save could not be written."
	)
	if ok and browser != null:
		browser.refresh()


## A slot the router refused: the pause menu comes back with the notice and the
## running campaign stays exactly where it was (wiki: campaign-persistence
## § Load and resume — a refused load replaces nothing).
func show_load_refused(message: String) -> void:
	open()
	_show_pause_page()
	_status.text = message


func _show_pause_page() -> void:
	if _pause_page != null:
		_pause_page.visible = true
	if _keys_page != null:
		_keys_page.visible = false
	if browser != null:
		browser.visible = false


## The pause page's KEYS reading, built on first open from the live InputMap.
func _show_keys_page() -> void:
	if _keys_page == null:
		var frame := _pause_page.get_parent() if _pause_page != null else null
		var host := frame as Control
		if host == null:
			return
		var short: bool = MenuFrame.is_short(_ui)
		_keys_page = VBoxContainer.new()
		_keys_page.name = "KeysPage"
		_keys_page.add_theme_constant_override("separation", 8 if short else 10)
		host.add_child(_keys_page)
		KeysSheet.build(_keys_page, short, _show_pause_page)
	_pause_page.visible = false
	if browser != null:
		browser.visible = false
	_keys_page.visible = true


func _on_browser_slot(slot: int) -> void:
	if browser == null:
		return
	if browser.mode() == SaveBrowser.Mode.SAVE:
		save_chosen.emit(slot)
		return
	close()
	load_chosen.emit(slot)


func _on_main_menu() -> void:
	close()
	main_menu_chosen.emit()


func _save_dir() -> String:
	var screen := get_parent() as MapScreen
	return screen.save_dir if screen != null else SaveStore.DIR


## Prefer the session seed once play is live; fall back to the screen pin.
func _resolve_seed() -> int:
	var screen := get_parent() as MapScreen
	if screen == null:
		return 0
	if screen.play != null:
		return screen.play.map_seed
	return screen.map_seed


func _refresh_seed() -> void:
	_shown_seed = _resolve_seed()
	if seed_label != null:
		seed_label.text = str(_shown_seed) if _shown_seed != 0 else "—"
	if copy_seed_button != null:
		copy_seed_button.disabled = _shown_seed == 0
	if crown_label != null:
		crown_label.text = LeaderCatalog.crown_line(_resolve_leader())


## The crown's own leader as the run bound it: the session roster first, the
## screen's pin while a campaign is still booting, the catalog default last —
## the same three-step read `LeaderCatalog.roster` builds (wiki: leader-bonuses
## § Leader Selection).
func _resolve_leader() -> String:
	var screen := get_parent() as MapScreen
	if screen == null:
		return LeaderCatalog.DEFAULT_KEY
	if screen.play != null:
		var key: String = String(
			screen.play.leaders.get(screen.play.player_faction, "")
		)
		if not key.is_empty():
			return key
	if not screen.player_leader.is_empty():
		return screen.player_leader
	return LeaderCatalog.default_key(screen.player_faction)


func _on_copy_seed() -> void:
	if _shown_seed == 0:
		_refresh_seed()
	if _shown_seed == 0:
		return
	DisplayServer.clipboard_set(str(_shown_seed))
	if _status != null:
		_status.text = "Seed copied."


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed(InputActions.CANCEL):
		handle_back()
		get_viewport().set_input_as_handled()


## Android/iOS back gesture: the save browser and the keys page step aside before
## the pause menu itself closes (REQ-P5-07).
func handle_back() -> bool:
	if not is_open():
		return false
	if browser != null and browser.visible:
		# Prefer the shared closer so pause rows and the browser stay in sync.
		_show_pause_page()
		return true
	if _keys_page != null and _keys_page.visible:
		# The keys reading is one page of the pause, not a layer of its own: back
		# returns to the rows it was opened from.
		_show_pause_page()
		return true
	close()
	return true


func _exit_tree() -> void:
	if _owns_pause:
		get_tree().paused = false
		_owns_pause = false
