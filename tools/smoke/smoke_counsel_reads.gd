extends RefCounted
## The tallies behind the counsel step: what each reading must leave exactly as
## it found it, and how many rows wear the counsel's mark. One home for both so
## the two halves of the step — the sheets (smoke_counsel.gd) and the yards
## (smoke_counsel_yards.gd) — read the same tally instead of each keeping a copy.
##
## No `class_name`: the counsel steps preload this file.


## Every spy in both charts as the order it holds and the ground it stands on:
## what the eyes' reading must leave exactly as it found it (DR-20261122-18).
static func spy_orders(screen: MapScreen) -> Array:
	var found: Array = []
	var play: PlaySession = screen.play
	for region: int in play.world.region_count():
		for raw: Variant in MapPlaySpyAi.roster_for(play, region):
			var unit := raw as CivilianState
			if unit == null or not SpyRules.is_spy(unit):
				continue
			found.append([region, unit.id, unit.work_action(), unit.tile])
	return found


## Every squadron's station and move flag, so a reading that sailed one shows.
static func fleet_orders(screen: MapScreen) -> Array:
	var seen: Array = []
	for region: int in screen.play.ship_layer.regions.region_ids():
		for fleet: FleetState in MapPlayCourtRoster.region_fleets(screen.play, region):
			if fleet == null:
				continue
			seen.append("%d:%s:%s" % [fleet.id, fleet.mission, fleet.moved])
	seen.sort()
	return seen


## Every Tribe's overture stage with the crown, so a reading that signed one
## shows.
static func colony_overtures(screen: MapScreen) -> Array:
	var seen: Array = []
	for tribe: int in FactionCatalog.tribe_ids():
		seen.append(screen.play.diplomacy.overture(screen.play.player_faction, tribe))
	return seen


## Every standard's place and move flag, so a reading that marched one shows.
static func army_orders(screen: MapScreen) -> Array:
	var seen: Array = []
	for region: int in screen.play.army_layer.regions.region_ids():
		for army: ArmyState in MapPlayCourtRoster.visible_armies(screen.play, region):
			if army == null:
				continue
			seen.append("%d:%d:%s" % [army.id, army.province, army.moved])
	seen.sort()
	return seen


## How many of the crown's crews hold a running order: the tally a reading may
## not move.
static func working_crews(screen: MapScreen) -> int:
	var working: int = 0
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit != null and unit.owner == screen.play.player_faction and unit.is_working():
			working += 1
	return working


## The network rows wearing the counsel's mark.
static func marked_spies(panel: SpyLedgerPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as SpyLedgerRow
		if row != null and row.court:
			marked += 1
	return marked


## The drill-yard rows wearing the counsel's mark.
static func marked_yard_rows(block: ArmyMusterBlock, mark: String) -> int:
	var seen: int = 0
	for child: Node in block.get_children():
		if not (child is VBoxContainer) or child.is_queued_for_deletion():
			continue
		var top := (child as VBoxContainer).get_child(0) as HBoxContainer
		if top == null or top.get_child_count() < 2:
			continue
		if String((top.get_child(1) as Label).text).begins_with(mark):
			seen += 1
	return seen


## How many realm rows wear the counsel's mark: the ground the court would act
## in, as the sheet prints it.
static func marked_rows(panel: ProvinceLedgerPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as ProvinceLedgerRow
		if row != null and row.court:
			marked += 1
	return marked


## How many estate rows wear the counsel's mark, so the smoke can hold the count
## to the reading's own keys (DR-20261122-04).
static func marked_estates(panel: ImprovementPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as ImprovementRow
		if row != null and row.court:
			marked += 1
	return marked


## How many roster rows wear the counsel's mark, so the smoke can hold the count
## to the reading's own keys (DR-20261122-06).
static func marked_crews(panel: CivilianRosterPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as CivilianRosterRow
		if row != null and row.court:
			marked += 1
	return marked


## How many muster rows wear the court's mark, so the smoke can hold the count to
## the reading's own keys (DR-20261122-03).
static func marked_forces(panel: ForceLedgerPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as ForceLedgerRow
		if row != null and row.court:
			marked += 1
	return marked


## How many standard or squadron headings wear the counsel's mark, so the smoke
## can hold the marks painted to the headings the reading names
## (DR-20261122-05).
static func marked_headings(rows: VBoxContainer) -> int:
	var marked: int = 0
	for child: Node in rows.get_children():
		var box := child as VBoxContainer
		if box == null or box.get_child_count() == 0:
			continue
		var label := box.get_child(0) as Label
		if label != null and label.text.begins_with(ForceLedgerRow.COURT_MARK):
			marked += 1
	return marked


## How many market rows wear the counsel's mark, so the smoke can hold the count
## to the reading's own book (DR-20261122-08).
static func marked_goods(page: LedgerMarket) -> int:
	var marked: int = 0
	var prefix: String = MarketRow.COURT_MARK + " "
	for label: Label in page.find_children("*", "Label", true, false):
		if label.text.begins_with(prefix):
			marked += 1
	return marked


## How many workshop rows wear the counsel's mark, so the smoke can hold the
## count to the reading's own runs (DR-20261122-10). The heading's legend wears
## the same glyph and is not a row.
static func marked_recipes(page: LedgerProduction) -> int:
	var marked: int = 0
	var prefix: String = LedgerProduction.COURT_MARK + " "
	for label: Label in page.find_children("*", "Label", true, false):
		if label.text == LedgerProduction.COURT_LEGEND:
			continue
		if label.text.begins_with(prefix):
			marked += 1
	return marked


## Whether a sheet prints one line of exactly this text: the legend under a
## section's heading, which nothing else on the page reads.
static func printed(page: Node, text: String) -> bool:
	for label: Label in page.find_children("*", "Label", true, false):
		if label.text == text:
			return true
	return false
