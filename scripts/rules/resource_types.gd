class_name ResourceTypes
extends RefCounted
## A province's estate rows folded into resource types, for the survey lens
## plate (wiki: extraction-and-improvements § Improvement Naming). A type is the
## catalog category, so every estate of that ground shares one emblem: a lumber
## camp is a wood type, an iron and a coal mine are both mine. Pure projection
## over `ResourceSurvey` rows; the dossier and the lens read the same fold
## (REQ-P3-03).
##
## The plate prints one emblem per type with that type's built / linked / total
## badge, so no estate is dropped from the slip the way a seal cap drops them.


## One group per resource type, the type holding most estates first. Every row
## lands in exactly one group, so the counts always add up to the row count.
static func aggregate(rows: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for row: Dictionary in rows:
		var category: String = ImprovementCatalog.category(int(row["resource"]))
		var group: Dictionary = groups.get(category, {
			"category": category,
			"icon": String(row["icon"]),
			"estates": 0,
			"developed": 0,
			"linked": 0,
			"foreign": 0,
			"building": false,
		})
		group["estates"] = int(group["estates"]) + 1
		var ours: bool = bool(row["ours"])
		if not ours:
			group["foreign"] = int(group["foreign"]) + 1
		# Developed and linked are the crown's own facts, exactly as the province
		# counts them: a rival's worked estate is never linked to our capital.
		if ours and int(row["level"]) > 0:
			group["developed"] = int(group["developed"]) + 1
			if bool(row["connected"]):
				group["linked"] = int(group["linked"]) + 1
		var status: String = String(row["status"])
		group["building"] = bool(group["building"]) or status.ends_with("building")
		groups[category] = group
	var types: Array[Dictionary] = [] as Array[Dictionary]
	for category: Variant in groups:
		types.append(groups[category])
	types.sort_custom(_most_estates_first)
	return types


static func _most_estates_first(a: Dictionary, b: Dictionary) -> bool:
	var ea: int = int(a["estates"])
	var eb: int = int(b["estates"])
	if ea != eb:
		return ea > eb
	return String(a["category"]) < String(b["category"])
