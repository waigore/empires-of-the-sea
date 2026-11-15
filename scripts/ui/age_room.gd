class_name AgeRoom
extends VBoxContainer
## The age's race as a printed table (wiki: victory § Military victory, § Victory
## Check; DR-20261115-05). The Gazette's foot states one line of the race; this
## room prints the whole standing, one row per Great Power, so the crown can read
## who is near the bar and who is not. Presentation only: every number is the
## read [VictoryStandings.rows] hands the end-of-turn check, so the table can
## never name a bar or a holding the check does not act on (REQ-P2-03, REQ-P3-03,
## REQ-P5-03).

const INK_SOFT: Color = Color(0.34, 0.26, 0.16)
const EMPTY_LINE: String = "No Great Power stands to be read."
const HEADINGS: Array[String] = ["CROWN", "OLD WORLD · TO THE AGE"]

## The rows this room last printed, in the race's own order.
var rows: Array[Dictionary] = []
## The crown reading the sheet, or NO_ID for the full-AI observer.
var human: int = MapModel.NO_ID
## The campaign's calendar, as the sheet's foot words it.
var calendar: String = ""
## The bar the age is won at, as [VictoryStandings.bar_note] words it.
var note: String = ""


func _init() -> void:
	add_theme_constant_override("separation", 4)


## Rebuilds the table from the payload the map's gazette adapter built:
## `rows`, `human`, `calendar` and `note` (see MapPlayGazette.age_payload).
func fill(payload: Dictionary) -> void:
	UiRowBuilder.clear(self)
	rows.clear()
	rows.assign(payload.get("rows", []))
	human = int(payload.get("human", MapModel.NO_ID))
	calendar = String(payload.get("calendar", ""))
	note = String(payload.get("note", ""))
	if rows.is_empty():
		add_child(GazetteParts.label(EMPTY_LINE, 14, Palette.INK))
		return
	add_child(_headings())
	add_child(GazetteParts.rule(Palette.INK_FAINT))
	for entry: Dictionary in rows:
		add_child(_row(entry))
	_footer()


## One row's name column: the court, then the two facts the race turns on — the
## reader's own crown and the race's leader.
static func name_text(entry: Dictionary, reader: int = MapModel.NO_ID) -> String:
	var parts: PackedStringArray = [String(entry.get("name", ""))]
	if bool(entry.get("human", false)):
		parts.append("your crown")
	if reader != MapModel.NO_ID and bool(entry.get("leader", false)):
		parts.append("leads")
	return " · ".join(parts)


## One row's standing column: where the court stands against its own bar, and
## what it still needs — a crown already on the bar never reads "0 to go".
static func standing_text(entry: Dictionary) -> String:
	var holdings: int = int(entry.get("holdings", 0))
	var bar: int = int(entry.get("bar", 0))
	var need: int = maxi(int(entry.get("need", 0)), 0)
	var to_go: String = "on the bar" if need == 0 else "%d to go" % need
	return "%d of %d · %s" % [holdings, bar, to_go]


func _headings() -> Control:
	var row := UiRowBuilder.row(0.0)
	var first := GazetteParts.label(HEADINGS[0], 11, INK_SOFT)
	first.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(first)
	row.add_child(cell(HEADINGS[1], 11, INK_SOFT))
	return row


func _row(entry: Dictionary) -> Control:
	var row := UiRowBuilder.row(0.0)
	var ink: Color = Palette.INK
	var name := GazetteParts.label(name_text(entry, human), 14, ink)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(cell(standing_text(entry), 14, ink))
	return row


## A table cell is one line (issue #672): a cell left to wrap reports no minimum
## width, so the row's HBox hands it a strip of glyphs and the standing column
## stacks one letter per line. The name column keeps the sheet's wrap, so a
## phone plate breaks a long court name at a word instead of crushing the
## standing beside it.
static func cell(text: String, pixels: int, ink: Color) -> Label:
	var out := GazetteParts.label(text, pixels, ink)
	out.autowrap_mode = TextServer.AUTOWRAP_OFF
	return out


func _footer() -> void:
	add_child(GazetteParts.spacer(8))
	add_child(GazetteParts.rule(Palette.INK_FAINT))
	if not calendar.is_empty():
		add_child(GazetteParts.label(_sentence(calendar), 13, INK_SOFT, true))
	if not note.is_empty():
		add_child(GazetteParts.label(note, 13, INK_SOFT))


## The calendar line opens the sentence the way the sheet's foot does, without
## touching the words after it ("the calendar closes in 140 turns").
static func _sentence(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_upper() + text.substr(1)
