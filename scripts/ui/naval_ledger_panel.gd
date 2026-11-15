class_name NavalLedgerPanel
extends SheetFrame
## The crown's navy: every hull the crown floats in both charts, read squadron by
## squadron — her class, her guns, the holds she carries and where she sails
## (wiki: ships-and-naval § Ship combat and cargo stats; DR-20261115-14). The
## projection lives in [NavalLedger]; this sheet only renders headings and rows
## and asks MapPlayForceLedger to jump to a hull's squadron (REQ-P3-02,
## REQ-P3-03). The sheet chrome, fade and pause-door park come from SheetFrame.

var _rows: VBoxContainer = null
var _empty: Label = null
var _bar: LedgerFilterBar = null
var _region: String = LedgerRows.REGION_ALL
var _reading: String = NavalLedger.READING_ALL
var _snapshot: Dictionary = {}


func _init() -> void:
	title_text = "THE CROWN'S NAVY"
	hint_text = (
		"Visit opens the squadron's chart and dossier. The sheet reads every "
		+ "hull as she stands; it never launches, docks or orders one."
	)
	toggle_action = InputActions.NAVY_LEDGER


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both charts' fleet rosters for the player's crown and repaints.
func refresh() -> void:
	if play == null or play.world == null or play.ship_layer == null:
		return
	_snapshot = NavalLedger.snapshot(
		play.world, play.ship_layer.regions, play.player_faction
	)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	var art: Texture2D = ShipArt.medallion("frigate")
	if art == null:
		return Icon.new("anchor", 42.0, Palette.GOLD)
	var crest := TextureRect.new()
	crest.texture = art
	crest.custom_minimum_size = Vector2(42, 42)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return crest


func _can_open() -> bool:
	return super._can_open() and play.ship_layer != null


func _build_body(column: VBoxContainer) -> void:
	_bar = LedgerFilterBar.new()
	_bar.fill(
		"Chart", "Hull", LedgerRows.REGION_FILTERS, NavalLedger.READINGS,
		NavalLedger.reading_label
	)
	_bar.chosen.connect(_on_filter)
	column.add_child(_bar)
	# The rule a crown buys hulls by sits on the sheet, not in a hover: a phone
	# hides the footer hint (REQ-P1-07, REQ-P5-03).
	var note := UiRowBuilder.label(NavalLedger.note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- filters -----------------------------------------------------------------


func _on_filter(key: String, region_row: bool) -> void:
	if region_row:
		_region = key
	else:
		_reading = key
	refresh()


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	_bar.render(_region, _reading)
	_subtitle.text = NavalLedger.summary(_snapshot, _region, _reading)
	var shown: int = NavalLedger.count(_snapshot, _region, _reading)
	_empty.visible = shown == 0
	if shown == 0:
		_empty.text = _empty_text()
		return
	LedgerList.fill(
		_rows, _empty, NavalLedger.groups(_snapshot, _region, _reading), _heading, _make_row
	)


## One squadron's heading: where she sails and the station she holds, then the
## hulls she flies. A hull's orders are her squadron's, so they are read once.
func _heading(group: Dictionary, count: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var title := Label.new()
	title.text = "%s  ·  %d hull%s" % [
		String(group["heading"]), count, "" if count == 1 else "s"
	]
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Palette.GOLD_DIM)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var standing := UiRowBuilder.label(
		_standing_text(group), 10, Color(0.74, 0.68, 0.55, 0.85)
	)
	standing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(standing)
	return box


static func _standing_text(group: Dictionary) -> String:
	return "%s  ·  %s  ·  %d holds  ·  %.1f strength" % [
		String(group["place"]),
		String(group["station"]),
		int(group["holds"]),
		float(group["strength"]),
	]


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := NavalLedgerRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


## The explanation a filter that empties the sheet earns: the crown may hold no
## hull yet, or the filter may be hiding them (REQ-P5-05).
func _empty_text() -> String:
	if int(_snapshot.get("total", 0)) == 0:
		var slips: int = NavalLedger.squadron_count(_snapshot, _region)
		if slips > 0:
			return (
				"No hull afloat in %s — the yard launches the first, and every "
				+ "hull she builds is read here."
			) % NavalLedger.scope_text(_region)
		return "No squadron answers this chart. Clear a filter to see the whole navy."
	return "No hull answers this view. Clear a filter to see the whole navy."


## Visit frames the hull's squadron and opens its dossier: a hull has no marker
## of her own, so the sea she sails is the one the map can show.
func _visit(region: int, fleet_id: int) -> void:
	if play == null:
		return
	if MapPlayForceLedger.focus(play, region, ForceLedger.KIND_SQUADRON, fleet_id):
		close()
