class_name MarketCargo
extends RefCounted
## The cargo afloat: what each crown bought at the turn's clearing, one row per
## buyer and commodity, read by the next turn's raid pass and spent once that
## pass has taken its share (wiki: ships-and-naval § Trade and Transport
## Interception; DR-20261110-13). Pure data so the clearing, the raid pass and
## saves share one book (REQ-P3-03).

## Faction id -> {commodity: units}. A loaded book may key factions by string.
var rows: Dictionary = {}
## True once a per-crown row exists: the explicit rows are then authoritative
## even while empty, so a spent book cannot fall back to the pooled demand an
## older save carried.
var tracked: bool = false


## Books one crown's purchased tonnage. Ids stay one row per buyer, so a rival's
## cargo is never counted as the crown's (DR-20261110-13).
func record(faction: int, commodity: String, quantity: int) -> void:
	if quantity <= 0:
		return
	tracked = true
	var row: Dictionary = _row(faction)
	row[commodity] = int(row.get(commodity, 0)) + quantity


## One crown's own cargo, commodity -> units. Empty when the crown bought
## nothing this turn (or the book has been spent).
func of(faction: int) -> Dictionary:
	var row: Variant = rows.get(faction, rows.get(str(faction), null))
	if row is Dictionary:
		return (row as Dictionary).duplicate()
	return {}


## Every crown with cargo afloat, ascending: the courts a raid can victimise.
func factions() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in rows.keys():
		var row: Dictionary = rows[raw] as Dictionary
		if not row.is_empty():
			out.append(int(raw))
	out.sort()
	return out


## Spends the book: the raid pass has read it, and cargo is not afloat twice.
func close() -> void:
	rows.clear()


func copy() -> MarketCargo:
	var clone := MarketCargo.new()
	clone.rows = rows.duplicate(true)
	clone.tracked = tracked
	return clone


func to_dict() -> Dictionary:
	return rows.duplicate(true)


static func from_dict(data: Dictionary) -> MarketCargo:
	var cargo := MarketCargo.new()
	cargo.rows = data.duplicate(true)
	cargo.tracked = true
	return cargo


## The live row for one crown, created on its first purchase this turn.
func _row(faction: int) -> Dictionary:
	var existing: Variant = rows.get(faction, rows.get(str(faction), null))
	if existing is Dictionary:
		return existing as Dictionary
	var fresh: Dictionary = {}
	rows[faction] = fresh
	return fresh
