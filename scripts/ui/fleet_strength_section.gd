class_name FleetStrengthSection
extends VBoxContainer
## The fleet dossier's combat maths: the weighted strength the resolver fights
## with, the stat totals behind it and the hull pool that absorbs the victor's
## damage, plus the share of a contested sea zone each side holds (wiki:
## ships-and-naval § Naval Strength Aggregation Formula). Reads plain data;
## NavalStrength owns every number. Kept to three short lines: the dossier has
## to fit a phone sheet beside the orders (REQ-P1-07).

var _strength: Label = null
var _pool: Label = null
var _zone: Label = null


func _ready() -> void:
	visible = false
	add_theme_constant_override("separation", 2)
	_strength = _line(12, Palette.GOLD_PALE)
	add_child(_strength)
	_pool = _line(10, Palette.TEXT_DIM)
	add_child(_pool)
	_zone = _line(11, Palette.TEXT)
	add_child(_zone)


## Empty data hides the block, so the capital slip and a port with no squadron
## keep the dossier short. `strength["zone"]` is the sea zone's odds, when read.
## A sighted rival the crown has not read shows `???` and none of the maths, and
## names the watch that would earn it (wiki: ships-and-naval § Sighted strength).
func set_data(strength: Dictionary) -> void:
	visible = int(strength.get("count", 0)) > 0
	if not visible:
		return
	var read: bool = bool(strength.get("known", true))
	if not read:
		_strength.text = "??? strength — watch her across a turn to read her weight."
		_strength.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_pool.text = "Lose sight of her and the watch starts over."
		_pool.visible = true
		_zone.text = ""
		_zone.visible = false
		return
	_pool.visible = true
	_zone.visible = false
	_strength.add_theme_color_override("font_color", Palette.GOLD_PALE)
	var zone: Dictionary = strength.get("zone", {})
	_strength.text = "%.1f strength = %s" % [
		float(strength.get("strength", 0.0)), String(strength.get("formula", ""))
	]
	_pool.text = "Hull pool %.1f · above %d%% of a zone's strength wins." % [
		float(strength.get("durability", 0.0)), _need()
	]
	_zone.text = _zone_line(zone)
	_zone.visible = not _zone.text.is_empty()
	_zone.add_theme_color_override("font_color", _zone_colour(zone))


## The zone's arithmetic in one line, and nothing when the water is empty: a
## dossier that says "no enemy here" three times is noise, not evidence. An
## unread rival leaves the odds unknown, so no share is printed against her.
func _zone_line(zone: Dictionary) -> String:
	if bool(zone.get("unread", false)):
		return "This zone: %.1f of ours against a strength not yet read." % [
			float(zone.get("own", 0.0))
		]
	if float(zone.get("foe", 0.0)) <= 0.0:
		return ""
	return "This zone: %.1f against %.1f — you hold %s." % [
		float(zone.get("own", 0.0)),
		float(zone.get("foe", 0.0)),
		NavalStrength.share_text(zone),
	]


func _zone_colour(zone: Dictionary) -> Color:
	if bool(zone.get("unread", false)):
		return Palette.GOLD_PALE
	match NavalStrength.outcome_of(zone):
		NavalStrength.OUTCOME_WIN:
			return Palette.HEALTH_HIGH
		NavalStrength.OUTCOME_LOSS:
			return Palette.HEALTH_LOW
	return Palette.GOLD_PALE


func _need() -> int:
	return int(round(NavalStrength.need() * 100.0))


func _line(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
