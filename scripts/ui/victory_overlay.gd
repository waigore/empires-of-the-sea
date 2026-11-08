class_name VictoryOverlay
extends Control
## Campaign-end plate (wiki: victory § Victory Screen, military variant).
## The HUD mounts it when the rules set a victory; it names the winner, type and
## turn and lets the crown keep viewing the map with the campaign over.
## Presentation only: it reads the VictoryState the rules produced (REQ-P2-03).

signal dismissed

const MIN_PANEL_WIDTH: float = 460.0
const VIEWPORT_MARGIN: float = 24.0
## Calendar-cap variant (wiki: victory § Calendar campaign end).
const CALENDAR_TITLE: String = "Campaign complete"
const NO_WINNER: String = "No crown prevails"

var state: VictoryState = null

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title: Label = null
var _winner: Label = null
var _detail: Label = null
var _tagline: Label = null
var _continue: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build()
	visible = false
	resized.connect(_fit)


## Renders one decided campaign. `player_faction` only picks the address line;
## `holdings` is the winner's Old World province count.
func show_victory(p_state: VictoryState, player_faction: int, holdings: int) -> void:
	state = p_state
	if state == null:
		visible = false
		return
	_title.text = state.type_label().to_upper()
	_winner.text = state.winner_name().to_upper()
	_detail.text = "%d Old World provinces  ·  Turn %d  ·  %d" % [
		holdings, state.turn_number, TurnTime.year_for_turn(state.turn_number)
	]
	_tagline.text = (
		"The age belongs to your crown."
		if state.won_by(player_faction)
		else "%s has won the age." % state.winner_name()
	)
	_mount()


## Renders the calendar-cap variant: no military victory, only the strongest
## crown by power score — or a shared top score, which declares no-one.
func show_campaign_complete(leader: int, turn: int) -> void:
	state = null
	_title.text = CALENDAR_TITLE.to_upper()
	_winner.text = (
		FactionCatalog.name_of(leader).to_upper()
		if leader != MapModel.NO_ID
		else NO_WINNER.to_upper()
	)
	_detail.text = "No military victory  ·  Turn %d  ·  %d" % [
		turn, TurnTime.year_for_turn(turn)
	]
	_tagline.text = (
		"%s closes the age strongest." % FactionCatalog.name_of(leader)
		if leader != MapModel.NO_ID
		else "The crowns close the age in a dead heat."
	)
	_mount()


func _mount() -> void:
	_continue.text = "View final state"
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	_continue.grab_focus()


## Continue-viewing path: the map stays, the plate steps aside, turns stay shut.
func dismiss() -> void:
	if not visible:
		return
	visible = false
	dismissed.emit()


func is_shown() -> bool:
	return visible


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.078, 0.063, 0.047, 0.78)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.11, 0.09, 0.07, 0.97), Palette.GOLD, 2, 4, Vector4(32, 26, 32, 26)
		)
	)
	centre.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(column)

	column.add_child(_label("THE CAMPAIGN IS DECIDED", 12, Palette.GOLD_DIM))
	_title = _label("MILITARY VICTORY", 32, Palette.GOLD)
	column.add_child(_title)
	column.add_child(_rule())
	_winner = _label("", 26, Palette.GOLD_PALE)
	column.add_child(_winner)
	_detail = _label("", 15, Palette.TEXT_DIM)
	column.add_child(_detail)
	_tagline = _label("", 14, Palette.TEXT)
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_tagline)
	column.add_child(_spacer(8))
	column.add_child(_actions())
	_fit()


func _actions() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_continue = Button.new()
	_continue.text = "View final state"
	_continue.custom_minimum_size = Vector2(220, 46)
	_continue.add_theme_font_size_override("font_size", 18)
	_continue.add_theme_color_override("font_color", Palette.INK)
	_continue.add_theme_color_override("font_hover_color", Palette.INK)
	_continue.add_theme_color_override("font_pressed_color", Palette.INK)
	_continue.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.GOLD, Palette.GOLD_PALE, 1, 3, Vector4(14, 8, 14, 8))
	)
	_continue.add_theme_stylebox_override(
		"hover", UiTheme.box(Palette.GOLD_PALE, Color(1, 0.96, 0.85), 1, 3, Vector4(14, 8, 14, 8))
	)
	_continue.add_theme_stylebox_override(
		"pressed", UiTheme.box(Palette.GOLD_DIM, Palette.GOLD, 1, 3, Vector4(14, 8, 14, 8))
	)
	_continue.pressed.connect(dismiss)
	row.add_child(_continue)
	return row


func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Palette.GOLD_DIM
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _spacer(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## Phones and small windows: the plate never outgrows the viewport.
func _fit() -> void:
	if _panel == null:
		return
	var room: float = maxf(size.x - VIEWPORT_MARGIN * 2.0, 280.0)
	_panel.custom_minimum_size = Vector2(minf(MIN_PANEL_WIDTH, room), 0)
	if _tagline != null:
		_tagline.custom_minimum_size = Vector2(minf(MIN_PANEL_WIDTH, room) - 72.0, 0)
