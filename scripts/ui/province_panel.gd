class_name ProvincePanel
extends PanelContainer
## Slide-in dossier for the selected province. The frame, the title block, the
## fact grid, the estates it holds and the order rail are sections of their own,
## so no build method grows into a god method (REQ-P3-01). Every row is a fact
## the player can act on; the rules decide what an order may do (REQ-P3-02).

signal action_pressed(action: String)
signal close_pressed
signal dock_side_pressed
## The head's realm door, forwarded as the panel's own: the HUD wires one signal
## instead of searching the sheet for the head it built (REQ-P3-02).
signal realm_pressed

var _head: ProvinceSheetHead = null
## The court's own reading, asked at every refresh: the work its civilian pass
## would put crews to on this province's ground and the hosts its land pass
## would send here, or the gate that leaves the sheet with nothing to name
## (wiki: world-model § The crown's provinces; DR-20261121-19).
var counsel_source: Callable = Callable()
var _counsel: CounselLine = null
## The session the boot seats (`MapPlayProvinceHosts.seat`), read for the
## province on show: the hosts standing on its ground — the crown's own
## everywhere, another court's where the grid holds the province at `fogged` or
## better (wiki: fog-and-exploration § Order-of-battle readings;
## DR-20261123-13). The reading is this panel's own method, never a closure
## handed in from the session: a bound callable cannot outlive the session it
## reads (DR-20261121-14). A panel with no session — or one whose session has
## been freed — prints no row.
var play: PlaySession = null
var _grid: ProvinceFactsGrid = null
var _orders: ProvinceOrdersSection = null
var _resources: ProvinceResources = null
var _rail: ProvinceRailBlock = null
## The frame the sections print into: the scrolling column, the hairlines, the
## hint and the dock seal (ProvinceSheetShell; REQ-P3-01).
var _shell: ProvinceSheetShell = null
var _orders_index: int = -1

## The live tables the dossier paints from (set by MapPlaySetup, like the
## estates ledger): one opening, so a longer seat adds a named field instead of
## another loose table on the panel (ProvinceDossierOpening; REQ-P3-02).
var _opening: ProvinceDossierOpening = null
var _province_id: int = -1


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Palette.with_alpha(Palette.PARCHMENT, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(20, 18, 20, 18))
	)
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)


## The dossier re-orders itself for the viewport it is actually shown in.
func _fit_to_viewport() -> void:
	set_compact(HudLayout.is_compact(get_viewport_rect().size))


func _build() -> void:
	_shell = ProvinceSheetShell.new()
	_shell.dock_pressed.connect(func() -> void: dock_side_pressed.emit())
	add_child(_shell)

	_head = ProvinceSheetHead.new()
	_head.close_pressed.connect(func() -> void: close_pressed.emit())
	_head.realm_pressed.connect(func() -> void: realm_pressed.emit())
	_shell.add_block(_head)

	# The court's own reading sits under the head and above the facts it answers:
	# what its staff would do with this province's ground this turn (CounselLine;
	# DR-20261121-19). A dossier with no province on show asks nothing.
	_counsel = CounselLine.make(_shell.column)
	_counsel.gate = func() -> bool:
		return _opening != null and _opening.model != null and _province_id >= 0

	_grid = ProvinceFactsGrid.new()
	_shell.add_section(_grid)

	_resources = ProvinceResources.new()
	_resources.road_pressed.connect(_on_road_pressed)
	_shell.add_section(_resources)

	# The rail block sits under the estates: a railroad upgrades a road, so the
	# press that lays one belongs beside the ground it serves (DR-20261117-10).
	_rail = ProvinceRailBlock.new()
	_rail.rail_pressed.connect(_on_rail_pressed)
	_shell.add_section(_rail)

	_orders = ProvinceOrdersSection.new()
	_orders.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	_shell.add_section(_orders)
	_orders_index = _orders.get_index()

	_shell.add_hint()
	_fit_to_viewport()


