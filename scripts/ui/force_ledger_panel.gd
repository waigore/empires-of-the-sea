class_name ForceLedgerPanel
extends SheetFrame
## The crown's muster roll: every army and squadron in the Old and New World in
## one ledger, narrowed by region and kind, with a Visit action that opens the
## force's map and dossier (wiki: military-armies § The muster roll;
## DR-20261113-12). The projection lives in ForceLedger; this class only renders
## rows and asks MapPlayForceLedger to jump (REQ-P3-02, REQ-P3-03). The sheet
## chrome, fade and pause-door park come from SheetFrame.

## The muster roll names each squadron; the hull sheet behind this door reads
## every hull she flies (REQ-P5-01, REQ-P5-03; DR-20261115-14).
signal navy_pressed

var _rows: VBoxContainer = null
var _empty: Label = null
var _bar: LedgerFilterBar = null
var _region: String = ForceLedger.REGION_ALL
var _kind: String = ForceLedger.KIND_ALL
var _snapshot: Dictionary = {}


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
	_bar = LedgerFilterBar.new()
	_bar.fill("Region", "Force", ForceLedger.REGION_FILTERS, ForceLedger.KIND_FILTERS, _kind_word)
	_bar.chosen.connect(_on_filter)
	column.add_child(_bar)
	column.add_child(_navy_door())

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


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


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- filters -----------------------------------------------------------------


## The reading chips: "All forces", "Armies", "Squadrons".
func _kind_word(key: String) -> String:
	if key == ForceLedger.KIND_ALL:
		return "All forces"
	return ForceLedger.kind_label(key, true).capitalize()


func _on_filter(key: String, region_row: bool) -> void:
	if region_row:
		_region = key
	else:
		_kind = key
	refresh()


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	_bar.render(_region, _kind)
	var groups: Array[Dictionary] = ForceLedger.groups(_snapshot, _region, _kind)
	var shown: int = ForceLedger.count(_snapshot, _region, _kind)
	_subtitle.text = _subtitle_text(shown)
	_empty.visible = shown == 0
	if shown == 0:
		_empty.text = "No force answers this view. Clear a filter to see the whole muster."
		return
	LedgerList.fill(_rows, _empty, groups, _heading, _make_row)


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
	var scope: String = "in both charts"
	if _region == ForceLedger.REGION_OLD:
		scope = "in the Old World"
	elif _region == ForceLedger.REGION_NEW:
		scope = "in the New World"
	var counts: Dictionary = ForceLedger.kind_counts(_snapshot, _region)
	var armies: int = int(counts.get(ForceLedger.KIND_ARMY, 0))
	var squadrons: int = int(counts.get(ForceLedger.KIND_SQUADRON, 0))
	var army_word: String = ForceLedger.kind_label(ForceLedger.KIND_ARMY, armies != 1)
	var squadron_word: String = ForceLedger.kind_label(ForceLedger.KIND_SQUADRON, squadrons != 1)
	return "Showing %d of %d forces %s — %d %s, %d %s." % [
		shown, int(_snapshot.get("total", 0)), scope, armies, army_word, squadrons, squadron_word,
	]


func _visit(region: int, kind: String, id: int) -> void:
	if play == null:
		return
	if MapPlayForceLedger.focus(play, region, kind, id):
		close()
