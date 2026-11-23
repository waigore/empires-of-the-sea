extends RefCounted
## The yards half of the counsel step: the three yards — the drill yard in the Home
## Army's own dossier, the capital slip's hull, and the capital rail's crew and
## work presses. Each marks the one row its gold line names, off the same pick
## the line is worded from, and a yard that names nothing marks nothing; no yard
## raises a regiment or spends a coin.
##
## The sheets on the bar's ledgers are their own halves
## (smoke_counsel_ledger.gd, smoke_counsel_sheets.gd), and all of them read one
## tally (smoke_counsel_reads.gd).
##
## No `class_name`: the counsel step (tools/smoke/smoke_counsel.gd) preloads
## this file.

const SmokeReads = preload("res://tools/smoke/smoke_counsel_reads.gd")


static func step(run, screen: MapScreen) -> void:
	await _yards(run, screen)


## The yards mark the one row their gold line names: the drill yard's pattern, the
## slip's hull and the capital rail's crew, each off the same pick the line is
## worded from, and a yard that names nothing marks nothing (wiki:
## military-armies § Home Army, ships-and-naval § Ship build economy,
## civilian-units § Training; DR-20261122-12).
static func _yards(run, screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var before: Dictionary = {
		"regiments": play.army_layer.regiment_count_all(play.player_faction),
		"treasury": play.economy.economy.treasury,
	}
	# The drill yard, in the Home Army's own dossier (DR-20261121-03).
	MapPlayArmies.open_muster(play)
	await run.tree.process_frame
	var army_panel: ArmyPanel = screen.hud.panels.army_panel
	var yard: ArmyMusterBlock = army_panel._muster_box if army_panel != null else null
	run.check(yard != null, "the drill yard stands in the Home Army's dossier")
	if yard != null:
		_drill_yard(run, play, yard)
	# The capital slip, from the door the province dossier opens (DR-20261121-02).
	MapPlayFleetYard.open(play)
	await run.tree.process_frame
	var fleet_panel: FleetPanel = screen.hud.panels.fleet_panel
	var slip: FleetYardBlock = fleet_panel._yard if fleet_panel != null else null
	run.check(slip != null, "the slip stands in the capital's dossier")
	if slip != null:
		_slip(run, play, slip)
	# The capital rail's craft rows (DR-20261121-06).
	var seat: int = int(MapPlayCourtHoldings.crown_seat(play).get("province", -1))
	run.check(seat >= 0, "the crown keeps a seat to hire at")
	if seat >= 0:
		await _rail(run, screen, play, seat)
	run.check(
		play.army_layer.regiment_count_all(play.player_faction)
		== int(before["regiments"]),
		"the yards' readings raise no regiment"
	)
	run.check(
		play.economy.economy.treasury == int(before["treasury"]),
		"the yards' readings spend nothing"
	)


## The drill yard prints the court's own muster, marks the pattern its line names
## and says what the mark means under the line (DR-20261121-03, DR-20261123-08).
static func _drill_yard(run, play: PlaySession, yard: ArmyMusterBlock) -> void:
	var home: ArmyState = ArmyTraining.home_army(
		play.army_layer.armies, play.player_faction
	)
	var muster: Dictionary = MapPlayMusterPick.pick(play, home)
	run.check(
		yard.pick_line() == MapPlayPickProse.sentence_of(muster),
		"the drill yard prints the court's own muster"
	)
	run.check(
		yard.mark_type() == String(muster.get("type", "")),
		"the drill yard marks the pattern its line names"
	)
	run.check(
		SmokeReads.marked_yard_rows(yard, ArmyMusterBlock.COURT_MARK)
		== (1 if not yard.mark_type().is_empty() else 0),
		"and paints the mark on that pattern's row alone"
	)
	# The yard keeps no footer: the sentence that says what the mark means
	# stands directly under the line (DR-20261123-08).
	run.check(
		yard.legend_text() == ArmyMusterBlock.MARK_LEGEND,
		"the drill yard names its mark"
	)
	run.check(
		yard.legend_shown() == not yard.mark_type().is_empty(),
		"and its legend stands with the mark it explains"
	)


## The slip prints the court's own claim, marks the hull its line names and says
## what the mark means under the line (DR-20261121-02, DR-20261123-08).
static func _slip(run, play: PlaySession, slip: FleetYardBlock) -> void:
	var laid: Dictionary = MapPlayYardPick.pick(play)
	run.check(
		slip.pick_line() == MapPlayPickProse.sentence_of(laid),
		"the slip prints the court's own claim"
	)
	run.check(
		slip.mark_type() == String(laid.get("type", "")),
		"the slip marks the hull its line names"
	)
	run.check(
		slip.legend_text() == FleetYardBlock.MARK_LEGEND,
		"the slip names its mark"
	)
	run.check(
		slip.legend_shown() == not slip.mark_type().is_empty(),
		"and its legend stands with the mark it explains"
	)


## The capital rail's craft row and work presses, each marked off its own pick
## (DR-20261121-06, DR-20261122-23).
static func _rail(run, screen: MapScreen, play: PlaySession, seat: int) -> void:
	MapPlayInput.select_province(
		play, seat, screen.model.province_center(seat) * MapScreen.TILE_SIZE
	)
	await run.tree.process_frame
	var sheet: ProvincePanel = screen.hud.panels.panel
	run.check(sheet != null, "the capital's sheet opens")
	if sheet == null:
		return
	var hire: Dictionary = MapPlayHirePick.pick(play)
	var crew: String = String(hire.get("crew", ""))
	run.check(
		sheet.hire_line_text() == String(hire.get("line", "")),
		"the rail prints the court's own hire"
	)
	run.check(
		sheet.hire_mark_crew() == crew,
		"the rail marks the craft its line names"
	)
	if not crew.is_empty():
		var row: Dictionary = sheet._orders.training_row(crew)
		run.check(
			String((row.get("button", null) as Button).text).begins_with(
				ProvinceOrdersSection.COURT_MARK
			),
			"and paints the mark on that craft's row"
		)
	# The rail's work presses wear the same read (DR-20261122-23).
	var rail_pick: Dictionary = MapPlayProvinceCounsel.pick(play, screen.model, seat)
	run.check(
		sheet.court_marks() == rail_pick.get("keys", {}),
		"the rail marks the presses the court would file"
	)
	for key: String in sheet.court_marks().keys():
		run.check(
			sheet.press_text(key).begins_with(ProvinceOrdersSection.COURT_MARK),
			"and paints the mark on the press it names: %s" % key
		)
