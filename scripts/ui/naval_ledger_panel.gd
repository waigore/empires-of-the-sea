class_name NavalLedgerPanel
extends ForceLedgerSheet
## The crown's navy: every hull the crown floats in both charts, read squadron by
## squadron — her class, her guns, the holds she carries and where she sails
## (wiki: ships-and-naval § Ship combat and cargo stats; DR-20261115-14), and the
## sails the court's own naval pass would order, with the squadrons that reading
## names marked `▸` on their headings (DR-20261121-13, DR-20261122-05). The
## projection lives in [NavalLedger]; this sheet only names its words and asks
## MapPlayForceLedger to jump to a hull's squadron (REQ-P3-02, REQ-P3-03). The
## sheet chrome, fade and pause-door park come from SheetFrame; the chips, rows,
## headings and empty notice from ForceLedgerSheet.


func _init() -> void:
	title_text = "THE CROWN'S NAVY"
	hint_text = (
		"A ▸ marks the squadrons the court would sail this turn. Visit opens "
		+ "the squadron's chart and dossier. The sheet reads every hull as she "
		+ "stands; it never launches, docks or orders one."
	)
	toggle_action = InputActions.NAVY_LEDGER
	# The reading is the panel's own method, not a closure handed in from the
	# session: a bound callable cannot outlive the session it reads
	# (DR-20261121-14).
	counsel_source = _read_counsel


## The sails the court's own naval pass would order its squadrons this turn, read
## off the sheet's bound session (wiki: ships-and-naval § The crown's navy;
## DR-20261121-13). The pick also keys the squadrons it names, so their headings
## wear the counsel's mark (DR-20261122-05).
func _read_counsel(data: Dictionary) -> Dictionary:
	return MapPlayNavyPick.pick(play, data)


## Whether the court's own reading names this squadron, so her heading leads with
## the mark a crown finds her by among a long roll (DR-20261122-05).
func _is_marked(group: Dictionary) -> bool:
	return _counsel.keys().has(MapPlayPickProse.row_key(group, "fleet"))


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


# --- what the navy names -----------------------------------------------------


func _layer_ready() -> bool:
	return play.ship_layer != null


func _read() -> Dictionary:
	return NavalLedger.snapshot(play.world, play.ship_layer.regions, play.player_faction)


func _filters() -> Array:
	return NavalLedger.READINGS


func _reading_word(key: String) -> String:
	return NavalLedger.reading_label(key)


func _row_word(count: int) -> String:
	return "hull" if count == 1 else "hulls"


func _groups(region_key: String, reading_key: String) -> Array[Dictionary]:
	return NavalLedger.groups(_snapshot, region_key, reading_key)


func _count(region_key: String, reading_key: String) -> int:
	return NavalLedger.count(_snapshot, region_key, reading_key)


## Where one squadron sails and the station she holds, above the hulls she flies:
## place, station, holds and strength.
func _standing_text(group: Dictionary) -> String:
	return "%s  ·  %s  ·  %d holds  ·  %.1f strength" % [
		String(group["place"]),
		String(group["station"]),
		int(group["holds"]),
		float(group["strength"]),
	]


## The rule a crown buys hulls by sits on the sheet, not in a hover: a phone
## hides the footer hint (REQ-P1-07, REQ-P5-03).
func _note() -> Control:
	var note := UiRowBuilder.label(NavalLedger.note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


## The count line the navy prints: the view against the chart it is read in,
## with the fleet's own totals when every hull is shown (REQ-P5-05).
func _subtitle_text(_shown: int) -> String:
	return NavalLedger.summary(_snapshot, _region, _reading)


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
