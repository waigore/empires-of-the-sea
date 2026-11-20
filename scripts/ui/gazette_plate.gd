class_name GazettePlate
extends ModalShell
## The crown's news sheet on the map: the turn-start plate, the history screen
## and the watchlist editor on one surface (wiki: the-gazette; DR-20261110-14).
## Its door is the cartouche's GAZETTE seal, and it opens as the one full-screen
## modal every bar door uses: the crown's news is read, not skimmed beside the
## chart (REQ-P1-05, REQ-P1-07, REQ-P5-06, REQ-P5-07).
## Presentation only — it prints the lines [Gazette] already built (REQ-P2-03).

signal dismissed
## The player added or removed a court on the watchlist.
signal watch_changed(faction: int)

enum Mode { SHEET, ARCHIVE, WATCHLIST, AGE }

const EMPTY_LINE: String = GazetteParts.EMPTY_LINE
const NO_HISTORY: String = GazetteArchiveRoom.NO_HISTORY
const INK_SOFT: Color = Color(0.34, 0.26, 0.16)

var state: GazetteState = null
var diplomacy: DiplomacyState = null
var viewer: int = 0
## The age's race at the live sheet's foot (wiki: victory § Victory Check).
var _age: String = ""
## The whole race, for the age's own tab: `rows`, `human`, `calendar`, `note`
## (see MapPlayGazette.age_payload). Empty when the session has no crown.
var _age_data: Dictionary = {}

var _mode: Mode = Mode.SHEET
var _sheet: Dictionary = {}
## The archive's page and its reading filter — every class, or one class alone
## (wiki: the-gazette § History screen; DR-20261115-06).
var _archive_room: GazetteArchiveRoom = null

var _title: Label = null
var _stamp: Label = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _tabs: HBoxContainer = null
var _nav: HBoxContainer = null
var _watchlist: GazetteWatchlist = null
var _age_room: AgeRoom = null
var _newer: Button = null
var _older: Button = null
var _nav_label: Label = null
var _header_row: HBoxContainer = null


## Raises the sheet the turn just produced; `age_line` is its standing column and
## `age` the whole race its own tab prints (MapPlayGazette.age_payload).
func open_sheet(
	sheet: Dictionary, p_state: GazetteState, p_diplomacy: DiplomacyState, who: int,
	age_line: String = "", age: Dictionary = {}
) -> void:
	state = p_state
	diplomacy = p_diplomacy
	viewer = who
	_sheet = sheet
	_age = age_line
	_age_data = age
	_mode = Mode.SHEET
	open()


## Raises the history screen with the live sheet one tab back: that tab keeps
## the standing the turn-start open prints; a past sheet stays bare (DR-20261112-05).
func open_archive(
	p_state: GazetteState, p_diplomacy: DiplomacyState, who: int, age_line: String = "",
	age: Dictionary = {}
) -> void:
	state = p_state
	diplomacy = p_diplomacy
	viewer = who
	if _archive_room != null:
		_archive_room.at = 0
	_sheet = p_state.newest() if p_state != null else {}
	_age = age_line
	_age_data = age
	_mode = Mode.ARCHIVE
	open()


## Raises the watchlist editor on its own (reachable from the cartouche seal).
func open_watchlist(p_state: GazetteState, p_diplomacy: DiplomacyState, who: int) -> void:
	state = p_state
	diplomacy = p_diplomacy
	viewer = who
	_mode = Mode.WATCHLIST
	open()


func is_shown() -> bool:
	return is_open()


## One press sets the sheet aside; a full-screen door closes cleanly with it.
func dismiss() -> void:
	close()


## A door that closes without its Close door still raises the court's news back.
func close() -> void:
	if not is_open():
		return
	super.close()
	dismissed.emit()


## Repaints after the watchlist changed underneath, and on every open.
func refresh() -> void:
	_render()


# --- shell hooks -------------------------------------------------------------


## Printed paper inside a brass rule, lifted off the chart by its own shadow, so
## the sheet reads as the crown's broadsheet rather than another dossier
## (REQ-P1-02).
func _dress_plate(_compact_now: bool) -> void:
	var style := UiTheme.box(Palette.PAPER, Palette.GOLD_DIM, 2, 2, Vector4(20, 14, 20, 14))
	style.shadow_color = Color(0.05, 0.04, 0.03, 0.55)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	_panel.add_theme_stylebox_override("panel", style)


