class_name CommandLedgerRow
extends LedgerRow
## One commander in the crown's command ledger: his medallion, the name the
## roster christened him with, the medals on his colours and what they buy in
## the field (wiki: military-generals § Medals; DR-20261115-11). Presentational
## only — [CommandLedger] owns the figures and GeneralRoster owns the name.
##
## The row reads, it does not visit: no chip, no Visit door, no whole-row tap.
## The skeleton is LedgerRow's; the medal tally is the row's own state column.

var _medals: Label = null
var _pip: TextureRect = null


func _build_icon() -> Control:
	var portrait := TextureRect.new()
	portrait.texture = ChromeIcons.texture("commander")
	portrait.custom_minimum_size = Vector2(36, 36) if compact else Vector2(42, 42)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return portrait


func _wants_chip() -> bool:
	return false


func _wants_visit() -> bool:
	return false


## The medals a commander wears: one chevron for every decoration he has earned,
## counted beside it so a phone reads four without counting glyphs.
func _build_state(state: VBoxContainer) -> void:
	state.add_theme_constant_override("separation", 5)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pip = TextureRect.new()
	_pip.texture = ChromeIcons.texture("chevron")
	_pip.custom_minimum_size = Vector2(18, 18)
	_pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.add_child(_pip)
	_medals = UiRowBuilder.label("", 13, Palette.GOLD)
	_medals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state.add_child(_medals)


func _fill() -> void:
	var medals: int = int(data.get("medals", 0))
	_name.text = String(data.get("name", "Commander"))
	var effects: Dictionary = data.get("effects", {}) as Dictionary
	if medals <= 0:
		_detail.text = "No medals yet · his line is the crown's own"
		_pip.modulate = Color(1, 1, 1, 0.35)
		_medals.text = "—"
		_medals.add_theme_color_override("font_color", Palette.TEXT_DIM)
		return
	var line: int = int(effects.get("line", 0))
	var morale: int = int(effects.get("morale_pct", 0))
	var initiative: int = int(effects.get("initiative", 0))
	_detail.text = "Line +%d · morale +%d%% · initiative +%d" % [line, morale, initiative]
	if bool(data.get("full", false)):
		_detail.text += " · every medal he can earn"
	_medals.text = "×%d" % medals
	_medals.add_theme_color_override("font_color", Palette.GOLD)
	_medals.tooltip_text = "%d medal%s" % [medals, MoneyText.plural(medals)]
