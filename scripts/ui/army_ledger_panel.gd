class_name ArmyLedgerPanel
extends LedgerSheet
## The crown's army: every regiment the crown fields in both charts, read
## standard by standard — its class, its stat line, the condition it holds and
## the colours it wears (wiki: military-armies § The regiments behind an army;
## DR-20261116-16). The projection lives in [ArmyLedger]; this sheet only renders
## headings and rows and asks MapPlayForceLedger to jump to a regiment's standard
## (REQ-P3-02, REQ-P3-03). The sheet chrome, fade and pause-door park come from
## SheetFrame; the chips, rows and empty notice from LedgerSheet.


func _init() -> void:
	title_text = "THE CROWN'S ARMY"
	hint_text = (
		"Visit opens the standard's chart and dossier. The sheet reads every "
		+ "regiment as it stands; it never musters, detaches or dismisses one."
	)


## Re-reads both charts' army rosters for the player's crown and repaints.
func refresh() -> void:
	if play == null or play.world == null or play.army_layer == null:
		return
	_snapshot = ArmyLedger.snapshot(
		play.world,
		play.army_layer.regions,
		play.ship_layer.regions if play.ship_layer != null else null,
		play.player_faction
	)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("crest", 42.0, Palette.GOLD)


func _can_open() -> bool:
	return super._can_open() and play.army_layer != null


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Chart", "Regiment", ArmyLedger.READINGS, ArmyLedger.reading_label, _regiment_note
	)


## The rule a crown fields men by sits on the sheet, not in a hover: a phone
## hides the footer hint (REQ-P1-07, REQ-P5-03).
func _regiment_note() -> Control:
	var note := UiRowBuilder.label(ArmyLedger.note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = ArmyLedger.groups(_snapshot, _region, _reading)
	var shown: int = ArmyLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


## The count line the army prints: the view against the chart it is read in,
## with the army's own totals when every regiment is shown (REQ-P5-05).
func _subtitle_text(_shown: int) -> String:
	return ArmyLedger.summary(_snapshot, _region, _reading)


## One standard's heading: where it stands and what it is doing, then the
## regiments it flies. A regiment's orders are its standard's, so they read once.
func _heading(group: Dictionary, count: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var title := Label.new()
	title.text = "%s  ·  %d regiment%s" % [
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
	return "%s  ·  %s  ·  %.1f strength  ·  %d food" % [
		String(group["place"]),
		String(group["standing"]),
		float(group["strength"]),
		int(group["food"]),
	]


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := ArmyLedgerRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


## The explanation a filter that empties the sheet earns: the crown may field no
## regiment yet, the filter may be hiding them, or the chart may hold none at all
## (REQ-P5-05).
func _empty_text() -> String:
	if int(_snapshot.get("total", 0)) == 0:
		var armies: int = ArmyLedger.army_count(_snapshot, _region)
		if armies > 0:
			return (
				"No regiment musters in %s — the drill yard raises the first, "
				+ "and every regiment it raises is read here."
			) % ArmyLedger.scope_text(_region)
		return "No standard answers this chart. Clear a filter to see the whole army."
	return "No regiment answers this view. Clear a filter to see the whole army."


## Visit frames the standard that flies the colours and opens its dossier: a
## regiment has no marker of its own, so the standard is what the map can show.
func _visit(region: int, army_id: int) -> void:
	if play == null:
		return
	if MapPlayForceLedger.focus(play, region, ForceLedger.KIND_ARMY, army_id):
		close()
