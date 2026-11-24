class_name ModalShell
extends Control
## The HUD's one full-screen modal (REQ-P1-07, REQ-P5-01, REQ-P5-07): a dim wash
## that swallows the pointer, a safe-area margin and the plate a door draws
## itself. So open/close, the fade, the pause-door park, the compact fit and the
## back gesture are written once and every cartouche door presents the same way.
##
## A subclass owns what its sheet reads: SheetFrame builds the crown's ledgers,
## the estates card and the Gazette print their own plate, and ModalDoor hosts a
## panel that already carries its chrome (the ledger, the court).
##
## Shells live on their own canvas layer, outside the HUD's safe-area offsets,
## so the shell applies the device insets itself.

const MARGIN_WIDE: int = 42
const MARGIN_COMPACT: int = 10
## The canvas layer every sheet rides: above the HUD's chrome and the pause menu,
## so no bar door or menu row can bleed through an open sheet (REQ-P1-07).
const LAYER: int = 6
## The wash a door lays over the chart: heavy enough that the bar behind it stops
## competing with the sheet. A soft plate used to leave the map readable, and the
## door's information was the worse for it (REQ-P1-05, REQ-P1-07).
const DIM: Color = Color(0.05, 0.04, 0.03, 0.80)
const FILL: Color = Color(Palette.PARCHMENT, 0.99)
const PADDING: Vector4 = Vector4(20, 16, 20, 16)
const PADDING_COMPACT: Vector4 = Vector4(12, 10, 12, 10)

## The session the shell reads (the pause door it parks, the HUD whose news lane
## it holds). Null until a subclass binds it or the tree reaches a screen.
var play: PlaySession = null
## The InputMap action that toggles the shell; empty leaves the key unused.
var toggle_action: String = ""

var _overlay: Control = null
var _margin: MarginContainer = null
var _panel: PanelContainer = null
var _column: VBoxContainer = null
var _fade: Tween = null
## Last applied layout profile (-1 before the first fit).
var _was_compact: int = -1
var _compact: bool = false
## This shell holds the pause door while it is up (mirrored park/release).
var _parked_menu: bool = false


## Gives a sheet its own named layer, so the sheet stands above the pause menu
## and the bar without sharing their canvas item order. Every sheet that is not
## hosted by a ModalDoor rides one of these (REQ-P1-07, REQ-P5-07).
static func mount_layer(host: Node, layer_name: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = layer_name
	layer.layer = LAYER
	host.add_child(layer)
	return layer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build_shell()
	_build_plate(_column)
	visible = false
	resized.connect(_fit)
	_fit()


# --- subclass hooks ----------------------------------------------------------


## Everything the door prints inside the plate: a masthead, a body, a school of
## rows. The shell owns only the plate around it.
func _build_plate(_host: VBoxContainer) -> void:
	pass


## The plate's dress: fill, rule and padding. The Gazette prints paper and the
## estates card its own card, so they paint over this.
func _dress_plate(compact: bool) -> void:
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(FILL, Palette.GOLD_DIM, 1, 4, PADDING_COMPACT if compact else PADDING)
	)


## Whether the door may open. A shell with no session to read (the Gazette, a
## suite's own plate) always can; a ledger needs a campaign under it.
func _can_open() -> bool:
	return true


## Repaint whatever the sheet reads; the shell calls it before it opens.
func refresh() -> void:
	pass


## The compact/narrow profile, once per fit: the masthead's title step, the crest
## a phone drops, the standing lines it trades for rows (REQ-P1-07, RUB-P3-01).
func _apply_profile(_compact_now: bool, _narrow: bool) -> void:
	pass


## True when the compact profile changed after the first fit.
func _on_profile_changed() -> void:
	pass


# --- shell -------------------------------------------------------------------


func _build_shell() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = DIM
	_overlay.add_child(dim)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_margin)

	_panel = PanelContainer.new()
	_margin.add_child(_panel)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_panel.add_child(_column)


# --- open / close ------------------------------------------------------------


func open() -> void:
	if not _can_open():
		return
	visible = true
	refresh()
	_set_menu_visible(false)
	_sync_despatch_cover()
	_reveal()


func close() -> void:
	if not visible:
		return
	visible = false
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	ModalDrag.reset_on(_margin)
	_set_menu_visible(true)
	_sync_despatch_cover()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func _reveal() -> void:
	visible = true
	modulate.a = 0.0
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)


## The pause trigger sits on a higher canvas layer than the HUD; park it while
## the sheet is up so its gold seal does not cut through the frame. The notifier
## mirrors the park: a sheet that closes without ever opening does not release
## another ledger's or the observer's frame (REQ-P5-07).
func _set_menu_visible(show_menu: bool) -> void:
	var session: PlaySession = _play()
	var door: GameMenuDoor = (
		session.pause_menu.door if session != null and session.pause_menu != null else null
	)
	_parked_menu = GameMenuDoor.set_held(door, show_menu, _parked_menu)


## A phone sheet holds the court's news while it is up (HudDespatchCover owns the
## rule); a shell mounted without a HUD simply skips it (REQ-P5-05).
func _sync_despatch_cover() -> void:
	var screen: MapScreen = map_screen()
	if screen != null:
		HudDespatchCover.refresh(screen.hud)


## The campaign the shell stands in, or a subclass' own binding.
func _play() -> PlaySession:
	if play != null:
		return play
	var screen: MapScreen = map_screen()
	return screen.play if screen != null else null


## The screen the shell is mounted on: the doors reach it up the tree rather
## than through a node path (REQ-P3-02).
func map_screen() -> MapScreen:
	var node: Node = get_parent()
	while node != null:
		var screen := node as MapScreen
		if screen != null:
			return screen
		node = node.get_parent()
	return null


func _exit_tree() -> void:
	_set_menu_visible(true)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(InputActions.CANCEL):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action.is_empty() or not event.is_action_pressed(toggle_action):
		return
	var session: PlaySession = _play()
	if session != null and session.campaign_over():
		return
	toggle()
	get_viewport().set_input_as_handled()


# --- layout ------------------------------------------------------------------


func _fit() -> void:
	if _margin == null:
		return
	var view: Vector2 = get_viewport_rect().size
	var compact: bool = HudLayout.is_compact(view)
	var side: int = MARGIN_COMPACT if compact else MARGIN_WIDE
	var insets: Vector4 = PlatformDisplay.safe_insets(get_window())
	_margin.add_theme_constant_override("margin_left", side + int(insets.x))
	_margin.add_theme_constant_override("margin_right", side + int(insets.z))
	_margin.add_theme_constant_override(
		"margin_top", (56 if compact else 88) + int(insets.y)
	)
	_margin.add_theme_constant_override(
		"margin_bottom", (6 if compact else 34) + int(insets.w)
	)
	_column.add_theme_constant_override("separation", 6 if compact else 10)
	_compact = compact
	_dress_plate(compact)
	_apply_profile(compact, view.x < 520.0)
	var profile: int = 1 if compact else 0
	var changed: bool = _was_compact >= 0 and _was_compact != profile
	_was_compact = profile
	if changed:
		_on_profile_changed()
