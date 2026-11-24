class_name SpyLedger
extends RefCounted
## The crown's eyes: every spy it holds, the courts those spies shadow and
## whether the counter-espionage screen is up (wiki: civilian-units § Spy
## (1)–(5); DR-20261115-10).
##
## A pure projection over the two charts' civilian rosters. It never moves a
## spy, assigns an order or rolls a die, and every reading is the rules' own
## predicate (`SpyRules.is_foreign`, `SpyRules.screened_owners`,
## `SpyNetworks.qualifying_rivals`), so the sheet cannot name a shadow the
## Research phase would not pay for (REQ-P2-03, REQ-P3-03).
##
## A spy's duty is what the crown gets from it where it stands:
##   shadow — on a rival Great Power's land: +15% research and her court reports
##   watch  — on a Minor Nation's or Tribe's land: the province's charted tiles
##   screen — on `counter_spy` at home: the empire-wide kill bonus
##   idle   — at home with no order
##   aboard — a passenger of one of the crown's squadrons

const DUTY_SHADOW: String = "shadow"
const DUTY_WATCH: String = "watch"
const DUTY_SCREEN: String = "screen"
const DUTY_IDLE: String = "idle"
const DUTY_ABOARD: String = "aboard"

const NO_ID: int = -1


## Whole-network snapshot in reading order. `courts` lists every Great Power but
## the reader's own, shadowed or not, so the gap is as legible as the gain.
static func snapshot(
	world: WorldMap, regions: MapRegionTable, faction: int
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var courts: Array[Dictionary] = []
	var screen: Dictionary = {}
	if world == null or regions == null:
		return _empty(rows, courts, screen)
	var shadowed: Dictionary = {}
	for region: int in world.region_count():
		var model: MapModel = world.region(region)
		if model == null:
			continue
		var units: Array = LedgerRows.stored_rows(regions, region)
		for raw: Variant in units:
			var unit := raw as CivilianState
			if unit == null or unit.owner != faction or not SpyRules.is_spy(unit):
				continue
			var row: Dictionary = _row(model, unit, region)
			rows.append(row)
			if String(row["duty"]) == DUTY_SHADOW:
				shadowed[int(row["host"])] = row
		# One spy on counter_spy anywhere covers every owned province, so the
		# first screen found in either chart is the whole reading.
		if screen.is_empty() and SpyRules.screened_owners(model, units).has(faction):
			screen = _screen_of(model, units, faction, region)
	rows.sort_custom(_before)
	for gp: int in FactionCatalog.great_power_ids():
		if gp == faction:
			continue
		var host_row: Dictionary = shadowed.get(gp, {})
		courts.append({
			"faction": gp,
			"name": FactionCatalog.name_of(gp),
			"shadowed": not host_row.is_empty(),
			"province_name": String(host_row.get("province_name", "")),
			"region": int(host_row.get("region", NO_ID)),
			"line": _court_line(gp, host_row),
		})
	return _empty(rows, courts, screen)


## What the crown gets from one spy where it stands.
static func duty_of(model: MapModel, unit: CivilianState) -> String:
	if unit == null:
		return DUTY_IDLE
	if unit.is_embarked():
		return DUTY_ABOARD
	if SpyRules.is_foreign(model, unit):
		var host: int = model.owner_at(unit.tile.x, unit.tile.y)
		return DUTY_SHADOW if FactionCatalog.great_power_ids().has(host) else DUTY_WATCH
	if unit.is_working() and unit.work_action() == SpyRules.WORK_COUNTER:
		return DUTY_SCREEN
	return DUTY_IDLE


## The one word a network row scans for, in the same reading order as the rows.
static func duty_word(duty: String) -> String:
	match duty:
		DUTY_SHADOW:
			return "SHADOW"
		DUTY_SCREEN:
			return "SCREEN"
		DUTY_WATCH:
			return "WATCH"
		DUTY_ABOARD:
			return "ABOARD"
	return "IDLE"


## One sentence for a network row: what this spy is doing for the crown.
static func duty_text(duty: String, host: int, place: String) -> String:
	var owner_name: String = FactionCatalog.name_of(host) if host != NO_ID else ""
	match duty:
		DUTY_SHADOW:
			return "Shadowing %s — +15%% research and her court reports" % owner_name
		DUTY_WATCH:
			return "Watching %s — %s's charted tiles stay visible" % [owner_name, place]
		DUTY_SCREEN:
			return "Counter-espionage at %s — +5%% to kill enemy spies" % place
		DUTY_ABOARD:
			return "Aboard a squadron — no report while she sails"
	return "Idle — no order"


## One line for the head: how many spies, whom they shadow, whether the screen
## is up and how many wait for an order.
static func summary(snapshot_data: Dictionary) -> String:
	var spies: int = int(snapshot_data.get("spies", 0))
	if spies == 0:
		return "No spy answers the crown — train one at the capital."
	var parts: PackedStringArray = [
		count_text(spies),
		"shadowing %d court%s" % [
			int(snapshot_data.get("shadowed", 0)),
			"" if int(snapshot_data.get("shadowed", 0)) == 1 else "s",
		],
	]
	parts.append(screen_word(snapshot_data, false))
	var idle: int = int(snapshot_data.get("idle", 0))
	if idle > 0:
		parts.append("%d idle" % idle)
	return "  ·  ".join(parts)


## The network's count in plain words, the way a heading prints it: "no spies",
## "1 spy", "3 spies". A tally is a heading, not a table column, so it never
## prints "spys" (issue #1303).
static func count_text(spies: int) -> String:
	if spies <= 0:
		return "no spies"
	return "%d %s" % [spies, "spy" if spies == 1 else "spies"]


## The screen's state in the words a heading prints: "no screen", or "up at
## Cádiz" — never a bare "down" (issue #1303). `place` sheds the seat for the
## summary's digest line.
static func screen_word(snapshot_data: Dictionary, place: bool = true) -> String:
	if not bool(snapshot_data.get("screened", false)):
		return "no screen"
	var where: String = String((snapshot_data.get("screen", {}) as Dictionary).get(
		"province_name", ""
	))
	if not place or where.is_empty():
		return "screen up"
	return "up at %s" % where


## The courts reading's own sentence: the gap named, never only the gain.
static func courts_note(snapshot_data: Dictionary) -> String:
	var courts: Array = snapshot_data.get("courts", [])
	if courts.is_empty():
		return "No rival Great Power is left to shadow."
	var open: int = int(snapshot_data.get("unobserved", 0))
	if open == 0:
		return "Every Great Power is shadowed — the college takes +15%% on each."
	return (
		"%d of %d Great Powers shadowed. A spy on an unshadowed court's land adds "
		+ "+15%% to every slot studying an advance she already knows."
	) % [courts.size() - open, courts.size()]


## The screen's own sentence: up and where, or how a crown raises it.
static func screen_text(snapshot_data: Dictionary) -> String:
	if not bool(snapshot_data.get("screened", false)):
		return (
			"No counter-espionage screen — a spy on `counter_spy` in an owned "
			+ "province raises it for the whole empire."
		)
	var where: String = String((snapshot_data.get("screen", {}) as Dictionary).get(
		"province_name", ""
	))
	return (
		"Screen up at %s — +5%% to kill enemy spies in your own land, and 10%% a "
		+ "turn for a survivor to defect."
	) % where


## What one shadowed court is worth, in the college's own terms.
static func boost_note() -> String:
	return (
		"Each shadowed court adds %d%% research points to slots studying an "
		+ "advance she already knows."
	) % SpyNetworks.BOOST_PERCENT


## What a shadow abroad costs when it is caught (wiki: civilian-units § Spy (3),
## diplomacy § Spy-death penalty): a host's counter-espionage screen takes a
## shadow on 5% a turn, turns a survivor on 10%, and every catch cools the pair's
## relations by 8. The figures are `SpyRules`' own constants — the ones
## `resolve_turn` rolls and the map adapter charges — so the sheet cannot name a
## price the rules do not pay. A reading: no spy is moved, caught or turned.
static func catch_note() -> String:
	return (
		"A host's screen catches a shadow on %d%% a turn and turns a survivor on "
		+ "%d%% — every catch costs −%d with that court."
	) % [SpyRules.KILL_PCT, SpyRules.DEFECT_PCT, int(SpyRules.KILL_RELATION_PENALTY)]


# --- rows -------------------------------------------------------------------


static func _row(model: MapModel, unit: CivilianState, region: int) -> Dictionary:
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	var host: int = model.owner_at(unit.tile.x, unit.tile.y)
	var place: String = "Open country"
	if province != MapModel.NO_ID:
		place = model.province_name(province)
	var duty: String = duty_of(model, unit)
	return {
		"unit_id": unit.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"province_id": province,
		"province_name": place,
		"host": host,
		"host_name": FactionCatalog.name_of(host) if host != NO_ID else "",
		"duty": duty,
		"duty_text": duty_text(duty, host, place),
		"tile": unit.tile,
	}


static func _court_line(gp: int, host_row: Dictionary) -> String:
	if host_row.is_empty():
		return "Unobserved — a spy on her land adds +15% to the college"
	return "Shadowed in %s — +15%% research and her court reports" % String(
		host_row.get("province_name", "")
	)


## The spy that holds the screen: the first `counter_spy` order at home, which
## is the same order `SpyRules.screened_owners` counts.
static func _screen_of(
	model: MapModel, units: Array, faction: int, region: int
) -> Dictionary:
	for raw: Variant in units:
		var unit := raw as CivilianState
		if unit == null or unit.owner != faction or not SpyRules.is_spy(unit):
			continue
		if not unit.is_working() or unit.work_action() != SpyRules.WORK_COUNTER:
			continue
		if model.owner_at(unit.tile.x, unit.tile.y) != faction:
			continue
		var province: int = model.province_at(unit.tile.x, unit.tile.y)
		var place: String = "Open country"
		if province != MapModel.NO_ID:
			place = model.province_name(province)
		return {
			"unit_id": unit.id,
			"region": region,
			"province_name": place,
		}
	return {}


# --- assembly ---------------------------------------------------------------


static func _empty(
	rows: Array[Dictionary], courts: Array[Dictionary], screen: Dictionary
) -> Dictionary:
	var counts: Dictionary = {
		"spies": rows.size(),
		"shadowed": 0,
		"watched": 0,
		"screened": false,
		"idle": 0,
		"aboard": 0,
		"unobserved": 0,
	}
	for row: Dictionary in rows:
		match String(row["duty"]):
			DUTY_SHADOW:
				counts["shadowed"] = int(counts["shadowed"]) + 1
			DUTY_WATCH:
				counts["watched"] = int(counts["watched"]) + 1
			DUTY_IDLE:
				counts["idle"] = int(counts["idle"]) + 1
			DUTY_ABOARD:
				counts["aboard"] = int(counts["aboard"]) + 1
	for court: Dictionary in courts:
		if not bool(court["shadowed"]):
			counts["unobserved"] = int(counts["unobserved"]) + 1
	counts["screened"] = not screen.is_empty()
	var result: Dictionary = counts.duplicate()
	result["rows"] = rows
	result["courts"] = courts
	result["screen"] = screen
	return result


## Shadowed spies first (the crown reads its gains), then the screen, the
## watches, the idle and the passengers; inside a duty the chart's own order.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	var left: int = _duty_rank(String(a["duty"]))
	var right: int = _duty_rank(String(b["duty"]))
	if left != right:
		return left < right
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	var left_place: String = String(a["province_name"])
	var right_place: String = String(b["province_name"])
	if left_place != right_place:
		return left_place < right_place
	return int(a["unit_id"]) < int(b["unit_id"])


static func _duty_rank(duty: String) -> int:
	match duty:
		DUTY_SHADOW:
			return 0
		DUTY_SCREEN:
			return 1
		DUTY_WATCH:
			return 2
		DUTY_IDLE:
			return 3
	return 4
