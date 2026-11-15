class_name ForceLedgerPanel
extends LedgerSheet
## The crown's muster roll: every army and squadron in the Old and New World in
## one ledger, narrowed by region and kind, with a Visit action that opens the
## force's map and dossier (wiki: military-armies § The muster roll;
## DR-20261113-12). The projection lives in ForceLedger; this class only renders
## rows and asks MapPlayForceLedger to jump (REQ-P3-02, REQ-P3-03). The sheet
## chrome, fade and pause-door park come from SheetFrame; the chips, rows and
## empty notice from LedgerSheet.

## The muster roll names each squadron; the hull sheet behind this door reads
## every hull she flies (REQ-P5-01, REQ-P5-03; DR-20261115-14).
signal navy_pressed


func _init() -> void:
	title_text = "THE CROWN'S MUSTER"
	hint_text = (
		"Visit opens the force's map and dossier. The muster roll reads each "
		+ "standard and squadron as it stands; it never orders a march."
	)
	toggle_action = InputActions.MUSTER_ROLL


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both layer rosters for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = ForceLedger.snapshot(
		play.world,
		play.army_layer.regions if play.army_layer != null else null,
		play.ship_layer.regions if play.ship_layer != null else null,
		play.player_faction
	)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("crest", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Region", "Force", ForceLedger.KIND_FILTERS, _kind_word, _navy_door
	)


## The door to the crown's navy: the roll counts a squadron's hulls, the hull
## sheet reads each of them, and the press is one reach from the row that raises
## the question (REQ-P5-01, REQ-P5-03; DR-20261115-14). A full-width row keeps
## it a thumb-sized tap on a phone sheet.
func _navy_door() -> Control:
	var door := Button.new()
	door.text = "The crown's navy ›"
	door.tooltip_text = "Every hull the crown floats, squadron by squadron (N)"
	door.custom_minimum_size = Vector2(0, 34)
	door.add_theme_font_size_override("font_size", 12)
	door.pressed.connect(func() -> void: navy_pressed.emit())
	return door


# --- filters -----------------------------------------------------------------


## The reading chips: "All forces", "Armies", "Squadrons".
func _kind_word(key: String) -> String:
	if key == ForceLedger.KIND_ALL:
		return "All forces"
	return ForceLedger.kind_label(key, true).capitalize()


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = ForceLedger.groups(_snapshot, _region, _reading)
	var shown: int = ForceLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


func _empty_text() -> String:
	return "No force answers this view. Clear a filter to see the whole muster."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d force%s" % [
		String(group["region_label"]).to_upper(), count, "" if count == 1 else "s"
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := ForceLedgerRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


func _subtitle_text(shown: int) -> String:
	var counts: Dictionary = ForceLedger.kind_counts(_snapshot, _region)
	var armies: int = int(counts.get(ForceLedger.KIND_ARMY, 0))
	var squadrons: int = int(counts.get(ForceLedger.KIND_SQUADRON, 0))
	var army_word: String = ForceLedger.kind_label(ForceLedger.KIND_ARMY, armies != 1)
	var squadron_word: String = ForceLedger.kind_label(ForceLedger.KIND_SQUADRON, squadrons != 1)
	return "Showing %d of %d forces %s — %d %s, %d %s." % [
		shown,
		int(_snapshot.get("total", 0)),
		LedgerRows.scope_text(_region),
		armies,
		army_word,
		squadrons,
		squadron_word,
	]


func _visit(region: int, kind: String, id: int) -> void:
	if play == null:
		return
	if MapPlayForceLedger.focus(play, region, kind, id):
		close()