## The live tables the survey rows and the town gate read (ProvinceDossierOpening;
## set by `MapPlaySetup.refresh_dossier`). The panel keeps the opening, so a turn
## that changes works or research re-renders the open dossier without the map
## layer handing it over again. The opening carries the purse the town order
## prices against and the court's sealed coasts, so a blockaded colony's estates
## read the cut the Extraction phase pays (wiki: capital-and-connectivity
## § Blockade).
func set_opening(opening: ProvinceDossierOpening) -> void:
	var same_map: bool = (
		opening != null and opening.model != null
		and _opening != null and opening.model == _opening.model
	)
	_opening = opening
	if not same_map:
		# A region switch invalidates the province id it was showing.
		_province_id = -1
		return
	if _province_id >= 0:
		refresh(opening.model, _province_id)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _shell == null:
		return
	_shell.set_dock_affordance(glyph, tip)


## A phone sheet is short, so orders move above the survey table: every action
## stays one tap away and only the details scroll. Idempotent.
func set_compact(compact: bool) -> void:
	if _orders == null or _grid == null or _shell == null:
		return
	# Recruit is a live order now, so it stays on the phone sheet too.
	var orders_at: int = _orders.get_index()
	var grid_at: int = _grid.get_index()
	if compact == (orders_at < grid_at):
		return
	_shell.column.move_child(_orders, grid_at if compact else _orders_index)


func set_training_visible(visible: bool) -> void:
	_orders.set_training_visible(visible)


## The capital rail's reading: the pick the court's own hire order answers with —
## the crew it takes next, or the gate that holds it (DR-20261121-06) — kept whole
## so the rail marks that craft's row off the same read (DR-20261122-12). Pushed
## like the army's march pick, so the sheet stays a view and the map keeps the
## reading (REQ-P3-03).
func set_hire_pick(pick: Dictionary) -> void:
	_orders.set_hire_pick(pick)


## The rail's hire reading, so a suite asserts the line rather than the label
## under it (REQ-P3-02).
func hire_line_text() -> String:
	return _orders.hire_line_text() if _orders != null else ""


## The craft the rail marks, so a suite asserts the mark (REQ-P3-02).
func hire_mark_crew() -> String:
	return _orders.hire_mark_crew() if _orders != null else ""


## Repaints the live crown rows after a road completed or a town grew, without
## re-sliding the sheet the player is reading.
func refresh_crown(crown: Dictionary) -> void:
	_grid.refresh_crown(crown)


## `crown` is `LandConnectivity.province_link` for this province: whether its
## town reaches the capital. When omitted, the roads row falls back to the
## estate survey (DossierCopy).
func refresh(model: MapModel, province_id: int, crown: Dictionary = {}) -> void:
	if _opening == null:
		# A bare panel (a suite's, or one whose boot seats it later) paints the
		# same defaults a seat with no tables always did.
		_opening = ProvinceDossierOpening.new()
	# The repaint's chart is the one on show from here on, exactly as the old
	# per-panel model field was: a later crown-link repaint reads the same chart.
	_opening.model = model
	_province_id = province_id
	var seat: ProvinceDossierOpening = _opening
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return
	_head.show_province(data)
	# The grid reads the wall's storm off the crown's own studies, so a rival's
	# wall prints the published envelope (DR-20261123-20).
	_grid.show_province(model, province_id, data, seat.faction, seat.tech_unlocked)
	_grid.set_hosts(_hosts_line(model, province_id))
	# The harbour reads off the same seated session; the module answers "" for a
	# sheet the boot never seated (DR-20261123-14).
	_grid.set_harbour(MapPlayProvinceHarbour.line(play, model, province_id))
	var rows: Array[Dictionary] = ResourceSurvey.province_rows(
		model, seat.works, seat.units, seat.faction, province_id, seat.visibility,
		seat.capital_tile, seat.tech_caps, seat.blockade
	)
	var unsurveyed: int = MineralSurvey.unsurveyed_in_province(
		model, seat.works, seat.faction, province_id, seat.visibility
	).size()
	_resources.render(
		rows, unsurveyed, _road_plans(model, rows),
		MapPlayProvinceHarvest.line(play, model, province_id)
	)
	_rail.render(RailWorks.province_plans(
		model, seat.works, seat.units, seat.faction, province_id, seat.tech_unlocked
	))
	_grid.set_estate_roads(data, rows, crown)
	_orders.set_town_order(data, seat.faction, seat.tech_unlocked, seat.stockpile)
	_orders.set_wall_order(
		model, data, seat.faction, seat.units, seat.tech_unlocked, seat.stockpile
	)
	_orders.set_ward_order(
		model, data, seat.faction, seat.units, seat.tech_unlocked, seat.stockpile
	)
	_orders.set_training(seat.tech_unlocked)
	_orders.set_shipyard_visible(
		data.owner == seat.faction and data.capital and data.port_tile.x >= 0
	)
	_sync_counsel()


