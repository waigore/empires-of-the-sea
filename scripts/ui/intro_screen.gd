class_name IntroScreen
extends Control
## The crown's charge: the campaign's opening gate, printed as a broadside
## before the first turn (wiki: dialogue-management § Kinds, `game_start_intro`:
## dismiss-only, no resume API, raised before orders and end-turn).
##
## One press opens the age; there is no second option and nothing to answer
## (REQ-P5-02). The page prints what [CampaignIntro] composed, so it can never
## speak a rule of its own (REQ-P2-03, REQ-P3-03).

## The crown begins the age. The router installs the map screen on this.
signal begin_pressed

const PANEL_WIDTH: float = 620.0
const PHONE_PANEL_WIDTH: float = 520.0
const BODY_PIXELS: int = 17
const BODY_PIXELS_SHORT: int = 15
## Printed ink on paper: the broadside reads as a sheet, not as another dossier
## (REQ-P1-02, REQ-P1-07).
const INK_SOFT: Color = Color(0.28, 0.22, 0.15)

var begin_button: Button = null
var paper: PanelContainer = null

var _address: Dictionary = {}
var _kicker: Label = null
var _title: Label = null
var _stamp: Label = null
var _body: Label = null
var _charges: VBoxContainer = null


func _ready() -> void:
	InputActions.ensure_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	MenuFrame.backdrop(self)
	if _address.is_empty():
		_address = CampaignIntro.default_address()
	_build()


## Prints one charge. Call before the page enters the tree, or call it again on
## a page already mounted (the shell builds it once, tests reprint it).
func show_address(address: Dictionary) -> void:
	_address = address
	if not is_inside_tree() or _body == null:
		return
	_render()


func _build() -> void:
	var short: bool = MenuFrame.is_short(self)
	var box: VBoxContainer = MenuFrame.page(
		self, PHONE_PANEL_WIDTH if short else PANEL_WIDTH, _build_actions(short)
	)
	if short:
		box.add_theme_constant_override("separation", 8)
	else:
		box.add_child(MenuFrame.crest(56))
	paper = PanelContainer.new()
	paper.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Palette.PAPER, Palette.GOLD_DIM, 2, 3, Vector4(24, 20, 24, 20))
	)
	box.add_child(paper)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	paper.add_child(column)

	_kicker = _label("", 11, INK_SOFT)
	column.add_child(_kicker)
	_title = _label("", 26 if short else 32, Palette.INK)
	column.add_child(_title)
	_stamp = _label("", 13, INK_SOFT, true)
	column.add_child(_stamp)
	column.add_child(_rule(Palette.INK_LINE))
	_body = _label("", BODY_PIXELS_SHORT if short else BODY_PIXELS, Palette.INK)
	column.add_child(_body)
	column.add_child(_rule(Palette.INK_FAINT))
	_charges = VBoxContainer.new()
	_charges.add_theme_constant_override("separation", 2)
	column.add_child(_charges)
	_render()


## The gate's one action lives outside the scroll, so BEGIN stays on screen at
## every window height, including a phone held landscape (REQ-P5-01, REQ-P5-07).
func _build_actions(short: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	begin_button = MenuFrame.action_button(
		CampaignIntro.BEGIN, MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	)
	begin_button.custom_minimum_size = Vector2(
		minf(260.0, maxf(get_viewport_rect().size.x - 48.0, 180.0)),
		MenuFrame.BUTTON_HEIGHT_SHORT if short else MenuFrame.BUTTON_HEIGHT
	)
	begin_button.pressed.connect(begin)
	row.add_child(begin_button)
	return row


func _render() -> void:
	_kicker.text = String(_address.get("kicker", "")).to_upper()
	_title.text = String(_address.get("title", ""))
	_stamp.text = String(_address.get("stamp", ""))
	_body.text = String(_address.get("body", ""))
	for child: Node in _charges.get_children():
		_charges.remove_child(child)
		child.queue_free()
	for line: Variant in _address.get("charges", []) as Array:
		_charges.add_child(_label(String(line), 13, INK_SOFT, true))
	if begin_button != null:
		begin_button.text = String(_address.get("begin", CampaignIntro.BEGIN))
		begin_button.grab_focus()


## The gate's single dismissal: the crown begins the age. Never silent — the
## router installs the map screen on this signal (REQ-P5-05).
func begin() -> void:
	begin_pressed.emit()


## Android/iOS back is the same one dismissal: a gate with no second option must
## never quit the app from under the player (REQ-P5-07).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		begin()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.CANCEL):
		begin()
		get_viewport().set_input_as_handled()


func _label(text: String, pixels: int, ink: Color, italic: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UiTheme.serif_italic() if italic else UiTheme.serif())
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", ink)
	return label


func _rule(ink: Color) -> Control:
	var line := ColorRect.new()
	line.color = ink
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
