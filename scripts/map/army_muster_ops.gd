class_name ArmyMusterOps
extends RefCounted
## Home-army muster mutations for the chart: split, dismiss, combine and recruit.
## Kept out of `ArmyLayer` so the layer stays orders, markers and signals
## (REQ-P3-01; wiki: military-armies). Mirrors ShipYardOps for the yard.


## Detaches regiment instances into a new field army (wiki: military-armies).
static func split(
	layer: ArmyLayer, army: ArmyState, regiment_ids: Array[String]
) -> Dictionary:
	if layer == null:
		return {"ok": false, "reason": "No chart."}
	var result: Dictionary = ArmyRoster.split(
		layer.armies, army, regiment_ids, layer.next_army
	)
	if not bool(result.get("ok", false)):
		return result
	layer.next_army += 1
	## The detach is part of the crown's muster: it reaches the chart's own
	## roster before any reading or save copies it (wiki: campaign-persistence).
	ArmyTransport.publish(layer)
	layer.prune_markers()
	var created: ArmyState = result["army"] as ArmyState
	layer.add_marker(created)
	layer.place_all()
	return result


## Dismisses a batch of regiments from an own army (wiki: military-armies
## § Dismissing regiments; DR-20261109-01). Each returns one peasant; an emptied
## field army retires at once and its standard leaves the chart, while the Home
## Army keeps its standard.
static func dismiss(
	layer: ArmyLayer, army: ArmyState, regiment_ids: Array[String], economy: PlayerEconomy
) -> Dictionary:
	if layer == null:
		return {"ok": false, "reason": "No chart.", "retired": false}
	var result: Dictionary = ArmyDismiss.dismiss(economy, army, regiment_ids)
	if not bool(result.get("ok", false)):
		return result
	if bool(result.get("retired", false)):
		layer.armies.erase(army)
		ArmyTransport.publish(layer)
		layer.prune_markers()
		return result
	layer.refresh_marker(army)
	layer.place_all()
	return result


## Combines the selected army with friendly armies in its province. The Home
## Army wins the merge target when it is in the group (wiki: military-armies).
static func combine(layer: ArmyLayer, army: ArmyState) -> Dictionary:
	if layer == null or army == null:
		return {"ok": false, "reason": "There is no army to combine."}
	var selected: Array[ArmyState] = [army]
	for other: ArmyState in layer.armies:
		if other != army and other.province == army.province and other.owner == army.owner:
			selected.append(other)
	var before: Array[ArmyState] = selected.duplicate()
	var result: Dictionary = ArmyRoster.combine(layer.armies, selected)
	if not bool(result.get("ok", false)):
		return result
	ArmyTransport.publish(layer)
	for old: ArmyState in before:
		if layer.armies.has(old):
			continue
		layer.remove_marker(old)
	layer.place_all()
	return result


## Musters one regiment into the faction's Home Army, keeping the marker in step.
## `roster` names the chart's army list the seat's Home Army lives on: the
## Build/work pass hands over the seat's own chart, so a crown watching a colony
## when the turn closes still musters at its capital (wiki:
## capital-and-connectivity § Capital; world-model-identity). Empty reads the
## chart on screen.
static func recruit(
	layer: ArmyLayer, owner: int, type_id: String, economy: PlayerEconomy, roster: Array = []
) -> Dictionary:
	if layer == null:
		return {
			"ok": false,
			"reason": "No chart.",
			"type": "",
			"regiment": "",
		}
	var seat: Array = layer.armies if roster.is_empty() else roster
	var home: ArmyState = ArmyTraining.home_army(seat, owner)
	if home == null:
		return {
			"ok": false,
			"reason": "The Home Army musters at your capital.",
			"type": "",
			"regiment": "",
		}
	var unit_id: String = "unit_%d" % layer.next_regiment
	var result: Dictionary = ArmyTraining.recruit(economy, home, type_id, unit_id)
	if not bool(result.get("ok", false)):
		return result
	layer.next_regiment += 1
	# A standard on another chart has no marker here; only the chart's own
	# roster repaints (map-topology § two regions).
	if layer.armies.has(home):
		layer.refresh_marker(home)
		layer.place_all()
	return result
