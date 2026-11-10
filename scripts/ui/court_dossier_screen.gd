class_name CourtDossierScreen
extends Control
## The full court dossier sheet (wiki: ai-dossier § Logical sections;
## DR-20261110-25): a sheet over the HUD that hosts [CourtDossierBody]. Only the
## chrome lives here — header, safe-area fit, open/close — so the page itself
## stays one domain and the rules never touch a node (REQ-P3-01, REQ-P2-03).
##
## Built once with the court (DiplomacyHud) over its own canvas layer, so opening
## it costs a repaint. The sheet takes the state it is shown with, so it needs no
## session reference and the HUD bootstrap stays untouched (REQ-P3-02).

const MARGIN_WIDE: int = 42
const MARGIN_COMPACT: int = 10

var _overlay: Control = null
var _margin: MarginContainer = null
var _panel: PanelContainer = null
var _column: VBoxContainer = null
var _subtitle: Label = null
var _hint: Label = null
var _close: Button = null
var _fade: Tween = null
## The page, kept public for tests and for a caller that wants the body alone.
var _body: CourtDossierBody = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build()
	visible = false
	resized.connect(_fit)
	_fit()


## Renders and shows the reading for `faction_id`. The caller holds the state, so
## the sheet needs no session reference.
func show_for(
	state: DiplomacyState, world: WorldMap, viewer: int, faction_id: int
) -> void:
	if _body == null:
		return
	var report: Dictionary = IntelDossier.report(state, world, viewer, faction_id)
	_subtitle.text = _court_line(faction_id)
	_body.show_report(report, state, world, viewer, faction_id)
	_fit()
	visible = true
	modulate.a = 0.0
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)


func close() -> void:
	if not visible:
		return
	visible = false
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0


func is_open() -> bool:
	return visible


func _build() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.04, 0.03, 0.80)
	_overlay.add_child(dim)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_margin)

	_panel = PanelContainer.new()
	_margin.add_child(_panel)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_panel.add_child(_column)
	_column.add_child(_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(scroll)
	_body = CourtDossierBody.new()
	scroll.add_child(_body)

	_column.add_child(_footer())


func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var crest := Icon.new("crest", 40, Palette.GOLD)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(crest)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	var title := _label("THE DOSSIER", 26, Palette.GOLD_PALE)
	title.add_theme_font_override("font", UiTheme.serif())
	titles.add_child(title)
	_subtitle = _label("", 12, Palette.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)

	_close = Button.new()
	_close.text = "Close"
	_close.custom_minimum_size = Vector2(92, 40)
	_close.pressed.connect(close)
	header.add_child(_close)
	return header


func _footer() -> Control:
	_hint = _label(
		"Bands are suspicion from what the court could see, not proof: "
		+ "'Confirmed' never names the agenda. Tap an agenda to read its timeline.",
		11,
		Color(0.80, 0.74, 0.62, 0.76)
	)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return _hint


static func _court_line(faction: int) -> String:
	return "%s  ·  %s  ·  %s" % [
		FactionCatalog.name_of(faction),
		FactionCatalog.type_label(FactionCatalog.type_of(faction)),
		FactionCatalog.region_label(FactionCatalog.region_of(faction)),
	]


func _label(text: String, size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	return label


## The sheet lives on its own canvas layer, outside the HUD's safe-area offsets,
## so it applies the device insets itself (REQ-P5-07).
func _fit() -> void:
	if _margin == null:
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	var side: int = MARGIN_COMPACT if compact else MARGIN_WIDE
	var insets: Vector4 = PlatformDisplay.safe_insets(get_window())
	_margin.add_theme_constant_override("margin_left", side + int(insets.x))
	_margin.add_theme_constant_override("margin_right", side + int(insets.z))
	_margin.add_theme_constant_override("margin_top", (56 if compact else 88) + int(insets.y))
	_margin.add_theme_constant_override("margin_bottom", (6 if compact else 34) + int(insets.w))
	_column.add_theme_constant_override("separation", 6 if compact else 10)
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.99),
			Palette.GOLD_DIM,
			1,
			4,
			Vector4(12, 10, 12, 10) if compact else Vector4(20, 16, 20, 16)
		)
	)
	var narrow: bool = get_viewport_rect().size.x < 520.0
	_close.custom_minimum_size.x = 64.0 if narrow else 92.0
	_hint.visible = not compact


## Mobile back closes the sheet before the map or a panel hears the press
## (REQ-P5-07); desktop Escape does the same.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(InputActions.CANCEL):
		close()
		get_viewport().set_input_as_handled()



