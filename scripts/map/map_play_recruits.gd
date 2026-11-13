class_name MapPlayRecruits
extends RefCounted
## Build/work for the crown's queued recruits: the worker orders first, then the
## civilian hires, the regiment musters and the hull launches, so a trained
## worker can fund the labour a build needs (wiki: workers-and-population
## § Phase placement). Rules stay in [PlayerEconomy], [ArmyTraining], [FleetYard]
## and [CivilianCatalog]; this pass only runs them in order and files the news
## (REQ-P3-02).
##
## Each order was validated when it was placed; the rules are asked again here,
## because the turn that resolved may have spent the treasury, lost the capital
## or filled the mustering tile. A refused order is spoken and then dropped, so
## the queue never keeps a promise the crown can no longer keep.


## Resolves every waiting order and returns the Build/work records the gazette
## prints (worker, civilian, regiment, ship), in the order they landed.
static func complete(play: PlaySession) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	if play == null or play.economy == null or play.economy.economy == null:
		return done
	if play.army_layer == null or play.ship_layer == null or play.civilian_layer == null:
		return done
	var economy: PlayerEconomy = play.economy.economy
	var queued: Array[Dictionary] = economy.recruits.take_all()
	if queued.is_empty():
		return done
	for row: Dictionary in queued:
		var kind: String = String(row.get("kind", ""))
		if kind != RecruitQueue.KIND_WORKER:
			continue
		var worker: Dictionary = _worker(play, int(String(row.get("key", "-1"))))
		if not worker.is_empty():
			done.append(worker)
	for row: Dictionary in queued:
		var rec: Dictionary = {}
		match String(row.get("kind", "")):
			RecruitQueue.KIND_CIVILIAN:
				rec = _civilian(play, String(row.get("key", "")))
			RecruitQueue.KIND_REGIMENT:
				rec = _regiment(play, String(row.get("key", "")))
			RecruitQueue.KIND_SHIP:
				rec = _ship(play, String(row.get("key", "")))
		if not rec.is_empty():
			done.append(rec)
	_refresh(play)
	return done


## One `RecruitWorkerOrder`: the ledger pays and the pool gains its worker.
static func _worker(play: PlaySession, tier: int) -> Dictionary:
	var economy: PlayerEconomy = play.economy.economy
	var result: Dictionary = economy.recruit(tier)
	if not bool(result.get("ok", false)):
		return _refuse(play, WorkerPool.tier_one(tier), String(result.get("reason", "")))
	return {"kind": "workerRecruited", "label": WorkerPool.tier_one(tier)}


## One civilian `BuildUnitOrder`: paper and ducats buy the hire at the capital.
static func _civilian(play: PlaySession, type_id: String) -> Dictionary:
	var result: Dictionary = MapPlayCivilians.settle(play, type_id)
	if not bool(result.get("ok", false)):
		return _refuse(play, CivilianCatalog.display_name(type_id), String(result.get("reason", "")))
	return {
		"kind": "civilianMustered",
		"label": CivilianCatalog.display_name(type_id),
		"place": play.model.province_name(play.capital_province),
	}


## One regiment `BuildUnitOrder`: it musters into the Home Army at the capital,
## under the title the naming table christens it with (DR-20261111-18).
static func _regiment(play: PlaySession, type_id: String) -> Dictionary:
	var result: Dictionary = play.army_layer.recruit(
		play.player_faction, type_id, play.economy.economy
	)
	if not bool(result.get("ok", false)):
		return _refuse(play, RegimentCatalog.display_name(type_id), String(result.get("reason", "")))
	var rec: Dictionary = {"kind": "regimentMustered", "label": RegimentCatalog.display_name(type_id)}
	var home: ArmyState = ArmyTraining.home_army(
		play.army_layer.armies, play.player_faction
	)
	var title: String = (
		RegimentNames.of(home, String(result.get("regiment", ""))) if home != null else ""
	)
	if not title.is_empty():
		rec["title"] = title
	return rec


## One naval `BuildUnitOrder`: the hull joins the home fleet at the capital port.
static func _ship(play: PlaySession, type_id: String) -> Dictionary:
	var province: int = play.capital_province
	if province < 0 or play.model.province_owner(province) != play.player_faction:
		return _refuse(play, ShipStats.display_name(type_id), "your capital is not in hand")
	if not NavalMovement.has_harbour(play.model, province):
		return _refuse(play, ShipStats.display_name(type_id), "your capital has no harbour")
	var result: Dictionary = play.ship_layer.launch_hull(
		province, type_id, play.economy.economy
	)
	if not bool(result.get("ok", false)):
		return _refuse(play, ShipStats.display_name(type_id), String(result.get("reason", "")))
	return {
		"kind": "shipLaunched",
		"label": ShipStats.display_name(type_id),
		"name": String(result.get("name", "")),
		"place": play.model.province_name(province),
	}


## A promise the turn could not keep: the court hears it and no sheet prints it.
static func _refuse(play: PlaySession, label: String, reason: String) -> Dictionary:
	if play.hud != null:
		var why: String = reason if not reason.is_empty() else "the crown cannot finish it"
		play.hud.toast("%s is not delivered — %s" % [label, why])
	return {}


## The counters the build just moved, so the top bar and the roster agree with
## the ledger before the panel repaints.
static func _refresh(play: PlaySession) -> void:
	if play.hud == null:
		return
	play.hud.set_treasury(play.treasury())
	play.hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	play.hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	play.hud.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
