class_name CommandLedgerRow
extends PanelContainer
## One commander in the crown's command ledger: his medallion, the name the
## roster christened him with, the medals on his colours and what they buy in
## the field (wiki: military-generals § Medals; DR-20261115-11). Presentational
## only — [CommandLedger] owns the figures and GeneralRoster owns the name.

var data: Dictionary = {}
var compact: bool = false

var _name: Label = null
var _effects: Label = null
var _medals: Label = null
var _pip: TextureRect = null


func setup(row: Dictionary) -> void:
	data = row
	_build()
	_fill()


func _build() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.13, 0.11, 0.08, 0.88),
			Color(0.54, 0.43, 0.12, 0.55),
			1,
			3,
			Vector4(8, 5, 8, 5) if compact else Vector4(10, 7, 10, 7)
		)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10 if compact else 12)
	add_child(line)

	var portrait := TextureRect.new()
	portrait.texture = ChromeIcons.texture("commander")
	portrait.custom_minimum_size = Vector2(36, 36) if compact else Vector2(42, 42)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(portrait)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)

	_name = Label.new()
	_name.add_theme_font_override("font", UiTheme.serif())
	_name.add_theme_font_size_override("font_size", 17 if compact else 19)
	_name.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_name)

	_effects = Label.new()
	_effects.add_theme_font_size_override("font_size", 11)
	_effects.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
	_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_effects)

	# The medals a commander wears: one chevron for every decoration he has
	# earned, counted beside it so a phone reads four without counting glyphs.
	var tally := HBoxContainer.new()
	tally.add_theme_constant_override("separation", 5)
	tally.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(tally)
	_pip = TextureRect.new()
	_pip.texture = ChromeIcons.texture("chevron")
	_pip.custom_minimum_size = Vector2(18, 18)
	_pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tally.add_child(_pip)
	_medals = Label.new()
	_medals.add_theme_font_size_override("font_size", 13)
	_medals.add_theme_color_override("font_color", Palette.GOLD)
	_medals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tally.add_child(_medals)


func _fill() -> void:
	var medals: int = int(data.get("medals", 0))
	_name.text = String(data.get("name", "Commander"))
	var effects: Dictionary = data.get("effects", {}) as Dictionary
	if medals <= 0:
		_effects.text = "No medals yet · his line is the crown's own"
		_pip.modulate = Color(1, 1, 1, 0.35)
		_medals.text = "—"
		_medals.add_theme_color_override("font_color", Palette.TEXT_DIM)
		return
	var line: int = int(effects.get("line", 0))
	var morale: int = int(effects.get("morale_pct", 0))
	var initiative: int = int(effects.get("initiative", 0))
	_effects.text = "Line +%d · morale +%d%% · initiative +%d" % [line, morale, initiative]
	if bool(data.get("full", false)):
		_effects.text += " · every medal he can earn"
	_medals.text = "×%d" % medals
	_medals.add_theme_color_override("font_color", Palette.GOLD)
	_medals.tooltip_text = "%d medal%s" % [medals, "" if medals == 1 else "s"]