func _build_plate(host: VBoxContainer) -> void:
	host.add_child(_header())
	# Double rule under the masthead, the way a printed gazette divides its flag
	# from the field (REQ-P1-02).
	host.add_child(GazetteParts.rule(Palette.INK_LINE))
	host.add_child(GazetteParts.rule(Palette.GOLD, 2))
	_tabs = _tabs_row()
	host.add_child(_tabs)
	_nav = _nav_row()
	host.add_child(_nav)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	_scroll.add_child(_body)
	# The watchlist editor lives in the body but survives a repaint, so its own
	# rows are the only thing a mode change rebuilds.
	_watchlist = GazetteWatchlist.new()
	_watchlist.visible = false
	_watchlist.watch_changed.connect(func(faction: int) -> void: watch_changed.emit(faction))
	_body.add_child(_watchlist)
	# The age's own tab: the whole race, printed from the same read the check
	# acts on (wiki: victory § Victory Check; DR-20261115-05).
	_age_room = AgeRoom.new()
	_age_room.visible = false
	_body.add_child(_age_room)
	# The archive's page: the filed sheets, the reading filter and the walk
	# through them (wiki: the-gazette § History screen; DR-20261115-06).
	_archive_room = GazetteArchiveRoom.new()
	_archive_room.visible = false
	# A chip press re-reads the page; the plate's stamp and walk follow it.
	_archive_room.filter_changed.connect(func(_cls: int) -> void: _render())
	_body.add_child(_archive_room)


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_header_row = row
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	_title = GazetteParts.label("THE GAZETTE", 26, Palette.INK)
	column.add_child(_title)
	_stamp = GazetteParts.label("", 12, INK_SOFT, true)
	column.add_child(_stamp)
	row.add_child(column)
	var close_door := CloseSeal.make("Close the sheet")
	close_door.pressed.connect(dismiss)
	row.add_child(close_door)
	return row


func _tabs_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for entry: Array in [
		[Mode.SHEET, "The sheet"], [Mode.ARCHIVE, "History"], [Mode.WATCHLIST, "Watchlist"],
		[Mode.AGE, "The age"]
	]:
		var button := Button.new()
		button.text = String(entry[1])
		button.set_meta("mode", int(entry[0]))
		button.pressed.connect(_go.bind(int(entry[0])))
		row.add_child(button)
	return row


func _nav_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_newer = Button.new()
	_newer.text = "◀  Newer"
	_newer.pressed.connect(_step.bind(-1))
	row.add_child(_newer)
	_nav_label = GazetteParts.label("", 13, INK_SOFT)
	_nav_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_nav_label)
	_older = Button.new()
	_older.text = "Older  ▶"
	_older.pressed.connect(_step.bind(1))
	row.add_child(_older)
	return row


# --- render ------------------------------------------------------------------


func _go(mode: int) -> void:
	_mode = mode
	if _mode == Mode.ARCHIVE:
		if _archive_room != null:
			_archive_room.at = 0
	_render()


func _step(delta: int) -> void:
	if _archive_room == null:
		return
	_archive_room.step(delta)
	_render()


func _render() -> void:
	for child: Node in _body.get_children():
		if child == _watchlist or child == _age_room or child == _archive_room:
			continue
		_body.remove_child(child)
		child.queue_free()
	_watchlist.visible = _mode == Mode.WATCHLIST
	_age_room.visible = _mode == Mode.AGE
	_archive_room.visible = _mode == Mode.ARCHIVE
	for child: Node in _tabs.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		var mode: int = int(button.get_meta("mode", Mode.SHEET))
		var current: bool = mode == int(_mode)
		button.add_theme_color_override("font_color", Palette.INK if current else INK_SOFT)
		button.add_theme_stylebox_override(
			"normal",
			UiTheme.box(
				Color(0.86, 0.80, 0.66, 1.0) if current else Color(0, 0, 0, 0),
				Palette.GOLD_DIM if current else Color(0, 0, 0, 0),
				1,
				2,
				Vector4(10, 4, 10, 4)
			)
		)
	_nav.visible = _mode == Mode.ARCHIVE
	match _mode:
		Mode.SHEET:
			_title.text = "THE GAZETTE"
			_stamp.text = DiplomacyHistory.stamp_for_turn(int(_sheet.get("turn", 0)))
			GazetteParts.sections(_body, _sheet)
			if not _age.is_empty():
				_body.add_child(GazetteParts.spacer(8))
				_body.add_child(GazetteParts.rule(Palette.INK_FAINT))
				_body.add_child(GazetteParts.label("THE STATE OF THE AGE", 11, INK_SOFT))
				_body.add_child(GazetteParts.label(_age, 14, Palette.INK))
		Mode.ARCHIVE:
			_render_archive()
		Mode.WATCHLIST:
			_render_watchlist()
		Mode.AGE:
			_render_age()


func _render_archive() -> void:
	_title.text = "THE GAZETTE  ·  ARCHIVE"
	_archive_room.fill(state, _archive_room.filter)
	_stamp.text = _archive_room.stamp()
	_nav_label.text = _archive_room.position_text()
	_newer.disabled = _archive_room.at_newest()
	_older.disabled = _archive_room.at_oldest()


## The whole race on its own tab: the foot's one line is the live sheet's
## standing; this prints every crown against its own bar (DR-20261115-05).
func _render_age() -> void:
	_title.text = "THE GAZETTE  ·  THE AGE"
	_stamp.text = "The Old World against every crown's bar"
	_age_room.fill(_age_data)


func _render_watchlist() -> void:
	_title.text = "THE GAZETTE  ·  WATCHLIST"
	_stamp.text = "Courts whose doings are reported"
	_watchlist.fill(state, diplomacy, viewer)
