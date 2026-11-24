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
## The crown's own ration band: the share of its hulls the last Consumption fed
## and the morale every sea battle fights at, or no row for another court's
## squadron (wiki: workers-and-population § Consumption — naval combat;
## DR-20261124-15). Under the strength line it scales.
var _rations: Label = null


func _ready() -> void:
	visible = false
	add_theme_constant_override("separation", 2)
	_strength = UiRowBuilder.wrapped_line("", 12, Palette.GOLD_PALE)
	add_child(_strength)
	# The band sits under the strength it scales and above the pool it does not
	# touch: the sea's own arithmetic, read off the crown's ledger
	# (DR-20261124-15).
	_rations = UiRowBuilder.wrapped_line("", 11, Palette.TEXT_DIM)
	_rations.visible = false
	add_child(_rations)
	_pool = UiRowBuilder.wrapped_line("", 10, Palette.TEXT_DIM)
	add_child(_pool)
	_zone = UiRowBuilder.wrapped_line("", 11, Palette.TEXT)
	add_child(_zone)


## Empty data hides the block, so the capital slip and a port with no squadron
## keep the dossier short. `strength["zone"]` is the sea zone's odds, when read.
## A sighted rival the crown has not read shows `???` and none of the maths, and
## names the watch that would earn it (wiki: ships-and-naval § Sighted strength).
## `rations` is the crown's own navy coverage; another court's sheet passes
## `NO_READING` and prints no band (DR-20261124-15).
func set_data(strength: Dictionary, rations: float = NavyRationRead.NO_READING) -> void:
	visible = int(strength.get("count", 0)) > 0
	if not visible:
		return
	_show_rations(rations)
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
## unread rival leaves the odds unknown, so no share is printed against her. A
## zone the crown would lose also reads the way out of the fight (§ Naval Retreat
## Formula), so the sheet answers both halves of one decision.
func _zone_line(zone: Dictionary) -> String:
	if bool(zone.get("unread", false)):
		return "This zone: %.1f of ours against a strength not yet read." % [
			float(zone.get("own", 0.0))
		]
	if float(zone.get("foe", 0.0)) <= 0.0:
		return ""
	return "This zone: %.1f against %.1f — you hold %s.%s" % [
		float(zone.get("own", 0.0)),
		float(zone.get("foe", 0.0)),
		NavalStrength.share_text(zone),
		_way_out(zone),
	]


## The published retreat the beaten side would take (wiki: ships-and-naval
## § Naval Retreat Formula), read over the court whose side would beat the crown
## and the haven the rules would steer her into — or the refusal when no adjacent
## water is safe, because then every hull goes down. Nothing when the crown holds
## the edge: no retreat is rolled for the side that wins.
func _way_out(zone: Dictionary) -> String:
	var offer: Dictionary = zone.get("retreat", {})
	if offer.is_empty():
		return ""
	var court: String = FactionCatalog.name_of(int(offer.get("court", -1)))
	if not bool(offer.get("ok", false)):
		return " Beaten here by %s: no adjacent water is safe — every hull goes down." % court
	var chance: int = int(round(float(offer.get("chance", 0.0)) * 100.0))
	return " Beaten here by %s: %d%% to slip into the %s." % [
		court, chance, String(offer.get("zone_name", "")),
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


## The ration band under the strength line: the share of the crown's hulls the
## last Consumption fed and the morale every sea battle fights at. A hungry navy
## wears the sheet's gold so the reader sees the bite before the next water, and
## a `NO_READING` opening — another court's squadron — prints no row at all
## (wiki: workers-and-population § Consumption — naval combat; DR-20261124-15).
func _show_rations(coverage: float) -> void:
	if _rations == null:
		return
	var text: String = NavyRationRead.line(coverage)
	_rations.text = text
	_rations.visible = not text.is_empty()
	_rations.tooltip_text = NavyRationRead.tip(coverage)
	var hungry: bool = coverage >= 0.0 and NavyRationRead.multiplier(coverage) < 1.0
	_rations.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if hungry else Palette.TEXT_DIM
	)


## The ration band's text, for tests and tooling (REQ-P3-02). Empty when the
## sheet holds no reading for the squadron on show.
func rations_text() -> String:
	return "" if _rations == null or not _rations.visible else _rations.text
