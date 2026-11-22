class_name AiCoverage
extends RefCounted
## Shipped-rule → order-row coverage checklist (issue #605).
##
## A 200-turn full-AI campaign is the only place a rival's rules are exercised,
## and a rule the court never reaches leaves no trace but the absence of a row:
## a hull never laid, a train never pitched. This module scans the observer's
## per-turn records — the same `MapPlayObserver.snapshot` rows the dashboard and
## the exporter read — and reports every shipped rival rule as exercised or
## never-exercised, with the counts, crowns and turns that prove it, so an
## under-use gap surfaces by scan instead of a forensic run.
##
## Pure and deterministic: records in, rows out, no nodes (REQ-P2-03, REQ-P3-03).

## One shipped rival rule: the trace row that proves a court exercised it.
##
## | field | meaning |
## |-------|---------|
## | `id` | the rule, named as the aim that prices it or the order it issues |
## | `label` | what the row means to a reader |
## | `keys` | `AiTurnLog` action keys the rule bumps when exercised |
## | `aims` | objective-ledger ids that show the rule was requested and funded |
## | `major` | true when never exercising it is a defect, not a quiet option |
## | `gate` | the precondition that can legitimately stop the row (printed) |
## | `source` | the published rule the row speaks for |
const RULES: Array[Dictionary] = [
	{
		"id": "war.declare",
		"label": "declaration of war",
		"keys": ["war"],
		"source": "diplomacy § War",
		"major": true,
	},
	{
		"id": "peace.offer",
		"label": "white peace",
		"keys": ["peace"],
		"source": "diplomacy § Peace",
		"major": true,
	},
	{
		"id": "treaty.overture",
		"label": "alliance and overture",
		"keys": ["treaty"],
		"source": "diplomacy § Treaties",
		"major": true,
	},
	{
		"id": "trade.terms",
		"label": "trade pact, aid, subsidy, boycott",
		"keys": ["trade"],
		"source": "diplomacy § Commercial acts",
		"major": true,
	},
	{
		"id": "army.muster",
		"label": "line regiment raised",
		"keys": ["reinforce"],
		"aims": ["muster.line"],
		"source": "ai-architecture § Land reinforcement",
		"major": true,
	},
	{
		"id": "army.hospital",
		"label": "field hospital train",
		"keys": ["hospital"],
		"source": "combat § Regiment condition (DR-20261112-08)",
		"major": false,
		"gate": "a worn field army on own ground with a working stock (twice the train's price)",
	},
	{
		"id": "land.march",
		"label": "march",
		"keys": ["march"],
		"source": "armies § Movement",
		"major": true,
	},
	{
		"id": "land.assault",
		"label": "assault on a province",
		"keys": ["attack"],
		"source": "armies § Assault",
		"major": true,
	},
	{
		"id": "land.split",
		"label": "army split",
		"keys": ["split"],
		"source": "armies § Detachment",
		"major": false,
	},
	{
		"id": "navy.sortie",
		"label": "sortie",
		"keys": ["sortie"],
		"source": "ai-architecture § Naval policy (DR-20261109-17)",
		# The sortie's own gate, measured on the seed-1500 batch (issue #1357):
		# a port squadron must hold a warship, be at war, and have a hostile
		# squadron in water it can sortie into. The batch never meets it — the
		# opening raids and battles take every court's hulls by t20 and the
		# frozen pool rebuilds none — so the row names the gate that held every
		# court instead of failing the checklist.
		"major": false,
		"gate": "a port squadron holding a warship, at war, with a hostile squadron in water it can reach",
	},
	{
		"id": "navy.pursue",
		"label": "pursuit",
		"keys": ["pursue"],
		"source": "ai-architecture § Naval policy (DR-20261110-21)",
		"major": true,
	},
	{
		"id": "navy.home",
		"label": "sail home, trade garrison",
		"keys": ["home"],
		"source": "ai-architecture § Naval policy (DR-20261114-08)",
		# The homeward leg's own gate, measured on the seed-1500 batch (issue
		# #1357): a squadron must be afloat with a harbour to reach — at peace,
		# or a court at war keeping no holds in port at its seat. The batch
		# never has one: the opening raids and battles take every court's hulls
		# by t20 and the frozen pool rebuilds none, so nothing is afloat to
		# bring home. The row names that gate instead of failing the checklist.
		"major": false,
		"gate": "a squadron afloat with a harbour to reach (at peace, or a court at war keeping no holds in port at its seat)",
	},
	{
		"id": "navy.convoy",
		"label": "convoy sail",
		"keys": ["convoy"],
		"source": "economy-planner § Cargo, ships-and-naval § Ship Types (issue #1258)",
		"major": false,
	},
	{
		"id": "navy.launch",
		"label": "hull laid down at the yard",
		"keys": ["build"],
		"aims": ["navy.build"],
		"source": "ships-and-naval § Ship build economy (issue #484)",
		"major": true,
	},
	{
		"id": "cargo.route",
		"label": "cargo route and merchant hull",
		"keys": ["cargo"],
		"source": "economy-planner § Cargo (DR-20261110-26)",
		"major": true,
	},
	{
		"id": "colonise.voyage",
		"label": "colonisation voyage",
		"keys": ["voyage"],
		"aims": ["expedition.voyage"],
		"source": "ai-architecture § Colonisation voyages",
		"major": true,
	},
	{
		"id": "colonise.land",
		"label": "colony landing",
		"keys": ["colony"],
		"source": "ai-architecture § Colonisation voyages",
		"major": true,
	},
	{
		"id": "invade.landing",
		"label": "overseas landing",
		"keys": ["invade"],
		"source": "ai-architecture § Overseas invasions (DR-20261114-03)",
		"major": true,
	},
	{
		"id": "economy.production",
		"label": "production run",
		"keys": ["production"],
		"source": "economy § Production",
		"major": true,
	},
	{
		"id": "economy.work",
		"label": "civilian work order",
		"keys": ["work"],
		"source": "improvements § Works",
		"major": true,
	},
	{
		"id": "civilian.hire",
		"label": "worker hired",
		"keys": ["recruit"],
		"source": "civilians § Workforce",
		"major": false,
	},
	{
		"id": "civilian.train",
		"label": "civilian mustered",
		"keys": ["train"],
		"source": "civilians § Muster",
		"major": true,
	},
]


