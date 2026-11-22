class_name ColonyLedgerPanel
extends LedgerSheet
## The world's colonies: every Tribe bought into an empire, who bought it, where
## it stands and what bars its trade (wiki: diplomacy § GP–Tribe Rules — Join
## Empire, § Boycott; DR-20261117-02). The projection lives in [ColonyLedger] and
## the map hook in [MapPlayColonies]; this class only renders the rows and asks
## for the jump (REQ-P3-02, REQ-P3-03). The sheet chrome, fade and pause-door
## park come from SheetFrame; the chips, rows and empty notice from LedgerSheet.
##
## No key of its own: the letters are spent (DR-20261116-16), so the court's
## own door is the one way in.

## The door the line's own court answers: a Tribe the crown has not bought has no
## colony row, and the chain the line names is pressed on THE COURT, so the sheet
## carries the one press that takes the crown there (wiki: diplomacy § The
## crown's own envoy; DR-20261123-02; REQ-P5-01).
const FOLLOW: String = "Open the court"
const FOLLOW_TIP: String = "Open THE COURT on %s — the chain this line names"
const NOT_IN_CONTACT: String = "%s is not in contact, so no court sheet opens."

var _notes: VBoxContainer = null
## The door the reading names, or null before the body builds.
var _follow: Button = null
## The pick the sheet is printing, so the door opens the court the line names.
var _pick: Dictionary = {}


func _init() -> void:
	title_text = "THE COLONIES"
	hint_text = (
		"Visit opens a colony's capital on the map. The roll reads the colonies "
		+ "the rules hold and names the Tribe the court is drawing in; it never "
		+ "signs a deed or lifts a boycott."
	)
	# The reading is the panel's own method, not a closure handed in from the
	# session: a bound callable cannot outlive the session it reads
	# (DR-20261121-14, DR-20261121-16).
	counsel_source = _read_pick


## The Tribe the court's own colony chain is buying this turn, read off the
## sheet's bound session (wiki: diplomacy § GP–Tribe Rules; DR-20261121-16). The
## pick travels whole rather than worded, so the gold line and the door come off
## one read (DR-20261123-02).
func _read_pick(_data: Dictionary) -> Dictionary:
	return MapPlayColonyPick.pick(play)


## Re-reads both charts and the crown's diplomacy record, then repaints.
func refresh() -> void:
	if play == null:
		return
	_snapshot = MapPlayColonies.snapshot(play)
	_fit()
	_sync_counsel()
	_sync_follow()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	var crest := TextureRect.new()
	crest.texture = ChromeIcons.texture("globe")
	crest.custom_minimum_size = Vector2(42, 42)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return crest


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Chart", "Reading", ColonyLedger.FILTERS, ColonyLedger.filter_label,
		_under_chips
	)
	# The rules a crown pays by, under the chips: what a boycott does to a
	# colony, and what a colony is not (REQ-P5-02, REQ-P2-03). A phone hides the
	# footer hint, so the rule sits on the sheet (REQ-P1-07, REQ-P5-03).
	_notes = VBoxContainer.new()
	_notes.add_theme_constant_override("separation", 2)
	column.add_child(_notes)
	_notes.add_child(_note(ColonyLedger.terms_line()))
	_notes.add_child(_note(ColonyLedger.colony_line()))


## What sits under the chips and above the rows: the court's own reading in gold
## and the one press that follows it to the court it names (wiki: diplomacy
## § GP–Tribe Rules; DR-20261121-16, DR-20261123-02).
func _under_chips() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_counsel_line(box)
	_follow = UiRowBuilder.button(FOLLOW, 38.0, 0.0, 13)
	_follow.visible = false
	_follow.pressed.connect(_on_follow)
	box.add_child(_follow)
	return box


## The door stands while the reading names a court and stands down when it names
## none (a footing that shuts new chains), off the same pick the gold line
## prints — so the press never opens a court the sentence does not name
## (DR-20261123-02; REQ-P1-07: printed, never a hover).
func _sync_follow() -> void:
	if _follow == null:
		return
	_pick = {} if _counsel == null else _counsel.pick
	var court: int = MapPlayColonyPick.door(_pick)
	_follow.visible = court >= 0
	if court >= 0:
		_follow.tooltip_text = FOLLOW_TIP % FactionCatalog.name_of(court)


## The door: THE COURT opens on the court the line names, and the colony sheet
## steps aside so the envoy rows are the sheet the crown reads (REQ-P5-01). A
## court the crown is not in contact with says so rather than leaving the press
## silent (REQ-P5-05). Nothing is offered, signed, bought or spent (REQ-P2-03).
func _on_follow() -> void:
	var court: int = MapPlayColonyPick.door(_pick)
	if court < 0:
		return
	if not MapPlayDiplomacy.open_court(play, court):
		if play != null and play.hud != null:
			play.hud.toast(NOT_IN_CONTACT % FactionCatalog.name_of(court))
		return
	close()


## The court the sheet's reading names, or -1 — the door's own target, exposed so
## a suite asserts it instead of walking the rebuilt children (REQ-P3-02).
func door_court() -> int:
	return MapPlayColonyPick.door(_pick)


## The door press as the sheet prints it: null before the body builds
## (REQ-P3-02).
func follow_press() -> Button:
	return _follow


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.85))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = ColonyLedger.groups(_snapshot, _region, _reading)
	var shown: int = ColonyLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


func _empty_text() -> String:
	if int(_snapshot.get("total", 0)) == 0:
		return (
			"No colony answers this view. A Tribe becomes a colony at the end of "
			+ "the Join Empire chain, and a court the crown has not met is nobody's news."
		)
	return "No colony answers this view. Clear a filter to see the whole world."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d colon%s" % [
		String(group["region_label"]).to_upper(), count, "y" if count == 1 else "ies"
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := ColonyLedgerRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


func _subtitle_text(shown: int) -> String:
	return ColonyLedger.summary(_snapshot, _region, shown)


func _visit(region: int, province_id: int) -> void:
	if play == null:
		return
	if MapPlayProvinces.focus(play, region, province_id):
		close()
