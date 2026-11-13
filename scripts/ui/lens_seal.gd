class_name LensSeal
extends Button
## The cartouche's one reading seal (REQ-P5-03). A click steps to the next map
## lens, a long press -- or a right click on desktop -- names the reading on a
## menu instead. The lenses themselves are MapPlayInput's: this control only
## raises the intent and mirrors the reading the screen reports back through
## `mirror`, so the seal can never claim a lens the map is not showing.

signal cycle_requested
signal lens_chosen(kind: String)

const TOOLTIP: String = "Map lens — click to cycle, hold for the list"
## The walk a click makes: no lens, then the four readings. The last reading
## steps back to the plain map because touch has no other way to clear it.
const CYCLE: Array = [
	"",
	LensLegend.KIND_SURVEY,
	LensLegend.KIND_DIPLOMACY,
	LensLegend.KIND_CROWN_ROAD,
	LensLegend.KIND_DEFENCE,
]
const MENU_LABELS: Array = [
	"No lens",
	"Resources  (L)",
	"Diplomacy  (P)",
	"Crown road  (R)",
	"Defence  (K)",
]
## R and K keep their old home on the seals (L and P stay on the screen's key
## table), so a press raises its reading and a second press puts it down.
const KEY_READINGS: Array = [
	[InputActions.CROWN_LENS, LensLegend.KIND_CROWN_ROAD],
	[InputActions.DEFENCE_LENS, LensLegend.KIND_DEFENCE],
]
const KIND_NAMES := {
	"": "no lens",
	LensLegend.KIND_SURVEY: "resources",
	LensLegend.KIND_DIPLOMACY: "the political map",
	LensLegend.KIND_CROWN_ROAD: "the crown road",
	LensLegend.KIND_DEFENCE: "the defences",
}
const KIND_ICONS := {
	"": "lens",
	LensLegend.KIND_SURVEY: "lens",
	LensLegend.KIND_DIPLOMACY: "diplomacy",
	LensLegend.KIND_CROWN_ROAD: "road",
	LensLegend.KIND_DEFENCE: "swords",
}
## Seconds a press must be held before the menu replaces the cycle.
const HOLD_SECONDS: float = 0.5

## The reading on screen; empty while every lens is down.
var active_kind: String = ""

var _hold: Timer = null
var _menu: PopupMenu = null
## The press that opened the menu must not also count as a cycle on release.
var _held: bool = false


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	_hold = Timer.new()
	_hold.name = "Hold"
	_hold.one_shot = true
	_hold.wait_time = HOLD_SECONDS
	add_child(_hold)
	_hold.timeout.connect(_on_held)

	_menu = PopupMenu.new()
	_menu.name = "LensMenu"
	_menu.add_theme_font_size_override("font_size", 14)
	_menu.add_theme_color_override("font_color", Palette.TEXT)
	_menu.add_theme_color_override("font_hover_color", Palette.INK)
	_menu.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM)
	_menu.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.98), Palette.GOLD_DIM, 1, 4, Vector4(6, 6, 6, 6))
	)
	_menu.add_theme_stylebox_override(
		"hover",
		UiTheme.box(Palette.GOLD, Palette.GOLD, 0, 2, Vector4(6, 4, 6, 4))
	)
	add_child(_menu)
	for index in MENU_LABELS.size():
		_menu.add_radio_check_item(String(MENU_LABELS[index]), index)
	_menu.id_pressed.connect(_on_menu_id)

	button_down.connect(_on_press_started)
	button_up.connect(_on_press_ended)
	pressed.connect(_on_pressed)


func _shortcut_input(event: InputEvent) -> void:
	for row: Array in KEY_READINGS:
		if not event.is_action_pressed(StringName(row[0])):
			continue
		var kind: String = String(row[1])
		lens_chosen.emit("" if kind == active_kind else kind)
		accept_event()
		return


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		open_menu()
		accept_event()


## Mirror the reading the screen raised: pressed, pictogram and tooltip follow.
func mirror(active: bool, kind: String) -> void:
	active_kind = kind if active else ""
	set_pressed_no_signal(active)
	var medallion := find_child("Medallion", true, false) as TextureRect
	if medallion != null:
		medallion.texture = ChromeIcons.texture(String(KIND_ICONS.get(active_kind, "lens")))
	tooltip_text = "%s  ·  %s" % [TOOLTIP, String(KIND_NAMES.get(active_kind, "no lens"))]


func open_menu() -> void:
	if _menu == null or _menu.visible:
		return
	for index in CYCLE.size():
		_menu.set_item_checked(index, String(CYCLE[index]) == active_kind)
	_menu.reset_size()
	_menu.position = Vector2i(get_screen_position() + Vector2(0.0, size.y))
	_menu.popup()


func is_menu_open() -> bool:
	return _menu != null and _menu.visible


## A menu pick: the screen decides whether the reading can be raised, then
## reports it back through GameHud.set_lens and `mirror`.
func choose(kind: String) -> void:
	_held = false
	_menu.hide()
	lens_chosen.emit(kind)


func _on_press_started() -> void:
	_held = false
	_hold.start()


func _on_press_ended() -> void:
	_hold.stop()


func _on_held() -> void:
	_held = true
	open_menu()


func _on_pressed() -> void:
	if _held:
		_held = false
		return
	cycle_requested.emit()


func _on_menu_id(id: int) -> void:
	choose(String(CYCLE[id]))