## One row per shipped rule, read from the run's per-turn observer records.
## Empty records give every rule a zero reading rather than an empty list, so a
## caller always prints the whole checklist.
static func scan(records: Array[Dictionary]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for rule: Dictionary in RULES:
		rows.append(_read(rule, records))
	return rows


## Merges a run's rows into `into` (a scan's own rows), so a multi-run harness
## reports one checklist. Counts and crowns add, turns span.
static func merge(into: Array[Dictionary], rows: Array[Dictionary]) -> void:
	for index in mini(into.size(), rows.size()):
		var target: Dictionary = into[index]
		var source: Dictionary = rows[index]
		target["count"] = int(target["count"]) + int(source["count"])
		target["runs"] = int(target["runs"]) + int(source["runs"])
		for raw: Variant in source.get("courts", []) as Array:
			var faction: int = int(raw)
			if not (target["courts"] as Array).has(faction):
				(target["courts"] as Array).append(faction)
		var first: int = int(source["first"])
		if first >= 0:
			target["first"] = first if int(target["first"]) < 0 else mini(int(target["first"]), first)
			target["last"] = maxi(int(target["last"]), int(source["last"]))
		target["aims_ranked"] = int(target["aims_ranked"]) + int(source["aims_ranked"])
		target["aims_funded"] = int(target["aims_funded"]) + int(source["aims_funded"])


## Rules that a major reading was never exercised for: the defect list the
## harness fails on. A policy-gated row (`major = false`) stays out of it.
static func missing_major(rows: Array[Dictionary]) -> Array[String]:
	var missing: Array[String] = []
	for row: Dictionary in rows:
		if bool(row["major"]) and int(row["count"]) <= 0:
			missing.append(String(row["id"]))
	return missing


## Rules whose aim was ranked but never funded — the under-use the run proves
## rather than infers (a funded aim that never issued an order is the same
## defect one step later, and reads in the row's counts).
static func starved(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		if int(row["aims_ranked"]) > 0 and int(row["aims_funded"]) <= 0:
			out.append(String(row["id"]))
	return out


## The checklist as the harness prints it, one line per rule.
static func report(rows: Array[Dictionary]) -> String:
	var lines: PackedStringArray = ["", "COVERAGE — shipped rule → order row"]
	lines.append("%-6s %-17s %-11s %6s %7s  %s" % ["", "rule", "row", "count", "crowns", "window"])
	for row: Dictionary in rows:
		lines.append(line(row))
	var missing: Array[String] = missing_major(rows)
	lines.append(
		"Exercised %d of %d · never-exercised major %d%s"
		% [
			rows.size() - _never(rows), rows.size(), missing.size(),
			"" if missing.is_empty() else ": " + ", ".join(missing),
		]
	)
	var starved: Array[String] = starved(rows)
	if not starved.is_empty():
		lines.append("Ranked but never funded: " + ", ".join(starved))
	return "\n".join(lines)


## One checklist line: verdict, rule, its order keys, count, crowns, window, and
## the gate or aim reading that explains a zero.
static func line(row: Dictionary) -> String:
	var count: int = int(row["count"])
	var verdict: String = "ok" if count > 0 else ("never" if bool(row["major"]) else "gated")
	var window: String = "—"
	if int(row["first"]) >= 0:
		window = "t%d..t%d" % [int(row["first"]), int(row["last"])]
	var note: String = String(row.get("gate", ""))
	if int(row["aims_ranked"]) > 0:
		note = "aim ranked %d, funded %d" % [
			int(row["aims_ranked"]), int(row["aims_funded"]),
		]
	return "%-6s %-17s %-11s %6d %5d/%d  %-11s %s" % [
		verdict, String(row["id"]), ",".join(row["keys"] as Array), count,
		(row["courts"] as Array).size(), 6, window, note,
	]


static func _never(rows: Array[Dictionary]) -> int:
	var total: int = 0
	for row: Dictionary in rows:
		if int(row["count"]) <= 0:
			total += 1
	return total


## One rule's reading across the run's records: how often its order rows fired,
## which crowns issued them, the turn window, and what the ledger said about its
## aim.
static func _read(rule: Dictionary, records: Array[Dictionary]) -> Dictionary:
	var row: Dictionary = {
		"id": String(rule["id"]),
		"label": String(rule["label"]),
		"keys": (rule["keys"] as Array).duplicate(),
		"source": String(rule["source"]),
		"major": bool(rule["major"]),
		"gate": String(rule.get("gate", "")),
		"count": 0,
		"runs": 0,
		"courts": [],
		"first": -1,
		"last": -1,
		"aims_ranked": 0,
		"aims_funded": 0,
	}
	row["runs"] = records.size()
	var keys: Array = rule["keys"]
	var aims: Array = rule.get("aims", [])
	for record: Dictionary in records:
		var turn: int = int(record.get("turn", 0))
		for raw: Variant in record.get("rows", []) as Array:
			var court: Dictionary = raw
			# A fallen crown exercises nothing: its rows are dropped, so a dead
			# court cannot make a rule read as exercised (issue #1136). A row
			# with no `alive` reading (an older exporter, a thin fixture) reads
			# as a living court — only an explicit false drops it.
			if not bool(court.get("alive", true)):
				continue
			var actions: Dictionary = (court.get("last", {}) as Dictionary).get("actions", {})
			var fired: int = 0
			for key: Variant in keys:
				fired += int(actions.get(String(key), 0))
			_count_aims(row, court, aims)
			if fired <= 0:
				continue
			row["count"] = int(row["count"]) + fired
			var faction: int = int(court.get("faction", -1))
			if faction >= 0 and not (row["courts"] as Array).has(faction):
				(row["courts"] as Array).append(faction)
			if int(row["first"]) < 0:
				row["first"] = turn
			row["last"] = turn
	return row


## The ledger's word on a rule's aim: how often it was ranked and how often the
## allocation funded it. Absent aims change nothing.
static func _count_aims(row: Dictionary, court: Dictionary, aims: Array) -> void:
	if aims.is_empty():
		return
	var ledger: Dictionary = (court.get("last", {}) as Dictionary).get("objectives", {})
	for raw: Variant in ledger.get("rows", []) as Array:
		var aim: Dictionary = raw
		if not aims.has(String(aim.get("id", ""))):
			continue
		row["aims_ranked"] = int(row["aims_ranked"]) + 1
		if String(aim.get("status", "")) == AiObjective.STATUS_FUNDED:
			row["aims_funded"] = int(row["aims_funded"]) + 1
