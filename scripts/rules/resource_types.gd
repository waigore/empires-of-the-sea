class_name ResourceTypes
extends RefCounted
## A province's estates read by **resource type** rather than tile by tile: the
## emblem kind, how many of that kind are built, how many of those reach the
## crown, and how many the province holds. The survey plate draws one column per
## row and the hover line names the same rows (issue #698).
##
## Pure projection over `ResourceSurvey`'s estate rows — node-free, no autoload,
## no view logic (`REQ-P3-03`).

## One emblem kind per resource type, in the order every plate reads them
## (timber, ore, riches, farm), so two plates never shuffle their columns.
const ORDER: Array[String] = ["tree", "ore", "coin", "wheat"]

## How a type is named in the hover line and the key. The emblem carries the kind
## on the plate; the words only appear where a line has room for them.
const NAMES: Dictionary = {
	"tree": "timber",
	"ore": "ore",
	"coin": "riches",
	"wheat": "farm",
}

## The kinds whose gathered units read as one mass noun, so a count keeps the
## word the key names ("12 timber", "4 ore", "2 riches"): only a farm counts
## estates, so only a farm takes a plural.
const MASS_KINDS: Array[String] = ["tree", "ore", "coin"]


## "1 farm" / "8 farms" / "12 timber": a kind's gathered units in the word form
## the count takes. The one home for the line, so no sheet prints "8 farm"
## (REQ-P1-07, REQ-P3-01).
static func unit_label(kind: String, units: int) -> String:
	var word: String = String(NAMES.get(kind, kind))
	if units != 1 and not MASS_KINDS.has(kind):
		word += "s"
	return "%d %s" % [units, word]


## One row per resource type a province holds. A kind the chart seeds later keeps
## a column of its own after the four the catalogue publishes.
static func rows(entry: Dictionary) -> Array[Dictionary]:
	var by_kind: Dictionary = {}
	var seen: Array[String] = []
	for raw: Variant in entry.get("rows", []):
		var row: Dictionary = raw
		var kind: String = String(row["icon"])
		if not by_kind.has(kind):
			by_kind[kind] = {
				"icon": kind,
				"name": String(NAMES.get(kind, kind)),
				"developed": 0,
				"linked": 0,
				"total": 0,
				"foreign": 0,
				"building": 0,
				"maxed": 0,
			}
			seen.append(kind)
		var tally: Dictionary = by_kind[kind]
		tally["total"] = int(tally["total"]) + 1
		if bool(row["ours"]):
			# Developed and linked stay the crown's own facts: a foreign estate
			# is never "linked to our capital", however worked it looks.
			if int(row["level"]) > 0:
				tally["developed"] = int(tally["developed"]) + 1
				if bool(row["connected"]):
					tally["linked"] = int(tally["linked"]) + 1
		else:
			tally["foreign"] = int(tally["foreign"]) + 1
		match String(row["status"]):
			"building", "foreign_building":
				tally["building"] = int(tally["building"]) + 1
			"maxed":
				tally["maxed"] = int(tally["maxed"]) + 1
	var types: Array[Dictionary] = [] as Array[Dictionary]
	for known: String in ORDER:
		if by_kind.has(known):
			types.append(_finish(by_kind[known]))
	for kind: String in seen:
		if not ORDER.has(kind):
			types.append(_finish(by_kind[kind]))
	return types


## Built, linked, held — the three counts one type's badge carries, in the order
## the plate reads them left to right.
static func badge(developed: int, linked: int, total: int) -> String:
	return "%d/%d/%d" % [developed, linked, total]


## One type's reading: its badge and the status its emblem's ring carries. The
## ring speaks the province vocabulary the key names — a foreign holding, work
## under way, vacant ground, a cut estate, a paying one — so a type reads its
## estate state before its numbers are counted.
static func _finish(tally: Dictionary) -> Dictionary:
	var total: int = int(tally["total"])
	var developed: int = int(tally["developed"])
	var linked: int = int(tally["linked"])
	var status: String = "producing"
	if int(tally["foreign"]) >= total:
		status = "foreign"
	elif int(tally["building"]) > 0:
		status = "building"
	elif developed <= 0:
		status = "vacant"
	elif linked < developed:
		status = "disconnected"
	elif int(tally["maxed"]) >= developed:
		status = "maxed"
	tally["status"] = status
	tally["badge"] = badge(developed, linked, total)
	return tally