## The gold counsel line: what the court's staff would do with this province's
## ground this turn, or nothing when neither pass names the ground. A closed
## sheet reads nothing, because the pass is a planner walk no one is looking at
## (REQ-P4-02; CounselLine). The rail's marks come off the same reading, so the
## sentence and the presses cannot disagree (DR-20261122-23).
func _sync_counsel() -> void:
	if _counsel == null:
		return
	_counsel.source = counsel_source
	var model: MapModel = _opening.model if _opening != null else null
	_counsel.args = [model, _province_id]
	_counsel.sync()
	if _orders != null:
		_orders.set_court_marks(_counsel.keys())


## The counsel line's text, for tests and tooling (REQ-P3-02). Empty when the
## sheet carries no reading.
func counsel_text() -> String:
	return "" if _counsel == null else _counsel.text


## The Hosts row's text for the province on show, for tests and tooling
## (REQ-P3-02). Empty when no host stands there or the boot bound no reading.
func hosts_text() -> String:
	return "" if _grid == null or not _grid.hosts.visible else _grid.hosts.text


## The Hosts row's one reading, asked of the seated session with this chart and
## province. An unseated sheet (a test's bare panel) prints no row, and a session
## freed beneath the panel prints none either rather than reading a corpse.
func _hosts_line(model: MapModel, province_id: int) -> String:
	if play == null or not is_instance_valid(play):
		return ""
	return MapPlayProvinceHosts.line(play, model, province_id)


## The Squadrons row's text for the province on show, for tests and tooling
## (REQ-P3-02). Empty when no squadron rides its harbour or the boot bound no
## reading.
func harbour_text() -> String:
	return "" if _grid == null or not _grid.harbour.visible else _grid.harbour.text


## The rail's marks: the presses the court's own crew pass would file on this
## ground, read off the counsel line's own pick so the line and the marks come
## off one read (DR-20261122-23). Exposed so a suite asserts the marks instead of
## reading button captions (REQ-P3-02).
func court_marks() -> Dictionary:
	return {} if _orders == null else _orders.court_marks()


## One rail press's caption as the sheet prints it — marked or plain (REQ-P3-02).
func press_text(key: String) -> String:
	return "" if _orders == null else _orders.press_text(key)


## The Build road control's reading, one plan per estate RoadWorks would road:
## the crown network is resolved once for the whole province, so a dossier of
## five estates costs one BFS (REQ-P4-01).
func _road_plans(model: MapModel, rows: Array[Dictionary]) -> Dictionary:
	var seat: ProvinceDossierOpening = _opening
	return RoadWorks.province_plans(
		model, seat.works, seat.units, seat.faction, seat.capital_tile, rows
	)


## The estate block's Build road: the order travels as one intent string, the
## same way the order rail's own actions do (REQ-P3-02).
func _on_road_pressed(tile: Vector2i) -> void:
	action_pressed.emit("road:%d,%d" % [tile.x, tile.y])


## The rail block's Lay railroad: the same one intent string, so the crew the
## map dispatches and the tile the block names can never drift apart.
func _on_rail_pressed(tile: Vector2i) -> void:
	action_pressed.emit("rail:%d,%d" % [tile.x, tile.y])
