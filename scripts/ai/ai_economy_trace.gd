class_name AiEconomyTrace
extends RefCounted
## The rival economy pass's turn-trace rows: what a court produced, recruited,
## ordered, routed, launched and reserved this turn, read from the economy
## report the court hands in (wiki: turn-trace-interpretation). Pure translation:
## the merged record and its event cap belong to AiTurnLog, so this module only
## turns one report into that record's rows (REQ-P3-01).


## Writes one court's economy rows into the merged turn record: production runs,
## recruits, civilian work and training, then the cargo routes and the court's
## reservations.
static func record(merged: Dictionary, factions: Dictionary, report: Dictionary) -> void:
	var per: Dictionary = report.get("factions", {})
	for raw: Variant in per.keys():
		var faction: int = int(raw)
		if not factions.has(faction):
			continue
		var details: Dictionary = per[raw]
		var bucket: Dictionary = factions[faction]
		var assignments: Array = (details.get("production", {}) as Dictionary).get(
			"assignments", []
		)
		var recruits: Array = details.get("recruits", [])
		var civilians: Dictionary = details.get("civilians", {})
		var orders: Array = civilians.get("orders", [])
		var training: Array = civilians.get("training", [])
		var who: String = FactionCatalog.name_of(faction)
		if not assignments.is_empty():
			AiTurnLog.bump(bucket["actions"], "production")
			AiTurnLog.event(merged, bucket, faction, "%s sets %d production runs." % [
				who, assignments.size(),
			])
		if not recruits.is_empty():
			AiTurnLog.bump(bucket["actions"], "recruit", recruits.size())
			AiTurnLog.event(merged, bucket, faction, "%s trains %d workers." % [
				who, recruits.size(),
			])
		if not orders.is_empty():
			AiTurnLog.bump(bucket["actions"], "work", orders.size())
			AiTurnLog.event(merged, bucket, faction, "%s's civilians take %d work orders." % [
				who, orders.size(),
			])
		if not training.is_empty():
			AiTurnLog.bump(bucket["actions"], "train")
			AiTurnLog.event(merged, bucket, faction, "%s musters a civilian." % who)
		var held: String = String(civilians.get("training_blocked", ""))
		if not held.is_empty():
			# The footing held the hire shut: the court's yard says why it took
			# no crew rather than going quiet (REQ-P5-05; DR-20261116-15).
			AiTurnLog.event(
				merged, bucket, faction, "%s hires no new crew (%s)." % [who, held]
			)
		var bids: String = String((details.get("trade", {}) as Dictionary).get(
			"bids_blocked", ""
		))
		if not bids.is_empty():
			# The footing held the speculative bid shut: the market says why the
			# court bought nothing above its commitments (REQ-P5-05;
			# DR-20261117-01).
			AiTurnLog.event(
				merged, bucket, faction, "%s opens no speculative bid (%s)." % [who, bids]
			)
		_cargo(merged, bucket, faction, details.get("cargo", {}))
		_claims(bucket, details.get("claims", []))


## Every reservation the court claimed this turn — rations, the muster's row,
## the works, this turn's production — with what it was granted, so the trace
## shows the same floor every spender left (issue #491 T3).
static func _claims(bucket: Dictionary, lines: Variant) -> void:
	if typeof(lines) != TYPE_ARRAY or (lines as Array).is_empty():
		return
	bucket["claims"] = (lines as Array).duplicate()


## Cargo routes and a new hull from the yard: the colonies' left tonnage and the
## court's trade holds explain why a rival moves or builds merchant hulls
## (wiki: economy-planner § Cargo; DR-20261110-26).
static func _cargo(
	merged: Dictionary, bucket: Dictionary, faction: int, cargo: Dictionary
) -> void:
	var routes: Array = cargo.get("routes", [])
	var launch: Dictionary = cargo.get("launch", {})
	var warship: Dictionary = cargo.get("warship", {})
	# A fleet launch with no merchant routes must still print — the early empty
	# guard used to drop the yard event entirely (issue #484).
	if routes.is_empty() and launch.is_empty() and warship.is_empty():
		return
	var who: String = FactionCatalog.name_of(faction)
	if not routes.is_empty():
		AiTurnLog.bump(bucket["actions"], "cargo", routes.size())
		AiTurnLog.event(merged, bucket, faction, "%s routes %d merchant squadron%s home." % [
			who, routes.size(), "" if routes.size() == 1 else "s",
		])
	if not launch.is_empty():
		AiTurnLog.bump(bucket["actions"], "cargo")
		AiTurnLog.event(merged, bucket, faction, "%s lays down a %s for the cargo trade." % [
			who, ShipStats.display_name(String(launch.get("type_id", ""))),
		])
	if not warship.is_empty():
		AiTurnLog.bump(bucket["actions"], "build")
		# The row names the yard's price and the chest that allowed the launch,
		# so the trace explains the build itself (issue #484).
		AiTurnLog.event(merged, bucket, faction, "%s lays down a %s for the fleet: %d ducats against a %d chest." % [
			who, ShipStats.display_name(String(warship.get("type_id", ""))),
			int(warship.get("price", 0)), int(warship.get("chest", 0)),
		])
