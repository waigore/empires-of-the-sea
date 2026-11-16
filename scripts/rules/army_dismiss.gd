class_name ArmyDismiss
extends RefCounted
## Dismissing land regiments (wiki: military-armies § Dismissing regiments and the
## docket; DR-20261109-01). Rules only, so the order resolves headless
## (REQ-P3-03): each dismissed regiment returns **exactly one peasant** to the
## pool and nothing else is refunded, and an emptied **field army** retires at
## once while the **Home Army** keeps its standard.
##
## The view arms one batched order and reports it; this module never touches a
## node (REQ-P3-02). The breaker's yard is the sea's counterpart
## (`FleetYard.scrap`), and the two return the same one peasant.

## Peasants a dismissal returns to the pool: the one the muster took
## (wiki: military-units § Paying the muster; RegimentEconomy.WORKER_COST).
const PEASANTS_PER_REGIMENT: int = RegimentEconomy.WORKER_COST


## Empty string when the order may be filed; otherwise the first reason the
## rules refuse it. The view and the order path read this one gate
## (REQ-P2-03), so a button can never offer what the ledger would refuse.
static func blocked_reason(
	economy: PlayerEconomy, army: ArmyState, regiment_ids: Array[String]
) -> String:
	if army == null:
		return "There is no army to dismiss from."
	if regiment_ids.is_empty():
		return "No regiment was named."
	for regiment_id: String in regiment_ids:
		if not army.regiments.has(regiment_id):
			return "That regiment does not stand in this army."
	if economy == null:
		return "There is no ledger to return the peasants to."
	return ""


## Applies one batched dismissal. Returns `{ok, reason, count, peasants, names,
## retired}`: `names` are the colours that left, so the court can be told which
## ones (REQ-P5-05), and `retired` says the standard leaves the field because a
## field army was emptied (the Home Army never retires).
static func dismiss(
	economy: PlayerEconomy, army: ArmyState, regiment_ids: Array[String]
) -> Dictionary:
	var reason: String = blocked_reason(economy, army, regiment_ids)
	if not reason.is_empty():
		return _deny(reason)
	var names: Array[String] = []
	## One instance leaves once: a batch that names the same colours twice still
	## returns one peasant for them (wiki: military-armies § Dismissing
	## regiments).
	var seen: Dictionary = {}
	for regiment_id: String in regiment_ids:
		if seen.has(regiment_id):
			continue
		seen[regiment_id] = true
		names.append(RegimentNames.of(army, regiment_id))
		army.remove_regiment(regiment_id)
		economy.workers.add(WorkerPool.Tier.PEASANT, PEASANTS_PER_REGIMENT)
	return {
		"ok": true,
		"reason": "",
		"count": names.size(),
		"peasants": names.size() * PEASANTS_PER_REGIMENT,
		"names": names,
		"retired": army.is_empty() and not army.is_home_army(),
	}


static func _deny(reason: String) -> Dictionary:
	var none: Array[String] = []
	return {
		"ok": false,
		"reason": reason,
		"count": 0,
		"peasants": 0,
		"names": none,
		"retired": false,
	}
