class_name CourtRows
extends RefCounted
## How a court row is drawn in the court panel: the relative power line under a
## Great Power's name and the band it names (wiki: diplomacy § Great Power power
## score, § Acceptance criteria). Kept out of [DiplomacyPanel] so the panel stays
## under the P3 size bar (REQ-P3-01); presentation only — every number comes from
## [DiplomacyPower], so a row can never invent a score (REQ-P2-03).

## Band words for the relative line, highest share first. The share is the
## court's power over the reader's, so 1.0 is even.
const POWER_TIERS: Array[Dictionary] = [
	{"min": 1.5, "word": "OVERWHELMING"},
	{"min": 1.15, "word": "STRONGER"},
	{"min": 0.87, "word": "EVEN"},
	{"min": 0.65, "word": "WEAKER"},
	{"min": 0.0, "word": "FRAIL"},
]


## One court's band, its signed share of the reader's power and the colour that
## reads it: a court above the reader reads red, one the reader matches or
## exceeds reads green. Empty when there is no score for that court — a Minor
## Nation, or a session that supplied no orders.
static func line(power: Dictionary, viewer: int, faction_id: int) -> Dictionary:
	if power.is_empty() or faction_id == viewer:
		return {}
	if FactionCatalog.type_of(faction_id) != FactionCatalog.Type.GREAT_POWER:
		return {}
	if not power.has(faction_id) or not power.has(viewer):
		return {}
	var mine: int = int(power[viewer])
	var theirs: int = int(power[faction_id])
	var word: String = word_for(DiplomacyPower.power_ratio(mine, theirs))
	var percent: int = DiplomacyPower.power_percent(mine, theirs)
	var sign: String = "+" if percent > 0 else ("−" if percent < 0 else "")
	return {
		"word": word,
		"text": "%s\n%s%d%%" % [word, sign, absi(percent)],
		"color": Palette.DIPLO_WAR if theirs > mine else Palette.DIPLO_FRIENDLY,
		"mine": mine,
		"theirs": theirs,
		"percent": percent,
	}


## The band word for a power ratio.
static func word_for(ratio: float) -> String:
	for tier: Dictionary in POWER_TIERS:
		if ratio >= float(tier["min"]):
			return String(tier["word"])
	return String(POWER_TIERS[POWER_TIERS.size() - 1]["word"])


## The figures behind the band, for the selected court's page: both absolute
## scores and the band in words, so the comparison never depends on hover
## (REQ-P1-05).
static func detail_text(mark: Dictionary) -> String:
	return (
		"Power %s  ·  yours %s  ·  %s"
		% [
			TextFormat.thousands(int(mark["theirs"])),
			TextFormat.thousands(int(mark["mine"])),
			String(mark["word"]).capitalize(),
		]
	)


## Adds the power line under a court's name. `row` already holds the court's
## button, so the line never swallows the tap.
static func decorate(
	row: VBoxContainer, faction_id: int, power: Dictionary, viewer: int
) -> void:
	var mark: Dictionary = line(power, viewer, faction_id)
	if mark.is_empty():
		return
	var label := Label.new()
	label.text = String(mark["text"])
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", mark["color"] as Color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.tooltip_text = "Public power %s against your %s" % [
		TextFormat.thousands(int(mark["theirs"])),
		TextFormat.thousands(int(mark["mine"])),
	]
	row.add_child(label)


## The standing a court row prints under its name: the herald's word, the state
## of war and every treaty the pair holds (wiki: diplomacy § Order list).
static func status_line(
	state: DiplomacyState, player: int, faction: int, record: DiplomacyRelation
) -> String:
	var parts: PackedStringArray = [
		record.meter_label(), DiplomacyCatalog.state_label(record.at_war)
	]
	if record.formal_alliance:
		parts.append("Formal Alliance")
	if DiplomacyTrade.is_ftp(state, player, faction):
		parts.append("Trade Pact")
	if DiplomacyTrade.is_boycotting(state, player, faction):
		parts.append("Boycott")
	var colony_of: int = state.colony_of(faction)
	if colony_of >= 0:
		parts.append("Colony of %s" % FactionCatalog.name_of(colony_of))
	return "  ·  ".join(parts)


## The colour that standing reads in: war in crimson, a formal alliance in the
## friendly green, every other stand in plain ink.
static func status_color(record: DiplomacyRelation) -> Color:
	if record.at_war:
		return Color(0.85, 0.38, 0.32)
	if record.formal_alliance:
		return Color(0.58, 0.78, 0.52)
	return Palette.TEXT


## The overture chain's standing for the selected court: the stage reached and
## the stage the chain offers next, so the price of the next envoy is never
## hidden (wiki: diplomacy § Overture chain).
static func overture_line(state: DiplomacyState, player: int, faction: int) -> String:
	var stage: String = state.overture(player, faction)
	var next: String = DiplomacyCatalog.next_stage(stage)
	var line: String = "Overture: %s" % DiplomacyCatalog.stage_label(stage)
	if not next.is_empty():
		line += "  ·  next: %s" % DiplomacyCatalog.stage_label(next)
	return line


## Court order in the panel's list: the Great Powers first, then the Minors and
## Tribes, each band by name (wiki: diplomacy § Acceptance criteria).
static func sorts_before(left: int, right: int) -> bool:
	var left_type: int = FactionCatalog.type_of(left)
	var right_type: int = FactionCatalog.type_of(right)
	if left_type != right_type:
		return left_type < right_type
	return FactionCatalog.name_of(left) < FactionCatalog.name_of(right)
