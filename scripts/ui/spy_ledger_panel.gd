class_name SpyLedgerPanel
extends SheetFrame
## The crown's eyes: the intelligence council's one reading (wiki:
## civilian-units § Spy; DR-20261115-10). Every spy the crown holds and what it
## earns where it stands, every Great Power shadowed or not, and whether the
## counter-espionage screen is up. The projection lives in SpyLedger; this sheet
## only renders rows and asks MapPlayCivilianRoster to jump (REQ-P3-02,
## REQ-P3-03). The sheet chrome, fade and pause-door park come from SheetFrame.

var _rows: VBoxContainer = null


func _init() -> void:
	title_text = "THE CROWN'S EYES"
	hint_text = (
		"Visit opens the spy's map and dossier. The sheet reads the network as "
		+ "it stands and names the spies the court would book; it never moves a "
		+ "spy or sets an order."
	)
	toggle_action = InputActions.SPY_LEDGER


## Re-reads both charts' civilian rosters for the player's crown and repaints.
func refresh() -> void:
	if play == null or play.world == null or play.civilian_layer == null:
		return
	_snapshot = SpyLedger.snapshot(
		play.world, play.civilian_layer.regions, play.player_faction
	)
	_fit()
	_paint()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	var art: Texture2D = CivilianArt.medallion(SpyRules.TYPE)
	if art == null:
		return Icon.new("crest", 42.0, Palette.GOLD)
	var crest := TextureRect.new()
	crest.texture = art
	crest.custom_minimum_size = Vector2(42, 42)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return crest


func _can_open() -> bool:
	return super._can_open() and play.civilian_layer != null


func _build_body(column: VBoxContainer) -> void:
	# The gold counsel line above the network: the spies the court would book.
	_counsel_line(column)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_paint()


# --- body --------------------------------------------------------------------


func _paint() -> void:
	UiRowBuilder.clear(_rows)
	_subtitle.text = SpyLedger.summary(_snapshot)
	_sync_counsel()
	_network()
	_courts()
	_screen()


## The crown's spies, one row each: where it stands and what it earns there.
func _network() -> void:
	var rows: Array = _snapshot.get("rows", [])
	_heading("THE NETWORK", SpyLedger.count_text(rows.size()))
	if rows.is_empty():
		_rows.add_child(UiRowBuilder.wrapped_line(
			"No spy answers the crown. Train one at the capital — 2,000 ducats and "
			+ "4 paper — and post it on a rival's land.",
			13,
			Palette.TEXT_DIM
		))
		return
	for raw: Variant in rows:
		_rows.add_child(_spy_row(raw as Dictionary))


## Every Great Power but the reader's own: the shadowed and the open alike, so
## the gap is as legible as the gain (REQ-P5-03).
func _courts() -> void:
	var courts: Array = _snapshot.get("courts", [])
	_heading("THE COURTS", "%d of %d shadowed" % [
		courts.size() - int(_snapshot.get("unobserved", 0)), courts.size()
	])
	for raw: Variant in courts:
		_rows.add_child(_court_row(raw as Dictionary))
	_rows.add_child(UiRowBuilder.wrapped_line(
		SpyLedger.courts_note(_snapshot), 12, Palette.TEXT_DIM
	))


func _screen() -> void:
	_heading("THE SCREEN", SpyLedger.screen_word(_snapshot))
	var line := UiRowBuilder.wrapped_line(
		SpyLedger.screen_text(_snapshot), 13,
		Palette.GOLD_PALE if bool(_snapshot.get("screened", false)) else Palette.TEXT
	)
	_rows.add_child(line)
	_rows.add_child(UiRowBuilder.wrapped_line(
		SpyLedger.boost_note(), 12, Palette.TEXT_DIM
	))


func _heading(caption: String, tally: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := UiRowBuilder.caption(caption, 11, Palette.GOLD_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(UiRowBuilder.label(tally, 11, Palette.TEXT_DIM))
	_rows.add_child(row)


# --- rows --------------------------------------------------------------------


func _spy_row(row: Dictionary) -> Control:
	var widget := SpyLedgerRow.new()
	widget.compact = LedgerList.is_compact(_rows)
	widget.visit_pressed.connect(_visit)
	widget.setup(row)
	return widget


func _court_row(court: Dictionary) -> Control:
	var shadowed: bool = bool(court.get("shadowed", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := UiRowBuilder.label(
		String(court.get("name", "")), 13,
		Palette.GOLD_PALE if shadowed else Palette.TEXT
	)
	name_label.custom_minimum_size = Vector2(96, 0)
	row.add_child(name_label)
	row.add_child(UiRowBuilder.wrapped_line(
		String(court.get("line", "")), 12,
		Palette.TEXT if shadowed else Palette.TEXT_DIM
	))
	return row


func _visit(region: int, unit_id: int) -> void:
	if play == null:
		return
	if MapPlayCivilianRoster.focus(play, region, unit_id):
		close()
